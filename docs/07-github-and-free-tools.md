# Building without a Mac: GitHub Actions, and what "free AI" can and can't do here

## The one thing that actually reduces load: let GitHub's Macs compile
GitHub-hosted macOS runners are real Macs with Xcode. Two workflows are included:

- `.github/workflows/ios-build.yml` — on every push: runs the HazaCore tests on Linux and builds the full Xcode project (app + widgets + Watch) for the iOS Simulator with signing disabled. If it goes green, the code compiles. If it goes red, the log names the exact line — paste it back to me and I fix it. No Mac involved.
- `.github/workflows/testflight.yml` — manual: archives and uploads to TestFlight once you add the signing secrets listed at the top of the file. This is the "rented Mac" step done by GitHub instead.

Verified pricing (docs.github.com, "About billing for GitHub Actions"): "The use of standard GitHub-hosted runners is free: In public repositories." GitHub Free includes 2,000 minutes/month for private repos, and macOS runners bill at $0.062/minute beyond the quota and consume it at a higher rate than Linux. Practical advice: make the repo **public** while you iterate (the code contains no secrets — the Supabase publishable key is meant to be public), or private and watch the minutes.

Setup from your laptop (Windows is fine):
1. Install Git (git-scm.com) and create a GitHub account.
2. `git init` in the `pace` folder → create a repo on github.com → `git remote add origin …` → `git push -u origin main`.
3. Actions tab → the build runs by itself. Green = compiles.

## What I can and can't do with "free AIs"
- This cloud session is not linked to your computer, so I can't install or run anything on your PC.
- "Free Claude / GPT" wrappers on GitHub are unofficial scrapers of someone else's account or key. They break, they violate the providers' terms, and several have shipped credential stealers. I won't route your project through them.
- Legitimate free options if you want a second pair of hands on the Mac-phase compile fixes: GitHub Copilot's free tier inside VS Code, or an open-weight model run locally with Ollama/LM Studio on your laptop. Both are yours to install; they don't need anything from me.
- GitHub Models (github.com/marketplace/models) gives free, rate-limited API access to some models with a GitHub token. It would not speed this project up — the remaining work is compiling and device testing, not text generation.

What actually burned your budget earlier was four parallel research agents. From here on: no subagents, the compiler does the checking, and I only spend tokens on fixes you paste back.
