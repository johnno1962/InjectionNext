//
//  ControlServer.swift
//  InjectionNext
//
//  Local TCP control server for MCP integration.
//  Listens on localhost:8919 for JSON commands and
//  maps them to existing AppDelegate actions.
//

import Cocoa

// MARK: - Log Buffer

class LogBuffer {

    static let shared = LogBuffer()

    struct Entry {
        let timestamp: TimeInterval
        let message: String
        let level: String
    }

    private let lock = NSLock()
    private var entries = [Entry]()
    private let maxEntries = 2000

    func append(_ message: String, level: String = "info") {
        lock.lock()
        defer { lock.unlock() }
        entries.append(Entry(
            timestamp: Date().timeIntervalSince1970,
            message: message,
            level: level
        ))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func get(since: TimeInterval = 0, limit: Int = 200) -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        let filtered = entries.filter { $0.timestamp > since }
        let sliced = filtered.suffix(limit)
        return sliced.map {
            ["timestamp": $0.timestamp, "message": $0.message, "level": $0.level]
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }
}

// MARK: - Control Server

class ControlServer {

    static let port: UInt16 = 8919
    static var shared: ControlServer?

    private var serverSocket: Int32 = -1
    private let queue = DispatchQueue(label: "ControlServer", attributes: .concurrent)

    static func start() {
        guard shared == nil else {
            print("\(APP_PREFIX)ControlServer: already started")
            return
        }
        print("\(APP_PREFIX)ControlServer: initializing...")
        shared = ControlServer()
        shared?.listen()
    }

    private func listen() {
        queue.async { [weak self] in
            guard let self = self else {
                print("\(APP_PREFIX)ControlServer: self was deallocated before listen()")
                return
            }

            print("\(APP_PREFIX)ControlServer: creating socket...")
            self.serverSocket = socket(AF_INET, SOCK_STREAM, 0)
            guard self.serverSocket >= 0 else {
                print("\(APP_PREFIX)ControlServer: socket() failed: \(String(cString: strerror(errno)))")
                return
            }

            var reuse: Int32 = 1
            setsockopt(self.serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = Self.port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(self.serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            guard bindResult == 0 else {
                print("\(APP_PREFIX)ControlServer: bind() failed on port \(Self.port): \(String(cString: strerror(errno)))")
                close(self.serverSocket)
                return
            }

            guard Darwin.listen(self.serverSocket, 5) == 0 else {
                print("\(APP_PREFIX)ControlServer: listen() failed: \(String(cString: strerror(errno)))")
                close(self.serverSocket)
                return
            }

            print("\(APP_PREFIX)ControlServer: listening on localhost:\(Self.port)")

            while true {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(self.serverSocket, $0, &clientLen)
                    }
                }
                guard clientSocket >= 0 else { continue }
                self.queue.async {
                    self.handleClient(clientSocket)
                }
            }
        }
    }

    private func handleClient(_ sock: Int32) {
        defer { close(sock) }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(sock, &buf, buf.count, 0)
            guard n > 0 else { break }
            data.append(contentsOf: buf[0..<n])
            if data.contains(UInt8(ascii: "\n")) { break }
        }

        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            sendResponse(sock, success: false, error: "Invalid JSON or missing 'action'")
            return
        }

