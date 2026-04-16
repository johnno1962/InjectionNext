//
//  AppDelegate.swift
//  InjectionNext
//
//  Created by John Holdsworth on 06/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  Slim AppDelegate: no XIB outlets, servers + state bridge to ConfigStore.
//

import Cocoa
import Popen
import SwiftRegex

enum InjectionState: String {
    case ok = "OK"
    case idle = "Idle"
    case busy = "Busy"
    case ready = "Ready"
    case error = "Error"
}

class AppDelegate: NSObject, NSApplicationDelegate {

    static var ui: AppDelegate!

    @objc let defaults = UserDefaults.standard

    // MARK: - Compatibility shims for code that reads outlet state

    var enableDevicesEnabled: Bool = true
    var deviceTestingOn: Bool = false

    /// Mimics the old `enableDevicesItem.state` for ControlServer / other references.
    var enableDevicesItem: CompatMenuItem { CompatMenuItem(isOn: enableDevicesEnabled) }
    /// Mimics `watchDirectoryItem.state` for InjectionHybrid.
    var watchDirectoryItem: CompatMenuItem { CompatMenuItem(isOn: !Self.watchers.isEmpty) }
    /// Mimics `launchXcodeItem.state` for MonitorXcode.
    var launchXcodeItem: CompatMenuItem { CompatMenuItem(isOn: MonitorXcode.runningXcode != nil) }
    /// Mimics `patchCompilerItem` for Experimental.swift.
    var patchCompilerItem: NSMenuItem { NSMenuItem() }
    /// Mimics `selectXcodeItem.toolTip` for ControlServer.
    var selectXcodeItem: CompatMenuItem { CompatMenuItem(isOn: false) }

    /// Mimics `deviceTesting?.state` for NextCompiler.
    var deviceTesting: CompatButton? { CompatButton(isOn: ConfigStore.shared.devicesEnabled) }
    /// Mimics `librariesField.stringValue` for NextCompiler.
    var librariesField: CompatTextField { CompatTextField(value: ConfigStore.shared.deviceLibraries) }

    /// Mimics `codeSignBox.stringValue.containedSHA1` for NextCompiler.
    var codeSigningID: String {
        ConfigStore.shared.codesigningIdentity ?? ""
    }

    static let watchProjectMenuDefaultTitle = "...or Watch Project"

    lazy var startHostLocatingServerOnce: () = {
        InjectionServer.multicastServe(HOTRELOADING_MULTICAST,
                                       port: HOTRELOADING_PORT)
    }()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Self.ui = self

        Recompiler.onCompilationEvent = { file, status, detail in
            InjectionEventTracker.shared.emit(file, status: status, detail: detail)
        }

        signal(SIGPIPE, { which in
            print(APP_PREFIX+"⚠️ SIGPIPE #\(which)\n" +
                  Thread.callStackSymbols.map { var frame = $0
                        frame[#"(?:\S+\s+){3}(\S+)"#, 1] = {
                            (groups: [String], stop) in
                            return groups[1].swiftDemangle ?? groups[1] }
                        return frame
                    }.joined(separator: "\n")) })

        ControlServer.start()

        let config = ConfigStore.shared
        enableDevicesEnabled = config.devicesEnabled
        applyDeviceSettings(enabled: enableDevicesEnabled)

        if let xcodePath = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dt.Xcode")
            .first?.bundleURL?.path {
            if Defaults.xcodeDefault == nil {
                Defaults.xcodeDefault = xcodePath
            }
            if updatePatchUnpatch() == .unpatched &&
                !config.hideXcodeAlert {
                InjectionServer.alert("""
                    Please quit Xcode and
                    use this app to launch it
                    (unless you are using a file watcher).
                    """)
            }
        }

        if let project = Defaults.projectPath {
            launchXcodeWithProject(directory: project, config: config)
        } else if config.autoLaunchXcode && MonitorXcode.runningXcode == nil {
            _ = MonitorXcode()
        }
    }

    // MARK: - Menu Icon (bridges to ConfigStore)

    func setMenuIcon(_ state: InjectionState) {
        ConfigStore.shared.setInjectionState(state)
    }

    // MARK: - Watch Project (bridges to ConfigStore)

    func refreshWatchProjectMenuItem() {
        ConfigStore.shared.updateWatchingDirectories()
    }

    // MARK: - Device Settings

    func applyDeviceSettings(enabled: Bool) {
        enableDevicesEnabled = enabled
        var openPort = ""
        if enabled {
            _ = startHostLocatingServerOnce
            openPort = "*"
        }
        InjectionServer.stopLastServer()
        InjectionServer.startServer(openPort + INJECTION_ADDRESS)
    }

    // MARK: - Run Xcode

    func runXcode(_ sender: Any) {
        guard MonitorXcode.runningXcode == nil else { return }
        let config = ConfigStore.shared
        if let project = Defaults.projectPath {
            launchXcodeWithProject(directory: project, config: config)
        } else {
            _ = MonitorXcode()
        }
    }

    /// Discovers .xcodeproj/.xcworkspace files, shows a picker if needed,
    /// launches Xcode with the chosen project, and auto-watches the directory.
    func launchXcodeWithProject(directory: String, config: ConfigStore) {
        guard MonitorXcode.runningXcode == nil else { return }
        guard let resolved = ProjectDiscovery.resolveProject(
            in: directory, config: config) else { return }

        _ = MonitorXcode(args: " '\(resolved)'")

        Reloader.xcodeDev = config.xcodePath + "/Contents/Developer"
        watch(path: directory)
        config.updateWatchingDirectories()
    }

    func deviceEnable(_ sender: NSMenuItem?) {
        let newState = !enableDevicesEnabled
        enableDevicesEnabled = newState
        ConfigStore.shared.devicesEnabled = newState
        applyDeviceSettings(enabled: newState)
    }
}

// MARK: - Compatibility Types

/// Mimics NSMenuItem for code that reads `.state`.
struct CompatMenuItem {
    var state: NSControl.StateValue
    var toolTip: String?

    init(isOn: Bool) {
        self.state = isOn ? .on : .off
    }
}

/// Mimics NSButton for code that reads `.state`.
struct CompatButton {
    var state: NSControl.StateValue

    init(isOn: Bool) {
        self.state = isOn ? .on : .off
    }
}

/// Mimics NSTextField for code that reads `.stringValue`.
struct CompatTextField {
    var stringValue: String

    init(value: String) {
        self.stringValue = value
    }
}

// MARK: - SHA1 extraction (used by codesigning)

private extension String {
    var containedSHA1: String? { self[#"([0-9A-F]{40})"#] }
}

private extension NSControl.StateValue {
    @discardableResult
    mutating func toggle() -> Self {
        switch self {
        case .on:  self = .off
        case .off: self = .on
        default: break
        }
        return self
    }
}
