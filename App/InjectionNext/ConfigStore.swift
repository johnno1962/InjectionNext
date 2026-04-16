//
//  ConfigStore.swift
//  InjectionNext
//
//  Central observable configuration store.
//  Replaces Defaults.swift with explicit, user-driven settings.
//

import SwiftUI
import Combine
import Popen

// MARK: - Enums

enum BuildSystem: String, CaseIterable, Identifiable {
    case xcode = "Xcode"
    case bazel = "Bazel"
    case spm = "Swift Package Manager"
    var id: String { rawValue }
}

enum GenericsMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case legacy = "Legacy (Object Sweep)"
    case disabled = "Disabled"
    var id: String { rawValue }
}

enum KeyPathsMode: String, CaseIterable, Identifiable {
    case auto = "Auto (TCA detection)"
    case enabled = "Always Enabled"
    case disabled = "Disabled"
    var id: String { rawValue }
}

enum TraceMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case injected = "Injected Functions"
    case all = "All Functions"
    var id: String { rawValue }
}

// MARK: - Xcode Installation

struct XcodeInstallation: Identifiable, Hashable {
    let id: String // path
    let path: String
    let version: String
    let buildVersion: String
    var displayName: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return "\(name) (\(version) - \(buildVersion))"
    }
}

// MARK: - ConfigStore

final class ConfigStore: ObservableObject {

    static let shared = ConfigStore()

    let ud = UserDefaults.standard

    // MARK: - General (read-only)

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    var buildNumber: String {
        Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String ?? "?"
    }

    // MARK: - Injection State (published, not persisted)

    @Published var injectionState: InjectionState = .idle
    @Published var isXcodeRunning = false
    @Published var isClientConnected = false
    @Published var watchingDirectories: [String] = []

