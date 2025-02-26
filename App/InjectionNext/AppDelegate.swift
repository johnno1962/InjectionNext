//
//  AppDelegate.swift
//  InjectionNext
//
//  Created by John Holdsworth on 06/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/injectiond/AppDelegate.swift#76 $
//
//  Implementation Toolbar menu "UI".
//
import Cocoa
import Popen
import SwiftRegex

var appDelegate: AppDelegate!

enum InjectionState: String {
    case ok = "OK" // Orange
    case idle = "Idle" // Blue
    case busy = "Busy" // Green
    case ready = "Ready" // Purple
    case error = "Error" // Yellow
}

@objc(AppDelegate)
class AppDelegate : NSObject, NSApplicationDelegate {

    // Status menu
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet var statusItem: NSStatusItem!
    // Codesigning identity
    @IBOutlet var identityField: NSTextField!
    // Enable injection on devices
    @IBOutlet var deviceTesting: NSButton!
    // Testing libraries to link with
    @IBOutlet var librariesField: NSTextField!
    // Place to display last error that occured
    @IBOutlet var lastErrorField: NSTextView!
    // Restart XCode if crashed.
    @IBOutlet weak var restartDeviceItem: NSMenuItem!
    @IBOutlet weak var patchCompilerItem: NSMenuItem!

    // Interface to app's persistent state.
    @objc let defaults = Defaults.userDefaults

    @IBOutlet weak var codeSignBox: NSComboBox!

    /// Code signing ID as parsed from the code signing box. If the content of the box is not
    /// parsable as SHA1 code signing ID, an empty string.
    var codeSigningID: String { codeSignBox.stringValue.containedSHA1 ?? "" }

    let userIDComboBoxDataSaver = UserIDComboBoxDataSaver()

    @objc func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        appDelegate = self

