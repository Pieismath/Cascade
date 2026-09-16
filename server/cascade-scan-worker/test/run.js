// Offline test suite for the cascade-scan worker: token verification, session
// round-trips, MusicXML extraction, SSE parsing, provider fallback routing.
// Run with: node test/run.js

import assert from "node:assert/strict";
import {
  verifyAppleIdentityToken,
  issueSessionToken,
  verifySessionToken,
  bytesToB64url,
  AuthError,
} from "../src/auth.js";
import {
  extractMusicXML,
  looksLikeMusicXML,
  sseEvents,
  recognize,
  ProviderError,
} from "../src/providers.js";

let passed = 0;
async function test(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ok  ${name}`);
  } catch (err) {
    console.error(`FAIL  ${name}\n      ${err.message}`);
    process.exitCode = 1;
  }
}

// MARK: helpers to forge Apple-style tokens with our own RSA key

const { publicKey, privateKey } = await crypto.subtle.generateKey(
  { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
  true,
  ["sign", "verify"]
);
const jwk = await crypto.subtle.exportKey("jwk", publicKey);
const KID = "test-key-1";
const BUNDLE = "jhfang.MyPianoInstructor2";

const fakeAppleFetch = async (url) => {
  assert.equal(url, "https://appleid.apple.com/auth/keys");
  return new Response(JSON.stringify({ keys: [{ ...jwk, kid: KID, use: "sig", alg: "RS256" }] }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
};

async function forgeToken(payloadOverrides = {}, kid = KID) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", kid, typ: "JWT" };
  const payload = {
    iss: "https://appleid.apple.com",
    aud: BUNDLE,
    sub: "001234.abcdef.5678",
    exp: now + 600,
    iat: now,
    ...payloadOverrides,
  };
  const enc = (o) => bytesToB64url(new TextEncoder().encode(JSON.stringify(o)));
  const signingInput = `${enc(header)}.${enc(payload)}`;
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(signingInput)
  );
  return `${signingInput}.${bytesToB64url(new Uint8Array(sig))}`;
}

// MARK: Apple identity token verification

await test("valid Apple token verifies and returns sub", async () => {
  const token = await forgeToken();
  const payload = await verifyAppleIdentityToken(token, BUNDLE, fakeAppleFetch);
  assert.equal(payload.sub, "001234.abcdef.5678");
});

await test("tampered payload is rejected", async () => {
  const token = await forgeToken();
  const parts = token.split(".");
  const tampered = JSON.parse(new TextDecoder().decode(Buffer.from(parts[1], "base64url")));
  tampered.sub = "attacker";
  parts[1] = bytesToB64url(new TextEncoder().encode(JSON.stringify(tampered)));
  await assert.rejects(
    verifyAppleIdentityToken(parts.join("."), BUNDLE, fakeAppleFetch),
    AuthError
  );
});

await test("wrong audience is rejected", async () => {
  const token = await forgeToken({ aud: "com.other.app" });
  await assert.rejects(verifyAppleIdentityToken(token, BUNDLE, fakeAppleFetch), AuthError);
});

await test("expired token is rejected", async () => {
  const token = await forgeToken({ exp: Math.floor(Date.now() / 1000) - 3600 });
  await assert.rejects(verifyAppleIdentityToken(token, BUNDLE, fakeAppleFetch), AuthError);
});

await test("unknown key id is rejected", async () => {
  const token = await forgeToken({}, "unknown-kid");
  await assert.rejects(verifyAppleIdentityToken(token, BUNDLE, fakeAppleFetch), AuthError);
});

// MARK: session tokens

await test("session token round-trips", async () => {
  const token = await issueSessionToken("user-1", "secret-A", 30);
  const payload = await verifySessionToken(token, "secret-A");
  assert.equal(payload.sub, "user-1");
});

await test("session token with wrong secret is rejected", async () => {
  const token = await issueSessionToken("user-1", "secret-A", 30);
  await assert.rejects(verifySessionToken(token, "secret-B"), AuthError);
});

await test("expired session token is rejected", async () => {
  const token = await issueSessionToken("user-1", "secret-A", -1);
  await assert.rejects(verifySessionToken(token, "secret-A"), AuthError);
});

// MARK: MusicXML extraction

const SCORE = `<?xml version="1.0"?>\n<score-partwise version="4.0"><part id="P1"><measure number="1"><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note></measure></part></score-partwise>`;

await test("extractMusicXML passes clean documents through", () => {
  assert.equal(extractMusicXML(SCORE), SCORE);
});

await test("extractMusicXML strips markdown fences and prose", () => {
  const wrapped = "Here is the transcription:\n```xml\n" + SCORE + "\n```\nLet me know!";
  assert.equal(extractMusicXML(wrapped), SCORE);
});

await test("extractMusicXML trims prose without fences", () => {
  const wrapped = "Sure! " + SCORE + " Hope this helps.";
  assert.equal(extractMusicXML(wrapped), SCORE);
});

await test("looksLikeMusicXML accepts scores and rejects prose", () => {
  assert.equal(looksLikeMusicXML(SCORE), true);
  assert.equal(looksLikeMusicXML("I could not read the image, sorry."), false);
});

// MARK: SSE parsing

await test("sseEvents accumulates text deltas across chunk boundaries", async () => {
  const events = [
    `data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"<score-"}}\n\n`,
    `data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"partwise>"}}\n\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n`,
  ];
  const body = new ReadableStream({
    start(controller) {
      const encoder = new TextEncoder();
      // Split mid-line to prove buffering works
      const raw = events.join("");
      controller.enqueue(encoder.encode(raw.slice(0, 37)));
      controller.enqueue(encoder.encode(raw.slice(37)));
      controller.close();
    },
  });
  let text = "";
  let stop = null;
  for await (const e of sseEvents(body)) {
    if (e.type === "content_block_delta") text += e.delta.text;
    if (e.type === "message_delta") stop = e.delta.stop_reason;
  }
  assert.equal(text, "<score-partwise>");
  assert.equal(stop, "end_turn");
});

// MARK: provider routing

function sseResponse(text, stopReason = "end_turn") {
  const chunks = [
    `data: {"type":"content_block_delta","delta":{"type":"text_delta","text":${JSON.stringify(text)}}}\n\n`,
    `data: {"type":"message_delta","delta":{"stop_reason":"${stopReason}"}}\n\n`,
  ].join("");
  return new Response(chunks, { status: 200 });
}

const ENV = {
  ANTHROPIC_API_KEY: "k",
  GEMINI_API_KEY: "g",
  ANTHROPIC_MODEL: "claude-sonnet-5",
  ANTHROPIC_MODEL_HIGH: "claude-fable-5",
  GEMINI_MODEL: "gemini-2.5-flash",
};

await test("recognize uses anthropic when it succeeds", async () => {
  const fetcher = async (url) => {
    assert.ok(String(url).includes("anthropic.com"));
    return sseResponse(SCORE);
  };
  const result = await recognize(ENV, ["cGFnZQ=="], "standard", fetcher);
  assert.equal(result.provider, "anthropic/claude-sonnet-5");
  assert.equal(result.musicXML, SCORE);
});

await test("recognize escalates model for high quality", async () => {
  let requestedModel;
  const fetcher = async (url, init) => {
    requestedModel = JSON.parse(init.body).model;
    return sseResponse(SCORE);
  };
  await recognize(ENV, ["cGFnZQ=="], "high", fetcher);
  assert.equal(requestedModel, "claude-fable-5");
});

await test("recognize falls back to gemini on retryable anthropic failure", async () => {
  const fetcher = async (url) => {
    if (String(url).includes("anthropic.com")) {
      return new Response(JSON.stringify({ error: { message: "overloaded" } }), { status: 529 });
    }
    assert.ok(String(url).includes("generativelanguage.googleapis.com"));
    return new Response(
      JSON.stringify({ candidates: [{ content: { parts: [{ text: SCORE }] }, finishReason: "STOP" }] }),
      { status: 200 }
    );
  };
  const result = await recognize(ENV, ["cGFnZQ=="], "standard", fetcher);
  assert.equal(result.provider, "gemini/gemini-2.5-flash");
  assert.equal(result.musicXML, SCORE);
});

await test("gemini-only env runs entirely on gemini (free-tier mode)", async () => {
  const geminiOnly = { ...ENV, ANTHROPIC_API_KEY: undefined };
  const fetcher = async (url) => {
    assert.ok(String(url).includes("generativelanguage.googleapis.com"), "must not call anthropic");
    return new Response(
      JSON.stringify({ candidates: [{ content: { parts: [{ text: SCORE }] }, finishReason: "STOP" }] }),
      { status: 200 }
    );
  };
  const result = await recognize(geminiOnly, ["cGFnZQ=="], "standard", fetcher);
  assert.equal(result.provider, "gemini/gemini-2.5-flash");
  assert.equal(result.musicXML, SCORE);
});

await test("recognize does not fall back on non-retryable errors", async () => {
  const fetcher = async () =>
    new Response(JSON.stringify({ error: { message: "bad key" } }), { status: 401 });
  await assert.rejects(recognize(ENV, ["cGFnZQ=="], "standard", fetcher), ProviderError);
});

await test("truncated output surfaces as truncated error", async () => {
  const fetcher = async () => sseResponse("<score-partwise>partial", "max_tokens");
  await assert.rejects(
    recognize({ ...ENV, GEMINI_API_KEY: undefined }, ["cGFnZQ=="], "standard", fetcher),
    (err) => err instanceof ProviderError && err.truncated
  );
});

console.log(`\n${passed} tests passed${process.exitCode ? " (with failures)" : ""}`);
