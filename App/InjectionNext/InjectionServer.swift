//
//  InjectionServer.swift
//  InjectionNext
//
//  Created by John H on 30/05/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//

import Cocoa
import Fortify

class InjectionServer: SimpleSocket {
    
    static let commandQueue = DispatchQueue(label: "InjectionCommand")
    static weak var currentClient: InjectionServer?
    
    var injectionNumber = 0
    var platform = "iPhoneSimulator"
    var arch = "arm64"
    var tmpPath = "/unset"

    open func log(_ msg: String) {
        NSLog("\(APP_PREFIX)\(APP_NAME) \(msg)")
        sendCommand(.log, with: APP_PREFIX+msg)
    }
    open func error(_ msg: String) {
        log("⚠️ "+msg)
    }

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

    func sendCommand(_ command: InjectionCommand, with string: String?) {
        Self.commandQueue.sync {
            _ = writeCommand(command.rawValue, with: string)
        }
    }

    func validateConnection() -> CInt? {
        let clientVersion = readInt()
        return clientVersion == INJECTION_VERSION &&
            readString()?.hasPrefix(NSHomeDirectory()) == true ?
            clientVersion : nil
    }
    
    override func runInBackground() {
        do {
            try Fortify.protect {
                Self.currentClient = self
                appDelegate.setMenuIcon(.ok)
                processCommands()
                appDelegate.setMenuIcon(MonitorXcode.runningXcode != nil ?
                                        .ready : .idle)
            }
        } catch {
            self.error("\(self) error \(error)")
        }
    }
    
    func processCommands() {
        guard let _ = validateConnection() else {
            sendCommand(.invalid, with: nil)
            error("Connection did not validate.")
            return
        }
        
        guard MonitorXcode.runningXcode != nil else {
            error("Xcode not launched via app. Injection will not be possible.")
            return
        }
        
        sendCommand(.xcodePath, with: MonitorXcode.xcodePath)
        
        while true {
            let commandInt = readInt()
            guard let command = InjectionResponse(rawValue: commandInt) else {
                error("Invalid responseInt: \(commandInt)")
                break
            }
            switch command {
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
                if !Unhider.reunhide() {
                    log("Injection failed to load. If this was due to a default " +
                        "argument. Select the app's menu item \"Unhide Symbols\".")
                }
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