        let appName = "InjectionNext"
        let statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: statusBar.thickness)
        statusItem.highlightMode = true
        statusItem.menu = statusMenu
        statusItem.isEnabled = true
        statusItem.title = appName
        setMenuIcon(.idle)

        signal(SIGPIPE, { which in
            print(APP_PREFIX+"⚠️ SIGPIPE #\(which)\n" +
                  Thread.callStackSymbols.map { var frame = $0
                        frame[#"(?:\S+\s+){3}(\S+)"#, 1] = {
                            (groups: [String], stop) in
                            return groups[1].swiftDemangle ?? groups[1] }
                        return frame
                    }.joined(separator: "\n")) })

        if let quit = statusMenu.item(at: statusMenu.items.count-1) {
            quit.title = "Quit "+appName
            if let build = Bundle.main
                .infoDictionary?[kCFBundleVersionKey as String] {
                quit.toolTip = "Quit (build #\(build))"
            }
        }
        
        if !updatePatchUnpatch() && NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dt.Xcode").first != nil {
            InjectionServer.error("""
                Please quit Xcode and
                use this app to launch it
                (unless you are using a file watcher).
                """)
        }
 
        librariesField.stringValue = Defaults.deviceLibraries
        InjectionServer.startServer(INJECTION_ADDRESS)
        setupCodeSigningComboBox()
        restartDeviceItem.state = Defaults.xcodeRestart == true ? .on : .off
        
        if let project = Defaults.projectPath {
            _ = MonitorXcode(args: " '\(project)'")
        }
    }
    
    func setMenuIcon(_ state: InjectionState) {
        DispatchQueue.main.async {
            let tiffName = "Injection"+state.rawValue
            if let path = Bundle.main.path(forResource: tiffName, ofType: "tif"),
                let image = NSImage(contentsOfFile: path) {
    //            image.template = TRUE;
                self.statusItem.image = image
                self.statusItem.alternateImage = image
            }
        }
    }

    @IBAction func runXcode(_ sender: Any) {
        if MonitorXcode.runningXcode == nil {
            _ = MonitorXcode()
        }
    }
    
    @IBAction func selectXcode(_ sender: NSMenuItem) {
        let open = NSOpenPanel()
        open.prompt = "Select Xcode"
        open.directoryURL = URL(fileURLWithPath:
            Defaults.xcodePath).deletingLastPathComponent()
        open.canChooseDirectories = false
        open.canChooseFiles = true
        if open.runModal() == .OK, let path = open.url?.path {
            Defaults.xcodePath = path
            _ = updatePatchUnpatch()
            sender.toolTip = path
            runXcode(sender)
        }
    }
    
    lazy var startHostLocatingServerOnce: () = {
        InjectionServer.broadcastServe(HOTRELOADING_MULTICAST,
                                       port: HOTRELOADING_PORT)
    }()
    
    @IBAction func deviceEnable(_ sender: NSMenuItem) {
        var openPort = ""
        if sender.state.toggle() == .on {
            codeSignBox.window?.makeKeyAndOrderFront(sender)
            NSApplication.shared.activate(ignoringOtherApps: true)
            _ = startHostLocatingServerOnce
            openPort = "*"
        }
        InjectionServer.stopServer()
        InjectionServer.startServer(openPort+INJECTION_ADDRESS)
    }
    
    @IBAction func testingEnable(_ sender: NSButton) {
        if sender.state == .on, let script = Bundle.main
            .url(forResource: "copy_bundle", withExtension: "sh") {
            let buildPhase = """
                export RESOURCES="\(script.deletingLastPathComponent().path)"
                if [ -f "$RESOURCES/\(script.lastPathComponent)" ]; then
                    "$RESOURCES/\(script.lastPathComponent)"
                fi
                """
            let pasteBoard = NSPasteboard.general
            pasteBoard.declareTypes([.string], owner:nil)
            pasteBoard.setString(buildPhase, forType:.string)
            InjectionServer.error("Run Script, Build Phase to " +
                  "copy testing libraries added to clipboard.")
        }
    }

    @IBAction func updateLibraries(_ sender: NSTextField) {
        Defaults.deviceLibraries = librariesField.stringValue
    }


    @IBAction func updateXcodeRestart(_ sender: NSMenuItem) {
        Defaults.xcodeRestart = sender.state.toggle() == .on
    }
    
    @IBAction func unhideSymbols(_ sender: NSMenuItem) {
        Unhider.startUnhide()
    }

    @IBAction func resetUnhiding(_ sender: NSMenuItem) {
        Unhider.unhiddens.removeAll()
    }

    @IBAction func showlastError(_ sender: NSMenuItem) {
        lastErrorField.string = MonitorXcode
            .runningXcode?.recompiler.lastError ?? "No error."
        lastErrorField.window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func setupCodeSigningComboBox() {
        codeSignBox.removeAllItems()

        codeSignBox.addItems(withObjectValues: userIDComboBoxDataSaver.validCodeSigningIDs)

        if let savedID = userIDComboBoxDataSaver.savedID {
            codeSignBox.stringValue = savedID
        } else if let firstIdentity = userIDComboBoxDataSaver.validCodeSigningIDs.first {
            codeSignBox.stringValue = firstIdentity
        } else {
            codeSignBox.stringValue = "No valid code signing IDs found"
        }

        codeSignBox.target = userIDComboBoxDataSaver
        codeSignBox.action = #selector(UserIDComboBoxDataSaver.comboBoxValueDidChange(_:))
    }
}

private extension String {
    /// Returns the sha1 string contained in this string, or `nil` if no such string is contained.
    var containedSHA1: String? { self[#"([0-9A-F]{40})"#] }
}

class UserIDComboBoxDataSaver {

    /// List of valid IDs.
    let validCodeSigningIDs: [String] = {
        var identities: [String] = []

        let security = Topen(exec: "/usr/bin/security",
                             arguments: ["find-identity", "-v", "-p", "codesigning"])

        while let line = security.readLine() {
            let components = line.split(separator: ")", maxSplits: 1)
            if components.count >= 2 {
                let identity = components[1]
                identities.append(String(identity))
            }
        }

        return identities
    }()

    /// Last savedID, if valid. `nil` otherwise.
    var savedID: String? {
        guard let savedValue = Defaults.codesigningIdentity else { return nil }

        return validCodeSigningIDs.first(where: { $0.containedSHA1 == savedValue.containedSHA1} )
    }

    @objc func comboBoxValueDidChange(_ sender: NSComboBox) {
        if let newValueSHA1 = sender.stringValue.containedSHA1,
           validCodeSigningIDs.contains(where: { $0.containedSHA1 == newValueSHA1 }) {
            Defaults.codesigningIdentity = newValueSHA1
        } else {
            NSLog("Selected value does not contain a valid ID")
            return
        }
    }
}

private extension NSControl.StateValue {
    @discardableResult
    mutating func toggle() -> Self {
        switch self {
        case .on:
            self = .off
        case .off:
            self = .on
        case .mixed:
            self = .mixed
        default:
            break
        }
        return self
    }
}
