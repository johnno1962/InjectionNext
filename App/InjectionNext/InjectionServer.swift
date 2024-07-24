//
//  InjectionServer.swift
//  InjectionNext
//
//  Created by John H on 30/05/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Subclass of SimpleSocket to receive connection from
//  user apps using the InjectionNext Swift Package. An
//  incoming connection with enter runInBackground() on
//  a background thread. Validiates the connection and
//  forwards "commands" to the client app to load dynamic
//  libraries and inject them etc.
//
import Cocoa
import Fortify

class InjectionServer: SimpleSocket {
    
    /// So commands from differnt threads don't get mixed up
    static let commandQueue = DispatchQueue(label: "InjectionCommand")
    /// Current connection to client app. There can be only one.
    static weak var currentClient: InjectionServer?
    
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
            alert.alertStyle = NSAlert.Style.warning
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
        return -1
    }

    // Send command to client app
    func sendCommand(_ command: InjectionCommand, with string: String?) {
        Self.commandQueue.async {
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

    // Simple validation to weed out invalid connections
    func validateConnection() -> CInt? {
        let clientVersion = readInt()
        guard clientVersion == INJECTION_VERSION &&
            readString()?.hasPrefix(NSHomeDirectory()) == true else { return nil }
        return clientVersion
    }

    // On a new connection starts executing here
    override func runInBackground() {
        do {
            try Fortify.protect {
                Self.currentClient = self
                appDelegate.setMenuIcon(.ok)
                processResponses()
                appDelegate.setMenuIcon(MonitorXcode
                    .runningXcode != nil ? .ready : .idle)
            }
        } catch {
            self.error("\(self) error \(error)")
        }
        Self.commandQueue.sync {} // flush messages
    }

    func processResponses() {
        guard let _ = validateConnection() else {
            sendCommand(.invalid, with: nil)
            error("Connection did not validate.")
            return
        }
        
        guard MonitorXcode.runningXcode != nil else {
            error("Xcode not launched via app. Injection will not be possible.")
            return
        }
        
        sendCommand(.xcodePath, with: Defaults.xcodePath)
        
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
                } else {
                    error("**** Bad tmp ****")
                }
            case .injected:
                appDelegate.setMenuIcon(.ok)
            case .failed:
                appDelegate.setMenuIcon(.error)
            case .unhide:
                log("Injection failed to load. If this was due to a default " +
                    "argument. Select the app's menu item \"Unhide Symbols\".")
            case .exit:
                log("**** exit ****")
                return
            @unknown default:
                error("**** @unknown case ****")
                return
            }
        }
    }
}
