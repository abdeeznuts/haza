# Haza — The Mac Phase (everything you deliberately left for the end)

You said "avoid doing Mac things" — so here is the complete list of what only a Mac (or a rented cloud Mac) can do, in order. Budget: a focused weekend for build + device tests, then waiting on Apple.

## 0. Accounts (can be done from any computer)
1. Apple Developer Program — $99/yr, enroll at developer.apple.com (needs your legal name/ID; D-U-N-S only if enrolling as a company).
2. LiveKit Cloud — create a project (free Build plan), copy `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`.
3. In Apple Developer → Keys: create an APNs key (.p8). Note Key ID and Team ID.
4. Download Apple Root CA - G3 from https://www.apple.com/certificateauthority/ → `openssl x509 -inform der -in AppleRootCA-G3.cer -out root.pem`.
5. Supabase → project `pace` → Edge Functions → Secrets: add `LIVEKIT_*`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY` (.p8 contents), `APNS_BUNDLE_ID=app.haza.ios`, `APNS_ENV=sandbox`, `APPLE_ROOT_CA_G3_PEM` (root.pem contents), `PUSH_WEBHOOK_SECRET` (value in backend/README.md).
6. Supabase → Authentication → Providers → Apple: enable, add your Services ID / bundle id (native Sign in with Apple only needs the bundle id).
7. Domain + site: buy the domain for the final name, then deploy the `site/` folder to Cloudflare Pages or Netlify (free, drag-and-drop). It already contains the landing page, `/i/<code>` invite page, privacy policy, terms, support, `_redirects`, and `/.well-known/apple-app-site-association` — replace `TEAMID` and `APPSTORE_ID_HERE` and the `DATE_HERE` effective dates.

## 1. Build (Mac)
1. Install Xcode 26 from the App Store; `brew install xcodegen`.
2. `cd ios && xcodegen generate` → `Haza.xcodeproj`. Open it.
3. Set your Team on all three targets (Haza, HazaWidgets, HazaWatch). Register the App ID `app.haza.ios` with capabilities: Push Notifications, Push to Talk, Sign in with Apple, Associated Domains, App Groups (`group.app.haza`), Background Modes.
4. Let SwiftPM resolve supabase-swift and livekit client-sdk-swift.
5. Build. Expect a small number of compile fixes — the code was written and syntax-checked without an Apple SDK. LiveKit `mixer.capture(appAudio:)` and `audioSession.isAutomaticConfigurationEnabled` are confirmed against LiveKit's Docs/audio.md; supabase-swift `channel`/`subscribe`/`broadcast(event:message:)`/`broadcastStream(event:)` against the Swift reference. The one spot still unverified: `Product.SubscriptionOffer.period` formatting in `PaywallView` (cosmetic).
6. Add a StoreKit configuration file (Products: the two subscription IDs) for local purchase testing.
7. Add an app icon (1024 px) to `Assets.xcassets/AppIcon`; add an optional `TalkChannel` image for the PTT system UI.

## 2. Device tests (real iPhone + Watch; simulator can't do PTT/BLE)
- Push to Talk: join, hold, system UI on Lock Screen, second device receives the `pushtotalk` push (APNS_ENV=sandbox for dev builds).
- Steering-wheel play/pause keys the mic in a CarPlay car or the CarPlay Simulator (Additional Tools for Xcode).
- Valentine One Gen2: pair, see the panel follow the detector, Ka alert pin appears for a friend.
- Watch: hold on the watch → friend hears you; incoming talk taps the wrist.
- Background drive: drive 5 minutes with the app closed; the drive appears; the Live Activity shows on the Lock Screen and (iOS 26 car) the CarPlay Dashboard; the widget shows on the Dashboard.
- Referral: second account claims the first's code, completes a 1-mile drive, both get Pro time.

## 3. Ship
1. Archive → App Store Connect → TestFlight. Invite 5–10 friends (car people) for a week.
2. Flip `APNS_ENV` to `production` for the store build; set the App Store Server Notification URLs.
3. Fill App Store Connect from docs/04 (metadata, IAP, privacy labels, reviewer notes, screenshots).
4. Submit. Separately, file the CarPlay entitlement request (docs/04) — the app ships without it.

## No Mac? Options that work without owning one
- Rent a cloud Mac by the hour/day (MacStadium, MacinCloud, AWS EC2 Mac) for the build/archive steps; device tests still need your iPhone connected to that Mac over the network (Xcode supports wireless devices on the same LAN — only practical with a local Mac). Borrowing a friend's Mac for one weekend is the honest answer for the device tests.
- Xcode Cloud can build and upload to TestFlight from a Git repo once the project exists, but the first `xcodegen generate` + signing setup still needs a Mac session.
