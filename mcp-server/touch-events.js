#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function usage() {
  return `Usage:
  node touch-events.js get [events.json]
  node touch-events.js replay <events.json>
  node touch-events.js roundtrip [events.json]

Commands:
  get        Fetch accumulated touch events, print them, and clear the app buffer.
  replay     Replay touch events from a JSON file.
  roundtrip  Fetch events, optionally save them, then immediately replay them.`;
}

function textContent(result) {
  return (result.content || [])
    .filter((item) => item.type === "text")
    .map((item) => item.text)
    .join("\n");
}

function parseToolJSON(result, toolName) {
  const text = textContent(result);
  if (result.isError) {
    throw new Error(text || `${toolName} MCP tool returned an error`);
  }
  if (!text) {
    return {};
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${toolName} returned non-JSON text:\n${text}`);
  }
}

function normalizeEvents(data) {
  if (Array.isArray(data)) {
    return { events: data };
  }
  if (Array.isArray(data.events)) {
    return data;
  }
  throw new Error("Touch event payload must be an array or an object with an events array");
}

async function readEventsFile(file) {
  const text = await fs.readFile(path.resolve(file), "utf8");
  return normalizeEvents(JSON.parse(text));
}

async function writeEventsFile(file, events) {
  if (!file) return;
  await fs.writeFile(path.resolve(file), JSON.stringify(events, null, 2) + "\n");
}

const command = process.argv[2] || "roundtrip";
const file = process.argv[3];

if (!["get", "replay", "roundtrip", "-h", "--help", "help"].includes(command)) {
  console.error(usage());
  process.exit(2);
}

if (["-h", "--help", "help"].includes(command)) {
  console.log(usage());
  process.exit(0);
}

if (command === "replay" && !file) {
  console.error(usage());
  process.exit(2);
}

let client;

async function ensureClientApp() {
  const status = await client.callTool({
    name: "get_status",
    arguments: {},
  });
  const statusData = parseToolJSON(status, "get_status");
  if (!statusData.has_connected_client) {
    throw new Error(
      "No connected client app. Launch an app that has the InjectionNext " +
      "package/bundle loaded, then retry once InjectionNext reports a " +
      "connected client."
    );
  }
}

async function getEvents() {
  const result = await client.callTool({
    name: "get_touch_events",
    arguments: {},
  });
  return normalizeEvents(parseToolJSON(result, "get_touch_events"));
}

async function replayEvents(events) {
  const result = await client.callTool({
    name: "replay_touch_events",
    arguments: events,
  });
  return parseToolJSON(result, "replay_touch_events");
}

async function main() {
  const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
  const { StdioClientTransport } =
    await import("@modelcontextprotocol/sdk/client/stdio.js");

  client = new Client({
    name: "injection-next-touch-events-cli",
    version: "1.0.0",
  });

  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.join(__dirname, "index.js")],
    cwd: __dirname,
    stderr: "inherit",
  });

  await client.connect(transport);
  await ensureClientApp();

  if (command === "replay") {
    const events = await readEventsFile(file);
    console.log(JSON.stringify(events, null, 2));
    const result = await replayEvents(events);
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  const events = await getEvents();
  console.log(JSON.stringify(events, null, 2));
  await writeEventsFile(file, events);

  if (command === "roundtrip") {
    const result = await replayEvents(events);
    console.log(JSON.stringify(result, null, 2));
  }
}

try {
  await main();
} finally {
  await client?.close();
}
