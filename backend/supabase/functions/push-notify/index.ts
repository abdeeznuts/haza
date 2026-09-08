// Ordinary APNs alert pushes, driven by database triggers (public.notify_push → this function):
//   pings INSERT            → "Muhammad wants to talk"          (to_user)
//   planned_drives → live   → "Canyon run is live"              (everyone going/maybe)
//   referrals → rewarded    → "Ali finished their first drive"  (referrer)
// Authenticated by the x-webhook-secret header (PUSH_WEBHOOK_SECRET) — deployed with verify_jwt=false.
// Secrets: PUSH_WEBHOOK_SECRET, APNS_TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY, APNS_BUNDLE_ID, APNS_ENV
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, handle, HttpError, json } from "../_shared/supabase.ts";
import { providerToken } from "../_shared/apns.ts";
import { setting } from "../_shared/settings.ts";

interface Hook { type: string; table: string; record: Record<string, unknown>; old_record: Record<string, unknown> | null }

async function sendAlert(token: string, environment: string, title: string, body: string, data: Record<string, unknown>, category: string) {
  const bundle = await setting("APNS_BUNDLE_ID");
  if (!bundle) throw new Error("APNS_BUNDLE_ID not set");
  const host = environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const res = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${await providerToken()}`,
      "apns-push-type": "alert",
      "apns-topic": bundle,
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title, body }, sound: "default", category, "interruption-level": "time-sensitive" }, ...data }),
  });
  let reason: string | undefined;
  if (!res.ok) { try { reason = (await res.json()).reason; } catch { /* ignore */ } }
  return { token, status: res.status, reason };
}

Deno.serve(handle(async (req) => {
  if (req.method !== "POST") throw new HttpError(405, "POST only");
  const expected = await setting("PUSH_WEBHOOK_SECRET");
  if (!expected) throw new HttpError(503, "PUSH_WEBHOOK_SECRET not set");
  if (req.headers.get("x-webhook-secret") !== expected) throw new HttpError(401, "bad secret");

  const hook = await req.json().catch(() => null) as Hook | null;
  if (!hook?.record) throw new HttpError(400, "no record");
  const admin = adminClient();

  // Work out recipients + text per event.
  let recipients: string[] = [];
  let title = "", body = "", category = "GENERAL";
  let data: Record<string, unknown> = {};

  const name = async (id: string) => (await admin.from("profiles").select("display_name").eq("id", id).single()).data?.display_name ?? "A friend";

  if (hook.table === "pings") {
    const r = hook.record as { from_user: string; to_user: string; kind: string; channel_id: string | null };
    recipients = [r.to_user];
    const who = await name(r.from_user);
    category = "PING";
    data = { channel_id: r.channel_id, from_user: r.from_user, kind: r.kind };
    switch (r.kind) {
      case "talk": title = `${who} wants to talk`; body = "Tap to join the channel"; break;
      case "wave": title = `${who} waved`; body = "They're nearby"; break;
      case "meet": title = `${who} wants to meet`; body = "Open Haza to see where"; break;
      default: title = `${who} pinged you`; body = "Open Haza"; break;
    }
  } else if (hook.table === "planned_drives") {
    const r = hook.record as { id: string; title: string; creator_id: string; meet_name: string | null };
    const { data: rows } = await admin.rpc("plan_participants", { p_plan: r.id });
    recipients = ((rows ?? []) as { user_id: string }[]).map((x) => x.user_id).filter((u) => u !== r.creator_id);
    category = "PLAN_LIVE";
    data = { plan_id: r.id };
    title = `${r.title} is live`;
    body = r.meet_name ? `Everyone's heading to ${r.meet_name}. Talk channel is open.` : "Talk channel is open.";
  } else if (hook.table === "friendships") {
    const r = hook.record as { user_id: string; friend_id: string; status: string };
    if (r.status !== "pending") return json({ ok: true, ignored: "not pending" });
    recipients = [r.friend_id];
    category = "FRIEND_REQUEST";
    data = { from_user: r.user_id };
    title = `${await name(r.user_id)} wants to add you`;
    body = "Accept in Haza to see each other on the map.";
  } else if (hook.table === "referrals") {
    const r = hook.record as { referrer_id: string; referee_id: string };
    recipients = [r.referrer_id];
    category = "REFERRAL";
    title = `${await name(r.referee_id)} finished their first drive`;
    body = "30 days of Pro added to your account.";
  } else {
    return json({ ok: true, ignored: hook.table });
  }

  if (recipients.length === 0) return json({ ok: true, sent: 0 });
  // Launch phase without an Apple Developer account: no APNs key yet. The in-app inbox (Realtime) already
  // delivered this event; just say so instead of failing.
  if (!(await setting("APNS_TEAM_ID"))) return json({ ok: true, skipped: "apns not configured", recipients: recipients.length });
  const { data: tokens } = await admin.from("device_tokens").select("user_id, token, environment").in("user_id", recipients).eq("platform", "ios");
  const results = await Promise.all((tokens ?? []).map((t) => sendAlert(t.token, t.environment, title, body, data, category)));
  const dead = results.filter((r) => r.status === 410 || (r.status === 400 && r.reason === "BadDeviceToken")).map((r) => r.token);
  if (dead.length) await admin.from("device_tokens").delete().in("token", dead);
  return json({ ok: true, sent: results.filter((r) => r.status === 200).length, failed: results.filter((r) => r.status !== 200) });
}));
