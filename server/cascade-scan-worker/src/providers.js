// Recognition providers. Anthropic (Claude vision) is primary; Gemini is the
// optional fallback for outages/rate limits. Both are prompted to emit the
// MusicXML subset the iOS app's parser understands, and the raw reply passes
// through the same defensive extraction the app used when it called
// Anthropic directly.

export class ProviderError extends Error {
  constructor(message, { retryable = false, truncated = false } = {}) {
    super(message);
    this.retryable = retryable;
    this.truncated = truncated;
  }
}

const MAX_OUTPUT_TOKENS = 24000;

// MARK: Prompts (kept in lockstep with the app's original prompt)

export const SYSTEM_PROMPT =
  "You are an expert music engraver who transcribes piano sheet music images into MusicXML with perfect fidelity. You read key signatures, time signatures, clefs, accidentals, ties, dots, tuplets, dynamics, tempo markings, and pedal marks accurately, and you keep both staves rhythmically aligned. Your entire reply is always exactly one complete MusicXML document — no markdown fences, no commentary before or after.";

export function transcriptionRequest(pageCount, context = "") {
  const pages =
    pageCount === 1 ? "this image" : `these ${pageCount} images (in reading order)`;
  const extra = context && context.trim() ? `\n\nAdditional context for this request:\n${context.trim()}\n` : "";
  return `Transcribe the piano music in ${pages} into a single continuous MusicXML document.${extra}

Format requirements — the consuming app reads a specific MusicXML subset:
- \`score-partwise\` with exactly one part (id "P1") for piano.
- Two staves: right hand on staff 1 with voice 1, left hand on staff 2 with voice 5. Every note carries <voice> and <staff>. Use <backup> to return to the start of the measure for the left hand.
- Choose one <divisions> value for the whole piece that expresses every rhythm you see, including dots and tuplets (24 works for most music; use 480 if there are complex tuplets). Every <duration> must be a whole number.
- Emit <sound tempo="N"/> in the first measure (from the printed tempo/metronome marking, or a musically sensible value for the style if none is printed). Add further <sound tempo> elements only where the score changes tempo.
- Spell sounding pitches with <step>, <octave>, and <alter> (apply the key signature and accidentals; use <alter>1</alter> for sharps, -1 for flats).
- Chords: subsequent chord tones carry <chord/>. Ties between same pitches use <tie type="start"/> and <tie type="stop"/>. Rests use <rest/> with a duration. Grace notes use <grace/> and no duration.
- Pedal markings become <direction><direction-type><pedal type="start"/></direction-type></direction> and type "stop" where released.
- Write out repeats literally: unfold repeat barlines, volta endings, D.C./D.S. instructions into the full played-through sequence.
- If a detail is smudged or ambiguous, choose the most musically plausible reading and continue — never insert comments or placeholders.

Reply with only the MusicXML document.`;
}

// MARK: Output cleanup (port of the app's extractMusicXML)

export function extractMusicXML(text) {
  let result = String(text).trim();

  const fenceStart = result.indexOf("```");
  if (fenceStart !== -1) {
    const afterFence = result.slice(fenceStart + 3);
    const fenceEnd = afterFence.indexOf("```");
    if (fenceEnd !== -1) {
      let inner = afterFence.slice(0, fenceEnd);
      if (inner.startsWith("xml")) inner = inner.slice(3);
      result = inner.trim();
    }
  }

  const xmlStart = result.indexOf("<?xml");
  const scoreStart = result.indexOf("<score-partwise");
  const start = xmlStart !== -1 ? xmlStart : scoreStart;
  if (start > 0) result = result.slice(start);

  const end = result.lastIndexOf("</score-partwise>");
  if (end !== -1) result = result.slice(0, end + "</score-partwise>".length);

  return result;
}

/** Cheap server-side sanity check; the app re-validates with its real parser. */
export function looksLikeMusicXML(text) {
  return (
    typeof text === "string" &&
    text.includes("<score-partwise") &&
    text.includes("</score-partwise>") &&
    text.includes("<note")
  );
}

// MARK: Anthropic (primary, streaming)

/**
 * Calls the Anthropic Messages API with SSE streaming and accumulates the
 * text. Streaming keeps bytes flowing so long transcriptions don't trip idle
 * timeouts between the worker and the API.
 */
