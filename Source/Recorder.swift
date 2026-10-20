import AppKit
import ScreenCaptureKit
import AVFoundation

enum RecordingAudio: Int, CaseIterable {
    case none, system, microphone, both
    var title: String { [L("不录声音"), L("电脑声音"), L("麦克风"), L("电脑声音＋麦克风")][rawValue] }
    var includesSystem: Bool { self == .system || self == .both }
    var includesMicrophone: Bool { self == .microphone || self == .both }
}

@available(macOS 15.0, *)
final class Recorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    var stream: SCStream?
    var output: SCRecordingOutput?
    var finished: (@MainActor (Result<URL,Error>)->Void)?
    var url: URL?
    func start(to url:URL, audio:RecordingAudio = .none, target:RecordingTarget, completion:@escaping @MainActor (Result<URL,Error>)->Void) async throws {
        if audio.includesMicrophone {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for:.audio) {
            case .authorized: allowed=true
            case .notDetermined: allowed=await AVCaptureDevice.requestAccess(for:.audio)
            default: allowed=false
            }
            guard allowed else {
                throw NSError(domain:"LightCapture",code:3,userInfo:[NSLocalizedDescriptionKey:L("未获得麦克风权限。请在系统设置 → 隐私与安全性 → 麦克风中允许轻截，或选择电脑声音／不录声音。")])
            }
        }
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        let excluded=content.applications.filter{$0.processID == getpid()}
        let filter:SCContentFilter
        var crop:CGRect?
        switch target {
        case .display(let chosen,let selectedRect):
            guard let display=content.displays.first(where:{$0.displayID==chosen.displayID}) else{throw NSError(domain:"LightCapture",code:5,userInfo:[NSLocalizedDescriptionKey:L("目标显示器已断开，请重新选择。")])}
            filter=SCContentFilter(display:display,excludingApplications:excluded,exceptingWindows:[])
            if let selectedRect {
                let clipped=selectedRect.intersection(CGRect(origin:.zero,size:display.frame.size))
                guard !clipped.isNull,clipped.width>=16,clipped.height>=16 else{throw NSError(domain:"LightCapture",code:6,userInfo:[NSLocalizedDescriptionKey:L("录制区域已超出屏幕，请重新选择。")])}
                crop=clipped
            }
        case .window(let chosen):
            guard let window=content.windows.first(where:{$0.windowID==chosen.windowID}) else{throw NSError(domain:"LightCapture",code:7,userInfo:[NSLocalizedDescriptionKey:L("目标窗口已关闭，请重新选择。")])}
            filter=SCContentFilter(desktopIndependentWindow:window)
        }
        let size=crop?.size ?? filter.contentRect.size
        let scale=CGFloat(filter.pointPixelScale)
        let config=SCStreamConfiguration()
        config.width=max(2,Int(size.width*scale)/2*2);config.height=max(2,Int(size.height*scale)/2*2)
        if let crop {config.sourceRect=crop}
        config.ignoreShadowsSingleWindow=true
        config.minimumFrameInterval=CMTime(value:1,timescale:30);config.showsCursor=true;config.capturesAudio=audio.includesSystem
        config.captureMicrophone=audio.includesMicrophone
        config.excludesCurrentProcessAudio=true
        config.sampleRate=48000;config.channelCount=2
        let recording=SCRecordingOutputConfiguration();recording.outputURL=url;recording.videoCodecType = .h264;recording.outputFileType = .mp4
        if #available(macOS 27.0, *) {recording.mixesAudioWithMicrophone=true}
        let output=SCRecordingOutput(configuration:recording,delegate:self)
        let stream=SCStream(filter:filter,configuration:config,delegate:self)
        self.finished=completion;self.url=url;self.output=output;self.stream=stream
        try stream.addRecordingOutput(output);try await stream.startCapture()
    }
    func stop() async throws {try await stream?.stopCapture()}
    func recordingOutputDidFinishRecording(_ recordingOutput:SCRecordingOutput) {if let url {DispatchQueue.main.async{self.finished?(.success(url));self.finished=nil;self.stream=nil;self.output=nil}}}
    func recordingOutput(_ recordingOutput:SCRecordingOutput,didFailWithError error:Error) {DispatchQueue.main.async{self.finished?(.failure(error));self.finished=nil;self.stream=nil;self.output=nil}}
    func stream(_ stream:SCStream,didStopWithError error:Error) {DispatchQueue.main.async{self.finished?(.failure(error));self.finished=nil;self.stream=nil;self.output=nil}}
}
