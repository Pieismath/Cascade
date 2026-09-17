#!/usr/bin/env node
// Scores a scan against a known-correct MusicXML file, so "is this any good?"
// has a number behind it instead of a vibe.
//
//   node tools/compare-scan.mjs scan-out.musicxml ../../Resources/FurEliseOpening.musicxml
//
// Compares measure by measure: which pitches are there (ignoring how they're
// spelled or ordered within the measure) and whether the measure holds the
// right number of beats.

import { readFile } from "node:fs/promises";
import { basename } from "node:path";

const [scanPath, referencePath] = process.argv.slice(2);
if (!scanPath || !referencePath) {
  console.error("usage: node tools/compare-scan.mjs <scan.musicxml> <reference.musicxml>");
  process.exit(1);
}

const STEPS = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

function parseScore(xml) {
  const divisions = Number(xml.match(/<divisions>(\d+)<\/divisions>/)?.[1] ?? 1) || 1;
  const measures = [];
  const measureRe = /<measure\b[^>]*>([\s\S]*?)<\/measure>/g;
  let match;
  while ((match = measureRe.exec(xml))) {
    const body = match[1];
    const notes = [];
    const noteRe = /<note\b[^>]*>([\s\S]*?)<\/note>/g;
    let noteMatch;
    while ((noteMatch = noteRe.exec(body))) {
      const note = noteMatch[1];
      const step = note.match(/<step>([A-G])<\/step>/)?.[1];
      const octave = Number(note.match(/<octave>(-?\d+)<\/octave>/)?.[1] ?? NaN);
      const alter = Number(note.match(/<alter>(-?\d+)<\/alter>/)?.[1] ?? 0);
      notes.push({
        rest: /<rest\b/.test(note),
        chord: /<chord\s*\/>/.test(note),
        grace: /<grace\b/.test(note),
        midi: step && Number.isFinite(octave) ? (octave + 1) * 12 + STEPS[step] + alter : null,
        beats: Number(note.match(/<duration>(\d+)<\/duration>/)?.[1] ?? 0) / divisions,
        voice: note.match(/<voice>(\d+)<\/voice>/)?.[1] ?? "1",
      });
    }
    measures.push(notes);
  }
  return { divisions, measures };
}

/** Beats in a measure = the longest voice in it (staves run in parallel). */
function measureBeats(notes) {
  const perVoice = new Map();
  for (const note of notes) {
    if (note.chord || note.grace) continue;
    perVoice.set(note.voice, (perVoice.get(note.voice) ?? 0) + note.beats);
  }
  return Math.max(0, ...perVoice.values());
}

const pitches = (notes) => notes.filter((n) => !n.rest && !n.grace && n.midi != null).map((n) => n.midi).sort((a, b) => a - b);

/** How much of `want` shows up in `got`, counting duplicates. */
function overlap(want, got) {
  const pool = [...got];
  let hits = 0;
  for (const value of want) {
    const at = pool.indexOf(value);
    if (at !== -1) {
      pool.splice(at, 1);
      hits += 1;
    }
  }
  return hits;
}

const scan = parseScore(await readFile(scanPath, "utf8"));
const reference = parseScore(await readFile(referencePath, "utf8"));

const pairs = Math.min(scan.measures.length, reference.measures.length);
let wantedNotes = 0;
let matchedNotes = 0;
let exactMeasures = 0;
let rhythmOk = 0;
const problems = [];

for (let i = 0; i < pairs; i++) {
  const want = pitches(reference.measures[i]);
  const got = pitches(scan.measures[i]);
  const hits = overlap(want, got);
  wantedNotes += want.length;
  matchedNotes += hits;

  const exact = hits === want.length && got.length === want.length;
  if (exact) exactMeasures += 1;

  const wantBeats = measureBeats(reference.measures[i]);
  const gotBeats = measureBeats(scan.measures[i]);
  const sameRhythm = Math.abs(wantBeats - gotBeats) < 0.01;
  if (sameRhythm) rhythmOk += 1;

  if ((!exact || !sameRhythm) && problems.length < 8) {
    problems.push(
      `  measure ${i + 1}: ${hits}/${want.length} pitches` +
        (got.length !== want.length ? ` (got ${got.length})` : "") +
        (sameRhythm ? "" : `, ${gotBeats} beats vs ${wantBeats}`)
    );
  }
}

const pct = (a, b) => (b === 0 ? "—" : `${((a / b) * 100).toFixed(1)}%`);

console.log(`
${basename(scanPath)} vs ${basename(referencePath)}

measures        ${scan.measures.length} scanned vs ${reference.measures.length} expected
notes found     ${pct(matchedNotes, wantedNotes)} of the right pitches (${matchedNotes}/${wantedNotes})
perfect bars    ${pct(exactMeasures, pairs)} (${exactMeasures}/${pairs} note-for-note)
rhythm intact   ${pct(rhythmOk, pairs)} (${rhythmOk}/${pairs} bars hold the right beats)
${problems.length ? "\nfirst problems:\n" + problems.join("\n") : "\nno differences found"}

Rough reading: above ~95% pitches and ~90% perfect bars plays convincingly;
below ~80% the video will sound wrong to anyone who knows the piece.`);
