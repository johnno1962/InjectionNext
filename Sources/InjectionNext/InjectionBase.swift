//
//  InjectionBase.swift
//  InjectionNext
//
//  Base class for injection with file system monitoring capabilities.
//

import Foundation

/// Base class for injection functionality with file system monitoring
class InjectionBase {
    var watcher: FileWatcher?
    private var gitIgnoreParsers: [GitIgnoreParser] = []
    
    init() {
        setupFileWatcher()
    }
    
    deinit {
        watcher?.stop()
    }
    
    private func setupFileWatcher() {
        // Will be initialized when watching starts
    }
    
    /// Called when a file change is detected
    func inject(source: String) {
        // Override in subclasses
    }
    
    /// Start watching a directory for file changes
    func startWatching(directory: String) {
        // Load gitignore files for the directory
        gitIgnoreParsers = GitIgnoreParser.findGitIgnoreFiles(startingFrom: directory)
        
        watcher = FileWatcher(directory: directory) { [weak self] filePath in
            self?.handleFileChange(filePath: filePath)
        }
        watcher?.start()
    }
    
    /// Stop watching for file changes
    func stopWatching() {
        watcher?.stop()
        watcher = nil
        gitIgnoreParsers.removeAll()
    }
    
    private func handleFileChange(filePath: String) {
        // Check if file should be ignored according to gitignore rules
        let isDirectory = FileManager.default.fileExists(atPath: filePath, isDirectory: nil)
        
        for parser in gitIgnoreParsers {
            if parser.shouldIgnore(path: filePath, isDirectory: isDirectory) {
                return // File is ignored, don't process
            }
        }
        
        // Only process Swift files and other relevant source files
        let validExtensions = [".swift", ".m", ".mm", ".h", ".c", ".cpp", ".cc"]
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        
        if validExtensions.contains(".\(fileExtension)") {
            inject(source: filePath)
        }
    }
}

/// File system watcher using DispatchSource
class FileWatcher {
    private let directory: String
    private let callback: (String) -> Void
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    
    init(directory: String, callback: @escaping (String) -> Void) {
        self.directory = directory
        self.callback = callback
    }
    
    deinit {
        stop()
    }
    
    func start() {
        guard dispatchSource == nil else { return }
        
        fileDescriptor = open(directory, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open directory: \(directory)")
            return
        }
        
        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .revoke],
            queue: DispatchQueue.global(qos: .background)
        )
        
        dispatchSource?.setEventHandler { [weak self] in
            self?.scanDirectory()
        }
        
        dispatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }
        
        dispatchSource?.resume()
    }
    
    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }
    
    func restart() {
        stop()
        start()
    }
    
    private func scanDirectory() {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  let isRegularFile = resourceValues.isRegularFile,
                  isRegularFile else { continue }
            
            callback(fileURL.path)
        }
    }
}