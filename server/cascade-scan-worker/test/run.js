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
  GEMINI_MODEL: "gemini-3.6-flash",
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
  assert.equal(result.provider, "gemini/gemini-3.6-flash");
  assert.equal(result.musicXML, SCORE);
});

await test("PRIMARY_PROVIDER=gemini routes to gemini first, anthropic covers outages", async () => {
  const geminiFirst = { ...ENV, PRIMARY_PROVIDER: "gemini", GEMINI_MODEL_HIGH: "gemini-3.8-flash" };
  const calls = [];
  const ok = new Response(
    JSON.stringify({ candidates: [{ content: { parts: [{ text: SCORE }] }, finishReason: "STOP" }] }),
    { status: 200 }
  );
  const first = await recognize(geminiFirst, ["cGFnZQ=="], "standard", async (url) => {
    calls.push(String(url));
    return ok.clone();
  });
  assert.equal(first.provider, "gemini/gemini-3.6-flash");
  assert.ok(calls[0].includes("generativelanguage.googleapis.com"));

  const high = await recognize(geminiFirst, ["cGFnZQ=="], "high", async (url) => {
    assert.ok(String(url).includes("gemini-3.8-flash"), "high quality uses the stronger gemini model");
    return ok.clone();
  });
  assert.equal(high.provider, "gemini/gemini-3.8-flash");

  const fellBack = await recognize(geminiFirst, ["cGFnZQ=="], "standard", async (url) => {
    if (String(url).includes("generativelanguage.googleapis.com")) {
      return new Response(JSON.stringify({ error: { message: "quota" } }), { status: 429 });
    }
    return sseResponse(SCORE);
  });
  assert.equal(fellBack.provider, "anthropic/claude-sonnet-5");
});

await test("gemini-only env runs entirely on gemini", async () => {
  const geminiOnly = { ...ENV, ANTHROPIC_API_KEY: undefined };
  const fetcher = async (url) => {
    assert.ok(String(url).includes("generativelanguage.googleapis.com"), "must not call anthropic");
    return new Response(
      JSON.stringify({ candidates: [{ content: { parts: [{ text: SCORE }] }, finishReason: "STOP" }] }),
      { status: 200 }
    );
  };
  const result = await recognize(geminiOnly, ["cGFnZQ=="], "standard", fetcher);
  assert.equal(result.provider, "gemini/gemini-3.6-flash");
  assert.equal(result.musicXML, SCORE);
});

await test("gemini 3 requests keep thinking short; older models get no such field", async () => {
  const ok = () =>
    new Response(
      JSON.stringify({ candidates: [{ content: { parts: [{ text: SCORE }] }, finishReason: "STOP" }] }),
      { status: 200 }
    );

  let body;
  await recognize({ GEMINI_API_KEY: "g", GEMINI_MODEL: "gemini-3.6-flash" }, ["cGFnZQ=="], "standard", async (_url, init) => {
    body = JSON.parse(init.body);
    return ok();
  });
  assert.equal(body.generationConfig.thinking_level, "low", "thinking tokens share the output budget");
  assert.equal(body.generationConfig.maxOutputTokens, 24000);

  await recognize({ GEMINI_API_KEY: "g", GEMINI_MODEL: "gemini-2.5-flash" }, ["cGFnZQ=="], "standard", async (_url, init) => {
    body = JSON.parse(init.body);
    return ok();
  });
  assert.equal(body.generationConfig.thinking_level, undefined);

  await recognize(
    { GEMINI_API_KEY: "g", GEMINI_MODEL: "gemini-3.6-flash", GEMINI_THINKING_LEVEL: "minimal" },
    ["cGFnZQ=="], "standard",
    async (_url, init) => { body = JSON.parse(init.body); return ok(); }
  );
  assert.equal(body.generationConfig.thinking_level, "minimal");
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
import { verifySignedTransaction, PurchaseError, encodeOID, containsOID } from "../src/appstore.js";
import { execSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

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
    FREE_SCANS: "1",
    PAGES_PER_CREDIT: "4",
    MAX_IMAGES_PER_CREDIT: "24",
    MAX_REQUESTS_PER_CREDIT: "6",
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

async function sessionFor(env, sub) {
  return issueSessionToken(sub, env.SESSION_SECRET, 60);
}

await test("DELETE /v1/account removes the usage record", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await sessionFor(env, "del-user");
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
  const token = await sessionFor(env, "u");
  const res = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE] } });
  assert.equal(res.status, 503);
  assert.equal(res.json.error.code, "scan_unavailable");
});

