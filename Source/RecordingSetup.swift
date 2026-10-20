import AppKit
import ScreenCaptureKit

enum RecordingMode: Int, CaseIterable {
    case region, window, display
    var title: String { [L("矩形区域"), L("窗口"), L("全屏")][rawValue] }
}

enum RecordingTarget {
    case display(SCDisplay, CGRect?)
    case window(SCWindow)
    var summary: String {
        switch self {
        case .display(let display,let rect):
            if let rect {return LF("区域 %@ × %@ 点",Int(rect.width),Int(rect.height))}
            return L("全屏")+" · "+(display.displayID == CGMainDisplayID() ? L("主显示器") : LF("显示器 %@",display.displayID))
        case .window(let window): return L("窗口")+" · "+(window.owningApplication?.applicationName ?? "")+" · "+(window.title ?? L("无标题"))
        }
    }
}
struct RecordingOptions { let target: RecordingTarget; let url: URL; let audio: RecordingAudio }

enum CaptureSelectionOverlay {
    // A zero-alpha hole lets WindowServer route real clicks to the app underneath.
    // Keep the selection almost clear, but retain a mouse-receiving surface.
    static let selectedFill=NSColor.black.withAlphaComponent(0.03)
}

final class WindowCaptureView:NSView {
    var targets:[CGRect]=[]
    var desktop=CGRect.zero
    var mainTop:CGFloat=0
    var selected:CGRect?
    var finished:((CGRect?)->Void)?
    private var completed=false
    private var hoverTracking:NSTrackingArea?
    override var isFlipped:Bool {true}
    override var acceptsFirstResponder:Bool {true}
    override var mouseDownCanMoveWindow:Bool {false}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.crosshair)}
    override func updateTrackingAreas(){
        if let hoverTracking{removeTrackingArea(hoverTracking)}
        super.updateTrackingAreas()
        let area=NSTrackingArea(rect:bounds,options:[.activeAlways,.mouseMoved,.inVisibleRect],owner:self,userInfo:nil)
        hoverTracking=area;addTrackingArea(area)
    }
    static func target(at point:NSPoint,in targets:[CGRect])->CGRect? {targets.first{$0.contains(point)}}
    func updateSelection(at point:NSPoint){
        let global=NSPoint(x:desktop.minX+point.x,y:mainTop-desktop.maxY+point.y)
        selected=Self.target(at:global,in:targets);needsDisplay=true
    }
    override func mouseMoved(with event:NSEvent){updateSelection(at:convert(event.locationInWindow,from:nil))}
    func finish(_ rect:CGRect?){guard !completed else{return};completed=true;finished?(rect)}
    override func mouseDown(with event:NSEvent){
        guard !completed else{return}
        updateSelection(at:convert(event.locationInWindow,from:nil))
        if let selected{finish(selected.integral)}
    }
    override func rightMouseDown(with event:NSEvent){finish(nil)}
    override func rightMouseDragged(with event:NSEvent){finish(nil)}
    override func rightMouseUp(with event:NSEvent){finish(nil)}
    override func keyDown(with event:NSEvent){if event.keyCode==53{finish(nil)}else{super.keyDown(with:event)}}
    override func draw(_ dirtyRect:NSRect){
        NSColor.black.withAlphaComponent(0.32).setFill();bounds.fill()
        if let selected {
            let rect=CGRect(x:selected.minX-desktop.minX,y:selected.minY-mainTop+desktop.maxY,width:selected.width,height:selected.height).intersection(bounds)
            CaptureSelectionOverlay.selectedFill.setFill();rect.fill(using:.copy)
            NSColor.systemTeal.setStroke();let outline=NSBezierPath(rect:rect.insetBy(dx:1,dy:1));outline.lineWidth=2;outline.stroke()
        }
        let text=L("左键单击窗口截图 · 右键 / Esc 取消")
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:18,weight:.semibold),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black.withAlphaComponent(0.75)]
        text.draw(at:NSPoint(x:max(20,(bounds.width-text.size(withAttributes:attrs).width)/2),y:32),withAttributes:attrs)
    }
    static func choose()->CGRect? {
        guard let first=NSScreen.screens.first else{return nil}
        let desktop=NSScreen.screens.dropFirst().reduce(first.frame){$0.union($1.frame)}
        let windowInfo=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
        let targets=windowInfo.compactMap {info -> CGRect? in
            guard (info[kCGWindowLayer as String] as? Int)==0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1)>0,
                  let bounds=info[kCGWindowBounds as String] as? [String:Any],
                  let rect=CGRect(dictionaryRepresentation:bounds as CFDictionary),rect.width>=16,rect.height>=16 else{return nil}
            return rect
        }
        let panel=RegionPanel(contentRect:desktop,styleMask:.borderless,backing:.buffered,defer:false)
        panel.title=L("选择截图窗口");panel.isOpaque=false;panel.backgroundColor = .clear;panel.level = .screenSaver;panel.isMovable=false;panel.acceptsMouseMovedEvents=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.isReleasedWhenClosed=false
        let view=WindowCaptureView(frame:NSRect(origin:.zero,size:desktop.size));view.targets=targets;view.desktop=desktop;view.mainTop=first.frame.maxY;panel.contentView=view
        let mouse=NSEvent.mouseLocation
        view.updateSelection(at:NSPoint(x:mouse.x-desktop.minX,y:desktop.maxY-mouse.y))
        var selected:CGRect?
        view.finished={rect in selected=rect;NSApp.stopModal(withCode:rect == nil ? .cancel:.OK);panel.orderOut(nil)}
        NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(view)
        NSApp.runModal(for:panel);panel.close();return selected
    }
}

