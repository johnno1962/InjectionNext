## Bazel Support

This version includes enhanced Bazel build system support with automatic target discovery and optimized compilation queries. When InjectionLite detects a Bazel workspace (via `MODULE.bazel` or `WORKSPACE` files), it automatically:

1. **Auto-discovers iOS application targets** from your Bazel build graph, prioritizing targets closer to the workspace root
2. **Generates optimized aquery commands** that only query dependencies of your app targets, reducing overhead
3. **Handles Bazel-specific placeholders** like `__BAZEL_XCODE_SDKROOT__` and `__BAZEL_XCODE_DEVELOPER_DIR__`
4. **Processes output-file-map configurations** for better compatibility with Bazel's compilation strategy
5. **Automatically overrides whole-module-optimization** settings that interfere with hot reloading

The system uses a two-tier approach: first attempting optimized queries using discovered app targets, then falling back to legacy broad queries if needed. This ensures compatibility while providing performance benefits for typical iOS development workflows.

Bazel integration requires either `bazel` or `/opt/homebrew/bin/bazelisk` to be available in your system PATH.

### rules_xcodeproj Support

When a project uses `rules_xcodeproj`, Xcode builds artifacts in a separate output base at `<outputBase>/rules_xcodeproj.noindex/build_output_base/` rather than the main Bazel output base. InjectionNext automatically detects this and:

- Resolves `bazel-out/` paths to the rules_xcodeproj output base
- Maps aquery configuration hashes (e.g. `ios_sim_arm64-fastbuild-*`) to the corresponding rules_xcodeproj configs (e.g. `ios_sim_arm64-dbg-*`)
- Uses the rules_xcodeproj exec root as the working directory for recompilation

This is transparent — hot reloading works the same whether you build via `bazel run` or from Xcode with a rules_xcodeproj-generated project.
