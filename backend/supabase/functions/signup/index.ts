// POST { email, password, display_name? } → { ok, created | exists }
// Beta sign-up that needs no email round-trip: the service role creates the user already confirmed,
// then the app signs in with the password. Rationale: Supabase's built-in mailer allows only a couple
// of auth emails per hour, which breaks "five friends sign up at the meet". When custom SMTP exists,
// the magic-link / 6-digit-code path in the app takes over and this function can be retired.
// Deployed with verify_jwt=false (the caller has no session yet); the gateway still requires the
// project's publishable key in the apikey header.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, handle, HttpError, json } from "../_shared/supabase.ts";

const recent = new Map<string, number[]>();   // per-IP throttle (best effort, per isolate)

Deno.serve(handle(async (req) => {
  if (req.method !== "POST") throw new HttpError(405, "POST only");
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
  const now = Date.now();
  const hits = (recent.get(ip) ?? []).filter((t) => now - t < 60 * 60 * 1000);
  if (hits.length >= 20) throw new HttpError(429, "too many sign-ups from this network; try again later");
  recent.set(ip, [...hits, now]);

  const body = await req.json().catch(() => ({}));
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const displayName = String(body.display_name ?? "").trim().slice(0, 40);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new HttpError(400, "enter a valid email");
  if (password.length < 6) throw new HttpError(400, "password must be at least 6 characters");

  const admin = adminClient();
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: displayName ? { full_name: displayName } : {},
  });
  if (error) {
    const msg = (error.message ?? "").toLowerCase();
    if (msg.includes("already") || msg.includes("exists") || (error as { status?: number }).status === 422) {
      return json({ ok: true, exists: true });
    }
    throw new HttpError(400, error.message);
  }
  return json({ ok: true, created: true, user_id: data.user?.id });
}));
