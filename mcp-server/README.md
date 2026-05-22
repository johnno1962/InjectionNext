# InjectionNext MCP Server

MCP (Model Context Protocol) server that lets AI agents control InjectionNext — start file watching, check status, read debug logs, toggle device injection, and more.

## Prerequisites

- **macOS** with Xcode installed
- **Node.js** 18.14.1+
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

## Step 2: Enable the ControlServer

The TCP control server is **opt-in**. Enable it via a UserDefault before launching the app:

```bash
defaults write com.johnholdsworth.InjectionNext mcpServer -bool true
```

To disable it later:

```bash
defaults delete com.johnholdsworth.InjectionNext mcpServer
```

## Step 3: Install the MCP server

```bash
cd mcp-server
npm install
```

## Step 4: Configure Cursor

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

## Step 5: Launch InjectionNext

Start the app before using the MCP tools:

```bash
open /Applications/InjectionNext.app
# or from DerivedData:
open ~/Library/Developer/Xcode/DerivedData/InjectionNext-*/Build/Products/Debug/InjectionNext.app
```

You should see the InjectionNext icon in the menu bar.

## Step 6: Test it

### Quick test from terminal (no MCP needed)

```bash
# Check status
echo '{"action":"status"}' | nc -U /tmp/InjectionNext-control.sock

# Start watching a project
echo '{"action":"watch_project","path":"/path/to/your/project"}' | nc -U /tmp/InjectionNext-control.sock

# Read debug logs
echo '{"action":"get_logs"}' | nc -U /tmp/InjectionNext-control.sock

# Stop watching
echo '{"action":"stop_watching"}' | nc -U /tmp/InjectionNext-control.sock
```

### Screenshot test from terminal

This starts the MCP server over stdio, calls its `take_screenshot` tool, and writes the returned PNG:

```bash
cd mcp-server
npm run screenshot -- /tmp/injection-screenshot.png
```

`take_screenshot` captures the connected client app, not the InjectionNext menu-bar app. Launch a target app that has the InjectionNext package/bundle loaded before running this command.

### Touch event test from terminal

Touch capture is enabled only when the ControlServer/MCP option is enabled and the client app connects. After changing the `mcpServer` default or rebuilding InjectionNext, restart InjectionNext and relaunch the target app so the client receives the capture command during connection.

Fetch accumulated touch events, print them, save them, and clear the app buffer:

```bash
cd mcp-server
npm run touch-events -- get /tmp/injection-events.json
```

Replay saved events into the connected client app:

```bash
npm run touch-events -- replay /tmp/injection-events.json
```

Or fetch and immediately replay the same events:

```bash
npm run touch-events -- roundtrip /tmp/injection-events.json
```

Events are JSON and preserve the recorded timing interval between touch events. Replayed touches show a temporary translucent circle in the client app.

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
| `take_screenshot` | Capture a PNG screenshot from the connected client app |
| `get_touch_events` | Fetch and clear accumulated touch event JSON from the connected client app |
| `replay_touch_events` | Replay captured touch event JSON in the connected client app |
| `prepare_swiftui_source` | Add injection annotations to current SwiftUI file |
| `prepare_swiftui_project` | Prepare all SwiftUI files in target |
| `set_xcode_path` | Point to a different Xcode.app |
| `get_logs` | Read debug console (supports `since` for polling) |
| `clear_logs` | Clear the log buffer |

## Architecture

```
┌─────────────┐   Unix domain socket    ┌──────────────────────┐
│  MCP Server │◄───────────────────────►│  InjectionNext.app   │
│  (Node.js)  │   JSON commands/resp    │  ┌─────────────────┐ │
│             │                         │  │  ControlServer  │ │
│  stdio ↕    │                         │  │  (UDS listener) │ │
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

**"Cannot connect to InjectionNext control socket"**
- Make sure InjectionNext.app is running (check menu bar icon)
- Make sure you built the version with ControlServer support (from this repo)
- Check: `ls -l /tmp/InjectionNext-control.sock` should show the socket

**Stale socket file**
- Kill any stale InjectionNext processes: `pkill -f InjectionNext`
- Re-launch the app

**Logs are empty**
- Logs only capture events that happen while the app is running
- Try `watch_project` to generate some activity, then `get_logs`

**Touch events are empty**
- Make sure `mcpServer` was enabled before launching InjectionNext
- Restart InjectionNext and relaunch the target app so it reconnects
- Touch capture starts only after the client receives the MCP capture command during connection
