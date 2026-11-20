# Architecture and milestones

Leaf is a local macOS app with a SwiftUI window and three workspaces. `LeafApp` owns the scene, `WorkspaceView` owns sidebar selection, and `Workspace` describes the three destinations. The app and its Swift Testing target are built directly by Xcode. The app is sandboxed and requests no network capability.

Use the current stable macOS SDK and the Swift 6 language mode. macOS 26 is the deployment floor because its system controls provide Liquid Glass. The window, sidebar, and toolbar use system styles. Detail content follows the system appearance and uses the standard content surface. See [Apple’s Liquid Glass adoption guidance](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).

The library stores managed copies and a small JSON catalog in Application Support. Each entry uses a format and content hash to identify its copy. Leaf validates a selected file before storing it, writes the copy before publishing the catalog entry, and replaces the catalog atomically. Readers save format-specific positions in the catalog. The converter uses its own workspace and package, with a shared TXT decoder.

## 1. Native application shell

**Deliverable.** A dependency-free Xcode project with a resizable window, a two-column `NavigationSplitView`, an empty library, and Reader and Converter placeholders.

**Acceptance.** The shared scheme builds and launches on Apple Silicon. The library is visible on launch, all three workspace selections update the detail pane and title, and the system sidebar toggle responds. Layout and text remain legible in Light and Dark. Navigation unit tests pass.

## 2. Validate reading engines

