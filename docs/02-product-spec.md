# Haza — Product Specification (v1, iOS)

Name: **Haza** (see §10). Bundle id `app.haza.ios`; the display name is the one constant `HazaBrand.name`.

## 1. One-line pitch
The map for car people: see where your friends are, talk to them like a walkie-talkie from your phone, watch, or car screen, plan drives together, and get your radar detector's alerts on the same map.

## 2. Who it's for
Car enthusiasts who already drive together (crews, meets, canyon runs, night drives) and who currently juggle Life360/Find My + a group chat + phone calls + a separate radar detector app. Age 17+ rating (user-generated content, location sharing).

## 3. What ships in v1 (and what is deliberately not)

| Area | v1 | Not in v1 (why) |
|---|---|---|
| Map | Apple MapKit dark editorial map, friends as car chips with heading, live speed (if they share it), "at home" bubble, crew filter | Google Places on the map (Google ToS §14.2 forbids Places content on a non-Google map) |
| Talk | Push-to-Talk framework channels (system UI, background, CarPlay play/pause keys the mic), LiveKit audio, per-crew / per-drive / direct channels, "Ping to talk" | Full-duplex calls (PTT half-duplex is the product) |
| Watch | Standalone Watch app: nearby friends, hold-to-talk that relays audio through the iPhone, incoming talk clips + haptics, Smart Stack widget | Direct WebRTC on the watch (LiveKit has no watchOS SDK) |
| CarPlay | Interactive Dashboard widget (Talk on/off, speed, next meet, nearest friend) + Live Activity for the active drive — no entitlement needed on iOS 26; Communication-category CarPlay app (contacts → talk, crew channel) once Apple grants the entitlement | Custom CarPlay map UI (only navigation apps may) |
| Drives | Auto-detect trips (Core Motion automotive + location), timeline, route playback, per-car stats, personal top speed (private) | Speed leaderboards / speed challenges (App Review 1.4.4, 1.4.5) |
| Plans | Planned drives: title, meet point, time, crew, RSVPs, "go live" turns it into a convoy with its own talk channel | Turn-by-turn navigation (handoff to Apple Maps instead) |
| Radar | Valentine One Gen2 over BLE (real ESP implementation): band, direction arrows, strength, frequency; alerts drop pins and go to crew for 15 min | Escort / Uniden (no public API; "request access" state + partner email) |
| Home | Manual pin, Contacts "me card" address import, or inferred from overnight dwell (3+ nights); 150 m privacy bubble hides exact location from friends | — |
| Pro | Subscription via StoreKit 2 + referral-earned Pro time | Lifetime unlock in v1 |
| Android | — | Phase 2 (Kotlin, same backend; Android Auto calling apps are limited to closed testing tracks today) |

## 4. Screens (matches the prototype and the SwiftUI code)

1. **Welcome / Sign in** — Sign in with Apple (first), email OTP. Invite code field auto-fills from a Universal Link or the pasted code.
2. **Briefing** — the "what you're missing" page. Server list (`my_briefing()`) merged with device facts: location "Always" not granted, Watch app not installed, CarPlay widget not added, Control Center "Talk" control not added, radar not paired. Each row is one tap to fix. Shown at launch until every setup item is done, then lives in Profile.
3. **Map (home tab)** — full-bleed map; top: crew selector + "Talk" pill (green when channel joined); bottom sheet: Friends nearby (distance, speed, tap to ping/talk), radar alerts near me, active plan.
4. **Talk** — channel list (crews, direct, live drive), big hold-to-talk button, who's speaking, mute, "Ping" (sends a talk-request push).
5. **Drives** — timeline of auto-recorded drives, detail with route playback, distance, time, avg, your private top speed, which car.
6. **Plans** — upcoming drives with RSVP, create plan (title, when, meet point from map search, crew), "Go live".
7. **Garage** — cars (make/model/year/color), primary car is what friends see.
8. **Radar** — pair Valentine One Gen2, live V1 panel (bogey count, bars, band, arrows), share-to-crew toggle, legality notice.
9. **Profile & Pro** — invite link + code, referral progress ("2 friends joined → 60 days Pro"), Pro paywall, privacy (home, share speed, visibility), account deletion.

## 5. The walkie-talkie, precisely

