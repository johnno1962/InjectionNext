#!/usr/bin/env node

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function outputPathFromArgs() {
  const arg = process.argv[2];
  if (arg) return path.resolve(arg);

  const stamp = new Date().toISOString()
    .replace(/[:.]/g, "-")
    .replace("T", "_")
    .replace("Z", "");
  return path.resolve(`injection-screenshot-${stamp}.png`);
}

const client = new Client({
  name: "injection-next-screenshot-cli",
  version: "1.0.0",
});

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(__dirname, "index.js")],
  cwd: __dirname,
  stderr: "inherit",
});

function textContent(result) {
  return (result.content || [])
    .filter((item) => item.type === "text")
    .map((item) => item.text)
    .join("\n");
}

async function main() {
  await client.connect(transport);

  const status = await client.callTool({
    name: "get_status",
    arguments: {},
  });
  const statusText = textContent(status);
  const statusData = statusText ? JSON.parse(statusText) : {};
  if (!statusData.has_connected_client) {
    throw new Error(
      "No connected client app. Launch an app that has the InjectionNext " +
      "package/bundle loaded, then retry once InjectionNext reports a " +
      "connected client."
    );
  }

  const result = await client.callTool({
    name: "take_screenshot",
    arguments: {},
  });

  if (result.isError) {
    const message = textContent(result) ||
      "Screenshot MCP tool returned an error";
    throw new Error(message);
  }

  const image = (result.content || []).find((item) => item.type === "image");
  if (!image || !image.data) {
    throw new Error("Screenshot MCP tool did not return image data");
  }

  const output = outputPathFromArgs();
  await fs.writeFile(output, Buffer.from(image.data, "base64"));

  const bytes = Buffer.byteLength(image.data, "base64");
  console.log(`Wrote ${bytes} bytes (${image.mimeType || "image/png"}) to ${output}`);
}

try {
  await main();
} finally {
  await client.close();
}
