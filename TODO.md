# Internal plan — upstream contribution of fork changes

Target: merge `maatheusgois-dd/InjectionNext` changes back into
`johnno1962/InjectionNext` `main`, split into reviewable PRs.
All validation on **Xcode 26.3** / macOS 15 / Apple Silicon.

Upstream issue to open first: "Big changes in the UI and how the setup is done
(proposal to land in steps)" — see draft body in chat history.

---

## 0. Pre-flight (before opening any PR)

- [ ] Sync local with upstream: `git remote add upstream git@github.com:johnno1962/InjectionNext.git && git fetch upstream`
- [ ] Rebase `main` on `upstream/main` (or merge, whichever John prefers). Ours is currently ~50 commits ahead, 0 behind.
- [ ] `InjectionLite` submodule: already merged `upstream/main` locally (commit `2241ab6`). Push `maatheusgois-dd/InjectionLite` main + bump submodule pointer in this repo.
- [ ] `DLKit` submodule: check if upstream has new commits; if so, same merge dance. Otherwise leave as-is.
- [ ] Open the upstream issue with screenshots (status menu, settings, console, project picker, build-system view) and link this plan.
- [ ] Wait for John's sign-off on the merge plan / ordering before pushing PRs.
- [ ] Create a throwaway fresh-clone of `johnno1962/InjectionNext` in `/tmp` to stage each PR on top of a clean upstream base.

## 1. PR 1 — Compiler/runtime fixes (non-UI)

Scope: zero-behavior-change hardening. Easiest to land first.

- [ ] Filter whole-module-optimization flags from captured compiler args (`Recompiler` / log-parser path).
- [ ] Start `ControlServer` before any alert can block main thread.
- [ ] Improve `ControlServer` debug logging.
- [ ] Fix watch-project menu title when directories are watched.
- [ ] `@MainActor` annotations on `launchXcodeWithProject` / `runXcode`.
- [ ] Safer signal handlers.
- [ ] Silence safe warnings (`var`→`let`, unused `fcntl`, MainActor hops).
- [ ] Cut console noise / dedup log spam / warn on Xcode CAS / SIGPIPE.
- [ ] Manual test: simulator + macOS app round-trip on Xcode 26.3.
- [ ] PR description: list each fix with one-line rationale.

## 2. PR 2 — Assets + Makefile + CI

Scope: additive, no runtime change.

- [ ] `AppIcon` asset catalog set (replaces `App.icns`).
- [ ] `INJECTION_RED.imageset` asset.
- [ ] `Makefile` with `build` / `install` / `run` / `sync` targets.
- [ ] GitHub Actions release workflow on tags (currently removed from fork per request — re-add here only if John wants it).
- [ ] Verify app bundle still gets a valid icon in Finder + menu bar.

## 3. PR 3 — SwiftUI migration (status menu + settings + picker)

Scope: biggest UI diff. Must be self-contained: old XIB/AppKit removed in the same PR to avoid dead code.

- [ ] `InjectionNextApp.swift` SwiftUI entry point.
- [ ] `StatusMenuView`, `SettingsView`, `CompilerSettingsView`, `BuildSystemSettingsView`, `ConsoleView`.
- [ ] `ConfigStore` wiring (persist + reload).
- [ ] Remove old `.xib` files and AppKit window controllers.
- [ ] Match all existing menu items (Launch Xcode, Watch Project, Enable Devices, Prepare SwiftUI, Trace toggles, etc.).
- [ ] Manual test matrix:
  - [ ] Menu open/close, all items clickable.
  - [ ] Settings persistence round-trip.
  - [ ] Status-color transitions: blue → purple → orange → green / yellow / red.
  - [ ] Keyboard shortcuts still work.
  - [ ] Works when launched from CLI with `-projectPath`.

## 4. PR 4 — Project picker enhancements

Depends on PR 3.

- [ ] Picker dialog when multiple `xcodeproj`/`xcworkspace` found.
- [ ] Browse option for arbitrary path.
- [ ] "Select Project" action in status bar.
- [ ] Reuse running Xcode instance when possible.
- [ ] Manual test: 0 / 1 / 3 `xcodeproj`s in a workspace.

## 5. PR 5 — Build-system settings UI

- [ ] Auto-detect Xcode / SPM / Bazel.
- [ ] User override persisted in `ConfigStore`.
- [ ] Honor override in `Recompiler` dispatch (skip Bazel paths when Xcode/SPM forced).
- [ ] Hybrid fallback: skip SDK filter when no client connected.
- [ ] Manual test: force each mode on a Bazel project + a plain SPM project.

## 6. PR 6 — In-app console + `LogManager`

- [ ] `LogManager` capturing stdout/stderr.
- [ ] `ConsoleView` window with scrollback + clear.
- [ ] Dedup log spam, warn on Xcode CAS / SIGPIPE.
- [ ] Verify no recursion (log → capture → log).
- [ ] Verify performance under heavy injection (1k+ lines/sec).

## 7. PR 7 — MCP server + event tracker

- [ ] Ship as a separate SPM target so default app doesn't bloat.
- [ ] `Recompiler` `onCompilationEvent` hook (already upstream via PR #23 on `InjectionLite`) — document usage.
- [ ] Event tracker (compiling / compiled / failed).
- [ ] Log buffer wired to `Recompiler` events.
- [ ] Docs: short README section + example agent prompt.
- [ ] Discuss with John: does he want this in-tree or as a sibling repo?

---

## Cross-cutting tasks

- [ ] For each PR: rebase on latest `upstream/main` right before pushing.
- [ ] For each PR: run `make build` clean + smoke-test on Xcode 26.3 before pushing.
- [ ] For each PR: include before/after screenshots where UI is touched.
- [ ] Keep `maatheusgois-dd/InjectionNext` main as the staging branch; each PR is a branch off `main` rebased on `upstream/main`.
- [ ] Track PR status here:
  - [ ] PR 1 opened
  - [ ] PR 2 opened
  - [ ] PR 3 opened
  - [ ] PR 4 opened
  - [ ] PR 5 opened
  - [ ] PR 6 opened
  - [ ] PR 7 opened

## Open questions for John

- [ ] SwiftUI vs AppKit-incremental migration preference.
- [ ] MCP server: in-tree optional target vs sibling repo.
- [ ] Squash `AppIcon` into PR 1 or keep in PR 2.
- [ ] Commit-message style (`conventional` vs `[Main] - ...`).

## Out of scope / fork-only (do NOT upstream)

- [ ] `.github/workflows/release.yml` (removed on request).
- [ ] Fork-specific submodule pins (`maatheusgois-dd/InjectionLite`, `maatheusgois-dd/DLKit`) — upstream keeps `johnno1962/*`.
- [ ] `README.md` "What's new in this fork" section — fork-only.
- [ ] Any DoorDash-internal references (none currently, but re-check before each push).