final class RegionPanel: NSPanel {
    override var canBecomeKey: Bool {true}
}
final class RegionView: NSView {
    var prompt=L("拖动选择录制区域 · Esc 取消")
    var confirmationFormat="%@ × %@ 点 · 松开鼠标确认 · Esc 取消"
    var cancelWithRightMouse=false
    var minimumSelectionSize:CGFloat=16
    private var completed=false
    var start: NSPoint?
    var selection: CGRect?
    var finished: ((CGRect?)->Void)?
    override var isFlipped: Bool {true}
    override var acceptsFirstResponder: Bool {true}
    override var mouseDownCanMoveWindow: Bool {false}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool {true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.crosshair)}
    override func draw(_ rect:NSRect){
        NSColor.black.withAlphaComponent(0.32).setFill();bounds.fill()
        if let selection {
            CaptureSelectionOverlay.selectedFill.setFill();selection.fill(using:.copy)
            NSColor.systemTeal.setStroke();let line=NSBezierPath(rect:selection);line.lineWidth=2;line.stroke()
        }
        let text=selection.map{LF(confirmationFormat,Int($0.width),Int($0.height))} ?? prompt
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:18,weight:.semibold),.foregroundColor:NSColor.white,.backgroundColor:NSColor.black.withAlphaComponent(0.75)]
        text.draw(at:NSPoint(x:max(20,(bounds.width-text.size(withAttributes:attrs).width)/2),y:32),withAttributes:attrs)
    }
    override func mouseDown(with event:NSEvent){guard !completed else{return};start=convert(event.locationInWindow,from:nil);selection=nil}
    override func mouseDragged(with event:NSEvent){guard !completed,let start else{return};let p=convert(event.locationInWindow,from:nil);selection=CGRect(x:min(start.x,p.x),y:min(start.y,p.y),width:abs(start.x-p.x),height:abs(start.y-p.y)).intersection(bounds);needsDisplay=true}
    override func mouseUp(with event:NSEvent){guard !completed else{return};guard let selection,selection.width>=minimumSelectionSize,selection.height>=minimumSelectionSize else{start=nil;selection=nil;needsDisplay=true;return};finishSelection(selection.integral)}
    func finishSelection(_ rect:CGRect?) {guard !completed else{return};completed=true;finished?(rect)}
    override func rightMouseDown(with event:NSEvent){if cancelWithRightMouse{finishSelection(nil)}else{super.rightMouseDown(with:event)}}
    override func rightMouseDragged(with event:NSEvent){if cancelWithRightMouse{finishSelection(nil)}else{super.rightMouseDragged(with:event)}}
    override func rightMouseUp(with event:NSEvent){if cancelWithRightMouse{finishSelection(nil)}else{super.rightMouseUp(with:event)}}
    override func keyDown(with event:NSEvent){if event.keyCode==53{finishSelection(nil)}else{super.keyDown(with:event)}}
    static func chooseScreenshot()->CGRect? {
        guard let first=NSScreen.screens.first else{return nil}
        let desktop=NSScreen.screens.dropFirst().reduce(first.frame){$0.union($1.frame)}
        let panel=RegionPanel(contentRect:desktop,styleMask:.borderless,backing:.buffered,defer:false)
        panel.isMovable=false;panel.title=L("选择截图区域");panel.isOpaque=false;panel.backgroundColor = .clear;panel.level = .screenSaver;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.isReleasedWhenClosed=false
        let view=RegionView(frame:NSRect(origin:.zero,size:desktop.size));view.cancelWithRightMouse=true;view.minimumSelectionSize=2
        view.prompt=L("左键拖选并松开截图 · 右键 / Esc 取消")
        view.confirmationFormat="%@ × %@ 点 · 松开左键截图 · 右键 / Esc 取消"
        panel.contentView=view
        var selected:CGRect?
        view.finished={rect in
            if let rect {selected=screenCaptureRect(rect,desktop:desktop,mainTop:first.frame.maxY)}
            NSApp.stopModal(withCode:rect == nil ? .cancel:.OK);panel.orderOut(nil)
        }
        NSApp.activate(ignoringOtherApps:true);panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(view)
        NSApp.runModal(for:panel);panel.close();return selected
    }
    static func screenCaptureRect(_ rect:CGRect,desktop:CGRect,mainTop:CGFloat)->CGRect {
        CGRect(x:desktop.minX+rect.minX,y:mainTop-desktop.maxY+rect.minY,width:rect.width,height:rect.height).integral
    }
    static func choose(on screen:NSScreen)->CGRect? {
        let panel=RegionPanel(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
        panel.title=L("选择录制区域");panel.isOpaque=false;panel.backgroundColor = .clear;panel.level = .screenSaver;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.isReleasedWhenClosed=false
        let view=RegionView(frame:NSRect(origin:.zero,size:screen.frame.size));panel.contentView=view
        var selected:CGRect?
        view.finished={rect in selected=rect;NSApp.stopModal(withCode:rect == nil ? .cancel:.OK);panel.orderOut(nil)}
        panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(view);NSApp.runModal(for:panel);panel.close()
        return selected
    }
}

