<div align="center">

<img src="https://nyora.pages.dev/icon.png" width="120" alt="Nyora" />

# Nyora — iOS

### Read like the world can wait.

A fast, free, ad-free, open-source manga / manhwa / manhua reader for **iPhone & iPad** — part of the cross-platform [Nyora](https://nyora.pages.dev) series. Hundreds of sources, an in-reader translation overlay, and your library synced across every device you read on.

<p>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-0055FF?style=for-the-badge&logo=swift&logoColor=white" />
  <img alt="iOS 15+" src="https://img.shields.io/badge/iOS-15%2B-000000?style=for-the-badge&logo=apple&logoColor=white" />
  <img alt="Version 2.1.0" src="https://img.shields.io/badge/version-2.1.0-FF4655?style=for-the-badge" />
</p>

<p>
  <a href="./LICENSE"><img alt="License: GPLv3" src="https://img.shields.io/badge/license-GPLv3-blue.svg" /></a>
  <a href="https://github.com/Hasan72341/nyora-ios/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/Hasan72341/nyora-ios?style=social" /></a>
</p>

<p>
  <a href="https://nyora.pages.dev"><img alt="Website" src="https://img.shields.io/badge/Website-nyora.pages.dev-FF4655?style=for-the-badge&logo=githubpages&logoColor=white" /></a>
  <a href="https://github.com/Hasan72341/nyora-ios/releases/latest"><img alt="Download IPA" src="https://img.shields.io/badge/Download-.ipa-5A0FC8?style=for-the-badge&logo=apple&logoColor=white" /></a>
</p>

**No App Store, no ads, no sign-up wall.** Sideload the `.ipa` and start reading.

</div>

---

## About

**Nyora for iOS** is the iPhone / iPad edition of Nyora, built on the excellent open-source [**Aidoku**](https://github.com/Aidoku/Aidoku) reader (GPLv3) and rebuilt around the Nyora ecosystem. The device does **zero parsing** — it talks to the hosted **Nyora helper** (`api.nyora.xyz`, powered by the [Kotatsu](https://github.com/KotatsuApp/kotatsu) parser engine), so every source in the catalogue is available without bundling fragile parsers into the app. Sign in with a **Nyora Cloud** account (email + password) and your library, history and reading progress follow you to every other Nyora platform; or just continue as a guest and read — no account required.

It shares the Nyora design language with the Android app — an indigo → magenta accent, Poppins type, a Discover home with trending rails, and a modern reader — so it feels like one product across every device.

## Features

- 📚 **960+ sources** (363 health-checked working) — install any source from the catalogue; browse Popular / Latest, search, and read
- 🈳 **In-reader translation overlay** — a toggle, not baked-in: **Google**, on-device **Apple Intelligence** (iOS 26), or **bring-your-own-key** (any OpenAI-compatible endpoint) — with per-page OCR + bubble detection
- ☁️ **Nyora Cloud sync** — one library across Android, iOS/iPadOS, macOS, Windows, Linux & Web. Sign in with **email + password** against the self-hosted **Nyora Cloud** backend (`sync.nyora.xyz`, OAuth2 + JWT) — no Google account, no third-party service — or **continue as guest**
- 🎨 **Nyora design** — Discover home (trending hero + rails), indigo/Poppins theme, AMOLED, custom reader chrome
- 🧭 **Powerful reader** — paged & webtoon modes, color filters, brightness/dim, tap-zones, volume-key paging, auto-scroll, save page to Photos
- 📈 **Trackers** — AniList, MyAnimeList, Kitsu
- 🚫 **No ads, no tracking** · 🧩 **Fully open-source**

## Install (sideload)

Nyora for iOS is distributed as an **unsigned `.ipa`** for sideloading — the App Store path is intentionally not used.

### AltStore / SideStore (recommended)
1. Install [AltStore](https://altstore.io) or [SideStore](https://sidestore.io) on your device.
2. Download the latest `Nyora-*.ipa` from the [**Releases**](https://github.com/Hasan72341/nyora-ios/releases/latest) page.
3. Open it in AltStore/SideStore → **Install**. (Apps signed with a free Apple ID must be refreshed every 7 days.)

### Manual (TrollStore / signing tools)
The latest `.ipa` is always on the [releases page](https://github.com/Hasan72341/nyora-ios/releases/latest) — install it with your preferred sideloading tool.

> Requires **iOS/iPadOS 15 or later**.

## Sources

Nyora sources are served by the hosted helper — no per-source app updates needed. There is also a companion **[Aidoku source list](https://github.com/Hasan72341/nyora-aidoku)** if you prefer to use the sources in stock Aidoku:

```
https://raw.githubusercontent.com/Hasan72341/nyora-aidoku/main/index.min.json
```

## Building from source

Requires **Xcode 26+** on macOS.

```sh
git clone https://github.com/Hasan72341/nyora-ios.git
cd nyora-ios

# Build & run in the Simulator
xcodebuild -project Nyora.xcodeproj -scheme "Nyora (iOS)" \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation build

# Build an unsigned .ipa for sideloading
xcodebuild -project Nyora.xcodeproj -scheme "Nyora (iOS)" \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation build
mkdir -p Payload && cp -R "build/Build/Products/Release-iphoneos/Nyora.app" Payload/
zip -qry Nyora.ipa Payload && rm -rf Payload
```

Bundle id `com.nyora.ios` · the Xcode module name stays `Aidoku` internally (Core Data / tests), which is invisible to users.

## The Nyora series

Nyora is one manga reader across every platform, sharing a library and a look:

| Platform | Repo |
|---|---|
| iOS / iPadOS | **you are here** — [`nyora-ios`](https://github.com/Hasan72341/nyora-ios) |
| Android | [`nyora-android`](https://github.com/Hasan72341/nyora-android) |
| Web (PWA) | [`nyora-web`](https://github.com/Hasan72341/nyora-web) — [open app](https://nyoraweb.pages.dev) |
| Windows | [`nyora-windows`](https://github.com/Hasan72341/nyora-windows) |
| macOS / Linux | see [nyora.pages.dev](https://nyora.pages.dev) |
| Aidoku source list | [`nyora-aidoku`](https://github.com/Hasan72341/nyora-aidoku) |

## Credits & license

Built on [**Aidoku**](https://github.com/Aidoku/Aidoku) by Skittyblock and contributors. Nyora for iOS is a derivative work distributed under [**GPLv3**](./LICENSE) — the same license as Aidoku. Translation strings inherited from Aidoku remain under Apache-2.0.

Reader, sources and sync are part of the [Nyora](https://nyora.pages.dev) project.