await test("free scan is consumed, then the account is out of scans", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await sessionFor(env, "free-user");
  const first = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "A"] } });
  assert.equal(first.status, 200);
  assert.equal(first.json.remainingScans, 0);
  assert.equal(first.json.freeRemaining, 0);
  const second = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "B"] } });
  assert.equal(second.status, 402);
  assert.equal(second.json.error.code, "insufficient_credits");
});

await test("segmented job charges a single credit across requests", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await sessionFor(env, "job-user");
  const jobId = "job-abc-123";
  const first = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "A"], jobId, pageCount: 2 } });
  const second = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "B"], jobId, pageCount: 2, context: "part 2" } });
  const third = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "C"], jobId, pageCount: 2 } });
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  assert.equal(third.status, 200);
  assert.equal(third.json.remainingScans, 0);
  assert.equal(JSON.parse(env.SCAN_KV.store.get("u:job-user")).used, 1);
});

await test("long scans cost more credits and are refused without them", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await sessionFor(env, "long-user");
  const res = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE], jobId: "long-1", pageCount: 6 } });
  assert.equal(res.status, 402);
  assert.equal(res.json.error.needed, 2);
  assert.equal(res.json.error.remaining, 1);
});

await test("a job cannot exceed its per-credit request cap", async () => {
  const env = withProviderStub(handlerEnv({ MAX_REQUESTS_PER_CREDIT: "2" }));
  const token = await sessionFor(env, "cap-user");
  const jobId = "cap-job";
  assert.equal((await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "1"], jobId } })).status, 200);
  assert.equal((await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "2"], jobId } })).status, 200);
  const third = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "3"], jobId } });
  assert.equal(third.status, 413);
  assert.equal(third.json.error.code, "job_too_large");
});

await test("cache hits cost nothing", async () => {
  const env = withProviderStub(handlerEnv());
  const token = await sessionFor(env, "cache-user");
  const a = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE] } });
  assert.equal(a.json.remainingScans, 0);
  const b = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE] } });
  assert.equal(b.status, 200);
  assert.equal(b.json.cached, true);
});

await test("context changes the cache key", async () => {
  const env = withProviderStub(handlerEnv({ FREE_SCANS: "5" }));
  const token = await sessionFor(env, "ctx-user");
  const a = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE], context: "x" } });
  const b = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE], context: "y" } });
  assert.equal(a.json.cached, false);
  assert.equal(b.json.cached, false);
});

await test("rate limit trips after the configured burst", async () => {
  const env = withProviderStub(handlerEnv({ FREE_SCANS: "50", RATE_LIMIT_PER_MINUTE: "3" }));
  const token = await sessionFor(env, "burst-user");
  for (let i = 0; i < 3; i++) {
    assert.equal((await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + i] } })).status, 200);
  }
  const res = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "x"] } });
  assert.equal(res.status, 429);
});

// MARK: App Store purchases (chain generated with openssl, signed like StoreKit 2)

function pemToDER(pem) {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return new Uint8Array(Buffer.from(b64, "base64"));
}