export async function callAnthropic(env, pages, model, fetcher = fetch, context = "") {
  const content = pages.map((b64) => ({
    type: "image",
    source: { type: "base64", media_type: "image/jpeg", data: b64 },
  }));
  content.push({ type: "text", text: transcriptionRequest(pages.length, context) });

  const res = await fetcher("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: MAX_OUTPUT_TOKENS,
      stream: true,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content }],
    }),
  });

  if (!res.ok) {
    const detail = await safeErrorMessage(res);
    const retryable = res.status === 429 || res.status >= 500 || res.status === 529;
    throw new ProviderError(`anthropic ${res.status}: ${detail}`, { retryable });
  }

  let text = "";
  let stopReason = null;
  for await (const event of sseEvents(res.body)) {
    if (event.type === "content_block_delta" && event.delta?.type === "text_delta") {
      text += event.delta.text;
    } else if (event.type === "message_delta" && event.delta?.stop_reason) {
      stopReason = event.delta.stop_reason;
    } else if (event.type === "error") {
      throw new ProviderError(`anthropic stream error: ${event.error?.message ?? "unknown"}`, {
        retryable: true,
      });
    }
  }

  if (stopReason === "max_tokens") {
    throw new ProviderError("output truncated", { truncated: true });
  }
  return extractMusicXML(text);
}

/** Minimal SSE parser: yields each `data: {...}` JSON object. */
export async function* sseEvents(body) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    let newlineIndex;
    while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, newlineIndex).trimEnd();
      buffer = buffer.slice(newlineIndex + 1);
      if (!line.startsWith("data:")) continue;
      const payload = line.slice(5).trim();
      if (!payload || payload === "[DONE]") continue;
      try {
        yield JSON.parse(payload);
      } catch {
        // Ignore malformed keep-alive lines
      }
    }
  }
}

// MARK: Gemini (fallback)

export async function callGemini(env, pages, fetcher = fetch, context = "") {
  const model = env.GEMINI_MODEL || "gemini-2.5-flash";
  const parts = pages.map((b64) => ({
    inline_data: { mime_type: "image/jpeg", data: b64 },
  }));
  parts.push({ text: transcriptionRequest(pages.length, context) });

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const res = await fetcher(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-goog-api-key": env.GEMINI_API_KEY,
    },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: "user", parts }],
      generationConfig: { maxOutputTokens: MAX_OUTPUT_TOKENS, temperature: 0.2 },
    }),
  });

  if (!res.ok) {
    const detail = await safeErrorMessage(res);
    throw new ProviderError(`gemini ${res.status}: ${detail}`, {
      retryable: res.status === 429 || res.status >= 500,
    });
  }

  const json = await res.json();
  const candidate = json.candidates?.[0];
  const text = (candidate?.content?.parts ?? [])
    .map((p) => p.text ?? "")
    .join("");
  if (candidate?.finishReason === "MAX_TOKENS") {
    throw new ProviderError("output truncated", { truncated: true });
  }
  return extractMusicXML(text);
}

// MARK: Routing

/**
 * Primary/fallback routing:
 * - With an Anthropic key: quality "standard" → ANTHROPIC_MODEL; "high" →
 *   ANTHROPIC_MODEL_HIGH (the app escalates when a result fails its parser),
 *   and Gemini covers retryable Anthropic failures when configured.
 * - With only a Gemini key (free-tier mode): Gemini handles everything.
 */
export async function recognize(env, pages, quality, fetcher = fetch, context = "") {
  if (!env.ANTHROPIC_API_KEY && env.GEMINI_API_KEY) {
    const musicXML = await callGemini(env, pages, fetcher, context);
    return { musicXML, provider: `gemini/${env.GEMINI_MODEL || "gemini-2.5-flash"}` };
  }

  const model =
    quality === "high"
      ? env.ANTHROPIC_MODEL_HIGH || "claude-fable-5"
      : env.ANTHROPIC_MODEL || "claude-sonnet-5";

  let primaryError;
  try {
    const musicXML = await callAnthropic(env, pages, model, fetcher, context);
    return { musicXML, provider: `anthropic/${model}` };
  } catch (err) {
    primaryError = err;
  }

  const canFallback =
    env.GEMINI_API_KEY &&
    primaryError instanceof ProviderError &&
    primaryError.retryable;

  if (canFallback) {
    const musicXML = await callGemini(env, pages, fetcher, context);
    return { musicXML, provider: `gemini/${env.GEMINI_MODEL || "gemini-2.5-flash"}` };
  }

  throw primaryError;
}

async function safeErrorMessage(res) {
  try {
    const json = await res.json();
    return json.error?.message ?? JSON.stringify(json).slice(0, 200);
  } catch {
    return "no details";
  }
}
