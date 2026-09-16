// App Store purchase verification without any library: StoreKit 2 hands the
// app a JWS (`Transaction.jwsRepresentation`) signed by Apple, with the
// signing certificate chain in the `x5c` header. We verify that chain up to
// the pinned Apple Root CA - G3, check Apple's purpose-marker OIDs, verify the
// JWS signature with the leaf key, and only then trust the payload. A modified
// app therefore cannot mint credits — only Apple can sign a transaction.
//
// DER handling is deliberately minimal: we only need the three top-level
// fields of a certificate (tbsCertificate, signatureAlgorithm, signatureValue)
// and the subjectPublicKeyInfo / validity inside tbsCertificate.

export class PurchaseError extends Error {}

const APPLE_ROOT_CA_G3_URL = "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer";
const ROOT_MAX_AGE_MS = 7 * 86400 * 1000;

// Apple's marker extensions: leaf = receipt/transaction signing, intermediate = WWDR.
const LEAF_MARKER_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_MARKER_OID = "1.2.840.113635.100.6.2.1";

const OID_ECDSA_SHA256 = "1.2.840.10045.4.3.2";
const OID_ECDSA_SHA384 = "1.2.840.10045.4.3.3";
const OID_ECDSA_SHA512 = "1.2.840.10045.4.3.4";
const OID_P256 = "1.2.840.10045.3.1.7";
const OID_P384 = "1.3.132.0.34";
const OID_P521 = "1.3.132.0.35";

let rootCache = { der: null, fetchedAt: 0 };

// MARK: - Public API

/**
 * Verifies a StoreKit 2 signed transaction and returns its payload.
 * `options.rootCertDER` pins the trust anchor (tests inject their own);
 * production fetches Apple Root CA - G3 from apple.com and caches it.
 */
export async function verifySignedTransaction(jws, options) {
  const { bundleId, fetcher = fetch, now = Date.now(), requireMarkerOIDs = true } = options;
  const parts = String(jws).split(".");
  if (parts.length !== 3) throw new PurchaseError("malformed signed transaction");

  let header;
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
  } catch {
    throw new PurchaseError("malformed transaction header");
  }
  if (header.alg !== "ES256") throw new PurchaseError("unexpected transaction algorithm");
  if (!Array.isArray(header.x5c) || header.x5c.length < 2) {
    throw new PurchaseError("transaction is missing its certificate chain");
  }

  const chain = header.x5c.map((b64) => b64ToBytes(b64));
  const rootDER = options.rootCertDER ?? (await appleRootCA(fetcher));

  // Chain: leaf ← intermediate ← root. If Apple included the root, it must be ours.
  const leaf = chain[0];
  const intermediate = chain[1];
  if (chain.length >= 3 && !bytesEqual(chain[2], rootDER)) {
    throw new PurchaseError("certificate chain does not end at Apple's root");
  }

  const leafCert = parseCertificate(leaf);
  const intermediateCert = parseCertificate(intermediate);
  const rootCert = parseCertificate(rootDER);

  checkValidity(leafCert, now, "signing certificate");
  checkValidity(intermediateCert, now, "intermediate certificate");

  if (!(await certificateSignedBy(leafCert, intermediateCert))) {
    throw new PurchaseError("signing certificate was not issued by the intermediate");
  }
  if (!(await certificateSignedBy(intermediateCert, rootCert))) {
    throw new PurchaseError("intermediate certificate was not issued by Apple's root");
  }

  if (requireMarkerOIDs) {
    if (!containsOID(leafCert.tbs, LEAF_MARKER_OID)) {
      throw new PurchaseError("signing certificate is not an App Store signing certificate");
    }
    if (!containsOID(intermediateCert.tbs, INTERMEDIATE_MARKER_OID)) {
      throw new PurchaseError("intermediate certificate is not Apple WWDR");
    }
  }

  // JWS signature over "header.payload" with the leaf key (ES256, raw r||s).
  const leafKey = await importSPKI(leafCert.spki, leafCert.curve);
  const signed = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafKey,
    b64urlToBytes(parts[2]),
    signed
  );
  if (!ok) throw new PurchaseError("transaction signature is invalid");

  let payload;
  try {
    payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));
  } catch {
    throw new PurchaseError("malformed transaction payload");
  }
  if (payload.bundleId !== bundleId) throw new PurchaseError("transaction is for a different app");
  if (!payload.transactionId || !payload.productId) {
    throw new PurchaseError("transaction is missing identifiers");
  }
  if (payload.environment === "Xcode") {
    throw new PurchaseError("Xcode test transactions cannot be redeemed against the live service");
  }
  if (payload.revocationDate) throw new PurchaseError("transaction was refunded");
  return payload;
}

