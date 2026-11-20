# Leaf
A lightweight, native macOS eBook reader and converter built with SwiftUI and Liquid Glass.

Leaf reads local EPUB, MOBI, AZW3, PDF and TXT books offline. It uses a private library without accounts or telemetry. Protected books are outside the supported reading and conversion scope.

## Install Leaf

Download the Apple Silicon DMG from [GitHub Releases](https://github.com/Alano-ai/Leaf/releases) on macOS 26 or later. Open the DMG, drag **Leaf** to **Applications**, then launch Leaf from Applications. Eject the installer disk when finished. If the window stays closed after opening the DMG, select **Install Leaf** in Finder’s sidebar.

GitHub marks builds without Apple notarization as previews. Gatekeeper may block them on first launch.

## 简体中文

Leaf 的书库、阅读器、格式转换和错误提示支持简体中文。界面跟随 macOS 的语言设置。也可以在「系统设置 → 通用 → 语言与地区 → 应用程序」中为 Leaf 单独选择简体中文，然后重新打开 Leaf。安装镜像提供中英文拖放指引。

把书籍拖到「全部图书」可导入书库，右键菜单提供收藏、重命名、查看信息和转换。阅读工具栏可以调整纸张背景、宋体或苹方、字号、行距、页边距和阅读模式。「格式转换」支持拖入多个文件，并一次选择输出格式和保存文件夹。

阅读器默认按窗口大小显示单页，可在阅读工具栏切换模式。EPUB、MOBI、AZW3、PDF 和 TXT 可在 Leaf 内离线互转。EPUB、MOBI 和 AZW3 互转时会保留受支持的正文图片。

## Read a local book

Drop files onto the bookshelf, choose **Import Books…**, or press **⌘O** in any library view. Leaf stores a private copy of each book. A single import opens in Reader. The sidebar provides All Books, Recently Read and Favorites. The book context menu provides conversion, renaming and file information. On startup, Leaf reopens the most recent book at its saved page, section, or scroll position.

- EPUB, MOBI and AZW3 use native reflowable text with section navigation, tables of contents, internal links and supported local raster images. Leaf applies its own typography. Fixed-layout books and EPUB font-obfuscation manifests are outside this reader’s scope.
- Reader defaults to a single page that fits the window. Scrolling and two-page layouts are available in Reading Appearance. Reflowable books have white, paper and dark backgrounds and adjustable font, size, line spacing and margins. PDF keeps its page artwork and offers page navigation and zoom. TXT supports UTF-8, BOM-marked UTF-16 and GB18030.
- The import limit is 64 MB per file.

## Convert between formats

In **Converter**, drop or select one or more files, pick an output format and choose a destination. EPUB, MOBI, AZW3, PDF and TXT each work as a source or a target. In a batch, Leaf skips files already in the target format and keeps completed outputs if you cancel. The source files stay intact, and batch output uses a new filename when one already exists.

All 20 directions run locally inside Leaf with no additional installation. The per-file conversion limit is 64 MB. EPUB, MOBI and AZW3 conversions reflow the text and carry detected chapter titles, covers and supported raster illustrations. PDF and TXT conversion uses text. PDFs need selectable text, so scanned PDFs require OCR before conversion.

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

The shared `Leaf` scheme tests all 20 conversion directions and reopens the resulting files.

See [architecture and milestones](docs/architecture.md) for feature scope and acceptance criteria.

The [standalone reader prototype](Prototypes/Reader/README.md) exercises the five planned file formats. Its [engine evaluation](docs/reader-engine-evaluation.md) records the integration decisions.

The [native reader probe](Prototypes/NativeReader/README.md) evaluates reflowable EPUB and Kindle decoding under the local-first design.

## Build a DMG

On Apple Silicon, run `bash scripts/package-dmg.sh 0.1.2` to build and verify the disk image in `build/distribution/`. The DMG opens as a Finder volume with an installation guide and an Applications shortcut. The license notices stay with the installed app.

GitHub Actions runs Xcode and package tests, builds the DMG, and publishes it with the corresponding source and SHA-256 checksums when a version tag is pushed. See the [release guide](docs/releasing.md) for signing and verification.

## License

Leaf is licensed under [GPL-3.0-only](LICENSE).
