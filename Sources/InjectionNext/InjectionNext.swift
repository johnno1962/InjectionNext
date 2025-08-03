//
//  InjectionNext.swift
//  InjectionNext Package
//
//  Created by John Holdsworth on 30/05/2024.
//
//  Client app side of injection using implementation of InjectionLite.
//
#if DEBUG || !SWIFT_PACKAGE
import Foundation
#if canImport(InjectionImpl)
import InjectionImpl
#endif
#if canImport(InjectionNextC)
@_exported import InjectionNextC
#endif

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
        #if targetEnvironment(simulator) || os(macOS)
        super.write(NSHomeDirectory())
        #else
        if let bazelWorkspace = getenv(BUILD_WORKSPACE_DIRECTORY) {
            super.write(String(cString: bazelWorkspace))
        } else {
            super.write(INJECTION_KEY)
        }
        #endif

        // Find client platform
        #if os(macOS) || targetEnvironment(macCatalyst)
        var platform = "Mac"
        #elseif os(tvOS)
        var platform = "AppleTV"
        #elseif os(visionOS)
        var platform = "XR"
        #elseif os(watchOS)
        var platform = "Watch"
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
        if let projectRoot = getenv(INJECTION_PROJECT_ROOT) ??
                           getenv(BUILD_WORKSPACE_DIRECTORY) {
            writeCommand(InjectionResponse.projectRoot.rawValue,
                         with: String(cString: projectRoot))
        }
        writeCommand(InjectionResponse.tmpPath.rawValue, with: NSTemporaryDirectory())
        if let detail = getenv(INJECTION_DETAIL) {
            writeCommand(InjectionResponse.detail.rawValue,
                         with: String(cString: detail))
        }

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
                return error("Connection did not validate.")
            case .log:
                if let msg = readString() {
                    print(msg)
                }
            case .xcodePath:
                if let xcodePath = readString() {
                    log("Xcode path: "+xcodePath)
                    Reloader.xcodeDev = xcodePath+"/Contents/Developer"
                }
            case .sendFile:
                guard let path = readString() else {
                    return error("Unable to read path")
                }
                if path.hasSuffix("/") {
                    mkdir(path, 0o755)
                    continue
                }
                recvFile(path)
            case .load:
                guard let dylib = readString() else {
                    return error("Unable to read path")
                }
                injectAndSweep(dylib)
            case .inject:
                guard let dylibName = readString(), let data = readData() else {
                    return error("Unable to read dylib")
                }
                let dylib = NSTemporaryDirectory() + dylibName
                try! data.write(to: URL(fileURLWithPath: dylib))
                injectAndSweep(dylib)
            case .EOF:
                return
            default:
                return error("**** @unknown case \(commandInt) ****")
            }
        }
    }
}
#endif
