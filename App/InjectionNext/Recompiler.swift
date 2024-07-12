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

struct Recompiler {

    /// Information required to call the compiler for a file.
    struct Compilation {
        /// Sundry arguments to the compiler
        let arguments: [String]
        /// Swift files in the target ready to be written as a -filelist
        var swiftFiles: String
        /// Directory to run compiler in (not usually important)
        var workingDir: String
    }
    
    /// App deauflts for persistent state
    static let xcodePathDefault = "XcodePath"
    static let librariesDefault = "libraries"
    static var xcodePath: String {
        get {
            appDelegate.defaults.string(forKey: xcodePathDefault) ??
                "/Applications/Xcode.app"
        }
        set {
            appDelegate.defaults.setValue(newValue, forKey: xcodePathDefault)
        }
    }
    static var deviceLibraries: String {
        get {
            appDelegate.defaults.string(forKey: librariesDefault) ??
                "-framework XCTest -lXCTestSwiftSupport"
        }
        set {
            appDelegate.defaults.setValue(newValue, forKey: librariesDefault)
        }
    }
    
    /// Base for temporary files
    let tmpbase = "/tmp/injectionNext"
    /// Injection pending if information was not available and last error
    var pendingSource: String?, lastError: String?
    /// Information for compiling a file per source file.
    var compilations = [String: Compilation]()
    /// Previous dynamic libraries prepared by source file
    var prepared = [String: String]()
    /// Default counter for Compilertron
    var compileNumber = 0

    @discardableResult
    func log(_ msg: String) -> Bool {
        let msg = APP_PREFIX+msg
        print(msg)
        InjectionServer.currentClient?.sendCommand(.log, with: msg)
        return true
    }
    func error(_ msg: String) {
        let msg = "⚠️ "+msg
        NSLog(msg)
        log(msg)
    }
    func error(_ err: Error) {
        error("Internal app error: \(err)")
    }
    
    /// Main entry point called by MonitorXcode
    mutating func inject(source: String) {
        do {
            try Fortify.protect {
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
                    return error("Injection failed.")
                }

                print("Prepared dylib: "+dylib)
                prepared[sourceName] = dylib
                InjectionServer.commandQueue.sync {
                    guard let client = InjectionServer.currentClient else {
                        appDelegate.setMenuIcon(.ready)
                        return
                    }
                    if useFilesystem {
                        client.writeCommand(InjectionCommand
                            .load.rawValue, with: dylib)
                    } else {
                        client.writeCommand(InjectionCommand
                            .inject.rawValue, with: dylibName)
                        client.write(data)
                    }
                    if let symbols = FileSymbols(path: dylib)?.trieSymbols()?
                        .filter({ strncmp($0.name, "_$s", 3) == 0 &&
                                  strstr($0.name, "fU") == nil }) // closures
                        .map({ String(cString: $0.name) }).sorted() {
//                            print(symbols)
                        if let exported = client.exports[source],
                           exported != symbols {
                            error("Symbols altered, this is not supported." +
                                  " \(symbols.count) c.f. \(exported.count)")
                        }
                        client.exports[source] = symbols
                    }
                }
            }
        } catch {
            self.error(error)
        }
    }
    
    /// Compile a source file using inforation provided by MonitorXcode
    /// task and return the full path to the resulting object file.
    mutating func recompile(source: String, platform: String) ->  String? {
        guard let stored = compilations[source] else {
            error("Retrying: \(source) not ready.")
            pendingSource = source
            return nil
        }
        
        let uniqueObject = InjectionServer.currentClient?.injectionNumber ?? 0
        let object = tmpbase+"_\(uniqueObject).o"
        let isSwift = source.hasSuffix(".swift")
        let filesfile = tmpbase+".filelist"

        unlink(object)
        unlink(filesfile)
        try? stored.swiftFiles.write(toFile: filesfile, atomically: false,
                                   encoding: .utf8)
    
        log("Recompiling: "+source)
        let toolchain = Self.xcodePath +
            "/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
        let compiler = toolchain + "/usr/bin/" +
            (isSwift ? "swift-frontend" : "clang")
        let platformDev = Self.xcodePath + "/Contents/Developer/Platforms/" +
            platform.replacingOccurrences(of: "Simulator", with: "OS") +
            ".platform/Developer"
        let languageSpecific = (isSwift ?
            ["-c", "-filelist", filesfile, "-primary-file", source,
             "-external-plugin-path",
             platformDev+"/usr/lib/swift/host/plugins#" +
             platformDev+"/usr/bin/swift-plugin-server",
             "-external-plugin-path",
             platformDev+"/usr/local/lib/swift/host/plugins#" +
             platformDev+"/usr/bin/swift-plugin-server",
             "-plugin-path", toolchain+"/usr/lib/swift/host/plugins",
             "-plugin-path", toolchain+"/usr/local/lib/swift/host/plugins"] :
            ["-c", source]) + ["-o", object, "-DINJECTING"]
        
        // Call compiler process
        if let errors = Popen.task(exec: compiler,
               arguments: stored.arguments + languageSpecific,
               cd: stored.workingDir, errors: nil), // Always returns stdout
           errors.contains(" error: ") {
            print(([compiler] + stored.arguments +
                   languageSpecific).joined(separator: " "))
            error("Recompile failed for: \(source)\n"+errors)
            lastError = errors
            return nil
        }
        
        return object
    }
    
    /// Link and object file to create a dynamic library
    mutating func link(object: String, dylib: String, platform: String, arch: String) -> String? {
        let xcodeDev = Self.xcodePath+"/Contents/Developer"
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
        case "XRSimulator": fallthrough case "XROS":
            osSpecific = ""
        default:
            error("Invalid platform \(platform)")
            // -Xlinker -bundle_loader -Xlinker \"\(Bundle.main.executablePath!)\""
        }

        let toolchain = xcodeDev+"/Toolchains/XcodeDefault.xctoolchain"
        let frameworks = Bundle.main.privateFrameworksPath ?? "/tmp"
        var testingOptions = ""
        if DispatchQueue.main.sync(execute: {
            appDelegate.deviceTesting.state == .on }) {
            let otherOptions = DispatchQueue.main.sync(execute: {
                appDelegate.librariesField.stringValue = Self.deviceLibraries
                return Self.deviceLibraries })
            let platformDev = "\(xcodeDev)/Platforms/\(platform).platform/Developer"
            testingOptions = """
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
            error("Linking failed:\n\(linkCommand)\nerrors:\n"+errors)
            lastError = errors
            return nil
        }

        return dylib
    }
    
    /// Codesign a dynamic library
    mutating func codesign(dylib: String, platform: String) -> Data? {
        var identity = "-"
        if !platform.hasSuffix("Simulator") && platform != "MacOSX" {
            identity = appDelegate.identityField.stringValue
        }
        let codesign = """
            (export CODESIGN_ALLOCATE="\(Self.xcodePath+"/Contents/Developer"
             )/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate"; \
            if /usr/bin/file \"\(dylib)\" | /usr/bin/grep ' shared library ' >/dev/null; \
            then /usr/bin/codesign --force -s "\(identity)" \"\(dylib)\";\
            else exit 1; fi)
            """
        if let errors = Popen.system(codesign, errors: true) {
            error("Codesign failed \(codesign) errors:\n"+errors)
            lastError = errors
        }
        return try? Data(contentsOf: URL(fileURLWithPath: dylib))
    }
}
