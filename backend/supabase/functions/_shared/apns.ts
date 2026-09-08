// Minimal APNs client (token-based auth, HTTP/2 via fetch) — used for Push to Talk pushes.
// Secrets: APNS_TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY (the .p8 file contents, PEM), APNS_BUNDLE_ID,
//          APNS_ENV ("production" | "sandbox")

function b64url(bytes: Uint8Array | string): string {
  const s = typeof bytes === "string" ? btoa(bytes) : btoa(String.fromCharCode(...bytes));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

let cached: { jwt: string; issuedAt: number } | null = null;

/** Apple requires the provider token to be refreshed no more than once every 20 minutes and at least hourly. */
export async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.issuedAt < 45 * 60) return cached.jwt;

  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const pem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!teamId || !keyId || !pem) throw new Error("APNs not configured (APNS_TEAM_ID / APNS_KEY_ID / APNS_PRIVATE_KEY)");

  const key = await crypto.subtle.importKey(
    "pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: now }));
  const data = new TextEncoder().encode(`${header}.${claims}`);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, data));
  const jwt = `${header}.${claims}.${b64url(sig)}`;
  cached = { jwt, issuedAt: now };
  return jwt;
}

export interface PushResult { token: string; status: number; reason?: string }

/**
 * Sends a Push to Talk push (apns-push-type: pushtotalk, topic <bundle>.voip-ptt, priority 10, expiration 0)
 * — exactly the headers Apple documents in "Creating a Push to Talk app".
 */
export async function sendPushToTalk(deviceToken: string, payload: Record<string, unknown>): Promise<PushResult> {
  const bundle = Deno.env.get("APNS_BUNDLE_ID");
  if (!bundle) throw new Error("APNS_BUNDLE_ID not set");
  const host = (Deno.env.get("APNS_ENV") ?? "production") === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";

  const res = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${await providerToken()}`,
      "apns-push-type": "pushtotalk",
      "apns-topic": `${bundle}.voip-ptt`,
      "apns-priority": "10",
      "apns-expiration": "0",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  let reason: string | undefined;
  if (!res.ok) {
    try { reason = (await res.json()).reason; } catch { /* ignore */ }
  }
  return { token: deviceToken, status: res.status, reason };
}
