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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered) { entry in
                        ConsoleLine(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: filtered.last?.id) { newID in
                guard autoScroll, let newID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newID, anchor: .bottom)
                }
            }
            .onAppear {
                if let lastID = filtered.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
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

// MARK: - Line

private struct ConsoleLine: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("[\(LogManager.timeFormatter.string(from: entry.timestamp))]")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(color(for: entry.level))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:   return .secondary
        case .info:    return .primary
        case .warning: return .orange
        case .error:   return .red
        case .alert:   return .pink
        }
    }
}
