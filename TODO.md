### High Priority

- [x] **1. Fix `rules_xcodeproj` output base resolution**
The Bazel aquery path queries the wrong output base (`execroot/_main/bazel-out/fastbuild-*`) instead of `rules_xcodeproj.noindex/build_output_base/`. This is the main blocker for hot-reload in rules_xcodeproj projects. Fix: detect `rules_xcodeproj.noindex` in the workspace and redirect aquery or fall back to xcactivitylog parsing. - https://github.com/maatheusgois-dd/InjectionLite/pull/1

- [x] **2. ~~Add `compiling`/`compiled` events to `Recompiler` (submodule)~~** — `Recompiler.onCompilationEvent` + `AppDelegate` wires to `InjectionEventTracker`.

- [ ] **3. Strip `-emit-object` in all code paths**
`swift-frontend -emit-object` silently ignores `-o` and produces no output. The fix (`-emit-object` → `-c`) needs to be in both `BazelAQueryParser.prepareFinalCommand` AND `LogParser.prepareFinalCommand` AND `FrontendServer.CompilationArgParser` (for the stored args).

---

### Medium Priority

- [ ] **4. `ulid.swift` fix for `BazelAQueryParser.extractSwiftSourceFiles`**
The same `.swift`-suffixed path bug exists in the aquery parser's source file extraction. We fixed `FrontendServer.CompilationArgParser` but the aquery path has the same issue when it encounters `-I path/to/swiftpkg_ulid.swift` as a separate token.

- [ ] **5. Smart cache invalidation**
InjectionNext caches compilation commands in a plist. When Bazel config changes (e.g. new dependency, different build config), the cache becomes stale and causes silent failures. Add a hash of the Xcode build log timestamp or DerivedData modification time to auto-invalidate.

- [ ] **6. MCP resource for live compilation status (SSE/streaming)**
Instead of polling `get_injection_status`, expose an MCP resource that streams events. The AI agent could subscribe and react immediately instead of polling every N seconds.

---

### Low Priority / Polish

- [ ] **7. Auto-detect `rules_xcodeproj` vs direct Bazel**
Currently InjectionNext always tries `bazel aquery` first. It should detect `rules_xcodeproj.noindex` in the workspace and skip aquery entirely, going straight to xcactivitylog parsing which has the correct paths.

- [ ] **8. Better error messages for common failures**
Map specific error patterns to actionable messages:
- "module map file not found" → "Bazel output base mismatch — try `make hot-reload` to regenerate"
- "no such file: eval1.o" → "Compilation silently failed — check `-emit-object` flag"
- "no such module 'X'" → "Module X not found in include paths — rebuild in Xcode first"

- [ ] **9. Cursor rule with MCP polling pattern**
Update `.cursor/rules/rule-hot-reload.mdc` with the `get_injection_status` polling pattern so AI agents automatically check injection status after making changes.

- [ ] **10. `make setup-hot-reload` pins to a working commit**
The setup script pins `PINNED_VERSION = "v1.6.1"` but all our fixes are on `Xcode26.3` branch. Update the pin after merging fixes, or make the script build from a specific branch.
