# Android (phase 2)

Same backend, Kotlin + Jetpack Compose. Notes from the research (docs/01):
- Android Auto: calling apps declare `androidx.car.app.category.CALLING`, must use the Telecom Jetpack library, and Android Auto shows its own in-call UI. Google currently limits calling apps to Internal/Closed testing tracks, so the Android Auto walkie-talkie should be planned as a closed beta first. A Driving/POI-style "Haza" Android Auto app (crew status, next meet) can ship publicly.
- Supabase has a Kotlin SDK (auth, PostgREST, Realtime); LiveKit has an Android SDK. The RPCs and Realtime topics are identical to iOS (see backend/README.md).
- Wear OS: same PCM-relay design as watchOS is possible via the Data Layer API.