async function appleRootCA(fetcher) {
  if (rootCache.der && Date.now() - rootCache.fetchedAt < ROOT_MAX_AGE_MS) return rootCache.der;
  const res = await fetcher(APPLE_ROOT_CA_G3_URL);
  if (!res.ok) throw new PurchaseError("could not fetch Apple's root certificate");
  const der = new Uint8Array(await res.arrayBuffer());
  rootCache = { der, fetchedAt: Date.now() };
  return der;
}

// MARK: - Certificates

/** Splits a DER certificate into the parts we need. */
export function parseCertificate(der) {
  const bytes = der instanceof Uint8Array ? der : new Uint8Array(der);
  const cert = readTLV(bytes, 0);
  if (cert.tag !== 0x30) throw new PurchaseError("certificate is not a DER sequence");
  const [tbs, sigAlg, sigValue] = children(bytes, cert);
  if (!tbs || !sigAlg || !sigValue) throw new PurchaseError("certificate structure is invalid");

  const tbsChildren = children(bytes, tbs);
  let i = 0;
  if (tbsChildren[0]?.tag === 0xa0) i = 1; // explicit version
  const validity = tbsChildren[i + 3];
  const spki = tbsChildren[i + 5];
  if (!validity || !spki) throw new PurchaseError("certificate is missing fields");

  const [notBefore, notAfter] = children(bytes, validity).map((t) => parseTime(bytes, t));
  const sigOID = decodeOID(bytes, children(bytes, sigAlg)[0]);
  const bitString = sigValue.content;
  const signatureDER = bitString.subarray(1); // drop "unused bits" byte

  return {
    tbs: bytes.subarray(tbs.start, tbs.end),
    signatureOID: sigOID,
    signatureDER,
    spki: bytes.subarray(spki.start, spki.end),
    curve: curveOf(bytes, spki),
    notBefore,
    notAfter,
  };
}

async function certificateSignedBy(cert, issuer) {
  const hash = hashForSignatureOID(cert.signatureOID);
  const key = await importSPKI(issuer.spki, issuer.curve);
  const raw = ecdsaDERToRaw(cert.signatureDER, curveByteLength(issuer.curve));
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, raw, cert.tbs);
}

function checkValidity(cert, now, label) {
  if (now < cert.notBefore.getTime() - 60_000 || now > cert.notAfter.getTime()) {
    throw new PurchaseError(`${label} is not currently valid`);
  }
}

function hashForSignatureOID(oid) {
  switch (oid) {
    case OID_ECDSA_SHA256: return "SHA-256";
    case OID_ECDSA_SHA384: return "SHA-384";
    case OID_ECDSA_SHA512: return "SHA-512";
    default: throw new PurchaseError(`unsupported certificate signature algorithm ${oid}`);
  }
}

function curveOf(bytes, spki) {
  const algorithm = children(bytes, spki)[0];
  const params = children(bytes, algorithm)[1];
  if (!params || params.tag !== 0x06) throw new PurchaseError("certificate key is not an EC key");
  const oid = decodeOID(bytes, params);
  switch (oid) {
    case OID_P256: return "P-256";
    case OID_P384: return "P-384";
    case OID_P521: return "P-521";
    default: throw new PurchaseError(`unsupported key curve ${oid}`);
  }
}

function curveByteLength(curve) {
  return curve === "P-256" ? 32 : curve === "P-384" ? 48 : 66;
}

async function importSPKI(spki, curve) {
  return crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: curve }, false, ["verify"]);
}

