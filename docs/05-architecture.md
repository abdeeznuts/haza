# Haza — Architecture

```
iPhone app (SwiftUI, iOS 17+)            Apple Watch app            Widgets / Live Activity / Control
 ├─ AppState (session, profile, briefing)  ├─ WatchSessionManager     ├─ TalkWidget (systemSmall → CarPlay)
 ├─ LocationService  ── drives, sharing    ├─ WatchRecorder (PCM)     ├─ DriveLiveActivity (.small → Watch+CarPlay)
 ├─ RealtimeService  ── loc:/crew: topics  └─ WatchTalkView           └─ TalkControl (Control Center)
 ├─ TalkService      ── PushToTalk + LiveKit          ▲ WatchConnectivity          ▲ App Group (SharedStore)
 ├─ V1Client         ── Core Bluetooth (ESP)          │                            │
 ├─ StoreService     ── StoreKit 2                    └────────── iPhone ──────────┘
 ├─ HomeService      ── overnight samples → inference
 └─ CarPlaySceneDelegate (templates; needs entitlement)

HazaCore (Swift package, tested on Linux): ESP protocol, SpeedFilter, Geo, HomeInference, Referral, Briefing

Supabase (live, project "pace")            LiveKit Cloud (you create)         Apple
 ├─ Postgres + PostGIS, RLS                 └─ audio rooms per talk channel     ├─ APNs `pushtotalk` (ptt-notify)
 ├─ Realtime Broadcast (private topics)                                         ├─ App Store Server Notifications → iap
 ├─ Edge: livekit-token, ptt-notify, iap                                        └─ StoreKit 2 (verify-transaction)
 └─ pg_cron: expiry, pruning, nightly home inference
```

## Data flows

**Position.** `LocationService` filters GPS through `SpeedFilter`, broadcasts `{lat,lng,spd,hdg,drv,t}` on `loc:<uid>` every 3 s while driving (60 s parked), and upserts `live_locations`. Friends subscribe to `loc:<friend>` (RLS: only accepted friends can). Positions inside a friend's home bubble come only from `friends_live()`, which snaps them to the home pin.

**Drive.** Core Motion automotive (or GPS > 6 m/s) starts a `DriveRecorder`; 4 minutes stationary ends it. Route is Douglas-Peucker simplified (12 m) and inserted into `drives`. The `drives_qualify_referral` trigger rewards referrals on the first ≥1 mi drive. A Live Activity runs for the duration.

**Talk.** User taps Join (foreground) → `PTChannelManager.requestJoinChannel` → `didJoinChannel` → fetch LiveKit token (`livekit-token` checks `can_access_channel`) → connect room. Ephemeral PTT token → `talk_members.ptt_token`. Hold → `requestBeginTransmitting` → `didBeginTransmittingFrom` → `ptt-notify` sends `pushtotalk` APNs to members → their apps wake, `incomingPushResult` returns the speaker, system activates audio, they subscribe to the room. `didActivate` → mic on. Release → mic off. LiveKit `didUpdateSpeakingParticipants` drives `setActiveRemoteParticipant`. Steering-wheel play/pause keys the mic (documented PTT behaviour). Watch: PCM chunks over WatchConnectivity → `TalkService.injectWatchAudio` (LiveKit app-audio mixer — verify API on Mac).

**Radar.** `V1Client` connects to the V1connection LE service, sends `reqVersion` + `reqStartAlertData`, parses `infDisplayData`/`respAlertData` with `ESP.Parser`, renders the panel, and shares priority alerts ≥3 bars to `radar_alerts` (15-minute TTL, friends-only read, cron-expired).

**Home.** Overnight (00–05) parked samples every 20 min → local file + `home_samples`. `HomeInference.suggest` (device) and `infer_home` (server, nightly) cluster them; ≥3 nights → suggestion the user confirms. Manual pin and typed address also supported.

**Pro.** StoreKit 2 purchase with `appAccountToken = user id` → app posts JWS to `iap/verify-transaction` → `subscriptions` row. Apple's notifications hit `iap/appstore-notifications` (JWS chain verified against Apple Root CA - G3). `is_pro(u)` = active subscription OR `profiles.pro_until > now()` (referral time). Client reads `my_pro()`.

**Briefing.** `my_briefing()` (server facts) + `DeviceFacts` (permissions, Watch installed, CarPlay/Control marked done) → `Briefing.merge` → ordered rows, each mapped to a one-tap action.

## Security model
- RLS on every table; friends see cards/positions only via SECURITY DEFINER RPCs that apply the privacy rules.
- Internal helpers revoked from `anon`/`authenticated` (advisor-clean except PostGIS's `spatial_ref_sys`, which Supabase can't RLS-enable).
- Edge functions: user JWT for `livekit-token`/`ptt-notify`/`verify-transaction`; Apple JWS signature for the webhook; fail closed when secrets are missing.
- No secrets in the app; the publishable key is the only key shipped.

## What runs where (for the Mac phase)
- Linux-verified: HazaCore tests (16 passing), Deno JWS verification test, SQL smoke test on the live DB, all Swift files parse.
- Mac-only: Xcode build, entitlements/provisioning, StoreKit config file, device tests for PTT, BLE, WatchConnectivity audio, LiveKit mixer API, CarPlay Simulator.