- One PTT channel is active system-wide (Apple limit) → Haza keeps **one** system channel ("Haza") and swaps its descriptor as the user switches crew/direct/drive conversations (Apple's documented multi-conversation pattern).
- Join/leave only from the foreground with a button (Apple rule). After joining, the ephemeral PTT push token is stored in `talk_members.ptt_token`.
- Transmit: system UI or in-app button → `requestBeginTransmitting` → on `didActivate(audioSession)` the app publishes the LiveKit mic track and calls `ptt-notify {begin}` so every other member's app wakes via `pushtotalk` APNs and shows the speaker in the system UI, then subscribes to the LiveKit room to play audio. On end: unpublish + `ptt-notify {end}`.
- CarPlay: with an active channel, the car's play/pause button begins/ends transmission (Apple docs). The Dashboard widget's "Talk" toggle joins/leaves the last channel via an App Intent.
- Watch: hold the button → watch records 16 kHz mono PCM chunks (AVAudioEngine) → `WCSession.sendMessageData` to the iPhone → iPhone injects the audio into the LiveKit room through its custom audio source and drives the PTT session exactly like a phone transmission. Incoming: iPhone forwards a short clip + speaker name to the watch (haptic + playback). Needs device validation (Mac phase).

## 6. Location, speed, privacy

- Foreground: `CLLocationUpdate.liveUpdates` while the app is open; background trips via `CLBackgroundActivitySession` + Core Motion automotive detection. Broadcast every 3 s while driving, 60 s parked, over Realtime `loc:<uid>`; last-known row in `live_locations`.
- Speed shown is GPS ground speed, smoothed (Kalman-lite in `HazaCore`). "Predicted speed" in the widget = speed extrapolated 3 s ahead from the speed/acceleration filter, labeled "now" and "in 3 s".
- Friends never receive raw coordinates inside the home bubble; the server snaps them to the home point (`friends_live()`). Speed is only shared if `share_speed`.
- Nothing about speed is ever ranked socially. Max speed stays in the owner's private drive detail.

## 7. Pro and money

Free: live map, talk, drives (last 30 days), 1 crew, 1 car, radar.
Pro ($4.99/mo, $29.99/yr via StoreKit 2 — priced under Wheelz's $4.99/$39.99 for launch; 7-day free trial via an introductory offer): unlimited history + route playback, unlimited crews and plans, all cars, radar alert sharing to crews, custom map themes, Pro badge on your car chip.

Referral (server-side, App Review-safe): every account has an invite link `https://haza.app/i/<CODE>`. When a new user claims a code and completes their first drive ≥1 mile, the referrer gets **30 days of Pro** and the new user **14 days**, stacked on any existing time, applied by the `drives_qualify_referral` trigger. This never unlocks paid features via a code (3.1.1); it's a time-limited promotional entitlement the server grants, and subscriptions still go through Apple. Limits: one claim per account and per device hash; self-referrals rejected.

## 8. App Review risk register (from the guidelines text in the research brief)

| Risk | Mitigation built in |
|---|---|
| 1.4.4 "encourage … excessive speed" | No leaderboards, no speed badges, no "fastest" sort; speed is a utility readout like Life360; description states this. |
| 1.4.5 challenges that risk harm | Plans are meets/cruises, no timed challenges. |
| 2.5.4 background modes | Modes used: location (trips), push-to-talk, audio (talk playback), remote notifications. Each tied to a visible feature. |
| 2.5.14 recording indication | System PTT UI + in-app red "transmitting" pill; mic only during transmission. |
| 3.1.1 unlocking via own mechanism | Pro only via StoreKit; referral grants are time-limited promos, never codes for paid features. |
| 4.8 login services | Sign in with Apple offered first. |
| 5.1.1(v) account deletion | Profile → Delete account → `delete_my_account()` cascades everything. |
| 5.1.5 location consent | Purpose strings explain each use; "Always" requested only when the user enables auto-drive detection, from the Briefing. |
| Privacy manifest | `PrivacyInfo.xcprivacy` declares location, user id, purchase history; no tracking. |
| Radar legality | Onboarding notice: banned in VA, DC, military bases, CMVs > 10,000 lb; the feature is a detector *display*, detection hardware is the user's. |

## 9. Success metrics for launch
Weekly active crews, talk minutes per active user, % of users with Watch or CarPlay widget installed, referral conversion (claims → qualified), trial → paid.

## 10. Name
**Haza** (short for hazard — flash your hazards to say thanks) was chosen on Sep 7, 2026. App Store listing name: **"Haza — Drive Together"** (a separate "Haza - Group Voice Chat Rooms" app exists; see the research brief). Bundle id `app.haza.ios`, App Group `group.app.haza`, Universal Link host `haza.app` (buy the domain, or change `HazaBrand.universalLinkHost` + `Referral.linkHost` + the entitlements to the one you get).
