import AppKit

final class DrawingToolButton: NSButton {
    override func draw(_ dirtyRect:NSRect) {
        let selected=state == .on
        let color:NSColor=selected ? .systemBlue:.labelColor
        let background:NSColor=selected ? .systemBlue.withAlphaComponent(isHighlighted ? 0.24:0.14):NSColor(calibratedWhite:isHighlighted ? 0.86:0.93,alpha:1)
        background.setFill()
        let outline=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:7,yRadius:7)
        outline.fill()
        if selected {NSColor.systemBlue.withAlphaComponent(0.6).setStroke();outline.lineWidth=1;outline.stroke()}
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:12,weight:selected ? .semibold:.regular),.foregroundColor:color]
        let size=title.size(withAttributes:attributes),iconSize:CGFloat=15,gap:CGFloat=5
        let x=(bounds.width-size.width-iconSize-gap)/2
        if let symbol=image?.withSymbolConfiguration(.init(paletteColors:[color])) {
            symbol.draw(in:NSRect(x:x,y:(bounds.height-iconSize)/2,width:iconSize,height:iconSize),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        title.draw(at:NSPoint(x:x+iconSize+gap,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
}

final class EditorCommandButton:NSButton {
    override var isFlipped:Bool {false}
    override func draw(_ dirtyRect:NSRect){
        if isHighlighted && isEnabled {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:5,yRadius:5).fill()
        }
        let color:NSColor=isEnabled ? (contentTintColor ?? .secondaryLabelColor):.disabledControlTextColor
        let iconColor:NSColor=isEnabled ? (contentTintColor ?? .gray):.lightGray
        let iconBox=NSRect(x:(bounds.width-26)/2,y:bounds.height-32,width:26,height:26)
        if let symbol=image?.withSymbolConfiguration(.init(paletteColors:[iconColor])) {
            let size=symbol.size
            let scale=min(1,26/max(1,size.width),26/max(1,size.height))
            let target=NSRect(x:iconBox.midX-size.width*scale/2,y:iconBox.midY-size.height*scale/2,width:size.width*scale,height:size.height*scale)
            symbol.draw(in:target,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        }
        let attrs:[NSAttributedString.Key:Any]=[.font:font ?? NSFont.systemFont(ofSize:11),.foregroundColor:color]
        let size=title.size(withAttributes:attrs)
        title.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:12),withAttributes:attrs)
    }
}

final class EditorScrollView: NSScrollView {
    var didLayout: (() -> Void)?
    var zoomAtPointer: ((CGFloat, NSPoint) -> Void)?
    var usesZoomMargins=false
    override func scrollWheel(with event:NSEvent) {
        guard event.modifierFlags.contains(.control) else{super.scrollWheel(with:event);return}
        let delta=event.scrollingDeltaY
        guard delta.isFinite,delta != 0 else{return}
        // Natural-scrolling preference should not reverse a physical zoom gesture.
        let direction:CGFloat=event.isDirectionInvertedFromDevice ? -1:1
        let sensitivity:CGFloat=event.hasPreciseScrollingDeltas ? 0.008:0.12
        let factor=exp(max(-0.5,min(0.5,delta*direction*sensitivity)))
        zoomAtPointer?(factor,contentView.convert(event.locationInWindow,from:nil))
    }
    override func layout() {super.layout();didLayout?()}
}
extension App {
    func commandHint(_ action:Selector,_ title:String)->String {
        switch action {
        case #selector(openImage):return L("打开图片 · ⌘O")
        case #selector(saveImage):return L("保存图片为 PNG、JPEG 或 PDF · ⌘S")
        case #selector(copyImage):return L("复制带标注的图片 · ⇧⌘C")
        case #selector(importClipboardImage):return L("从剪贴板导入 · ⌥⌘V")
        case #selector(undoEdit):return L("撤销上一次编辑 · ⌘Z")
        case #selector(redoEdit):return L("重做已撤销的编辑 · ⇧⌘Z")
        case #selector(selectCrop):return L("裁剪：拖出需要保留的区域，可撤销")
        case #selector(toggleDrawing):return L("显示或隐藏左侧绘图工具")
        case #selector(zoomIn):return L("放大图片显示，不改变导出尺寸")
        case #selector(zoomOut):return L("缩小图片显示，不改变导出尺寸")
        case #selector(zoomFit):return L("适合窗口：完整显示图片")
        case #selector(zoomActual):return L("原大：按 100% 显示图片")
        case #selector(ocr):return L("识别图片中的中英文文字，可复制结果")
        case #selector(pin):return L("将当前图片作为置顶参考图显示")
        case #selector(combine):return L("选择多张图片，从上到下拼接成长图")
        case #selector(toggleRecording):return L("屏幕录制")
        default:return title
        }
    }
    func buildEditorWindow() {
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:Localizer.isEnglish ? 1184:1120,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title=L("轻截 · 图片编辑器");window.minSize=NSSize(width:Localizer.isEnglish ? 1184:1040,height:560);window.center();window.delegate=self;window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.aqua)
        let root=NSStackView();root.orientation = .vertical;root.spacing=0;root.alignment = .leading;window.contentView=root
        func command(_ title:String,_ symbol:String,_ action:Selector)->NSButton {
            let b=EditorCommandButton(title:title,target:self,action:action);b.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil);b.bezelStyle = .regularSquare;b.isBordered=false;b.imagePosition = .imageAbove;b.font = .systemFont(ofSize:11);b.image=b.image?.withSymbolConfiguration(.init(pointSize:19,weight:.regular));b.toolTip=commandHint(action,title);b.setAccessibilityLabel(title)
            b.widthAnchor.constraint(equalToConstant:Localizer.isEnglish ? 60:49).isActive=true;b.heightAnchor.constraint(equalToConstant:54).isActive=true;return b
        }
        func divider()->NSView {let v=NSBox();v.boxType = .separator;v.widthAnchor.constraint(equalToConstant:1).isActive=true;v.heightAnchor.constraint(equalToConstant:34).isActive=true;return v}
        editorUndo=command(L("撤销"),"arrow.uturn.backward",#selector(undoEdit));editorRedo=command(L("重做"),"arrow.uturn.forward",#selector(redoEdit))
        recordButton=command(L("录屏"),"video",#selector(toggleRecording))
        editorPasteButton=command(L("粘贴"),"clipboard",#selector(importClipboardImage))
        refreshClipboardAvailability(force:true)
        let capture=NSPopUpButton(frame:.zero,pullsDown:true);capture.addItem(withTitle:L("截图"));capture.bezelStyle = .rounded;capture.toolTip=L("截图：选择区域、窗口或全屏捕获")
        capture.menu?.addItem(menuItem(L("区域截图"),#selector(region)));capture.menu?.addItem(menuItem(L("窗口截图"),#selector(captureWindow)));capture.menu?.addItem(menuItem(L("全屏截图"),#selector(full)));capture.menu?.addItem(menuItem(L("滚动截图"),#selector(scrollingCapture)));capture.menu?.addItem(menuItem(L("显示快速捕获栏"),#selector(showPanel)))
        let toolbar=NSStackView(views:[command(L("打开"),"folder",#selector(openImage)),command(L("保存"),"square.and.arrow.down",#selector(saveImage)),command(L("复制"),"doc.on.doc",#selector(copyImage)),editorPasteButton!,divider(),editorUndo!,editorRedo!,divider(),command(L("裁剪"),"crop",#selector(selectCrop)),command(L("绘图"),"pencil.tip",#selector(toggleDrawing)),divider(),command(L("放大"),"plus.magnifyingglass",#selector(zoomIn)),command(L("缩小"),"minus.magnifyingglass",#selector(zoomOut)),command(L("适合"),"arrow.up.left.and.arrow.down.right",#selector(zoomFit)),command(L("原大"),"1.magnifyingglass",#selector(zoomActual)),divider(),command(L("文字识别"),"text.viewfinder",#selector(ocr)),command(L("贴图"),"pin",#selector(pin)),command(L("拼接"),"rectangle.stack",#selector(combine)),divider(),capture,recordButton!]);toolbar.spacing=3;toolbar.alignment = .centerY;toolbar.edgeInsets=NSEdgeInsets(top:8,left:8,bottom:8,right:8)
        root.addArrangedSubview(toolbar)
        let line=NSBox();line.boxType = .separator;root.addArrangedSubview(line)
        editorSidebar=NSStackView();editorSidebar.orientation = .vertical;editorSidebar.alignment = .leading;editorSidebar.spacing=12;editorSidebar.edgeInsets=NSEdgeInsets(top:16,left:12,bottom:12,right:12);editorSidebar.widthAnchor.constraint(equalToConstant:Localizer.isEnglish ? 210:174).isActive=true
        let heading=NSTextField(labelWithString:L("绘图工具"));heading.font = .systemFont(ofSize:12,weight:.semibold);editorSidebar.addArrangedSubview(heading)
        let symbols=["cursorarrow","arrow.up.right","rectangle","oval","pencil","highlighter","t.square","1.circle","rectangle.fill","crop"]
        for row in stride(from:0,to:Tool.allCases.count,by:2) {
            let stack=NSStackView();stack.spacing=6
            for i in row..<min(row+2,Tool.allCases.count) {let b=DrawingToolButton(title:Tool.allCases[i].title,target:self,action:#selector(selectEditorTool(_:)));b.image=NSImage(systemSymbolName:symbols[i],accessibilityDescription:nil);b.setAccessibilityLabel(Tool.allCases[i].title);b.toolTip=Tool.allCases[i].hint;b.tag=i;b.setButtonType(.toggle);b.bezelStyle = .regularSquare;b.widthAnchor.constraint(equalToConstant:Localizer.isEnglish ? 90:72).isActive=true;b.heightAnchor.constraint(equalToConstant:32).isActive=true;b.font = .systemFont(ofSize:12);editorTools.append(b);stack.addArrangedSubview(b)}
            editorSidebar.addArrangedSubview(stack)
        }
        let style=NSTextField(labelWithString:L("线条样式"));style.font = .systemFont(ofSize:12,weight:.semibold);editorSidebar.addArrangedSubview(style)
        let color=NSColorWell(frame:.zero);color.color=canvas.ink;color.target=self;color.action = #selector(colorChanged(_:));color.widthAnchor.constraint(equalToConstant:55).isActive=true;color.heightAnchor.constraint(equalToConstant:25).isActive=true;color.setAccessibilityLabel(L("标注颜色"));color.toolTip=L("颜色：修改选中标注和后续绘图的颜色")
        editorColor=color;editorSidebar.addArrangedSubview(NSStackView(views:[NSTextField(labelWithString:L("颜色")),color]))
        let width=NSSegmentedControl(labels:[L("细"),L("中"),L("粗")],trackingMode:.selectOne,target:self,action:#selector(widthChanged(_:)));width.selectedSegment=canvas.stroke<=2 ? 0:(canvas.stroke>=8 ? 2:1);editorWidth=width;width.setAccessibilityLabel(L("线条粗细"));width.toolTip=L("线条粗细：修改选中标注和后续绘图的粗细");editorSidebar.addArrangedSubview(width)
        let hint=NSTextField(wrappingLabelWithString:L("单击选中，拖动移动\n拖动控制点调整图形\nDelete 删除，Esc 取消选中"));hint.font = .systemFont(ofSize:11);hint.textColor = .secondaryLabelColor;hint.widthAnchor.constraint(equalToConstant:Localizer.isEnglish ? 186:148).isActive=true;editorSidebar.addArrangedSubview(hint)
        let spacer=NSView();spacer.setContentHuggingPriority(.defaultLow,for:.vertical);editorSidebar.addArrangedSubview(spacer)
        editorScroll=EditorScrollView();editorScroll.hasVerticalScroller=true;editorScroll.hasHorizontalScroller=true;editorScroll.autohidesScrollers=true;editorScroll.borderType = .noBorder;editorScroll.documentView=canvas;editorScroll.didLayout={ [weak self] in self?.updateCanvasLayout() }
        editorScroll.zoomAtPointer={ [weak self] factor,point in self?.changeZoom(factor,at:point) }
        editorScroll.toolTip=L("按住 Control 并滚动鼠标滚轮，以指针为中心缩放")
        editorTitle.font = .systemFont(ofSize:12);editorTitle.textColor = .secondaryLabelColor
        let titleRow=NSStackView(views:[editorTitle]);titleRow.edgeInsets=NSEdgeInsets(top:7,left:12,bottom:7,right:12)
        let workspace=NSStackView(views:[titleRow,editorScroll]);workspace.orientation = .vertical;workspace.spacing=0;workspace.alignment = .leading
        editorScroll.widthAnchor.constraint(equalTo:workspace.widthAnchor).isActive=true
        let body=NSStackView(views:[editorSidebar,workspace]);body.spacing=0;body.alignment = .top;root.addArrangedSubview(body);workspace.trailingAnchor.constraint(equalTo:body.trailingAnchor).isActive=true
        editorSidebar.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true;workspace.heightAnchor.constraint(equalTo:body.heightAnchor).isActive=true
        let bottomLine=NSBox();bottomLine.boxType = .separator;root.addArrangedSubview(bottomLine)
        statusLabel.font = .systemFont(ofSize:11);statusLabel.textColor = .secondaryLabelColor;editorZoom.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular)
        let spring=NSView();spring.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let bottom=NSStackView(views:[statusLabel,spring,editorZoom]);bottom.edgeInsets=NSEdgeInsets(top:6,left:12,bottom:6,right:12);root.addArrangedSubview(bottom)
        for v in [line,body,bottomLine,bottom] {v.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true}
        body.setContentHuggingPriority(.defaultLow,for:.vertical);workspace.setContentHuggingPriority(.defaultLow,for:.horizontal);editorScroll.setContentHuggingPriority(.defaultLow,for:.vertical)
        editorScroll.setContentCompressionResistancePriority(.defaultLow,for:.vertical);body.setContentCompressionResistancePriority(.defaultLow,for:.vertical)
        canvas.changed={ [weak self] in self?.refreshEditor() };refreshEditor()
    }
    func updateCanvasLayout() {
        guard let scroll=editorScroll else{return};let size=scroll.contentSize
        if canvas.zoomScale == nil {scroll.usesZoomMargins=false}
        var target=size
        if let image=canvas.image,let scale=canvas.zoomScale {
            // Extra margins allow an image point to stay under the pointer even
            // while crossing from a fitted image to a scrollable image.
            let padding=scroll.usesZoomMargins ? NSSize(width:max(48,size.width*2),height:max(48,size.height*2)):NSSize(width:48,height:48)
            target=NSSize(width:max(size.width,image.size.width*scale+padding.width),height:max(size.height,image.size.height*scale+padding.height))
        }
        if canvas.frame.size != target {canvas.setFrameSize(target)}
        canvas.needsDisplay=true
        if let image=canvas.image {editorZoom.stringValue=LF("缩放 %@%%",Int((canvas.imageRect.width/image.size.width*100).rounded()))}else{editorZoom.stringValue=L("适合窗口")}
    }
    func refreshEditor() {
        editorColor?.color=canvas.ink;editorWidth?.selectedSegment=canvas.stroke<=2 ? 0:(canvas.stroke>=8 ? 2:1)
        updateCanvasLayout();editorUndo?.isEnabled = !canvas.history.isEmpty;editorRedo?.isEnabled = !canvas.future.isEmpty
        for (i,b) in editorTools.enumerated(){b.state=Tool.allCases[i]==canvas.tool ? .on:.off;b.contentTintColor=Tool.allCases[i]==canvas.tool ? .systemBlue:.labelColor;b.needsDisplay=true}
        if let image=canvas.image {editorTitle.stringValue=documentName;statusLabel.stringValue=LF("%@ × %@ 像素  ·  %@ 个标注  ·  %@",Int(image.size.width),Int(image.size.height),canvas.marks.count,canvas.tool.title)}
    }
    @objc func selectEditorTool(_ sender:NSButton) {canvas.clearSelection();canvas.tool=Tool.allCases[sender.tag];window.makeFirstResponder(canvas);refreshEditor()}
    @objc func selectCrop() {canvas.clearSelection();canvas.tool = .crop;editorSidebar.isHidden=false;refreshEditor()}
    @objc func toggleDrawing() {editorSidebar.isHidden.toggle()}
    func changeZoom(_ factor:CGFloat) {guard let image=canvas.image else{return};let current=canvas.zoomScale ?? canvas.imageRect.width/image.size.width;canvas.zoomScale=max(0.05,min(4,current*factor));updateCanvasLayout()}
    func changeZoom(_ factor:CGFloat,at clipPoint:NSPoint) {
        guard let image=canvas.image,let scroll=editorScroll,factor.isFinite,factor>0 else{return}
        let clip=scroll.contentView,oldRect=canvas.imageRect
        guard oldRect.width>0,oldRect.height>0 else{return}
        let point=canvas.convert(clipPoint,from:clip)
        let unit=NSPoint(x:(point.x-oldRect.minX)/oldRect.width,y:(point.y-oldRect.minY)/oldRect.height)
        let viewportPoint=NSPoint(x:clipPoint.x-clip.bounds.minX,y:clipPoint.y-clip.bounds.minY)
        let current=oldRect.width/image.size.width
        let scale=max(0.01,min(4,current*factor))
        guard abs(scale-current)>0.000001 else{return}
        scroll.usesZoomMargins=true;canvas.zoomScale=scale
        updateCanvasLayout();scroll.layoutSubtreeIfNeeded()
        let rect=canvas.imageRect
        let anchored=NSPoint(x:rect.minX+unit.x*rect.width,y:rect.minY+unit.y*rect.height)
        let inClip=clip.convert(anchored,from:canvas)
        let proposed=NSRect(origin:NSPoint(x:inClip.x-viewportPoint.x,y:inClip.y-viewportPoint.y),size:clip.bounds.size)
        clip.scroll(to:clip.constrainBoundsRect(proposed).origin);scroll.reflectScrolledClipView(clip)
    }
    func testPointerZoom() {
        guard let image=canvas.image else{preconditionFailure("Missing zoom fixture")}
        let clip=editorScroll.contentView
        let original=canvas.imageData()!,marksCount=canvas.marks.count,historyCount=canvas.history.count
        for unit in [NSPoint(x:0.2,y:0.3),NSPoint(x:0.8,y:0.7)] {
            zoomFit()
            let rect=canvas.imageRect
            let anchor=NSPoint(x:rect.minX+rect.width*unit.x,y:rect.minY+rect.height*unit.y)
            let inClip=clip.convert(anchor,from:canvas)
            let viewport=NSPoint(x:inClip.x-clip.bounds.minX,y:inClip.y-clip.bounds.minY)
            for factor:CGFloat in [1.25,2,0.5,0.8,0.01,10000] {
                let point=NSPoint(x:clip.bounds.minX+viewport.x,y:clip.bounds.minY+viewport.y)
                changeZoom(factor,at:point)
                let r=canvas.imageRect
                let after=clip.convert(NSPoint(x:r.minX+r.width*unit.x,y:r.minY+r.height*unit.y),from:canvas)
                assert(abs(after.x-clip.bounds.minX-viewport.x)<1)
                assert(abs(after.y-clip.bounds.minY-viewport.y)<1)
                assert(canvas.zoomScale!>=0.01 && canvas.zoomScale!<=4)
            }
        }
        assert(canvas.marks.count==marksCount && canvas.history.count==historyCount)
        assert(canvas.imageData()==original && canvas.image?.size==image.size)
        zoomFit()
    }
    @objc func zoomIn(){changeZoom(1.25)}
    @objc func zoomOut(){changeZoom(0.8)}
    @objc func zoomFit(){canvas.zoomScale=nil;updateCanvasLayout()}
    @objc func zoomActual(){guard canvas.image != nil else{return};canvas.zoomScale=1;updateCanvasLayout()}
}
