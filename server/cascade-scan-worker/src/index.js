// cascade-scan — the backend for Cascade's sheet-music scanning.
//
// Endpoints (all JSON):
//   POST   /v1/auth/apple        {identityToken}          → {sessionToken, ...balance}
//   GET    /v1/me                Bearer session           → balance
//   DELETE /v1/account           Bearer session           → {deleted: true}
//   POST   /v1/purchases/redeem  Bearer session,
//                                {signedTransaction}      → {added, ...balance}
//   POST   /v1/recognize         Bearer session,
//                                {pages:[b64jpeg], pageCount?, quality?, context?, jobId?}
//                                                         → {musicXML, cached, ...balance}
//
// Money model. Every scan is a "job" that costs ceil(pageCount / PAGES_PER_CREDIT)
// credits. Each Apple ID gets FREE_SCANS credits for free; beyond that credits
// come from App Store consumable packs, which are only granted after Apple's
// signature on the transaction verifies (see appstore.js). A job is charged
// once, on its first successful request; later requests of the same job ride
// free but are capped in images and requests per credit, so a misbehaving
// client cannot turn one credit into unbounded provider spend.
//
// The app's provider keys never leave this worker. Identical page sets are
// cached by content hash; cache hits consume nothing.

import {
  AuthError,
  verifyAppleIdentityToken,
  issueSessionToken,
  verifySessionToken,
} from "./auth.js";
import { ProviderError, recognize, looksLikeMusicXML } from "./providers.js";
import { PurchaseError, verifySignedTransaction } from "./appstore.js";

const MAX_PAGES_PER_REQUEST = 8;
const MAX_PAGE_B64_CHARS = 2_800_000; // ~2MB of JPEG per image
const MAX_CONTEXT_CHARS = 4000;
const CACHE_TTL_SECONDS = 60 * 86400;
const JOB_TTL_SECONDS = 2 * 3600;
const RATE_WINDOW_SECONDS = 60;

const DEFAULT_PRODUCTS = {
  "jhfang.MyPianoInstructor2.scans10": 10,
  "jhfang.MyPianoInstructor2.scans25": 25,
};

class ConfigError extends Error {}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/") {
        return json(200, { service: "cascade-scan", ok: true });
      }
      if (request.method === "POST" && url.pathname === "/v1/auth/apple") {
        return await handleAppleAuth(request, env);
      }
      if (request.method === "GET" && url.pathname === "/v1/me") {
        return await handleMe(request, env);
      }
      if (request.method === "DELETE" && url.pathname === "/v1/account") {
        return await handleDeleteAccount(request, env);
      }
      if (request.method === "POST" && url.pathname === "/v1/purchases/redeem") {
        return await handleRedeem(request, env);
      }
      if (request.method === "POST" && url.pathname === "/v1/recognize") {
        return await handleRecognize(request, env, ctx);
      }
      return error(404, "not_found", "No such endpoint.");
    } catch (err) {
      if (err instanceof AuthError) {
        return error(401, "unauthorized", err.message);
      }
      if (err instanceof ConfigError) {
        console.error("configuration:", err.message);
        return error(503, "scan_unavailable", "Scanning is temporarily unavailable. Please try again later.");
      }
      console.error("unhandled:", err.stack ?? err);
      return error(500, "internal", "Something went wrong on the server.");
    }
  },
};

// MARK: - Handlers

async function handleAppleAuth(request, env) {
  requireSessionConfig(env);
  const body = await readJSON(request);
  if (!body?.identityToken) {
    return error(400, "bad_request", "identityToken is required.");
  }

  const payload = await verifyAppleIdentityToken(body.identityToken, env.APPLE_BUNDLE_ID);
  const account = await loadAccount(env, payload.sub, { createIfMissing: true });
  const sessionToken = await issueSessionToken(
    payload.sub,
    env.SESSION_SECRET,
    intVar(env.SESSION_DAYS, 60)
  );

  return json(200, { sessionToken, ...balance(env, account) });
}

