// Recognition providers. Either can be primary (PRIMARY_PROVIDER); the other
// covers retryable failures when its key is configured. Both are prompted to emit the
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
// Claude thinks by default on Sonnet 5 / Opus 5 and thinking shares
// max_tokens with the answer; streaming allows a large ceiling without timeouts.
const ANTHROPIC_MAX_OUTPUT_TOKENS = 64000;
// Gemini 3 counts its thinking against the same budget as the answer and
// allows 64k, so give it room; a truncated reply wastes the whole request.
const GEMINI_MAX_OUTPUT_TOKENS = 48000;

// Google retires model ids fairly often; these are the defaults as of
// September 2026 and both are reachable on the free tier.
const DEFAULT_GEMINI_MODEL = "gemini-3.6-flash";
const DEFAULT_GEMINI_MODEL_HIGH = "gemini-3.8-flash";

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
- Use <divisions>24</divisions> (a quarter note = 24) unless the music needs finer resolution; then use 480. Every <duration> must be a whole number: eighth = 12, sixteenth = 6, dotted eighth = 18, eighth triplet = 8.
- Copy the printed time signature exactly, and make every measure add up to it: in 3/8 each measure holds three eighths (duration 36 per voice at divisions 24), in 4/4 it holds four quarters (96). Check each measure against this before moving on.
- Emit <sound tempo="N"/> in the first measure (from the printed tempo/metronome marking, or a musically sensible value for the style if none is printed). N is always quarter notes per minute, whatever the time signature: in 3/8 or 6/8, eighth = 120 is tempo 60. Add further <sound tempo> elements only where the score changes tempo.
- Spell sounding pitches with <step>, <octave>, and <alter> (apply the key signature and accidentals; use <alter>1</alter> for sharps, -1 for flats).
- Chords: subsequent chord tones carry <chord/>. Ties between same pitches use <tie type="start"/> and <tie type="stop"/>. Rests use <rest/> with a duration. Grace notes use <grace/> and no duration.
- Pedal markings become <direction><direction-type><pedal type="start"/></direction-type></direction> and type "stop" where released.
- Write out repeats literally: unfold repeat barlines, volta endings, D.C./D.S. instructions into the full played-through sequence.
- Transcribe every notehead you can see, in both staves, including inner voices and repeated notes. Do not simplify, summarise, or skip anything, and do not invent notes that aren't printed.
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

  const headers = {
    "content-type": "application/json",
    "x-api-key": env.ANTHROPIC_API_KEY,
    "anthropic-version": "2023-06-01",
  };
  const body = {
    model,
    max_tokens: ANTHROPIC_MAX_OUTPUT_TOKENS,
    stream: true,
    thinking: { type: "adaptive" },
    output_config: { effort: env.ANTHROPIC_EFFORT || "high" },
    system: SYSTEM_PROMPT,
    messages: [{ role: "user", content }],
  };
  // Opus 5's safety classifiers can decline a request; let the API re-run it
  // on Anthropic's recommended fallback instead of failing the scan.
  if (/^claude-opus-5/.test(model)) {
    headers["anthropic-beta"] = "server-side-fallback-2026-07-01";
    body.fallbacks = "default";
  }

  const res = await fetcher("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
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
  if (stopReason === "refusal") {
    // Any partial output is discarded; the other provider can try.
    throw new ProviderError("anthropic declined the request", { retryable: true });
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

export async function callGemini(env, pages, model = null, fetcher = fetch, context = "") {
  model = model || env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL;
  const parts = pages.map((b64) => ({
    inline_data: { mime_type: "image/jpeg", data: b64 },
  }));
  parts.push({ text: transcriptionRequest(pages.length, context) });

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const send = (generationConfig) =>
    fetcher(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": env.GEMINI_API_KEY,
      },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{ role: "user", parts }],
        generationConfig,
      }),
    });

  const config = geminiGenerationConfig(env, model);
  let res = await send(config);
  let detail = res.ok ? null : await safeErrorMessage(res);

  // Google moves the thinking knob between API generations (thinkingBudget →
  // thinkingConfig.thinkingLevel → thinking_level). If this model won't take
  // ours, send the request again without it rather than failing the scan.
  if (!res.ok && res.status === 400 && config.thinkingConfig &&
      /unknown name|cannot find field|thinking/i.test(detail ?? "")) {
    const { thinkingConfig, ...withoutThinking } = config;
    res = await send(withoutThinking);
    detail = res.ok ? null : await safeErrorMessage(res);
  }

  if (!res.ok) {
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

/**
 * Gemini 3 thinks by default and those tokens come out of the same budget as
 * the answer, which truncates long scores. Keep thinking brief; 2.x models
 * don't accept the field at all.
 */
function geminiGenerationConfig(env, model) {
  const config = { maxOutputTokens: GEMINI_MAX_OUTPUT_TOKENS, temperature: 0.2 };
  if (/^gemini-[3-9]/.test(model)) {
    config.thinkingConfig = { thinkingLevel: env.GEMINI_THINKING_LEVEL || "low" };
  }
  return config;
}

// MARK: Routing

/**
 * Provider order: PRIMARY_PROVIDER first when its key is set, otherwise
 * Anthropic then Gemini. Whichever provider is second covers retryable
 * failures (rate limits, overload, 5xx) from the first.
 */
export function providerOrder(env) {
  const available = { anthropic: !!env.ANTHROPIC_API_KEY, gemini: !!env.GEMINI_API_KEY };
  const preferred = String(env.PRIMARY_PROVIDER || "").toLowerCase();
  const order = [];
  if (available[preferred]) order.push(preferred);
  for (const name of ["anthropic", "gemini"]) {
    if (available[name] && !order.includes(name)) order.push(name);
  }
  return order;
}

/**
 * Quality "high" is the app's escalation retry: the stronger model of
 * whichever provider is answering.
 */
function modelFor(env, provider, quality) {
  if (provider === "anthropic") {
    return quality === "high"
      ? env.ANTHROPIC_MODEL_HIGH || "claude-fable-5"
      : env.ANTHROPIC_MODEL || "claude-sonnet-5";
  }
  return quality === "high"
    ? env.GEMINI_MODEL_HIGH || DEFAULT_GEMINI_MODEL_HIGH
    : env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL;
}

export async function recognize(env, pages, quality, fetcher = fetch, context = "") {
  const order = providerOrder(env);
  if (order.length === 0) throw new ProviderError("no provider key configured");

  let firstError;
  for (let i = 0; i < order.length; i++) {
    const provider = order[i];
    const model = modelFor(env, provider, quality);
    try {
      const musicXML = provider === "anthropic"
        ? await callAnthropic(env, pages, model, fetcher, context)
        : await callGemini(env, pages, model, fetcher, context);
      return { musicXML, provider: `${provider}/${model}` };
    } catch (err) {
      if (!firstError) firstError = err;
      const retryable = err instanceof ProviderError && err.retryable;
      if (!retryable || i + 1 === order.length) throw firstError;
    }
  }
  throw firstError;
}

async function safeErrorMessage(res) {
  try {
    const json = await res.json();
    return json.error?.message ?? JSON.stringify(json).slice(0, 200);
  } catch {
    return "no details";
  }
}
