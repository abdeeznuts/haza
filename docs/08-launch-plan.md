# Haza — Launch Plan (6 weeks from "Mac in hand")

The build is done to the point a compiler can check it. What's left is sequencing: accounts, a Mac weekend, a real-world beta with car people in Houston, review, launch. Each week has an exit condition; don't move on until it's true.

## Week 0 — Accounts and the name (laptop only, ~2 hours)
- Apple Developer Program ($99), LiveKit Cloud (free), domain for `haza.app` or the closest you can get (then change `HazaBrand.universalLinkHost`, `Referral.linkHost`, the entitlements `applinks:` line, and the site).
- Free USPTO search for HAZA / HAZZA in class 9 and 38 (usually the "communications" class for chat apps). If clear, file a trademark later; if not, choose the listing name accordingly.
- Deploy `site/` to Cloudflare Pages (free). The privacy and terms URLs must be live before App Review.
- Add the Supabase secrets listed in `backend/README.md`.
- Push the repo to GitHub (public → free macOS build minutes). Green build = the code compiles.
Exit: green GitHub build, site live, secrets set.

## Week 1 — The Mac weekend (`docs/06`)
- Generate the project, sign, run on your iPhone. Fix what the compiler names.
- Device tests in this order: sign in → briefing → map shows you → talk between two phones → Watch hold-to-talk → background drive recording → V1 pairing → purchase in sandbox → referral reward.
- Capture screenshots from the real app (App Review rejects concept art).
Exit: all six device tests pass on two phones.

## Week 2–3 — Closed beta in Houston
- TestFlight, 10–25 people from real crews (Cars & Coffee Sugar Land, Westheimer night drives, Grand Parkway runs). Two crews minimum so cross-crew behaviour gets exercised.
- Instrument the five metrics in §Metrics with simple SQL over the existing tables — no analytics SDK needed for v1.
- The three questions to answer with data: does Talk get used on more than half of drives with 2+ cars; does the home bubble ever surprise someone; does anyone hit "Radar" without a V1 (if many do, Escort/Uniden demand is real — start the partner email campaign in-app).
Exit: a week with zero crashes in TestFlight, Talk used on ≥50% of multi-car drives.

## Week 4 — Review
- Submit with `docs/04` metadata and the reviewer notes; two reviewer accounts already friends with a crew and a plan.
- File the CarPlay entitlement request the same day (separate track; the app ships without it).
- Expect one round of questions about background location and the walkie-talkie; the answers are in the reviewer notes.
Exit: Ready for Sale.

## Week 5–6 — Launch loop
- The referral is the marketing plan: 30 days Pro per friend is worth more to a car person than an ad. Seed it through the beta crews on launch day.
- Content that costs nothing: a 20-second CarPlay Dashboard clip and a Watch clip for TikTok/Reels; a post in r/Houston car groups and the Cars & Coffee Discords with the invite link.
- Pricing test after 30 days: yearly $29.99 vs $34.99 on new users only (App Store Connect price experiments are not A/B on the same SKU; use two promo codes instead).

## Metrics (SQL over existing tables)
| Metric | Query sketch |
|---|---|
| Weekly active crews | crews with ≥2 members who had a drive or talk join this week |
| Talk minutes / active user | sum of transmit durations (add `talk_events` table in v1.1 if needed; LiveKit Cloud dashboard has minutes today) |
| Watch / CarPlay adoption | `briefing.watch.done`, `briefing.carplay.done` sent to `profiles` (add two boolean columns in v1.1) |
| Referral conversion | `referrals` claimed → rewarded |
| Trial → paid | `subscriptions` with status active after 7 days vs trials started (App Store Connect Sales report is the source of truth) |

## Roadmap after 1.0 (in the order the data will probably ask for)
1. Route playback with friends' cars (Pro hero feature; data already stored in `drive_points`).
2. Crew map themes and a car-chip customizer (Pro upsell that costs nothing to run).
3. Android + Android Auto (same backend; calling apps are closed-testing-only on Play today — start with the widget-style companion).
4. Escort / Uniden the day either publishes an interface.
5. Meet-point sharing to Apple Maps via SharePlay-style "everyone navigate here".

## CarPlay entitlement request — answers to paste
- App name: Haza — Drive Together. Category requested: **Driving task** (alternative: Communication).
- What the CarPlay app does: lets a driver join/leave their crew's walkie-talkie channel, see which friends are nearby (distance only), and see the next planned meet — all from list and information templates, no maps, no message content, refreshed at most every 10 seconds.
- Why it's needed while driving: convoys need a hands-free way to open a channel and confirm the meet point without touching the phone; the steering-wheel play/pause already keys the mic once a channel is open.
- Safety: no gaming or social feed; nothing to read except a friend's name and distance; all flows possible without the iPhone.
