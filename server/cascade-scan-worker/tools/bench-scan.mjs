#!/usr/bin/env node
// Runs the same pages through several models and prints one table, so the
// "which provider should I pay for" question is answered with measurements.
//
//   export GEMINI_API_KEY=...        (and/or ANTHROPIC_API_KEY=...)
//   node tools/bench-scan.mjs
//
// With no arguments it uses the four system crops in ~/cascade-crops and the
// bundled Für Elise transcription as the right answer. Otherwise:
//
//   node tools/bench-scan.mjs --ref path/to/truth.musicxml page1.jpg page2.jpg
//
// Each configuration is one request; on Gemini's free tier keep an eye on the
// per-minute limit if you add many.

import { readFile, writeFile, access } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { recognize } from "../src/providers.js";
import { scoreScan, pct } from "./score.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const given = args.filter((a, i) => !a.startsWith("--") && !args[i - 1]?.startsWith("--"));

const exists = async (path) => access(path).then(() => true).catch(() => false);

const defaultCrops = [1, 2, 3, 4].map((n) =>
  join(homedir(), "cascade-crops", `Sample-FurElise-1-system-0${n}.jpg`)
);
const pagePaths = given.length ? given : defaultCrops;
const referencePath = flag("ref", resolve(here, "../../../Resources/FurEliseOpening.musicxml"));

for (const path of [...pagePaths, referencePath]) {
  if (!(await exists(path))) {
    console.error(`missing: ${path}`);
    if (!given.length) {
      console.error("\nRun the crop dump first:\n  TEST_RUNNER_CROP_DIR=~/cascade-crops xcodebuild -project Cascade.xcodeproj -scheme MyPianoInstructor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:MyPianoInstructorTests/SystemCropDump");
    }
    process.exit(1);
  }
}

const pages = [];
for (const path of pagePaths) pages.push((await readFile(path)).toString("base64"));
const reference = await readFile(referencePath, "utf8");

const configurations = [];
if (process.env.GEMINI_API_KEY) {
  configurations.push(
    { label: "gemini 3.6 flash", env: { GEMINI_MODEL: "gemini-3.6-flash" } },
    { label: "gemini 3.6 · think medium", env: { GEMINI_MODEL: "gemini-3.6-flash", GEMINI_THINKING_LEVEL: "medium" } },
    { label: "gemini 3.8 flash", env: { GEMINI_MODEL: "gemini-3.8-flash" } }
  );
}
if (process.env.ANTHROPIC_API_KEY) {
  configurations.push({ label: "claude sonnet", env: { ANTHROPIC_MODEL: process.env.ANTHROPIC_MODEL || "claude-sonnet-5" } });
}
if (configurations.length === 0) {
  console.error("Set GEMINI_API_KEY and/or ANTHROPIC_API_KEY first.");
  process.exit(1);
}

console.log(`${pages.length} image(s): ${pagePaths.map((p) => basename(p)).join(", ")}`);
console.log(`truth: ${basename(referencePath)}\n`);

const rows = [];
for (const configuration of configurations) {
  const usesGemini = !configuration.env.ANTHROPIC_MODEL;
  const env = {
    ...configuration.env,
    GEMINI_API_KEY: usesGemini ? process.env.GEMINI_API_KEY : undefined,
    ANTHROPIC_API_KEY: usesGemini ? undefined : process.env.ANTHROPIC_API_KEY,
  };

  process.stdout.write(`running ${configuration.label}… `);
  const started = Date.now();
  try {
    const result = await recognize(env, pages, "standard");
    const seconds = (Date.now() - started) / 1000;
    const score = scoreScan(result.musicXML, reference);
    const out = join(homedir(), `bench-${configuration.label.replace(/[^a-z0-9]+/gi, "-")}.musicxml`);
    await writeFile(out, result.musicXML);
    rows.push({ label: configuration.label, seconds, score, out });
    console.log(`${seconds.toFixed(0)}s`);
  } catch (error) {
    console.log(`failed: ${error.message}`);
    rows.push({ label: configuration.label, failed: error.message });
  }
}

const pad = (text, width) => String(text).padEnd(width);
console.log(`
${pad("model", 26)} ${pad("pitches", 9)} ${pad("perfect bars", 13)} ${pad("rhythm", 9)} ${pad("tempo", 7)} time`);
console.log("-".repeat(78));
for (const row of rows) {
  if (row.failed) {
    console.log(`${pad(row.label, 26)} ${row.failed}`);
    continue;
  }
  const s = row.score;
  const rhythm = s.rhythmExact >= s.rhythmSteady - 0.001 ? pct(s.rhythmExact) : `${pct(s.rhythmSteady)}*`;
  console.log(
    `${pad(row.label, 26)} ${pad(pct(s.pitchAccuracy), 9)} ${pad(pct(s.perfectBars), 13)} ${pad(rhythm, 9)} ${pad(s.tempo || "—", 7)} ${row.seconds.toFixed(0)}s`
  );
}
console.log(`
* rhythm written in different note values but consistent — plays correctly.
Reference tempo ${Math.round(scoreScan(reference, reference).referenceTempo)}. Transcriptions saved to ~/bench-*.musicxml.`);
