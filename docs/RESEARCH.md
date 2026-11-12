# iOS sideload research — One Piece TV (Nov 2026)

Verified from current guides/pages (Nov 2026). No App Store, no
TestFlight — direct sideload only, as the user chose.

## 1. The sideload path (free Apple ID)

Sideloading = installing an .ipa signed with your own certificate
instead of the App Store. It is **not jailbreaking**.

A **free Apple ID** ("personal team") has hard Apple limits that every
tool inherits — they are not bugs in any one tool:

| Limit | Free Apple ID |
|---|---|
| Certificate validity | **7 days** — the app stops opening unless re-signed |
| Apps at once | **3 sideloaded apps** |
| New App IDs | ~10 per rolling week |
| Push notifications / in-app purchases | Not available |

Developer Mode must be on (iOS 16+): Settings → Privacy & Security →
Developer Mode. Works on current iOS (26/27 era); Sideloadly lists
support up to iOS 26 "and future versions".

### Tools (all free, all sign with your own Apple ID)

| Tool | Needs a computer? | How re-signing works |
|---|---|---|
| **AltStore** | Mac/PC with AltServer, must stay on same Wi-Fi | AltServer refreshes apps over Wi-Fi automatically while the computer is awake on the same network |
| **SideStore** (fork of AltStore) | **One-time PC pairing only** | On-device VPN (StikDebug / LocalDevVPN) + pairing file refreshes signatures straight from the iPhone — no computer after setup. Recommended free pick in 2026 guides |
| **Sideloadly** | Windows/Mac every install | Desktop app, drag the .ipa in, sign with Apple ID; auto-refresh daemon needs the computer on + phone on same Wi-Fi or USB |

**Recommendation for this user: SideStore.** He travels (Egypt Nov 26 –
Mar 15) and will not have a Windows PC on the same Wi-Fi as the phone
for months; SideStore's on-device refresh is the only free option that
keeps working without a computer. AltStore is the simpler fallback if
he keeps a PC on at home. Sideloadly is the easiest one-off install
(good for the very first install from his Windows PC).

**Avoid:** "free enterprise certificate" signing services — shared
certificates Apple revokes in waves with no warning; every app signed
with one dies at once. Also avoid any service asking for the Apple ID
password outside Apple's own sign-in.

### What the user needs on his side

- iPhone 16 Pro Max (iOS 18/26) — target device, confirmed.
- A free Apple ID (any Apple ID works; the one already on the phone).
- Developer Mode ON.
- For first install: SideStore's one-time PC pairing (any Windows PC
  + USB cable), OR Sideloadly on a Windows PC, OR AltServer on a PC.
- After that (SideStore): nothing but the phone itself; refresh happens
  on-device. The app must be re-signed at least once every 7 days or
  it stops opening (data/login inside the app is preserved across
  re-signs — re-signing is not reinstalling).

### Paid Apple Developer Program ($99/yr) — what it changes

- Certificate lasts **1 year** instead of 7 days; the 3-app cap goes away.
- Same tools (AltStore/SideStore/Sideloadly) work with it.
- It ALSO unlocks App Store Connect API-key signing on CI (signed IPA
  straight from the cloud build) — but the user chose sideload-only,
  so this is optional, not required. Only worth it if the weekly
  re-sign chore gets annoying during the 4-month Egypt stay.
- No Apple Developer account is created or needed for the free path.

## 2. Cloud build without a Mac

The IPA is built on GitHub's macOS runners (free for public repos):

- **GitHub Actions, `macos-26` runner, Xcode 26.x pinned** — see
  `.github/workflows/ios-build.yml`. The workflow builds with
  `CODE_SIGNING_ALLOWED=NO` and packages an **unsigned .ipa**.
  The user signs it on his own computer/phone with his own Apple ID
  (AltStore/SideStore/Sideloadly). **No Apple credentials go into
  GitHub at all** — no Apple ID, no password, no .p8, no certificate.
- Cost: $0 on a public repo (macOS minutes free). On a private repo,
  macOS minutes are billed (~$0.062/min, ~5–8 min per build).
- Xcode 26 note: since 28 Apr 2026, App Store uploads must be built
  with Xcode 26+ / iOS 26 SDK. That rule is for App Store Connect
  uploads only — it does not apply to a sideloaded unsigned IPA — but
  the workflow pins Xcode 26.x anyway so the toolchain never drifts.

**Codemagic (alternative, not used here):** 500 free M2 minutes/month
on personal accounts, then $0.095/min. It can build the same unsigned
IPA, and with a paid Apple Developer account it can sign it too. The
GitHub path was chosen because it is $0 with no account signup beyond
GitHub, and the project has zero external dependencies (no pods), so
the build is one `xcodebuild` call.

## 3. What the user must supply before a first installable IPA

1. **Nothing yet for the build itself.** The CI build needs no Apple
   credentials (unsigned IPA).
2. **To install:** his Apple ID + password, typed by HIM into
   AltStore/SideStore/Sideloadly on his own PC/phone — never sent to
   us, never stored anywhere by us.
3. **To push the code to GitHub** (parent's step): a GitHub repo
   (public = free macOS minutes) containing this project folder.
4. **On the iPhone:** Developer Mode ON; the EN→AR translation pack
   + an Arabic voice downloaded for dubbing (Settings → Translation /
   Accessibility → Spoken Content), only if he wants dubbing.
5. **If he later wants the $99/yr path** (1-year cert, no weekly
   re-sign): he enrolls in the Apple Developer Program himself in a
   browser; then CI signing can be switched on with an App Store
   Connect API key (collected via secure entry, never in chat).

Sources: builds.io sideloading guides (2026), anazhd.com
("Mobile dev is getting ridiculous", Oct 2026, ipa-builder pattern),
macrun.dev / choicely.com / newly.app (2026, Xcode 26 + pricing),
GitHub Actions macOS runner docs as cited in those guides.
