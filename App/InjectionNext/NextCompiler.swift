//
//  Recompiler.swift
//  InjectionNext
//
//  Created by John Holdsworth on 21/06/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Server side implementation of injection.
//  Recompile, link, codesign, send to client.
//
import Foundation
import Fortify
import Popen
import DLKit

/// bring in injectingXCTest()
struct Reloader {}

/// Tracks timing metrics for injection process
struct InjectionMetricsTracker: Codable {
    var processingTimeMs: Double = 0
    var compilationTimeMs: Double = 0
    var linkingTimeMs: Double = 0
    var totalTimeMs: Double = 0
    var sourcePath: String
    var success: Bool = false
    var notificationName: String = INJECTION_METRICS_NOTIFICATION
    let startTime: Double

    init(sourcePath: String) {
        self.sourcePath = sourcePath
        self.startTime = Date.timeIntervalSinceReferenceDate
    }
}

@discardableResult
public func log(_ what: Any..., prefix: String = APP_PREFIX, separator: String = " ") -> Bool {
    var msg = what.map {"\($0)"}.joined(separator: separator)
    #if INJECTION_III_APP
    msg = "⏳ "+msg
    #else
    msg = prefix+msg
    #endif
    print(msg)
    for client in InjectionServer.currentClients {
        client?.sendCommand(.log, with: msg)
    }
    return true
}

class NextCompiler {

    /// Information required to call the compiler for a file.
    struct Compilation: Codable, Hashable {
        /// Sundry arguments to the compiler
        let arguments: [String]
        /// Swift files in the target ready to be written as a -filelist
        let swiftFiles: String
        /// Directory to run compiler in (not important for Swift)
        let workingDir: String
    }

    /// Queue for one compilation at a time.
    static let compileQueue = DispatchQueue(label: "InjectionCompile")
    /// Last build error.
    static var lastError: String?, lastSource: String?
    /// Current metrics being tracked
    static var currentMetrics: InjectionMetricsTracker?

    /// Base for temporary files
    let tmpbase = "/tmp/injectionNext"
    /// Injection pending if information was not available
    var pendingSource: String?
    /// Information for compiling a file per source file.
    var compilations = [String: Compilation]()
    /// Trying to avoid fragmenting memory
    var lastCompilation: Compilation?
    /// Last Injected
    var lastInjected = [String: TimeInterval]()
    /// Previous dynamic libraries prepared by source file
    var prepared = [String: String]()
    /// Default counter for Compilertron
    var compileNumber = 0

    func error(_ msg: String) -> Bool {
        let msg = "⚠️ "+msg
        NSLog(msg)
        log(msg)
        return false
    }
    func error(_ err: Error) -> Bool {
        error("Internal app error: \(err)")
    }
    
    func store(compilation: Compilation, for source: String) {
        Self.lastSource = source
        if lastCompilation != compilation {
            lastCompilation = compilation
        } //else { print("reusing") }
        compilations[source] = lastCompilation
        if source == pendingSource {
            print("Delayed injection of "+source)
            if inject(source: source) {
                pendingSource = nil
            }
        }
    }