async function handleMe(request, env) {
  requireSessionConfig(env);
  const session = await requireSession(request, env);
  const account = await loadAccount(env, session.sub, { createIfMissing: true });
  return json(200, balance(env, account));
}

/// App Store guideline 5.1.1(v): accounts must be deletable in-app. We hold
/// nothing but the usage counter and credit balance, so deletion is a single
/// KV removal. Unused paid credits are forfeited; the app says so before asking
/// for confirmation.
async function handleDeleteAccount(request, env) {
  requireSessionConfig(env);
  const session = await requireSession(request, env);
  await env.SCAN_KV.delete("u:" + session.sub);
  return json(200, { deleted: true });
}

/// Grants credits for an App Store consumable. Idempotent per transaction id,
/// so retrying after a network failure never double-credits, and a transaction
/// can't be replayed into a second account.
async function handleRedeem(request, env) {
  requireSessionConfig(env);
  const session = await requireSession(request, env);
  const body = await readJSON(request);
  if (typeof body?.signedTransaction !== "string") {
    return error(400, "bad_request", "signedTransaction is required.");
  }

  let payload;
  try {
    payload = await verifySignedTransaction(body.signedTransaction, {
      bundleId: env.APPLE_BUNDLE_ID,
      rootCertDER: env.__TEST_ROOT_CERT ?? undefined,
      requireMarkerOIDs: env.__TEST_ROOT_CERT ? false : true,
    });
  } catch (err) {
    if (err instanceof PurchaseError) {
      console.error("purchase rejected:", err.message);
      return error(400, "invalid_purchase", "This purchase could not be verified with Apple.");
    }
    throw err;
  }

  const products = productTable(env);
  const perUnit = products[payload.productId];
  if (!perUnit) {
    return error(400, "unknown_product", "This product doesn't add scans.");
  }

  const txKey = "t:" + payload.transactionId;
  const account = await loadAccount(env, session.sub, { createIfMissing: true });
  const existing = await env.SCAN_KV.get(txKey);
  if (existing) {
    // Already redeemed (by this or another account) — never credit twice.
    return json(200, { added: 0, alreadyRedeemed: true, ...balance(env, account) });
  }

  const quantity = Number.isInteger(payload.quantity) && payload.quantity > 0 ? payload.quantity : 1;
  const added = perUnit * quantity;
  account.credits += added;
  await saveAccount(env, session.sub, account);
  await env.SCAN_KV.put(txKey, JSON.stringify({ sub: session.sub, productId: payload.productId, added, at: new Date().toISOString() }));

  return json(200, { added, alreadyRedeemed: false, ...balance(env, account) });
}

