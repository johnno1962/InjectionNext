## Bazel Support

This version includes enhanced Bazel build system support with automatic target discovery and optimized compilation queries. When InjectionLite detects a Bazel workspace (via `MODULE.bazel` or `WORKSPACE` files), it automatically:

1. **Auto-discovers iOS application targets** from your Bazel build graph, prioritizing targets closer to the workspace root
2. **Generates optimized aquery commands** that only query dependencies of your app targets, reducing overhead
3. **Handles Bazel-specific placeholders** like `__BAZEL_XCODE_SDKROOT__` and `__BAZEL_XCODE_DEVELOPER_DIR__`
4. **Processes output-file-map configurations** for better compatibility with Bazel's compilation strategy
5. **Automatically overrides whole-module-optimization** settings that interfere with hot reloading

The system uses a two-tier approach: first attempting optimized queries using discovered app targets, then falling back to legacy broad queries if needed. This ensures compatibility while providing performance benefits for typical iOS development workflows.

Bazel integration requires either `bazel` or `/opt/homebrew/bin/bazelisk` to be available in your system PATH.

### ⚠️ rules_xcodeproj Limitation

**Important**: Currently, Bazel queries and commands cannot be executed from within the rules_xcodeproj-generated Xcode project environment. This means:

- If you run your app from Xcode using a rules_xcodeproj-generated project and modify a file, **hot reloading will not work** because the app runs through a different execution route that doesn't provide access to Bazel tooling
- **Workaround**: Run your app directly from the terminal using `bazel run` instead of launching from Xcode to enable hot reloading functionality
- This limitation only affects rules_xcodeproj workflows - standard Bazel development workflows are fully supported

We're working on addressing this limitation in future releases.
