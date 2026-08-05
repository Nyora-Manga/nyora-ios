<div align="center">

<img src="https://nyora.xyz/icon.png" width="120" alt="Nyora" />

# Nyora — iOS

### Read like the world can wait.

A fast, free, ad-free, open-source manga / manhwa / manhua reader for **iPhone & iPad** — part of the cross-platform [Nyora](https://nyora.xyz) series. Hundreds of sources, an in-reader AI translation overlay, and your library synced across every device you read on.

<p>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=white" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-0055FF?style=for-the-badge&logo=swift&logoColor=white" />
  <img alt="iOS 18+" src="https://img.shields.io/badge/iOS-18%2B-000000?style=for-the-badge&logo=apple&logoColor=white" />
  <img alt="Version 2.1.8" src="https://img.shields.io/badge/version-2.1.8-FF4655?style=for-the-badge" />
</p>

<p>
  <a href="./LICENSE"><img alt="License: GPLv3" src="https://img.shields.io/badge/license-GPLv3-blue.svg" /></a>
  <a href="https://github.com/Nyora-Manga/nyora-ios/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/Nyora-Manga/nyora-ios?style=social" /></a>
  <a href="https://nyora.xyz"><img alt="Website" src="https://img.shields.io/badge/Website-nyora.xyz-FF4655?style=for-the-badge&logo=githubpages&logoColor=white" /></a>
  <a href="https://github.com/Nyora-Manga/nyora-ios/releases/latest"><img alt="Download IPA" src="https://img.shields.io/badge/Download-.ipa-5A0FC8?style=for-the-badge&logo=apple&logoColor=white" /></a>
</p>

**No App Store, no ads, no sign-up wall.** Sideload the `.ipa` and start reading.

</div>

---

## About

**Nyora for iOS** is the iPhone / iPad edition of Nyora, built on the open-source [**Aidoku**](https://github.com/Aidoku/Aidoku) reader and rebuilt around the Nyora ecosystem. Parsing runs **on device**: the real [Kotatsu](https://github.com/KotatsuApp) parser engine (~960 sources, OkHttp + Jsoup + coroutines) is AOT-compiled to native ARM64 with **GraalVM Native Image**, so there is no hosted helper in the request path, no JavaScript bundle and no JIT — nothing is downloaded or interpreted at runtime. See [`native-engine/NATIVE_IOS.md`](native-engine/NATIVE_IOS.md).

Running the engine locally also means iOS can clear a Cloudflare challenge itself, so it gets the same source coverage as the Android and desktop apps rather than the reduced set a shared cloud helper can serve.

Sign in with a **Nyora Cloud** account (email + password) and your library, history and reading progress follow you to every other Nyora platform — or continue as a guest and read, no account required. It shares the Nyora design language with the Android app, so it feels like one product across every device.

## Features

- 📚 **Hundreds of sources** — install any source from the hosted catalogue; browse Popular / Latest, search, and read
- 🈳 **In-reader AI translation overlay** — a toggle, not baked-in: **Google Translate**, on-device **Apple Intelligence** (iOS 26), or **bring-your-own-key** (any OpenAI-compatible endpoint) — with per-page OCR and speech-bubble detection
- ☁️ **Nyora Cloud sync** — one library across Android, iOS/iPadOS, macOS, Windows, Linux & Web. Sign in with **email + password** against the self-hosted **Nyora Cloud** backend (OAuth2 + JWT), or **continue as guest**
- 🎨 **Nyora design** — Discover home (trending hero + rails), indigo/Poppins theme, AMOLED, custom reader chrome
- 🧭 **Powerful reader** — paged & webtoon modes, color filters, brightness/dim, tap-zones, volume-key paging, auto-scroll, save page to Photos
- 📈 **Trackers** — AniList, MyAnimeList, MangaBaka
- 🚫 **No ads, no tracking** · 🧩 **Fully open-source**

## Install (sideload)

Nyora for iOS is distributed as an **unsigned `.ipa`** for sideloading — the App Store path is intentionally not used.

**AltStore / SideStore (recommended)**
1. Install [AltStore](https://altstore.io) or [SideStore](https://sidestore.io) on your device.
2. Download the latest `Nyora-*.ipa` from the [**Releases**](https://github.com/Nyora-Manga/nyora-ios/releases/latest) page.
3. Open it in AltStore/SideStore → **Install**. (Apps signed with a free Apple ID must be refreshed every 7 days.)

**Manual (TrollStore / signing tools)** — grab the latest `.ipa` from [releases](https://github.com/Nyora-Manga/nyora-ios/releases/latest) and install it with your preferred tool.

> Requires **iOS / iPadOS 18 or later**.

## Sources

Sources are compiled into the app's parser engine ([`nyora-ios-engine`](https://github.com/Nyora-Manga/nyora-ios-engine)), which is rebuilt and published whenever the shared source fixes in [`nyora-data-driven`](https://github.com/Nyora-Manga/nyora-data-driven) change — so iOS tracks the same relocated domains and retired sources as the Android app. Adding a brand-new source still needs an app update, since the parsers ship in the binary rather than being fetched at runtime. A companion **[Aidoku source list](https://github.com/Nyora-Manga/nyora-aidoku)** is also published if you prefer to use the sources in stock Aidoku:

```
https://raw.githubusercontent.com/Nyora-Manga/nyora-aidoku/main/index.min.json
```

## Building from source

Requires **Xcode 26+** on macOS.

```sh
git clone https://github.com/Nyora-Manga/nyora-ios.git
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

Bundle id `com.nyora.ios`. The Xcode module name stays `Aidoku` internally (Core Data / tests) — invisible to users.

## The Nyora series

Nyora is one manga reader across every platform, sharing a library and a look:

| Platform | Repo |
|---|---|
| iOS / iPadOS | **you are here** — [`nyora-ios`](https://github.com/Nyora-Manga/nyora-ios) |
| Android | [`nyora-android`](https://github.com/Nyora-Manga/nyora-android) |
| Web (PWA) | [`nyora-web`](https://github.com/Nyora-Manga/nyora-web) — [open app](https://nyora.xyz) |
| Windows | [`nyora-windows`](https://github.com/Nyora-Manga/nyora-windows) |
| macOS / Linux | see [nyora.xyz](https://nyora.xyz) |
| Data-driven engine | [`nyora-data-driven`](https://github.com/Nyora-Manga/nyora-data-driven) |

## Credits

Nyora for iOS stands on the work of several open-source projects:

- **[Aidoku](https://github.com/Aidoku/Aidoku)** by Skittyblock and contributors — the iOS reader this app is forked from. Nyora is a derivative work under the same license; translation strings inherited from Aidoku remain under Apache-2.0.
- **[Kotatsu](https://github.com/KotatsuApp) / [kotatsu-parsers](https://github.com/KotatsuApp/kotatsu-parsers)** — the parser family the source definitions derive from, and the engine compiled into the app.
- **[nyora-data-driven](https://github.com/Nyora-Manga/nyora-data-driven)** — Nyora's data-driven catalogue (generic templates over Kotatsu parser definitions) that defines every source.
- **[GraalVM Native Image](https://www.graalvm.org/native-image/)** / **[Gluon Substrate](https://github.com/gluonhq/substrate)** — AOT-compile the JVM parser engine to native ARM64 so it runs on device.
- **AI translation stack** — [Google ML Kit](https://developers.google.com/ml-kit) (on-device OCR, including vertical Japanese), [Apple Vision](https://developer.apple.com/documentation/vision) (OCR fallback ensemble), [Apple Intelligence / Foundation Models](https://developer.apple.com/apple-intelligence/) (on-device refinement), [Google Translate](https://translate.google.com), and any OpenAI-compatible endpoint via bring-your-own-key.

Reader, sources and sync are part of the [Nyora](https://nyora.xyz) project.

## License

Licensed under [**GPLv3**](./LICENSE) — the same license as Aidoku.
