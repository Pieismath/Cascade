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


// MARK: worker handlers (in-memory KV, real session tokens)

import worker from "../src/index.js";

function memoryKV() {
  const store = new Map();
  return {
    store,
    async get(key) { return store.has(key) ? store.get(key) : null; },
    async put(key, value) { store.set(key, String(value)); },
    async delete(key) { store.delete(key); },
  };
}

function handlerEnv(overrides = {}) {
  return {
    SESSION_SECRET: "handler-secret",
    APPLE_BUNDLE_ID: BUNDLE,
    FREE_SCANS: "2",
    SESSION_DAYS: "60",
    SCAN_KV: memoryKV(),
    ...overrides,
  };
}

const ctx = { waitUntil() {} };
const PAGE = Buffer.from("fake-jpeg-bytes").toString("base64");

async function call(env, method, path, { body, token } = {}) {
  const headers = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  const req = new Request(`https://scan.test${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const res = await worker.fetch(req, env, ctx);
  return { status: res.status, json: await res.json() };
}

/** Provider stub: every Anthropic call returns SCORE (bypasses real network). */
function withProviderStub(env) {
  env.ANTHROPIC_API_KEY = "k";
  globalThis.fetch = async () =>
    new Response(sseBody([
      { type: "content_block_delta", delta: { type: "text_delta", text: SCORE } },
      { type: "message_delta", delta: { stop_reason: "end_turn" } },
    ]), { status: 200 });
  return env;
}

function sseBody(events) {
  return events.map((e) => `data: ${JSON.stringify(e)}\n\n`).join("");
}

await test("DELETE /v1/account removes the usage record", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await issueSessionToken("del-user", env.SESSION_SECRET, 60);
  await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE] } });
  assert.equal(JSON.parse(env.SCAN_KV.store.get("u:del-user")).used, 1);

  const del = await call(env, "DELETE", "/v1/account", { token });
  assert.equal(del.status, 200);
  assert.equal(del.json.deleted, true);
  assert.equal(env.SCAN_KV.store.has("u:del-user"), false);
});

await test("DELETE /v1/account requires a session", async () => {
  const env = handlerEnv();
  const res = await call(env, "DELETE", "/v1/account");
  assert.equal(res.status, 401);
});

await test("recognize without any provider key reports 503 scan_unavailable", async () => {
  const env = handlerEnv();
  const token = await issueSessionToken("u", env.SESSION_SECRET, 60);
  const res = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE] } });
  assert.equal(res.status, 503);
  assert.equal(res.json.error.code, "scan_unavailable");
});

await test("segmented job charges a single scan across requests", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await issueSessionToken("job-user", env.SESSION_SECRET, 60);
  const jobId = "job-abc-123";
  const first = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "A"], jobId } });
  const second = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "B"], jobId, context: "part 2" } });
  const third = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "C"], jobId } });
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(third.status, 200);
  assert.equal(third.json.remainingScans, 1);
  assert.equal(JSON.parse(env.SCAN_KV.store.get("u:job-user")).used, 1);
});

await test("segmented job keeps working after quota is exhausted mid-job", async () => {
  const env = withProviderStub(handlerEnv({ FREE_SCANS: "1" }));
  const token = await issueSessionToken("last-scan", env.SESSION_SECRET, 60);
  const jobId = "job-last";
  const first = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "1"], jobId } });
  assert.equal(first.json.remainingScans, 0);
  const second = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "2"], jobId } });
  assert.equal(second.status, 200, "later segments of an already-charged job must not be refused");
  const fresh = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "3"], jobId: "job-new" } });
  assert.equal(fresh.status, 402);
});

await test("context changes the cache key", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await issueSessionToken("ctx-user", env.SESSION_SECRET, 60);
  const a = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE], context: "x" } });
  const b = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE], context: "y" } });
  assert.equal(a.json.cached, false);
  assert.equal(b.json.cached, false);
});

console.log(`\n${passed} tests passed${process.exitCode ? " (with failures)" : ""}`);