/** Builds root → intermediate → leaf, mimicking Apple's chain shape and marker OIDs. */
function makeChain({ withMarkers = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "cascade-chain-"));
  const run = (cmd) => execSync(cmd, { cwd: dir, stdio: ["ignore", "pipe", "pipe"] });
  writeFileSync(join(dir, "int.ext"), `basicConstraints=critical,CA:TRUE\n${withMarkers ? "1.2.840.113635.100.6.2.1=ASN1:NULL\n" : ""}`);
  writeFileSync(join(dir, "leaf.ext"), `basicConstraints=CA:FALSE\n${withMarkers ? "1.2.840.113635.100.6.11.1=ASN1:NULL\n" : ""}`);
  run(`openssl ecparam -name secp384r1 -genkey -noout -out root.key`);
  run(`openssl req -x509 -new -key root.key -sha384 -days 30 -subj "/CN=Test Apple Root CA" -out root.pem`);
  run(`openssl ecparam -name secp384r1 -genkey -noout -out int.key`);
  run(`openssl req -new -key int.key -subj "/CN=Test WWDR G6" -out int.csr`);
  run(`openssl x509 -req -in int.csr -CA root.pem -CAkey root.key -CAcreateserial -sha384 -days 30 -extfile int.ext -out int.pem`);
  run(`openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out leaf.key`);
  run(`openssl req -new -key leaf.key -subj "/CN=Test Receipt Signing" -out leaf.csr`);
  run(`openssl x509 -req -in leaf.csr -CA int.pem -CAkey int.key -CAcreateserial -sha256 -days 30 -extfile leaf.ext -out leaf.pem`);
  return {
    root: pemToDER(readFileSync(join(dir, "root.pem"), "utf8")),
    intermediate: pemToDER(readFileSync(join(dir, "int.pem"), "utf8")),
    leaf: pemToDER(readFileSync(join(dir, "leaf.pem"), "utf8")),
    leafKeyPEM: readFileSync(join(dir, "leaf.key"), "utf8"),
  };
}

async function signTransaction(chain, payload, { includeRoot = true } = {}) {
  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDER(chain.leafKeyPEM), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]
  );
  const x5c = [chain.leaf, chain.intermediate, ...(includeRoot ? [chain.root] : [])].map((d) => Buffer.from(d).toString("base64"));
  const enc = (o) => bytesToB64url(new TextEncoder().encode(JSON.stringify(o)));
  const signingInput = `${enc({ alg: "ES256", x5c })}.${enc(payload)}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${bytesToB64url(new Uint8Array(sig))}`;
}

const chain = makeChain();
const otherChain = makeChain();
const basePayload = {
  bundleId: BUNDLE,
  productId: "jhfang.MyPianoInstructor2.scans10",
  transactionId: "2000000123456789",
  originalTransactionId: "2000000123456789",
  quantity: 1,
  type: "Consumable",
  environment: "Sandbox",
  purchaseDate: Date.now(),
  signedDate: Date.now(),
};

await test("encodeOID / containsOID round-trip", () => {
  const der = encodeOID("1.2.840.113635.100.6.11.1");
  assert.deepEqual([...der], [0x06, 0x0a, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x06, 0x0b, 0x01]);
  assert.equal(containsOID(chain.leaf, "1.2.840.113635.100.6.11.1"), true);
  assert.equal(containsOID(chain.intermediate, "1.2.840.113635.100.6.2.1"), true);
  assert.equal(containsOID(chain.root, "1.2.840.113635.100.6.11.1"), false);
});

await test("a properly chained signed transaction verifies", async () => {
  const jws = await signTransaction(chain, basePayload);
  const payload = await verifySignedTransaction(jws, { bundleId: BUNDLE, rootCertDER: chain.root });
  assert.equal(payload.productId, basePayload.productId);
  assert.equal(payload.transactionId, basePayload.transactionId);
});

await test("chain without the root in x5c still verifies against the pinned root", async () => {
  const jws = await signTransaction(chain, basePayload, { includeRoot: false });
  const payload = await verifySignedTransaction(jws, { bundleId: BUNDLE, rootCertDER: chain.root });
  assert.equal(payload.transactionId, basePayload.transactionId);
});

