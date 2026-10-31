<img src="assets/icon.svg" width="64" height="64" alt="">

# Iwa for Frigate

A native, open-source client for [Frigate NVR](https://frigate.video) on iPhone, iPad, Mac and Apple TV.

> Iwa is the Hawaiian name for the frigatebird. Iwa is an independent project and is not affiliated with Frigate, Inc.

## Repository

| Path | What |
|---|---|
| `apple/` | Multiplatform SwiftUI app (`project.yml` for XcodeGen) and the `IwaKit` Swift package |
| `server/` | Rust workspace: `iwa-protocol` (shared types) and `iwa-agent` (sidecar next to Frigate) |

## Building

```sh
# Apple app (Xcode 27, iOS/macOS/tvOS 26+)
brew install xcodegen
cd apple && xcodegen generate && open Iwa.xcodeproj

# Swift package tests
cd apple/Packages/IwaKit && swift test

# Rust
cd server && cargo test
```

## License

MIT
