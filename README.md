# Leaf
A lightweight, native macOS eBook reader and converter built with SwiftUI and Liquid Glass.

Leaf reads local EPUB, MOBI, AZW3, PDF and TXT books offline. It uses a private library without accounts or telemetry. Protected books are outside the supported reading and conversion scope.

## Install Leaf

Download the Apple Silicon DMG from [GitHub Releases](https://github.com/Alano-ai/Leaf/releases) on macOS 26 or later. Open the DMG, drag **Leaf** to **Applications**, then launch Leaf from Applications. Eject the installer disk when finished. If the window stays closed after opening the DMG, select **Install Leaf** in Finder’s sidebar.

GitHub marks builds without Apple notarization as previews. Gatekeeper may block them on first launch.

## 简体中文

Leaf 的书库、阅读器、格式转换和错误提示支持简体中文。界面跟随 macOS 的语言设置。也可以在「系统设置 → 通用 → 语言与地区 → 应用程序」中为 Leaf 单独选择简体中文，然后重新打开 Leaf。安装镜像提供中英文拖放指引。

## Read a local book

Choose **Import Book…** in Library or press **⌘O** while Library is selected. Leaf stores its own copy in the app’s private library and opens it in Reader. Importing an identical file reuses the library entry and its reading position. On startup, Leaf reopens the most recent book at its saved page, section, or scroll position.

- EPUB, MOBI and AZW3 use native reflowable text with section navigation, tables of contents, internal links and supported local raster images. Leaf applies its own typography. Fixed-layout books and EPUB font-obfuscation manifests are outside this reader’s scope.
- PDF supports page navigation and zoom. TXT supports UTF-8, BOM-marked UTF-16 and GB18030.
- The import limit is 64 MB per file.

## Convert TXT to EPUB

In **Converter**, choose a TXT file and select **Convert to EPUB…** to choose the destination. The EPUB uses the source filename for its title and includes a table of contents. Cancel an active job from the Converter workspace. Leaf keeps the original TXT intact and saves the EPUB once the complete book is ready.

The converter accepts UTF-8, BOM-marked UTF-16 and GB18030 TXT up to 64 MB.

## Build and run

- Run Leaf on macOS 26 or later. Apple Silicon is the primary development and verification target.
- Build with Xcode 27.2 (macOS 27.2 SDK, Swift 6 language mode). The pinned ZIP and Kindle source packages are included in the repository for offline builds. See the [third-party notices](THIRD_PARTY_NOTICES.md).
- Open `Leaf.xcodeproj`, select the shared **Leaf** scheme and **My Mac**, then choose **Product → Run**.

From the repository root:

```sh
xcodebuild -project Leaf.xcodeproj -scheme Leaf -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
open build/Build/Products/Debug/Leaf.app
```

To verify reading, import samples of the five formats and check that each opens in Reader. Advance a PDF page, scroll a TXT, or use Contents and scroll in a reflowable book. Quit and relaunch Leaf to confirm that the most recent book restores its saved position, then open Library to see all imported books.

Run the standalone conversion tests with `xcrun swift test --package-path Packages/LeafConversion --scratch-path build/conversion-module`.

See [architecture and milestones](docs/architecture.md) for feature scope and acceptance criteria.

The [standalone reader prototype](Prototypes/Reader/README.md) exercises the five planned file formats. Its [engine evaluation](docs/reader-engine-evaluation.md) records the integration decisions.

The [native reader probe](Prototypes/NativeReader/README.md) evaluates reflowable EPUB and Kindle decoding under the local-first design.

## Build a DMG

On Apple Silicon, run `bash scripts/package-dmg.sh 0.1.2` to build and verify the disk image in `build/distribution/`. The DMG opens as a Finder volume with an installation guide and an Applications shortcut. The license notices stay with the installed app.

GitHub Actions runs Xcode and package tests, builds the DMG, and publishes it with the corresponding source and SHA-256 checksums when a version tag is pushed. See the [release guide](docs/releasing.md) for signing and verification.

## License

Leaf is licensed under [GPL-3.0-only](LICENSE).