    var statusIcon: NSImage {
        let tiffName = "Injection" + injectionState.rawValue
        if let path = Bundle.main.path(forResource: tiffName, ofType: "tif"),
           let image = NSImage(contentsOfFile: path) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "InjectionNext")!
    }

    // MARK: - Xcode

    @Published var xcodePath: String {
        didSet { ud.set(xcodePath, forKey: "XcodePath") }
    }
    @Published var autoLaunchXcode: Bool {
        didSet { ud.set(autoLaunchXcode, forKey: "autoLaunchXcode") }
    }
    @Published var xcodeRestart: Bool {
        didSet { ud.set(xcodeRestart, forKey: "xcodeRestartDefault") }
    }
    @Published var hideXcodeAlert: Bool {
        didSet { ud.set(hideXcodeAlert, forKey: "hideXcodeAlert") }
    }
    @Published var availableXcodes: [XcodeInstallation] = []

    // MARK: - Build System

    @Published var buildSystem: BuildSystem {
        didSet { ud.set(buildSystem.rawValue, forKey: "buildSystem") }
    }
    @Published var bazelPath: String {
        didSet { ud.set(bazelPath, forKey: "bazelPath") }
    }
    @Published var bazelTarget: String {
        didSet { ud.set(bazelTarget, forKey: "bazelTarget") }
    }
    @Published var xcrunPath: String {
        didSet { ud.set(xcrunPath, forKey: "xcrunPath") }
    }

    // MARK: - Compiler

    @Published var interceptCompiler: Bool = false
    @Published var emitFrontendCommandLines: Bool {
        didSet { ud.set(emitFrontendCommandLines, forKey: "emitFrontendCommandLines") }
    }

    var compilerState: FrontendServer.State {
        FileManager.default.fileExists(atPath: FrontendServer.patched) ? .patched : .unpatched
    }

    // MARK: - Injection

    @Published var projectPath: String {
        didSet { ud.set(projectPath, forKey: "projectPath") }
    }
    /// Remembers which .xcodeproj/.xcworkspace the user last chose inside projectPath.
    @Published var defaultProjectFile: String {
        didSet { ud.set(defaultProjectFile, forKey: "defaultProjectFile") }
    }
    /// Skip the picker dialog and always open the remembered project file.
    @Published var autoOpenDefaultProject: Bool {
        didSet { ud.set(autoOpenDefaultProject, forKey: "autoOpenDefaultProject") }
    }
    @Published var preserveStatics: Bool {
        didSet { ud.set(preserveStatics, forKey: "preserveStatics") }
    }
    @Published var disableStandalone: Bool {
        didSet { ud.set(disableStandalone, forKey: "disableStandalone") }
    }
    @Published var genericsMode: GenericsMode {
        didSet { ud.set(genericsMode.rawValue, forKey: "genericsMode") }
    }
    @Published var keyPathsMode: KeyPathsMode {
        didSet { ud.set(keyPathsMode.rawValue, forKey: "keyPathsMode") }
    }
    @Published var sweepExclude: String {
        didSet { ud.set(sweepExclude, forKey: "sweepExclude") }
    }
    @Published var sweepDetail: Bool {
        didSet { ud.set(sweepDetail, forKey: "sweepDetail") }
    }

    // MARK: - Devices

    @Published var devicesEnabled: Bool {
        didSet { ud.set(devicesEnabled, forKey: "devicesEnabled") }
    }
    @Published var codesigningIdentity: String? {
        didSet { ud.set(codesigningIdentity, forKey: "codesigningIdentity") }
    }
    @Published var deviceLibraries: String {
        didSet { ud.set(deviceLibraries, forKey: "libraries") }
    }
    @Published var availableIdentities: [String] = []

    // MARK: - Tracing

    @Published var traceMode: TraceMode {
        didSet { ud.set(traceMode.rawValue, forKey: "traceMode") }
    }
    @Published var traceFilter: String {
        didSet { ud.set(traceFilter, forKey: "traceFilter") }
    }
    @Published var traceFrameworks: String {
        didSet { ud.set(traceFrameworks, forKey: "traceFrameworks") }
    }
    @Published var traceLookup: Bool {
        didSet { ud.set(traceLookup, forKey: "traceLookup") }
    }
    @Published var traceUIKit: String {
        didSet { ud.set(traceUIKit, forKey: "traceUIKit") }
    }

    // MARK: - File Watcher

    @Published var fileWatcherLatency: Double {
        didSet { ud.set(fileWatcherLatency, forKey: "fileWatcherLatency") }
    }
    @Published var injectablePattern: String {
        didSet { ud.set(injectablePattern, forKey: "injectablePattern") }
    }

    // MARK: - Network (mostly read-only display)

    @Published var injectionHost: String {
        didSet { ud.set(injectionHost, forKey: "injectionHost") }
    }
    let injectionPort: String = HOTRELOADING_PORT
    let controlPort: UInt16 = 8919

    // MARK: - Advanced

    @Published var verboseLogging: Bool {
        didSet { ud.set(verboseLogging, forKey: "verboseLogging") }
    }
    @Published var benchmarking: Bool {
        didSet { ud.set(benchmarking, forKey: "benchmarking") }
    }

    // MARK: - Init

    private init() {
        // Xcode
        self.xcodePath = ud.string(forKey: "XcodePath") ?? "/Applications/Xcode.app"
        self.autoLaunchXcode = ud.bool(forKey: "autoLaunchXcode")
        self.xcodeRestart = ud.value(forKey: "xcodeRestartDefault") == nil ? true : ud.bool(forKey: "xcodeRestartDefault")
        self.hideXcodeAlert = ud.bool(forKey: "hideXcodeAlert")

        // Build System
        self.buildSystem = BuildSystem(rawValue: ud.string(forKey: "buildSystem") ?? "") ?? .xcode
        self.bazelPath = ud.string(forKey: "bazelPath") ?? ""
        self.bazelTarget = ud.string(forKey: "bazelTarget") ?? ""
        self.xcrunPath = ud.string(forKey: "xcrunPath") ?? "/usr/bin/xcrun"

        // Compiler
        self.emitFrontendCommandLines = ud.bool(forKey: "emitFrontendCommandLines")

        // Injection
        self.projectPath = ud.string(forKey: "projectPath") ?? ""
        self.defaultProjectFile = ud.string(forKey: "defaultProjectFile") ?? ""
        self.autoOpenDefaultProject = ud.bool(forKey: "autoOpenDefaultProject")
        self.preserveStatics = ud.bool(forKey: "preserveStatics")
        self.disableStandalone = ud.bool(forKey: "disableStandalone")
        self.genericsMode = GenericsMode(rawValue: ud.string(forKey: "genericsMode") ?? "") ?? .auto
        self.keyPathsMode = KeyPathsMode(rawValue: ud.string(forKey: "keyPathsMode") ?? "") ?? .auto
        self.sweepExclude = ud.string(forKey: "sweepExclude") ?? ""
        self.sweepDetail = ud.bool(forKey: "sweepDetail")

        // Devices
        self.devicesEnabled = ud.bool(forKey: "devicesEnabled")
        self.codesigningIdentity = ud.string(forKey: "codesigningIdentity")
        self.deviceLibraries = ud.string(forKey: "libraries") ?? "-framework XCTest -lXCTestSwiftSupport"

        // Tracing
        self.traceMode = TraceMode(rawValue: ud.string(forKey: "traceMode") ?? "") ?? .off
        self.traceFilter = ud.string(forKey: "traceFilter") ?? ""
        self.traceFrameworks = ud.string(forKey: "traceFrameworks") ?? ""
        self.traceLookup = ud.bool(forKey: "traceLookup")
        self.traceUIKit = ud.string(forKey: "traceUIKit") ?? ""

        // File Watcher
        self.fileWatcherLatency = ud.double(forKey: "fileWatcherLatency") == 0 ? 0.1 : ud.double(forKey: "fileWatcherLatency")
        self.injectablePattern = ud.string(forKey: "injectablePattern") ?? #"[^~]\.(mm?|cpp|cc|swift|lock|o)$"#

        // Network
        self.injectionHost = ud.string(forKey: "injectionHost") ?? "127.0.0.1"

        // Advanced
        self.verboseLogging = ud.bool(forKey: "verboseLogging")
        self.benchmarking = ud.bool(forKey: "benchmarking")

        // Auto-detect running Xcode on launch
        if ud.string(forKey: "XcodePath") == nil,
           let runningXcode = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dt.Xcode")
            .first?.bundleURL?.path {
            self.xcodePath = runningXcode
        }

        discoverXcodes()
        discoverCodesigningIdentities()
    }

    // MARK: - Discovery

    func discoverXcodes() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var installations = [XcodeInstallation]()

            let pipe = Popen(cmd: "mdfind \"kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'\"")
            while let path = pipe?.readLine() {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let plistPath = trimmed + "/Contents/Info.plist"
                guard let plist = NSDictionary(contentsOfFile: plistPath) else { continue }
                let version = plist["CFBundleShortVersionString"] as? String ?? "?"
                let build = plist["DTXcodeBuild"] as? String ?? "?"
                installations.append(XcodeInstallation(
                    id: trimmed, path: trimmed, version: version, buildVersion: build))
            }

            installations.sort { $0.version > $1.version }

            DispatchQueue.main.async {
                self?.availableXcodes = installations
            }
        }
    }

    func discoverCodesigningIdentities() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var identities = [String]()
            let security = Topen(exec: "/usr/bin/security",
                                 arguments: ["find-identity", "-v", "-p", "codesigning"])
            while let line = security.readLine() {
                let components = line.split(separator: ")", maxSplits: 1)
                if components.count >= 2 {
                    identities.append(String(components[1]))
                }
            }
            DispatchQueue.main.async {
                self?.availableIdentities = identities
            }
        }
    }

    // MARK: - Actions

    func setInjectionState(_ state: InjectionState) {
        DispatchQueue.main.async { self.injectionState = state }
    }

    func updateWatchingDirectories() {
        DispatchQueue.main.async {
            self.watchingDirectories = Array(AppDelegate.watchers.keys.sorted())
        }
    }

    func resetAllSettings() {
        let domain = Bundle.main.bundleIdentifier!
        ud.removePersistentDomain(forName: domain)
        ud.synchronize()

        xcodePath = "/Applications/Xcode.app"
        autoLaunchXcode = false
        xcodeRestart = true
        hideXcodeAlert = false
        buildSystem = .xcode
        bazelPath = ""
        bazelTarget = ""
        xcrunPath = "/usr/bin/xcrun"
        emitFrontendCommandLines = false
        projectPath = ""
        defaultProjectFile = ""
        autoOpenDefaultProject = false
        preserveStatics = false
        disableStandalone = false
        genericsMode = .auto
        keyPathsMode = .auto
        sweepExclude = ""
        sweepDetail = false
        devicesEnabled = false
        codesigningIdentity = nil
        deviceLibraries = "-framework XCTest -lXCTestSwiftSupport"
        traceMode = .off
        traceFilter = ""
        traceFrameworks = ""
        traceLookup = false
        traceUIKit = ""
        fileWatcherLatency = 0.1
        injectablePattern = #"[^~]\.(mm?|cpp|cc|swift|lock|o)$"#
        injectionHost = "127.0.0.1"
        verboseLogging = false
        benchmarking = false
    }
}

