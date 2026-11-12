# One Piece TV — iOS (iPhone 16 Pro Max, sideload only)

SwiftUI port of the Android app (`~/workspace/parts-android/iptv/`,
package `com.maro.iptv`, currently v4.24). **Direct sideload only —
no App Store, no TestFlight**, per the user's choice.

Target device: **iPhone 16 Pro Max** (modern iOS 18/26).
Deployment target: **iOS 17.0**. Zero external dependencies (no
CocoaPods, no SPM packages) — pure Apple frameworks, so the cloud
build is a single `xcodebuild`.

## What is in this scaffold

| Feature | Status | Notes |
|---|---|---|
| Xtream Codes login + M3U URL | ✅ built | Same `player_api.php` endpoints and stream-URL shapes as Android. Passwords in **Keychain only**; never in UserDefaults/chat |
| Built-in free card (iptv-org M3U) | ✅ built | `https://iptv-org.github.io/iptv/index.m3u`, no login — same as Android `builtin-free` |
| Live TV by category + logos | ✅ built | Category chips with counts; `AsyncImage` logos |
| Smart search + live suggestions | ✅ built | Exact port of Android v4.19: `foldAr`, AR/EN word map, Levenshtein + subsequence fuzzy match, score 2 exact / 1 fuzzy, 30 suggestions |
| Private list «قايمتي» | ✅ built | Favorite / rename / hide / move up-down / move-to-number / reset order, saved per list key (`ord_<key>`, v2) |
| Nilesat bundle «🛰️ باقة النايل سات» | ✅ built | Exact port of Android v4.14/v4.17/v4.20: veto-first `isNilesat`, grouped order كرتون، ناشونال جيوجرافيك، أفلام عربية، مسلسلات عربية، أفلام أجنبية، مسلسلات أجنبية، أخبار، كورة، الباقي |
| Movies + series library | ✅ built | Xtream VOD + series, `get_series_info` seasons/episodes, `get_vod_info` |
| Anime section, One Piece pinned first | ✅ built | Same name keys as Android v4.5; filters الكل / منتهي / مستمر / متوقف / قديم / جديد; status from provider category, user override, or 180-day episode gap |
| Playback (AVPlayer, HLS) | ✅ built | Fullscreen, tap-to-zap (prev/next in the opened list), EPG strip (`get_short_epg`), `.ts` → `.m3u8` retry, 10s auto-hide bars |
| Live dubbing | ⚠️ scaffolded, **not verified** | Pipeline written: `MTAudioProcessingTap` → on-device EN speech recognition → Translation framework EN→AR (iOS 18+) → `AVSpeechSynthesizer` Arabic; original muted while dubbing, stays off when any stage is missing (same rule as Android). **NOT compiled (no Xcode on this VM) and NOT device-tested — needs an on-device pass.** Android uses Vosk + ML Kit; iOS uses Apple Speech + Translation instead (same interface, swappable later) |
| Dish / USB tuner «📡 الدش» | ❌ intentionally absent | Impossible on iOS — no USB DVB host access, no TV Input Framework |
| Settings | ✅ built | Language AR/EN (RTL flips automatically), dubbing toggle, accounts, about |

## Build (unsigned IPA, $0)

1. Push this folder to a **public** GitHub repo (public = free macOS
   minutes; private repos bill ~$0.062/min).
2. The workflow `.github/workflows/ios-build.yml` runs on push or
   manually: builds Release with signing disabled on `macos-26`
   (Xcode 26.x pinned), strips residual signatures, uploads
   `OnePieceTV-unsigned.ipa` as an artifact (30 days).
3. No Apple credentials are needed in CI — the IPA is unsigned.

## Install on the iPhone (user's step)

See `docs/RESEARCH.md` for the full verified picture. Short version:

1. On the iPhone: Settings → Privacy & Security → Developer Mode ON.
2. First install: **SideStore** (one-time PC pairing, then on-device
   refresh — best for the 4-month Egypt stay) or **Sideloadly** /
   **AltStore** from a Windows PC. Sign in with his own free Apple ID
   **in that tool on his own machine** — never share the password.
3. Re-sign at least every **7 days** (free Apple ID cert expiry) or
   the app stops opening. SideStore can refresh on-device automatically.
4. Optional later: Apple Developer Program ($99/yr) → 1-year cert,
   no 3-app cap, no weekly chore.

## Project layout

```
OnePieceTV.xcodeproj/        hand-written Xcode project (no Mac here)
OnePieceTV/
  OnePieceTVApp.swift        entry: login until an account is selected
  Models.swift               Channel / VodItem / Episode / accounts / L()
  Search.swift               foldAr, smartFold, fuzzy match (Android v4.19)
  Nilesat.swift              isEgyptian / isNilesat / grouping (v4.14/17/20)
  XtreamAPI.swift            player_api.php client + M3U parser
  Store.swift                state, Keychain passwords, lists, orders
  Dubbing.swift              live-dubbing pipeline (see status above)
  PlayerView.swift           AVPlayer fullscreen + zap + EPG
  HomeView.swift             categories, grid, search, private list
  LibraryView.swift          movies / series / anime + series detail
  LoginView.swift            Xtream + M3U + free card + saved accounts
  SettingsView.swift         language, dubbing, accounts, about
  Assets.xcassets/           straw-hat icon (from Android play-listing)
.github/workflows/ios-build.yml
docs/RESEARCH.md
```

## Known gaps / next steps

1. **First CI build has never run** — no Xcode on this VM. Push to
   GitHub and run the workflow; fix whatever it reports (most likely
   candidates: the hand-written `project.pbxproj`, and the
   `MTAudioProcessingTap` callback signatures in `Dubbing.swift`).
2. **Dubbing needs an on-device test** (tap audio actually arrives,
   on-device EN recognition works on a live stream, AR pack present).
3. **No offline VOD downloads yet** (Android v4.17 has them) — add
   later with `AVAssetDownloadTask` if wanted.
4. **No crash reporting** wired (Android posts to the onepiece-crashes
   worker) — add later.
5. iPhone model / iOS version confirmed: **iPhone 16 Pro Max**;
   exact iOS version still unknown — assume current (18/26).
