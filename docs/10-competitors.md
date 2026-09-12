# Haza vs. the field (Sept 12, 2026)

Sources: App Store / Google Play listings and vendor sites read today — Wheelz (apps.apple.com id6774287184, wheelz.club), Life360 (apps.apple.com id384830320, support.life360.com drive-detection article), Enroad (id6757245082), Convoy Tracker: Group Nav (id6753726393), Apple Find My (built into iOS). "✓" = shipped in Haza, "→" = being built now, "✗" = not planned.

| Feature | Wheelz | Life360 | Find My | Enroad | Convoy Tracker | Haza |
|---|---|---|---|---|---|---|
| Automatic drive tracking (no start/stop) | ✓ | ✓ (½ mi + 15 mph to count as a Drive) | ✗ | ✓ | ✗ | ✓ |
| Live friends on one map | ✓ (3D cars) | ✓ | ✓ | ✗ | ✓ (convoy only) | ✓ |
| Friend speed readout | ✓ | ✓ (drive events) | ✗ | ✗ | ✗ | ✓ (opt-out per user) |
| Walkie-talkie (iPhone / Watch / CarPlay) | ✗ | ✗ | ✗ | ✗ | ✗ (broadcast text only) | ✓ (LiveKit; Lock Screen PTT with the signed build) |
| Ping a friend to talk | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Planned drives / convoys with their own channel | convoy | ✗ | ✗ | ✗ | routes + join code | ✓ |
| Route replay | 3D replays | ✗ | ✗ | ✗ | ✓ | ✓ (with the cars that were with you) |
| Drive stats: distance, time, avg/max | ✓ | ✓ | ✗ | ✓ | ✗ | ✓ |
| 0–60 timing, G-force, hard braking / rapid acceleration counts | ✓ (Pro) | braking/accel/speed events | ✗ | ✓ (Pro: accel, braking, cornering, stops, lane changes) | ✗ | → |
| Weekly / monthly recap | ✓ | family driving summary | ✗ | shareable stat image | ✗ | → |
| Garage (cars) | 300+ 3D models | ✗ | ✗ | ✗ | ✗ | ✓ (make/model/year/colour; 3D ✗) |
| Places with arrive / leave alerts | ✗ | ✓ (2 places free, unlimited paid) | ✓ (notify when arrives/leaves) | ✗ | ✗ | → |
| Location history / timeline | drive timeline | 2 days (Silver) → 30 days (Gold) | ✗ | drive list | route history | → (unlimited) |
| Battery level of friends | ✗ | ✓ | ✗ | ✗ | ✗ | → |
| Check-in | ✗ | ✓ | ✗ | ✗ | ✗ | → |
| SOS to friends | ✗ | ✓ (+ dispatch paid) | ✗ | ✗ | ✗ | → (friends + tap-to-call 911; no dispatch service) |
| Crash detection | ✗ | ✓ (Arity; dispatch paid) | ✗ (iPhone 14+ has Apple's own) | ✗ | ✗ | → (beta: on-device impact heuristic → "Are you OK?" → SOS to friends) |
| Ghost mode / pause sharing | ✓ | bubbles | stop sharing | ✗ | ✗ | → |
| Home privacy bubble | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ (150 m; learned automatically) |
| Radar detector on the map | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ (Valentine One Gen2; shared alerts) |
| Widgets / Live Activity / CarPlay | widgets + Live Activities | ✗ | ✗ | ✗ | CarPlay nav (beta) | ✓ (Home Screen, Control Center, Live Activity, CarPlay Dashboard; CarPlay app pending entitlement) |
| Apple Watch app | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ (hold-to-talk, nearby, ping) |
| ETA to the meet point for everyone | ✗ | ✗ | Maps ETA share | ✗ | turn-by-turn | → |
| "Friend just started driving" alerts | ✗ | drive start/end (family) | ✗ | ✗ | ✗ | → (opt-in per friend; convoy suggestion when two friends drive near each other) |
| Android | ✓ | ✓ | ✗ | ✓ | ✓ | → (APK first, Play later) |
| Price | Pro $2.99/wk, $4.99/mo, $39.99/yr | $7.99 / $14.99 / $24.99 per month | free | Pro | free | everything free during launch |

## Drive detection — how the leaders do it, and Haza's rule set
- Life360 counts a Drive only after ½ mile and 15 mph; needs battery > 10%, background access, no low-power mode, cell signal; records phone usage, high speed, hard braking, rapid acceleration (Arity).
- Wheelz: "detects when you start moving, begins a trip in the background"; manual-only mode available; ghost mode.
- Haza (after this round): Core Motion automotive + GPS > 13 mph confirms a drive; parked = no GPS at all (significant-change + visits only); a drive is kept if ≥ 0.12 mi and ≥ 60 s; ends after 4 min stationary; below 15 % battery the recorder drops to a 30 s cadence; friends only receive positions every 3 s while moving (60 s parked) and never inside a home bubble.

## Where Haza is already ahead
Walkie-talkie across iPhone/Watch/CarPlay, ping-to-talk, planned drives with their own channel, radar alerts on the map, automatic home privacy bubble, route playback with companions, everything free.

## Gaps being closed in this round (iOS, then Android)
Battery-first engine; battery % sharing; ghost mode; check-in; SOS; drive-start alerts + convoy suggestion + auto-join live plan channels; places with arrive/leave alerts; driving stats (0–60, G, braking/accel counts) + weekly recap; ETA to meet; location timeline; crash-detection beta.
