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
    /// Cache of resolved git directories for watched paths
    static var gitDirectories = [String: String]()

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
        Reloader.injectionQueue = .main
        setenv(INJECTION_DIRECTORIES,
               NSHomeDirectory()+"/Library/Developer,"+path, 1)

        // Resolve and cache git directory once during registration
        if let gitDir = resolveGitDirectory(for: path) {
            Self.gitDirectories[path] = gitDir
            log("InjectionNext: Resolved git directory for \(path): \(gitDir)")
        } else {
            log("InjectionNext: No git directory found for \(path)")
        }

        Self.lastWatched = path
        Self.watchers[path] = InjectionHybrid()
        watchDirectoryItem.state = Self.watchers.isEmpty ? .off : .on
    }
    static func alreadyWatching(_ projectRoot: String) -> String? {
        return watchers.keys.first { projectRoot.hasPrefix($0) }
    }
    static func restartLastWatcher() {
        DispatchQueue.main.async {
            lastWatched.flatMap { watchers[$0]?.watcher?.restart() }
        }
    }

    /// Resolve git directory for a path, handling both regular repos and worktrees
    func resolveGitDirectory(for path: String) -> String? {
        let fm = FileManager.default
        var currentPath = path

        while currentPath != "/" {
            let gitPath = currentPath + "/.git"

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: gitPath, isDirectory: &isDirectory) else {
                currentPath = URL(fileURLWithPath: currentPath)
                    .deletingLastPathComponent().path
                continue
            }

            if isDirectory.boolValue {
                // Regular repository - .git is a directory
                return gitPath
            } else {
                // Worktree - .git is a file containing gitdir path
                do {
                    let content = try String(contentsOfFile: gitPath, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // Content is like: "gitdir: /path/to/main/.git/worktrees/name"
                    if content.hasPrefix("gitdir: ") {
                        let gitDir = content.replacingOccurrences(of: "gitdir: ", with: "")
                        // Resolve to absolute path if relative
                        if gitDir.hasPrefix("/") {
                            return gitDir
                        } else {
                            return URL(fileURLWithPath: currentPath)
                                .appendingPathComponent(gitDir)
                                .standardized
                                .path
                        }
                    }
                } catch {
                    NSLog("InjectionNext: Failed to read .git file at \(gitPath): \(error)")
                }
                return nil
            }
        }
        return nil
    }
}

/// Watches git lock files using FSEvents and updates repository locked state
class GitLockWatcher {
    private var lockStream: FSEventStreamRef?
    private let gitDirectory: String
    private let lockFiles: [String]
    private var context = FSEventStreamContext()

    init?(gitDirectory: String) {
        self.gitDirectory = gitDirectory
        self.lockFiles = [
            gitDirectory + "/index.lock",
            gitDirectory + "/HEAD.lock",
            gitDirectory + "/config.lock"
        ]

        // Perform initial check for existing lock files
        checkLockState()

        // Setup FSEvents watcher
        guard setupWatcher() else { return nil }
    }

    private func setupWatcher() -> Bool {
        context.info = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)

        let callback: FSEventStreamCallback = {
            (streamRef: ConstFSEventStreamRef,
             clientCallBackInfo: UnsafeMutableRawPointer?,
             numEvents: Int,
             eventPaths: UnsafeMutableRawPointer,
             eventFlags: UnsafePointer<FSEventStreamEventFlags>,
             eventIds: UnsafePointer<FSEventStreamEventId>) in

            guard let watcher = unsafeBitCast(clientCallBackInfo, to: GitLockWatcher?.self) else { return }

            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]