// MARK: - Project Discovery

struct DiscoveredProject: Identifiable, Hashable {
    let path: String
    var id: String { path }

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var isWorkspace: Bool { path.hasSuffix(".xcworkspace") }
    var icon: String { isWorkspace ? "building.2" : "hammer" }
}

enum ProjectDiscovery {

    static func discoverProjects(in directory: String) -> [DiscoveredProject] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

        let ignoredWorkspaces: Set<String> = ["project.xcworkspace"]

        var projects = [DiscoveredProject]()
        for item in contents.sorted() {
            let full = (directory as NSString).appendingPathComponent(item)
            if item.hasSuffix(".xcworkspace") && !ignoredWorkspaces.contains(item) {
                projects.append(DiscoveredProject(path: full))
            } else if item.hasSuffix(".xcodeproj") {
                projects.append(DiscoveredProject(path: full))
            }
        }
        return projects
    }

    /// Returns the project file to open:
    /// - If only one exists, returns it directly.
    /// - If a remembered default matches, returns it (when `autoOpen` is true).
    /// - Otherwise shows a picker alert and returns the user's choice (or nil on cancel).
    @MainActor
    static func resolveProject(in directory: String,
                                config: ConfigStore) -> String? {
        let projects = discoverProjects(in: directory)
        guard !projects.isEmpty else { return directory }

        if projects.count == 1 {
            let chosen = projects[0].path
            config.defaultProjectFile = chosen
            return chosen
        }

        if config.autoOpenDefaultProject,
           !config.defaultProjectFile.isEmpty,
           projects.contains(where: { $0.path == config.defaultProjectFile }) {
            return config.defaultProjectFile
        }

        return showProjectPicker(projects: projects, directory: directory, config: config)
    }

    @MainActor
    private static func showProjectPicker(projects: [DiscoveredProject],
                                           directory: String,
                                           config: ConfigStore) -> String? {
        let picker = ProjectPickerWindow(
            projects: projects,
            directory: directory,
            initialSelection: config.defaultProjectFile,
            rememberChoice: config.autoOpenDefaultProject
        )
        NSApp.activate(ignoringOtherApps: true)
        let result = picker.runModal()

        switch result {
        case .launch(let path, let remember):
            config.defaultProjectFile = path
            config.autoOpenDefaultProject = remember
            return path

        case .newWatcher(let remember):
            let open = NSOpenPanel()
            open.prompt = "Select Project or Workspace"
            open.directoryURL = URL(fileURLWithPath: directory)
            open.canChooseDirectories = false
            open.canChooseFiles = true
            open.allowedContentTypes = [.folder]
            open.allowsOtherFileTypes = true
            guard open.runModal() == .OK, let url = open.url,
                  url.pathExtension == "xcodeproj" || url.pathExtension == "xcworkspace" else {
                return nil
            }
            let chosen = url.path
            config.defaultProjectFile = chosen
            config.autoOpenDefaultProject = remember
            return chosen

        case .cancel:
            return nil
        }
    }
}

