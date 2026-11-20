# Leaf
A lightweight, native macOS eBook reader and converter built with SwiftUI and Liquid Glass.

Leaf currently reads local PDF and TXT files. Leaf is designed for offline use without accounts or telemetry. EPUB, MOBI and AZW3 remain planned formats. Protected books are outside the supported reading and conversion scope.

## Read a local book

Choose **Import Book…** in Library or press **⌘O** while Library is selected. Leaf stores its own copy in the app’s private library and opens it in Reader. Importing an identical file reuses the library entry and its reading position. Leaf reopens the most recently opened book at its saved PDF page or TXT position when it starts.

PDF supports page navigation and zoom. TXT supports UTF-8, BOM-marked UTF-16 and GB18030. The current import limit is 64 MB per file.

## Build and run

- Run Leaf on macOS 26 or later. Apple Silicon is the primary development and verification target.
- Build with Xcode 27.2 (macOS 27.2 SDK, Swift 6 language mode). No third-party packages are required.
- Open `Leaf.xcodeproj`, select the shared **Leaf** scheme and **My Mac**, then choose **Product → Run**.

From the repository root:

```sh
xcodebuild -project Leaf.xcodeproj -scheme Leaf -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
open build/Build/Products/Debug/Leaf.app
```

To verify reading, import a PDF and advance a page. Quit and relaunch Leaf to confirm that the page is restored. Repeat with a TXT file after scrolling, then open Library and verify that it still lists both books.

See [architecture and milestones](docs/architecture.md) for feature scope and acceptance criteria.

The [standalone reader prototype](Prototypes/Reader/README.md) exercises the five planned file formats. Its [engine evaluation](docs/reader-engine-evaluation.md) records the integration decisions.

The [native reader probe](Prototypes/NativeReader/README.md) evaluates reflowable EPUB and Kindle decoding under the local-first design.

## License

Leaf is licensed under [GPL-3.0-only](LICENSE).
