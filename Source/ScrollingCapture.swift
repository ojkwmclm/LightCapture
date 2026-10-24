import AppKit
import ApplicationServices

enum ScrollPacing {
    static let normalDelay=0.22
    static let retryDelay=0.6
    static func step(height:CGFloat)->Int32 {Int32(max(20,min(760,height*0.62)))}
}

// Pixel coordinates use a top-left origin throughout registration and stitching.
struct ScrollFrame {
    let image:CGImage
    let width:Int
    let height:Int
    let pixels:[UInt8]
    init(_ image:CGImage) throws {
        let width=image.width,height=image.height
        self.image=image;self.width=width;self.height=height
        guard width>0,height>0,width*height<=60_000_000 else{throw ScrollCaptureError.invalidImage}
        var data=[UInt8](repeating:0,count:width*height*4)
        let ok=data.withUnsafeMutableBytes { bytes -> Bool in
            guard let c=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
            c.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard ok else{throw ScrollCaptureError.invalidImage};pixels=data
    }
    func difference(_ next:ScrollFrame,shift:Int)->Double {
        let overlap=height-shift
        guard width==next.width,height==next.height,overlap>=24 else{return .infinity}
        let dx=max(1,width/32),dy=max(1,overlap/32)
        var total=0.0,count=0
        // Ignore scrollbars and narrow edge shadows, not content in the centre.
        for y in stride(from:8,to:overlap-8,by:dy) {
            for x in stride(from:max(2,width/25),to:width-max(2,width/25),by:dx) {
                let a=((y+shift)*width+x)*4,b=(y*width+x)*4
                for channel in 0..<3 {total+=Double(abs(Int(pixels[a+channel])-Int(next.pixels[b+channel])));count+=1}
            }
        }
        return total/Double(max(1,count))
    }
    enum Match:Equatable {case unchanged, moved(Int), uncertain}
    func match(_ next:ScrollFrame)->Match {
        guard width==next.width,height==next.height,height>=80 else{return .uncertain}
        if difference(next,shift:0)<0.8{return .unchanged}
        let maxShift=height*3/4,step=1
        var candidates:[(Int,Double)]=[]
        for shift in stride(from:2,through:maxShift,by:step){candidates.append((shift,difference(next,shift:shift)))}
        guard let coarse=candidates.min(by:{$0.1<$1.1}) else{return .uncertain}
        var best=coarse
        for shift in max(1,coarse.0-step)...min(maxShift,coarse.0+step) {
            let score=difference(next,shift:shift);if score<best.1{best=(shift,score)}
        }
        // Repeated/blank content is ambiguous: preserve what is known rather than guess.
        let alternate=candidates.filter{abs($0.0-best.0)>max(8,height/40)}.map{$0.1}.min() ?? 255
        guard best.1<4.0,alternate>best.1+0.8 else{return .uncertain}
        return .moved(best.0)
    }
}

enum ScrollCaptureError:LocalizedError {
    case invalidImage,capture,changed,limit
    var errorDescription:String? {
        switch self {
        case .invalidImage:return L("无法读取滚动截图画面。")
        case .capture:return L("截图失败，请检查屏幕录制权限。")
        case .changed:return L("无法可靠拼接。请避开固定工具栏、动画或重复内容后重试。")
        case .limit:return L("已达到长图大小上限，已保留当前结果。")
        }
    }
}

struct ScrollStitcher {
    private(set) var previous:ScrollFrame?
    private(set) var strips:[CGImage]=[]
    private(set) var totalHeight=0
    private(set) var count=0
    mutating func append(_ image:CGImage)throws->ScrollFrame.Match {
        let next=try ScrollFrame(image)
        guard let previous else{self.previous=next;strips=[image];totalHeight=image.height;count=1;return .moved(image.height)}
        let match=previous.match(next)
        if case .moved(let delta)=match {
            guard (totalHeight+delta)*image.width<=60_000_000,count<80,totalHeight+delta<=40000 else{throw ScrollCaptureError.limit}
            guard let strip=image.cropping(to:CGRect(x:0,y:image.height-delta,width:image.width,height:delta)) else{throw ScrollCaptureError.invalidImage}
            guard let copy=CGContext(data:nil,width:strip.width,height:strip.height,bitsPerComponent:8,bytesPerRow:0,space:strip.colorSpace ?? CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw ScrollCaptureError.invalidImage}
            copy.draw(strip,in:CGRect(x:0,y:0,width:strip.width,height:strip.height))
            guard let compact=copy.makeImage() else{throw ScrollCaptureError.invalidImage}
            strips.append(compact);totalHeight+=delta;count+=1;self.previous=next
        }
        return match
    }
    func result()->CGImage? {
        guard let first=strips.first,let context=CGContext(data:nil,width:first.width,height:totalHeight,bitsPerComponent:8,bytesPerRow:0,space:first.colorSpace ?? CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
        var top=0
        for strip in strips {
            context.draw(strip,in:CGRect(x:0,y:totalHeight-top-strip.height,width:strip.width,height:strip.height));top+=strip.height
        }
        return context.makeImage()
    }
}

func scrollTargetIsVisible(_ id:CGWindowID,bounds:CGRect,rect:CGRect,windows:[[String:Any]],ownPID:Int32)->Bool {
    guard let target=windows.first(where:{($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value==id}),
          let b=target[kCGWindowBounds as String] as? NSDictionary,let current=CGRect(dictionaryRepresentation:b),current==bounds else{return false}
    for item in windows {
        if (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value==id{return true}
        guard (item[kCGWindowLayer as String] as? Int ?? -1)==0,
              (item[kCGWindowAlpha as String] as? Double ?? 1)>0.01,
              (item[kCGWindowOwnerPID as String] as? Int32) != ownPID,
              let b=item[kCGWindowBounds as String] as? NSDictionary,let frame=CGRect(dictionaryRepresentation:b) else{continue}
        if frame.contains(CGPoint(x:rect.midX,y:rect.midY)){return false}
    }
    return false
}

final class ScrollingCaptureController:NSObject {
    let rect:CGRect
    let completion:(CGImage?,String?)->Void
    let progress=NSTextField(labelWithString:"")
    let controls:NSPanel
    var stitcher=ScrollStitcher()
    var process:Process?
    var scheduled:DispatchWorkItem?
    var finished=false
    var stopRequested=false
    var unchanged=0
    var failedMatches=0
    var settleDelay=ScrollPacing.normalDelay
    var targetIssue=L("目标窗口已变化，已停止并保留当前结果。")
    var target:NSRunningApplication?
    var targetWindow:CGWindowID?
    var targetBounds:CGRect?
    var localMonitor:Any?
    var globalMonitor:Any?
    init(rect:CGRect,completion:@escaping(CGImage?,String?)->Void){
        self.rect=rect;self.completion=completion
        controls=NSPanel(contentRect:NSRect(x:0,y:0,width:330,height:64),styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init()
        controls.title=L("滚动截图");controls.level = .floating;controls.hidesOnDeactivate=false;controls.isReleasedWhenClosed=false
        controls.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let stop=NSButton(title:L("完成"),target:self,action:#selector(stop));stop.bezelStyle = .rounded
        let cancel=NSButton(title:L("取消"),target:self,action:#selector(cancel));cancel.bezelStyle = .rounded
        let row=NSStackView(views:[progress,stop,cancel]);row.spacing=10;row.translatesAutoresizingMaskIntoConstraints=false
        controls.contentView!.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:controls.contentView!.leadingAnchor,constant:12),row.trailingAnchor.constraint(equalTo:controls.contentView!.trailingAnchor,constant:-12),row.centerYAnchor.constraint(equalTo:controls.contentView!.centerYAnchor)])
    }
    func start(){
        let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        if let info=windows.first(where:{ info in
            guard (info[kCGWindowLayer as String] as? Int)==0,let b=info[kCGWindowBounds as String] as? NSDictionary,let bounds=CGRect(dictionaryRepresentation:b),bounds.contains(CGPoint(x:rect.midX,y:rect.midY)) else{return false}
            return (info[kCGWindowOwnerPID as String] as? Int32) != getpid()
        }),let pid=info[kCGWindowOwnerPID as String] as? Int32 {target=NSRunningApplication(processIdentifier:pid);targetWindow=(info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            if let b=info[kCGWindowBounds as String] as? NSDictionary {targetBounds=CGRect(dictionaryRepresentation:b)}
        }
        guard target != nil else{finish(note:L("没有找到可滚动的目标窗口。"));return}
        // Preserve the selected window ordering. Activating an application can
        // raise a different window belonging to the same process.
        let mainTop=NSScreen.screens.first?.frame.maxY ?? 0
        let cocoaRect=NSRect(x:rect.minX,y:mainTop-rect.maxY,width:rect.width,height:rect.height)
        let size=controls.frame.size
        // The controller must stay entirely outside the pixels being captured.
        let candidates=NSScreen.screens.flatMap { screen -> [NSPoint] in
            let v=screen.visibleFrame
            return [NSPoint(x:v.minX,y:v.maxY-size.height),NSPoint(x:v.maxX-size.width,y:v.maxY-size.height),NSPoint(x:v.minX,y:v.minY),NSPoint(x:v.maxX-size.width,y:v.minY)]
        }
        if let origin=candidates.first(where:{!NSRect(origin:$0,size:size).intersects(cocoaRect)}) {
            controls.setFrameOrigin(origin);controls.orderFrontRegardless()
        }
        // The menu-bar stop action remains available when no controller fits outside the selection.
        progress.stringValue=L("准备滚动…")
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] e in if e.keyCode==53{self?.stop();return nil};return e}
        globalMonitor=NSEvent.addGlobalMonitorForEvents(matching:.keyDown){[weak self] e in if e.keyCode==53{self?.stop()}}
        later(0.25){self.captureFrame()}
    }
    func later(_ delay:Double,_ action:@escaping()->Void){
        scheduled?.cancel();let task=DispatchWorkItem{[weak self] in guard self?.finished==false else{return};action()};scheduled=task
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:task)
    }
    func captureFrame(){
        guard !finished else{return}
        guard targetUnchanged() else{finish(note:targetIssue);return}
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture");p.arguments=["-x","-R","\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))",url.path];p.standardError=FileHandle.nullDevice
        process=p
        p.terminationHandler={[weak self] task in DispatchQueue.main.async {
            defer{try? FileManager.default.removeItem(at:url)}
            guard let self,!self.finished else{return};self.process=nil
            guard task.terminationStatus==0,let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{self.finish(note:ScrollCaptureError.capture.localizedDescription);return}
            do {
                let match=try self.stitcher.append(image)
                switch match {
                case .moved:self.unchanged=0;self.failedMatches=0;self.settleDelay=max(ScrollPacing.normalDelay,self.settleDelay*0.8)
                case .unchanged:self.unchanged+=1
                case .uncertain:self.failedMatches+=1;self.settleDelay=min(0.75,max(ScrollPacing.retryDelay,self.settleDelay*1.5))
                }
                self.progress.stringValue=LF("已捕获 %@ 段",self.stitcher.count)
                if self.stopRequested {self.finish();return}
                if self.failedMatches>=2{self.finish(note:ScrollCaptureError.changed.localizedDescription);return}
                if self.unchanged>=3{self.finish();return}
                if match == .uncertain {self.later(self.settleDelay){self.captureFrame()}}else{self.scroll()}
            }catch{self.finish(note:error.localizedDescription)}
        }}
        do{try p.run()}catch{process=nil;finish(note:error.localizedDescription)}
    }
    func scroll(){
        guard !finished else{return}
        guard targetUnchanged() else{finish(note:targetIssue);return}
        if stopRequested{finish();return}
        let center=CGPoint(x:rect.midX,y:rect.midY)
        CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:center,mouseButton:.left)?.post(tap:.cghidEventTap)
        let amount=ScrollPacing.step(height:rect.height)
        let event=CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:-amount,wheel2:0,wheel3:0)
        event?.location=center;event?.post(tap:.cghidEventTap)
        later(settleDelay){self.captureFrame()}
    }
    func targetUnchanged()->Bool {
        guard let target,!target.isTerminated,let targetWindow,let targetBounds else{targetIssue=L("目标窗口已关闭，已停止捕获。");return false}
        let visible=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let valid=scrollTargetIsVisible(targetWindow,bounds:targetBounds,rect:rect,windows:visible,ownPID:getpid())
        if !valid {targetIssue=L("目标窗口已移动或被遮挡，已停止捕获。")}
        return valid
    }
    @objc func stop(){guard !finished else{return};stopRequested=true;if process==nil{scheduled?.cancel();captureFrame()}}
    @objc func cancel(){finish(discard:true)}
    func finish(discard:Bool=false,note:String?=nil){
        guard !finished else{return};finished=true;scheduled?.cancel();scheduled=nil
        if let process,process.isRunning {process.terminate()};process=nil
        if let localMonitor{NSEvent.removeMonitor(localMonitor)};if let globalMonitor{NSEvent.removeMonitor(globalMonitor)}
        localMonitor=nil;globalMonitor=nil;controls.close()
        let result=discard ? nil:stitcher.result();stitcher=ScrollStitcher()
        completion(result,note)
    }
}

