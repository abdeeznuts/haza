// Verifies Apple's signed JWS payloads (App Store Server Notifications V2, StoreKit 2 signed
// transactions/renewal info). Apple signs with an ES256 leaf certificate carried in the JWS
// `x5c` header; the chain must lead to Apple Root CA - G3.
//
// Trust anchor: set the secret APPLE_ROOT_CA_G3_PEM to the PEM of Apple Root CA - G3, downloaded
// from https://www.apple.com/certificateauthority/ (AppleRootCA-G3.cer -> `openssl x509 -inform der -in AppleRootCA-G3.cer`).
// The function fails closed if the anchor is missing.

export interface VerifiedJws<T = Record<string, unknown>> { header: Record<string, unknown>; payload: T }

// ---------- base64 helpers ----------
function b64urlDecode(s: string): Uint8Array {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}
function b64Decode(s: string): Uint8Array {
  return Uint8Array.from(atob(s.replace(/\s+/g, "")), (c) => c.charCodeAt(0));
}
function pemToDer(pem: string): Uint8Array {
  return b64Decode(pem.replace(/-----[^-]+-----/g, ""));
}
function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

// ---------- tiny DER reader ----------
interface Tlv { tag: number; start: number; end: number; hStart: number; hEnd: number } // value = [start,end), whole = [hStart,hEnd)

function readTlv(buf: Uint8Array, offset: number): Tlv {
  const tag = buf[offset];
  let i = offset + 1;
  let len = buf[i++];
  if (len & 0x80) {
    const n = len & 0x7f;
    len = 0;
    for (let k = 0; k < n; k++) len = (len << 8) | buf[i++];
  }
  return { tag, start: i, end: i + len, hStart: offset, hEnd: i + len };
}
function children(buf: Uint8Array, tlv: Tlv): Tlv[] {
  const out: Tlv[] = [];
  let p = tlv.start;
  while (p < tlv.end) { const c = readTlv(buf, p); out.push(c); p = c.hEnd; }
  return out;
}
function slice(buf: Uint8Array, tlv: Tlv, whole = false): Uint8Array {
  return whole ? buf.slice(tlv.hStart, tlv.hEnd) : buf.slice(tlv.start, tlv.end);
}
function oidEquals(buf: Uint8Array, tlv: Tlv, hex: string): boolean {
  const v = slice(buf, tlv);
  return Array.from(v).map((b) => b.toString(16).padStart(2, "0")).join("") === hex;
}

const OID_P256 = "2a8648ce3d030107";          // 1.2.840.10045.3.1.7
const OID_P384 = "2b81040022";                // 1.3.132.0.34
const OID_ECDSA_SHA256 = "2a8648ce3d040302";  // 1.2.840.10045.4.3.2
const OID_ECDSA_SHA384 = "2a8648ce3d040303";  // 1.2.840.10045.4.3.3

interface ParsedCert {
  der: Uint8Array;
  tbs: Uint8Array;            // whole TBSCertificate TLV (what the signature covers)
  spki: Uint8Array;           // whole SubjectPublicKeyInfo TLV
  curve: "P-256" | "P-384";
  sigHash: "SHA-256" | "SHA-384";
  signature: Uint8Array;      // DER ECDSA signature
  notBefore: Date; notAfter: Date;
}

function parseTime(buf: Uint8Array, tlv: Tlv): Date {
  const s = new TextDecoder().decode(slice(buf, tlv));
  // UTCTime YYMMDDHHMMSSZ or GeneralizedTime YYYYMMDDHHMMSSZ
  const full = tlv.tag === 0x17 ? ((parseInt(s.slice(0, 2)) < 50 ? "20" : "19") + s) : s;
  return new Date(Date.UTC(+full.slice(0, 4), +full.slice(4, 6) - 1, +full.slice(6, 8), +full.slice(8, 10), +full.slice(10, 12), +full.slice(12, 14)));
}

