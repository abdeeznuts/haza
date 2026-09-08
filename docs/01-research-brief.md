# Haza — Research Brief (verified sources only)

Date: September 7, 2026. Every claim below was read from the linked page. Anything I could not confirm is in the "Not verified" list at the end — nothing in this brief is guessed.

## 1. Wheelz (the app you're modeling)

Facts from the App Store listing and the developer's site:

- App: "Wheelz - Social Drive Tracker", seller Vortac Labs Inc., bundle `com.gigamow.Wheelz`, category Navigation (also Utilities), 4+, requires iOS 18.0+, 288.5 MB. Released June 2, 2026; version 4.4 on Sept 1, 2026; 2,925 ratings at 4.74 average. Source: https://apps.apple.com/us/app/wheelz-social-drive-tracker/id6774287184
- Pro pricing shown in the App Store "In-App Purchases" block: Wheelz Pro 1 Week $2.99, 1 Month $4.99, 1 Year $39.99. (The description text still says $4.99 / $9.99 / $49.99 — the IAP block is the live price list.) Same source.
- What it does (developer's own words): automatic trip detection in the background, live drive view with speedometer, trip breakdowns, timeline, a garage of your real cars, "premium dark map aesthetic". Same source.
- Website feature list: automatic drive tracking, drive history timeline, Friends ("Send a link, they tap accept"), Live convoys ("everyone in it appears live on the same map"), 3D garage (300+ cars), stats. Free tier: last 30 days of history, three starter cars. Premium: unlimited history, all cars, lifetime stats, unlimited friends and convoys, no ads. Source: https://wheelz.club/features and https://wheelz.club/premium
- Review-risk signal: the iOS description says "Wheelz does not promote speeding or dangerous activity … Our leaderboards do not contain speed related metrics." The Google Play description still advertises "top speed, average speed … speed leaderboards" but adds "Leaderboards do not display speed." Sources: App Store listing above; https://play.google.com/store/apps/details?id=com.gigamow.Wheelz
- Android version exists (Google Play, 4.9 with 1.02K reviews, updated Sep 4, 2026). Source: Play listing above.
- No Apple Watch or CarPlay support is listed on the App Store page (supportedDevices contains no Watch entries; no CarPlay mention).
- Referral program: I could NOT find any public description of a "friends join through your link → Pro" mechanic for Wheelz. Its site only describes friend-invite links. Treat the referral-unlock idea as your own feature, not a copy.

Screenshots (viewed): dark map, tabs Drives / Friends / Stats / Trophies, friend rows show "Driving now" with a 3D car, stats show total distance, top speed, "Longest drive", heatmap of drives, "1 Million+ drives tracked" badge.

### Names — what was checked
- **Pace** (first codename): an app called **"PACE - Drive with friends"** (seller Emanuel Berger, category Travel, iOS 18.1+, in-app purchases $3.99–$39.99 "PACE Pro Access", 4 ratings, v1.0.5) already does almost the same thing (speedometer, trip stats, friends, groups, leaderboards, 0–60 timer). Source: https://apps.apple.com/us/app/pace-drive-with-friends/id6761122094 — rejected.
- **Cruz**: live U.S. trademark CRUZ (Reg. 5751568, Carsforsale.com, Inc., class 9 "mobile application that provides access to an online vehicle marketplace") plus "Cruz App" and "Cruz: Ride with Cruz" on the App Store. Sources: https://trademarks.justia.com/867/70/cruz-86770740.html , https://apps.apple.com/us/app/cruz/id6748697022 , https://apps.apple.com/us/app/cruz-ride-with-cruz/id6736480995 — rejected.
- **Ryde**: eight or more RYDE ride-hailing apps (including RYDE Houston) and trademark RYDE Reg. 5325181. Sources: https://apps.apple.com/us/app/ryde-houston/id1484620543 , https://trademarks.justia.com/871/35/ryde-87135184.html — rejected.
- **Haza** (chosen Sep 7, 2026, short for "hazard"): one existing App Store app, **"Haza - Group Voice Chat Rooms"** (seller TAALA PTE. LTD., Social Networking, iOS 14+, 16 ratings) — a live group voice-chat app. Source: https://apps.apple.com/us/app/haza/id6450698630. No U.S. trademark for HAZA was found in web searches (not a legal clearance). Because the existing app is also voice-based, list the app as **"Haza — Drive Together"** (App Store names must be unique; the suffix also separates it in search) and run a USPTO search before spending on branding.

### Adjacent apps (from Wheelz's "You might also like" and Zello)
- Enroad – Drive Tracker (6.7K ratings), Velox: Drive, Convoy, Explore ("Social driving & convoys", 42 ratings), Open Road: Speed Tracker GPS (788), Uniden R/TACH (56), ROADS by Porsche. Source: Wheelz App Store page, similar-items shelf.
- Zello (push-to-talk, 150M users claim, Business category, iOS 17+) has **no Apple Watch app** — reviewers explicitly ask for one. Source: https://apps.apple.com/us/app/zello-walkie-talkie/id508231856

## 2. Apple platform capabilities (what is actually possible)

### Push to Talk framework (iPhone walkie-talkie) — YES
- "PTT provides the interface, and you provide the back-end communication service." Apps "implement their own audio encoding and streaming process to transmit audio between users." Source: https://developer.apple.com/documentation/pushtotalk/creating-a-push-to-talk-app
- Setup: Background Modes → Push to Talk; Push to Talk capability; Push Notifications; `NSMicrophoneUsageDescription`. Only one PTT channel can be active on the system at a time. "A person can only join a channel when a PTT app is running in the foreground — with explicit user interaction." Same source.
- Incoming audio: APNs push type `pushtotalk`, topic `<bundle id>.voip-ptt`, priority 10, expiration 0; system wakes the app and calls `incomingPushResult`. Same source.
- Car relevance: "The system automatically interprets play or pause toggle events from wired headsets and CarPlay devices when the system has an active PTT channel. Events result in begin- or end-transmission events." Same source. (So a steering-wheel play/pause button can key the mic.)
- Entitlement `com.apple.developer.push-to-talk` availability: iOS 16.0+, iPadOS 16.0+ only. Source: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.push-to-talk
- Not available to compatible apps running in visionOS. Source: https://developer.apple.com/documentation/pushtotalk

### Apple Watch walkie-talkie — POSSIBLE, but not with the PTT framework or LiveKit on the watch
- The PTT framework and its entitlement exist only on iOS/iPadOS (source above).
- watchOS 9 added CallKit VoIP support so "users will be able to start, end, or mute VoIP calls from the Apple Watch in supported apps like Webex." Source: https://www.macrumors.com/2022/06/07/apple-watch-voip-calling-watchos-9/
- LiveKit's Swift SDK does **not** support watchOS: the watchOS support request (Jan 3, 2024) was closed as "not planned" / "wontfix". Source: https://github.com/livekit/client-sdk-swift/issues/288 ; SDK targets iOS, macOS, tvOS, visionOS: https://github.com/livekit/client-sdk-swift
- Design consequence (my architecture, built on the facts above): the Watch app records while you hold the button and streams the audio chunks to the paired iPhone over WatchConnectivity; the iPhone injects them into the LiveKit room and shows the system PTT UI. Incoming talk is mirrored to the watch as short clips + haptics. This must be validated on real hardware (Mac-phase item).

### CarPlay — the "widget" you asked for is now a real thing (iOS 26)
From Apple's CarPlay Developer Guide (dated 2026-06-08): https://developer.apple.com/carplay/ (PDF "CarPlay App Programming Guide")
- "Widgets appear to the left of CarPlay Dashboard … and support interaction on touchscreen vehicles. Your app does not need to be a CarPlay app to support widgets. Widgets are supported in CarPlay Ultra, and with iOS 26 in CarPlay." Enable with `.supportedFamilies([.systemSmall])`.
- "Live Activities are shown in CarPlay Dashboard, or as a notification. Your app does not need to be a CarPlay app to support Live Activities in CarPlay. Live Activities are supported with iOS 26 in CarPlay and CarPlay Ultra." Enable with `.supplementalActivityFamilies([.small])` — "If you already support Apple Watch, the same Live Activity will work in CarPlay."
- "Your widget can only launch your app in CarPlay if your app is also a CarPlay app."
- Full CarPlay apps require a category entitlement requested at http://developer.apple.com/carplay ("Apple will review your request"). Categories: Audio, Communication (SiriKit Messaging or VoIP Calling), Driving task, EV charging, Fueling, Navigation, Parking, Public safety, Quick food ordering, Video, Voice-based conversational. Entitlement keys: `com.apple.developer.carplay-communication` (iOS 14), `com.apple.developer.carplay-driving-task` (iOS 16).
- Rules that shape Haza's CarPlay scene: "Communication apps that provide VoIP calling features must support CallKit, and … INStartCallIntent." Driving task apps: "Do not periodically refresh data items in the CarPlay UI more than once every 10 seconds (for example, no real-time engine data)"; "No gaming or social networking"; "Never show the content of messages"; templates only.
- HIG confirms the System small widget runs in "Home Screen, Today View, StandBy, and CarPlay" on iPhone. Source: https://developer.apple.com/design/human-interface-guidelines/widgets

So: the walkie-talkie toggle + speed stats widget ships as an **interactive WidgetKit systemSmall widget** (no entitlement needed), the drive itself is a **Live Activity** that shows on the Dashboard, and the full CarPlay app (contact list to ping/start a talk) is a **Communication-category** CarPlay app that you apply for.

### Widgets, Live Activities, Controls
- Controls (iOS 18): "A control is a button or toggle that provides quick access to your app's features from other areas of the system" — Control Center, Lock Screen, Action button. Source: https://developer.apple.com/design/human-interface-guidelines/controls (used for the "Talk" toggle)
- Live Activities HIG and Widgets HIG (interactivity via buttons/toggles in widgets): https://developer.apple.com/design/human-interface-guidelines/live-activities , https://developer.apple.com/design/human-interface-guidelines/widgets

### App Store Review Guidelines that decide approval (exact text)
Source: https://developer.apple.com/app-store/review/guidelines/
- 1.4.4: "Apps may only display DUI checkpoints that are published by law enforcement agencies, and should never encourage drunk driving or other reckless behavior such as excessive speed."
- 1.4.5: "Apps should not urge customers to participate in activities (like bets, challenges, etc.) or use their devices in a way that risks physical harm to themselves or others."
- 2.5.4: "Multitasking apps may only use background services for their intended purposes: VoIP, audio playback, location, task completion, local notifications, etc."
- 2.5.14: "Apps must request explicit user consent and provide a clear visual and/or audible indication when recording … This includes any use of the device camera, microphone…"
- 3.1.1: "If you want to unlock features or functionality within your app … you must use in-app purchase. Apps may not use their own mechanisms to unlock content or functionality, such as license keys…"
- 3.1.2(a): auto-renewable subscriptions "must provide ongoing value … the subscription period must last at least seven days and be available across all of the user's devices."
- 4.8: apps using third-party/social login "must also offer as an equivalent option another login service" that limits data to name and email and lets users hide their email (Sign in with Apple satisfies this).
- 5.1.1(v): "If your app supports account creation, you must also offer account deletion within the app."
- 5.1.5: "Use Location Services in your app only when it is directly relevant to the features and services provided by the app… Ensure that you notify and obtain consent before collecting, transmitting, or using location data."
- 5.6.3: "Manipulating any element of the App Store customer experience such as charts, search, reviews, or referrals to your app erodes customer trust and is not permitted."

Design consequences: no top-speed leaderboards or speed challenges (1.4.4/1.4.5); Pro unlock only via StoreKit (3.1.1) — the referral reward is a *server-side free Pro period*, never a code that unlocks paid features; Sign in with Apple as the first login option (4.8); in-app account deletion (5.1.1); recording indicator during talk (2.5.14).

### Fonts
- Apple ships SF Pro / SF Compact (sans) and New York (serif): "New York (NY) is a serif typeface family designed to work well by itself and alongside the SF fonts." Source: https://developer.apple.com/design/human-interface-guidelines/typography and https://developer.apple.com/fonts/

## 3. Radar detectors — who can actually be connected

| Brand | Connectivity | Third-party access | Source |
|---|---|---|---|
| Valentine One Gen2 | Built-in Bluetooth ("Bluetooth is now built in to the V1 Gen2") | **Open**: "an open API. This allows third party developers to design apps and accessories that directly communicate with the V1." Valentine publishes the ESP spec (Rev 3.016, Aug 2026) and MIT-licensed iOS/Android ESP libraries; developer contact v1developer@valentine1.com | https://www.vortexradar.com/2020/05/valentine-1-gen2-review/ ; https://github.com/ValentineResearch ; ESP spec PDF from valentine1.com |
| Uniden R4/R4w/R8/R8w/R9/R9w | Bluetooth (pairing mode on the detector) | Uniden's own free "R/TACH" app; **no public API found** | https://www.vortexradar.com/2024/11/uniden-rtach-radar-detector-app/ ; https://uniden.com/pages/rtach-app |
| Escort Max 360c / Redline 360c / Max 3 | Escort's "Drive Smarter" app, which itself integrates with Apple CarPlay and Android Auto | **No API/SDK/partner program published** on Escort's page | https://www.escortradar.com/pages/drive-smarter-app |

What I built: a real Valentine ESP implementation (framing, checksum, `respAlertData`, `infDisplayData`, BLE service `92A0AFF4-9E05-11E2-AA59-F23C91AEC05E`, chunking per the BLE addendum). For Escort and Uniden the app ships a "coming soon / request access" state and a partner-request email template — connecting them requires their cooperation or reverse engineering, which I did not do.

ESP protocol facts used in code (from the spec): frame `AA, D0+dest, E0+origin, packetID, payloadLen, payload…, checksum, AB`; checksum is 8-bit sum of all preceding bytes; `respAlertData` ($43) payload = index/count byte, freq MSB/LSB (MHz), front strength, rear strength, band/arrow byte (bit0 Laser, 1 Ka, 2 K, 3 X, 4 Ku, 5 Front, 6 Side, 7 Rear), aux0 (bit7 priority, bit6 junk); `reqStartAlertData` $41, `reqStopAlertData` $42, `reqMuteOn` $34, `reqMuteOff` $35, `reqVersion` $01. Device IDs 3–5 are reserved for third-party devices. V1connection LE splits packets >20 bytes into indexed chunks (high nibble = index, low nibble = count).

Legality (the app shows this in onboarding): radar detectors are banned in passenger vehicles in Virginia (Code § 46.2-1079), Washington D.C., and on military installations; federally banned in commercial vehicles over 10,000 lbs (49 CFR 392.71). Source (last verified March 2026): https://www.vortexradar.com/2017/11/are-radar-detectors-illegal-or-legal-in-the-usa-radar-detector-laws/

## 4. Maps and places data

- Google's own terms: "Customer must not use Google Maps Content from the Places API in conjunction with a non-Google map" (Service Specific Terms §14.2). Lat/lng may be cached max 30 days; place IDs may be cached. Source: https://cloud.google.com/maps-platform/terms/maps-service-terms
- Google pricing (page updated 2026-09-01): free monthly cap 10,000 events for Essentials SKUs, 5,000 Pro, 1,000 Enterprise; Nearby Search Pro and Text Search Pro $32.00 per 1,000 above the cap; Place Details Essentials $5.00, Pro $17.00, Enterprise $20.00 per 1,000; Autocomplete $2.83 per 1,000; Dynamic Maps $7.00 per 1,000. Source: https://developers.google.com/maps/billing-and-pricing/pricing
- Decision: Haza uses **Apple MapKit** (native, no per-load cost, Look Around, MKLocalSearch POIs) as the map, so Google Places data is not used on it (would violate §14.2). Places come from MapKit search; an optional Google Places "detail card" (opened in its own sheet with Google attribution, on no map) can be added later without breaking the terms.

## 5. Backend and audio vendors

- Supabase Free plan: 500 MB database, 1 GB storage, 5 GB egress, 50,000 MAU, Realtime 200 concurrent peak connections and 2 million messages/month, 500,000 Edge Function invocations, 2 active projects, "Free projects are paused after 1 week of inactivity." Pro from $25/mo (500 realtime connections, 5M messages). Source: https://supabase.com/pricing
- LiveKit Cloud Build plan: $0/mo, 5,000 participant minutes, 100 concurrent connections, 50 GB downstream; Ship plan from $50/mo with 150,000 participant minutes. Source: https://livekit.com/pricing
- Firebase Dynamic Links shut down August 25, 2025 (links return 404; first-open attribution returns empty). Source: https://firebase.google.com/support/dynamic-links-faq — so referral attribution in Haza uses Universal Links + a server-issued invite code that survives install (clipboard/App Clip-free "enter code" fallback).
- Android Auto (phase 2): calling apps declare `androidx.car.app.category.CALLING`, must use the Telecom Jetpack library, Android Auto shows its own in-call view; "apps that support calling can only be published to Internal Testing and Closed Testing tracks on Google Play." Source: https://developer.android.com/training/cars/communication/calling

## Not verified (do not rely on these)
- Whether Wheelz has any referral-to-Pro program.
- Whether Escort or Uniden would grant API access on request (no public program found).
- Exact watchOS behaviour of streaming WatchConnectivity audio while the iPhone is in the background — needs a device test.
- Whether "Haza" (single word) is free as an App Store name; the "PACE - Drive with friends" listing strongly suggests you should rename.
