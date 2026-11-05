import AppKit

enum ImageRotationError:LocalizedError {
    case angle,size,render
    var errorDescription:String? {
        switch self {
        case .angle:return L("请输入 -360～360 之间的角度。")
        case .size:return L("旋转后的图片过大，请先裁剪或缩小图片。")
        case .render:return L("无法生成旋转后的图片。")
        }
    }
}
enum RotationRenderer {
    static func outputSize(_ size:NSSize,angle:Double,autoCrop:Bool)->NSSize {
        let radians=angle * .pi/180,c=abs(cos(radians)),s=abs(sin(radians))
        if !autoCrop {return NSSize(width:ceil(size.width*c+size.height*s-1e-7),height:ceil(size.width*s+size.height*c-1e-7))}
        // Maximise x*y inside both source-edge constraints for a centred crop.
        let a=size.width/2,b=size.height/2
        if s<1e-9 {return size}
        if c<1e-9 {return NSSize(width:size.height,height:size.width)}
        var candidates=[NSPoint(x:a/(2*c),y:a/(2*s)),NSPoint(x:b/(2*s),y:b/(2*c))]
        let determinant=c*c-s*s
        if abs(determinant)>1e-9 {candidates.append(NSPoint(x:(a*c-b*s)/determinant,y:(b*c-a*s)/determinant))}
        let best=candidates.filter{$0.x>0 && $0.y>0 && c*$0.x+s*$0.y<=a+1e-7 && s*$0.x+c*$0.y<=b+1e-7}.max{ $0.x*$0.y < $1.x*$1.y } ?? .zero
        return NSSize(width:max(1,floor(best.x*2+1e-7)),height:max(1,floor(best.y*2+1e-7)))
    }
    static func render(_ image:NSImage,angle:Double,background:NSColor,autoCrop:Bool)throws->NSImage {
        guard angle.isFinite,abs(angle)<=360 else{throw ImageRotationError.angle}
        let size=outputSize(image.size,angle:angle,autoCrop:autoCrop)
        guard size.width>0,size.height>0,size.width<=40000,size.height<=40000,size.width*size.height<=60_000_000 else{throw ImageRotationError.size}
        guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:rep) else{throw ImageRotationError.render}
        NSGraphicsContext.saveGraphicsState()
        let cg=context.cgContext;cg.translateBy(x:0,y:size.height);cg.scaleBy(x:1,y:-1)
        NSGraphicsContext.current=NSGraphicsContext(cgContext:cg,flipped:true)
        background.withAlphaComponent(1).setFill();NSRect(origin:.zero,size:size).fill()
        cg.translateBy(x:size.width/2,y:size.height/2);cg.rotate(by:angle * .pi/180)
        NSGraphicsContext.current?.imageInterpolation = abs(angle.truncatingRemainder(dividingBy:90))<1e-9 ? .none:.high
        image.draw(in:NSRect(x:-image.size.width/2,y:-image.size.height/2,width:image.size.width,height:image.size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        NSGraphicsContext.restoreGraphicsState()
        let result=NSImage(size:size);result.addRepresentation(rep);return result
    }
}
extension Canvas {
    @discardableResult func rotateImage(degrees:Int,clockwise:Bool=true)throws->Bool {
        guard (1...360).contains(degrees) else{throw ImageRotationError.angle}
        return try rotateImage(angle:Double(degrees)*(clockwise ? 1:-1))
    }
    @discardableResult func rotateImage(angle:Double,background:NSColor = .white,autoCrop:Bool=false)throws->Bool {
        guard angle.isFinite,abs(angle)<=360 else{throw ImageRotationError.angle}
        guard image != nil,abs(angle.truncatingRemainder(dividingBy:360))>1e-9 else{return false}
        // Validate the output before allocating the flattened source bitmap.
        let size=RotationRenderer.outputSize(image!.size,angle:angle,autoCrop:autoCrop)
        guard size.width<=40000,size.height<=40000,size.width*size.height<=60_000_000 else{throw ImageRotationError.size}
        guard let rendered=renderedImage() else{throw ImageRotationError.render}
        let result=try RotationRenderer.render(rendered,angle:angle,background:background,autoCrop:autoCrop)
        checkpoint();image=result;marks=[];draft=nil;clearSelection();needsDisplay=true;changed?();return true
    }
}

class RotationPreviewView:NSView {
    var image:NSImage?
    var angle:Double=0
    var background:NSColor = .white
    var autoCrop=false
    var grid=false
    override var isFlipped:Bool {true}
    override func draw(_ dirtyRect:NSRect){
        NSColor(calibratedWhite:0.78,alpha:1).setFill();bounds.fill()
        guard let image else{return}
        let size=RotationRenderer.outputSize(image.size,angle:angle,autoCrop:autoCrop)
        let scale=min((bounds.width-4)/max(1,size.width),(bounds.height-4)/max(1,size.height))
        let rect=NSRect(x:(bounds.width-size.width*scale)/2,y:(bounds.height-size.height*scale)/2,width:size.width*scale,height:size.height*scale)
        NSGraphicsContext.saveGraphicsState();NSBezierPath(rect:rect).addClip()
        background.setFill();rect.fill()
        let transform=NSAffineTransform();transform.translateX(by:rect.midX,yBy:rect.midY);transform.scale(by:scale);transform.rotate(byDegrees:angle);transform.concat()
        image.draw(in:NSRect(x:-image.size.width/2,y:-image.size.height/2,width:image.size.width,height:image.size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        NSGraphicsContext.restoreGraphicsState()
        if grid {
            let path=NSBezierPath();path.lineWidth=0.5
            for i in 1..<4 {
                let x=bounds.width*CGFloat(i)/4,y=bounds.height*CGFloat(i)/4
                path.move(to:NSPoint(x:x,y:0));path.line(to:NSPoint(x:x,y:bounds.height))
                path.move(to:NSPoint(x:0,y:y));path.line(to:NSPoint(x:bounds.width,y:y))
            }
            NSColor.white.withAlphaComponent(0.65).setStroke();path.stroke()
        }
        NSColor.gray.setStroke();NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
    }
}
final class RotationFullscreenWindow:NSWindow {override var canBecomeKey:Bool {true}}
final class RotationFullscreenView:RotationPreviewView {
    var dismiss:(()->Void)?
    override var acceptsFirstResponder:Bool {true}
    override func mouseDown(with event:NSEvent){dismiss?()}
    override func keyDown(with event:NSEvent){if event.keyCode==53 || event.keyCode==36 {dismiss?()}else{super.keyDown(with:event)}}
    override func draw(_ dirtyRect:NSRect){super.draw(dirtyRect);L("单击或按 Esc 返回").draw(at:NSPoint(x:20,y:20),withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.white,.backgroundColor:NSColor.darkGray])}
}
final class RotationAdjustmentController:NSObject,NSWindowDelegate,NSTextFieldDelegate {
    let dialog:NSWindow
    let source:NSImage
    let before=RotationPreviewView(),after=RotationPreviewView()
    let slider=NSSlider(value:0,minValue:-360,maxValue:360,target:nil,action:nil)
    let field=NSTextField(string:"0.0"),stepper=NSStepper()
    let crop=NSButton(checkboxWithTitle:L("自动裁剪"),target:nil,action:nil)
    let color=NSColorWell()
    let info=NSTextField(labelWithString:"")
    let ok=NSButton(title:L("确定"),target:nil,action:nil)
    let fullscreen=NSButton(title:L("全屏预览"),target:nil,action:nil)
    var angle:Double=0
    var accepted=false
    init(source:NSImage){
        self.source=source
        dialog=NSWindow(contentRect:NSRect(x:0,y:0,width:880,height:530),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        super.init()
        dialog.title=L("任意角度旋转");dialog.minSize=NSSize(width:760,height:430);dialog.isReleasedWhenClosed=false;dialog.delegate=self;dialog.appearance=NSAppearance(named:.aqua)
        // Cache a bounded preview while keeping its logical dimensions in source pixels.
        var preview=source
        let factor=min(1,1400/max(source.size.width,source.size.height))
        if factor<1,let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(source.size.width*factor),pixelsHigh:Int(source.size.height*factor),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:rep) {
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
            source.draw(in:NSRect(x:0,y:0,width:rep.pixelsWide,height:rep.pixelsHigh));NSGraphicsContext.restoreGraphicsState()
            preview=NSImage(size:source.size);preview.addRepresentation(rep)
        }
        before.image=preview;after.image=preview;after.grid=true
        before.setAccessibilityLabel(L("旋转前"));after.setAccessibilityLabel(L("旋转后"))
        let root=NSStackView();root.orientation = .vertical;root.spacing=10;root.alignment = .leading;root.edgeInsets=NSEdgeInsets(top:12,left:12,bottom:12,right:12);root.translatesAutoresizingMaskIntoConstraints=false
        dialog.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:dialog.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:dialog.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:dialog.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:dialog.contentView!.bottomAnchor)])
        func column(_ title:String,_ view:NSView)->NSStackView {
            let label=NSTextField(labelWithString:title);label.alignment = .center
            let stack=NSStackView(views:[label,view]);stack.orientation = .vertical;stack.spacing=5
            view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
            view.heightAnchor.constraint(greaterThanOrEqualToConstant:230).isActive=true
            return stack
        }
        let comparisons=NSStackView(views:[column(L("旋转前"),before),column(L("旋转后"),after)]);comparisons.distribution = .fillEqually;comparisons.spacing=8
        before.heightAnchor.constraint(equalTo:after.heightAnchor).isActive=true
        comparisons.setContentHuggingPriority(.defaultLow,for:.vertical);root.addArrangedSubview(comparisons)
        slider.target=self;slider.action = #selector(slideAngle);slider.isContinuous=true;slider.setAccessibilityLabel(L("旋转角度滑块"));slider.toolTip=L("正值顺时针，负值逆时针")
        field.delegate=self;field.alignment = .right;field.widthAnchor.constraint(equalToConstant:72).isActive=true;field.setAccessibilityLabel(L("旋转角度"))
        stepper.minValue = -360;stepper.maxValue=360;stepper.increment=0.1;stepper.target=self;stepper.action = #selector(stepAngle);stepper.setAccessibilityLabel(L("旋转角度"))
        let row=NSStackView(views:[NSTextField(labelWithString:L("旋转：")),slider,field,stepper]);row.spacing=8;root.addArrangedSubview(row)
        crop.target=self;crop.action = #selector(updateOptions);crop.toolTip=L("裁去旋转后新增的边角，仅保留原图内的最大中心矩形")
        color.color = .white;color.target=self;color.action = #selector(updateOptions);color.setAccessibilityLabel(L("旋转背景颜色"));color.widthAnchor.constraint(equalToConstant:80).isActive=true;color.heightAnchor.constraint(equalToConstant:25).isActive=true
        fullscreen.target=self;fullscreen.action = #selector(fullscreenPreview);fullscreen.bezelStyle = .rounded
        let spring=NSView();spring.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let options=NSStackView(views:[crop,NSTextField(labelWithString:L("背景：")),color,spring,fullscreen]);options.spacing=12;root.addArrangedSubview(options)
        ok.target=self;ok.action = #selector(confirm);ok.bezelStyle = .rounded;ok.keyEquivalent="\r"
        let cancel=NSButton(title:L("取消"),target:self,action:#selector(cancel));cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}"
        info.font = .systemFont(ofSize:11);info.textColor = .secondaryLabelColor;info.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let bottomSpring=NSView();bottomSpring.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let bottom=NSStackView(views:[info,bottomSpring,ok,cancel]);bottom.spacing=10;root.addArrangedSubview(bottom)
        for v in [comparisons,row,options,bottom] {v.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-24).isActive=true}
        dialog.initialFirstResponder=field;dialog.center();updatePreview()
    }
    func run()->Bool {dialog.makeKeyAndOrderFront(nil);NSApp.runModal(for:dialog);color.deactivate();dialog.close();return accepted}
    func windowShouldClose(_ sender:NSWindow)->Bool {cancel();return false}
    @objc func confirm(){guard validateField() else{return};accepted=true;NSApp.stopModal()}
    @objc func cancel(){accepted=false;NSApp.stopModal()}
    @objc func slideAngle(){angle=(slider.doubleValue*10).rounded()/10;syncControls();updatePreview()}
    @objc func stepAngle(){angle=(stepper.doubleValue*10).rounded()/10;syncControls();updatePreview()}
    func syncControls(){field.stringValue=String(format:"%.1f",angle);slider.doubleValue=angle;stepper.doubleValue=angle}
    @discardableResult func validateField()->Bool {
        guard let value=Double(field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)),value.isFinite,abs(value)<=360 else {info.stringValue=L("请输入 -360～360 之间的角度。");info.textColor = .systemRed;ok.isEnabled=false;fullscreen.isEnabled=false;return false}
        angle=(value*10).rounded()/10;slider.doubleValue=angle;stepper.doubleValue=angle;updatePreview();return ok.isEnabled
    }
    func controlTextDidChange(_ notification:Notification){validateField()}
    @objc func updateOptions(){updatePreview()}
    func updatePreview(){
        after.angle=angle;after.background=color.color.withAlphaComponent(1);after.autoCrop=crop.state == .on;after.needsDisplay=true
        let size=RotationRenderer.outputSize(source.size,angle:angle,autoCrop:after.autoCrop)
        let valid=size.width<=40000 && size.height<=40000 && size.width*size.height<=60_000_000
        ok.isEnabled=valid;fullscreen.isEnabled=valid;info.textColor=valid ? .secondaryLabelColor:.systemRed
        info.stringValue=valid ? "\(Int(size.width)) × \(Int(size.height)) px  ·  "+L("正值顺时针，负值逆时针"):L("旋转后的图片过大，请先裁剪或缩小图片。")
    }
    @objc func fullscreenPreview(){
        guard validateField(),let screen=dialog.screen ?? NSScreen.main else{return}
        let window=RotationFullscreenWindow(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.level = .statusBar
        let view=RotationFullscreenView(frame:NSRect(origin:.zero,size:screen.frame.size));view.image=after.image;view.angle=angle;view.background=after.background;view.autoCrop=after.autoCrop;view.dismiss={NSApp.stopModal()}
        window.contentView=view;window.makeKeyAndOrderFront(nil);window.makeFirstResponder(view);NSApp.runModal(for:window);window.close();dialog.makeKeyAndOrderFront(nil)
    }
}
extension App {
    @objc func rotateImage(){
        guard let source=canvas.renderedImage() else{return}
        let adjustment=RotationAdjustmentController(source:source)
        guard adjustment.run() else{return}
        do{if try canvas.rotateImage(angle:adjustment.angle,background:adjustment.color.color,autoCrop:adjustment.crop.state == .on){zoomFit()}}catch{self.error(error)}
    }
}
func testImageRotation() {
    let c=Canvas(frame:NSRect(x:0,y:0,width:800,height:600))
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:8,pixelsHigh:4,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    for y in 0..<4 {for x in 0..<8 {rep.setColor(NSColor(deviceRed:CGFloat(x+1)/10,green:CGFloat(y+1)/10,blue:0.3,alpha:1),atX:x,y:y)}}
    let image=NSImage(size:NSSize(width:8,height:4));image.addRepresentation(rep)
    for degrees in [90,180,270] {
        for clockwise in [true,false] {
            c.setImage(image);c.marks=[Mark(tool:.redact,points:[NSPoint(x:2,y:1),NSPoint(x:4,y:3)],color:.black,width:1)]
            let original=c.imageData()!,before=NSBitmapImageRep(data:original)!
            assert(try! c.rotateImage(degrees:degrees,clockwise:clockwise))
            let after=NSBitmapImageRep(data:c.imageData()!)!
            let turn=(clockwise ? degrees:360-degrees)/90
            assert(after.pixelsWide==(turn==2 ? 8:4) && after.pixelsHigh==(turn==2 ? 4:8))
            for y in 0..<4 {for x in 0..<8 {
                let point:(Int,Int)
                switch turn {case 1:point=(3-y,x);case 2:point=(7-x,3-y);default:point=(y,7-x)}
                let actual=after.colorAt(x:point.0,y:point.1)!.usingColorSpace(.deviceRGB)!,wanted=before.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                assert(abs(actual.redComponent-wanted.redComponent)<0.005 && abs(actual.greenComponent-wanted.greenComponent)<0.005 && abs(actual.blueComponent-wanted.blueComponent)<0.005)
            }}
            assert(c.history.count==1 && c.marks.isEmpty)
            let rotated=c.imageData()!
            c.undoEdit();assert(c.imageData()==original && c.marks.count==1)
            c.redoEdit();assert(c.imageData()==rotated && c.marks.isEmpty)
        }
    }
    for degrees in 1...359 {
        c.setImage(image);assert(try! c.rotateImage(degrees:degrees))
        let rotated=NSBitmapImageRep(data:c.imageData()!)!
        assert(rotated.pixelsWide>0 && rotated.pixelsHigh>0)
        if degrees==45 {
            assert(rotated.pixelsWide==9 && rotated.pixelsHigh==9)
            for (x,y) in [(0,0),(8,0),(0,8),(8,8)] {
                let white=rotated.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                assert(white.redComponent>0.99 && white.greenComponent>0.99 && white.blueComponent>0.99 && white.alphaComponent>0.99)
            }
        }
    }
    c.setImage(image);let original=c.imageData()!
    assert(!(try! c.rotateImage(degrees:360)) && c.history.isEmpty && c.imageData()==original)
    for invalid in [0,-1,361] {
        do{try c.rotateImage(degrees:invalid);assertionFailure("Invalid angle accepted")}catch{}
        assert(c.history.isEmpty && c.imageData()==original)
    }
    c.setImage(NSImage(size:NSSize(width:40000,height:40000)))
    do{try c.rotateImage(degrees:45);assertionFailure("Oversized rotation accepted")}catch{}
    assert(c.history.isEmpty)
}

