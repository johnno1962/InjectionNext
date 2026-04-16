//
//  LogManager.swift
//  InjectionNext
//
//  Centralized logger. Stores timestamped entries, publishes them for SwiftUI
//  observers and hijacks stdout/stderr so arbitrary print / NSLog / runtime
//  warnings show up in the in-app Console window.
//

import Foundation
import Combine
import Darwin

enum LogLevel: String, CaseIterable {
    case debug, info, warning, error, alert

    init(string: String) {
        self = LogLevel(rawValue: string) ?? .info
    }

    var symbol: String {
        switch self {
        case .debug:   return "•"
        case .info:    return "ℹ︎"
        case .warning: return "⚠︎"
        case .error:   return "✖︎"
        case .alert:   return "‼︎"
        }
    }
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel

    /// [HH:mm:ss.SSS] message
    var formatted: String {
        "[\(LogManager.timeFormatter.string(from: timestamp))] \(message)"
    }
}

/// Global logger. Keeps in-memory ring buffer of log entries and mirrors
/// stdout/stderr so any `print` / `NSLog` / Swift runtime warning ends up
/// visible in the Console window inside the app.
final class LogManager: ObservableObject {

    static let shared = LogManager()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    @Published private(set) var entries: [LogEntry] = []

    private let lock = NSLock()
    private let maxEntries = 5000

    // Duplicate suppression window for the stderr/stdout mirror.
    private var recentSignatures: [(sig: String, when: TimeInterval)] = []
    private let dedupeWindow: TimeInterval = 1.0

    // Saved original fds so we can still print through to the real terminal.
    private var savedStdout: Int32 = -1
    private var savedStderr: Int32 = -1
    private var capturing = false

    // MARK: - Public API

    func append(_ message: String, level: LogLevel = .info) {
        let trimmed = Self.stripNoise(message)
        guard !trimmed.isEmpty else { return }
        let entry = LogEntry(timestamp: Date(), message: trimmed, level: level)

        performOnMain { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
            self.remember(signature: trimmed)
            self.lock.unlock()
        }
    }

    /// Back-compat entry point used by legacy call sites that pass a raw string.
    func append(_ message: String, level: String) {
        append(message, level: LogLevel(string: level))
    }

    func clear() {
        performOnMain { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.entries.removeAll()
            self.recentSignatures.removeAll()
            self.lock.unlock()
        }
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    // JSON-friendly representation for ControlServer / MCP consumers.
    func get(since: TimeInterval = 0, limit: Int = 200) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        let ts = since
        let filtered = entries.filter { $0.timestamp.timeIntervalSince1970 > ts }
        return filtered.suffix(limit).map { entry in
            [
                "timestamp": entry.timestamp.timeIntervalSince1970,
                "message": entry.message,
                "level": entry.level.rawValue,
            ]
        }
    }

    // MARK: - stdout / stderr interception ("swizzling")

    /// Pipes stdout/stderr through the logger while still writing to the
    /// original descriptors so Console.app and the attached terminal keep
    /// working. Safe to call more than once.
    func startCapturing() {
        lock.lock()
        guard !capturing else { lock.unlock(); return }
        capturing = true
        lock.unlock()

        installUncaughtHandlers()
        hijack(fd: STDOUT_FILENO, level: .info,  saved: &savedStdout)
        hijack(fd: STDERR_FILENO, level: .error, saved: &savedStderr)
    }

