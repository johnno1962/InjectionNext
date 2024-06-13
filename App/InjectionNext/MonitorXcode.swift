//
//  RunXcode.swift
//  InjectionNext
//
//  Created by John H on 30/05/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//

import Foundation
import SwiftRegex
import Fortify
import Popen

class MonitorXcode {
    
    struct Compilation {
        let arguments: [String]
        var swiftFiles: String
        var workingDir: String
    }
    
    static let compileQueue = DispatchQueue(label: "InjectionCompile")
    static let librariesDefault = "libraries"
    static let xcodePathDefault = "XcodePath"
    static var deviceLibraries: String {
        get {
            appDelegate.defaults.string(forKey: librariesDefault) ??
                "-framework XCTest -lXCTestSwiftSupport"
        }
        set {
            appDelegate.defaults.setValue(newValue, forKey: librariesDefault)
        }
    }
    static var xcodePath: String {
        get {
            appDelegate.defaults.string(forKey: xcodePathDefault) ??
                "/Applications/Xcode.app"
        }
        set {
            appDelegate.defaults.setValue(newValue, forKey: xcodePathDefault)
        }
    }
    static weak var runningXcode: MonitorXcode?

    let tmpbase = "/tmp/injectionNext"
    var compilations = [String: Compilation]()
    var pendingSource: String?
    var lastArguments: [String]?
    var lastFilelist: String?

    func error(_ msg: String) {
        let msg = "⚠️ "+msg
        NSLog(msg)
        log(msg)
    }
    func error(_ err: Error) {
        error("Internal app error: \(err)")
    }
    func debug(_ msg: String) {
        #if DEBUG
        //print(msg)
        #endif
    }
    @discardableResult
    func log(_ msg: String) -> Bool {
        let msg = APP_PREFIX+msg
        print(msg)
        InjectionServer.currentClient?.sendCommand(.log, with: msg)
        return true
    }
    
    init() {
        #if DEBUG
        let tee = " | tee \(tmpbase).log"
        #else
        let tee = ""
        #endif
        if let xcodeStdout = Popen(cmd: "export SOURCEKIT_LOGGING=1; export LANG=en_GB.UTF-8 && " + "'\(Self.xcodePath)/Contents/MacOS/Xcode' 2>&1\(tee)") {
            Self.runningXcode = self
            DispatchQueue.global().async {
                while true {
                    do {
                        try Fortify.protect {
                            appDelegate.setMenuIcon(.ready)
                            self.processSourceKitOutput(from: xcodeStdout)
                            appDelegate.setMenuIcon(.idle)
                        }
                        break
                    } catch {
                        self.error(error)
                    }
                }
            }
        }
    }
    
    var buffer = [CChar](repeating: 0, count: 10_000)

    func processSourceKitOutput(from xcodeStdout: Popen) {
        func readQuotedString() -> String? {
            var offset = 0, doubleQuotes = Int32(UInt8(ascii: "\""))
            while let line = fgets(&buffer[offset], CInt(buffer.count-offset),
                                   xcodeStdout.fileStream) {
                offset += strlen(line)
                if offset > 0 && buffer[offset-1] == UInt8(ascii: "\n") {
                    if let start = strchr(buffer, doubleQuotes),
                       let end = strrchr(start+1, doubleQuotes) {
                        end[0] = 0
                        var out = String(cString: start+1)
                        if strstr(start+1, "\\\"") != nil {
                            out = out.replacingOccurrences(of: "\\\"", with: "\"")
                        }
                        return out
                    }
                    
                    return nil
                }
                
                var grown = [CChar](repeating: 0, count: buffer.count*2)
                strcpy(&grown, buffer)
                buffer = grown
            }
            
            return nil
        }
        
        while let line = xcodeStdout.readLine() {
            debug(">>"+line+"<<")
            if line.hasPrefix("  key.request: source.request.") &&
                (line == "  key.request: source.request.editor.open," ||
                 line == "  key.request: source.request.diagnostics," ||
                 line == "  key.request: source.request.activeregions," ||
                 line == "  key.request: source.request.relatedidents,") &&
                xcodeStdout.readLine() == "  key.compilerargs: [" ||
                line == "  key.compilerargs: [" {
                var files = "", fcount = 0, args = [String](), workingDir = "/tmp"
                while let arg = readQuotedString() {
                    if arg.hasSuffix(".swift") {
                        files += arg+"\n"
                        fcount += 1
                    } else if arg == "-fsyntax-only" {
                        _ = xcodeStdout.readLine()
                    } else if var work: String = arg[#"-working-directory(?:=(.*))?"#] {
                        if work == RegexOptioned.unmatchedGroup,
                           let swork = readQuotedString() {
                            work = swork
                        }
                        workingDir = work
                    } else if arg != "-Xfrontend" &&
                                arg != "-experimental-allow-module-with-compiler-errors" {
                        if args.last == "-F" && arg.hasSuffix("/PackageFrameworks") {
                            Unhider.packageFrameworks = arg
                        }
                        args.append(arg)
                    }
                }
                guard let source = readQuotedString() ?? readQuotedString() else {
                    continue
                }
                if let prev = compilations[source]?.arguments ?? lastArguments,
                    args == prev {
                    args = prev
                } else {
                    lastArguments = args
                }
                if let prev = compilations[source]?.swiftFiles ?? lastFilelist,
                    files == prev {
                    files = prev
                } else {
                    lastFilelist = files
                }
                print("Updating \(fcount) files \(args.count) args "+source+" "+line)
                let update = Compilation(arguments: args, swiftFiles: files,
                                         workingDir: workingDir)
                self.compilations[source] = update ////
                Self.compileQueue.async {
                    if source == self.pendingSource {
                        print("Pending "+source)
                        self.pendingSource = nil
                        self.inject(source: source)
                    }
                }
            } else if line ==
                "  key.request: source.request.indexer.editor-did-save-file,",
                  let _ = xcodeStdout.readLine(), let source = readQuotedString() {
                print("Fie saved "+source)
                Self.compileQueue.async {
                    self.inject(source: source)
                }
            }
        }
    }
    
