import AppKit

enum Tool: String, CaseIterable { case select="选择", arrow="箭头", box="矩形", oval="椭圆", pen="画笔", highlight="高亮", text="文字", step="序号", redact="遮挡", crop="裁剪" }
extension Tool {var title:String {L(rawValue)}}
extension Tool {
    var hint:String {
        switch self {
        case .select:return L("选择：单击标注选中，拖动移动；Delete 删除")
        case .arrow:return L("箭头：拖动绘制，选中后拖动两端调整方向和长度")
        case .box:return L("矩形：拖动绘制，选中后拖动角点调整大小")
        case .oval:return L("椭圆：拖动绘制，选中后拖动角点调整大小")
        case .pen:return L("画笔：按住鼠标自由绘制线条")
        case .highlight:return L("高亮：拖动绘制半透明色块，突出图片内容")
        case .text:return L("文字：单击图片输入文字，选中后可拖动位置")
        case .step:return L("序号：单击放置递增编号，选中后可拖动位置")
        case .redact:return L("遮挡：拖动绘制实心黑块，覆盖敏感内容")
        case .crop:return L("裁剪：拖出需要保留的区域，可撤销")
        }
    }
}
struct Mark { var tool: Tool; var points: [NSPoint]; var color: NSColor; var width: CGFloat; var text: String = "" }
struct Snapshot { var image: NSImage; var marks: [Mark] }
// Top-left pixel coordinates: corners and edge midpoints, clockwise.
enum CanvasEdge:Int,CaseIterable {
    case topLeft,top,topRight,right,bottomRight,bottom,bottomLeft,left
    var movesLeft:Bool {[.topLeft,.bottomLeft,.left].contains(self)}
    var movesRight:Bool {[.topRight,.right,.bottomRight].contains(self)}
    var movesTop:Bool {[.topLeft,.top,.topRight].contains(self)}
    var movesBottom:Bool {[.bottomLeft,.bottom,.bottomRight].contains(self)}
    static func points(in r:NSRect)->[NSPoint] {
        [NSPoint(x:r.minX,y:r.minY),NSPoint(x:r.midX,y:r.minY),NSPoint(x:r.maxX,y:r.minY),NSPoint(x:r.maxX,y:r.midY),NSPoint(x:r.maxX,y:r.maxY),NSPoint(x:r.midX,y:r.maxY),NSPoint(x:r.minX,y:r.maxY),NSPoint(x:r.minX,y:r.midY)]
    }
    func resized(_ size:NSSize,delta:NSPoint)->NSRect {
        var left:CGFloat=0,top:CGFloat=0,right=size.width,bottom=size.height
        if movesLeft {left=min(size.width-1,max(size.width-40000,delta.x.rounded()))}
        if movesRight {right=max(1,min(40000,size.width+delta.x.rounded()))}
        if movesTop {top=min(size.height-1,max(size.height-40000,delta.y.rounded()))}
        if movesBottom {bottom=max(1,min(40000,size.height+delta.y.rounded()))}
        return NSRect(x:left,y:top,width:right-left,height:bottom-top)
    }
}
struct CanvasResizeDrag {
    let edge:CanvasEdge
    let start:NSPoint
    let imageRect:NSRect
    let imageSize:NSSize
    var bounds:NSRect
}
final class Canvas: NSView {
    var zoomScale: CGFloat?
    var image: NSImage?
    var marks: [Mark] = []
    var draft: Mark?
    var tool: Tool = .arrow
    var ink: NSColor = .systemRed
    var stroke: CGFloat = 4
    var history: [Snapshot] = [], future: [Snapshot] = []
    var selectedIndex: Int?
    var selectedMark: Mark? {guard let i=selectedIndex,marks.indices.contains(i) else{return nil};return marks[i]}
    private var dragOriginal: Mark?
    private var dragStart = NSPoint.zero
    private var dragHandle: Int?
    private var dragCheckpoint = false
    private(set) var canvasResize:CanvasResizeDrag?
    var changed: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var imageRect: NSRect {
        guard let image else { return .zero }
        let scale = zoomScale ?? min((bounds.width-48)/image.size.width, (bounds.height-48)/image.size.height, 1)
        let s = NSSize(width: image.size.width*max(0.01,scale), height:image.size.height*max(0.01,scale))
        return NSRect(x:(bounds.width-s.width)/2,y:(bounds.height-s.height)/2,width:s.width,height:s.height)
    }
    func setImage(_ value: NSImage) { clearSelection(); image=value; zoomScale=nil; marks=[]; draft=nil; history=[]; future=[]; needsDisplay=true; changed?() }
    func checkpoint() { if let image { history.append(Snapshot(image:image,marks:marks)); if history.count>40 { history.removeFirst() }; future=[] } }
    func undoEdit() { guard let old=history.popLast(), let image else{return}; future.append(Snapshot(image:image,marks:marks)); clearSelection(); self.image=old.image; marks=old.marks; needsDisplay=true; changed?() }
    func redoEdit() { guard let old=future.popLast(), let image else{return}; history.append(Snapshot(image:image,marks:marks)); clearSelection(); self.image=old.image; marks=old.marks; needsDisplay=true; changed?() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite:0.84,alpha:1).setFill(); bounds.fill()
        guard let image else {
            let title=L("打开图片，开始编辑")
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:26,weight:.semibold),.foregroundColor:NSColor.darkGray]
            let size=title.size(withAttributes:attrs)
            title.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:bounds.height/2-60),withAttributes:attrs)
            let hint=L("点击上方「打开」，或从「截图」菜单捕获屏幕")
            let a:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.gray]
            hint.draw(at:NSPoint(x:(bounds.width-hint.size(withAttributes:a).width)/2,y:bounds.height/2-12),withAttributes:a)
            return
        }
        let r=imageRect
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.4); shadow.shadowBlurRadius=18; shadow.set()
        let border=canvasResize.map {NSRect(x:r.minX+$0.bounds.minX*viewScale,y:r.minY+$0.bounds.minY*viewScale,width:$0.bounds.width*viewScale,height:$0.bounds.height*viewScale)} ?? r
        NSColor.white.setFill(); border.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:border).addClip()
        let transform=NSAffineTransform(); transform.translateX(by:r.minX,yBy:r.minY); transform.scale(by:r.width/image.size.width); transform.concat()
        drawContent(image)
        if let draft { drawMark(draft) }
        NSGraphicsContext.restoreGraphicsState()
        if canvasResize == nil {drawSelection()}
        drawCanvasEdges(in:border)
    }
    func drawContent(_ image:NSImage) { image.draw(in:NSRect(origin:.zero,size:image.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil); marks.forEach(drawMark) }
    func drawMark(_ m:Mark) {
        guard let a=m.points.first, let b=m.points.last else{return}
        let r=NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y))
        let p=NSBezierPath(); p.lineWidth=m.width; p.lineCapStyle = .round; p.lineJoinStyle = .round
        m.color.setStroke(); m.color.setFill()
        switch m.tool {
        case .select: break
        case .arrow:
            p.move(to:a);p.line(to:b);p.stroke()
            let angle=atan2(b.y-a.y,b.x-a.x),len=max(14,m.width*4)
            let tip=NSBezierPath();tip.move(to:b)
            tip.line(to:NSPoint(x:b.x-len*cos(angle-0.48),y:b.y-len*sin(angle-0.48)))
            tip.line(to:NSPoint(x:b.x-len*cos(angle+0.48),y:b.y-len*sin(angle+0.48)));tip.close();tip.fill()
        case .box: let p=NSBezierPath(rect:r);p.lineWidth=m.width;p.stroke()
        case .oval: let p=NSBezierPath(ovalIn:r);p.lineWidth=m.width;p.stroke()
        case .pen: p.move(to:a);m.points.dropFirst().forEach{p.line(to:$0)};p.stroke()
        case .highlight: m.color.withAlphaComponent(0.28).setFill();r.fill(using:.sourceOver)
        case .redact: NSColor.black.setFill();r.fill()
        case .text:
            m.text.draw(at:a,withAttributes:[.font:NSFont.systemFont(ofSize:max(20,m.width*6),weight:.semibold),.foregroundColor:m.color])
        case .step:
            let diameter=max(30,m.width*9), circle=NSRect(x:a.x-diameter/2,y:a.y-diameter/2,width:diameter,height:diameter)
            NSBezierPath(ovalIn:circle).fill()
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:diameter*0.55,weight:.bold),.foregroundColor:NSColor.white]
            let s=m.text.size(withAttributes:attrs);m.text.draw(at:NSPoint(x:a.x-s.width/2,y:a.y-s.height/2),withAttributes:attrs)
        case .crop:
            NSColor.systemTeal.setStroke(); let p=NSBezierPath(rect:r);p.lineWidth=2;p.setLineDash([6,4],count:2,phase:0);p.stroke()
        }
    }
    // Object coordinates stay in source pixels; handles stay the same size on screen.
    var viewScale: CGFloat {guard let image else{return 1};return imageRect.width/image.size.width}
    func markBounds(_ m:Mark)->NSRect {
        guard let a=m.points.first else{return .zero}
        if m.tool == .text {return NSRect(origin:a,size:m.text.size(withAttributes:[.font:NSFont.systemFont(ofSize:max(20,m.width*6),weight:.semibold)]))}
        if m.tool == .step {let d=max(30,m.width*9);return NSRect(x:a.x-d/2,y:a.y-d/2,width:d,height:d)}
        let xs=m.points.map(\.x),ys=m.points.map(\.y)
        return NSRect(x:xs.min()!,y:ys.min()!,width:xs.max()!-xs.min()!,height:ys.max()!-ys.min()!)
    }
    func handles(_ m:Mark)->[NSPoint] {
        if m.tool == .arrow {return [m.points.first!,m.points.last!]}
        if [.box,.oval,.highlight,.redact].contains(m.tool) {
            let r=markBounds(m);return [NSPoint(x:r.minX,y:r.minY),NSPoint(x:r.maxX,y:r.minY),NSPoint(x:r.maxX,y:r.maxY),NSPoint(x:r.minX,y:r.maxY)]
        }
        return []
    }
    func segmentDistance(_ p:NSPoint,_ a:NSPoint,_ b:NSPoint)->CGFloat {
        let dx=b.x-a.x,dy=b.y-a.y, length=dx*dx+dy*dy
        let t=length>0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/length)):0
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
    }
    func hitMark(_ p:NSPoint)->Int? {
        let tolerance=7/max(0.01,viewScale)
        return marks.indices.reversed().first {i in
            let m=marks[i],r=markBounds(m),t=tolerance+m.width/2
            guard r.insetBy(dx:-t,dy:-t).contains(p) else{return false}
            switch m.tool {
            case .arrow,.pen:
                return zip(m.points,m.points.dropFirst()).contains {segmentDistance(p,$0.0,$0.1)<=t}
            case .box:
                return tool == .select || !r.insetBy(dx:t,dy:t).contains(p)
            case .oval:
                guard r.width>0,r.height>0 else{return false}
                let normalized=hypot((p.x-r.midX)/(r.width/2),(p.y-r.midY)/(r.height/2))
                return tool == .select ? normalized<=1+t/min(r.width,r.height)*2 : abs(normalized-1)<=t/min(r.width,r.height)*2
            default:return true
            }
        }
    }
    func clearSelection() {canvasResize=nil;selectedIndex=nil;dragOriginal=nil;dragHandle=nil;dragCheckpoint=false;needsDisplay=true}
    func selectMark(_ index:Int?) {selectedIndex=index;if let m=selectedMark {ink=m.color;stroke=m.width};needsDisplay=true;changed?()}
    func beginObjectDrag(at p:NSPoint)->Bool {
        let tolerance=8/max(0.01,viewScale)
        var handle:Int?
        if let m=selectedMark {handle=handles(m).firstIndex {hypot($0.x-p.x,$0.y-p.y)<=tolerance}}
        if handle == nil {
            if let m=selectedMark, [.box,.oval,.highlight,.redact].contains(m.tool),markBounds(m).contains(p) {}
            else {guard let i=hitMark(p) else{return false};selectMark(i)}
        }
        dragOriginal=selectedMark;dragStart=p;dragHandle=handle;dragCheckpoint=false;return dragOriginal != nil
    }
    func dragObject(to p:NSPoint) {
        guard let original=dragOriginal,let i=selectedIndex,marks.indices.contains(i) else{return}
        guard hypot(p.x-dragStart.x,p.y-dragStart.y)>0.01 else{return}
        if !dragCheckpoint {checkpoint();dragCheckpoint=true}
        var m=original
        if let h=dragHandle {
            if m.tool == .arrow {m.points[h]=p}
            else {
                let opposite=handles(original)[(h+2)%4]
                m.points=[opposite,p]
            }
        } else {
            m.points=original.points.map {NSPoint(x:$0.x+p.x-dragStart.x,y:$0.y+p.y-dragStart.y)}
        }
        marks[i]=m;needsDisplay=true;changed?()
    }
    func endObjectDrag() {dragOriginal=nil;dragHandle=nil;dragCheckpoint=false}
    func setColor(_ color:NSColor) {ink=color;guard let i=selectedIndex,marks.indices.contains(i),!marks[i].color.isEqual(color) else{return};checkpoint();marks[i].color=color;needsDisplay=true;changed?()}
    func setStroke(_ width:CGFloat) {stroke=width;guard let i=selectedIndex,marks.indices.contains(i),marks[i].width != width else{return};checkpoint();marks[i].width=width;needsDisplay=true;changed?()}
    func deleteSelection() {guard let i=selectedIndex,marks.indices.contains(i) else{return};checkpoint();marks.remove(at:i);clearSelection();changed?()}
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {deleteSelection()}
        else if event.keyCode == 53 {clearSelection();draft=nil;changed?()}
        else {super.keyDown(with:event)}
    }
    func drawSelection() {
        guard let m=selectedMark else{return}
        func viewPoint(_ p:NSPoint)->NSPoint {NSPoint(x:imageRect.minX+p.x*viewScale,y:imageRect.minY+p.y*viewScale)}
        NSGraphicsContext.saveGraphicsState()
        NSColor.systemBlue.setStroke()
        let r=markBounds(m),a=viewPoint(r.origin)
        let outline=NSBezierPath(rect:NSRect(origin:a,size:NSSize(width:r.width*viewScale,height:r.height*viewScale)).insetBy(dx:-3,dy:-3))
        outline.lineWidth=1;outline.setLineDash([4,3],count:2,phase:0);outline.stroke()
        for p in handles(m) {
            let v=viewPoint(p),circle=NSBezierPath(ovalIn:NSRect(x:v.x-4.5,y:v.y-4.5,width:9,height:9))
            NSColor.white.setFill();circle.fill();NSColor.systemBlue.setStroke();circle.lineWidth=1.5;circle.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    func drawCanvasEdges(in rect:NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSColor(calibratedWhite:0.35,alpha:1).setStroke()
        for point in CanvasEdge.points(in:rect) {
            let dot=NSBezierPath(ovalIn:NSRect(x:point.x-3.5,y:point.y-3.5,width:7,height:7))
            NSColor.white.setFill();dot.fill();dot.lineWidth=1;dot.stroke()
        }
        if let drag=canvasResize {
            let text="\(Int(drag.bounds.width)) × \(Int(drag.bounds.height)) px"
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor.labelColor,.backgroundColor:NSColor.controlBackgroundColor]
            text.draw(at:NSPoint(x:rect.minX,y:rect.minY-22),withAttributes:attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        guard image != nil else{return}
        for edge in CanvasEdge.allCases {
            let point=CanvasEdge.points(in:imageRect)[edge.rawValue]
            let cursor:NSCursor=[.top,.bottom].contains(edge) ? .resizeUpDown:([.left,.right].contains(edge) ? .resizeLeftRight:.crosshair)
            addCursorRect(NSRect(x:point.x-7,y:point.y-7,width:14,height:14),cursor:cursor)
        }
    }
    func beginCanvasResize(at point:NSPoint)->Bool {
        guard let image else{return false}
        let r=imageRect
        // Fixed screen-space hit radius, independent of zoom and drawing tool.
        guard let edge=CanvasEdge.allCases.min(by:{ a,b in
            let points=CanvasEdge.points(in:r)
            return hypot(points[a.rawValue].x-point.x,points[a.rawValue].y-point.y)<hypot(points[b.rawValue].x-point.x,points[b.rawValue].y-point.y)
        }) else{return false}
        let handle=CanvasEdge.points(in:r)[edge.rawValue]
        guard hypot(handle.x-point.x,handle.y-point.y)<=7 else{return false}
        clearSelection();draft=nil
        canvasResize=CanvasResizeDrag(edge:edge,start:point,imageRect:r,imageSize:image.size,bounds:NSRect(origin:.zero,size:image.size))
        needsDisplay=true;return true
    }
    func dragCanvasResize(to point:NSPoint) {
        guard var drag=canvasResize else{return}
        let scale=drag.imageRect.width/drag.imageSize.width
        let bounds=drag.edge.resized(drag.imageSize,delta:NSPoint(x:(point.x-drag.start.x)/scale,y:(point.y-drag.start.y)/scale))
        guard bounds.width*bounds.height<=60_000_000 else{return}
        drag.bounds=bounds;canvasResize=drag;needsDisplay=true
    }
    func endCanvasResize() {
        guard let drag=canvasResize else{return}
        canvasResize=nil
        resizeCanvas(to:drag.bounds)
        needsDisplay=true
    }
    func resizeCanvas(to rect:NSRect) {
        guard let image,rect != NSRect(origin:.zero,size:image.size),
              rect.width>=1,rect.height>=1,rect.width<=40000,rect.height<=40000,rect.width*rect.height<=60_000_000,
              let rendered=renderedImage(),
              let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(rect.width),pixelsHigh:Int(rect.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context=NSGraphicsContext(bitmapImageRep:rep) else{return}
        NSGraphicsContext.saveGraphicsState()
        context.cgContext.translateBy(x:0,y:rect.height);context.cgContext.scaleBy(x:1,y:-1)
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context.cgContext,flipped:true)
        NSColor.white.setFill();NSRect(origin:.zero,size:rect.size).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        rendered.draw(in:NSRect(x:-rect.minX,y:-rect.minY,width:image.size.width,height:image.size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        NSGraphicsContext.restoreGraphicsState()
        let result=NSImage(size:rect.size);result.addRepresentation(rep)
        checkpoint();self.image=result;marks=[];draft=nil;clearSelection()
        needsDisplay=true;changed?()
    }
    func point(_ event:NSEvent)->NSPoint? {
        guard let image else{return nil};let p=convert(event.locationInWindow,from:nil),r=imageRect
        return NSPoint(x:max(0,min(image.size.width,(p.x-r.minX)*image.size.width/r.width)),y:max(0,min(image.size.height,(p.y-r.minY)*image.size.height/r.height)))
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self)
        if beginCanvasResize(at:convert(event.locationInWindow,from:nil)) {return}
        guard imageRect.contains(convert(event.locationInWindow,from:nil)),let p=point(event) else{return}
        if tool != .crop && beginObjectDrag(at:p) {return}
        clearSelection();changed?()
        if tool == .select {return}
        if tool == .text {
            let alert=NSAlert();alert.messageText=L("添加文字");let field=NSTextField(frame:NSRect(x:0,y:0,width:320,height:28));alert.accessoryView=field;alert.addButton(withTitle:L("添加"));alert.addButton(withTitle:L("取消"));alert.window.initialFirstResponder=field
            if alert.runModal() == .alertFirstButtonReturn && !field.stringValue.isEmpty { checkpoint();marks.append(Mark(tool:.text,points:[p],color:ink,width:stroke,text:field.stringValue));selectMark(marks.count-1) };return
        }
        if tool == .step {checkpoint(); marks.append(Mark(tool:.step,points:[p],color:ink,width:stroke,text:String(marks.filter{$0.tool == .step}.count+1)));selectMark(marks.count-1);return}
        draft=Mark(tool:tool,points:[p,p],color:ink,width:stroke)
    }
    override func mouseDragged(with event:NSEvent) { if canvasResize != nil {autoscroll(with:event);dragCanvasResize(to:convert(event.locationInWindow,from:nil));return};if dragOriginal != nil,let p=point(event) {dragObject(to:p);return};guard draft != nil,let p=point(event) else{return};if tool == .pen {draft?.points.append(p)} else {draft?.points[1]=p};needsDisplay=true }
    override func rightMouseDown(with event:NSEvent) {
        if canvasResize != nil {canvasResize=nil;needsDisplay=true;return}
        super.rightMouseDown(with:event)
    }
    override func mouseUp(with event:NSEvent) {
        if canvasResize != nil {dragCanvasResize(to:convert(event.locationInWindow,from:nil));endCanvasResize();return}
        if dragOriginal != nil {endObjectDrag();return}
        guard let d=draft else{return};draft=nil
        guard let a=d.points.first,let b=d.points.last,hypot(a.x-b.x,a.y-b.y)>2 else{needsDisplay=true;return}
        if d.tool == .crop {
            if let rendered=renderedImage(), let cg=rendered.cgImage(forProposedRect:nil,context:nil,hints:nil) {
                let r=NSRect(x:min(a.x,b.x),y:min(a.y,b.y),width:abs(a.x-b.x),height:abs(a.y-b.y)).integral
                if let cut=cg.cropping(to:r) {checkpoint();image=NSImage(cgImage:cut,size:r.size);marks=[];clearSelection()}
            }
        } else { checkpoint();marks.append(d);selectMark(marks.count-1) }
        needsDisplay=true;changed?()
    }
    func renderedImage()->NSImage? {
        guard let image,let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(image.size.width),pixelsHigh:Int(image.size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:rep) else{return nil}
        NSGraphicsContext.saveGraphicsState();let cg=context.cgContext;cg.translateBy(x:0,y:image.size.height);cg.scaleBy(x:1,y:-1);NSGraphicsContext.current=NSGraphicsContext(cgContext:cg,flipped:true);drawContent(image);NSGraphicsContext.restoreGraphicsState()
        let result=NSImage(size:image.size);result.addRepresentation(rep);return result
    }
    func imageData(_ type:NSBitmapImageRep.FileType = .png)->Data? { guard let cg=renderedImage()?.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil};return NSBitmapImageRep(cgImage:cg).representation(using:type,properties:[.compressionFactor:0.92]) }
}

func testCanvasEdges() {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:48,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    for y in 0..<48 {for x in 0..<64 {rep.setColor(NSColor(deviceRed:CGFloat(x+20)/100,green:CGFloat(y+10)/100,blue:0.3,alpha:1),atX:x,y:y)}}
    let image=NSImage(size:NSSize(width:64,height:48));image.addRepresentation(rep)
    let c=Canvas(frame:NSRect(x:0,y:0,width:800,height:600))
    for scale:CGFloat in [0.25,1,2] {
        for edge in CanvasEdge.allCases {
            for expanding in [true,false] {
                c.setImage(image);c.zoomScale=scale
                c.marks=[Mark(tool:.redact,points:[NSPoint(x:25,y:20),NSPoint(x:35,y:30)],color:.black,width:2)]
                let original=c.imageData()!,before=NSBitmapImageRep(data:original)!
                let dx:CGFloat=edge.movesLeft ? -10:(edge.movesRight ? 10:0)
                let dy:CGFloat=edge.movesTop ? -8:(edge.movesBottom ? 8:0)
                let delta=NSPoint(x:expanding ? dx:-dx,y:expanding ? dy:-dy)
                let expected=edge.resized(image.size,delta:delta)
                let point=CanvasEdge.points(in:c.imageRect)[edge.rawValue]
                assert(c.beginCanvasResize(at:point))
                c.dragCanvasResize(to:NSPoint(x:point.x+delta.x*scale,y:point.y+delta.y*scale))
                assert(c.canvasResize?.bounds==expected)
                assert(c.history.isEmpty && c.imageData()==original)
                c.endCanvasResize()
                assert(c.history.count==1 && c.marks.isEmpty && c.image?.size==expected.size)
                let after=NSBitmapImageRep(data:c.imageData()!)!
                assert(after.pixelsWide==Int(expected.width) && after.pixelsHigh==Int(expected.height))
                for y in 0..<after.pixelsHigh {for x in 0..<after.pixelsWide {
                    let actual=after.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                    let sx=x+Int(expected.minX),sy=y+Int(expected.minY)
                    let wanted=(sx>=0 && sx<64 && sy>=0 && sy<48) ? before.colorAt(x:sx,y:sy)!.usingColorSpace(.deviceRGB)!:NSColor.white.usingColorSpace(.deviceRGB)!
                    assert(abs(actual.redComponent-wanted.redComponent)<0.005 && abs(actual.greenComponent-wanted.greenComponent)<0.005 && abs(actual.blueComponent-wanted.blueComponent)<0.005 && actual.alphaComponent>0.99)
                }}
                let resized=c.imageData()!
                c.undoEdit();assert(c.imageData()==original && c.marks.count==1)
                c.redoEdit();assert(c.imageData()==resized && c.marks.isEmpty)
            }
        }
    }
    c.setImage(image);c.zoomScale=1
    let point=CanvasEdge.points(in:c.imageRect)[4]
    assert(c.beginCanvasResize(at:point));c.endCanvasResize();assert(c.history.isEmpty)
    assert(!c.beginCanvasResize(at:NSPoint(x:c.imageRect.midX,y:c.imageRect.midY)))
    assert(c.beginCanvasResize(at:point));c.dragCanvasResize(to:NSPoint(x:point.x+20,y:point.y+20))
    let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:53)!
    c.keyDown(with:escape);c.endCanvasResize();assert(c.history.isEmpty && c.image?.size==image.size)
    assert(c.beginCanvasResize(at:point));c.dragCanvasResize(to:NSPoint(x:point.x+20,y:point.y+20))
    let right=NSEvent.mouseEvent(with:.rightMouseDown,location:point,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:0,clickCount:1,pressure:1)!
    c.rightMouseDown(with:right);c.endCanvasResize();assert(c.history.isEmpty && c.image?.size==image.size)
    assert(CanvasEdge.left.resized(image.size,delta:NSPoint(x:1000,y:0)).width==1)
    assert(CanvasEdge.top.resized(image.size,delta:NSPoint(x:0,y:1000)).height==1)
    assert(CanvasEdge.right.resized(image.size,delta:NSPoint(x:100000,y:0)).width==40000)
    c.resizeCanvas(to:NSRect(x:0,y:0,width:40000,height:40000));assert(c.history.isEmpty)
}
