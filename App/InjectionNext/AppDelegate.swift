//
//  AppDelegate.swift
//  InjectionNext
//
//  Created by John Holdsworth on 06/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  Slim AppDelegate: no XIB outlets. UI is provided by SwiftUI
//  (InjectionNextApp + StatusMenuView). AppKit-era call sites keep
//  compiling through read/write Compat shims that route to ConfigStore.
//

import Cocoa
import Popen
import SwiftRegex

enum InjectionState: String {
    case ok = "OK"      // Orange
    case idle = "Idle"  // Blue
    case busy = "Busy"  // Green
    case ready = "Ready"// Purple
    case error = "Error"// Yellow
}

@objc(AppDelegate)
class AppDelegate: NSObject, NSApplicationDelegate {

    static var ui: AppDelegate!

    // MARK: - Compatibility shims (route to ConfigStore)

    /// Mimics `watchDirectoryItem.state` for ControlServer / InjectionHybrid.
    var watchDirectoryItem: CompatMenuItem {
        CompatMenuItem(
            get: { AppDelegate.watchers.isEmpty ? .off : .on },
            set: { _ in ConfigStore.shared.updateWatchingDirectories() }
        )
    }

    /// Mimics `enableDevicesItem.state` for ControlServer.
    var enableDevicesItem: CompatMenuItem {
        CompatMenuItem(
            get: { ConfigStore.shared.devicesEnabled ? .on : .off },
            set: { ConfigStore.shared.devicesEnabled = ($0 == .on) }
        )
    }

    /// Mimics `patchCompilerItem` — a real orphan NSMenuItem so
    /// `patchCompilerItem?.title = ...` and `prepareProject(item)` calls compile.
    var patchCompilerItem: NSMenuItem! { NSMenuItem() }

    /// Mimics `restartDeviceItem.state`.
    var restartDeviceItem: CompatMenuItem {
        CompatMenuItem(
            get: { ConfigStore.shared.xcodeRestart ? .on : .off },
            set: { ConfigStore.shared.xcodeRestart = ($0 == .on) }
        )
    }

    /// Mimics `deviceTesting?.state` for NextCompiler. Opt-in, *not* the same
    /// as `devicesEnabled` — gates whether we link `deviceLibraries`
    /// (XCTest + friends) into the injection dylib.
    var deviceTesting: CompatButton? {
        CompatButton(isOn: ConfigStore.shared.deviceTesting)
    }

    /// Mimics `librariesField.stringValue` for NextCompiler.
    var librariesField: CompatTextField {
        CompatTextField(
            get: { ConfigStore.shared.deviceLibraries },
            set: { ConfigStore.shared.deviceLibraries = $0 }
        )
    }

    /// Mimics `codeSignBox.stringValue.containedSHA1` for NextCompiler.
    var codeSigningID: String {
        ConfigStore.shared.codesigningIdentity ?? ""
    }

    // MARK: - Lifecycle

    lazy var startHostLocatingServerOnce: () = {
        InjectionServer.multicastServe(HOTRELOADING_MULTICAST,
                                       port: HOTRELOADING_PORT)
    }()

    @objc func applicationDidFinishLaunching(_ aNotification: Notification) {
        Self.ui = self

        // All TCP sockets in SimpleSocket are created with SO_NOSIGPIPE,
        // so any SIGPIPE we see comes from stdout/stderr or one of the
        // Popen(...) shell invocations writing to a broken pipe — in every
        // case write() returns EPIPE and the caller handles it. Ignoring
        // the signal outright avoids the async-signal-unsafe logging
        // handler that used to crash with _os_unfair_lock_recursive_abort.
        signal(SIGPIPE, SIG_IGN)

        setMenuIcon(.idle)

        // Populate the list of valid codesigning identities.
        ConfigStore.shared.discoverCodesigningIdentities()

        // Start injection server(s) for on-device/sim connections.
        if updatePatchUnpatch() == .patched {
            _ = FrontendServer.startOnce
        }
        deviceEnable(nil)

        if let xcodePath = MonitorXcode.externalXcode?.bundleURL?.path {
            if Defaults.xcodeDefault == nil {
                Defaults.xcodeDefault = xcodePath
            }
            if !ConfigStore.shared.hideXcodeAlert &&
                updatePatchUnpatch() == .unpatched &&
                getenv(INJECTION_HIDE_XCODE_ALERT) == nil {
                InjectionServer.alert("""
                    Please quit Xcode and
                    use this app to launch it
                    (unless you are using a file watcher).
                    """)
            }
        }

        if ConfigStore.shared.autoLaunchXcode {
            _ = MonitorXcode()
        }

        if Defaults.mcpServer {
            LogManager.shared.startCapturing()
            ControlServer.start()
        }
    }

    // MARK: - Status Icon (bridges to ConfigStore)

