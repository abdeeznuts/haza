// POST { channel_id, event: "begin" | "end" }
// Called by the iPhone the moment the user starts/stops transmitting. Wakes every other joined
// member's app with a `pushtotalk` APNs push so the system PTT UI shows the active speaker and
// the app connects to the LiveKit room in the background.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, handle, HttpError, json, requireUser } from "../_shared/supabase.ts";
import { sendPushToTalk } from "../_shared/apns.ts";

Deno.serve(handle(async (req) => {
  if (req.method !== "POST") throw new HttpError(405, "POST only");
  const { id: userId } = await requireUser(req);
  const body = await req.json().catch(() => ({}));
  const channelId = body.channel_id as string | undefined;
  const event = (body.event as string | undefined) ?? "begin";
  if (!channelId) throw new HttpError(400, "channel_id required");

  const admin = adminClient();
  const { data: ok } = await admin.rpc("can_access_channel", { c: channelId, u: userId });
  if (!ok) throw new HttpError(403, "not a member of this channel");

  const [{ data: me }, { data: members }] = await Promise.all([
    admin.from("profiles").select("display_name").eq("id", userId).single(),
    admin.from("talk_members")
      .select("user_id, ptt_token")
      .eq("channel_id", channelId).eq("joined", true).neq("user_id", userId)
      .not("ptt_token", "is", null),
  ]);

  const payload = event === "end"
    ? { channelId, ended: true }
    : { channelId, activeSpeaker: me?.display_name ?? "Friend", activeSpeakerId: userId };

  const results = await Promise.all((members ?? []).map((m) => sendPushToTalk(m.ptt_token!, payload)));

  // Tokens Apple reports as bad are dropped so we stop pushing to them.
  const bad = results.filter((r) => r.status === 400 && (r.reason === "BadDeviceToken" || r.reason === "Unregistered"));
  if (bad.length) {
    await admin.from("talk_members").update({ ptt_token: null, joined: false })
      .eq("channel_id", channelId).in("ptt_token", bad.map((b) => b.token));
  }

  return json({ sent: results.filter((r) => r.status === 200).length, failed: results.filter((r) => r.status !== 200) });
}));
