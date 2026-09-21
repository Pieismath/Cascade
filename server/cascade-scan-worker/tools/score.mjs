// Scoring a transcription against a known-correct MusicXML file. Shared by
// compare-scan.mjs (one result) and bench-scan.mjs (a table of them).

const STEPS = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

export function parseScore(xml, inheritedDivisions = 1) {
  // A continuation part that leaves out <divisions> keeps the previous part's,
  // the same as the app's stitched document would.
  const divisions = Number(xml.match(/<divisions>(\d+)<\/divisions>/)?.[1] ?? inheritedDivisions) || 1;
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

const pitches = (notes) =>
  notes.filter((n) => !n.rest && !n.grace && n.midi != null).map((n) => n.midi).sort((a, b) => a - b);

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

/**
 * Compares measure by measure. Rhythm is judged two ways: `rhythmExact` wants
 * the same beats as the reference, `rhythmSteady` accepts a transcription
 * written in a different note value as long as it's consistent (every measure
 * off by the same factor still plays correctly, just at another notated
 * tempo).
 */
export function scoreScan(scanXml, referenceXml, { expectedMeasures } = {}) {
  // A scan can arrive in several parts (one per request); each keeps its own
  // divisions, so parse them separately and line their measures up end to end.
  const parts = Array.isArray(scanXml) ? scanXml : [scanXml];
  const scan = { measures: [] };
  let divisions = 1;
  for (const part of parts) {
    const parsed = parseScore(part, divisions);
    divisions = parsed.divisions;
    scan.measures.push(...parsed.measures);
  }
  const firstPart = parts[0] ?? "";
  const reference = parseScore(referenceXml);
  // How many bars the pages really hold. Without it we can only compare what
  // came back, which lets a model that skips bars look better than it is.
  const pairs = expectedMeasures
    ? Math.min(expectedMeasures, reference.measures.length)
    : Math.min(scan.measures.length, reference.measures.length);

  let wantedNotes = 0;
  let matchedNotes = 0;
  let exactMeasures = 0;
  let rhythmExact = 0;
  const ratios = [];
  const problems = [];

  for (let i = 0; i < pairs; i++) {
    const want = pitches(reference.measures[i]);
    const got = pitches(scan.measures[i] ?? []);
    const hits = overlap(want, got);
    wantedNotes += want.length;
    matchedNotes += hits;

    const exact = hits === want.length && got.length === want.length;
    if (exact) exactMeasures += 1;

    const wantBeats = measureBeats(reference.measures[i]);
    const gotBeats = measureBeats(scan.measures[i] ?? []);
    const sameRhythm = Math.abs(wantBeats - gotBeats) < 0.01;
    if (sameRhythm) rhythmExact += 1;
    if (wantBeats > 0 && gotBeats > 0) ratios.push(gotBeats / wantBeats);

    if (i >= scan.measures.length) {
      if (problems.length < 8) problems.push(`  measure ${i + 1}: missing`);
      continue;
    }
    if ((!exact || !sameRhythm) && problems.length < 8) {
      problems.push(
        `  measure ${i + 1}: ${hits}/${want.length} pitches` +
          (got.length !== want.length ? ` (got ${got.length})` : "") +
          (sameRhythm ? "" : `, ${gotBeats} beats vs ${wantBeats}`)
      );
    }
  }

  // Consistent = every measure is off by the same factor.
  const typical = ratios.length ? ratios.slice().sort((a, b) => a - b)[Math.floor(ratios.length / 2)] : 1;
  const rhythmSteady = ratios.filter((r) => Math.abs(r - typical) < 0.02).length;

  return {
    scanMeasures: scan.measures.length,
    missingMeasures: Math.max(0, pairs - scan.measures.length),
    referenceMeasures: reference.measures.length,
    comparedMeasures: pairs,
    wantedNotes,
    matchedNotes,
    pitchAccuracy: wantedNotes ? matchedNotes / wantedNotes : 0,
    exactMeasures,
    perfectBars: pairs ? exactMeasures / pairs : 0,
    rhythmExact: pairs ? rhythmExact / pairs : 0,
    rhythmSteady: pairs ? rhythmSteady / pairs : 0,
    beatRatio: typical,
    tempo: Number(firstPart.match(/<sound tempo="([\d.]+)"/)?.[1] ?? 0),
    referenceTempo: Number(referenceXml.match(/<sound tempo="([\d.]+)"/)?.[1] ?? 0),
    problems,
  };
}

export const pct = (value) => `${(value * 100).toFixed(1)}%`;