    /// Main entry point called by MonitorXcode
    func inject(source: String) -> Bool {
        // Start tracking metrics
        Self.currentMetrics = InjectionMetricsTracker(sourcePath: source)

        do {
            let result = try Fortify.protect { () -> Bool in
                for client in InjectionServer.currentClients.reversed() {
                guard let (dylib, dylibName, platform, useFilesystem)
                        = prepare(source: source, connected: client),
                   let data = codesign(dylib: dylib, platform: platform) else {
                    AppDelegate.ui.setMenuIcon(.error)
                    return error("Injection failed. Was your app connected?")
                }

                InjectionServer.clientQueue.sync {
                    guard let client = client else {
                        AppDelegate.ui.setMenuIcon(.ready)
                        return
                    }
//                    if Reloader.injectingXCTest(in: dylib) {
//                        _ = client.copyPlugIns
//                    }
                    if useFilesystem {
                        client.writeCommand(InjectionCommand
                            .load.rawValue, with: dylib)
                    } else {
                        client.writeCommand(InjectionCommand
                            .inject.rawValue, with: dylibName)
                        client.write(data)
                    }
                    unsupported(source: source, dylib: dylib, client: client)
                }
                }
                Self.lastSource = source
                return true
            }

            // Calculate total time and send metrics
            if let metrics = Self.currentMetrics {
                metrics.totalTimeMs = (Date.timeIntervalSinceReferenceDate - metrics.startTime) * 1000
                metrics.success = result
                sendMetrics(metrics)
            }

            return result
        } catch {
            // Send failure metrics
            if let metrics = Self.currentMetrics {
                metrics.totalTimeMs = (Date.timeIntervalSinceReferenceDate - metrics.startTime) * 1000
                metrics.success = false
                sendMetrics(metrics)
            }
            return self.error(error)
        }
    }

