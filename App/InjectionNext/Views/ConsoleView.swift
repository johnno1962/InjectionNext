//
//  ConsoleView.swift
//  InjectionNext
//
//  In-app console that mirrors everything captured by LogManager.
//

import SwiftUI

struct ConsoleView: View {
    @ObservedObject private var logs = LogManager.shared

    @State private var query: String = ""
    @State private var levelFilter: LogLevel? = nil
    @State private var autoScroll: Bool = true
    @State private var showingExporter = false

    var filtered: [LogEntry] {
        logs.entries.filter { entry in
            if let levelFilter, entry.level != levelFilter { return false }
            if query.isEmpty { return true }
            return entry.message.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 360)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)

            TextField("Filter…", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Picker("Level", selection: $levelFilter) {
                Text("All").tag(LogLevel?.none)
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized).tag(LogLevel?.some(level))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 140)

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            Button {
                copyAllToPasteboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy visible lines")

            Button(role: .destructive) {
                logs.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
        }
        .padding(8)
    }

    // MARK: - Content

    private var content: some View {
        LogTextView(entries: filtered, autoScroll: autoScroll)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(filtered.count) of \(logs.entries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("InjectionNext Console")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func copyAllToPasteboard() {
        let text = filtered.map(\.formatted).joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

// MARK: - Selectable log text view

/// NSTextView-backed log pane so users can select arbitrary text across
/// multiple lines (SwiftUI's `.textSelection(.enabled)` is per-Text only).
private struct LogTextView: NSViewRepresentable {
    let entries: [LogEntry]
    let autoScroll: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        let attr = Self.render(entries: entries)

        // Preserve selection if user has one, otherwise we'll optionally scroll
        // to the bottom. Equality check avoids resetting the view every tick
        // when nothing actually changed.
        if storage.length != attr.length || storage.string != attr.string {
            let hadSelection = tv.selectedRange().length > 0
            let previousSelection = tv.selectedRange()

            storage.beginEditing()
            storage.setAttributedString(attr)
            storage.endEditing()

            if hadSelection,
               previousSelection.location + previousSelection.length <= attr.length {
                tv.setSelectedRange(previousSelection)
            } else if autoScroll {
                tv.scrollToEndOfDocument(nil)
            }
        } else if autoScroll, tv.selectedRange().length == 0 {
            tv.scrollToEndOfDocument(nil)
        }
    }

    private static func render(entries: [LogEntry]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let monoSmall = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        for (idx, entry) in entries.enumerated() {
            let stamp = "[\(LogManager.timeFormatter.string(from: entry.timestamp))] "
            out.append(NSAttributedString(string: stamp, attributes: [
                .font: monoSmall,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            out.append(NSAttributedString(string: entry.message, attributes: [
                .font: mono,
                .foregroundColor: nsColor(for: entry.level),
            ]))
            if idx < entries.count - 1 {
                out.append(NSAttributedString(string: "\n"))
            }
        }
        return out
    }

    private static func nsColor(for level: LogLevel) -> NSColor {
        switch level {
        case .debug:   return .secondaryLabelColor
        case .info:    return .labelColor
        case .warning: return .systemOrange
        case .error:   return .systemRed
        case .alert:   return .systemPink
        }
    }
}
