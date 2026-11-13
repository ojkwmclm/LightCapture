import AppKit
import Darwin

// Keep the inode in place: unlinking a held lock would allow two owners.
final class InstanceLock {
    private let descriptor:Int32
    init?(path:String) {
        descriptor=open(path,O_CREAT|O_RDWR|O_NOFOLLOW,mode_t(0o600))
        guard descriptor>=0 else{return nil}
        guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else{close(descriptor);return nil}
        let pid=Data(String(getpid()).utf8)
        _=ftruncate(descriptor,0);pid.withUnsafeBytes{_ = write(descriptor,$0.baseAddress,$0.count)}
    }
    deinit{_ = flock(descriptor,LOCK_UN);close(descriptor)}
}
final class SingleInstance {
    static let wakeNotification=Notification.Name("local.lightcapture.showQuickCapture")
    var lock:InstanceLock?
    func claim()->Bool {
        // Self-tests have their own identity and never wake a user's application.
        if CommandLine.arguments.contains("--self-test") {return true}
        let identifier=Bundle.main.bundleIdentifier ?? "local.lightcapture.app"
        let name=identifier.map{$0.isLetter || $0.isNumber ? String($0):"_"}.joined()
        lock=InstanceLock(path:NSTemporaryDirectory()+"LightCapture-"+name+".lock")
        let others=NSRunningApplication.runningApplications(withBundleIdentifier:identifier).filter{$0.processIdentifier != getpid() && !$0.isTerminated}.sorted{($0.launchDate ?? .distantFuture)<($1.launchDate ?? .distantFuture)}
        if let existing=others.first(where:{self.lock == nil || $0.isFinishedLaunching}) {
            lock=nil
            DistributedNotificationCenter.default().postNotificationName(Self.wakeNotification,object:String(existing.processIdentifier),userInfo:["bundleIdentifier":identifier],deliverImmediately:true)
            if let url=existing.bundleURL {
                let config=NSWorkspace.OpenConfiguration();config.createsNewApplicationInstance=false;config.activates=true
                var done=false
                NSWorkspace.shared.openApplication(at:url,configuration:config){_,_ in done=true}
                let deadline=Date().addingTimeInterval(2)
                while !done && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
            }else{existing.activate(options:[])}
            return false
        }
        // A simultaneous launch may own the lock before AppKit registers it.
        guard lock != nil else {
            for _ in 0..<20 {
                DistributedNotificationCenter.default().postNotificationName(Self.wakeNotification,object:nil,userInfo:["bundleIdentifier":identifier],deliverImmediately:true)
                Thread.sleep(forTimeInterval:0.05)
            }
            return false
        }
        return true
    }
}
func testInstanceLock(){
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("LightCapture-instance-test-"+UUID().uuidString)
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let path=directory.appendingPathComponent("instance.lock").path
    var first:InstanceLock?=InstanceLock(path:path);assert(first != nil)
    let process=Process();process.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);process.arguments=["--instance-lock-probe",path]
    try! process.run();process.waitUntilExit();assert(process.terminationStatus==3)
    first=nil
    let next=Process();next.executableURL=process.executableURL;next.arguments=process.arguments
    try! next.run();next.waitUntilExit();assert(next.terminationStatus==0)
}
