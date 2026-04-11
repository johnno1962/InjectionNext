# InjectionNext MCP Server

MCP (Model Context Protocol) server that lets AI agents control InjectionNext — start file watching, check status, read debug logs, toggle device injection, and more.

## Prerequisites

- **macOS** with Xcode installed
- **Node.js** 18+
- **InjectionNext.app** built from this repo (with ControlServer support)

## Step 1: Build InjectionNext with ControlServer

```bash
# Clone and init submodules
git clone <repo-url>
cd InjectionNext
git submodule update --init --recursive

# Build the app (ad-hoc signing for local dev)
cd App
xcodebuild -project InjectionNext.xcodeproj \
  -scheme InjectionNext \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# The built app is at:
# ~/Library/Developer/Xcode/DerivedData/InjectionNext-*/Build/Products/Debug/InjectionNext.app
```

Optionally copy it to `/Applications`:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/InjectionNext-*/Build/Products/Debug/InjectionNext.app /Applications/
```

## Step 2: Install the MCP server

```bash
cd mcp-server
npm install
```

## Step 3: Configure Cursor

Add to your Cursor MCP config at `~/.cursor/mcp.json` (global) or `.cursor/mcp.json` (per-project):

```json
{
  "mcpServers": {
    "injection-next": {
      "command": "node",
      "args": ["/absolute/path/to/InjectionNext/mcp-server/index.js"]
    }
  }
}
```

Replace `/absolute/path/to` with the actual path to this repo.

## Step 4: Launch InjectionNext

Start the app before using the MCP tools:

```bash
open /Applications/InjectionNext.app
# or from DerivedData:
open ~/Library/Developer/Xcode/DerivedData/InjectionNext-*/Build/Products/Debug/InjectionNext.app
```

You should see the InjectionNext icon in the menu bar.

## Step 5: Test it

### Quick test from terminal (no MCP needed)

```bash
# Check status
echo '{"action":"status"}' | nc -w 3 localhost 8919

# Start watching a project
echo '{"action":"watch_project","path":"/path/to/your/project"}' | nc -w 3 localhost 8919

# Read debug logs
echo '{"action":"get_logs"}' | nc -w 3 localhost 8919

# Stop watching
echo '{"action":"stop_watching"}' | nc -w 3 localhost 8919
```

### Test from Cursor

After configuring the MCP server, open Cursor and ask the AI:

> "Use the injection-next MCP to check the status of InjectionNext"

or:

> "Watch my project at /path/to/project for hot reloading"

or:

> "Show me the InjectionNext debug logs"

## Available Tools

| Tool | Description |
|------|-------------|
| `get_status` | Full app status: Xcode, watched dirs, compiler, clients |
| `watch_project` | Start file-watching a directory for hot-reloading |
| `stop_watching` | Stop all file watchers |
| `launch_xcode` | Launch Xcode via InjectionNext with SourceKit logging |
| `get_compiler_state` | Check if Swift compiler is intercepted |
| `enable_devices` | Toggle device/simulator injection support |
| `unhide_symbols` | Fix default-argument symbol visibility issues |
| `get_last_error` | Get last compilation error |
| `prepare_swiftui_source` | Add injection annotations to current SwiftUI file |
| `prepare_swiftui_project` | Prepare all SwiftUI files in target |
| `set_xcode_path` | Point to a different Xcode.app |
| `get_logs` | Read debug console (supports `since` for polling) |
| `clear_logs` | Clear the log buffer |

## Architecture

```
┌─────────────┐       TCP :8919         ┌──────────────────────┐
│  MCP Server │◄───────────────────────►│  InjectionNext.app   │
│  (Node.js)  │   JSON commands/resp    │  ┌─────────────────┐ │
│             │                         │  │  ControlServer  │ │
│  stdio ↕    │                         │  │  (TCP listener) │ │
│             │                         │  └────────┬────────┘ │
│  Cursor /   │                         │           │          │
│  AI Agent   │                         │  ┌────────▼────────┐ │
└─────────────┘                         │  │  AppDelegate    │ │
                                        │  │  IBActions      │ │
                                        │  └────────┬────────┘ │
                                        │           │          │
                                        │  ┌────────▼────────┐ │
                                        │   │  LogBuffer     │ │
                                        │  │  (ring buffer)  │ │
                                        │  └─────────────────┘ │
                                        └──────────────────────┘
```

## Troubleshooting

**"Cannot connect to InjectionNext on port 8919"**
- Make sure InjectionNext.app is running (check menu bar icon)
- Make sure you built the version with ControlServer support (from this repo)
- Check: `lsof -i :8919` should show InjectionNext listening

**Port already in use**
- Kill any stale InjectionNext processes: `pkill -f InjectionNext`
- Re-launch the app

**Logs are empty**
- Logs only capture events that happen while the app is running
- Try `watch_project` to generate some activity, then `get_logs`
