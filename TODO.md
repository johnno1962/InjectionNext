# InjectionNext 2.0 — roadmap

Tracking the path from today's `2.0_overhaul` to a tagged `2.0.0`.

## Done

- [x] **DLKit: public `static var dlOpenMode` override** — landed upstream, consumed here via SPM.
- [x] **Modernised UI / AppKit → SwiftUI migration** — this branch (`maatheusgois-dd/2.0_overhaul-ui`), split into 5 logical commits:
  - `chore(assets)`: AppIcon catalog + `INJECTION_*` imagesets; drop `App.icns` and legacy `.tif` files.
  - `refactor(config)`: introduce `ConfigStore` (`ObservableObject`), drop `Defaults.swift`, keep `Defaults` shim for back-compat.
  - `feat(ui)`: SwiftUI `@main` entry (`InjectionNextApp`) + `StatusMenuView`; delete `MainMenu.xib`, `main.m`, old `AppDelegate` outlets; `CompatMenuItem` / `CompatButton` / `CompatTextField` shims to keep legacy mutation call sites compiling.
  - `UI: SettingsView` — 10 panels (`General`, `Xcode`, `BuildSystem`, `Compiler`, `Injection`, `Devices`, `FileWatcher`, `Network`, `Tracing`, `Advanced`) observing `ConfigStore`; new `Window("settings")` scene.
  - `UI: LogManager + ConsoleView` — central `ObservableObject` logger with ring buffer, dedupe, uncaught-exception / fatal-signal capture, stdout/stderr hijack mirrored to the real fds; `Window("console")` scene; `LogBuffer` becomes a typealias of `LogManager` for back-compat.
- [x] **Swift 6 / strict-concurrency audit** — nothing in the ported UI requires Swift 6; package/target language mode stays Swift 5.
- [x] **Device Testing toggle** — split from `devicesEnabled`. Gates linking of `deviceLibraries` (XCTest + helpers) into the injection dylib. Prevents `Library not loaded: @rpath/XCTest.framework/XCTest` crashes on apps that don't ship `copy_bundle.sh`.

## Next

- [ ] **Bump version to 2.0.0** — `MARKETING_VERSION`; tag after upstream merge.
- [ ] **Fix red internal-Xcode icon when launching Xcode from the app (non log-parsing path)** — currently stays red until a compile event flips it; need to flip to idle/green once the `MonitorXcode` attach + log tap succeeds. ERROR: - When a user-launched Xcode is already running, MonitorXcode() calls Popen with SOURCEKIT_LOGGING=1 … Xcode. The second Xcode process exits immediately (macOS single-instances the app and just activates the existing one).
- [ ] **Re-sync submodules against latest heads** — after upstream merges, run `git submodule update --init --recursive` and bump pins in a dedicated commit.
- [ ] **Settings / preferences refactor** — continue consolidating `ConfigStore` as the single source of truth; migrate any remaining `UserDefaults` direct reads in the backend (`MonitorXcode`, `NextCompiler`, `FrontendServer`).
- [ ] **Logging + error surfacing improvements** — surface last compile error in the status menu; ring-buffer truncation indicator in the console; level filter persistence.
- [ ] **README / docs update for the 2.0 flow** — document the SwiftUI entry, ConfigStore, and the in-app Console.
- [ ] **Smoke-test matrix** — Xcode 15.x, 16.x, 26.x; macOS 14 / 15. Capture screenshots per matrix.

### Hybrid / file-watcher

- [ ] **Allow file-watcher injection while Xcode is running** — `InjectionHybrid.filesChanged(_:)` currently returns early with `guard MonitorXcode.runningXcode == nil else { return }`. Drop that gate so editors like Cursor / VSCode and Bazel-driven workflows can inject without quitting Xcode. Xcode-owned compiles still win via the existing `MonitorXcode.recompiler.canCompile` fast-path.
- [ ] **Skip SDK filter in log-parsing recompiler when no client is connected** — `Recompiler.recompile(..., platformFilter: "SDKs/\(platform)")` uses `FrontendServer.clientPlatform`, which defaults to `"MacOSX"` until a device/sim connects. Editing an iOS file before first connect produces `grep SDKs/MacOSX` misses and `Log scanning failed` errors. Detect `InjectionServer.currentClients.isEmpty` and drop the `SDKs/...` filter so the most recent build log wins instead.
- [ ] **Replace `DispatchQueue.main.sync` lock on `pendingFilesChanged` with `NSLock`** — the file-watcher debounce currently hops to the main queue just to mutate a shared array, which deadlocks when the main queue is already waiting on disk I/O inside the compile path. A plain `NSLock` (or `OSAllocatedUnfairLock`) around `pendingFilesChanged` is both correct and non-blocking.

### Developer tooling

- [ ] **Reuse already-running Xcode instead of spawning a duplicate process** — `AppDelegate.runXcode(_:)` unconditionally calls `MonitorXcode()`, which `Popen`-launches `Xcode.app`. macOS single-instances `Xcode.app`, so the second process activates the existing one and exits immediately, leaving `MonitorXcode.runningXcode` pointed at a dead pipe and the status icon stuck red. Detect a running Xcode via `NSRunningApplication` and attach to it (mirror lifecycle into the status icon, observe `NSWorkspace.didTerminateApplicationNotification`) rather than spawning.
- [ ] **Top-level `Makefile` for local dev** — `build-app` / `run` / `open` / `kill` / `sync` / `clean` targets wrapping the `xcodebuild` invocation and `/Applications` install step, so contributors don't have to memorise the flags. Zero source impact.
- [ ] **CI release workflow** — `.github/workflows/release.yml` that builds on tag push, codesigns / notarises (optional), attaches the `.app` to a GitHub Release, and surfaces `InjectionNext.dmg`. Pairs with the 2.0.0 tag.

### Integrations / observability

- [ ] **Injection event tracker for external consumers (MCP / AI agents)** — emit structured events (`detecting` / `compiled` / `injected` / `failed`) from `InjectionHybrid.filesChanged` and `Recompiler.inject` into an `ObservableObject` bus. Surface over the existing `ControlServer` (`mcp-server/index.js`) so editors can react to injection state in real time.

## Current branch

`maatheusgois-dd/2.0_overhaul-ui` off `maatheusgois-dd/2.0_overhaul`.

Clean build: `xcodebuild -project App/InjectionNext.xcodeproj -scheme InjectionNext clean build` → `BUILD SUCCEEDED` on Xcode 26.3.
