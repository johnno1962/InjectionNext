//
//  InjectionNext.swift
//  InjectionNext Package
//
//  Created by John Holdsworth on 30/05/2024.
//
//  Client app side of injection using implementation of InjectionLite.
//
#if DEBUG || !SWIFT_PACKAGE
#if canImport(InjectionImpl)
import InjectionImpl
#endif
@_exported import InjectionNextC

@objc(InjectionNext)
open class InjectionNext: SimpleSocket {
    
    func log(_ msg: String) {
        print(APP_PREFIX+APP_NAME+": "+msg)
    }
    func error(_ msg: String) {
        log("⚠️ "+msg)
    }
    
    /// Connection from client app opened in ClientBoot.mm arrives here
    open override func runInBackground() {
        super.write(INJECTION_VERSION)
        super.write(INJECTION_KEY)
        
        // Find client platform
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
        
        // Let server side know the platform and architecture
        writeCommand(InjectionResponse.platform.rawValue, with: platform)
        super.write(arch)
        writeCommand(InjectionResponse.tmpPath.rawValue, with: NSTemporaryDirectory())

        log("\(platform) connection to app established, waiting for commands.")
        processCommandsFromApp()
        log("Connection lost, disconnecting.")
    }
        
    func processCommandsFromApp() {
        var loader = Reloader() // InjectionLite injection implementation
        func injectAndSweep(_ dylib: String) {
            Reloader.injectionNumber += 1
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
            case .EOF:
                return
            default:
                error("**** @unknown case ****")
                return
            }
        }
    }
}
#endif
