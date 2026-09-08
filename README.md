# Haza — social drive tracker with a walkie-talkie

| Folder | What's inside | Verified how |
|---|---|---|
| `docs/` | 01 research brief (sources), 02 product spec, 03 design system, 04 App Store kit, 05 architecture, 06 Mac checklist, 07 GitHub/free tools, 08 launch plan | every claim linked to its page |
| `prototype/pace.html` | tappable iPhone prototype (published as an artifact) | rendered + screenshot |
| `backend/` | Supabase schema/migrations, RLS, RPCs, cron; edge functions (`livekit-token`, `ptt-notify`, `iap`) | applied to the live project; SQL smoke test; Deno JWS test |
| `ios/` | XcodeGen project: Haza app, HazaWidgets, HazaWatch, `Packages/HazaCore` | HazaCore: 16 tests pass on Linux; all 29 app files parse with swiftc |
| `site/` | landing page, invite page (`/i/<code>`), privacy, terms, support, Apple app-site-association — deploy to Cloudflare Pages/Netlify | static |
| `.github/workflows/` | iOS build check on GitHub's free macOS runners; manual TestFlight upload | — |
| `android/` | phase-2 notes | — |

Start with `docs/06-mac-checklist.md` when you have a Mac. App Store listing name: "Haza — Drive Together" (`docs/02` §10).