export function parseCert(der: Uint8Array): ParsedCert {
  const cert = readTlv(der, 0);
  const [tbsTlv, sigAlgTlv, sigValTlv] = children(der, cert);
  const tbsKids = children(der, tbsTlv);
  let idx = 0;
  if (tbsKids[0].tag === 0xa0) idx = 1;          // explicit version present
  // serial, signature, issuer, validity, subject, spki
  const validity = tbsKids[idx + 3];
  const spkiTlv = tbsKids[idx + 5];
  const [nb, na] = children(der, validity);

  const [spkiAlg] = children(der, spkiTlv);
  const [, curveOid] = children(der, spkiAlg);
  let curve: ParsedCert["curve"];
  if (oidEquals(der, curveOid, OID_P256)) curve = "P-256";
  else if (oidEquals(der, curveOid, OID_P384)) curve = "P-384";
  else throw new Error("unsupported public key curve");

  const [sigOid] = children(der, sigAlgTlv);
  let sigHash: ParsedCert["sigHash"];
  if (oidEquals(der, sigOid, OID_ECDSA_SHA256)) sigHash = "SHA-256";
  else if (oidEquals(der, sigOid, OID_ECDSA_SHA384)) sigHash = "SHA-384";
  else throw new Error("unsupported certificate signature algorithm");

  const sigBits = slice(der, sigValTlv);          // BIT STRING: first byte = unused bits
  return {
    der, tbs: slice(der, tbsTlv, true), spki: slice(der, spkiTlv, true), curve, sigHash,
    signature: sigBits.slice(1), notBefore: parseTime(der, nb), notAfter: parseTime(der, na),
  };
}

/** DER ECDSA signature (SEQUENCE { r INTEGER, s INTEGER }) -> raw r||s for WebCrypto. */
function derSigToRaw(sig: Uint8Array, size: number): Uint8Array {
  const seq = readTlv(sig, 0);
  const [r, s] = children(sig, seq);
  const out = new Uint8Array(size * 2);
  const put = (t: Tlv, at: number) => {
    let v = slice(sig, t);
    while (v.length > size && v[0] === 0) v = v.slice(1);
    out.set(v, at + size - v.length);
  };
  put(r, 0); put(s, size);
  return out;
}

async function importSpki(spki: Uint8Array, curve: "P-256" | "P-384"): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: curve }, false, ["verify"]);
}

/** Verifies `subject` was signed by `issuer`. */
async function verifyCertSignature(subject: ParsedCert, issuer: ParsedCert): Promise<boolean> {
  const key = await importSpki(issuer.spki, issuer.curve);
  const raw = derSigToRaw(subject.signature, issuer.curve === "P-256" ? 32 : 48);
  return crypto.subtle.verify({ name: "ECDSA", hash: subject.sigHash }, key, raw, subject.tbs);
}

function trustedRoot(): ParsedCert {
  const pem = Deno.env.get("APPLE_ROOT_CA_G3_PEM");
  if (!pem) throw new Error("APPLE_ROOT_CA_G3_PEM not set — refusing to verify Apple JWS without a trust anchor");
  return parseCert(pemToDer(pem));
}

/**
 * Verify an Apple JWS: chain (leaf -> intermediate -> pinned root), validity windows, and the
 * ES256 signature over `header.payload`. Returns the decoded payload.
 */
export async function verifyAppleJws<T = Record<string, unknown>>(jws: string): Promise<VerifiedJws<T>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed JWS");
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
  if (header.alg !== "ES256") throw new Error(`unexpected alg ${header.alg}`);
  const x5c: string[] = header.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) throw new Error("x5c chain missing");

  const chain = x5c.map((c) => parseCert(b64Decode(c)));
  const root = trustedRoot();
  const now = new Date();
  for (const c of chain) {
    if (now < c.notBefore || now > c.notAfter) throw new Error("certificate outside validity window");
  }
  // Each cert must be signed by the next; the last must be signed by (or be) the pinned root.
  for (let i = 0; i < chain.length - 1; i++) {
    if (!(await verifyCertSignature(chain[i], chain[i + 1]))) throw new Error(`chain break at ${i}`);
  }
  const last = chain[chain.length - 1];
  if (!bytesEqual(last.der, root.der)) {
    if (!(await verifyCertSignature(last, root))) throw new Error("chain does not lead to Apple Root CA - G3");
  }

  const leafKey = await importSpki(chain[0].spki, chain[0].curve);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, leafKey, b64urlDecode(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new Error("JWS signature invalid");

  return { header, payload: JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1]))) as T };
}

/** Shape of the decoded transaction Apple signs (subset used by Haza). */
export interface AppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  purchaseDate: number;
  expiresDate?: number;
  environment: "Sandbox" | "Production";
  appAccountToken?: string;
  bundleId: string;
  type: string;
  revocationDate?: number;
}
export interface AppleRenewalInfo {
  originalTransactionId: string;
  autoRenewStatus: 0 | 1;
  autoRenewProductId?: string;
  isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: number;
  environment: "Sandbox" | "Production";
}