async function handleRecognize(request, env, ctx) {
  requireSessionConfig(env);
  requireProviderConfig(env);
  const session = await requireSession(request, env);

  if (!(await withinRateLimit(env, session.sub))) {
    return error(429, "rate_limited", "Too many scan requests. Please wait a minute and try again.");
  }

  const body = await readJSON(request);
  const pages = body?.pages;
  const quality = body?.quality === "high" ? "high" : "standard";
  const context = typeof body?.context === "string" ? body.context.slice(0, MAX_CONTEXT_CHARS) : "";
  const jobId = typeof body?.jobId === "string" && /^[A-Za-z0-9-]{1,64}$/.test(body.jobId)
    ? body.jobId
    : null;

  if (!Array.isArray(pages) || pages.length === 0) {
    return error(400, "bad_request", "pages must be a non-empty array of base64 JPEG strings.");
  }
  if (pages.length > MAX_PAGES_PER_REQUEST) {
    return error(413, "too_many_pages", `Send up to ${MAX_PAGES_PER_REQUEST} images per request.`);
  }
  if (pages.some((p) => typeof p !== "string" || p.length === 0 || p.length > MAX_PAGE_B64_CHARS)) {
    return error(413, "page_too_large", "One of the pages is empty or too large.");
  }

  const pagesPerCredit = intVar(env.PAGES_PER_CREDIT, 4);
  const declaredPages = Number.isInteger(body?.pageCount) && body.pageCount > 0 ? body.pageCount : pages.length;
  const maxPages = intVar(env.MAX_PAGES_PER_SCAN, 12);
  if (declaredPages > maxPages) {
    return error(413, "too_many_pages", `Scan up to ${maxPages} pages at a time.`);
  }

  // Cache: identical images + context at the same quality tier → same result, no charge.
  const cacheKey = "c:" + (await pagesDigest(pages, quality, context));
  const cached = await env.SCAN_KV.get(cacheKey);
  const account = await loadAccount(env, session.sub, { createIfMissing: true });
  if (cached) {
    return json(200, { musicXML: cached, cached: true, ...balance(env, account) });
  }

  // Job accounting: charged once, then capped.
  const jobKey = jobId ? `j:${session.sub}:${jobId}` : null;
  let job = jobKey ? await loadJob(env, jobKey) : null;
  if (!job) {
    const cost = Math.max(1, Math.ceil(declaredPages / pagesPerCredit));
    const available = balance(env, account).remainingScans;
    if (available < cost) {
      const message = cost === 1
        ? "You're out of scans."
        : `This scan needs ${cost} credits (up to ${pagesPerCredit} pages each) and you have ${available}.`;
      return json(402, { error: { code: "insufficient_credits", message, needed: cost, remaining: available } });
    }
    job = { cost, images: 0, requests: 0, charged: false };
  }
  job.images += pages.length;
  job.requests += 1;
  const imageCap = job.cost * intVar(env.MAX_IMAGES_PER_CREDIT, 24);
  const requestCap = job.cost * intVar(env.MAX_REQUESTS_PER_CREDIT, 6);
  if (job.images > imageCap || job.requests > requestCap) {
    return error(413, "job_too_large", "This scan is too long for its credits. Try fewer pages at a time.");
  }
  if (jobKey) await saveJob(env, jobKey, job);

  let result;
  try {
    result = await recognize(env, pages, quality, fetch, context);
  } catch (err) {
    if (err instanceof ProviderError && err.truncated) {
      return error(422, "too_long", "This piece is too long for one scan. Try fewer pages at a time.");
    }
    console.error("recognition failed:", err.message);
    return error(502, "recognition_failed", "The recognition service is unavailable right now. Please try again.");
  }

  if (!looksLikeMusicXML(result.musicXML)) {
    // Provider replied, but not with usable MusicXML — don't charge the user.
    return error(422, "unreadable", "No readable music was found. Make sure the pages are sharp, well-lit, and right-side up.");
  }

  if (!job.charged) {
    chargeCredits(env, account, job.cost);
    job.charged = true;
    await saveAccount(env, session.sub, account);
    if (jobKey) await saveJob(env, jobKey, job);
  }
  ctx.waitUntil(env.SCAN_KV.put(cacheKey, result.musicXML, { expirationTtl: CACHE_TTL_SECONDS }));

  // Which model answered stays in the logs; clients only get the result.
  console.log("recognized with", result.provider);
  return json(200, {
    musicXML: result.musicXML,
    cached: false,
    ...balance(env, account),
  });
}

// MARK: - Accounts, credits & jobs (KV)
// KV is eventually consistent, so a determined user racing two devices could
// squeeze out an extra request — bounded by the per-job caps. Move to D1 if
// that ever matters.

async function loadAccount(env, sub, { createIfMissing = false } = {}) {
  const raw = await env.SCAN_KV.get("u:" + sub);
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      return {
        used: parsed.used ?? 0,
        credits: parsed.credits ?? 0,
        createdAt: parsed.createdAt,
      };
    } catch {
      // fall through to fresh account
    }
  }
  const fresh = { used: 0, credits: 0, createdAt: new Date().toISOString() };
  if (createIfMissing) await saveAccount(env, sub, fresh);
  return fresh;
}

