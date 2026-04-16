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

    func watchProject(_ sender: Any) {
        let open = NSOpenPanel()
        open.prompt = "Select Project Directory"
        open.canChooseDirectories = true
        open.canChooseFiles = false
        if open.runModal() == .OK, let url = open.url {
            Reloader.xcodeDev = Defaults.xcodePath+"/Contents/Developer"
            watch(path: url.path)
        } else {
            Self.watchers.removeAll()
            Self.lastWatched = nil
            refreshWatchProjectMenuItem()
        }
    }

    func watch(path: String) {
        guard Self.alreadyWatching(path) == nil else { return }
        GitIgnoreParser.monitor(directory: path)
        Self.watchers[path] = InjectionHybrid(watching: path)
        Self.lastWatched = path
        refreshWatchProjectMenuItem()
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
    /// Lock protecting pendingFilesChanged (avoids DispatchQueue.main.sync deadlock)
    static let pendingLock = NSLock()
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
            pattern: #"[^~]\.(mm?|cpp|cc|swift|lock|o)$"#)
    }

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        let fileName = URL(fileURLWithPath: source).lastPathComponent
        if source.hasSuffix(".swift") || source.hasSuffix(".m") || source.hasSuffix(".mm") || source.hasSuffix(".cpp") {
            InjectionEventTracker.shared.emit(fileName, status: "detecting")
        }
        // File-watcher injection is allowed even when Xcode is running (Cursor/Bazel workflow)
        // Skip git lock files silently — don't block injection on Xcode builds
        if source.hasSuffix(".lock") && source.contains("/.git/") { return }

        let now = Date.timeIntervalSinceReferenceDate
        guard !AppDelegate.watchers.isEmpty, now - (
                Self.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        Self.lastInjected[source] = now

        Self.pendingLock.lock()
        Self.pendingFilesChanged.append(source)
        Self.pendingLock.unlock()
        NextCompiler.compileQueue.async {
            self.injectNext()
        }
    }

    func injectNext() {
        guard let source = ({ () -> String? in
            Self.pendingLock.lock()
            defer { Self.pendingLock.unlock() }
            guard let source = Self.pendingFilesChanged.first else { return nil }
            Self.pendingFilesChanged.removeAll(where: { $0 == source })
            if !Self.pendingFilesChanged.isEmpty {
                NextCompiler.compileQueue.async { self.injectNext() }
            }
            return source
        }()) else { return }

        autoreleasepool {
        // Always use Bazel/log-parsing path for Cursor file-watcher workflow
        let recompiler = logParsingCompiler

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
        let oldCache = Reloader.cacheFile
        Reloader.sdk = platform // Select commands cache file.
        if oldCache != Reloader.cacheFile { Self.liteRecompiler = Recompiler() }
        // When no client is connected we don't actually know the target SDK
        // (platform defaults to "MacOSX" in NextCompiler.prepare), so skip
        // the SDK grep filter and let the most recent build log win. This
        // avoids "Log scanning failed: … grep SDKs/MacOSX" when the user
        // edits a file before the iOS app has connected back.
        let noClient = InjectionServer.currentClients.compactMap({ $0 }).isEmpty
        let filter = noClient ? "" : "SDKs/" + platform
        return Self.liteRecompiler.recompile(source: source,
                                             platformFilter: filter,
                                             dylink: false)
    }

    override func link(object: String, dylib: String, arch: String) -> (String, Double)? {
        return super.link(object: object, dylib: dylib, arch: arch) ??
                                   Self.liteRecompiler.linkingFailed()
    }
}
