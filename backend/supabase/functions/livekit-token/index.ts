// POST { channel_id } -> { token, url, room }
// Mints a LiveKit access token for a talk channel the caller belongs to.
// Secrets: LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET  (from a LiveKit Cloud project, free "Build" plan)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { AccessToken } from "npm:livekit-server-sdk@2";
import { adminClient, handle, HttpError, json, requireUser } from "../_shared/supabase.ts";
import { setting } from "../_shared/settings.ts";

Deno.serve(handle(async (req) => {
  if (req.method !== "POST") throw new HttpError(405, "POST only");
  const { id: userId } = await requireUser(req);
  const { channel_id } = await req.json().catch(() => ({}));
  if (typeof channel_id !== "string") throw new HttpError(400, "channel_id required");

  const admin = adminClient();
  const { data: ok } = await admin.rpc("can_access_channel", { c: channel_id, u: userId });
  if (!ok) throw new HttpError(403, "not a member of this channel");

  const { data: channel, error } = await admin
    .from("talk_channels").select("livekit_room").eq("id", channel_id).single();
  if (error || !channel) throw new HttpError(404, "channel not found");

  const { data: profile } = await admin
    .from("profiles").select("display_name").eq("id", userId).single();

  const apiKey = await setting("LIVEKIT_API_KEY");
  const apiSecret = await setting("LIVEKIT_API_SECRET");
  const url = await setting("LIVEKIT_URL");
  if (!apiKey || !apiSecret || !url) throw new HttpError(503, "LiveKit not configured (set LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET)");

  const at = new AccessToken(apiKey, apiSecret, {
    identity: userId,
    name: profile?.display_name ?? "Driver",
    ttl: "6h",
  });
  at.addGrant({
    room: channel.livekit_room,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: true,
  });

  // Mark membership as joined so PTT pushes target this user.
  await admin.from("talk_members").upsert(
    { channel_id, user_id: userId, joined: true },
    { onConflict: "channel_id,user_id" },
  );

  return json({ token: await at.toJwt(), url, room: channel.livekit_room });
}));