    /// Send metrics to all connected clients
    func sendMetrics(_ metrics: InjectionMetricsTracker) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let jsonData = try? encoder.encode(metrics),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        for client in InjectionServer.currentClients {
            client?.sendCommand(.metrics, with: jsonString)
        }
    }

    /// Seek to highlight potentially unsupported injections.
    func unsupported(source: String, dylib: String, client: InjectionServer) {
        #if !INJECTION_III_APP
        if let symbols = FileSymbols(path: dylib)?.trieSymbols()?
            .filter({ entry in
                lazy var symbol: String = String(cString: entry.name)
                return strncmp(entry.name, "_$s", 3) == 0 &&
                strstr(entry.name, "fU") == nil && // closures
                !symbol.hasSuffix("MD") && !symbol.hasSuffix("Oh") &&
                !symbol.hasSuffix("Wl") && !symbol.hasSuffix("WL") })
            .map({ String(cString: $0.name) }).sorted() {
//            print(symbols)
            if let previous = client.exports[source],
               previous.count != symbols.count {
                log("ℹ️ Symbols altered, this may not be supported." +
                      " \(symbols.count) c.f. \(previous.count)")
                if #available(macOS 15.0, *) {
                    print(symbols.difference(from: previous))
                }
            }
            client.exports[source] = symbols
        }
        #endif
    }

    func prepare(source: String, connected: InjectionServer?)
        -> (dylib: String, dylibName: String, platform: String, Bool)? {
        connected?.injectionNumber += 1
        AppDelegate.ui.setMenuIcon(.busy)
        compileNumber += 1
        Self.lastError = nil

        // Support for https://github.com/johnno1962/Compilertron
        let isCompilertron = connected == nil && source.hasSuffix(".cpp")
        let compilerTmp = "/tmp/compilertron_patches"
        let compilerPlatform = "MacOSX"
        let compilerArch = "arm64"

        let tmpPath = connected?.tmpPath ?? compilerTmp
        let platform = connected?.platform ?? compilerPlatform
        let sourceName = URL(fileURLWithPath: source)
            .deletingPathExtension().lastPathComponent
        if isCompilertron, let previous = prepared[sourceName] {
            unlink(previous)
        }

        let dylibName = DYLIB_PREFIX + sourceName +
            "_\(connected?.injectionNumber ?? compileNumber).dylib"
        let useFilesystem = connected?.isLocalClient != false
        #if INJECTION_III_APP
        let dylibPath = (true ? tmpPath : "/tmp") + dylibName
        #else
        let dylibPath = (useFilesystem ? tmpPath : "/tmp") + dylibName
        #endif
        guard let object = recompile(source: source, platform: platform),
           tmpPath != compilerTmp || mkdir(compilerTmp, 0o777) != -999,
           let (dylib, linkingTimeMs) = link(object: object, dylib: dylibPath, platform:
            platform, arch: connected?.arch ?? compilerArch) else { return nil }

        Self.currentMetrics?.linkingTimeMs = linkingTimeMs

        prepared[sourceName] = dylib
        print("Prepared dylib: "+dylib)
        return (dylib, dylibName, platform, useFilesystem)
    }

    /// Compile a source file using inforation provided by MonitorXcode
    /// task and return the full path to the resulting object file.
    func recompile(source: String, platform: String) ->  String? {
        guard let stored = compilations[source] else {
            _ = error("Postponing: \(source) Have you viewed it in Xcode?")
            pendingSource = source
            return nil
        }

        lastInjected[source] = Date().timeIntervalSince1970
        let uniqueObject = InjectionServer.currentClient?.injectionNumber ?? 0
        let object = tmpbase+"_\(uniqueObject).o"
        let isSwift = source.hasSuffix(".swift")
        let filesfile = tmpbase+".filelist"

        unlink(object)
        unlink(filesfile)
        try? stored.swiftFiles.write(toFile: filesfile,
                                     atomically: false, encoding: .utf8)

        log("Recompiling: "+source)
        let toolchain = Defaults.xcodePath +
            "/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        let compiler = (isSwift ? FrontendServer.loggedFrontend : nil) ??
            toolchain + "/usr/bin/" + (isSwift ? "swift-frontend" : "clang")
        let platformUsr = Defaults.xcodePath + "/Contents/Developer/Platforms/" +
            platform.replacingOccurrences(of: "Simulator", with: "OS") +
            ".platform/Developer/usr/"
        let baseOptionsToAdd = ["-o", object, "-DDEBUG", "-DINJECTING"]
        let languageSpecific = (isSwift ?
            ["-c", "-filelist", filesfile, "-primary-file", source,
             Reloader.typeCheckLimit,
             "-external-plugin-path",
             platformUsr+"lib/swift/host/plugins#" +
             platformUsr+"bin/swift-plugin-server",
             "-external-plugin-path",
             platformUsr+"local/lib/swift/host/plugins#" +
             platformUsr+"bin/swift-plugin-server",
             "-plugin-path", toolchain+"/usr/lib/swift/host/plugins",
             "-plugin-path", toolchain+"/usr/local/lib/swift/host/plugins"] :
            ["-c", source, "-Xclang", "-fno-validate-pch"]) + baseOptionsToAdd

        // Track processing time (time from inject start to compilation start)
        if let metrics = Self.currentMetrics {
            metrics.processingTimeMs = (Date.timeIntervalSinceReferenceDate - metrics.startTime) * 1000
        }

        // Call compiler process with timing
        let compilationStartTime = Date.timeIntervalSinceReferenceDate
        let compile = Topen(exec: compiler,
               arguments: stored.arguments + languageSpecific,
               cd: stored.workingDir)
        var errors = ""
        while let line = compile.readLine() {
            if let slow: String = line[Reloader.typeCheckRegex] {
                log(slow)
            }
            errors += line+"\n"
        }
        if errors.contains(" error: ") {
            print(([compiler] + stored.arguments +
                   languageSpecific).joined(separator: " "))
            _ = error("Recompile failed for: \(source)\n"+errors)
            Self.lastError = errors
            return nil
        }

        // Log successful compilation with timing
        let now = Date.timeIntervalSinceReferenceDate
        let compilationTimeMs = (now - compilationStartTime) * 1000
        Self.currentMetrics?.compilationTimeMs = compilationTimeMs
        detail(String(format: "⚡ Compiled in %.0fms", compilationTimeMs))

        return object
    }

    /// Link and object file to create a dynamic library
    func link(object: String, dylib: String, platform: String, arch: String) -> (String, Double)? {
        let linkingStartTime = Date.timeIntervalSinceReferenceDate
        let xcodeDev = Defaults.xcodePath+"/Contents/Developer"
        let sdk = "\(xcodeDev)/Platforms/\(platform).platform/Developer/SDKs/\(platform).sdk"

        var osSpecific = ""
        switch platform {
        case "iPhoneSimulator":
            osSpecific = "-mios-simulator-version-min=9.0"
        case "iPhoneOS":
            osSpecific = "-miphoneos-version-min=9.0"
        case "AppleTVSimulator":
            osSpecific = "-mtvos-simulator-version-min=9.0"
        case "AppleTVOS":
            osSpecific = "-mtvos-version-min=9.0"
        case "MacOSX":
            let target = "" /*compileCommand
                .replacingOccurrences(of: #"^.*( -target \S+).*$"#,
                                      with: "$1", options: .regularExpression)*/
            osSpecific = "-mmacosx-version-min=10.11"+target
        case "WatchSimulator": fallthrough case "WatchOS":
        fallthrough case "XRSimulator": fallthrough case "XROS":
            osSpecific = ""
        default:
            _ = error("Invalid platform \(platform)")
            // -Xlinker -bundle_loader -Xlinker \"\(Bundle.main.executablePath!)\""
        }

        let toolchain = xcodeDev+"/Toolchains/XcodeDefault.xctoolchain"
        let frameworks = Bundle.main.privateFrameworksPath ?? "/tmp"
        var testingOptions = ""
        if DispatchQueue.main.sync(execute: {
            AppDelegate.ui.deviceTesting?.state == .on }) {
            let otherOptions = DispatchQueue.main.sync(execute: { () -> String in
                AppDelegate.ui.librariesField.stringValue = Defaults.deviceLibraries
                return Defaults.deviceLibraries })
            let platformDev = "\(xcodeDev)/Platforms/\(platform).platform/Developer"
            testingOptions = """
                -F /tmp/InjectionNext.Products \
                -F "\(platformDev)/Library/Frameworks" \
                -L "\(platformDev)/usr/lib" \(otherOptions)
                """
        }

        let linkCommand = """
            "\(toolchain)/usr/bin/clang" -arch "\(arch)" \
                -Xlinker -dylib -isysroot "__PLATFORM__" \
                -L"\(toolchain)/usr/lib/swift/\(platform.lowercased())" \(osSpecific) \
                -undefined dynamic_lookup -dead_strip -Xlinker -objc_abi_version \
                -Xlinker 2 -Xlinker -interposable -fobjc-arc \(testingOptions) \
                -fprofile-instr-generate \(object) -L "\(frameworks)" -F "\(frameworks)" \
                -rpath "\(frameworks)" -o \"\(dylib)\" -rpath /usr/lib/swift \
                -rpath "\(toolchain)/usr/lib/swift-5.5/\(platform.lowercased())"
            """.replacingOccurrences(of: "__PLATFORM__", with: sdk)

        if let errors = Popen.system(linkCommand, errors: true) {
            _ = error("Linking failed:\n\(linkCommand)\nerrors:\n"+errors)
            Self.lastError = errors
            return nil
        }

        let linkingTimeMs = (Date.timeIntervalSinceReferenceDate - linkingStartTime) * 1000
        return (dylib, linkingTimeMs)
    }

    /// Codesign a dynamic library
    func codesign(dylib: String, platform: String) -> Data? {
        if platform != "iPhoneSimulator" {
        var identity = "-"
        if !platform.hasSuffix("Simulator") && platform != "MacOSX" {
            identity = DispatchQueue.main.sync { AppDelegate.ui.codeSigningID }
            log("Codesigning dylib with identity "+identity)
        }
        let codesign = """
            (export CODESIGN_ALLOCATE="\(Defaults.xcodePath+"/Contents/Developer"
             )/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate"; \
            if /usr/bin/file \"\(dylib)\" | /usr/bin/grep ' shared library ' >/dev/null; \
            then /usr/bin/codesign --force -s "\(identity)" \"\(dylib)\";\
            else exit 1; fi)
            """
        if let errors = Popen.system(codesign, errors: true) {
            _ = error("Codesign failed \(codesign) errors:\n"+errors)
            Self.lastError = errors
        }
        }
        return try? Data(contentsOf: URL(fileURLWithPath: dylib))
    }
}