extension App {
    @objc func scrollingCapture(){
        if let scrollCapture {scrollCapture.stop();return}
        guard !capturing,!recording,!recordingBusy,NSApp.modalWindow==nil else{return}
        NSApp.activate(ignoringOtherApps:true)
        let alert=NSAlert();alert.messageText=L("滚动截图");alert.informativeText=L("请先将目标内容滚动到起点，再框选可滚动的内容区域，避开固定标题栏和滚动条。开始后请勿移动窗口或操作页面。到底自动完成；也可按 Esc 或点击“完成”保留结果。自动滚动需要辅助功能权限。");alert.addButton(withTitle:L("选择区域…"));alert.addButton(withTitle:L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        guard CGPreflightPostEventAccess() else {
            _=CGRequestPostEventAccess()
            message(L("需要辅助功能权限"),L("请在系统设置 → 隐私与安全性 → 辅助功能中允许轻截，然后重新发起滚动截图。"));return
        }
        let restoreEditor=window.isVisible
        capturing=true;window.orderOut(nil);panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2){[self] in
            guard let rect=RegionView.chooseScreenshot(),rect.width>=100,rect.height>=100 else{self.capturing=false;if restoreEditor{self.showEditor()}else{self.showPanel()};return}
            guard NSScreen.screens.contains(where:{ screen in
                let top=NSScreen.screens.first?.frame.maxY ?? 0
                return CGRect(x:screen.frame.minX,y:top-screen.frame.maxY,width:screen.frame.width,height:screen.frame.height).contains(rect)
            }) else{self.capturing=false;self.showPanel();self.message(L("滚动截图"),L("请在同一显示器内选择截图区域。"));return}
            let controller=ScrollingCaptureController(rect:rect){[weak self] image,note in
                guard let self else{return};self.scrollCapture=nil;self.capturing=false;self.status.button?.image=NSImage(systemSymbolName:"viewfinder",accessibilityDescription:L("轻截"))
                if let image {self.documentName=L("滚动截图");self.canvas.setImage(NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)));self.refreshEditor();self.showEditor()}else if restoreEditor{self.showEditor()}else{self.showPanel()}
                if let note {self.message(L("滚动截图"),note)}
            }
            self.scrollCapture=controller;self.status.button?.image=NSImage(systemSymbolName:"arrow.down.square.fill",accessibilityDescription:L("完成滚动截图"));controller.start()
        }
    }
}