final class RecordingSetupController: NSObject, NSWindowDelegate {
    let window:NSWindow
    var radios:[NSButton]=[]
    let targetLabel=NSTextField(wrappingLabelWithString:L("尚未选择区域"))
    let selectButton=NSButton(title:L("选择区域…"),target:nil,action:nil)
    let computerAudio=NSButton(checkboxWithTitle:L("电脑声音"),target:nil,action:nil)
    let microphoneAudio=NSButton(checkboxWithTitle:L("麦克风"),target:nil,action:nil)
    let pathLabel=NSTextField(wrappingLabelWithString:L("请选择视频文件保存位置"))
    let browseButton=NSButton(title:L("浏览…"),target:nil,action:nil)
    let startButton=NSButton(title:L("开始录制"),target:nil,action:nil)
    var mode:RecordingMode = .region
    var target:RecordingTarget?
    var outputURL:URL?
    var result:RecordingOptions?
    var selecting=false
    let willSelect:()->Void
    let didSelect:()->Void
    init(willSelect:@escaping ()->Void,didSelect:@escaping ()->Void){
        self.willSelect=willSelect;self.didSelect=didSelect
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:430,height:430),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init()
        window.title=L("轻截 · 屏幕录制");window.isReleasedWhenClosed=false;window.delegate=self;window.center()
        let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=14;root.translatesAutoresizingMaskIntoConstraints=false
        let content=window.contentView!;content.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:18),root.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-18),root.topAnchor.constraint(equalTo:content.topAnchor,constant:18),root.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-18)])
        let scope=NSStackView();scope.orientation = .vertical;scope.alignment = .leading;scope.spacing=7
        for item in RecordingMode.allCases {
            let radio=NSButton(radioButtonWithTitle:item.title,target:self,action:#selector(modeChanged(_:)));radio.tag=item.rawValue;radio.state=item == .region ? .on:.off;radios.append(radio);scope.addArrangedSubview(radio)
        }
        targetLabel.font = .systemFont(ofSize:12);targetLabel.textColor = .secondaryLabelColor;targetLabel.preferredMaxLayoutWidth=340
        scope.addArrangedSubview(targetLabel);selectButton.target=self;selectButton.action = #selector(selectTarget);selectButton.bezelStyle = .rounded;scope.addArrangedSubview(selectButton)
        root.addArrangedSubview(group(L("录制范围"),scope))
        let sound=NSStackView(views:[computerAudio,microphoneAudio]);sound.spacing=24
        let previous=RecordingAudio(rawValue:UserDefaults.standard.integer(forKey:"recordingAudio")) ?? .none
        computerAudio.state=previous.includesSystem ? .on:.off;microphoneAudio.state=previous.includesMicrophone ? .on:.off
        root.addArrangedSubview(group(L("声音"),sound))
        let save=NSStackView();save.orientation = .vertical;save.alignment = .leading;save.spacing=6
        pathLabel.font = .systemFont(ofSize:12);pathLabel.preferredMaxLayoutWidth=340;pathLabel.lineBreakMode = .byTruncatingMiddle;pathLabel.maximumNumberOfLines=2
        save.addArrangedSubview(pathLabel);browseButton.target=self;browseButton.action = #selector(browse);browseButton.bezelStyle = .rounded;save.addArrangedSubview(browseButton);root.addArrangedSubview(group(L("保存视频"),save))
        let cancel=NSButton(title:L("取消"),target:self,action:#selector(cancel));cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}"
        startButton.target=self;startButton.action = #selector(start);startButton.bezelStyle = .rounded;startButton.image=NSImage(systemSymbolName:"record.circle.fill",accessibilityDescription:L("开始录制"));startButton.imagePosition = .imageLeading;startButton.contentTintColor = .systemRed;startButton.keyEquivalent="\r"
        let buttons=NSStackView(views:[cancel,startButton]);buttons.spacing=12;root.addArrangedSubview(buttons)
        for view in root.arrangedSubviews where view is NSBox {view.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true}
        refresh()
    }
    func group(_ title:String,_ stack:NSStackView)->NSBox {
        let box=NSBox();box.title=title;box.contentViewMargins=NSSize(width:12,height:10);box.contentView=NSView();stack.translatesAutoresizingMaskIntoConstraints=false
        let v=box.contentView!;v.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:v.leadingAnchor),stack.trailingAnchor.constraint(equalTo:v.trailingAnchor),stack.topAnchor.constraint(equalTo:v.topAnchor),stack.bottomAnchor.constraint(equalTo:v.bottomAnchor)])
        box.heightAnchor.constraint(greaterThanOrEqualToConstant:max(24,ceil(stack.fittingSize.height))+38).isActive=true
        return box
    }
    func refresh(){
        selectButton.title=mode == .region ? L("选择区域…"):mode == .window ? L("选择窗口…"):L("选择屏幕…")
        targetLabel.stringValue=target?.summary ?? (mode == .region ? L("拖动框选屏幕上的矩形区域"):mode == .window ? L("选择一个应用窗口，录制时跟随窗口内容"):L("选择要录制的显示器"))
        pathLabel.stringValue=outputURL?.path ?? L("请选择视频文件保存位置")
        browseButton.isEnabled=target != nil && !selecting;selectButton.isEnabled = !selecting
        startButton.isEnabled=target != nil && outputURL != nil && !selecting
        radios.forEach{$0.isEnabled = !selecting}
    }
    @objc func modeChanged(_ sender:NSButton){guard !selecting,let value=RecordingMode(rawValue:sender.tag) else{return};mode=value;radios.forEach{$0.state=$0 === sender ? .on:.off};target=nil;refresh()}
    @objc func selectTarget(){
        guard !selecting else{return};selecting=true;refresh()
        Task { @MainActor in
            defer{self.selecting=false;self.refresh()}
            do {
                let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                if self.mode == .window {
                    let windows=content.windows.filter{$0.owningApplication?.processID != getpid() && $0.windowLayer==0 && $0.frame.width>=60 && $0.frame.height>=60}.sorted{($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "")}
                    guard !windows.isEmpty else{throw self.failure(L("没有找到可录制的窗口，请先打开目标应用。"))}
                    let names=windows.map{($0.owningApplication?.applicationName ?? L("应用"))+" · "+($0.title ?? L("无标题窗口"))}
                    guard let index=self.choose(L("选择录制窗口"),names) else{return};self.target = .window(windows[index])
                } else {
                    let displays=content.displays.sorted{a,b in a.displayID==CGMainDisplayID() && b.displayID != CGMainDisplayID()}
                    guard !displays.isEmpty else{throw self.failure(L("找不到可录制的显示器。"))}
                    let names=displays.map{display in let screen=self.screen(for:display);return (screen?.localizedName ?? L("显示器"))+(display.displayID==CGMainDisplayID() ? L("（主屏幕）"):"")}
                    let index:Int
                    if displays.count==1{index=0}else{guard let selected=self.choose(L("选择显示器"),names) else{return};index=selected}
                    let display=displays[index]
                    if self.mode == .region {
                        guard let screen=self.screen(for:display) else{throw self.failure(L("找不到对应屏幕，请重新选择。"))}
                        self.willSelect();self.window.orderOut(nil)
                        let rect=RegionView.choose(on:screen)
                        self.didSelect();self.window.makeKeyAndOrderFront(nil)
                        if let rect{self.target = .display(display,rect)}
                    }else{self.target = .display(display,nil)}
                }
            }catch{let alert=NSAlert(error:error);alert.runModal()}
        }
    }
    func screen(for display:SCDisplay)->NSScreen?{NSScreen.screens.first{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID}}
    func choose(_ title:String,_ names:[String])->Int?{
        let alert=NSAlert();alert.messageText=title;let popup=NSPopUpButton(frame:NSRect(x:0,y:0,width:440,height:28),pullsDown:false);popup.addItems(withTitles:names);alert.accessoryView=popup;alert.addButton(withTitle:L("确定"));alert.addButton(withTitle:L("取消"));return alert.runModal() == .alertFirstButtonReturn ? popup.indexOfSelectedItem:nil
    }
    func failure(_ message:String)->NSError{NSError(domain:"LightCapture",code:4,userInfo:[NSLocalizedDescriptionKey:message])}
    @objc func browse(){
        guard target != nil else{return}
        let panel=NSSavePanel();panel.title=L("视频保存位置");panel.allowedContentTypes=[.mpeg4Movie];panel.canCreateDirectories=true;panel.prompt=L("选择保存位置")
        let formatter=DateFormatter();formatter.dateFormat="yyyyMMdd-HHmmss";panel.nameFieldStringValue=outputURL?.lastPathComponent ?? L("轻截录屏")+"-\(formatter.string(from:Date())).mp4"
        if let outputURL{panel.directoryURL=outputURL.deletingLastPathComponent()}else if let saved=UserDefaults.standard.string(forKey:"recordingFolder"){panel.directoryURL=URL(fileURLWithPath:saved,isDirectory:true)}else{panel.directoryURL=FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask).first}
        if panel.runModal() == .OK,let url=panel.url{outputURL=url};refresh()
    }
    @objc func start(){guard let target,let url=outputURL else{return};let system=computerAudio.state == .on,mic=microphoneAudio.state == .on;let audio:RecordingAudio=system ? (mic ? .both:.system):(mic ? .microphone:.none);result=RecordingOptions(target:target,url:url,audio:audio);UserDefaults.standard.set(audio.rawValue,forKey:"recordingAudio");UserDefaults.standard.set(url.deletingLastPathComponent().path,forKey:"recordingFolder");NSApp.stopModal(withCode:.OK);window.orderOut(nil)}
    @objc func cancel(){NSApp.stopModal(withCode:.cancel);window.orderOut(nil)}
    func windowShouldClose(_ sender:NSWindow)->Bool{cancel();return false}
    func run()->RecordingOptions?{window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);NSApp.runModal(for:window);window.close();return result}
}
