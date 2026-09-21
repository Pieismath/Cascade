#!/usr/bin/env node
// Runs the same pages through several models and batch sizes and prints one
// table, so "which provider, and how should the app call it" is answered with
// measurements. Requests carry the same continuation context the app sends
// (ScoreTranscriptionJob.context), so the numbers match what users would get.
//
//   export GEMINI_API_KEY=...        (and/or ANTHROPIC_API_KEY=...)
//   node tools/bench-scan.mjs
//
// With no arguments it uses the four system crops in ~/cascade-crops and the
// bundled Für Elise transcription as the right answer. Otherwise:
//
//   node tools/bench-scan.mjs --ref path/to/truth.musicxml crop1.jpg crop2.jpg …

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

const defaultCrops = [1, 2, 3, 4].map((n) => join(homedir(), "cascade-crops", `Sample-FurElise-1-system-0${n}.jpg`));
const pagePaths = given.length ? given : defaultCrops;
const referencePath = flag("ref", resolve(here, "../../../Resources/FurEliseOpening.musicxml"));
// Bars actually on the pages sent: the default crops are Für Elise systems 1–4,
// three bars each. Pass --bars for your own pages.
const expectedMeasures = Number(flag("bars", given.length ? 0 : 12)) || undefined;

for (const path of [...pagePaths, referencePath]) {
  if (!(await exists(path))) {
    console.error(`missing: ${path}`);
    process.exit(1);
  }
}

const images = [];
for (const path of pagePaths) images.push((await readFile(path)).toString("base64"));
const reference = await readFile(referencePath, "utf8");

// MARK: - The app's continuation context (port of ScoreTranscriptionJob.context)

function attributesOf(xml, previous = {}) {
  const first = (re) => xml.match(re)?.[1];
  const tempos = [...xml.matchAll(/<sound tempo="([\d.]+)"/g)].map((m) => Number(m[1]));
  return {
    divisions: Number(first(/<divisions>(\d+)<\/divisions>/)) || previous.divisions,
    fifths: first(/<fifths>(-?\d+)<\/fifths>/) ?? previous.fifths,
    beats: first(/<beats>(\d+)<\/beats>/) ?? previous.beats,
    beatType: first(/<beat-type>(\d+)<\/beat-type>/) ?? previous.beatType,
    tempo: tempos.at(-1) ?? previous.tempo,
    measures: (previous.measures ?? 0) + (xml.match(/<measure\b/g) || []).length,
  };
}

function context(batchIndex, batchCount, attributes) {
  const lines = [
    "The images are consecutive systems (groups of staves) cropped from the same printed score, in reading order — not full pages. Transcribe them as one continuous passage.",
  ];
  if (batchCount > 1) lines.push(`This is part ${batchIndex + 1} of ${batchCount} of the same piece.`);
  if (batchIndex > 0) {
    lines.push(`Continue directly from the previous part: number the first measure ${attributes.measures + 1}. Include a complete <attributes> block (divisions, key, time, staves, clefs) in your first measure so the document is self-contained.`);
    const facts = [];
    if (attributes.divisions) facts.push(`<divisions>${attributes.divisions}</divisions>`);
    if (attributes.fifths != null) facts.push(`key fifths ${attributes.fifths}`);
    if (attributes.beats && attributes.beatType) facts.push(`time ${attributes.beats}/${attributes.beatType}`);
    if (attributes.tempo) facts.push(`tempo ${Math.round(attributes.tempo)} BPM`);
    if (facts.length) {
      lines.push(`Established so far: ${facts.join(", ")}. Keep the same divisions value; only emit <sound tempo> if the image shows a tempo change.`);
    }
  }
  return lines.join(" ");
}

// MARK: - Configurations

const configurations = [];
if (process.env.GEMINI_API_KEY) {
  configurations.push(
    { label: "gemini 3.6 · 4 per request", model: "gemini-3.6-flash", batch: 4 },
    { label: "gemini 3.8 · 4 per request", model: "gemini-3.8-flash", batch: 4 }
  );
}
if (process.env.ANTHROPIC_API_KEY) {
  configurations.push(
    { label: "claude sonnet 5 · 4 per request", model: "claude-sonnet-5", batch: 4, anthropic: true },
    { label: "claude opus 5 · 4 per request", model: "claude-opus-5", batch: 4, anthropic: true }
  );
}
if (configurations.length === 0) {
  console.error("Set GEMINI_API_KEY and/or ANTHROPIC_API_KEY first.");
  process.exit(1);
}

console.log(`${images.length} system crop(s): ${pagePaths.map((p) => basename(p)).join(", ")}`);
console.log(`truth: ${basename(referencePath)}\n`);

const rows = [];
for (const configuration of configurations) {
  const env = configuration.anthropic
    ? { ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY, ANTHROPIC_MODEL: configuration.model }
    : { GEMINI_API_KEY: process.env.GEMINI_API_KEY, GEMINI_MODEL: configuration.model };

  const batches = [];
  for (let i = 0; i < images.length; i += configuration.batch) batches.push(images.slice(i, i + configuration.batch));

  process.stdout.write(`running ${configuration.label} (${batches.length} request${batches.length === 1 ? "" : "s"})… `);
  const started = Date.now();
  const parts = [];
  let attributes = {};
  try {
    for (const [index, batch] of batches.entries()) {
      const result = await recognize(env, batch, "standard", fetch, context(index, batches.length, attributes));
      parts.push(result.musicXML);
      attributes = attributesOf(result.musicXML, attributes);
    }
    const seconds = (Date.now() - started) / 1000;
    const score = scoreScan(parts, reference, { expectedMeasures });
    const out = join(homedir(), `bench-${configuration.label.replace(/[^a-z0-9]+/gi, "-")}.musicxml`);
    await writeFile(out, parts.join("\n\n<!-- next request -->\n\n"));
    rows.push({ label: configuration.label, seconds, score });
    console.log(`${seconds.toFixed(0)}s`);
  } catch (error) {
    console.log(`failed: ${error.message}`);
    rows.push({ label: configuration.label, failed: error.message });
  }
}

const pad = (text, width) => String(text).padEnd(width);
console.log(`
${pad("setup", 30)} ${pad("bars", 7)} ${pad("pitches", 9)} ${pad("perfect bars", 13)} ${pad("rhythm", 9)} ${pad("tempo", 7)} time`);
console.log("-".repeat(88));
for (const row of rows) {
  if (row.failed) {
    console.log(`${pad(row.label, 30)} ${row.failed}`);
    continue;
  }
  const s = row.score;
  const rhythm = s.rhythmExact >= s.rhythmSteady - 0.001 ? pct(s.rhythmExact) : `${pct(s.rhythmSteady)}*`;
  console.log(
    `${pad(row.label, 30)} ${pad(`${s.comparedMeasures - s.missingMeasures}/${s.comparedMeasures}`, 7)} ${pad(pct(s.pitchAccuracy), 9)} ${pad(pct(s.perfectBars), 13)} ${pad(rhythm, 9)} ${pad(s.tempo || "—", 7)} ${row.seconds.toFixed(0)}s`
  );
}
console.log(`
* rhythm written in different note values but consistent — plays correctly.
Reference tempo ${Math.round(scoreScan(reference, reference).referenceTempo)}. Transcriptions saved to ~/bench-*.musicxml.`);
