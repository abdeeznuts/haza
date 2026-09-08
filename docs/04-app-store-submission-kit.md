# Haza — App Store Submission Kit

Everything App Store Connect will ask for, prewritten. Replace "Haza" if you rename (see product spec §10).

## App Store Connect — App Information
- **Name:** Haza — Drive Together (the bare word is used by "Haza - Group Voice Chat Rooms", so the suffix is part of the listing name)
- **Subtitle (30):** Drive together. Talk hands-free.
- **Primary category:** Navigation · **Secondary:** Social Networking
- **Age rating:** 17+ answers: unrestricted web access No; user-generated content Yes (crew names, plan titles, voice); location sharing → "Frequent/Intense: none"; the 17+ comes from the social + location combination the way Life360 is rated. Fill the questionnaire honestly and accept the rating it computes.
- **Content rights:** no third-party content.
- **Privacy policy URL:** https://haza.app/privacy (publish before submitting; the app links it in Profile).
- **Support URL:** https://haza.app/support · **Marketing URL:** https://haza.app

## Description (4000 max)
Haza is the map for people who drive together.

See your friends on the road with their car, heading and speed. Hold one button to talk to them — on your iPhone, on your Apple Watch, or from your car's screen with CarPlay. Plan a drive, and when it starts everyone going shows up on the same map with their own walkie-talkie channel.

Pair a Valentine One Gen2 radar detector over Bluetooth and its alerts appear on your map and, if you choose, on your friends' maps for 15 minutes.

Every drive records itself — distance, time, route, which car — with no start or stop button. Your home is protected by a privacy bubble: inside 150 m of it, friends see your home pin, never your exact spot. Haza can learn where home is from where your phone sleeps; you always confirm.

Haza does not rank or reward speed. Speed is shown as a readout so a friend behind you knows when you're slowing down — the same way it works in family-location apps. Obey the speed limit and the laws where you drive.

Pro (subscription): unlimited drive history and route playback, unlimited crews and plans, all your cars, radar alert sharing, map themes. Invite a friend and you both get free Pro time after their first drive.

Subscriptions: Haza Pro Monthly $4.99, Haza Pro Yearly $29.99 (7-day free trial). Auto-renew unless cancelled at least 24 hours before the end of the period; manage in your Apple ID settings. Terms: https://haza.app/terms · Privacy: https://haza.app/privacy

Radar detectors are illegal in passenger vehicles in Virginia, Washington D.C., on military installations, and in commercial vehicles over 10,000 lb. Haza only displays what your own detector reports.

## Keywords (100)
car friends,convoy,walkie talkie,push to talk,drive tracker,car meet,radar detector,carplay,crew,speedometer

## What's New (1.0)
First release.

## In-App Purchases (create before the build is uploaded)
| Reference name | Product ID | Type | Price | Intro offer |
|---|---|---|---|---|
| Haza Pro Monthly | app.haza.pro.monthly | Auto-renewable, group "Pro" | $4.99 | — |
| Haza Pro Yearly | app.haza.pro.yearly | Auto-renewable, group "Pro" | $29.99 | 7-day free trial |
Subscription group display name: Haza Pro. Localized description: "Unlimited history, playback, crews, cars and radar sharing." App Store Server Notifications V2 URL: `https://ooeykcnrnvneklwoxyti.supabase.co/functions/v1/iap/appstore-notifications` (Production and Sandbox).

## App Privacy (nutrition labels) — matches PrivacyInfo.xcprivacy
Data linked to you: Precise Location (app functionality), Name, User ID, Audio Data (voice while talking; not stored), Purchase History. No tracking. No data used for advertising. Third parties that process data: Supabase (database), LiveKit (real-time audio), Apple (payments, push).

## App Review — Notes to reviewer (paste into "Notes")
Haza is a social driving app: live map of friends, walkie-talkie using Apple's Push to Talk framework, drive logging, planned drives, and an optional Bluetooth link to a Valentine One radar detector.

Test account: (create two TestFlight accounts and put both here — the reviewer needs a friend to see). Sign in with Apple also works.

Walkie-talkie: Talk tab → Join → hold the button. Audio is transported by LiveKit; the system PTT UI appears on the Lock Screen. With two devices, a push (apns-push-type: pushtotalk) wakes the second one.

Location: "Always" is requested only from the Briefing row, so drives record themselves; "While Using" works too. We show the background location indicator.

Speed: displayed as a readout for the user and (optionally) friends; there are no leaderboards, rankings or challenges (Guideline 1.4.4). Maximum speed is private to the driver.

Radar: the app only displays what the user's own detector reports over Bluetooth; it does not detect anything itself. The legal notice is shown in onboarding and on the Radar tab.

Subscriptions: StoreKit 2; server-side entitlement; account deletion is in Profile → Delete account (5.1.1(v)). Referral rewards are time-limited promotional Pro periods granted by our server after a referred user's first drive; no purchase or unlock happens outside StoreKit (3.1.1).

CarPlay: this build ships the iOS 26 Dashboard widget and Live Activity (no entitlement needed). The CarPlay app scene is included but inactive until Apple grants the entitlement requested separately.

## Screenshots plan (6.9" and 6.5" iPhone, plus Apple Watch)
1. Map with three friends and the speed sheet — "See who's driving. Right now."
2. Talk screen mid-transmission — "Hold to talk. iPhone, Watch, CarPlay."
3. CarPlay Dashboard widget — "On your car's screen." (capture in CarPlay Simulator on the Mac)
4. Radar panel with a Ka alert and the crew pin — "Your radar detector, on the map."
5. Plans — "Plan the drive. Everyone shows up."
6. Profile referral card — "Invite friends, earn Pro."
Watch: hold-to-talk screen and nearby list.

## Entitlement requests you file with Apple (separate from review)
- **CarPlay** at https://developer.apple.com/carplay — request *Driving task* (talk toggle, crew status, next meet during a drive) and mention the app also qualifies as *Communication* if Apple prefers; describe that the UI is template-only, refreshes ≤ every 10 s, never shows message content. Apple reviews the request; expect weeks. Add the granted key to `Haza.entitlements` (commented block) and regenerate the provisioning profile.
- **Push to Talk**: normal capability, no request needed (enabled in Signing & Capabilities).
- **Associated Domains**: host `https://haza.app/.well-known/apple-app-site-association` with `{"applinks":{"details":[{"appIDs":["TEAMID.app.haza.ios"],"components":[{"/":"/i/*"}]}]}}`.

## Pre-flight checklist (from the guidelines text in the research brief)
- [ ] Sign in with Apple shown first (4.8) · [ ] Account deletion works end-to-end (5.1.1 v)
- [ ] Every permission string explains the feature (5.1.1) · [ ] Background modes justified: location, push-to-talk, audio, remote-notification, bluetooth-central (2.5.4)
- [ ] No speed rankings anywhere; App Store text says so (1.4.4/1.4.5)
- [ ] Recording indicator: system PTT UI + in-app "Talking" state (2.5.14)
- [ ] Privacy manifest present; nutrition labels match (App Privacy)
- [ ] Subscription terms in the description and paywall; restore purchases button (3.1.2)
- [ ] Two reviewer accounts that are already friends, with a crew and one plan
- [ ] Privacy policy and terms pages live at the URLs above