async function saveAccount(env, sub, account) {
  await env.SCAN_KV.put("u:" + sub, JSON.stringify(account));
}

function balance(env, account) {
  const freeScans = intVar(env.FREE_SCANS, 1);
  const freeRemaining = Math.max(0, freeScans - account.used);
  return {
    freeScans,
    freeRemaining,
    credits: account.credits,
    remainingScans: freeRemaining + account.credits,
    pagesPerCredit: intVar(env.PAGES_PER_CREDIT, 4),
  };
}

/** Free allowance first, then paid credits. */
function chargeCredits(env, account, cost) {
  const freeRemaining = Math.max(0, intVar(env.FREE_SCANS, 1) - account.used);
  const fromFree = Math.min(freeRemaining, cost);
  account.used += fromFree;
  account.credits = Math.max(0, account.credits - (cost - fromFree));
}

async function loadJob(env, key) {
  const raw = await env.SCAN_KV.get(key);
  if (!raw) return null;
  try {
    const j = JSON.parse(raw);
    if (!Number.isInteger(j.cost)) return null;
    return { cost: j.cost, images: j.images ?? 0, requests: j.requests ?? 0, charged: Boolean(j.charged) };
  } catch {
    return null;
  }
}

async function saveJob(env, key, job) {
  await env.SCAN_KV.put(key, JSON.stringify(job), { expirationTtl: JOB_TTL_SECONDS });
}

async function withinRateLimit(env, sub) {
  const limit = intVar(env.RATE_LIMIT_PER_MINUTE, 20);
  const window = Math.floor(Date.now() / (RATE_WINDOW_SECONDS * 1000));
  const key = `r:${sub}:${window}`;
  const count = intVar(await env.SCAN_KV.get(key), 0) + 1;
  await env.SCAN_KV.put(key, String(count), { expirationTtl: RATE_WINDOW_SECONDS * 2 });
  return count <= limit;
}

function productTable(env) {
  if (typeof env.PRODUCTS === "string" && env.PRODUCTS.trim()) {
    try {
      const parsed = JSON.parse(env.PRODUCTS);
      if (parsed && typeof parsed === "object") return parsed;
    } catch {
      console.error("PRODUCTS is not valid JSON; using defaults");
    }
  }
  return DEFAULT_PRODUCTS;
}

// MARK: - Helpers

async function requireSession(request, env) {
  const header = request.headers.get("authorization") ?? "";
  if (!header.startsWith("Bearer ")) throw new AuthError("missing bearer token");
  return verifySessionToken(header.slice(7), env.SESSION_SECRET);
}

function requireSessionConfig(env) {
  const missing = ["SESSION_SECRET", "APPLE_BUNDLE_ID"].filter((name) => !env[name]);
  if (missing.length) {
    throw new Error(`worker is missing configuration: ${missing.join(", ")}`);
  }
}

/// Either provider key works alone; Gemini-only is the free-tier mode. A
/// deployment with neither is reachable (sign-in works) but can't scan yet,
/// so recognition reports "temporarily unavailable" instead of a 500.
function requireProviderConfig(env) {
  if (!env.ANTHROPIC_API_KEY && !env.GEMINI_API_KEY) {
    throw new ConfigError("worker needs ANTHROPIC_API_KEY or GEMINI_API_KEY (at least one)");
  }
}

async function pagesDigest(pages, quality, context) {
  const encoder = new TextEncoder();
  const hashes = [];
  for (const page of pages) {
    const digest = await crypto.subtle.digest("SHA-256", encoder.encode(page));
    hashes.push(hex(digest));
  }
  const combined = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(quality + "|" + hashes.join("|") + "|" + (context ?? ""))
  );
  return hex(combined);
}

function hex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function intVar(value, fallback) {
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

async function readJSON(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function error(status, code, message) {
  return json(status, { error: { code, message } });
}