    func inject(source: String) {
        do {
            try Fortify.protect {
                appDelegate.setMenuIcon(.busy)
                let connected = InjectionServer.currentClient
                connected?.injectionNumber += 1
                let isCompiler = connected == nil && source.hasSuffix(".cpp")
                let compilerTmp = "/tmp/compilertron_patches"
                let compilerPlatform = "MacOSX"
                let compilerArch = "arm64"
                let tmpPath = connected?.tmpPath ?? compilerTmp
                let platform = connected?.platform ?? compilerPlatform
                let sourceName = URL(fileURLWithPath: source)
                    .deletingPathExtension().lastPathComponent
                let dylibName = DYLIB_PREFIX +
                    "\(sourceName)_\(connected?.injectionNumber ?? 0).dylib"
                let dylibPath = (connected?.isLocalClient != false ?
                                 tmpPath : "/tmp") + dylibName
                
                if connected != nil || isCompiler, tmpPath != compilerTmp ||
                    isCompiler && mkdir(compilerTmp, 0o777) != -999,
                   let object = recompile(source: source),
                   let dylib = link(object: object, dylib: dylibPath, platform:
                            platform, arch: connected?.arch ?? compilerArch),
                   let data = codesign(dylib: dylib, platform: platform) {
                    log("Prepared dylib: "+dylib)
                    InjectionServer.commandQueue.sync {
                        guard let client = InjectionServer.currentClient else {
                            appDelegate.setMenuIcon(.ready)
                            return
                        }
                        if client.isLocalClient {
                            client.writeCommand(InjectionCommand
                                .load.rawValue, with: dylib)
                        } else {
                            client.writeCommand(InjectionCommand
                                .inject.rawValue, with: dylibName)
                            client.write(data)
                        }
                    }
                } else {
                    appDelegate.setMenuIcon(.error)
                    error("Injection failed.")
                }
            }
        } catch {
            self.error(error)
        }
    }
    
    func recompile(source: String) ->  String? {
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
        let languageSpecific = (isSwift ?
            ["-c", "-filelist", filesfile, "-primary-file", source] :
            ["-c", source]) + ["-o", object, "-DINJECTING"]
        if let errors = Popen.task(exec: Self.xcodePath +
            "/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/" +
            (isSwift ? "swift-frontend" : "clang"),
                                   arguments: stored.arguments + languageSpecific,
                                   cd: stored.workingDir, errors: nil),
            errors.contains(": error: ") {
            error("Recompile failed for: \(source)\n"+errors)
            return nil
        }
        
        return object
    }
    
    func link(object: String, dylib: String, platform: String, arch: String) -> String? {
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
            log("Invalid platform \(platform)")
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
            return nil
        }

        return dylib
    }
    
    func codesign(dylib: String, platform: String) -> Data? {
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
        }
        return try? Data(contentsOf: URL(fileURLWithPath: dylib))
    }
}