    private func hijack(fd: Int32, level: LogLevel, saved: inout Int32) {
        let dup = Darwin.dup(fd)
        guard dup >= 0 else { return }
        saved = dup

        var fds: [Int32] = [-1, -1]
        let rc = fds.withUnsafeMutableBufferPointer { buf -> Int32 in
            return pipe(buf.baseAddress!)
        }
        guard rc == 0 else { return }

        // Unbuffered so log lines show up immediately.
        setvbuf(fd == STDOUT_FILENO ? stdout : stderr, nil, _IONBF, 0)

        Darwin.dup2(fds[1], fd)
        Darwin.close(fds[1])

        let readFd = fds[0]
        let passthrough = dup
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.readLoop(readFd: readFd, passthrough: passthrough, level: level)
        }
    }

    private func readLoop(readFd: Int32, passthrough: Int32, level: LogLevel) {
        var scratch = [UInt8](repeating: 0, count: 4096)
        var buffer = ""

        while true {
            let n = read(readFd, &scratch, scratch.count)
            if n <= 0 { break }

            // Mirror raw bytes to the real fd (terminal, Console.app, etc).
            _ = scratch.withUnsafeBufferPointer {
                write(passthrough, $0.baseAddress, n)
            }

            if let chunk = String(bytes: scratch[0..<n], encoding: .utf8) {
                buffer.append(chunk)
            }

            while let newline = buffer.firstIndex(of: "\n") {
                let rawLine = String(buffer[..<newline])
                buffer.removeSubrange(...newline)
                ingestCapturedLine(rawLine, level: level)
            }
        }
    }

    private func ingestCapturedLine(_ raw: String, level: LogLevel) {
        let cleaned = Self.stripNoise(raw)
        guard !cleaned.isEmpty else { return }

        lock.lock()
        let now = Date().timeIntervalSince1970
        recentSignatures.removeAll { now - $0.when > dedupeWindow }
        if recentSignatures.contains(where: { $0.sig == cleaned }) {
            lock.unlock()
            return
        }
        lock.unlock()

        let inferred = inferLevel(from: cleaned, default: level)
        let entry = LogEntry(timestamp: Date(), message: cleaned, level: inferred)

        performOnMain { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
            self.remember(signature: cleaned)
            self.lock.unlock()
        }
    }

    private func remember(signature: String) {
        let now = Date().timeIntervalSince1970
        recentSignatures.append((signature, now))
        recentSignatures.removeAll { now - $0.when > dedupeWindow }
    }

    private func inferLevel(from message: String, default fallback: LogLevel) -> LogLevel {
        let lower = message.lowercased()
        if message.contains("⚠️") || lower.contains("warning") { return .warning }
        if message.contains("❌") || message.contains("✖") || lower.contains("error") || lower.contains("failed") {
            return .error
        }
        if message.contains("‼") || lower.contains("fatal") || lower.contains("crash") {
            return .alert
        }
        return fallback
    }

    // Strip NSLog's `2026-04-16 14:00:00.123 AppName[1234:5678] ` prefix and
    // trailing whitespace so the Console view stays compact.
    private static func stripNoise(_ line: String) -> String {
        var out = line
        if let range = out.range(
            of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+ \S+\[\d+(:[0-9a-fA-F]+)?\]\s*"#,
            options: .regularExpression) {
            out.removeSubrange(range)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Uncaught exception / signal capture

    private func installUncaughtHandlers() {
        NSSetUncaughtExceptionHandler { exc in
            let stack = exc.callStackSymbols.joined(separator: "\n")
            LogManager.shared.append(
                "Uncaught exception: \(exc.name.rawValue) — \(exc.reason ?? "nil")\n\(stack)",
                level: .alert)
        }

        // Signal handlers MUST be async-signal-safe: no malloc, no locks,
        // no Swift runtime beyond StaticString. Calling LogManager.append
        // (string formatting + NSLock + DispatchQueue.main.async) deadlocks
        // when a signal fires while another thread holds the malloc
        // unfair_lock — you get _os_unfair_lock_recursive_abort instead of
        // the real crash.
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS] {
            signal(sig) { which in
                let msg: StaticString
                switch which {
                case SIGABRT: msg = "*** SIGABRT\n"
                case SIGILL:  msg = "*** SIGILL\n"
                case SIGSEGV: msg = "*** SIGSEGV\n"
                case SIGFPE:  msg = "*** SIGFPE\n"
                case SIGBUS:  msg = "*** SIGBUS\n"
                default:      msg = "*** fatal signal\n"
                }
                msg.withUTF8Buffer { buf in
                    _ = Darwin.write(STDERR_FILENO, buf.baseAddress, buf.count)
                }
                Darwin.signal(which, SIG_DFL)
                Darwin.raise(which)
            }
        }
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGILL:  return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE:  return "SIGFPE"
        case SIGBUS:  return "SIGBUS"
        case SIGPIPE: return "SIGPIPE"
        default:      return "SIG#\(sig)"
        }
    }

    // MARK: - Main-thread hop

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

// MARK: - Back-compat shim

/// Legacy name kept so existing call sites continue to compile.
typealias LogBuffer = LogManager

extension LogManager {
    /// Mirrors the old `LogBuffer.shared` entry point.
    static var legacyShared: LogManager { shared }
}
