# Haza backend (Supabase + LiveKit)

Live project: `pace` (ref `ooeykcnrnvneklwoxyti`, region us-east-2, Free plan).
API URL: https://ooeykcnrnvneklwoxyti.supabase.co
Publishable key (safe to ship in the app): `sb_publishable_CJVZYYyfc3ITVFq-XLmaKg_GvVyjRbk`

## What is deployed and verified
- `supabase/migrations/0001_init.sql` — schema (PostGIS), RLS, RPCs, triggers, pg_cron jobs. Applied.
  Smoke-tested live: invite-code claim → auto-friend, home privacy bubble in `friends_live()`,
  `friends_nearby()`, referral reward on first ≥1 mi drive (30 days referrer / 14 days new user),
  home inference (`infer_home`) found the right cluster from 4 nights of synthetic samples.
- Edge functions (Deno): `livekit-token`, `ptt-notify`, `iap` (`/iap/appstore-notifications`,
  `/iap/verify-transaction`), `push-notify` (pings, plans going live, referral rewards → APNs alert pushes,
  fired by database triggers through pg_net; verified live: a ping insert reached the function).
  Apple JWS chain verification was unit-tested locally with a generated P-384→P-384→P-256 chain
  (valid accepted, tampered rejected, wrong anchor rejected).
- `supabase/migrations/0002_push_and_plans.sql` — `device_tokens`, `join_crew(code)`, `go_live(plan)`, webhook triggers.

## Secrets you must add (Supabase → Project Settings → Edge Functions → Secrets)
| Secret | Where it comes from |
|---|---|
| `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | LiveKit Cloud project (free Build plan: 5,000 participant-minutes/mo) |
| `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY` | Apple Developer → Keys → new key with APNs enabled (.p8 contents) |
| `APNS_BUNDLE_ID` | your bundle id (currently `app.haza.ios` in `ios/project.yml`) |
| `APNS_ENV` | `sandbox` while testing on TestFlight/dev builds, `production` for the store |
| `APPLE_ROOT_CA_G3_PEM` | PEM of Apple Root CA - G3 from https://www.apple.com/certificateauthority/ (`openssl x509 -inform der -in AppleRootCA-G3.cer`) |
| `PUSH_WEBHOOK_SECRET` | `7536efbb98869157aa6b6f788ec2534ee0a4f582dbe83aec` — already stored in the database (`private.settings`); paste the same value here so the triggers can call `push-notify`. Rotate both places together if it leaks. |

Until these exist the functions fail closed with a clear error (503/500), nothing silently passes.

## Realtime channels (private, RLS-protected)
- `loc:<user_id>` — broadcast your position every 2–5 s while driving; friends subscribe.
- `crew:<crew_id>` — crew room: positions, who's talking, radar alerts, plan updates.
- `user:<user_id>` — the user's inbox, only they can listen. Database triggers (`inbox_broadcast`,
  migration 0006) push pings, friend requests/acceptances and plans going live into it with
  `realtime.send()`, so the app reacts instantly with no APNs (banner in-app, local notification in
  the background). Note: `realtime.send` needs the day's `realtime.messages` partition, which the
  Realtime service creates the first time any client connects — already warmed up for this project.

## Launch phase
`private.settings.everything_unlocked = 'true'` makes `is_pro()` true for everyone (migration 0003).
Set it to `'false'` (and `HazaBrand.everythingUnlocked = false` in the app) when it's time to sell.

## Client RPCs
`claim_invite(code, device_hash)`, `friends_live()`, `friends_nearby(radius_m)`, `direct_channel(friend)`,
`radar_alerts_near(lat, lng, radius_m)`, `my_briefing()`, `my_pro()`, `my_home_suggestion()`, `delete_my_account()`,
`join_crew(code)`, `go_live(plan)`.