        let result = executeAction(action, params: json)
        sendResponse(sock, success: result.success, data: result.data, error: result.error)
    }

    private func sendResponse(_ sock: Int32, success: Bool, data: [String: Any]? = nil, error: String? = nil) {
        var response: [String: Any] = ["success": success]
        if let error = error { response["error"] = error }
        if let data = data { response["data"] = data }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        let line = jsonStr + "\n"
        _ = line.withCString { ptr in
            send(sock, ptr, strlen(ptr), 0)
        }
    }

    struct ActionResult {
        let success: Bool
        let data: [String: Any]?
        let error: String?

        static func ok(_ data: [String: Any]? = nil) -> ActionResult {
            ActionResult(success: true, data: data, error: nil)
        }
        static func fail(_ error: String) -> ActionResult {
            ActionResult(success: false, data: nil, error: error)
        }
    }

    private func executeAction(_ action: String, params: [String: Any]) -> ActionResult {
        switch action {

        case "status":
            return getStatus()

        case "watch_project":
            guard let path = params["path"] as? String else {
                return .fail("Missing 'path' parameter")
            }
            return watchProject(path: path)

        case "stop_watching":
            return stopWatching()

        case "launch_xcode":
            return launchXcode()

        case "intercept_compiler":
            return interceptCompiler()

        case "enable_devices":
            let enable = params["enable"] as? Bool ?? true
            return enableDevices(enable: enable)

        case "unhide_symbols":
            return unhideSymbols()

        case "get_last_error":
            return getLastError()

        case "prepare_swiftui_source":
            return prepareSwiftUISource()

        case "prepare_swiftui_project":
            return prepareSwiftUIProject()

        case "set_xcode_path":
            guard let path = params["path"] as? String else {
                return .fail("Missing 'path' parameter")
            }
            return setXcodePath(path: path)

        case "get_logs":
            let since = params["since"] as? TimeInterval ?? 0
            let limit = params["limit"] as? Int ?? 200
            return getLogs(since: since, limit: limit)

        case "clear_logs":
            return clearLogs()

        default:
            return .fail("Unknown action: \(action)")
        }
    }

    // MARK: - Actions

    private func getStatus() -> ActionResult {
        var result = [String: Any]()
        DispatchQueue.main.sync {
            let delegate = AppDelegate.ui!
            result["xcode_running"] = MonitorXcode.runningXcode != nil
            result["xcode_path"] = Defaults.xcodePath
            result["compiler_intercepted"] = delegate.updatePatchUnpatch() == .patched
            result["devices_enabled"] = delegate.enableDevicesItem.state == .on
            result["watching_directories"] = Array(AppDelegate.watchers.keys)
            result["has_connected_client"] = InjectionServer.currentClient != nil
            result["auto_restart_xcode"] = Defaults.xcodeRestart
            result["last_error"] = NextCompiler.lastError
        }
        return .ok(result)
    }

    private func watchProject(path: String) -> ActionResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return .fail("Path does not exist: \(path)")
        }
        DispatchQueue.main.sync {
            Reloader.xcodeDev = Defaults.xcodePath + "/Contents/Developer"
            AppDelegate.ui.watch(path: path)
        }
        return .ok(["watching": path])
    }

    private func stopWatching() -> ActionResult {
        DispatchQueue.main.sync {
            AppDelegate.watchers.removeAll()
            AppDelegate.lastWatched = nil
            AppDelegate.ui.watchDirectoryItem.state = .off
            AppDelegate.ui.refreshWatchProjectMenuItem()
        }
        return .ok()
    }

    private func launchXcode() -> ActionResult {
        DispatchQueue.main.sync {
            if MonitorXcode.runningXcode == nil {
                _ = MonitorXcode()
            }
        }
        return .ok(["xcode_path": Defaults.xcodePath])
    }

    private func interceptCompiler() -> ActionResult {
        var state = ""
        DispatchQueue.main.sync {
            let delegate = AppDelegate.ui!
            let currentState = delegate.updatePatchUnpatch()
            state = currentState == .patched ? "patched" : "unpatched"
        }
        return .ok(["compiler_state": state,
                     "note": "Use Xcode UI to toggle interception (requires user confirmation alert)"])
    }

    private func enableDevices(enable: Bool) -> ActionResult {
        DispatchQueue.main.sync {
            let delegate = AppDelegate.ui!
            let currentlyEnabled = delegate.enableDevicesItem.state == .on
            if enable != currentlyEnabled {
                delegate.deviceEnable(delegate.enableDevicesItem)
            }
        }
        return .ok(["devices_enabled": enable])
    }

    private func unhideSymbols() -> ActionResult {
        Unhider.startUnhide()
        return .ok()
    }

    private func getLastError() -> ActionResult {
        let error = NextCompiler.lastError ?? "No error."
        return .ok(["error": error])
    }

    private func prepareSwiftUISource() -> ActionResult {
        guard let lastSource = NextCompiler.lastSource else {
            return .fail("No source file currently being edited")
        }
        DispatchQueue.main.sync {
            AppDelegate.ui.prepareSwiftUI(source: lastSource)
        }
        return .ok(["source": lastSource])
    }

    private func prepareSwiftUIProject() -> ActionResult {
        DispatchQueue.main.sync {
            AppDelegate.ui.prepareProject(AppDelegate.ui.patchCompilerItem)
        }
        return .ok()
    }

    private func setXcodePath(path: String) -> ActionResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return .fail("Xcode not found at: \(path)")
        }
        DispatchQueue.main.sync {
            Defaults.xcodeDefault = path
            AppDelegate.ui.selectXcodeItem.toolTip = path
            AppDelegate.ui.updatePatchUnpatch()
        }
        return .ok(["xcode_path": path])
    }

    private func getLogs(since: TimeInterval, limit: Int) -> ActionResult {
        let logs = LogBuffer.shared.get(since: since, limit: min(limit, 500))
        return .ok(["logs": logs, "count": LogBuffer.shared.count])
    }

    private func clearLogs() -> ActionResult {
        LogBuffer.shared.clear()
        return .ok()
    }
}
