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
    
    override class open func error(_ message: String) -> Int32 {
        let msg = String(format: message, strerror(errno))
        print(APP_PREFIX+APP_NAME+": "+msg)
        if errno == EHOSTUNREACH { // No route to host
            print("ℹ️ "+APP_NAME+": Accept permission prompt on device.")
        }
        return errno
    }

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
        if let bazelTarget = getenv(INJECTION_BAZEL_TARGET) {
            writeCommand(InjectionResponse.bazelTarget.rawValue,
                         with: String(cString: bazelTarget))
        }
        if let executable = Bundle.main.executablePath {
            writeCommand(InjectionResponse.executable.rawValue,
                         with: executable)
        }

        Reloader.injectionQueue.sync {
            tracingOptions()
        }

        log("\(arch) \(platform) connected to app, waiting for commands.")
        #if !SWIFT_PACKAGE
        if let build = Bundle(for: Self.self)
            .infoDictionary?["CFBundleVersion"] as? String {
            detail("Bundle build #"+build)
        }
        #endif
        processCommandsFromApp()
        log("Connection lost, disconnecting.")
    }
    
    func tracingOptions() {
        SwiftTrace.injectableSymbol = Reloader.injectableSymbol
        SwiftTrace.defaultMethodExclusions += // CoreFoundation
            #"|\[NS(Method|Tagged|Array|\w*Dict|Date|Data|Timer)|allocWithZone:|__unurl|_trueSelf"#
          + #"|InjectionBundle.|fast_dl"#
        for name in [INJECTION_TRACE_LOOKUP, INJECTION_TRACE_FILTER, INJECTION_TRACE_ALL,
                     INJECTION_TRACE_FRAMEWORKS, INJECTION_TRACE_UIKIT, INJECTION_TRACE] {
            if let value = getenv(name) {
                setVariable(name: name, to: String(cString: value), first: true)
            }
        }
    }
 
    func setVariable(name: String, to value: String, first: Bool) {
        let wasSet = getenv(name) != nil
        if name == INJECTION_DLOPEN_MODE, let mode = Int32(value) {
            DLKit.dlOpenMode = mode
        } else if name == INJECTION_TRACE_FILTER {
            if value == UNSETENV_VALUE {
                if wasSet {
                    SwiftTrace.traceFilterInclude = "."
                }
            } else {
                SwiftTrace.traceFilterInclude = value
            }
        }
        if value == UNSETENV_VALUE {
            unsetenv(name)
            return
        }
        
        setenv(name, value, 1)
        if !first && wasSet {
            return
        }

        switch name {
        /// Custom type lookup on tracing.
        case INJECTION_TRACE_LOOKUP:
            if value.hasPrefix("|") {
                SwiftTrace.defaultLookupExclusions += value
            }
            SwiftTrace.typeLookup = true
        /// Entire App bundle tracing.
        case INJECTION_TRACE_ALL:
            if value.hasPrefix("|") {
                SwiftTrace.defaultMethodExclusions += value
            }
            SwiftTrace.interposeEclusions = SwiftTrace.exclusionRegexp
            appBundleImages { imageName, _, _ in
                if SwiftTrace.interposeMethods(inBundlePath: imageName) == 0,
                   strstr(imageName, "XCT") == nil {
                    self.error("""
                            Unable to interpose to trace image \
                            \(String(cString: imageName)), have you added \
                            "Other Linker Flags" -Xlinker -interposable
                            """)
                }
                SwiftTrace.trace(bundlePath: imageName)
            }
        /// Trace calls to framework e.g. SwiftUI,SwiftUICore
        case INJECTION_TRACE_FRAMEWORKS:
            traceCalls(toFrameworks: value, images: DLKit.appImages.imageList)
        /// Trace UIKit internals using swizzling
        case INJECTION_TRACE_UIKIT:
            var frmwks = value
            if frmwks == "" || frmwks == "1" { frmwks = "UIKitCore" }
            for frmwk in frmwks.components(separatedBy: ",") {
                if let bundle = DLKit.imageMap[frmwk]?.imageName {
                    SwiftTrace.trace(bundlePath: bundle)
                } else {
                    error("Invalid swizzle framework \(frmwk)")
                }
            }
        /// Function and class method tracing on injection.
        case INJECTION_TRACE:
            Reloader.traceHook = { (injected, name) in
                let name = SwiftMeta.demangle(symbol: name) ?? String(cString: name)
                detail("SwiftTracing \(name)")
                return autoBitCast(SwiftTrace.trace(name: name, original: injected)) ?? injected
            }
        default:
            break
        }
    }
    
    func traceCalls(toFrameworks: String, images: [ImageSymbols]) {
        var frmwks = toFrameworks
        if frmwks == "" || frmwks == "1" { frmwks = "SwiftUI,SwiftUICore" }
        for frmwk in frmwks.components(separatedBy: ",") {
            if let dylib = DLKit.imageMap[frmwk] {
                Self.target = dylib
                for image in images {
                    detail("Tracing image \(image)")
                    rebind_symbols_trace(autoBitCast(image.imageHeader),
                                         image.imageSlide, Self.tracer)
                }
            } else {
                error("Invalid trace framework \(frmwk)")
            }
        }
    }

    static var target: ImageSymbols?
    static var tracer: STTracer = { existing, symname in
        var traced = existing
        if SwiftTrace.injectableSymbol(symname),
           let info = trie_iterator(existing),
           target?.imageHeader == info.pointee.header,
           let name = SwiftMeta.demangle(symbol: symname) {
            detail("Tracing \(name) \(existing)")
            traced = autoBitCast(SwiftTrace
                .trace(name: "   "+name, original: existing)) ?? existing
        }
        return traced
    }

    func processCommandsFromApp() {
        var loader = Reloader() // InjectionLite injection implementation
        func injectAndSweep(_ dylib: String) {
            Reloader.injectionNumber += 1
            var succeeded = false
            if let (image, classes) = Reloader.injectionQueue
                .sync(execute: { loader.loadAndPatch(in: dylib) }) {
                if let tracing = getenv(INJECTION_TRACE_FRAMEWORKS) {
                    traceCalls(toFrameworks: String(cString: tracing),
                               images: [image])
                }
                loader.sweeper.sweepAndRunTests(image: image, classes: classes)
                succeeded = true

                let countKey = "__injectionsPerformed", howOften = 100
                let count = UserDefaults.standard.integer(forKey: countKey)+1
                UserDefaults.standard.set(count, forKey: countKey)
                if count % howOften == 0 && getenv("INJECTION_SPONSOR") == nil {
                    log("""
                        ℹ️ Seems like you're using injection quite a bit. \
                        Have you considered sponsoring the project at \
                        https://github.com/johnno1962/\(APP_NAME) or \
                        asking your boss if they should? (This message \
                        prints every \(howOften) injections.)
                        """)
                }
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
                return error("Connection did not validate. Have you upgraded?")
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
            case .metrics:
                guard let metricsJSON = readString() else {
                    return error("Unable to read metrics JSON")
                }
                if let data = metricsJSON.data(using: .utf8),
                   let metricsDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let notificationName = metricsDict["notification_name"] as? String {
                    NotificationCenter.default.post(
                        name: NSNotification.Name(notificationName),
                        object: nil,
                        userInfo: metricsDict
                    )
                }
            case .setenv:
                while let name = readString(), let value = readString() {
                    setVariable(name: name, to: value, first: false)
                    if readInt() != commandInt {
                        break
                    }
                }
            case .EOF:
                return
            default:
                return error("**** @unknown case \(commandInt) **** " +
                             "Do you need to update the InjectionNext package?")
            }
        }
    }
}
#endif
