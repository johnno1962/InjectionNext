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
        if let bazelTarget = getenv(INJECTION_BAZEL_TARGET) {
            writeCommand(InjectionResponse.bazelTarget.rawValue,
                         with: String(cString: bazelTarget))
        }

        Reloader.injectionQueue.sync {
            tracingOptions()
        }

        log("\(platform) connection to app established, waiting for commands.")
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
        SwiftTrace.defaultMethodExclusions += #"|\[NS(Method|Tagged|Array|\w*Dict|Date|Data|Timer)|allocWithZone:|__unurl|_trueSelf"#
        SwiftTrace.defaultLookupExclusions += "|ScrollIndicatorVisibility"
        /// Custom type lookup on tracing.
        if let exclude = getenv(INJECTION_TRACE_LOOKUP) {
            if exclude[0] == UInt8(ascii: "|") {
                SwiftTrace.defaultLookupExclusions += String(cString: exclude)
            }
            SwiftTrace.typeLookup = true
        }
        if let filter = getenv(INJECTION_TRACE_FILTER) {
            SwiftTrace.inclusionRegexp =
                NSRegularExpression(regexp: String(cString: filter))
        }
        /// Entire App bundle tracing.
        if let exclude = getenv(INJECTION_TRACE_ALL) {
            if exclude[0] == UInt8(ascii: "|") {
                SwiftTrace.defaultMethodExclusions += String(cString: exclude)
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
        }
        /// Trace calls to framework e.g. SwiftUI,SwiftUICore
        if let which = getenv(INJECTION_TRACE_FRAMEWORKS) {
            var frmwks = String(cString: which)
            if frmwks == "" { frmwks = "SwiftUI,SwiftUICore" }
            for frmwk in frmwks.components(separatedBy: ",") {
                if let dylib = DLKit.imageMap[frmwk] {
                    Self.target = dylib
                    appBundleImages { path, header, slide in
                        rebind_symbols_trace(autoBitCast(header), slide, Self.tracer)
                    }
                } else {
                    error("Inavlid trace framework \(frmwk)")
                }
            }
        }
        // Trace UIKit internals using swizzling
        if let which = getenv(INJECTION_TRACE_UIKIT) {
            var frmwks = String(cString: which)
            if frmwks == "" { frmwks = "UIKitCore" }
            for frmwk in frmwks.components(separatedBy: ",") {
                if let bundle = DLKit.imageMap[frmwk]?.imageName {
                    SwiftTrace.trace(bundlePath: bundle)
                } else {
                    error("Inavlid swizzle framework \(frmwk)")
                }
            }
        }
        /// Function and class method tracing on injection.
        if getenv(INJECTION_TRACE) != nil {
            Reloader.traceHook = { (injected, name) in
                let name = SwiftMeta.demangle(symbol: name) ?? String(cString: name)
                detail("SwiftTracing \(name)")
                return autoBitCast(SwiftTrace.trace(name: name, original: injected)) ?? injected
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
                loader.sweeper.sweepAndRunTests(image: image, classes: classes)
                succeeded = true

                let countKey = "__injectionsPerformed", howOften = 100
                let count = UserDefaults.standard.integer(forKey: countKey)+1
                UserDefaults.standard.set(count, forKey: countKey)
                if count % howOften == 0 && getenv("INJECTION_SPONSOR") == nil {
                    log("Seems like you're using injection quite a bit. " +
                        "Have you considered sponsoring the project at " +
                        "https://github.com/johnno1962/\(APP_NAME) or " +
                        "asking your boss if they should? (This messsage " +
                        "prints every \(howOften) injections.)")
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
            case .EOF:
                return
            default:
                return error("**** @unknown case \(commandInt) ****")
            }
        }
    }
}
#endif
