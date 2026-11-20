# Architecture and milestones

Leaf is a local macOS app with a SwiftUI window and three workspaces. `LeafApp` owns the scene, `WorkspaceView` owns sidebar selection, and `Workspace` describes the three destinations. The app and its Swift Testing target are built directly by Xcode. The app is sandboxed and requests no network capability.

Use the current stable macOS SDK and the Swift 6 language mode. macOS 26 is the deployment floor because its system controls provide Liquid Glass. The window, sidebar, and toolbar use system styles. Detail content follows the system appearance and uses the standard content surface. See [Apple’s Liquid Glass adoption guidance](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).

As features arrive, the library will own local file references and saved reading positions. Readers consume a local source and expose format-appropriate navigation. Conversion will have its own module and UI, accept a source file and an output destination, and run independently of the library and reader. Add storage and format-specific interfaces when a feature needs them.

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

## 4. Independent conversion

**Deliverable.** Start with TXT to EPUB as a candidate pair. Confirm the supported input and output pairs after evaluating native implementation and any format tooling.

**Acceptance.** The conversion module and its tests run without the reader. A user can choose a local source and destination, cancel a job, and receive a valid output or an actionable error. Source files remain intact and incomplete outputs are cleaned up. The output reopens in Leaf and an independent reader.

## 5. Automated DMG distribution

**Deliverable.** Use GitHub Actions to build and test on Apple Silicon, then package version tags into DMGs and attach them to GitHub Releases. Configure Developer ID signing and notarization when credentials are available for public distribution.

**Acceptance.** CI builds the app and passes the test suite on a supported stable Xcode. A tagged run produces a DMG containing the versioned app and publishes the matching source and required license notices with the release. Verify that the distributed app launches from a clean supported Mac and, for signed distribution, that Gatekeeper accepts it.
