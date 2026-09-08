# Run Haza on your iPhone — from a Windows laptop, no Mac, no developer account

Two halves: GitHub's free Mac servers **build** the app; **Sideloadly** on your laptop **installs** it on your iPhone with your normal Apple ID. Your friends install the same way. When you hand the project to the software house, they use their developer account and TestFlight instead (bottom of this page).

What you get with a free Apple ID: the whole app — map, friends, speed, drives with route playback, plans, crews, talk (in-app hold-to-talk over the same channel), pings and "plan is live" alerts (in-app banner, or a local notification while Haza runs in the background), radar, home intelligence, briefing. What waits for a paid developer signature: the Lock Screen / CarPlay walkie-talkie mode (Apple's Push to Talk entitlement), Home Screen widgets and Control Center control, push notifications when the app is fully closed, Sign in with Apple, the Apple Watch app, and `haza.app/...` links opening the app (the invite **code** works instead). Free Apple ID rules: the app stops opening after 7 days (re-install from Sideloadly, data is kept), max 3 sideloaded apps, and you need Developer Mode on.

## A. One-time: GitHub (10 minutes)

1. github.com → create a free account → **New repository** → name `haza`, **Public** (public = unlimited free Mac build minutes), no README → Create.
2. Get the code up. Either give the token to Claude (fastest — it pushes, runs the build, reads the errors and fixes them):
   - GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate. Repository access: *Only select repositories* → `haza`. Permissions: **Contents: Read and write**, **Actions: Read and write**, **Workflows: Read and write**. Copy the token and paste it in the chat. Delete the token when the build is green.
   - …or do it yourself: install **GitHub Desktop**, *File → Add local repository* → `Documents\Haza` → *Publish repository* (untick "keep private").
3. Repo → **Actions** tab → *iOS build* → **Run workflow**. Green tick after ~20 minutes. Open the run → **Artifacts** → download **Haza-ipa** (a zip with `Haza-sideload.ipa` and `Haza-full-unsigned.ipa`).

   First runs are expected to fail on compiler errors — the code has never been through Xcode. That is the loop Claude closes with the token: read log → fix → push → rerun.

## B. One-time: Supabase sign-in email (2 minutes, or say "do it from my laptop")

Email sign-in needs two dashboard settings (Sign in with Apple is not available on a free Apple ID):

1. supabase.com → project **pace** → Authentication → **URL Configuration** → Redirect URLs → add `haza://auth` → Save.
2. Authentication → **Email Templates** → *Magic Link* → put the code in the email body, e.g. add a line `Your code: {{ .Token }}` → Save.

Now the welcome screen's email box sends one email containing a link (opens the app) and a 6-digit code (type it in the app).

## C. One-time: laptop + iPhone (10 minutes)

1. Download **Sideloadly** from sideloadly.io (Windows). Install what its installer/FAQ asks for (Apple's iTunes and iCloud).
2. iPhone: Settings → Privacy & Security → **Developer Mode** → on → restart when asked.
3. Plug the iPhone in with a cable, tap **Trust** on the phone.

## D. Every install (3 minutes)

1. Open Sideloadly, drag `Haza-sideload.ipa` in, type your Apple ID email, press **Start**, enter your Apple ID password (or an app-specific password from appleid.apple.com if it asks) and the 2-factor code.
2. iPhone: Settings → General → **VPN & Device Management** → your Apple ID → **Trust**.
3. Open Haza. Allow Location (choose **Always** when the briefing asks), Microphone, Bluetooth, Motion, Notifications.

Repeat step D every 7 days (Sideloadly can also refresh over Wi-Fi once the phone is known).

## E. Friends

Same laptop, same file: they type *their* Apple ID into Sideloadly (their app, their certificate). Or they install Sideloadly on their own PC/Mac. Then: sign in with email → paste your invite code on the welcome screen (Profile → Your invite → Copy/Share) → you're friends instantly, both on the map, both in the crew channel.

## F. What to check on the first drive together

Two phones, two Apple IDs, both signed in and friends. Map: both cars visible, speed readouts. Talk: Join → hold. Ping: from the map chip. Plans: create one, the other RSVPs, creator taps Go live. Drives: leave the car parked 3+ minutes after driving → the drive appears. Radar tab pairs a Valentine One Gen2 if someone has one. Home: after a few nights the briefing suggests your home; or set it by address.

## G. Handing it to the software house

Send them the GitHub repo link (or `Documents\Haza`). They: `brew install xcodegen`, `cd ios && xcodegen`, set their Team in Signing, tick Push to Talk / App Groups / Sign in with Apple / Push Notifications / Associated Domains, and follow `docs/06-mac-checklist.md` → TestFlight. Their TestFlight build is the one where the Lock Screen walkie-talkie, Watch app, widgets and pushes switch on — no code changes needed, the app detects its own entitlements.
