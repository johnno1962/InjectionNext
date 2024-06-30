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
    // Enable injection on deivces
    @IBOutlet var deviceTesting: NSButton!
    // Testing libraries to link with
    @IBOutlet var librariesField: NSTextField!
    // Place to display last error that occured
    @IBOutlet var lastErrorField: NSTextView!
    @objc let defaults = UserDefaults.standard

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

        if let quit = statusMenu.item(at: statusMenu.items.count-1) {
            quit.title = "Quit "+appName
            if let build = Bundle.main
                .infoDictionary?[kCFBundleVersionKey as String] {
                quit.toolTip = "Quit (build #\(build))"
            }
        }
        
        if NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dt.Xcode").first != nil {
            InjectionServer.error("Please quit Xcode and\nuse this app to launch it.")
        }
 
        librariesField.stringValue = Recompiler.deviceLibraries
        InjectionServer.startServer(INJECTION_ADDRESS)
        setMenuIcon(.idle)
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
            Recompiler.xcodePath).deletingLastPathComponent()
        open.canChooseDirectories = false
        open.canChooseFiles = true
        if open.runModal() == .OK, let path = open.url?.path {
            Recompiler.xcodePath = path
            sender.toolTip = path
        }
    }
    
    lazy var startHostLocatingServerOnce: () = {
        InjectionServer.broadcastServe(HOTRELOADING_MULTICAST,
                                       port: HOTRELOADING_PORT)
    }()
    
    @IBAction func deviceEnable(_ sender: NSMenuItem) {
        sender.state = sender.state == .off ? .on : .off
        var openPort = ""
        if sender.state == .on {
            identityField.window?.makeKeyAndOrderFront(sender)
            NSApplication.shared.activate(ignoringOtherApps: true)
            _ = startHostLocatingServerOnce
            openPort = "*"
        }
        InjectionServer.stopServer()
        InjectionServer.startServer(openPort+INJECTION_ADDRESS)
    }
    
    @IBAction func testingEnable(_ sender: NSButton) {
        if sender.state == .on, let script = Bundle.main
            .path(forResource: "copy_test_frameworks", ofType: "sh") {
            let buildPhase = """
                if [ -f "\(script)" ]; then
                    "\(script)"
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
        Recompiler.deviceLibraries = librariesField.stringValue
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
}