func testScrollStitcher(){
    precondition(ScrollPacing.normalDelay<0.75)
    for height:CGFloat in [100,300,800,1200,3000] {
        let step=CGFloat(ScrollPacing.step(height:height))
        precondition(step<height*0.75 && step>=min(760,height*0.6))
    }
    let width=240,height=1800,viewport=880
    var data=[UInt8](repeating:255,count:width*height*4)
    var random:UInt64=42
    for y in 0..<height {for x in 0..<width {
        random=random &* 6364136223846793005 &+ 1
        let i=(y*width+x)*4
        data[i]=UInt8(truncatingIfNeeded:random>>32);data[i+1]=UInt8(truncatingIfNeeded:random>>40);data[i+2]=UInt8(truncatingIfNeeded:random>>48)
    }}
    let image=data.withUnsafeMutableBytes {bytes in CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!}
    var stitch=ScrollStitcher()
    let offsets=[0,545,707]
    for (index,offset) in offsets.enumerated(){
        let frame=image.cropping(to:CGRect(x:0,y:offset,width:width,height:viewport))!
        let match=try! stitch.append(frame)
        precondition(match == .moved(index==0 ? viewport:offset-offsets[index-1]),"Unexpected alignment: \(match)")
    }
    let last=image.cropping(to:CGRect(x:0,y:707,width:width,height:viewport))!
    precondition(try! stitch.append(last) == .unchanged)
    let result=stitch.result()!
    precondition(result.width==width && result.height==1587)
    let expected=try! ScrollFrame(image.cropping(to:CGRect(x:0,y:0,width:width,height:1587))!)
    let actual=try! ScrollFrame(result)
    precondition(expected.pixels==actual.pixels,"Stitch changed pixels or reversed the image")
    let small=image.cropping(to:CGRect(x:0,y:0,width:100,height:100))!
    precondition(try! stitch.append(small) == .uncertain)
    let unrelated=image.cropping(to:CGRect(x:0,y:0,width:width,height:viewport))!
    precondition(try! stitch.append(unrelated) == .uncertain)
    let targetBounds=CGRect(x:20,y:20,width:500,height:600),captureRect=CGRect(x:50,y:80,width:200,height:300)
    func windowInfo(_ id:Int,_ bounds:CGRect,_ pid:Int32=2)->[String:Any] {
        [kCGWindowNumber as String:NSNumber(value:id),kCGWindowBounds as String:bounds.dictionaryRepresentation,kCGWindowOwnerPID as String:pid,kCGWindowLayer as String:0]
    }
    let target=windowInfo(42,targetBounds),outside=windowInfo(8,CGRect(x:600,y:0,width:60,height:60))
    precondition(scrollTargetIsVisible(42,bounds:targetBounds,rect:captureRect,windows:[outside,target],ownPID:1))
    precondition(!scrollTargetIsVisible(42,bounds:targetBounds,rect:captureRect,windows:[windowInfo(8,captureRect),target],ownPID:1))
    let edgeWindow=windowInfo(10,CGRect(x:40,y:70,width:20,height:20))
    precondition(scrollTargetIsVisible(42,bounds:targetBounds,rect:captureRect,windows:[edgeWindow,target],ownPID:1))
    var overlay=windowInfo(9,captureRect);overlay[kCGWindowLayer as String]=1000
    precondition(scrollTargetIsVisible(42,bounds:targetBounds,rect:captureRect,windows:[overlay,target],ownPID:1))
    overlay[kCGWindowLayer as String]=0;overlay[kCGWindowAlpha as String]=0.0
    precondition(scrollTargetIsVisible(42,bounds:targetBounds,rect:captureRect,windows:[overlay,target],ownPID:1))
    precondition(!scrollTargetIsVisible(42,bounds:targetBounds,rect:captureRect,windows:[outside],ownPID:1))
    precondition(!scrollTargetIsVisible(42,bounds:targetBounds,rect:captureRect,windows:[windowInfo(42,targetBounds.offsetBy(dx:5,dy:0))],ownPID:1))
    var completions=0
    let cancelled=ScrollingCaptureController(rect:CGRect(x:0,y:0,width:200,height:200)){image,note in precondition(image==nil && note==nil);completions+=1}
    cancelled.cancel();cancelled.cancel();precondition(completions==1)
}
