//
//  InjectionHybrid.swift
//  InjectionNext
//
//  Created by John Holdsworth on 09/11/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Provide file watcher/log parser fallback
//  for use outside Xcode (e.g. Cursor/VSCode)
//  Also uses FileWatcher for operation when
//  swift-frontend has been replaced by a
//  script to capture compiler invocations.
//
import Cocoa

extension AppDelegate {
    static var watchers = [String: InjectionHybrid]()
    static var lastWatched: String?

    @IBAction func watchProject(_ sender: NSMenuItem) {
        let open = NSOpenPanel()
        open.prompt = "Select Project Directory"
        open.canChooseDirectories = true
        open.canChooseFiles = false
        // open.showsHiddenFiles = TRUE;
        if open.runModal() == .OK, let url = open.url {
            Reloader.xcodeDev = Defaults.xcodePath+"/Contents/Developer"
            watch(path: url.path)
        } else {
            Self.watchers.removeAll()
            Self.lastWatched = nil
        }
    }

    func watch(path: String) {
        guard Self.alreadyWatching(path) == nil else { return }
        GitIgnoreParser.monitor(directory: path)
        Self.watchers[path] = InjectionHybrid(watching: path)
        Self.lastWatched = path
        watchDirectoryItem.state = Self.watchers.isEmpty ? .off : .on
    }
    static func alreadyWatching(_ projectRoot: String) -> String? {
        return Self.watchers[projectRoot] != nil ? projectRoot :
            watchers.keys.first { projectRoot.hasPrefix($0+"/") }
    }
    static func restartLastWatcher() {
        DispatchQueue.main.async {
            lastWatched.flatMap { watchers[$0]?.watcher?.restart() }
        }
    }
}

class InjectionHybrid: InjectionBase {
    /// Last Injected for deduplication
    static var lastInjected = [String: TimeInterval]()
    /// Last queue of file changes
    static var pendingFilesChanged = [String]()
    /// Repository locked state - stops processing until app reconnects
    static var isRepositoryLocked = false
    /// Path to detected git lock file - used to check if git operation still active
    static var gitLockPath: String?
    /// InjectionNext compiler that uses InjectionLite log parser
    var logParsingCompiler: NextCompiler = HybridCompiler(name: "BuildLogs")
    /// Minimum seconds between injections
    let minInterval = 1.0

    init(watching path: String) { // FileWatcher compatibility
        let watchPaths = (getenv(INJECTION_DIRECTORIES) == nil ?
            NSHomeDirectory()+"/Library/Developer," : "") + path
        setenv(INJECTION_DIRECTORIES, watchPaths, 1)
        Reloader.injectionQueue = .main
        super.init()
        // Extend FileWatcher pattern to detect git lock files
        FileWatcher.INJECTABLE_PATTERN = try! NSRegularExpression(
            pattern: ConfigStore.shared.injectablePattern)
    }

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        // Detect git lock files - record path for later checking
        if source.hasSuffix(".lock") &&
           source.contains("/.git/") {
            Self.gitLockPath = source
            return
        }

        // Skip processing if repository is already locked
        if Self.isRepositoryLocked {
            log("""
                File processing stopped due to git lock. \
                Please relaunch your app to resume injection.
                """)
            return
        }

        // Check if source file is changing while git lock still exists
        if let lockPath = Self.gitLockPath {
            if FileManager.default.fileExists(atPath: lockPath) {
                // Source files changing while git lock exists = branch switch/merge/rebase
                Self.isRepositoryLocked = true
                Self.pendingFilesChanged.removeAll()
                Self.gitLockPath = nil
                log("""
                    Git operation in progress (branch switch/merge/rebase detected). \
                    File processing stopped. Please relaunch your app to resume injection.
                    """)
                return
            } else {
                // Lock file is gone - was probably just a commit
                Self.gitLockPath = nil
            }
        }

        let now = Date.timeIntervalSinceReferenceDate
        guard !AppDelegate.watchers.isEmpty, now - (
                Self.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        Self.lastInjected[source] = now

        Self.pendingFilesChanged.append(source)
        NextCompiler.compileQueue.async {
            self.injectNext()
        }
    }

    func injectNext() {
        guard let source = (DispatchQueue.main.sync { () -> String? in
            guard let source = Self.pendingFilesChanged.first else { return nil }
            Self.pendingFilesChanged.removeAll(where: { $0 == source })
            if !Self.pendingFilesChanged.isEmpty {
                NextCompiler.compileQueue.async { self.injectNext() }
            }
            return source
        }) else { return }

        autoreleasepool {
        var recompiler = MonitorXcode.recompiler
        let platform = FrontendServer.clientPlatform
        if recompiler.canCompile(source: source, for: platform),
           recompiler.inject(source: source) { return }

        recompiler = logParsingCompiler
        if source.hasSuffix(".swift") &&
            AppDelegate.ui.updatePatchUnpatch() == .patched {
            let proxyCompiler = FrontendServer.frontendRecompiler(for: platform)
            if proxyCompiler.canCompile(source: source) {
                recompiler = proxyCompiler
            }
        }

        if let why = GitIgnoreParser.shouldExclude(file: source) {
            log("Excluded \(source) as \(why)")
        } else if !recompiler.inject(source: source) {
            recompiler.pendingSource = source
        }
        }
    }
}

class HybridCompiler: NextCompiler {
    /// Legacy log parsing version of recomilation
    static var liteRecompiler = Recompiler()

    override func recompile(source: String, platform: String) ->  String? {
        let connected = InjectionServer.currentClient  != nil,
            oldCache = Reloader.cacheFile
        Reloader.sdk = platform // Switch commands cache file.
        if oldCache != Reloader.cacheFile && connected {
            Self.liteRecompiler = Recompiler()
        }
        return Self.liteRecompiler.recompile(source: source, platformFilter:
                            connected ? "SDKs/"+platform : "", dylink: false)
    }

    override func link(object: String, dylib: String, arch: String) -> (String, Double)? {
        return super.link(object: object, dylib: dylib, arch: arch) ??
                                   Self.liteRecompiler.linkingFailed()
    }
}