            // Filter to depth-0 events (direct children of .git only)
            for path in paths {
                // Check if this is a direct child of .git (no subdirectories after .git/)
                let relativePath = path.replacingOccurrences(of: watcher.gitDirectory + "/", with: "")

                // If relative path contains '/', it's in a subdirectory - skip it
                if relativePath.contains("/") {
                    continue
                }

                // Check if this is one of our lock files
                if relativePath == "index.lock" || relativePath == "HEAD.lock" || relativePath == "config.lock" {
                    // Lock file event detected - check current state
                    DispatchQueue.main.async {
                        watcher.checkLockState()
                    }
                    return
                }
            }
        }

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [gitDirectory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1, // latency
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream = stream else { return false }

        lockStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue as CFString)
        FSEventStreamStart(stream)

        return true
    }

    private func checkLockState() {
        let fm = FileManager.default
        let hasLock = lockFiles.contains { fm.fileExists(atPath: $0) }

        if hasLock {
            if !InjectionHybrid.hasActiveLock {
                InjectionHybrid.hasActiveLock = true
                log("Git lock detected - monitoring for source changes")
            }
        } else {
            if InjectionHybrid.hasActiveLock {
                InjectionHybrid.hasActiveLock = false
                if InjectionHybrid.isRepositoryLocked {
                    log("Git lock cleared (injection still blocked - relaunch app to resume)")
                } else {
                    log("Git lock cleared - no blocking occurred")
                }
            }
        }
    }

    deinit {
        if let stream = lockStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

class InjectionHybrid: InjectionBase {
    static var pendingFilesChanged = [String]()
    /// Tracks if git lock files currently exist (monitoring state)
    static var hasActiveLock = false
    /// Repository locked state - stops processing until app reconnects
    static var isRepositoryLocked = false
    /// InjectionNext compiler that uses InjectionLite log parser
    var liteRecompiler: NextCompiler = HybridCompiler()
    /// Minimum seconds between injections
    let minInterval = 1.0
    /// Cached git directory for this watcher (handles both repos and worktrees)
    var gitDirectory: String?
    /// Watches git lock files for repository operations
    var gitLockWatcher: GitLockWatcher?

    override init() {
        super.init()
        // Retrieve cached git directory from AppDelegate
        if let watchedPath = AppDelegate.lastWatched {
            self.gitDirectory = AppDelegate.gitDirectories[watchedPath]

            // Setup git lock file watcher if git directory is available
            if let gitDir = self.gitDirectory {
                self.gitLockWatcher = GitLockWatcher(gitDirectory: gitDir)
                if self.gitLockWatcher == nil {
                    log("⚠️ Failed to setup git lock watcher for \(gitDir)")
                }
            }
        }
    }

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        // Check if we should block due to source change during active lock
        if Self.hasActiveLock && !Self.isRepositoryLocked {
            DispatchQueue.main.async {
                if Self.hasActiveLock && !Self.isRepositoryLocked {
                    Self.isRepositoryLocked = true
                    Self.pendingFilesChanged.removeAll()
                    log("""
                        Source file changed during git operation. \
                        Injection blocked. Please relaunch your app to resume.
                        """)
                }
            }
            return
        }

        guard !AppDelegate.watchers.isEmpty,
              Date().timeIntervalSince1970 - (MonitorXcode.runningXcode?
                .recompiler.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        Self.pendingFilesChanged.append(source)
        NextCompiler.compileQueue.async {
            autoreleasepool {
                self.injectNext()
            }
        }
    }

    func injectNext() {
        // Skip processing if repository is already locked (detected by GitLockWatcher)
        if InjectionHybrid.isRepositoryLocked {
            log("""
                File processing stopped due to git lock. \
                Please relaunch your app to resume injection.
                """)
            return
        }

        guard let source = (DispatchQueue.main.sync { () -> String? in
            if Self.pendingFilesChanged.isEmpty { return nil }
            let source = Self.pendingFilesChanged.removeFirst()
            if !Self.pendingFilesChanged.isEmpty {
                NextCompiler.compileQueue.async { self.injectNext() }
            }
            return source
        }) else { return }

        if let running = MonitorXcode.runningXcode,
           running.recompiler.inject(source: source) { return }

        var recompiler = liteRecompiler
        if FrontendServer.loggedFrontend != nil && source.hasSuffix(".swift") {
            recompiler = FrontendServer.frontendRecompiler()
        }
        if let why = GitIgnoreParser.shouldExclude(file: source) {
            log("Excluded \(source) as \(why)")
        } else if !recompiler.inject(source: source) {
            recompiler.pendingSource = source
        } else if !(recompiler === liteRecompiler) {
            FrontendServer.writeCache()
        }
    }
}

class HybridCompiler: NextCompiler {
    /// Legacy log parsing version of recomilation
    var liteRecompiler = Recompiler()

    override func recompile(source: String, platform: String) ->  String? {
        return liteRecompiler.recompile(source: source, platformFilter:
                                            "SDKs/"+platform, dylink: false)
    }
}
