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
import DLKit
import Darwin

// MARK: - Enums

enum BuildSystem: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case xcode = "Xcode"
    case bazel = "Bazel"
    case spm = "Swift Package Manager"
    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .auto:  return "Auto"
        case .xcode: return "Xcode"
        case .bazel: return "Bazel"
        case .spm:   return "SPM"
        }
    }

    var symbolName: String {
        switch self {
        case .auto:  return "questionmark.circle"
        case .xcode: return "hammer"
        case .bazel: return "cube"
        case .spm:   return "shippingbox"
        }
    }
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

/// Preset flag combinations passed to `dlopen` when DLKit loads an
/// injected dylib. Exposed as `DLKit.dlOpenMode` for overrides.
enum DLOpenMode: String, CaseIterable, Identifiable {
    /// Recommended default: bind symbols lazily, expose globally so
    /// later injections can resolve each other's symbols.
    case lazyGlobal = "Lazy + Global (default)"
    /// Eager resolution, globally visible so injected modules can
    /// cross-reference each other.
    case nowGlobal  = "Now + Global"
    /// Eager resolution, kept in the loader's local namespace — symbols
    /// are NOT merged into the global table. Strictest isolation.
    case now        = "Now (local only)"
    var id: String { rawValue }

    var flags: Int32 {
        switch self {
        case .lazyGlobal: return RTLD_LAZY | RTLD_GLOBAL
        case .nowGlobal:  return RTLD_NOW  | RTLD_GLOBAL
        case .now:        return RTLD_NOW
        }
    }

    /// Short one-liner shown under the picker.
    var shortDescription: String {
        switch self {
        case .lazyGlobal: return "Default. Fast loads, symbols resolve on first call."
        case .nowGlobal:  return "Eager + shared. Fails fast when symbols are missing."
        case .now:        return "Eager + isolated. No cross-injection symbol sharing."
        }
    }

    /// Longer help text — suitable for tooltips / info popovers.
    var helpText: String {
        switch self {
        case .lazyGlobal:
            return "RTLD_LAZY | RTLD_GLOBAL — resolves symbols on first use and publishes them to the global namespace. Best for normal hot-reload; later injections can see symbols defined by earlier ones."
        case .nowGlobal:
            return "RTLD_NOW | RTLD_GLOBAL — resolves every symbol at load time and publishes them globally. Surfaces missing symbols immediately; useful when diagnosing failed injections while keeping cross-dylib references working."
        case .now:
            return "RTLD_NOW — resolves every symbol at load time but keeps them private to this dylib (no RTLD_GLOBAL). Strict isolation: each injection is self-contained and cannot satisfy symbol lookups for later injections. Use when tracking down leaks between injected modules."
        }
    }
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
    @Published var haveLaunchedXocde = false
    @Published var isClientConnected = false
    @Published var watchingDirectories: [String] = []

    var statusIcon: NSImage {
        let assetName: String
        switch injectionState {
        case .idle:  assetName = "INJECTION_BLUE"
        case .ok:    assetName = "INJECTION_ORANGE"
        case .busy:  assetName = "INJECTION_PURPLE"
        case .ready: assetName = "INJECTION_GREEN"
        case .error: assetName = "INJECTION_RED"
        }
        if let image = NSImage(named: assetName) {
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

    /// User-facing selection (may be `.auto`).
    @Published var buildSystem: BuildSystem {
        didSet {
            ud.set(buildSystem.rawValue, forKey: "buildSystem")
            applyBuildSystemOverride()
        }
    }

    /// Build system detected from the currently selected / watched project.
    /// Returns `nil` when nothing is selected or the type can't be determined.
    /// When the user forces a non-Bazel build system via `buildSystem`, Bazel
    /// detection is skipped entirely so we never shell out to `bazel query`.
    var detectedBuildSystem: BuildSystem? {
        let bazelAllowed = buildSystem == .auto || buildSystem == .bazel
        let candidates = [defaultProjectFile]
            + watchingDirectories
            + (projectPath.isEmpty ? [] : [projectPath])

        for path in candidates where !path.isEmpty {
            // Prefer Bazel detection: an .xcodeproj generated by
            // rules_xcodeproj lives inside a Bazel workspace alongside a
            // BUILD file, so plain `.xcodeproj` suffix is not enough to
            // classify it as Xcode.
            if bazelAllowed,
               BazelInterface.findWorkspaceRoot(containing: path) != nil {
                return .bazel
            }
            if path.hasSuffix(".xcodeproj") || path.hasSuffix(".xcworkspace") {
                return .xcode
            }

            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                if let entries = try? FileManager.default.contentsOfDirectory(atPath: path) {
                    if bazelAllowed, entries.contains(where: {
                        $0 == "MODULE.bazel" || $0 == "MODULE" ||
                        $0 == "WORKSPACE" || $0 == "WORKSPACE.bazel"
                    }) {
                        return .bazel
                    }
                    if entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
                        return .xcode
                    }
                    if entries.contains("Package.swift") {
                        return .spm
                    }
                }
            }
        }
        return nil
    }

    /// The build system actually in effect: honors the override when not `.auto`,
    /// otherwise returns the detected value (nil if nothing selected).
    var effectiveBuildSystem: BuildSystem? {
        buildSystem == .auto ? detectedBuildSystem : buildSystem
    }

