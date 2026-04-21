//
//  StatusMenuView.swift
//  InjectionNext
//
//  SwiftUI menu bar dropdown replacing MainMenu.xib status menu.
//

import SwiftUI
import UniformTypeIdentifiers

struct StatusMenuView: View {
    @ObservedObject var config: ConfigStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("InjectionNext v\(config.appVersion) (build \(config.buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
                bringSettingsToFront()
            } label: {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Preferences Config")

            Button {
                AppDelegate.ui?.runXcode(self)
            } label: {
                HStack {
                    Text("Launch Xcode")
                    if config.haveLaunchedXcode {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
            .help("Launch Xcode in a way that logs how to recompile files")

            Divider()

            Button {
                let open = NSOpenPanel()
                open.prompt = "Select Project Directory"
                open.canChooseDirectories = true
                open.canChooseFiles = false
                if open.runModal() == .OK, let url = open.url {
                    Reloader.xcodeDev = config.xcodePath + "/Contents/Developer"
                    AppDelegate.ui.watch(path: url.path)
                    config.updateWatchingDirectories()
                }
            } label: {
                HStack {
                    Text(config.watchingDirectories.isEmpty ? "Watch Project..." : "Watch Another...")
                    if !config.watchingDirectories.isEmpty {
                        Spacer()
                        Image(systemName: "eye.fill")
                    }
                }
            }
            .help("Add another directory that will be watched for source changes")

            if !config.watchingDirectories.isEmpty {
                Button("Stop Watching") {
                    AppDelegate.watchers.removeAll()
                    AppDelegate.lastWatched = nil
                    config.updateWatchingDirectories()
                }

                ForEach(config.watchingDirectories, id: \.self) { dir in
                    Text("  \(URL(fileURLWithPath: dir).lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button(config.compilerState == .patched ? "Unpatch Compiler" : "Intercept Compiler") {
                AppDelegate.ui.patchCompiler(NSMenuItem())
            }

            Button("Unhide Symbols") {
                Unhider.startUnhide()
            }
            .help("Make public generators for injecting default arguments")

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "console")
            } label: {
                Label("Open Console…", systemImage: "terminal")
            }
            .help("Open low level app logs")

            Divider()

            Label {
                Text(config.isClientConnected ? "Client Connected" : "No Client")
            } icon: {
                Image(nsImage: Self.coloredDot(config.isClientConnected ? .systemGreen : .systemGray))
            }

            Label {
                Text("Status: \(config.injectionState.rawValue)")
            } icon: {
                Image(nsImage: Self.coloredDot(stateNSColor))
            }
            .help("Status of \(APP_NAME).app")

            Label {
                Text(buildSystemStatusText)
            } icon: {
                Image(systemName: (config.effectiveBuildSystem ?? .auto).symbolName)
            }
            .help(buildSystemHelpText)

            if config.buildSystem != .auto {
                Text("  Overridden in Settings (\(config.buildSystem.shortName))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Quit InjectionNext") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    @MainActor
    private func bringSettingsToFront() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.identifier?.rawValue == "settings" {
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    @MainActor
    private func selectProject() {
        let directory = config.watchingDirectories.first
            ?? (config.projectPath.isEmpty ? NSHomeDirectory() : config.projectPath)

        let open = NSOpenPanel()
        open.prompt = "Select Project or Workspace"
        open.directoryURL = URL(fileURLWithPath: directory)
        open.canChooseDirectories = false
        open.canChooseFiles = true
        open.treatsFilePackagesAsDirectories = false
        open.allowsMultipleSelection = false
        var types: [UTType] = []
        if let t = UTType("com.apple.xcode.project") { types.append(t) }
        if let t = UTType("com.apple.dt.document.workspace") { types.append(t) }
        open.allowedContentTypes = types
        NSApp.activate(ignoringOtherApps: true)

        guard open.runModal() == .OK, let url = open.url else { return }
        let ext = url.pathExtension
        guard ext == "xcodeproj" || ext == "xcworkspace" else { return }

        let chosen = url.path
        let parent = url.deletingLastPathComponent().path

        config.projectPath = parent
        config.defaultProjectFile = chosen
        config.autoOpenDefaultProject = true

        if MonitorXcode.runningXcode == nil {
            _ = MonitorXcode(args: " '\(chosen)'")
            Reloader.xcodeDev = config.xcodePath + "/Contents/Developer"
            AppDelegate.ui.watch(path: parent)
            config.updateWatchingDirectories()
        }
    }

    private var buildSystemStatusText: String {
        if let effective = config.effectiveBuildSystem {
            return "Build: \(effective.shortName)"
        }
        return "Build: None"
    }

    private var buildSystemHelpText: String {
        if config.buildSystem == .auto {
            return config.effectiveBuildSystem == nil
                ? "No project selected. Override in Settings > Build System."
                : "Auto-detected from project. Override in Settings > Build System."
        }
        return "Manually overridden in Settings > Build System."
    }

    private var stateNSColor: NSColor {
        switch config.injectionState {
        case .idle: return .systemBlue
        case .ok: return .systemOrange
        case .busy: return .systemPurple
        case .ready: return .systemGreen
        case .error: return .systemRed
        }
    }

    private static func coloredDot(_ color: NSColor, size: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

}
