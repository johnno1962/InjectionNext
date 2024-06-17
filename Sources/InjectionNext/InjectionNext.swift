// The Swift Programming Language
// https://docs.swift.org/swift-book

#if DEBUG
import InjectionImpl
import InjectionNextC

@objc(InjectionNext)
open class InjectionNext: SimpleSocket {
    
    func log(_ msg: String) {
        print(APP_PREFIX+APP_NAME+": "+msg)
    }
    func error(_ msg: String) {
        log("⚠️ "+msg)
    }
    
    open override func runInBackground() {
        super.write(INJECTION_VERSION)
        super.write(INJECTION_KEY)
        
        #if os(macOS) || targetEnvironment(macCatalyst)
        var platform = "Mac"
        #elseif os(tvOS)
        var platform = "AppleTV"
        #elseif os(visionOS)
        var platform = "XR"
        #else
        var platform = "iPhone"
        #endif
        
        #if targetEnvironment(simulator)
        platform += "Simulator"
        #else
        platform += "OS"
        #endif
        #if os(macOS)
        platform += "X"
        #endif
        
        Reloader.platform = platform
        
        #if arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "arm64"
        #endif
        
        writeCommand(InjectionResponse.platform.rawValue, with: platform)
        super.write(arch)
        writeCommand(InjectionResponse.tmpPath.rawValue, with: NSTemporaryDirectory())

        log("\(platform) connection to app established, waiting for commands.")
        processCommands()
        log("Connection lost, disconnecting.")
    }
        
    func processCommands() {
        var loader = Reloader()
        func injectAndSweep(_ dylib: String) {
            var succeeded = false
            if let (image, classes) = Reloader.injectionQueue
                .sync(execute: { loader.loadAndPatch(in: dylib) }) {
                loader.sweeper.sweepAndRunTests(image: image, classes: classes)
                succeeded = true
            } else {
                writeCommand(InjectionResponse.unhide.rawValue, with: nil)
            }
            writeCommand(succeeded ? InjectionResponse.injected.rawValue :
                            InjectionResponse.failed.rawValue, with: nil)
        }
        while true {
            let commandInt = readInt()
            guard let command = InjectionCommand(rawValue: commandInt) else {
                error("Invalid command rawValue: \(commandInt)")
                break
            }
            switch command {
            case .invalid:
                error("Connection did not validate.")
                return
            case .log:
                if let msg = readString() {
                    print(msg)
                }
            case .xcodePath:
                if let xcodePath = readString() {
                    Reloader.xcodeDev = xcodePath+"/Contents/Developer"
                }
            case .load:
                guard let dylib = readString() else {
                    error("Unable to read path")
                    return
                }
                injectAndSweep(dylib)
            case .inject:
                guard let dylibName = readString(), let data = readData() else {
                    error("Unable to read dylib")
                    return
                }
                let dylib = NSTemporaryDirectory() + dylibName
                try! data.write(to: URL(fileURLWithPath: dylib))
                injectAndSweep(dylib)
            default:
                error("**** @unknown case ****")
                return
            }
        }
    }
}
#endif
