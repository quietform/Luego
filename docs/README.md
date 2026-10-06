# Luego

A minimal read-it-later app for iPhone and iPad, with offline access to previously fetched articles.

[Download](https://apps.apple.com/us/app/luego/id6755436648) on the App Store or [Join Beta](https://testflight.apple.com/join/XCNeNBsA) on TestFlight.
<p>
  <img src="screenshots/App Store Screenshot 1.jpg" width="180" />
  <img src="screenshots/App Store Screenshot 2.jpg" width="180" />
  <img src="screenshots/App Store Screenshot 3.jpg" width="180" />
  <img src="screenshots/App Store Screenshot 4.jpg" width="180" />
</p>

## Architecture

Luego uses SwiftUI and Observation, with services organized by feature and dependencies wired through `DIContainer`. Articles are stored locally with GRDB/SQLite and synchronized through `CKSyncEngine` with a CloudKit private database. See [ARCHITECTURE.md](ARCHITECTURE.md) for the data flows and [CONTRIBUTING.md](CONTRIBUTING.md) for contribution rules.

## Features

- **Article saving**: Add a URL in the app or queue it through the share extension for import when the app is active.
- **Content extraction**: Parse articles locally with a downloaded parser SDK, with API fallback.
- **Offline reading**: Read previously fetched content with saved reading position and Markdown rendering.
- **Reading lists**: Favorite and archive articles, with local SQLite storage and iCloud sync.
- **Discovery**: Explore articles from Kagi Small Web and Blogroll.
- **Import and export**: Transfer article URLs as plain text.

## Requirements

- iOS 26.0+ or iPadOS 26.0+
- Xcode 26.0+
- The project uses Swift 5 language mode with complete strict concurrency checking.

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/quietform/Luego.git
cd Luego
```

### 2. Open in Xcode

```bash
open Luego.xcodeproj
```

### 3. Configure Signing

Before building, you need to configure code signing:

1. Select the **Luego** project in the navigator
2. Select the **Luego** target
3. Go to **Signing & Capabilities** tab
4. Select your **Team** from the dropdown
5. Repeat for the **LuegoShareExtension** target

Bundle identifiers and display names are configured per build configuration in [Configuration/](../Configuration/). If using your own identifiers, update both targets, their App Group entitlements, the App Group identifiers in `SharedStorage` and `LegacySwiftDataArticleDataSource`, and the CloudKit container in the app entitlements and `AppConfiguration` together. The app uses `iCloud.com.esoxjem.Luego`; both targets share `group.com.esoxjem.Luego` for queued URLs.

## Developer CLI

See [TESTING.md](TESTING.md) for simulator commands and verification guidance.
