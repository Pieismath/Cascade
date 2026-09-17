#!/usr/bin/env node
// Run one scan through a provider from your own machine, with your own key,
// so you can judge recognition quality before wiring anything to the app.
// Nothing is uploaded to the worker and no account or credit is involved.
//
//   export GEMINI_API_KEY=...        (or ANTHROPIC_API_KEY=...)
//   node tools/try-scan.mjs ../../Resources/Sample-FurElise-1.png
//
// Options:
//   --provider gemini|anthropic   which one to call (default: whichever key is set)
//   --quality standard|high       the app's normal pass or its retry tier
//   --out path.musicxml           where to write the result (default: ./scan-out.musicxml)

import { readFile, writeFile } from "node:fs/promises";
import { basename } from "node:path";
import { recognize } from "../src/providers.js";

const args = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const files = args.filter((a, i) => !a.startsWith("--") && !args[i - 1]?.startsWith("--"));

if (files.length === 0) {
  console.error("usage: node tools/try-scan.mjs <page.png|page.jpg> [more pages…] [--provider gemini|anthropic] [--quality standard|high] [--out file.musicxml]");
  process.exit(1);
}

const env = {
  GEMINI_API_KEY: process.env.GEMINI_API_KEY,
  ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
  GEMINI_MODEL: process.env.GEMINI_MODEL,
  GEMINI_MODEL_HIGH: process.env.GEMINI_MODEL_HIGH,
  ANTHROPIC_MODEL: process.env.ANTHROPIC_MODEL,
  ANTHROPIC_MODEL_HIGH: process.env.ANTHROPIC_MODEL_HIGH,
  PRIMARY_PROVIDER: flag("provider", process.env.PRIMARY_PROVIDER),
};

if (!env.GEMINI_API_KEY && !env.ANTHROPIC_API_KEY) {
  console.error("Set GEMINI_API_KEY or ANTHROPIC_API_KEY in your shell first.");
  process.exit(1);
}
// Only call the provider that was asked for.
if (env.PRIMARY_PROVIDER === "gemini") env.ANTHROPIC_API_KEY = undefined;
if (env.PRIMARY_PROVIDER === "anthropic") env.GEMINI_API_KEY = undefined;

const pages = [];
for (const file of files) {
  pages.push((await readFile(file)).toString("base64"));
}

const quality = flag("quality", "standard");
const started = Date.now();
console.log(`Sending ${pages.length} page(s) — ${files.map((f) => basename(f)).join(", ")}…`);

let result;
try {
  result = await recognize(env, pages, quality);
} catch (err) {
  console.error("\nFailed:", err.message);
  process.exit(1);
}

const xml = result.musicXML;
const seconds = ((Date.now() - started) / 1000).toFixed(1);
const measures = (xml.match(/<measure\b/g) || []).length;
const notes = (xml.match(/<note>/g) || []).length;
const rests = (xml.match(/<rest\b/g) || []).length;
const tempo = xml.match(/<sound tempo="([\d.]+)"/)?.[1] ?? "none";

const out = flag("out", "scan-out.musicxml");
await writeFile(out, xml);

console.log(`
provider   ${result.provider}
time       ${seconds}s
measures   ${measures}
notes      ${notes} (${rests} rests)
tempo      ${tempo}
written to ${out}

Open ${out} in MuseScore to check it against the printed page, or import it
into Cascade (Home → Import) to hear and watch it.`);
