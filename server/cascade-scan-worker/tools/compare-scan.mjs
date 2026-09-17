#!/usr/bin/env node
// Scores a scan against a known-correct MusicXML file, so "is this any good?"
// has a number behind it instead of a vibe.
//
//   node tools/compare-scan.mjs scan-out.musicxml ../../Resources/FurEliseOpening.musicxml

import { readFile } from "node:fs/promises";
import { basename } from "node:path";
import { scoreScan, pct } from "./score.mjs";

const [scanPath, referencePath] = process.argv.slice(2);
if (!scanPath || !referencePath) {
  console.error("usage: node tools/compare-scan.mjs <scan.musicxml> <reference.musicxml>");
  process.exit(1);
}

const result = scoreScan(await readFile(scanPath, "utf8"), await readFile(referencePath, "utf8"));

const rhythmNote = result.rhythmExact >= result.rhythmSteady - 0.001
  ? ""
  : `\n                (${pct(result.rhythmSteady)} are consistently ${result.beatRatio.toFixed(2)}× the reference — same music, different note values)`;

console.log(`
${basename(scanPath)} vs ${basename(referencePath)}

measures        ${result.scanMeasures} scanned vs ${result.referenceMeasures} expected
notes found     ${pct(result.pitchAccuracy)} of the right pitches (${result.matchedNotes}/${result.wantedNotes})
perfect bars    ${pct(result.perfectBars)} (${result.exactMeasures}/${result.comparedMeasures} note-for-note)
rhythm intact   ${pct(result.rhythmExact)} (${result.comparedMeasures} bars compared)${rhythmNote}
tempo           ${result.tempo || "none"} vs ${Math.round(result.referenceTempo) || "none"}
${result.problems.length ? "\nfirst problems:\n" + result.problems.join("\n") : "\nno differences found"}

Rough reading: above ~95% pitches and ~90% perfect bars plays convincingly;
below ~80% the video will sound wrong to anyone who knows the piece.`);
