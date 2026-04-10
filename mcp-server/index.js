#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import net from "node:net";

const CONTROL_PORT = 8919;
const CONTROL_HOST = "127.0.0.1";

function sendCommand(action, params = {}) {
  return new Promise((resolve, reject) => {
    const client = new net.Socket();
    const timeout = setTimeout(() => {
      client.destroy();
      reject(new Error("Connection timed out. Is InjectionNext running with ControlServer?"));
    }, 5000);

    client.connect(CONTROL_PORT, CONTROL_HOST, () => {
      const payload = JSON.stringify({ action, ...params }) + "\n";
      client.write(payload);
    });

    let data = "";
    client.on("data", (chunk) => {
      data += chunk.toString();
      if (data.includes("\n")) {
        clearTimeout(timeout);
        client.destroy();
        try {
          resolve(JSON.parse(data.trim()));
        } catch {
          reject(new Error("Invalid JSON response from InjectionNext"));
        }
      }
    });

    client.on("error", (err) => {
      clearTimeout(timeout);
      if (err.code === "ECONNREFUSED") {
        reject(new Error(
          "Cannot connect to InjectionNext on port 8919. " +
          "Make sure InjectionNext.app is running (build with ControlServer support)."
        ));
      } else {
        reject(err);
      }
    });
  });
}

function formatResponse(result) {
  if (!result.success) {
    return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
  }
  const text = result.data
    ? JSON.stringify(result.data, null, 2)
    : "OK";
  return { content: [{ type: "text", text }] };
}

const server = new McpServer({
  name: "injection-next",
  version: "1.0.0",
});

server.tool(
  "get_status",
  "Get the current status of InjectionNext: Xcode state, watched directories, compiler interception, connected clients, and last error",
  {},
  async () => {
    const result = await sendCommand("status");
    return formatResponse(result);
  }
);

server.tool(
  "watch_project",
  "Start file-watching a project directory for hot-reloading. This enables injection for Cursor/VS Code workflows without launching Xcode through the app.",
  { path: z.string().describe("Absolute path to the project directory to watch") },
  async ({ path }) => {
    const result = await sendCommand("watch_project", { path });
    return formatResponse(result);
  }
);

server.tool(
  "stop_watching",
  "Stop watching all project directories",
  {},
  async () => {
    const result = await sendCommand("stop_watching");
    return formatResponse(result);
  }
);

server.tool(
  "launch_xcode",
  "Launch Xcode through InjectionNext with SOURCEKIT_LOGGING enabled for full injection support",
  {},
  async () => {
    const result = await sendCommand("launch_xcode");
    return formatResponse(result);
  }
);

server.tool(
  "get_compiler_state",
  "Check whether the Swift compiler is currently intercepted (patched) by InjectionNext",
  {},
  async () => {
    const result = await sendCommand("intercept_compiler");
    return formatResponse(result);
  }
);

server.tool(
  "enable_devices",
  "Enable or disable device injection support (opens TCP port for device/simulator connections)",
  { enable: z.boolean().describe("true to enable, false to disable") },
  async ({ enable }) => {
    const result = await sendCommand("enable_devices", { enable });
    return formatResponse(result);
  }
);

server.tool(
  "unhide_symbols",
  "Unhide default-argument symbols in the current build to fix injection loading failures",
  {},
  async () => {
    const result = await sendCommand("unhide_symbols");
    return formatResponse(result);
  }
);

server.tool(
  "get_last_error",
  "Get the last compilation error from InjectionNext",
  {},
  async () => {
    const result = await sendCommand("get_last_error");
    return formatResponse(result);
  }
);

server.tool(
  "prepare_swiftui_source",
  "Automatically add .enableInjection() and @ObserveInjection to the currently edited SwiftUI source file",
  {},
  async () => {
    const result = await sendCommand("prepare_swiftui_source");
    return formatResponse(result);
  }
);

server.tool(
  "prepare_swiftui_project",
  "Prepare all SwiftUI source files in the current target for hot-reloading injection",
  {},
  async () => {
    const result = await sendCommand("prepare_swiftui_project");
    return formatResponse(result);
  }
);

server.tool(
  "set_xcode_path",
  "Set the path to the Xcode installation to use",
  { path: z.string().describe("Absolute path to Xcode.app (e.g. /Applications/Xcode.app)") },
  async ({ path }) => {
    const result = await sendCommand("set_xcode_path", { path });
    return formatResponse(result);
  }
);

server.tool(
  "get_logs",
  "Read the InjectionNext debug console — returns recent log entries including injection events, compilation output, errors, file watcher activity, and client connections. Use 'since' (unix timestamp) to get only new logs since your last read.",
  {
    since: z.number().optional().describe("Unix timestamp — only return logs after this time. Omit to get all recent logs."),
    limit: z.number().optional().describe("Max entries to return (default 200, max 500)"),
  },
  async ({ since, limit }) => {
    const params = {};
    if (since !== undefined) params.since = since;
    if (limit !== undefined) params.limit = limit;
    const result = await sendCommand("get_logs", params);
    if (!result.success) {
      return { content: [{ type: "text", text: `Error: ${result.error}` }], isError: true };
    }
    const logs = result.data?.logs ?? [];
    if (logs.length === 0) {
      return { content: [{ type: "text", text: "No new log entries." }] };
    }
    const lines = logs.map((e) => {
      const ts = new Date(e.timestamp * 1000).toISOString().slice(11, 23);
      const tag = e.level !== "info" ? ` [${e.level.toUpperCase()}]` : "";
      return `${ts}${tag} ${e.message}`;
    });
    const header = `--- ${logs.length} log entries (${result.data.count} total buffered) ---`;
    return { content: [{ type: "text", text: header + "\n" + lines.join("\n") }] };
  }
);

server.tool(
  "clear_logs",
  "Clear the InjectionNext log buffer",
  {},
  async () => {
    const result = await sendCommand("clear_logs");
    return formatResponse(result);
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