**Deliverable.** A small local prototype and a decision record for [WebKit + foliate-js](https://github.com/johnfactotum/foliate-js), [PDFKit](https://developer.apple.com/documentation/pdfkit), and native TXT rendering. Keep prototype dependencies out of the app target until the review is complete.

**Acceptance.** Exercise unprotected EPUB, MOBI and AZW3 in a local WebKit prototype. Check chapter navigation, pagination, local images and fonts, and offline behavior. Verify PDF paging and zoom in PDFKit and TXT encoding and scrolling in SwiftUI. Record first-page latency, page-turn latency and peak memory on Apple Silicon with representative small and large files. Check that malformed inputs fail safely, book code cannot access external resources or privileged native APIs, and encrypted ebooks are rejected. Review the selected upstream revision, bundled code and notices for GPL-3.0-only distribution and document the measurements and go/no-go decision before integration.

See the [standalone prototype](../Prototypes/Reader/README.md) and [engine evaluation](reader-engine-evaluation.md).

## 3. Local library and reading

**Deliverable.** Add local import, library persistence, resume position and the approved rendering paths for EPUB, MOBI, AZW3, PDF and TXT.

**Acceptance.** Open all five formats offline via the library. Reopening Leaf restores the library and reading position. Missing, malformed, unsupported and protected files show a clear error. Recheck runtime performance against the prototype results.

Leaf uses PDFKit for PDF pages and zoom and SwiftUI for TXT and reflowable ebooks. EPUB uses the reviewed ZIP reader and Foundation XML parsing. MOBI and AZW3 use the libmobi decoder with encryption disabled and the system HTML parser for legacy markup. The three ebook adapters share native text and image rendering, internal navigation and a catalog position made up of the section and scroll block. Library imports read user-selected files into the private library. See the [native reader evaluation](native-reader-evaluation.md) and [third-party notices](../THIRD_PARTY_NOTICES.md).

The reflowable reader supports headings, basic emphasis, internal links and local raster images. Publisher stylesheets, embedded fonts, fixed layout and rich media remain compatibility work. EPUB accepts bounded, single-volume ZIP32 archives and rejects encryption manifests, including font obfuscation. Kindle checks both headers of hybrid books for encryption.

The 21-test Xcode suite covers all five formats, protected and malformed inputs, and saved reader positions. Four package tests exercise the bounded ZIP entry point. A signed Release build launched in an isolated app container. The Release reading check imported the real sample books into isolated catalogs, deleted the temporary input copies, and reopened the managed copies at new positions. It also checked table-of-contents anchors and decoded local images in the EPUB, MOBI 6 and hybrid KF8 samples.

The table reports medians from three fresh Release-mode reader processes per sample on the Apple M2. Import includes reading the source, validating the initial content and committing a private copy and catalog. Ebook target preparation includes decoding the initial section’s images and preparing the last contents target. Restore measures the saved position before SwiftUI layout. RSS is the highest value across these CLI runs. The [prototype timings](native-reader-evaluation.md#performance) measure individual decoder preparation and cannot be subtracted directly from import timings.

| Sample | Import (ms) | Ebook target preparation (ms) | Restore (ms) | Peak CLI RSS (MiB) |
| --- | ---: | ---: | ---: | ---: |
| 14.19 MiB EPUB | 26.38 | 8.61 | 9.72 | 43.1 |
| MOBI 6 | 28.00 | 28.02 | 21.37 | 17.4 |
| 3.03 MiB MOBI 4 dictionary | 898.50 | 806.25 | 892.40 | 114.5 |
| Standalone KF8 | 5.92 | 1.19 | 1.76 | 12.0 |
| Hybrid KF8 | 5.72 | 18.63 | 16.39 | 17.1 |
| 320-page PDF | 59.24 | — | 0.43 | 16.4 |
| 2.67 MiB TXT | 88.65 | — | 83.03 | 16.1 |

The MOBI 4 dictionary puts more than 5 MiB of HTML in a single section and remains the slowest sample. Reading preparation runs away from the UI for ebooks. Earlier desktop checks verified PDF page and TXT scroll restoration, and the native EPUB probe verified an inline chapter link.

## 4. Independent conversion

**Deliverable.** Convert local TXT to reflowable EPUB 3 with escaped text, preformatted line breaks, section navigation and a table of contents.

**Acceptance.** The conversion module and its tests run without the reader. A user can choose a local source and destination, cancel a job, and receive a valid output or an actionable error. Source files remain intact and incomplete outputs are cleaned up. The output reopens in Leaf and an independent reader.

`LeafConversion` uses the vendored ZIP writer and shares UTF-8, UTF-16 and GB18030 decoding with the reader through `LeafText`. Its test suite runs independently of the Xcode app and reading stack. The writer places the uncompressed media type entry first and creates a package document, reading order, navigation document and stylesheet. [EPUB 3.3](https://www.w3.org/TR/2026/REC-epub-33-20260113/)

The Converter workspace keeps one job active at a time. The system save panel grants access to the selected target. The worker stages the complete archive in the sandbox temporary directory, checks cancellation before publication and uses an atomic write to publish the final file. Cancellation and write failures clean up staging. The sandbox permits read and write access to user-selected files for import and export. [Apple’s user-selected file entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write)

Six standalone conversion tests and 22 Xcode tests passed on Apple Silicon. The Leaf integration test imported a generated EPUB and checked its contents and navigation. The standalone foliate-js reader opened an EPUB converted from UTF-16, turned pages and followed its table of contents. The source checksum stayed the same.

## 5. Automated DMG distribution

**Deliverable.** Use GitHub Actions to build and test on Apple Silicon, then package version tags into DMGs and attach them to GitHub Releases. Configure Developer ID signing and notarization when credentials are available for public distribution.

**Acceptance.** CI builds the app and passes the test suite on a supported stable Xcode. A tagged run produces a DMG containing the versioned app and publishes the matching source and required license notices with the release. Verify that the distributed app launches from a clean supported Mac and, for signed distribution, that Gatekeeper accepts it.

The [macOS workflow](../.github/workflows/macos.yml) tests the app and both Swift packages on the Apple Silicon Xcode 27 runner. The build job checks the mounted DMG and uploads it with the source archive and checksums. A separate job publishes these assets only for a version tag push. Developer ID signing and notarization are optional for previews. See the [release guide](releasing.md).

Local verification with Xcode 27.2 passed all 32 tests. The preview image mounted successfully, contained the arm64 app at the requested version and preserved the license notices. A copy from the image launched under an isolated bundle identifier. The first hosted release and Gatekeeper check on a clean Mac remain pending.

## 6. Bookshelf, reading layouts and full conversion matrix

The sidebar keeps the library, reader and converter workspaces. The bookshelf uses lazy cover thumbnails, with a bounded in-memory cache. Renaming changes the catalog title. Optional favorite and last-read fields keep older catalogs readable. The reader defaults to a single page, calculates text pages from the active viewport and persists user-selected layouts and typography settings.

`LeafConversion` accepts EPUB, MOBI, AZW3, PDF and TXT as inputs and outputs. Leaf supplies its existing EPUB and Kindle decoders to the package. The shared ebook model preserves ordered text and local raster images, and repeated image references share one resource. The package writes EPUB and Kindle containers in Swift and uses PDFKit and Core Text to extract PDF text and lay out new PDF pages. It stages each output locally and publishes the complete file atomically. The converter runs inside Leaf’s sandbox, handles one file at a time and rejects protected books. PDF conversion requires selectable text.

The Kindle writer uses the record layouts in Calibre’s published format notes and checks its output against an independent Calibre decoder during manual verification. Leaf ships its own Swift writer and the existing libmobi reader. [Calibre MOBI format notes](https://github.com/kovidgoyal/calibre/blob/v9.18.0/format_docs/pdb/mobi.txt)

**Acceptance.** Import by dragging from Finder, use the library filters and preserve legacy catalogs and reading positions. Exercise scrolling, single-page and two-page views with Chinese and Latin text. Convert all 20 directed format pairs with text-bearing samples. Verify that a batch can skip matching formats, protect existing destinations and preserve completed files on cancellation.