/** DER ECDSA-Sig-Value (SEQUENCE of two INTEGERs) → fixed-width r||s. */
export function ecdsaDERToRaw(der, size) {
  const seq = readTLV(der, 0);
  const [r, s] = children(der, seq);
  const out = new Uint8Array(size * 2);
  out.set(leftPad(stripLeadingZeros(r.content), size), 0);
  out.set(leftPad(stripLeadingZeros(s.content), size), size);
  return out;
}

function stripLeadingZeros(bytes) {
  let i = 0;
  while (i < bytes.length - 1 && bytes[i] === 0) i++;
  return bytes.subarray(i);
}

function leftPad(bytes, size) {
  if (bytes.length > size) throw new PurchaseError("signature integer too large");
  const out = new Uint8Array(size);
  out.set(bytes, size - bytes.length);
  return out;
}

// MARK: - DER helpers

function readTLV(bytes, offset) {
  if (offset + 2 > bytes.length) throw new PurchaseError("truncated DER");
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let headerLength = 2;
  if (length & 0x80) {
    const n = length & 0x7f;
    length = 0;
    for (let i = 0; i < n; i++) length = length * 256 + bytes[offset + 2 + i];
    headerLength = 2 + n;
  }
  const start = offset;
  const end = offset + headerLength + length;
  if (end > bytes.length) throw new PurchaseError("truncated DER element");
  return { tag, start, headerLength, length, end, content: bytes.subarray(offset + headerLength, end) };
}

function children(bytes, tlv) {
  const out = [];
  let offset = tlv.start + tlv.headerLength;
  while (offset < tlv.end) {
    const child = readTLV(bytes, offset);
    out.push(child);
    offset = child.end;
  }
  return out;
}

function decodeOID(bytes, tlv) {
  if (tlv.tag !== 0x06) throw new PurchaseError("expected OID");
  const c = tlv.content;
  const parts = [Math.floor(c[0] / 40), c[0] % 40];
  let value = 0;
  for (let i = 1; i < c.length; i++) {
    value = value * 128 + (c[i] & 0x7f);
    if ((c[i] & 0x80) === 0) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

/** Encodes a dotted OID as a full DER OID element (tag + length + content). */
export function encodeOID(oid) {
  const parts = oid.split(".").map(Number);
  const body = [parts[0] * 40 + parts[1]];
  for (const p of parts.slice(2)) {
    const chunk = [];
    let v = p;
    do {
      chunk.unshift(v & 0x7f);
      v = Math.floor(v / 128);
    } while (v > 0);
    for (let i = 0; i < chunk.length - 1; i++) chunk[i] |= 0x80;
    body.push(...chunk);
  }
  return new Uint8Array([0x06, body.length, ...body]);
}

/** True when the DER bytes contain the given OID element anywhere. */
export function containsOID(bytes, oid) {
  const needle = encodeOID(oid);
  outer: for (let i = 0; i + needle.length <= bytes.length; i++) {
    for (let j = 0; j < needle.length; j++) {
      if (bytes[i + j] !== needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

function parseTime(bytes, tlv) {
  const text = new TextDecoder().decode(tlv.content);
  let iso;
  if (tlv.tag === 0x17) {
    // UTCTime YYMMDDHHMMSSZ
    const yy = parseInt(text.slice(0, 2), 10);
    const year = yy >= 50 ? 1900 + yy : 2000 + yy;
    iso = `${year}-${text.slice(2, 4)}-${text.slice(4, 6)}T${text.slice(6, 8)}:${text.slice(8, 10)}:${text.slice(10, 12)}Z`;
  } else {
    // GeneralizedTime YYYYMMDDHHMMSSZ
    iso = `${text.slice(0, 4)}-${text.slice(4, 6)}-${text.slice(6, 8)}T${text.slice(8, 10)}:${text.slice(10, 12)}:${text.slice(12, 14)}Z`;
  }
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) throw new PurchaseError("certificate has an unreadable date");
  return date;
}

// MARK: - bytes

function b64urlToBytes(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return b64ToBytes(s);
}

function b64ToBytes(s) {
  const bin = atob(s);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

function bytesEqual(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}
