//
//  InjectionSettingsView.swift
//  InjectionNext
//
//  Project path, watch directories, generics, key paths, sweep config.
//

import SwiftUI

struct InjectionSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Project Path") {
                    HStack {
                        Text(config.projectPath.isEmpty ? "Not set" : config.projectPath)
                            .foregroundStyle(config.projectPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Browse...") {
                            let open = NSOpenPanel()
                            open.prompt = "Select Project"
                            open.canChooseDirectories = true
                            open.canChooseFiles = false
                            if open.runModal() == .OK, let url = open.url {
                                config.projectPath = url.path
                                config.defaultProjectFile = ""
                                Reloader.xcodeDev = config.xcodePath + "/Contents/Developer"
                                AppDelegate.ui?.watch(path: url.path)
                                config.updateWatchingDirectories()
                            }
                        }
                        if !config.projectPath.isEmpty {
                            Button("Clear") {
                                config.projectPath = ""
                                config.defaultProjectFile = ""
                                config.autoOpenDefaultProject = false
                            }
                        }
                    }
                }
                if !config.projectPath.isEmpty {
                    let projects = ProjectDiscovery.discoverProjects(in: config.projectPath)
                    if projects.count > 1 {
                        Picker("Default Project File", selection: $config.defaultProjectFile) {
                            Text("Ask every time").tag("")
                            ForEach(projects) { project in
                                Text(project.name).tag(project.path)
                            }
                        }

                        Toggle("Always open default project", isOn: $config.autoOpenDefaultProject)
                    } else if projects.count == 1 {
                        LabeledContent("Project File") {
                            Text(projects[0].name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("Project", systemImage: "folder")
            } footer: {
                Text("Set a project directory. If it contains multiple .xcodeproj/.xcworkspace files, you can pick a default or be asked each time Xcode launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if config.watchingDirectories.isEmpty {
                    Text("No directories being watched")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(config.watchingDirectories, id: \.self) { dir in
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundStyle(.green)
                            Text(dir)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Button("Add Watch Directory...") {
                    let open = NSOpenPanel()
                    open.prompt = "Watch Directory"
                    open.canChooseDirectories = true
                    open.canChooseFiles = false
                    if open.runModal() == .OK, let url = open.url {
                        Reloader.xcodeDev = config.xcodePath + "/Contents/Developer"
                        AppDelegate.ui.watch(path: url.path)
                        config.updateWatchingDirectories()
                    }
                }

                if !config.watchingDirectories.isEmpty {
                    Button("Stop All Watchers") {
                        AppDelegate.watchers.removeAll()
                        AppDelegate.lastWatched = nil
                        config.updateWatchingDirectories()
                    }
                    .foregroundStyle(.red)
                }
            } header: {
                Label("File Watchers", systemImage: "eye")
            }

            Section {
                Toggle("Preserve Static Variables", isOn: $config.preserveStatics)
                Toggle("Disable Standalone Mode", isOn: $config.disableStandalone)
            } header: {
                Label("Injection Behavior", systemImage: "bolt.circle")
            } footer: {
                Text("\"Preserve Statics\" keeps static/top-level variable values across injections. \"Disable Standalone\" prevents fallback standalone injection when the app can't connect to InjectionNext.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Generics Injection", selection: $config.genericsMode) {
                    ForEach(GenericsMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Key Paths", selection: $config.keyPathsMode) {
                    ForEach(KeyPathsMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            } header: {
                Label("Generic & Key Path Support", systemImage: "chevron.left.forwardslash.chevron.right")
            } footer: {
                Text("Auto mode detects TCA usage and adjusts key path hooking automatically. Legacy generics uses object sweep; new mode doesn't require it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Sweep Exclude Regex", text: $config.sweepExclude)
                    .textFieldStyle(.roundedBorder)
                Toggle("Sweep Verbose Logging", isOn: $config.sweepDetail)
            } header: {
                Label("Object Sweep", systemImage: "rectangle.and.text.magnifyingglass")
            } footer: {
                Text("The sweep locates live instances of injected classes to call @objc func injected(). Exclude regex filters types from the sweep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
