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

@discardableResult
public func log(_ what: Any..., prefix: String = APP_PREFIX, separator: String = " ") -> Bool {
    let msg = prefix+what.map {"\($0)"}.joined(separator: separator)
    print(msg)
    InjectionServer.currentClient?.sendCommand(.log, with: msg)
    return true
}

class NextCompiler {

    /// Information required to call the compiler for a file.
    struct Compilation {
        /// Sundry arguments to the compiler
        let arguments: [String]
        /// Swift files in the target ready to be written as a -filelist
        var swiftFiles: String
        /// Directory to run compiler in (not usually important)
        var workingDir: String
    }
    
    /// Base for temporary files
    let tmpbase = "/tmp/injectionNext"
    /// Injection pending if information was not available and last error
    var pendingSource: String?, lastError: String?
    /// Information for compiling a file per source file.
    var compilations = [String: Compilation]()
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
    
    /// Main entry point called by MonitorXcode
    func inject(source: String) -> Bool {
        do {
            return try Fortify.protect { () -> Bool in
                let connected = InjectionServer.currentClient
                connected?.injectionNumber += 1
                appDelegate.setMenuIcon(.busy)
                compileNumber += 1
                lastError = nil

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
                let dylibPath = (useFilesystem ? tmpPath : "/tmp") + dylibName

                guard let object = recompile(source: source, platform: platform),
                   tmpPath != compilerTmp || mkdir(compilerTmp, 0o777) != -999,
                   let dylib = link(object: object, dylib: dylibPath, platform:
                            platform, arch: connected?.arch ?? compilerArch),
                   let data = codesign(dylib: dylib, platform: platform) else {
                    appDelegate.setMenuIcon(.error)
                    return error("Injection failed. Was your app connected?")
                }

                print("Prepared dylib: "+dylib)
                prepared[sourceName] = dylib
                InjectionServer.commandQueue.sync {
                    guard let client = InjectionServer.currentClient else {
                        appDelegate.setMenuIcon(.ready)
                        return
                    }
                    if Reloader.injectingXCTest(in: dylib) {
                        _ = client.copyPlugIns
                    }
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
                return true
            }
        } catch {
            return self.error(error)
        }
    }
    
    /// Seek to highlight potentially unsupported injections.
    func unsupported(source: String, dylib: String, client: InjectionServer) {
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
                print(symbols.difference(from: previous))
            }
            client.exports[source] = symbols
        }
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
        try? stored.swiftFiles.write(toFile: filesfile, atomically: false,
                                   encoding: .utf8)
    
        log("Recompiling: "+source)
        let toolchain = Defaults.xcodePath +
            "/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        let compiler = toolchain + "/usr/bin/" +
            (isSwift ? "swift-frontend" : "clang")
        let platformUsr = Defaults.xcodePath + "/Contents/Developer/Platforms/" +
            platform.replacingOccurrences(of: "Simulator", with: "OS") +
            ".platform/Developer/usr/"
        let baseOptionsToAdd = ["-o", object, "-DINJECTING"]
        let languageSpecific = (isSwift ?
            ["-c", "-filelist", filesfile, "-primary-file", source,
             "-external-plugin-path",
             platformUsr+"lib/swift/host/plugins#" +
             platformUsr+"bin/swift-plugin-server",
             "-external-plugin-path",
             platformUsr+"local/lib/swift/host/plugins#" +
             platformUsr+"bin/swift-plugin-server",
             "-plugin-path", toolchain+"/usr/lib/swift/host/plugins",
             "-plugin-path", toolchain+"/usr/local/lib/swift/host/plugins"] :
            ["-c", source, "-Xclang", "-fno-validate-pch"]) + baseOptionsToAdd

        // Call compiler process
        if let errors = Popen.task(exec: compiler,
               arguments: stored.arguments + languageSpecific,
               cd: stored.workingDir, errors: nil), // Always returns stdout
           errors.contains(" error: ") {
            print(([compiler] + stored.arguments +
                   languageSpecific).joined(separator: " "))
            _ = error("Recompile failed for: \(source)\n"+errors)
            lastError = errors
            return nil
        }
        
        return object
    }
    
    /// Link and object file to create a dynamic library
    func link(object: String, dylib: String, platform: String, arch: String) -> String? {
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
            appDelegate.deviceTesting.state == .on }) {
            let otherOptions = DispatchQueue.main.sync(execute: {
                appDelegate.librariesField.stringValue = Defaults.deviceLibraries
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
            lastError = errors
            return nil
        }

        return dylib
    }
    
    /// Codesign a dynamic library
    func codesign(dylib: String, platform: String) -> Data? {
        if platform != "iPhoneSimulator" {
        var identity = "-"
        if !platform.hasSuffix("Simulator") && platform != "MacOSX" {
            identity = appDelegate.codeSigningID
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
            lastError = errors
        }
        }
        return try? Data(contentsOf: URL(fileURLWithPath: dylib))
    }
}
