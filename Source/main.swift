import AppKit
import Vision
import Carbon
import UniformTypeIdentifiers

final class CaptureToolButton: NSButton {
    private var hoverTracking:NSTrackingArea?
    override func updateTrackingAreas(){
        if let hoverTracking {removeTrackingArea(hoverTracking)}
        super.updateTrackingAreas()
        let area=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self,userInfo:nil)
        hoverTracking=area;addTrackingArea(area)
    }
    override func mouseEntered(with event:NSEvent){if isEnabled{layer?.backgroundColor=NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor}}
    override func mouseExited(with event:NSEvent){layer?.backgroundColor=NSColor.clear.cgColor}
}

enum PanelPlacement {
    static let key="quickCaptureWindowOrigin"
    static func save(_ origin:NSPoint,defaults:UserDefaults = .standard){
        guard origin.x.isFinite && origin.y.isFinite else{return}
        defaults.set(["x":Double(origin.x),"y":Double(origin.y)],forKey:key)
    }
    static func restore(size:NSSize,screens:[NSRect],fallback:NSPoint,defaults:UserDefaults = .standard)->NSPoint {
        guard let saved=defaults.dictionary(forKey:key),let x=saved["x"] as? Double,let y=saved["y"] as? Double,x.isFinite,y.isFinite else{return constrain(fallback,size:size,screens:screens)}
        return constrain(NSPoint(x:x,y:y),size:size,screens:screens)
    }
    static func constrain(_ origin:NSPoint,size:NSSize,screens:[NSRect])->NSPoint {
        guard !screens.isEmpty else{return origin}
        let frame=NSRect(origin:origin,size:size)
        func area(_ r:NSRect)->CGFloat {let hit=r.intersection(frame);return hit.isNull ? 0:hit.width*hit.height}
        func distance(_ r:NSRect)->CGFloat {pow(r.midX-frame.midX,2)+pow(r.midY-frame.midY,2)}
        let screen=screens.min {a,b in area(a)==area(b) ? distance(a)<distance(b):area(a)>area(b)}!
        return NSPoint(x:min(max(origin.x,screen.minX),max(screen.minX,screen.maxX-size.width)),y:min(max(origin.y,screen.minY),max(screen.minY,screen.maxY-size.height)))
    }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var editorColor:NSColorWell?
    var editorWidth:NSSegmentedControl?
    let canvas=Canvas(frame:.zero)
    var window:NSWindow!
    var panel:NSPanel!
    var status:NSStatusItem!
    var statusLabel=NSTextField(labelWithString:L("准备就绪 · 图片仅在本机处理"))
    var pins:[NSWindow]=[]
    var hotkeys:[EventHotKeyRef?]=[]
    var recorder=Recorder()
    var recording=false
    var scrollCapture:ScrollingCaptureController?
    var capturing=false
    var recordButton:NSButton!
    var quickRecordButton:NSButton!
    var clipboardButton:NSButton?
    var editorPasteButton:NSButton?
    var clipboardTimer:Timer?
    var screenObserver:NSObjectProtocol?
    var clipboardChangeCount = -1
    var clipboardContainsImage=false
    var editorScroll: EditorScrollView!
    var editorSidebar: NSStackView!
    var editorTools: [NSButton] = []
    var editorZoom = NSTextField(labelWithString:L("适合窗口"))
    var editorTitle = NSTextField(labelWithString:L("尚未打开图片"))
    var editorUndo: NSButton!
    var editorRedo: NSButton!
    var documentName = L("图片")
    var restoreQuickAfterRecording=false
    var recordingBusy=false
    func applicationDidFinishLaunching(_ note:Notification) {
        NSApp.setActivationPolicy(.regular);if let url=Bundle.main.url(forResource:"LightCapture",withExtension:"icns"),let icon=NSImage(contentsOf:url){NSApp.applicationIconImage=icon};buildMenus();buildWindow();buildPanel();buildStatus();registerHotkeys()
        startClipboardMonitoring()
        screenObserver=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main){[weak self] _ in self?.keepPanelOnScreen()}
        showPanel();NSApp.activate(ignoringOtherApps:true)
        if let index=CommandLine.arguments.firstIndex(of:"--open"),CommandLine.arguments.count>index+1 {load(URL(fileURLWithPath:CommandLine.arguments[index+1]));showEditor()}
        if CommandLine.arguments.contains("--self-test") {selfTest()}
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        if recording {showPanel()}
        else if let modal=sender.modalWindow {modal.makeKeyAndOrderFront(nil)}
        else if window.isVisible || window.isMiniaturized {
            if window.isMiniaturized {window.deminiaturize(nil)}
            showEditor()
        } else {showPanel()}
        sender.activate(ignoringOtherApps:true)
        return false
    }
    func button(_ title:String,_ action:Selector,_ symbol:String?=nil)->NSButton {
        let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded
        if let symbol {b.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title);b.imagePosition = .imageLeading};return b
    }
    func buildWindow() {buildEditorWindow()}
    func menuItem(_ title:String,_ action:Selector,_ key:String="",mods:NSEvent.ModifierFlags = .command)->NSMenuItem {let m=NSMenuItem(title:title,action:action,keyEquivalent:key);m.target=self;m.keyEquivalentModifierMask=mods;return m}
    func languageMenuItem()->NSMenuItem {
        let root=NSMenuItem(title:"语言 / Language",action:nil,keyEquivalent:"")
        let menu=NSMenu()
        for (index,title) in ["跟随系统 / System", "简体中文", "English"].enumerated() {
            let item=menuItem(title,#selector(changeLanguage(_:)));item.tag=index
            item.state=UILanguage.allCases[index] == Localizer.selection ? .on:.off
            menu.addItem(item)
        }
        root.submenu=menu;return root
    }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if capturing {return item.action == #selector(scrollingCapture) || item.action == #selector(quit)}
        if item.action == #selector(importClipboardImage) {refreshClipboardAvailability();return clipboardContainsImage && !capturing && !recordingBusy && NSApp.modalWindow == nil}
        return item.action == #selector(changeLanguage(_:)) ? (!recording && !recordingBusy && NSApp.modalWindow == nil):true
    }
    @objc func changeLanguage(_ sender:NSMenuItem) {
        guard !capturing && !recording && !recordingBusy && NSApp.modalWindow == nil else{return}
        let language=UILanguage.allCases[sender.tag]
        guard language != Localizer.selection else{return}
        let translatedName=["图片","屏幕截图","拼接图片","剪贴板图片","滚动截图"].first {L($0)==documentName}
        let editorVisible=window.isVisible, quickVisible=panel.isVisible
        let oldWindow=window!, oldPanel=panel!
        let editorFrame=window.frame, quickOrigin=panel.frame.origin
        let sidebarHidden=editorSidebar.isHidden
        oldWindow.orderOut(nil);oldPanel.orderOut(nil)
        canvas.removeFromSuperview();editorTools.removeAll()
        UserDefaults.standard.set(language.rawValue,forKey:"uiLanguage")
        if let translatedName {documentName=L(translatedName)}
        statusLabel.stringValue=L("准备就绪 · 图片仅在本机处理")
        editorTitle.stringValue=L("尚未打开图片")
        buildMenus();buildWindow();buildPanel()
        window.setFrame(editorFrame,display:false);panel.setFrameOrigin(quickOrigin)
        editorSidebar.isHidden=sidebarHidden
        NSStatusBar.system.removeStatusItem(status);buildStatus()
        canvas.needsDisplay=true;refreshEditor()
        if editorVisible {showEditor()}else if quickVisible {showPanel()}
        oldWindow.close();oldPanel.close()
    }
    func buildMenus() {
        let bar=NSMenu();let appItem=NSMenuItem();let appMenu=NSMenu();appMenu.addItem(menuItem(L("关于轻截"),#selector(about)));appMenu.addItem(languageMenuItem());appMenu.addItem(.separator());appMenu.addItem(menuItem(L("退出轻截"),#selector(quit),"q"));appItem.submenu=appMenu;bar.addItem(appItem)
        let file=NSMenuItem(title:L("文件"),action:nil,keyEquivalent:"");let fm=NSMenu();fm.addItem(menuItem(L("打开图片…"),#selector(openImage),"o"));fm.addItem(menuItem(L("从剪贴板导入"),#selector(importClipboardImage),"v",mods:[.command,.option]));fm.addItem(menuItem(L("保存图片…"),#selector(saveImage),"s"));fm.addItem(menuItem(L("区域截图"),#selector(region),"2",mods:[.command,.option]));fm.addItem(menuItem(L("全屏截图"),#selector(full),"3",mods:[.command,.option]));fm.addItem(menuItem(L("窗口截图"),#selector(captureWindow),"4",mods:[.command,.option]));fm.addItem(menuItem(L("滚动截图"),#selector(scrollingCapture)));fm.addItem(.separator());fm.addItem(menuItem(L("开始／停止录屏"),#selector(toggleRecording)));file.submenu=fm;bar.addItem(file)
        let edit=NSMenuItem(title:L("编辑"),action:nil,keyEquivalent:"");let em=NSMenu();em.addItem(menuItem(L("撤销标注"),#selector(undoEdit),"z"));em.addItem(menuItem(L("重做标注"),#selector(redoEdit),"z",mods:[.command,.shift]));let copy=NSMenuItem(title:L("复制"),action:#selector(NSText.copy(_:)),keyEquivalent:"c");em.addItem(copy);let paste=NSMenuItem(title:L("粘贴"),action:#selector(NSText.paste(_:)),keyEquivalent:"v");em.addItem(paste);let all=NSMenuItem(title:L("全选"),action:#selector(NSText.selectAll(_:)),keyEquivalent:"a");em.addItem(all);em.addItem(menuItem(L("复制标注图片"),#selector(copyImage),"c",mods:[.command,.shift]));edit.submenu=em;bar.addItem(edit);NSApp.mainMenu=bar
    }
    func fullScreenCaptureIcon()->NSImage {
        let icon=NSImage(size:NSSize(width:20,height:18),flipped:false){_ in
            NSColor.black.setStroke()
            let frame=NSBezierPath(roundedRect:NSRect(x:0.8,y:1.8,width:18.4,height:14.4),xRadius:2.8,yRadius:2.8)
            frame.lineWidth=1.4;frame.stroke()
            let arrows=NSBezierPath();arrows.lineWidth=1;arrows.lineCapStyle = .round;arrows.lineJoinStyle = .round
            for sx:CGFloat in [-1,1] {
                for sy:CGFloat in [-1,1] {
                    let tip=NSPoint(x:10+sx*4.5,y:9+sy*3.4)
                    arrows.move(to:NSPoint(x:10+sx*1.5,y:9+sy*1.1));arrows.line(to:tip)
                    arrows.move(to:NSPoint(x:tip.x-sx*2,y:tip.y));arrows.line(to:tip);arrows.line(to:NSPoint(x:tip.x,y:tip.y-sy*2))
                }
            }
            arrows.stroke()
            return true
        }
        icon.isTemplate=true;return icon
    }
    func buildPanel() {
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:230,height:34),styleMask:[.titled,.closable,.utilityWindow,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.allowsToolTipsWhenApplicationIsInactive=true;panel.title=L("轻截");panel.level = .floating;panel.isFloatingPanel=true;panel.hidesOnDeactivate=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.isReleasedWhenClosed=false
        func tool(_ label:String,_ action:Selector,_ symbol:String,_ hint:String)->NSButton {
            let button=CaptureToolButton(title:"",target:self,action:action)
            button.bezelStyle = .regularSquare;button.isBordered=false;button.imagePosition = .imageOnly
            button.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label)?.withSymbolConfiguration(.init(pointSize:16,weight:.regular))
            if action == #selector(full) {button.image=fullScreenCaptureIcon()}
            button.setAccessibilityLabel(label);button.toolTip=hint;button.wantsLayer=true;button.layer?.cornerRadius=4
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant:28),button.heightAnchor.constraint(equalToConstant:26)])
            return button
        }
        func separator()->NSView {
            let divider=NSBox();divider.boxType = .separator
            NSLayoutConstraint.activate([divider.widthAnchor.constraint(equalToConstant:1),divider.heightAnchor.constraint(equalToConstant:18)])
            return divider
        }
        quickRecordButton=tool(L("屏幕录制"),#selector(toggleRecording),"video",L("屏幕录制"))
        let more=NSPopUpButton(frame:.zero,pullsDown:true);more.bezelStyle = .regularSquare;more.isBordered=false;more.imagePosition = .imageOnly
        more.addItem(withTitle:L("更多"));more.item(at:0)?.image=NSImage(systemSymbolName:"gearshape",accessibilityDescription:L("更多工具"))?.withSymbolConfiguration(.init(pointSize:16,weight:.regular))
        more.setAccessibilityLabel(L("更多工具"));more.toolTip=L("更多工具与设置")
        let menu=more.menu!;menu.addItem(menuItem(L("滚动截图"),#selector(scrollingCapture)));menu.addItem(menuItem(L("拼接长图…"),#selector(combine)));menu.addItem(languageMenuItem());menu.addItem(.separator());menu.addItem(menuItem(L("关于轻截"),#selector(about)));menu.addItem(menuItem(L("退出轻截"),#selector(quit)))
        NSLayoutConstraint.activate([more.widthAnchor.constraint(equalToConstant:30),more.heightAnchor.constraint(equalToConstant:26)])
        let editorButton=tool(L("编辑器"),#selector(showEditor),"square.and.pencil",L("打开图片编辑器"))
        let settingsDivider=separator()
        clipboardButton=tool(L("从剪贴板导入"),#selector(importClipboardImage),"clipboard",L("从剪贴板导入 · ⌥⌘V"))
        refreshClipboardAvailability(force:true)
        let row=NSStackView(views:[clipboardButton!,tool(L("窗口截图"),#selector(captureWindow),"macwindow",L("窗口截图 · ⌥⌘4")),tool(L("区域截图"),#selector(region),"rectangle.dashed",L("矩形区域截图 · ⌥⌘2")),tool(L("全屏截图"),#selector(full),"arrow.up.left.and.arrow.down.right",L("全屏截图 · ⌥⌘3")),tool(L("滚动截图"),#selector(scrollingCapture),"arrow.down.square",L("滚动截图")),separator(),quickRecordButton!,separator(),tool(L("打开图片"),#selector(openImage),"folder",L("打开图片 · ⌘O")),editorButton,settingsDivider,more])
        row.spacing=2;row.setCustomSpacing(1,after:editorButton);row.setCustomSpacing(9,after:settingsDivider);row.alignment = .centerY
        panel.setContentSize(NSSize(width:ceil(row.fittingSize.width)+12,height:34));row.translatesAutoresizingMaskIntoConstraints=false
        if let content=panel.contentView {
            content.wantsLayer=true;content.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor;content.addSubview(row)
            NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:6),row.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-6),row.topAnchor.constraint(equalTo:content.topAnchor,constant:4),row.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-4)])
        }
        let fallback=NSPoint(x:(NSScreen.main?.visibleFrame.minX ?? 0)+80,y:(NSScreen.main?.visibleFrame.maxY ?? 800)-100)
        panel.setFrameOrigin(PanelPlacement.restore(size:panel.frame.size,screens:NSScreen.screens.map(\.visibleFrame),fallback:fallback))
        panel.delegate=self
    }
    func buildStatus() {status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);status.button?.image=NSImage(systemSymbolName:"viewfinder",accessibilityDescription:L("轻截"));let m=NSMenu();m.addItem(menuItem(L("区域截图   ⌥⌘2"),#selector(region)));m.addItem(menuItem(L("窗口截图   ⌥⌘4"),#selector(captureWindow)));m.addItem(menuItem(L("全屏截图   ⌥⌘3"),#selector(full)));m.addItem(menuItem(L("滚动截图／完成"),#selector(scrollingCapture)));m.addItem(.separator());m.addItem(menuItem(L("显示编辑器"),#selector(showEditor)));m.addItem(menuItem(L("显示浮动栏"),#selector(showPanel)));m.addItem(menuItem(L("开始／停止录屏"),#selector(toggleRecording)));m.addItem(.separator());m.addItem(menuItem(L("退出"),#selector(quit)));status.menu=m}
    func registerHotkeys() {
        var type=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{_,event,context in
            guard let context,let event else{return noErr};var id=EventHotKeyID();GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            let app=Unmanaged<App>.fromOpaque(context).takeUnretainedValue();DispatchQueue.main.async {if id.id==1 {app.region()} else if id.id==2 {app.full()} else {app.captureWindow()}};return noErr
        },1,&type,Unmanaged.passUnretained(self).toOpaque(),nil)
        for (index,key) in [UInt32(kVK_ANSI_2),UInt32(kVK_ANSI_3),UInt32(kVK_ANSI_4)].enumerated() {var ref:EventHotKeyRef?;let result=RegisterEventHotKey(key,UInt32(cmdKey|optionKey),EventHotKeyID(signature:0x4c434150,id:UInt32(index+1)),GetApplicationEventTarget(),0,&ref);hotkeys.append(ref);if result != noErr {statusLabel.stringValue=L("部分快捷键被占用，可使用菜单栏截图")}}
    }
    @objc func region(){chooseCaptureRect {RegionView.chooseScreenshot()}}
    @objc func captureWindow(){chooseCaptureRect {WindowCaptureView.choose()}}
    func chooseCaptureRect(_ choose:@escaping ()->CGRect?){
        guard !capturing else{return}
        let restoreEditor=window.isVisible
        capturing=true;window.orderOut(nil);panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.2){
            let rect=choose();self.capturing=false
            guard let rect else {if restoreEditor{self.showEditor()}else{self.showPanel()};return}
            self.capture(["-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"])
        }
    }
    @objc func full(){capture(["-m"])}
    func capture(_ flags:[String]) {
        guard !capturing else{return};capturing=true
        window.orderOut(nil);panel.orderOut(nil)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.3) {
            let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture");p.arguments=["-x"]+flags+[url.path];p.standardError=FileHandle.nullDevice
            p.terminationHandler={_ in DispatchQueue.main.async {self.capturing=false;if FileManager.default.fileExists(atPath:url.path) {self.load(url);self.documentName=L("屏幕截图");self.refreshEditor();try? FileManager.default.removeItem(at:url)} else {self.statusLabel.stringValue=L("截图已取消，或尚未授予屏幕录制权限")};self.showEditor()}}
            do{try p.run()}catch{self.capturing=false;self.showEditor();self.error(error)}
        }
    }
    func normalized(_ image:NSImage)->NSImage? {guard let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return nil};return NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))}
    func load(_ url:URL) {guard let image=NSImage(contentsOf:url),let image=normalized(image) else{message(L("无法打开图片"),L("请选择 PNG、JPEG、TIFF 或其他系统支持的图片。"));return};documentName=url.lastPathComponent;canvas.setImage(image)}
    func startClipboardMonitoring(){
        clipboardTimer?.invalidate()
        let timer=Timer(timeInterval:0.5,repeats:true){[weak self] _ in self?.refreshClipboardAvailability()}
        clipboardTimer=timer;RunLoop.main.add(timer,forMode:.common)
        refreshClipboardAvailability(force:true)
    }
    func applicationDidBecomeActive(_ notification:Notification){refreshClipboardAvailability(force:true)}
    func refreshClipboardAvailability(force:Bool=false){
        let pb=NSPasteboard.general
        if force || clipboardChangeCount != pb.changeCount {
            clipboardChangeCount=pb.changeCount;clipboardContainsImage=NSImage.canInit(with:pb)
        }
        let enabled=clipboardContainsImage && !capturing && !recordingBusy && NSApp.modalWindow == nil
        clipboardButton?.isEnabled=enabled;editorPasteButton?.isEnabled=enabled
    }
    @discardableResult func importImage(from pasteboard:NSPasteboard)->Bool {
        guard NSImage.canInit(with:pasteboard),let source=NSImage(pasteboard:pasteboard),let image=normalized(source) else{return false}
        documentName=L("剪贴板图片");canvas.setImage(image);showEditor();return true
    }
    @objc func importClipboardImage(){
        refreshClipboardAvailability(force:true)
        guard clipboardContainsImage && !capturing && !recordingBusy && NSApp.modalWindow == nil else{return}
        _=importImage(from:.general)
    }
    @objc func openImage() {
        guard !capturing else{return}
        let restoreQuick=panel.isVisible
        let targetScreen=(restoreQuick ? panel.screen:window.screen) ?? NSScreen.main
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps:true)
        let p=NSOpenPanel();p.allowedContentTypes=[.image]
        p.level = .modalPanel
        p.setFrameAutosaveName("")
        func centerFilePanel() {
            guard let screen=targetScreen else{return}
            let available=screen.visibleFrame
            p.setFrameOrigin(NSPoint(x:available.midX-p.frame.width/2,y:available.midY-p.frame.height/2))
        }
        // Keep the panel centered when its remote browser finishes sizing.
        let resizeObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResizeNotification,object:p,queue:.main){_ in centerFilePanel()}
        defer {NotificationCenter.default.removeObserver(resizeObserver)}
        centerFilePanel()
        p.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {if p.isVisible {centerFilePanel()}}
        if p.runModal() == .OK,let url=p.url {load(url);showEditor()}
        else if restoreQuick {showPanel()}
    }
    @objc func toolChanged(_ sender:NSSegmentedControl){canvas.tool=Tool.allCases[sender.selectedSegment]}
    @objc func colorChanged(_ sender:NSColorWell){canvas.setColor(sender.color)}
    @objc func widthChanged(_ sender:NSSegmentedControl){canvas.setStroke([CGFloat(2),4,8][sender.selectedSegment]);window.makeFirstResponder(canvas)}
    @objc func undoEdit(){canvas.undoEdit()}
    @objc func redoEdit(){canvas.redoEdit()}
    @objc func copyImage(){guard let data=canvas.imageData() else{return};let pb=NSPasteboard.general;pb.clearContents();pb.setData(data,forType:.png);statusLabel.stringValue=L("已复制标注后的图片，可直接粘贴到聊天或文档")}
    @objc func saveImage(){guard canvas.image != nil else{return};let p=NSSavePanel();p.allowedContentTypes=[.png,.jpeg,.pdf];p.nameFieldStringValue=L("轻截")+"-\(timestamp()).png";p.canCreateDirectories=true
        if p.runModal() == .OK,let url=p.url {do{let data:Data?;if url.pathExtension.lowercased()=="pdf",let image=canvas.renderedImage(){let view=NSImageView(frame:NSRect(origin:.zero,size:image.size));view.image=image;data=view.dataWithPDF(inside:view.bounds)}else{data=canvas.imageData(["jpg","jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg:.png)};guard let data else{throw NSError(domain:"LightCapture",code:2,userInfo:[NSLocalizedDescriptionKey:L("图片导出失败")])};try data.write(to:url,options:.atomic);statusLabel.stringValue=LF("已保存：%@",url.lastPathComponent)}catch{self.error(error)}}
    }
    @objc func ocr(){guard let image=canvas.renderedImage()?.cgImage(forProposedRect:nil,context:nil,hints:nil) else{return};statusLabel.stringValue=L("正在本机识别文字…");DispatchQueue.global(qos:.userInitiated).async{let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["zh-Hans","en-US"];request.usesLanguageCorrection=true
        do{try VNImageRequestHandler(cgImage:image).perform([request]);let text=request.results?.compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n") ?? "";DispatchQueue.main.async{self.showText(text)}}catch{DispatchQueue.main.async{self.error(error)}}}}
    func showText(_ text:String) {let alert=NSAlert();alert.messageText=L("识别结果");alert.informativeText=L("可选中编辑，点击「复制文字」放入剪贴板。");let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:540,height:300));scroll.hasVerticalScroller=true;let v=NSTextView(frame:scroll.bounds);v.isEditable=true;v.font = .systemFont(ofSize:15);v.string=text;scroll.documentView=v;alert.accessoryView=scroll;alert.addButton(withTitle:L("复制文字"));alert.addButton(withTitle:L("关闭"));if alert.runModal() == .alertFirstButtonReturn {NSPasteboard.general.clearContents();NSPasteboard.general.setString(v.string,forType:.string)};statusLabel.stringValue=text.isEmpty ? L("未识别到文字"):L("文字识别完成")}
    @objc func pin(){guard let image=canvas.renderedImage() else{return};let scale=min(600/image.size.width,500/image.size.height,1);let w=NSWindow(contentRect:NSRect(x:140,y:160,width:image.size.width*scale,height:image.size.height*scale),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);w.title=L("轻截 · 参考贴图");w.level = .floating;w.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];w.isReleasedWhenClosed=false;let v=NSImageView();v.image=image;v.imageScaling = .scaleProportionallyUpOrDown;w.contentView=v;w.makeKeyAndOrderFront(nil);pins.append(w)}
    @objc func combine(){guard !capturing else{return};let p=NSOpenPanel();p.allowedContentTypes=[.image];p.allowsMultipleSelection=true;p.message=L("按文件名顺序纵向拼接；请选择至少两张图片。");guard p.runModal() == .OK,p.urls.count>1 else{return};let images=p.urls.sorted{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}.compactMap{NSImage(contentsOf:$0)}.compactMap{normalized($0)};guard images.count==p.urls.count else{message(L("拼接失败"),L("部分文件无法读取。"));return};let width=images.map{$0.size.width}.max() ?? 1,height=images.reduce(CGFloat(0)){$0+$1.size.height};guard width*height<80_000_000 else{message(L("图片过大"),L("拼接总像素需小于 8000 万，请先缩小图片。"));return};let result=NSImage(size:NSSize(width:width,height:height));result.lockFocusFlipped(true);NSColor.white.setFill();NSRect(x:0,y:0,width:width,height:height).fill();var y:CGFloat=0;for image in images{image.draw(in:NSRect(x:0,y:y,width:image.size.width,height:image.size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil);y+=image.size.height};result.unlockFocus();if let normalized=normalized(result){documentName=L("拼接图片");canvas.setImage(normalized)};statusLabel.stringValue=LF("已按文件名顺序拼接 %@ 张图片（保留重叠区域）",images.count)}
    @objc func toggleRecording(){
        guard !capturing else{return}
        guard !recordingBusy else{return}
        if recording {setRecordingBusy(true);Task { @MainActor in do{try await recorder.stop()}catch{self.error(error);self.resetRecording()}};return}
        setRecordingBusy(true)
        let setup=RecordingSetupController(willSelect:{self.window.orderOut(nil);self.panel.orderOut(nil)},didSelect:{self.panel.orderFrontRegardless()})
        guard let options=setup.run() else{setRecordingBusy(false);return}
        restoreQuickAfterRecording=panel.isVisible
        panel.orderOut(nil)
        Task{ @MainActor in
            do{
                try await Task.sleep(nanoseconds:250_000_000)
                try await recorder.start(to:options.url,audio:options.audio,target:options.target){result in
                    self.resetRecording()
                    switch result {
                    case .success(let saved):self.statusLabel.stringValue=LF("录屏已保存：%@",saved.lastPathComponent);NSWorkspace.shared.activateFileViewerSelecting([saved])
                    case .failure(let error):self.error(error)
                    }
                }
                recording=true;recordButton.title=L("停止录制");recordButton.toolTip=L("停止录制并保存视频");quickRecordButton.title="";quickRecordButton.setAccessibilityLabel(L("停止录制"));quickRecordButton.toolTip=L("停止录制并保存视频");quickRecordButton.image=NSImage(systemSymbolName:"stop.fill",accessibilityDescription:L("停止录制"));quickRecordButton.contentTintColor = .systemRed;setRecordingBusy(false)
                status.button?.image=NSImage(systemSymbolName:"record.circle.fill",accessibilityDescription:L("正在录屏"));status.button?.toolTip=L("正在录制 · 点击菜单停止录制")
                statusLabel.stringValue=LF("正在录制：%@ · %@",options.target.summary,options.audio.title)
            }catch{resetRecording();self.error(error)}
        }
    }
    func setRecordingBusy(_ busy:Bool){recordingBusy=busy;recordButton.isEnabled = !busy;quickRecordButton.isEnabled = !busy}
    func resetRecording(){recording=false;recordButton.title=L("录屏");recordButton.toolTip=L("屏幕录制");quickRecordButton.title="";quickRecordButton.setAccessibilityLabel(L("屏幕录制"));quickRecordButton.toolTip=L("屏幕录制");quickRecordButton.image=NSImage(systemSymbolName:"record.circle",accessibilityDescription:L("录屏设置"));quickRecordButton.contentTintColor=nil;setRecordingBusy(false);status.button?.image=NSImage(systemSymbolName:"viewfinder",accessibilityDescription:L("轻截"));status.button?.toolTip=L("轻截");let restore=restoreQuickAfterRecording;restoreQuickAfterRecording=false;if restore && !window.isVisible{showPanel()}}
    @objc func showEditor(){
        guard scrollCapture == nil else{return}
        panel.orderOut(nil)
        if let area=window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            var frame=window.frame
            frame.size.width=min(frame.width,area.width);frame.size.height=min(frame.height,area.height)
            frame.origin.x=max(area.minX,min(frame.minX,area.maxX-frame.width))
            frame.origin.y=max(area.minY,min(frame.minY,area.maxY-frame.height))
            window.setFrame(frame,display:false)
        }
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func keepPanelOnScreen(){
        guard let panel else{return}
        let origin=PanelPlacement.constrain(panel.frame.origin,size:panel.frame.size,screens:NSScreen.screens.map(\.visibleFrame))
        if origin != panel.frame.origin {panel.setFrameOrigin(origin)}
    }
    func windowDidMove(_ notification:Notification){
        guard let moved=notification.object as? NSWindow,moved === panel else{return}
        PanelPlacement.save(moved.frame.origin)
    }
    func applicationWillTerminate(_ notification:Notification){if let panel {PanelPlacement.save(panel.frame.origin)}}
    @objc func showPanel(){guard scrollCapture == nil else{return};keepPanelOnScreen();panel.orderFrontRegardless()}
    func windowShouldClose(_ sender:NSWindow)->Bool {if sender === window {panel.orderFrontRegardless()};return true}
    @objc func quit(){if recording {message(L("请先停止录制"),L("录屏保存完成后即可退出。"));return};NSApp.terminate(nil)}
    @objc func about(){
        let dialog=RegionPanel(contentRect:NSRect(x:0,y:0,width:340,height:280),styleMask:[.titled,.fullSizeContentView],backing:.buffered,defer:false)
        dialog.title=L("关于轻截");dialog.titleVisibility = .hidden;dialog.titlebarAppearsTransparent=true;dialog.isReleasedWhenClosed=false;dialog.hasShadow=true;dialog.appearance=NSAppearance(named:.aqua)
        let root=NSStackView();root.orientation = .vertical;root.alignment = .centerX;root.spacing=18;root.translatesAutoresizingMaskIntoConstraints=false
        let content=dialog.contentView!;content.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),root.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),root.topAnchor.constraint(equalTo:content.topAnchor,constant:24),root.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-20)])
        let icon=NSImageView();icon.image=NSApp.applicationIconImage;icon.imageScaling = .scaleProportionallyUpOrDown;icon.setAccessibilityLabel(L("轻截"))
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant:64),icon.heightAnchor.constraint(equalToConstant:64)])
        root.addArrangedSubview(icon)
        let title=NSTextField(labelWithString:L("轻截 LightCapture 0.6.24"));title.font = .systemFont(ofSize:15,weight:.bold)
        let text=NSTextField(wrappingLabelWithString:L("区域／窗口／全屏：⌥⌘2／4／3\n图片复制：⇧⌘C；保存：⌘S\n截图与录屏需在系统设置中允许屏幕录制。"));text.font = .systemFont(ofSize:13);text.preferredMaxLayoutWidth=292
        root.addArrangedSubview(title);root.addArrangedSubview(text)
        let ok=NSButton(title:L("好"),target:self,action:#selector(dismissAbout));ok.bezelStyle = .rounded;ok.keyEquivalent="\r";root.addArrangedSubview(ok)
        for view in [title,text,ok] {view.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true}
        ok.heightAnchor.constraint(equalToConstant:32).isActive=true
        content.layoutSubtreeIfNeeded();dialog.setContentSize(NSSize(width:340,height:root.fittingSize.height+44));dialog.center()
        NSApp.activate(ignoringOtherApps:true);dialog.makeKeyAndOrderFront(nil);NSApp.runModal(for:dialog);dialog.close()
    }
    @objc func dismissAbout(){NSApp.stopModal()}
    func message(_ title:String,_ text:String){let a=NSAlert();a.icon=NSApp.applicationIconImage;a.messageText=title;a.informativeText=text;a.runModal()}
    func error(_ error:Error){message(L("操作未完成"),error.localizedDescription)}
    func timestamp()->String{let f=DateFormatter();f.dateFormat="yyyyMMdd-HHmmss";return f.string(from:Date())}
    func testEditableObjects() {
        let c=Canvas(frame:NSRect(x:0,y:0,width:848,height:548))
        c.setImage(NSImage(size:NSSize(width:800,height:500)))
        c.marks=[Mark(tool:.arrow,points:[NSPoint(x:100,y:100),NSPoint(x:250,y:180)],color:.red,width:4)]
        assert(c.hitMark(NSPoint(x:175,y:140))==0)
        assert(c.hitMark(NSPoint(x:350,y:300))==nil)
        c.selectMark(0)
        assert(c.beginObjectDrag(at:NSPoint(x:175,y:140)))
        c.dragObject(to:NSPoint(x:195,y:170));c.dragObject(to:NSPoint(x:215,y:180));c.endObjectDrag()
        assert(c.marks[0].points[0]==NSPoint(x:140,y:140))
        assert(c.history.count==1)
        c.undoEdit();assert(c.marks[0].points[0]==NSPoint(x:100,y:100))
        c.redoEdit();c.selectMark(0)
        assert(c.beginObjectDrag(at:c.marks[0].points[1]))
        c.dragObject(to:NSPoint(x:400,y:80));c.endObjectDrag()
        assert(c.marks[0].points[0]==NSPoint(x:140,y:140))
        assert(c.marks[0].points[1]==NSPoint(x:400,y:80))
        c.setColor(.blue);assert(c.marks[0].color.isEqual(NSColor.blue))
        c.setStroke(8);assert(c.marks[0].width==8)
        c.undoEdit();assert(c.marks[0].width==4)
        c.selectMark(0)
        let selected=c.imageData()!;c.clearSelection();assert(selected==c.imageData()!)
        for shape in [Tool.box,.oval,.highlight,.redact] {
            c.marks=[Mark(tool:shape,points:[NSPoint(x:100,y:100),NSPoint(x:200,y:200)],color:.red,width:4)]
            c.selectMark(0);assert(c.beginObjectDrag(at:NSPoint(x:100,y:100)))
            c.dragObject(to:NSPoint(x:80,y:60));c.endObjectDrag()
            assert(c.markBounds(c.marks[0])==NSRect(x:80,y:60,width:120,height:140))
            c.deleteSelection();assert(c.marks.isEmpty)
            c.undoEdit();assert(c.marks.count==1);c.redoEdit();assert(c.marks.isEmpty)
        }
        for shape in [Tool.pen,.text,.step] {
            let a=NSPoint(x:100,y:100)
            c.marks=[Mark(tool:shape,points:shape == .pen ? [a,NSPoint(x:150,y:150)]:[a],color:.red,width:4,text:"Test")]
            c.selectMark(0);assert(c.beginObjectDrag(at:a));c.dragObject(to:NSPoint(x:120,y:130));c.endObjectDrag()
            assert(c.marks[0].points[0]==NSPoint(x:120,y:130))
        }
    }
    func testRegionCancellation(){
        func event(_ type:NSEvent.EventType,_ x:CGFloat=40,_ y:CGFloat=40)->NSEvent {
            NSEvent.mouseEvent(with:type,location:NSPoint(x:x,y:y),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        }
        func fixture()->RegionView {
            let view=RegionView(frame:NSRect(x:0,y:0,width:400,height:300));view.cancelWithRightMouse=true;return view
        }
        for kind in [NSEvent.EventType.rightMouseDown,.rightMouseDragged,.rightMouseUp] {
            let view=fixture();var calls=0;var captured=false
            view.finished={rect in calls+=1;captured=rect != nil}
            view.mouseDown(with:event(.leftMouseDown));view.mouseDragged(with:event(.leftMouseDragged,160,140))
            switch kind {
            case .rightMouseDown:view.rightMouseDown(with:event(kind))
            case .rightMouseDragged:view.rightMouseDragged(with:event(kind))
            default:view.rightMouseUp(with:event(kind))
            }
            view.mouseUp(with:event(.leftMouseUp,160,140));view.rightMouseUp(with:event(.rightMouseUp))
            assert(calls==1 && !captured)
        }
        let left=fixture();var rect:CGRect?
        left.finished={rect=$0};left.mouseDown(with:event(.leftMouseDown));left.mouseDragged(with:event(.leftMouseDragged,160,140));left.mouseUp(with:event(.leftMouseUp,160,140))
        assert(rect?.width==120 && rect?.height==100)
        let escape=fixture();var cancelled=false;escape.finished={cancelled=$0 == nil}
        escape.keyDown(with:NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!)
        assert(cancelled)
        assert(RegionView.screenCaptureRect(CGRect(x:20,y:30,width:200,height:100),desktop:CGRect(x:-1000,y:-900,width:3000,height:2000),mainTop:900)==CGRect(x:-980,y:-170,width:200,height:100))
    }
    func testWindowCancellation(){
        let front=CGRect(x:20,y:20,width:100,height:80),back=CGRect(x:0,y:0,width:300,height:200)
        assert(WindowCaptureView.target(at:NSPoint(x:40,y:40),in:[front,back])==front)
        assert(WindowCaptureView.target(at:NSPoint(x:200,y:100),in:[front,back])==back)
        assert(WindowCaptureView.target(at:NSPoint(x:500,y:500),in:[front,back])==nil)
        func event(_ type:NSEvent.EventType)->NSEvent {NSEvent.mouseEvent(with:type,location:NSPoint(x:40,y:40),modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
        for kind in [NSEvent.EventType.rightMouseDown,.rightMouseDragged,.rightMouseUp] {
            let view=WindowCaptureView(frame:NSRect(x:0,y:0,width:400,height:300));view.targets=[front,back];view.desktop=view.bounds;view.mainTop=300
            var calls=0;var captured=false;view.finished={calls+=1;captured=$0 != nil}
            switch kind {
            case .rightMouseDown:view.rightMouseDown(with:event(kind))
            case .rightMouseDragged:view.rightMouseDragged(with:event(kind))
            default:view.rightMouseUp(with:event(kind))
            }
            view.mouseDown(with:event(.leftMouseDown));assert(calls==1 && !captured)
        }
        let view=WindowCaptureView(frame:NSRect(x:0,y:0,width:400,height:300));view.targets=[view.bounds];view.desktop=view.bounds;view.mainTop=300
        var rect:CGRect?;view.finished={rect=$0};view.mouseDown(with:event(.leftMouseDown));assert(rect==view.bounds)
    }
    func testSelectionMouseSurface(){
        func alpha(_ view:NSView,_ x:Int,_ y:Int)->CGFloat {
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:400,pixelsHigh:300,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
            view.draw(view.bounds);NSGraphicsContext.restoreGraphicsState()
            return rep.colorAt(x:x,y:y)!.alphaComponent
        }
        let window=WindowCaptureView(frame:NSRect(x:0,y:0,width:400,height:300));window.desktop=window.bounds;window.mainTop=300;window.selected=CGRect(x:30,y:60,width:220,height:180)
        let windowAlpha=alpha(window,100,150);assert(windowAlpha>0.01 && windowAlpha<0.1)
        let region=RegionView(frame:window.bounds);region.selection=CGRect(x:30,y:60,width:220,height:180)
        let regionAlpha=alpha(region,100,150);assert(regionAlpha>0.01 && regionAlpha<0.1)
    }
    func testClipboardImport(){
        let pb=NSPasteboard.withUniqueName();defer{pb.releaseGlobally()}
        precondition(pb.name != NSPasteboard.general.name, "Test pasteboard must never be the general clipboard")
        assert(!NSImage.canInit(with:pb))
        let original=canvas.image
        pb.setString("plain text",forType:.string)
        assert(!NSImage.canInit(with:pb));assert(!importImage(from:pb));assert(canvas.image === original)
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:32,pixelsHigh:24,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        for y in 0..<24 {for x in 0..<32 {rep.setColor(NSColor(calibratedRed:0.2,green:0.6,blue:0.9,alpha:1),atX:x,y:y)}}
        pb.clearContents();pb.setData(rep.representation(using:.png,properties:[:])!,forType:.png)
        assert(NSImage.canInit(with:pb));assert(importImage(from:pb));assert(canvas.image?.size==NSSize(width:32,height:24));assert(documentName==L("剪贴板图片"));assert(!panel.isVisible && window.isVisible)
        pb.clearContents();pb.setData(rep.tiffRepresentation!,forType:.tiff)
        assert(importImage(from:pb));assert(canvas.image?.size==NSSize(width:32,height:24))
        pb.clearContents();assert(!importImage(from:pb));assert(canvas.image?.size==NSSize(width:32,height:24))
    }
    func testPanelPlacement(){
        let suite="LightCapture.PanelPlacementTest."+UUID().uuidString
        let prefs=UserDefaults(suiteName:suite)!;defer{prefs.removePersistentDomain(forName:suite)}
        let screen=NSRect(x:0,y:0,width:1440,height:900),size=NSSize(width:260,height:56),position=NSPoint(x:520,y:420)
        let fallback=NSPoint(x:80,y:800)
        assert(PanelPlacement.restore(size:size,screens:[screen],fallback:fallback,defaults:prefs)==fallback)
        PanelPlacement.save(position,defaults:prefs)
        let reopened=UserDefaults(suiteName:suite)!
        assert(PanelPlacement.restore(size:size,screens:[screen],fallback:fallback,defaults:reopened)==position)
        PanelPlacement.save(NSPoint(x:2200,y:1200),defaults:prefs)
        assert(PanelPlacement.restore(size:size,screens:[screen],fallback:fallback,defaults:prefs)==NSPoint(x:1180,y:844))
        let left=NSRect(x:-1440,y:0,width:1440,height:900)
        assert(PanelPlacement.constrain(NSPoint(x:-800,y:300),size:size,screens:[left,screen])==NSPoint(x:-800,y:300))
        prefs.set(["x":"invalid","y":2],forKey:PanelPlacement.key)
        assert(PanelPlacement.restore(size:size,screens:[screen],fallback:fallback,defaults:prefs)==fallback)
    }
    func selfTest(){DispatchQueue.main.asyncAfter(deadline:.now()+0.4){self.testEditableObjects();self.testRegionCancellation();self.testWindowCancellation();self.testSelectionMouseSurface();self.testClipboardImport();self.testPanelPlacement();testScrollStitcher();let image=NSImage(size:NSSize(width:800,height:500));image.lockFocusFlipped(true);NSColor.white.setFill();NSRect(x:0,y:0,width:800,height:500).fill();"LightCapture 轻截".draw(at:NSPoint(x:60,y:50),withAttributes:[.font:NSFont.systemFont(ofSize:40),.foregroundColor:NSColor.black]);NSColor.systemBlue.setFill();NSRect(x:80,y:180,width:240,height:130).fill();image.unlockFocus();self.canvas.setImage(self.normalized(image)!);self.canvas.checkpoint();self.canvas.marks=[Mark(tool:.arrow,points:[NSPoint(x:500,y:120),NSPoint(x:310,y:230)],color:.systemRed,width:5),Mark(tool:.redact,points:[NSPoint(x:440,y:300),NSPoint(x:650,y:350)],color:.black,width:4),Mark(tool:.text,points:[NSPoint(x:400,y:380)],color:.systemRed,width:4,text:"本机处理 / Local only")];let path=ProcessInfo.processInfo.environment["LIGHTCAPTURE_TEST_OUTPUT"] ?? "/tmp/lightcapture-selftest.png";try? self.canvas.imageData()?.write(to:URL(fileURLWithPath:path));self.canvas.undoEdit();assert(self.canvas.marks.isEmpty);self.canvas.redoEdit();assert(self.canvas.marks.count==3);self.statusLabel.stringValue="自检通过：绘制、导出、撤销、重做";let data=self.canvas.imageData()!
        let bitmap=NSBitmapImageRep(data:data)!
        assert(bitmap.pixelsWide==Int(self.canvas.image!.size.width))
        let black=bitmap.colorAt(x:450,y:320)!.usingColorSpace(.deviceRGB)!
        assert(black.redComponent<0.01 && black.greenComponent<0.01 && black.blueComponent<0.01)
        self.canvas.zoomScale=2;self.updateCanvasLayout()
        assert(NSBitmapImageRep(data:self.canvas.imageData()!)!.pixelsWide==bitmap.pixelsWide)
        let viewPoint=self.canvas.imageRect.origin
        assert(viewPoint.x>=0 && viewPoint.y>=0)
        self.canvas.zoomScale=nil;self.updateCanvasLayout()
        let jpeg=self.canvas.imageData(.jpeg)!
        assert(NSBitmapImageRep(data:jpeg) != nil)
        let request=VNRecognizeTextRequest();request.recognitionLanguages=["zh-Hans","en-US"];request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage:bitmap.cgImage!).perform([request])
        let recognized=request.results?.compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n") ?? ""
        assert(recognized.contains("LightCapture"))
        let result:[String:Any]=["status":"PASS","png_dimensions":[bitmap.pixelsWide,bitmap.pixelsHigh],"checks":["PNG export","JPEG export","opaque redaction pixels","undo","redo","zoom preserves export dimensions","Vision OCR","annotation hit testing","object move","arrow endpoint editing","four shape resize types","selection excluded from export","style editing","delete and undo/redo","pen text step movement","right click/drag/release cancel without capture","left drag confirms region","Escape cancels region","multi-display capture coordinates","window right-click cancellation","left click confirms selected window","frontmost window hit testing","window selected area retains nonzero alpha","region selected area retains nonzero alpha","empty and text clipboard rejected without replacing image","PNG and TIFF clipboard import preserves pixel dimensions","clipboard import opens editor and hides quick bar","clipboard tests do not modify system clipboard","quick panel position persists across defaults instances","offscreen panel is constrained to a visible display","negative-coordinate display placement","invalid position falls back safely","scroll stitch exact overlap and partial final step","scroll stitch pixel-exact output","scroll unchanged and incompatible frames rejected","scroll unrelated content rejected"],"quick_panel_origin":[self.panel.frame.minX,self.panel.frame.minY],"ocr":recognized]
        let report=try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        try! report.write(to:URL(fileURLWithPath:path+".json"))
        if CommandLine.arguments.contains("--test-exit") {NSApp.terminate(nil)}}}
}
let app=NSApplication.shared
let delegate=App()
app.delegate=delegate
app.run()
