// In-app purchase backend (one function, two routes — Apple's webhook can't carry a Supabase JWT,
// so this function is deployed with verify_jwt=false and authenticates each route itself).
//
//   POST /iap/appstore-notifications   App Store Server Notifications V2 ({ signedPayload }),
//                                      authenticated by Apple's JWS signature chain.
//   POST /iap/verify-transaction       { jws_representation } from StoreKit 2, caller must be signed in.
//
// App Store Connect → App → App Information → App Store Server Notifications → URL:
//   https://<project-ref>.supabase.co/functions/v1/iap/appstore-notifications
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, handle, HttpError, json, requireUser } from "../_shared/supabase.ts";
import { setting } from "../_shared/settings.ts";
import { type AppleRenewalInfo, type AppleTransaction, verifyAppleJws } from "../_shared/apple-jws.ts";

interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: { bundleId: string; environment: string; signedTransactionInfo?: string; signedRenewalInfo?: string };
}

function bundleOk(bundleId?: string) {
  const expected = await setting("APNS_BUNDLE_ID");
  return !expected || !bundleId || bundleId === expected;
}

async function appStoreNotification(req: Request): Promise<Response> {
  const body = await req.json().catch(() => null);
  if (!body?.signedPayload) throw new HttpError(400, "signedPayload missing");
  const { payload } = await verifyAppleJws<NotificationPayload>(body.signedPayload);
  if (!bundleOk(payload.data?.bundleId)) throw new HttpError(400, "bundle mismatch");

  const admin = adminClient();
  let tx: AppleTransaction | undefined;
  let renewal: AppleRenewalInfo | undefined;
  if (payload.data?.signedTransactionInfo) tx = (await verifyAppleJws<AppleTransaction>(payload.data.signedTransactionInfo)).payload;
  if (payload.data?.signedRenewalInfo) renewal = (await verifyAppleJws<AppleRenewalInfo>(payload.data.signedRenewalInfo)).payload;

  await admin.from("appstore_events").insert({
    notification_type: payload.notificationType,
    subtype: payload.subtype ?? null,
    original_transaction_id: tx?.originalTransactionId ?? renewal?.originalTransactionId ?? null,
    payload: { notificationUUID: payload.notificationUUID, tx, renewal },
  });

  if (!tx) return json({ ok: true });
  // appAccountToken = the Supabase user id the app attaches at purchase time.
  const userId = tx.appAccountToken;
  if (!userId) return json({ ok: true, note: "no appAccountToken; nothing to map" });

  const revoked = payload.notificationType === "REFUND" || payload.notificationType === "REVOKE" || !!tx.revocationDate;
  const expired = payload.notificationType === "EXPIRED" || (tx.expiresDate !== undefined && tx.expiresDate < Date.now());
  const inGrace = payload.notificationType === "DID_FAIL_TO_RENEW" && payload.subtype === "GRACE_PERIOD";
  const status = revoked ? "revoked" : inGrace ? "grace" : expired ? "expired" : "active";
  const expiresAt = inGrace && renewal?.gracePeriodExpiresDate
    ? new Date(renewal.gracePeriodExpiresDate).toISOString()
    : tx.expiresDate ? new Date(tx.expiresDate).toISOString() : null;

  await admin.from("subscriptions").upsert({
    user_id: userId,
    product_id: tx.productId,
    original_transaction_id: tx.originalTransactionId,
    expires_at: expiresAt,
    status,
    environment: tx.environment,
    auto_renew: renewal ? renewal.autoRenewStatus === 1 : null,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  return json({ ok: true });
}

async function verifyTransaction(req: Request): Promise<Response> {
  const { id: userId } = await requireUser(req);
  const { jws_representation } = await req.json().catch(() => ({}));
  if (typeof jws_representation !== "string") throw new HttpError(400, "jws_representation required");

  const { payload: tx } = await verifyAppleJws<AppleTransaction>(jws_representation);
  if (!bundleOk(tx.bundleId)) throw new HttpError(400, "bundle mismatch");
  if (tx.appAccountToken && tx.appAccountToken.toLowerCase() !== userId.toLowerCase()) {
    throw new HttpError(403, "transaction belongs to a different account");
  }
  const revoked = !!tx.revocationDate;
  const expired = tx.expiresDate !== undefined && tx.expiresDate < Date.now();
  const status = revoked ? "revoked" : expired ? "expired" : "active";

  const admin = adminClient();
  const { error } = await admin.from("subscriptions").upsert({
    user_id: userId,
    product_id: tx.productId,
    original_transaction_id: tx.originalTransactionId,
    expires_at: tx.expiresDate ? new Date(tx.expiresDate).toISOString() : null,
    status,
    environment: tx.environment,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (error) throw new HttpError(500, error.message);
  const { data: isPro } = await admin.rpc("is_pro", { u: userId });
  return json({ ok: true, status, is_pro: !!isPro, expires_at: tx.expiresDate ?? null });
}

Deno.serve(handle(async (req) => {
  if (req.method !== "POST") throw new HttpError(405, "POST only");
  const path = new URL(req.url).pathname;
  if (path.endsWith("/appstore-notifications")) return appStoreNotification(req);
  if (path.endsWith("/verify-transaction")) return verifyTransaction(req);
  throw new HttpError(404, "unknown route");
}));