await test("a transaction signed by a foreign chain is rejected", async () => {
  const jws = await signTransaction(otherChain, basePayload);
  await assert.rejects(verifySignedTransaction(jws, { bundleId: BUNDLE, rootCertDER: chain.root }), PurchaseError);
});

await test("a tampered payload is rejected", async () => {
  const jws = await signTransaction(chain, basePayload);
  const parts = jws.split(".");
  parts[1] = bytesToB64url(new TextEncoder().encode(JSON.stringify({ ...basePayload, productId: "jhfang.MyPianoInstructor2.scans25" })));
  await assert.rejects(verifySignedTransaction(parts.join("."), { bundleId: BUNDLE, rootCertDER: chain.root }), PurchaseError);
});

await test("wrong bundle id, Xcode environment, and refunds are rejected", async () => {
  for (const override of [{ bundleId: "com.other" }, { environment: "Xcode" }, { revocationDate: Date.now() }]) {
    const jws = await signTransaction(chain, { ...basePayload, ...override });
    await assert.rejects(verifySignedTransaction(jws, { bundleId: BUNDLE, rootCertDER: chain.root }), PurchaseError);
  }
});

await test("certificates without Apple's marker OIDs are rejected", async () => {
  const plain = makeChain({ withMarkers: false });
  const jws = await signTransaction(plain, basePayload);
  await assert.rejects(verifySignedTransaction(jws, { bundleId: BUNDLE, rootCertDER: plain.root }), PurchaseError);
  const payload = await verifySignedTransaction(jws, { bundleId: BUNDLE, rootCertDER: plain.root, requireMarkerOIDs: false });
  assert.equal(payload.productId, basePayload.productId);
});

await test("POST /v1/purchases/redeem grants credits once per transaction", async () => {
  const env = withProviderStub(handlerEnv({ __TEST_ROOT_CERT: chain.root }));
  const token = await sessionFor(env, "buyer");
  const jws = await signTransaction(chain, basePayload);

  const first = await call(env, "POST", "/v1/purchases/redeem", { token, body: { signedTransaction: jws } });
  assert.equal(first.status, 200);
  assert.equal(first.json.added, 10);
  assert.equal(first.json.credits, 10);
  assert.equal(first.json.remainingScans, 11);

  const again = await call(env, "POST", "/v1/purchases/redeem", { token, body: { signedTransaction: jws } });
  assert.equal(again.json.added, 0);
  assert.equal(again.json.alreadyRedeemed, true);
  assert.equal(again.json.credits, 10);

  // Same transaction from another account: nothing granted.
  const other = await sessionFor(env, "someone-else");
  const replay = await call(env, "POST", "/v1/purchases/redeem", { token: other, body: { signedTransaction: jws } });
  assert.equal(replay.json.added, 0);
  assert.equal(replay.json.credits, 0);

  // Paid credits are spent only after the free one.
  const scan = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE] } });
  assert.equal(scan.json.freeRemaining, 0);
  assert.equal(scan.json.credits, 10);
  const scan2 = await call(env, "POST", "/v1/recognize", { token, body: { pages: [PAGE + "2"] } });
  assert.equal(scan2.json.credits, 9);
});

await test("redeem rejects unknown products and forged transactions", async () => {
  const env = handlerEnv({ __TEST_ROOT_CERT: chain.root });
  const token = await sessionFor(env, "buyer2");
  const unknown = await signTransaction(chain, { ...basePayload, productId: "jhfang.MyPianoInstructor2.nothing", transactionId: "1" });
  assert.equal((await call(env, "POST", "/v1/purchases/redeem", { token, body: { signedTransaction: unknown } })).json.error.code, "unknown_product");
  const forged = await signTransaction(otherChain, { ...basePayload, transactionId: "2" });
  assert.equal((await call(env, "POST", "/v1/purchases/redeem", { token, body: { signedTransaction: forged } })).json.error.code, "invalid_purchase");
});

console.log(`\n${passed} tests passed${process.exitCode ? " (with failures)" : ""}`);
