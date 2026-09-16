// Authentication: Apple identity-token verification (sign-in) and the
// worker's own HS256 session tokens (everything after sign-in).
//
// Flow: the app sends the short-lived Apple identity token once, at sign-in;
// we verify it against Apple's published JWKS and mint our own long-lived
// session token so users aren't re-prompted for every scan.

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const JWKS_MAX_AGE_MS = 12 * 3600 * 1000;

export class AuthError extends Error {}

// Module-level cache lives for the isolate's lifetime; refreshed when stale
// or when Apple rotates to a key id we haven't seen.
let jwksCache = { keys: null, fetchedAt: 0 };

// MARK: base64url helpers

export function b64urlToBytes(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export function bytesToB64url(bytes) {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeSegment(seg) {
  try {
    return JSON.parse(new TextDecoder().decode(b64urlToBytes(seg)));
  } catch {
    throw new AuthError("malformed token segment");
  }
}

// MARK: Apple identity tokens

/**
 * Verifies an Apple identity token (RS256 JWT) and returns its payload.
 * `fetcher` is injectable for tests.
 */
export async function verifyAppleIdentityToken(token, bundleId, fetcher = fetch) {
  const parts = String(token).split(".");
  if (parts.length !== 3) throw new AuthError("malformed identity token");

  const header = decodeSegment(parts[0]);
  const payload = decodeSegment(parts[1]);
  if (header.alg !== "RS256") throw new AuthError("unexpected signing algorithm");

  const key = await appleKey(header.kid, fetcher);
  const signed = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlToBytes(parts[2]),
    signed
  );
  if (!ok) throw new AuthError("invalid signature");

  const now = Date.now() / 1000;
  if (payload.iss !== APPLE_ISSUER) throw new AuthError("unexpected issuer");
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(bundleId)) throw new AuthError("token is for a different app");
  if (typeof payload.exp !== "number" || payload.exp < now - 60) {
    throw new AuthError("identity token expired");
  }
  if (!payload.sub) throw new AuthError("token has no subject");
  return payload;
}

async function appleKey(kid, fetcher) {
  const stale = Date.now() - jwksCache.fetchedAt > JWKS_MAX_AGE_MS;
  const missing = !jwksCache.keys || !jwksCache.keys.some((k) => k.kid === kid);
  if (stale || missing) {
    const res = await fetcher(APPLE_JWKS_URL);
    if (!res.ok) throw new AuthError("could not fetch Apple keys");
    jwksCache = { keys: (await res.json()).keys ?? [], fetchedAt: Date.now() };
  }
  const jwk = jwksCache.keys.find((k) => k.kid === kid);
  if (!jwk) throw new AuthError("unknown Apple key id");
  return crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
}

// MARK: Session tokens (HS256)

async function hmacKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

/** Issues a session JWT for a verified Apple user id. */
export async function issueSessionToken(sub, secret, days) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payload = { sub, iat: now, exp: now + days * 86400 };
  const enc = (obj) => bytesToB64url(new TextEncoder().encode(JSON.stringify(obj)));
  const signingInput = enc(header) + "." + enc(payload);
  const sig = await crypto.subtle.sign(
    "HMAC",
    await hmacKey(secret),
    new TextEncoder().encode(signingInput)
  );
  return signingInput + "." + bytesToB64url(new Uint8Array(sig));
}

/** Verifies a session JWT; returns its payload (with .sub) or throws AuthError. */
export async function verifySessionToken(token, secret) {
  const parts = String(token).split(".");
  if (parts.length !== 3) throw new AuthError("malformed session token");
  const ok = await crypto.subtle.verify(
    "HMAC",
    await hmacKey(secret),
    b64urlToBytes(parts[2]),
    new TextEncoder().encode(parts[0] + "." + parts[1])
  );
  if (!ok) throw new AuthError("invalid session token");
  const payload = decodeSegment(parts[1]);
  const now = Date.now() / 1000;
  if (typeof payload.exp !== "number" || payload.exp < now) {
    throw new AuthError("session expired");
  }
  if (!payload.sub) throw new AuthError("session has no subject");
  return payload;
}
