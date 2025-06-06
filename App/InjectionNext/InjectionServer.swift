//
//  InjectionServer.swift
//  InjectionNext
//
//  Created by John H on 30/05/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Subclass of SimpleSocket to receive connection from
//  user apps using the InjectionNext Swift Package. An
//  incoming connection will enter runInBackground() on
//  a background thread. Validiates the connection and
//  forwards "commands" to the client app to load dynamic
//  libraries and inject them etc. Also receives feeds
//  of compilation commands from swift-frontend.sh.
//
import Cocoa
import Fortify
import Popen

class InjectionServer: SimpleSocket {

    struct ClientConnection {
        weak var connection: InjectionServer?
    }

    /// So commands from differnt threads don't get mixed up
    static let clientQueue = DispatchQueue(label: "InjectionCommand")
    static private var connected = [ClientConnection]()
    static var currentClients: [InjectionServer?] {
        connected.removeAll { $0.connection == nil }
        return connected.isEmpty ? [nil] : connected.map { $0.connection }
    }
    /// Current connection to client app. There can be only one.
    static var currentClient: InjectionServer? { currentClients.last ?? nil }

    /// Sorted last symbols exported by source.
    var exports = [String: [String]]()
    /// Keeps dynamic library file names unique.
    var injectionNumber = 0
    /// Some defaults
    var platform = "iPhoneSimulator"
    var arch = "arm64"
    var tmpPath = "/unset"

    /// Pops up an alert panel for networking
    @discardableResult
    override public class func error(_ message: String) -> Int32 {
        let saveno = errno
        let msg = String(format:message, strerror(saveno))
        NSLog("\(APP_PREFIX)\(APP_NAME) \(msg)")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "\(self)"
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
        return -1
    }

    // Send command to client app
    func sendCommand(_ command: InjectionCommand, with string: String?) {
        Self.clientQueue.async {
            _ = self.writeCommand(command.rawValue, with: string)
        }
    }

    // Write message into Xcode console of client app.
    open func log(_ msg: String) {
        NSLog("\(APP_PREFIX)\(APP_NAME) \(msg)")
        sendCommand(.log, with: APP_PREFIX+msg)
    }
    open func error(_ msg: String) {
        log("⚠️ "+msg)
    }

    lazy var copyPlugIns: () = {
        let pattern = "/tmp/InjectionNext.PlugIns/*.xctest"
        if platform == "iPhoneOS" && isLocalClient {
            if let errors = Popen.system("""
                rm -rf "\(tmpPath)"/*.xctest; \
                rsync -a \(pattern) "\(tmpPath)"
                """, errors: true) {
                error("Copy *.xctest failed: "+errors)
            }
            return
        }
        guard let plugins = Glob(pattern: pattern) else { return }
        for plugin in plugins {
            writeCommand(InjectionCommand.log.rawValue, with: APP_PREFIX+"Sending "+plugin)
            let url = URL(fileURLWithPath: plugin)
            let dest = tmpPath+"/"+url.lastPathComponent
            writeCommand(InjectionCommand.sendFile.rawValue, with: dest+"/")
            writeCommand(InjectionCommand.sendFile.rawValue, with: dest+"/_CodeSignature/")
            for file in [url.deletingPathExtension().lastPathComponent,
                         "Info.plist", "/_CodeSignature/CodeResources"] {
                writeCommand(InjectionCommand.sendFile.rawValue, with: dest+"/"+file)
                sendFile(url.appendingPathComponent(file).path)
            }
        }
    }()

    // Simple validation to weed out invalid connections
    func validateConnection() -> Bool {
        guard readInt() == INJECTION_VERSION,
              let injectionKey = readString() else { return false }
        guard injectionKey.hasPrefix(NSHomeDirectory()) else {
            error("Invalid INJECTION_KEY: "+injectionKey)
            return false
        }
        return true
    }

    // On a new connection starts executing here
    override func runInBackground() {
        do {
            try Fortify.protect {
                guard validateConnection() else {
                    sendCommand(.invalid, with: nil)
                    error("Connection did not validate.")
                    return
                }
                DispatchQueue.main.async {
                    InjectionHybrid.pendingFilesChanged.removeAll()
                }
                AppDelegate.ui.setMenuIcon(.ok)
                processResponses()
                AppDelegate.ui.setMenuIcon(MonitorXcode
                    .runningXcode != nil ? .ready : .idle)
            }
        } catch {
            self.error("\(self) error \(error)")
        }
        Self.clientQueue.sync {} // flush messages
    }

    func processResponses() {
        if MonitorXcode.runningXcode == nil &&
            AppDelegate.watchers.isEmpty &&
            AppDelegate.ui.updatePatchUnpatch() == .unpatched {
            error("""
                Xcode not launched via app. Injection will not be possible \ 
                unless you file-watch a project and Xcode logs are available \
                or use the "Intercept Compiler" menu item.
                """)
        }

        sendCommand(.xcodePath, with: Defaults.xcodePath)
        AppDelegate.restartLastWatcher()
        if !AppDelegate.watchers.isEmpty {
            log("Watching directory: " +
                AppDelegate.watchers.keys.joined(separator: ", "))
        }

        while true {
            let responseInt = readInt()
            guard let response = InjectionResponse(rawValue: responseInt) else {
                error("Invalid responseInt: \(responseInt)")
                break
            }
            switch response {
            case .platform:
                if let platform = readString(), let arch = readString() {
                    log("Platform connected: "+platform)
                    self.platform = platform
                    self.arch = arch
                } else {
                    error("**** Bad platform ****")
                    return
                }
            case .tmpPath:
                if let tmpPath = readString() {
                    print("Tmp path: "+tmpPath)
                    self.tmpPath = tmpPath
                    if !tmpPath.contains("/Xcode/UserData/Previews/") {
                        NextCompiler.compileQueue.async {
                            Self.connected.append(ClientConnection(connection: self))
                        }
                    }
                } else {
                    error("**** Bad tmp ****")
                }
            case .injected:
                AppDelegate.ui.setMenuIcon(.ok)
            case .failed:
                AppDelegate.ui.setMenuIcon(.error)
            case .unhide:
                log("Injection could not load. If this was due to a default " +
                    "argument. Select the app's menu item \"Unhide Symbols\".")
            case .exit:
                log("**** client disconnected ****")
                return
            @unknown default:
                error("**** @unknown case \(responseInt) ****")
                return
            }
        }
    }
}