    /// Propagate the user override to the low-level Bazel detector and
    /// invalidate any cached workspace lookups so already-seen sources
    /// re-route through the Xcode log parser on the next injection.
    private func applyBuildSystemOverride() {
        Recompiler.workspaceCache.removeAll()
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
        didSet { ud.set(preserveStatics, forKey: "preserveStatics"); updateEnvVars() }
    }
    @Published var disableStandalone: Bool { // difficult to implement without connection.
        didSet { ud.set(disableStandalone, forKey: "disableStandalone") }
    }
    @Published var genericsMode: GenericsMode { // difficult to implement early.
        didSet { ud.set(genericsMode.rawValue, forKey: "genericsMode") }
    }
    @Published var keyPathsMode: KeyPathsMode { // difficult to implement early.
        didSet { ud.set(keyPathsMode.rawValue, forKey: "keyPathsMode") }
    }
    @Published var sweepExclude: String {
        didSet { ud.set(sweepExclude, forKey: "sweepExclude"); updateEnvVars() }
    }
    @Published var sweepDetail: Bool {
        didSet { ud.set(sweepDetail, forKey: "sweepDetail"); updateEnvVars() }
    }
    
    func updateEnvVars() {
        let clients = InjectionServer.currentClients
        InjectionServer.clientQueue.async {
            for client in clients where client != nil {
                self.sendEnvVars(to: client!)
            }
        }
    }
    
    func sendEnvVars(to client: InjectionServer) {
        client.writeCommand(InjectionCommand.setenv.rawValue,
                            with: INJECTION_PRESERVE_STATICS)
        client.write(preserveStatics ? "1" : "0")
        client.writeCommand(InjectionCommand.setenv.rawValue,
                            with: INJECTION_SWEEP_DETAIL)
        client.write(sweepDetail ? "1" : "0")
        if sweepExclude != "" {
            client.writeCommand(InjectionCommand.setenv.rawValue,
                                with: INJECTION_SWEEP_EXCLUDE)
            client.write(sweepExclude)
        }
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
    /// Opt-in: link `deviceLibraries` (XCTest + friends) into the injection
    /// dylib. Off by default because apps that don't link XCTest themselves
    /// will crash at dlopen with `Library not loaded: @rpath/XCTest.framework/XCTest`.
    /// Enable only when `copy_bundle.sh` has been added as a Run Script build phase
    /// so the test frameworks are shipped inside the app.
    @Published var deviceTesting: Bool {
        didSet { ud.set(deviceTesting, forKey: "deviceTesting") }
    }
    @Published var availableIdentities: [String] = []

    // MARK: - Tracing // difficult to implement as tracing happens early.

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
    @Published var dlOpenMode: DLOpenMode {
        didSet {
            ud.set(dlOpenMode.rawValue, forKey: "dlOpenMode")
            DLKit.dlOpenMode = dlOpenMode.flags
        }
    }
    /// Opt-in MCP server (ControlServer + LogBuffer). Default off; enable with:
    /// `defaults write com.johnholdsworth.InjectionNext mcpServer -bool true`
    @Published var mcpServer: Bool {
        didSet { ud.set(mcpServer, forKey: "mcpServer") }
    }

    // MARK: - Init

    private init() {
        // Xcode
        self.xcodePath = ud.string(forKey: "XcodePath") ?? "/Applications/Xcode.app"
        self.autoLaunchXcode = ud.bool(forKey: "autoLaunchXcode")
        self.xcodeRestart = ud.value(forKey: "xcodeRestartDefault") == nil ? true : ud.bool(forKey: "xcodeRestartDefault")
        self.hideXcodeAlert = ud.bool(forKey: "hideXcodeAlert")

        // Build System
        self.buildSystem = BuildSystem(rawValue: ud.string(forKey: "buildSystem") ?? "") ?? .auto
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
        self.deviceTesting = ud.bool(forKey: "deviceTesting")

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
        self.mcpServer = ud.bool(forKey: "mcpServer")
        self.dlOpenMode = DLOpenMode(rawValue: ud.string(forKey: "dlOpenMode") ?? "") ?? .lazyGlobal
        DLKit.dlOpenMode = self.dlOpenMode.flags

        // Auto-detect running Xcode on launch
        if ud.string(forKey: "XcodePath") == nil,
           let runningXcode = MonitorXcode.externalXcode?.bundleURL?.path {
            self.xcodePath = runningXcode
        }

        discoverXcodes()
        discoverCodesigningIdentities()

        applyBuildSystemOverride()
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
        if Thread.isMainThread {
            injectionState = state
        } else {
            DispatchQueue.main.async { [weak self] in self?.injectionState = state }
        }
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
        buildSystem = .auto
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
        deviceTesting = false
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
        mcpServer = false
        dlOpenMode = .lazyGlobal
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
    static var deviceTesting: Bool {
        get { ConfigStore.shared.deviceTesting }
        set { ConfigStore.shared.deviceTesting = newValue }
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
    static var mcpServer: Bool {
        get { ConfigStore.shared.mcpServer }
        set { ConfigStore.shared.mcpServer = newValue }
    }
}
