//
//  AppDelegate.swift
//  InjectionNext
//
//  Created by John Holdsworth on 06/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/injectiond/AppDelegate.swift#76 $
//

import Cocoa

var appDelegate: AppDelegate!

enum InjectionState: String {
    case ok = "OK"
    case idle = "Idle"
    case busy = "Busy"
    case ready = "Ready"
    case error = "Error"
}

@objc(AppDelegate)
class AppDelegate : NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet var statusItem: NSStatusItem!
    @IBOutlet var identityField: NSTextField!
    @IBOutlet var deviceTesting: NSButton!
    @IBOutlet var librariesField: NSTextField!
    @objc let defaults = UserDefaults.standard
    var compilerWork = false

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

        librariesField.stringValue = MonitorXcode.deviceLibraries
        InjectionServer.startServer(INJECTION_ADDRESS)
        setMenuIcon(.idle)

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
            MonitorXcode.xcodePath).deletingLastPathComponent()
        open.canChooseDirectories = false
        open.canChooseFiles = true
        if open.runModal() == .OK, let path = open.url?.path {
            MonitorXcode.xcodePath = path
            sender.toolTip = path
        }
    }
    
    lazy var startMulticastOnce: () = {
        InjectionServer.broadcastServe(HOTRELOADING_MULTICAST,
                                       port: HOTRELOADING_PORT)
    }()
    
    @IBAction func deviceEnable(_ sender: NSMenuItem) {
        sender.state = sender.state == .off ? .on : .off
        var openPort = ""
        if sender.state == .on {
            identityField.window?.makeKeyAndOrderFront(sender)
            _ = startMulticastOnce
            openPort = "*"
        }
        InjectionServer.stopServer()
        InjectionServer.startServer(openPort+INJECTION_ADDRESS)
    }
    
    @IBAction func compilerEnable(_ sender: NSMenuItem) {
        sender.state = sender.state == .off ? .on : .off
        compilerWork = sender.state == .on
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
        }
    }

    @IBAction func updateLibraries(_ sender: NSTextField) {
        MonitorXcode.deviceLibraries = librariesField.stringValue
    }

    @IBAction func unhideSymbols(_ sender: NSMenuItem) {
        Unhider.startUnhide()
    }

    @IBAction func resetUnhiding(_ sender: NSMenuItem) {
        Unhider.unhiddens.removeAll()
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
}
