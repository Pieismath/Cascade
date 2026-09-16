// cascade-scan — the backend for Cascade's sheet-music scanning.
//
// Endpoints (all JSON):
//   POST   /v1/auth/apple   {identityToken}      → {sessionToken, remainingScans, freeScans}
//   GET    /v1/me           Bearer session       → {remainingScans, freeScans}
//   DELETE /v1/account      Bearer session       → {deleted: true}
//   POST   /v1/recognize    Bearer session,
//                           {pages:[b64jpeg], quality?, context?, jobId?}
//                                                → {musicXML, provider, cached, remainingScans}
//
// The app's provider keys never leave this worker. Quota is per Apple account
// (lifetime free scans, FREE_SCANS var). Identical page sets are cached by
// content hash, and cache hits don't consume quota.
//
// Segmented jobs: the app splits long scores into several requests (system
// crops in batches) and sends the same `jobId` with each. Only the first
// request of a job consumes a scan; the rest ride along free for two hours.

import {
  AuthError,
  verifyAppleIdentityToken,
  issueSessionToken,
  verifySessionToken,
} from "./auth.js";
import { ProviderError, recognize, looksLikeMusicXML } from "./providers.js";

const MAX_PAGES = 8;
const MAX_PAGE_B64_CHARS = 2_800_000; // ~2MB of JPEG per page
const MAX_CONTEXT_CHARS = 4000;
const MAX_JOB_ID_CHARS = 64;
const CACHE_TTL_SECONDS = 60 * 86400;
const JOB_TTL_SECONDS = 2 * 3600;

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

  return json(200, {
    sessionToken,
    remainingScans: remaining(env, account),
    freeScans: intVar(env.FREE_SCANS, 5),
  });
}

async function handleMe(request, env) {
  requireSessionConfig(env);
  const session = await requireSession(request, env);
  const account = await loadAccount(env, session.sub, { createIfMissing: true });
  return json(200, {
    remainingScans: remaining(env, account),
    freeScans: intVar(env.FREE_SCANS, 5),
  });
}

/// App Store guideline 5.1.1(v): accounts must be deletable in-app. We hold
/// nothing but the usage counter, so deletion is a single KV removal. The
/// session token stays cryptographically valid until it expires, but any
/// later request simply recreates a fresh zero-usage account, which is the
/// same as a brand-new sign-in.
async function handleDeleteAccount(request, env) {
  requireSessionConfig(env);
  const session = await requireSession(request, env);
  await env.SCAN_KV.delete("u:" + session.sub);
  return json(200, { deleted: true });
}

async function handleRecognize(request, env, ctx) {
  requireSessionConfig(env);
  requireProviderConfig(env);
  const session = await requireSession(request, env);

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
  if (pages.length > MAX_PAGES) {
    return error(413, "too_many_pages", `Scan up to ${MAX_PAGES} pages at a time.`);
  }
  if (pages.some((p) => typeof p !== "string" || p.length === 0 || p.length > MAX_PAGE_B64_CHARS)) {
    return error(413, "page_too_large", "One of the pages is empty or too large.");
  }

  // Cache: identical pages + context at the same quality tier → same result, no quota.
  const cacheKey = "c:" + (await pagesDigest(pages, quality, context));
  const cached = await env.SCAN_KV.get(cacheKey);
  if (cached) {
    const account = await loadAccount(env, session.sub, { createIfMissing: true });
    return json(200, {
      musicXML: cached,
      provider: "cache",
      cached: true,
      remainingScans: remaining(env, account),
    });
  }

  // Quota check up front; consume only after a successful recognition.
  const account = await loadAccount(env, session.sub, { createIfMissing: true });
  const jobKey = jobId ? `j:${session.sub}:${jobId}` : null;
  const jobAlreadyCharged = jobKey ? Boolean(await env.SCAN_KV.get(jobKey)) : false;
  if (!jobAlreadyCharged && remaining(env, account) <= 0) {
    return error(402, "out_of_scans", "You've used all your free scans.");
  }

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

  if (!jobAlreadyCharged) {
    account.used += 1;
    await saveAccount(env, session.sub, account);
    if (jobKey) {
      await env.SCAN_KV.put(jobKey, "1", { expirationTtl: JOB_TTL_SECONDS });
    }
  }
  ctx.waitUntil(
    env.SCAN_KV.put(cacheKey, result.musicXML, { expirationTtl: CACHE_TTL_SECONDS })
  );

  return json(200, {
    musicXML: result.musicXML,
    provider: result.provider,
    cached: false,
    remainingScans: remaining(env, account),
  });
}

// MARK: - Accounts & quota (KV)
// KV is eventually consistent, so a determined user racing two devices could
// squeeze out an extra free scan — acceptable for this stake. Move to D1 if
// paid credits are added later.

async function loadAccount(env, sub, { createIfMissing = false } = {}) {
  const raw = await env.SCAN_KV.get("u:" + sub);
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      return { used: parsed.used ?? 0, createdAt: parsed.createdAt };
    } catch {
      // fall through to fresh account
    }
  }
  const fresh = { used: 0, createdAt: new Date().toISOString() };
  if (createIfMissing) await saveAccount(env, sub, fresh);
  return fresh;
}

async function saveAccount(env, sub, account) {
  await env.SCAN_KV.put("u:" + sub, JSON.stringify(account));
}

function remaining(env, account) {
  return Math.max(0, intVar(env.FREE_SCANS, 5) - account.used);
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