// MARK: - Project Picker Window

private enum ProjectPickerResult {
    case launch(path: String, remember: Bool)
    case newWatcher(remember: Bool)
    case cancel
}

@MainActor
private final class ProjectPickerWindow: NSObject {
    private let window: NSPanel
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let checkbox = NSButton(checkboxWithTitle: "Always open this project",
                                    target: nil, action: nil)
    private let projects: [DiscoveredProject]
    private var result: ProjectPickerResult = .cancel

    init(projects: [DiscoveredProject],
         directory: String,
         initialSelection: String,
         rememberChoice: Bool) {
        self.projects = projects

        let width: CGFloat = 440
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 10),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.level = .modalPanel

        super.init()

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),
        ])

        let title = NSTextField(labelWithString: "Multiple Projects Found")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString:
            "Choose which project to open in Xcode from: "
            + URL(fileURLWithPath: directory).lastPathComponent)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        for project in projects {
            let prefix = project.isWorkspace ? "⚙️  " : "🔨  "
            popup.addItem(withTitle: prefix + project.name)
        }
        if let idx = projects.firstIndex(where: { $0.path == initialSelection }) {
            popup.selectItem(at: idx)
        }

        checkbox.state = rememberChoice ? .on : .off

        let newWatcher = Self.makeButton(title: "+ New Watcher",
                                          action: #selector(newWatcherClicked))
        let cancel = Self.makeButton(title: "Cancel",
                                      action: #selector(cancelClicked),
                                      keyEquivalent: "\u{1b}")
        let launch = Self.makeButton(title: "Launch",
                                      action: #selector(launchClicked),
                                      keyEquivalent: "\r",
                                      prominent: true)
        [newWatcher, cancel, launch].forEach { $0.target = self }

        let buttonRow = NSStackView(views: [newWatcher, cancel, launch])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let header = NSStackView(views: [iconView, textStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        let content = NSStackView(views: [header, popup, checkbox, buttonRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 20, right: 22)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.setCustomSpacing(18, after: header)
        content.setCustomSpacing(8, after: popup)
        content.setCustomSpacing(18, after: checkbox)

        let root = NSView()
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            popup.widthAnchor.constraint(equalToConstant: width - 44),
            buttonRow.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44),
        ])

        window.contentView = root
        window.defaultButtonCell = (launch.cell as? NSButtonCell)
        window.initialFirstResponder = launch
    }

    private static func makeButton(title: String,
                                    action: Selector,
                                    keyEquivalent: String = "",
                                    prominent: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: nil, action: action)
        b.bezelStyle = .rounded
        b.keyEquivalent = keyEquivalent
        b.controlSize = .large
        if prominent, #available(macOS 11.0, *) {
            b.hasDestructiveAction = false
            b.bezelColor = .controlAccentColor
        }
        return b
    }

    func runModal() -> ProjectPickerResult {
        window.center()
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return result
    }

    @objc private func launchClicked() {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0 && idx < projects.count else {
            result = .cancel
            NSApp.stopModal()
            return
        }
        result = .launch(path: projects[idx].path, remember: checkbox.state == .on)
        NSApp.stopModal()
    }

    @objc private func newWatcherClicked() {
        result = .newWatcher(remember: checkbox.state == .on)
        NSApp.stopModal()
    }

    @objc private func cancelClicked() {
        result = .cancel
        NSApp.stopModal()
    }
}

// MARK: - Backward Compatibility

struct Defaults {
    static let userDefaults = UserDefaults.standard
    static let xcodePathDefault = "XcodePath"
    static let librariesDefault = "libraries"
    static let codesigningDefault = "codesigningIdentity"
    static let projectPathDefault = "projectPath"

    static var xcodePath: String {
        ConfigStore.shared.xcodePath
    }
    static var xcodeDefault: String? {
        get { ConfigStore.shared.ud.string(forKey: xcodePathDefault) }
        set {
            if let val = newValue {
                ConfigStore.shared.xcodePath = val
            }
        }
    }
    static var deviceLibraries: String {
        get { ConfigStore.shared.deviceLibraries }
        set { ConfigStore.shared.deviceLibraries = newValue }
    }
    static var codesigningIdentity: String? {
        get { ConfigStore.shared.codesigningIdentity }
        set { ConfigStore.shared.codesigningIdentity = newValue }
    }
    static var xcodeRestart: Bool {
        get { ConfigStore.shared.xcodeRestart }
        set { ConfigStore.shared.xcodeRestart = newValue }
    }
    static var projectPath: String? {
        get {
            let val = ConfigStore.shared.projectPath
            return val.isEmpty ? nil : val
        }
    }
}