func testRotationAdjustment() {
    let size=NSSize(width:100,height:60)
    for tenth in stride(from:0,through:3600,by:7) {
        let angle=Double(tenth)/10,r=angle * .pi/180,c=abs(cos(r)),s=abs(sin(r))
        let crop=RotationRenderer.outputSize(size,angle:angle,autoCrop:true)
        assert(crop.width>=1 && crop.height>=1)
        assert(c*crop.width+s*crop.height<=size.width+1e-6)
        assert(s*crop.width+c*crop.height<=size.height+1e-6)
    }
    assert(RotationRenderer.outputSize(size,angle:0,autoCrop:true)==size)
    assert(RotationRenderer.outputSize(size,angle:90,autoCrop:true)==NSSize(width:60,height:100))
    assert(RotationRenderer.outputSize(size,angle:45,autoCrop:true)==NSSize(width:42,height:42))
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:100,pixelsHigh:60,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    for y in 0..<60 {for x in 0..<100{rep.setColor(NSColor(deviceRed:1,green:0,blue:0,alpha:1),atX:x,y:y)}}
    let source=NSImage(size:size);source.addRepresentation(rep)
    let rotated=try! RotationRenderer.render(source,angle:17.3,background:NSColor(deviceRed:0,green:1,blue:0,alpha:1),autoCrop:false)
    let bitmap=NSBitmapImageRep(data:rotated.tiffRepresentation!)!
    let corner=bitmap.colorAt(x:0,y:0)!.usingColorSpace(.deviceRGB)!
    assert(corner.greenComponent>0.95 && corner.redComponent<0.01 && corner.alphaComponent>0.99)
    let cropped=try! RotationRenderer.render(source,angle:17.3,background:NSColor(deviceRed:0,green:1,blue:0,alpha:1),autoCrop:true)
    let expected=RotationRenderer.outputSize(size,angle:17.3,autoCrop:true)
    assert(cropped.size==expected)
    let pixels=NSBitmapImageRep(data:cropped.tiffRepresentation!)!
    let centre=pixels.colorAt(x:pixels.pixelsWide/2,y:pixels.pixelsHigh/2)!.usingColorSpace(.deviceRGB)!
    for (x,y) in [(0,0),(pixels.pixelsWide-1,0),(0,pixels.pixelsHigh-1),(pixels.pixelsWide-1,pixels.pixelsHigh-1)] {
        let color=pixels.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
        assert(abs(color.redComponent-centre.redComponent)<0.02 && abs(color.greenComponent-centre.greenComponent)<0.02 && abs(color.blueComponent-centre.blueComponent)<0.02)
    }
    let controller=RotationAdjustmentController(source:source)
    controller.field.stringValue="17.3";assert(controller.validateField() && controller.angle==17.3 && controller.after.angle==17.3)
    controller.crop.state = .on;controller.updateOptions();assert(controller.after.autoCrop)
    controller.field.stringValue="-90";assert(controller.validateField() && controller.angle == -90)
    controller.field.stringValue="invalid";assert(!controller.validateField() && !controller.ok.isEnabled)
    controller.field.stringValue="361";assert(!controller.validateField())
    controller.field.stringValue="0";assert(controller.validateField())
    controller.dialog.close()
}
