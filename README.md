# Leaf
A lightweight, native macOS eBook reader and converter built with SwiftUI and Liquid Glass.

Leaf currently opens to an empty library with Reader and Converter workspaces. The planned local reading formats are EPUB, MOBI, AZW3, PDF, and TXT. Leaf is designed for offline use without accounts or telemetry. Protected books are outside the supported reading and conversion scope.

## Build and run

- Run Leaf on macOS 26 or later. Apple Silicon is the primary development and verification target.
- Build with Xcode 27.2 (macOS 27.2 SDK, Swift 6 language mode). No third-party packages are required.
- Open `Leaf.xcodeproj`, select the shared **Leaf** scheme and **My Mac**, then choose **Product → Run**.

From the repository root:

```sh
xcodebuild -project Leaf.xcodeproj -scheme Leaf -destination 'platform=macOS,arch=arm64' -derivedDataPath build test
open build/Build/Products/Debug/Leaf.app
```

To verify the shell, launch Leaf and confirm that Library is selected. Navigate to Reader and Converter, toggle the sidebar, and resize the window. Repeat in Light and Dark appearance.

See [architecture and milestones](docs/architecture.md) for feature scope and acceptance criteria.

The [standalone reader prototype](Prototypes/Reader/README.md) exercises the five planned file formats. Its [engine evaluation](docs/reader-engine-evaluation.md) records the integration decisions.

## License

Leaf is licensed under [GPL-3.0-only](LICENSE).