    func setMenuIcon(_ state: InjectionState) {
        DispatchQueue.main.async {
            ConfigStore.shared.setInjectionState(state)
            ConfigStore.shared.isClientConnected = InjectionServer.currentClient != nil
        }
    }

    // MARK: - Actions

    @IBAction func runXcode(_ sender: Any) {
        if MonitorXcode.runningXcode == nil {
            _ = MonitorXcode()
        }
    }

    @IBAction func selectXcode(_ sender: NSMenuItem) {
        let open = NSOpenPanel()
        open.prompt = "Select Xcode"
        open.directoryURL = URL(fileURLWithPath: Defaults.xcodePath)
        open.canChooseDirectories = false
        open.canChooseFiles = true
        if open.runModal() == .OK, let path = open.url?.path {
            Defaults.xcodeDefault = path
            updatePatchUnpatch()
            if Defaults.xcodeRestart {
                runXcode(sender)
            }
        }
    }

    @IBAction func deviceEnable(_ sender: NSMenuItem?) {
        var newState = ConfigStore.shared.devicesEnabled
        if sender != nil {
            newState.toggle()
            ConfigStore.shared.devicesEnabled = newState
        }
        applyDeviceSettings(enabled: newState, restartServer: sender != nil)
    }

    /// Starts or restarts the injection server using the given enabled state.
    /// Called from SwiftUI (`DevicesSettingsView`) and menu toggles.
    func applyDeviceSettings(enabled: Bool, restartServer: Bool = true) {
        var openPort = ""
        if enabled {
            _ = startHostLocatingServerOnce
            openPort = "*"
        }
        if restartServer { InjectionServer.stopLastServer() }
        InjectionServer.startServer(openPort+INJECTION_ADDRESS)
    }

    @IBAction func testingEnable(_ sender: NSButton) {
        deviceTestingToggled(enabled: sender.state == .on)
    }

    /// Called from the SwiftUI Device Testing toggle. When turning on, puts
    /// the copy_bundle.sh Run Script snippet on the pasteboard so the user
    /// can paste it into their target's Build Phases.
    func deviceTestingToggled(enabled: Bool) {
        guard enabled, let script = Bundle.main
            .url(forResource: "copy_bundle", withExtension: "sh") else { return }
        let buildPhase = """
            export RESOURCES="\(script.deletingLastPathComponent().path)"
            if [ -f "$RESOURCES/\(script.lastPathComponent)" ]; then
                "$RESOURCES/\(script.lastPathComponent)"
            fi
            """
        let pasteBoard = NSPasteboard.general
        pasteBoard.declareTypes([.string], owner: nil)
        pasteBoard.setString(buildPhase, forType: .string)
        InjectionServer.error("Run Script, Build Phase to " +
              "copy testing libraries added to clipboard.")
    }

    @IBAction func updateLibraries(_ sender: NSTextField) {
        Defaults.deviceLibraries = sender.stringValue
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
        // Retained for MCP/script compatibility. SwiftUI consoles
        // surface last errors via LogManager/ConsoleView instead.
        _ = NextCompiler.lastError
    }
}

// MARK: - Compatibility Types

/// Read/write shim mimicking `NSMenuItem` for code that still touches
/// `.state` / `.toolTip` / `.title`. Writes are routed to ConfigStore
/// via the supplied closures.
final class CompatMenuItem {
    private let getter: () -> NSControl.StateValue
    private let setter: ((NSControl.StateValue) -> Void)?
    var toolTip: String?
    var title: String = ""

    init(get: @escaping () -> NSControl.StateValue,
         set: ((NSControl.StateValue) -> Void)? = nil) {
        self.getter = get
        self.setter = set
    }

    var state: NSControl.StateValue {
        get { getter() }
        set { setter?(newValue) }
    }
}

/// Read shim mimicking `NSButton` for code that reads `.state`.
final class CompatButton {
    var state: NSControl.StateValue
    init(isOn: Bool) { self.state = isOn ? .on : .off }
}

/// Read/write shim mimicking `NSTextField` for code that touches
/// `.stringValue`. Writes are routed to ConfigStore.
final class CompatTextField {
    private let getter: () -> String
    private let setter: ((String) -> Void)?

    init(get: @escaping () -> String,
         set: ((String) -> Void)? = nil) {
        self.getter = get
        self.setter = set
    }

    var stringValue: String {
        get { getter() }
        set { setter?(newValue) }
    }
}

// MARK: - Helpers

private extension String {
    /// Returns the sha1 string contained in this string, or `nil` if none.
    var containedSHA1: String? { self[#"([0-9A-F]{40})"#] }
}

private extension NSControl.StateValue {
    @discardableResult
    mutating func toggle() -> Self {
        switch self {
        case .on:  self = .off
        case .off: self = .on
        case .mixed: self = .mixed
        default: break
        }
        return self
    }
}
