<p align="center"><img src="Scout/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="112" alt="Scout app icon"></p>

# Scout

Scout helps editors find writers and stories for outreach and newsletters. It reads public RSS feeds from Medium and other sites, then lets you shortlist writers and collect stories for an issue.

I built its predecessor, MediumRSS, in 2023 while editing Better Programming. Claude helped me revisit it as Scout, with a bit of on-device AI for writing notes and newsletter drafts.

<p align="center"><img src="docs/media/scout-demo.gif" width="280" alt="Scout demo showing the scouting deck, shortlist and newsletter issue"></p>

[Watch the demo](docs/media/scout-demo.mp4) · The demo uses fictional writers.

## What it does

- Scout Medium topics, authors and publications, Hacker News, and other public RSS feeds.
- Shortlist writers, save stories to an issue, and export your work.
- Draft outreach notes and newsletter copy with Apple Intelligence on supported devices.

Scout ranks candidates in code; AI helps write the accompanying text. Topic matching is a starting point, not a judgment of quality: in a small retrospective evaluation against my editorial decisions, its rankings scored below chance. Outreach drafts are editable and are never sent automatically.

## Run it

Scout has iOS 27 and macOS 27 targets. You'll need Xcode with the corresponding SDKs and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Apple Intelligence features require a supported device and availability.

```bash
brew install xcodegen
xcodegen generate
open Scout.xcodeproj
```

Choose the Scout or ScoutMac scheme in Xcode. To run the shared package tests:

```bash
cd Packages/ScoutKit
swift test
```

Scout is an independent project, not affiliated with Medium. It uses public feeds and does not require a Medium account or API.

## Credits and license

The swipe deck adapts [Deckloom](https://github.com/anupamchugh/Deckloom); the Siri intents follow [SiriCardKit](https://github.com/krispuckett/SiriCardKit). See [third-party notices](THIRD_PARTY_NOTICES.md). Scout is [MIT licensed](LICENSE).
