#!/usr/bin/env node
/**
 * Smoke-test MCP stdio ↔ InjectionNext without Cursor.
 * Run: node scripts/test-stdio.mjs  (from mcp-server; InjectionNext.app must be running)
 */
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const proc = spawn("node", [path.join(root, "index.js")], {
  cwd: root,
  stdio: ["pipe", "pipe", "pipe"],
});

function send(o) {
  proc.stdin.write(JSON.stringify(o) + "\n");
}

proc.stdout.setEncoding("utf8");
proc.stdout.on("data", (chunk) => {
  for (const line of chunk.split("\n")) {
    if (line.trim()) console.log("stdout:", line);
  }
});
proc.stderr.on("data", (c) => process.stderr.write(String(c)));

send({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    protocolVersion: "2025-11-25",
    capabilities: {},
    clientInfo: { name: "injection-next-mcp-test", version: "0.0.1" },
  },
});

await new Promise((r) => setTimeout(r, 400));
send({ jsonrpc: "2.0", method: "notifications/initialized" });
await new Promise((r) => setTimeout(r, 150));
send({
  jsonrpc: "2.0",
  id: 2,
  method: "tools/call",
  params: { name: "get_status", arguments: {} },
});

await new Promise((r) => setTimeout(r, 8000));
proc.kill("SIGTERM");
process.exit(0);
