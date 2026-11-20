# Reading engine evaluation

The evaluation ran on 2026-11-20 on an Apple M2 with 8 GiB RAM, macOS 27.2.1 (26B131), and Xcode 27.2. The standalone probe uses Swift 6 and the macOS 27.2 SDK, targeting arm64 and macOS 26. The Leaf target uses its existing sandbox and source groups.

## Integration decision

| Engine | Decision | Basis |
| --- | --- | --- |
| PDFKit | Integrate in the library milestone | Native page changes and zoom work in the sandboxed build. The protected fixture is rejected before display. |
| SwiftUI TXT | Integrate in the library milestone | Native scrolling and Chinese sample text work with UTF-8, BOM-marked UTF-16, and GB18030. Start with these documented encodings and add others when there are fixtures. |
| WebKit + foliate-js | Hold from the Leaf target | The comparison build renders all three ebook formats. The system WebKit process cannot launch with Leaf’s current network-free sandbox on the test Mac. |

The executable with the same network-free sandbox as Leaf failed before rendering the local EPUB shell. WebKit reported that the application lacked permission to communicate with network resources. Adding `com.apple.security.network.client` to a separate comparison bundle allowed the local scheme to load. This entitlement permits outgoing connections at the OS level. The prototype validates resource blocking at the renderer level. Before integrating, decide whether an offline renderer can meet Leaf’s distribution model with that entitlement, or evaluate a non-WebKit rendering path. [Apple’s network-client entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)

## Format and isolation checks

- Reflowable and fixed-layout EPUB exercised first-page rendering, page turns, table-of-contents jumps, local images and embedded fonts. A fixed-layout jump is checked against the actual visible page because the location of a two-page spread can be reported as its leading page.
- The standalone MOBI parser exercised real version 4 and 6 inputs. The larger input is a dictionary. The two legacy fixtures contain no table of contents exposed by the parser, so chapter jumps are verified on EPUB and the chaptered KF8 fixture. The standalone KF8 fixture exercises an embedded font. The hybrid fixture exercises images and chapter navigation after confirming the parser selected its version 8 edition.
- The ebook iframe permits same-origin document inspection for layout with book scripts disabled. The custom scheme serves an explicit resource list and the selected book. The reader uses a nonpersistent data store, a restrictive content security policy, a WebKit content blocker, and a navigation delegate. Swift calls trusted page methods and exposes zero native script-message handlers.
- The EPUB fixture's inline script stayed inert and the file and HTTP images did not render. A local HTTP listener that returned a valid fixture image recorded its control request and zero requests from any tested book. In the GUI, the toolbar advanced the sample EPUB from 6% to 13%, and the chapter menu opened Chapter 3.
- The protected EPUB marker and MOBI/KF8 encryption flags are rejected before book rendering. PDF uses a genuinely password-protected fixture. The EPUB policy also rejects font-obfuscation manifests in this probe. Revisit standards-based font obfuscation separately from DRM when evaluating compatibility.
- The test corpus includes truncated or invalid input for all five formats. The probe caps input at 64 MiB and checks declared archive sizes. It does not prove resource budgets against misleading archive metadata or expensive parser input. A production candidate needs decompression limits, timeout or cancellation coverage, and a broader corpus.

## Performance

Each normal sample ran three times in a fresh app process. First-page timing starts at the open request and ends at the first page or viewport ready signal. WebKit waits for initial fonts and two animation frames. The PDFKit measurements end at the view's page and layout update. TXT measures a native viewport scroll. These signals have different rendering semantics across engines.

The table shows median first-view and turn times, and the highest sampled resident memory across runs. The combined peak adds the app and new WebKit processes observed in the same roughly 40 ms snapshot. This is an estimate from `ps`. It includes shared memory in RSS and can miss brief peaks or count an unrelated process launched during a sample.

| Sample | File size | First view (ms) | Turn or scroll (ms) | App peak (MiB) | Combined peak (MiB) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `small.epub` | 79.1 KiB | 294 | 116.7 | 109.3 | 199.6 |
| `large.epub` | 14.19 MiB | 309 | 116.6 | 126.5 | 251.8 |
| `fixed.epub` | 79.0 KiB | 269 | 85.1 | 109.6 | 198.9 |
| `small.mobi` | 105.9 KiB | 261 | 116.5 | 107.5 | 212.4 |
| `large.mobi` | 3.03 MiB | 479 | 116.5 | 110.6 | 248.8 |
| `small.azw3` | 82.4 KiB | 271 | 116.3 | 107.5 | 189.2 |
| `large.azw3` | 551.8 KiB | 303 | 116.6 | 113.0 | 233.9 |
| `small.pdf` | 4.8 KiB | 62 | 0.4 | 98.1 | 98.1 |
| `large.pdf` | 478.1 KiB | 66 | 0.6 | 106.2 | 106.2 |
| `small.txt` | 3.2 KiB | 42 | 12.4 | 99.6 | 99.6 |
| `large.txt` | 2.67 MiB | 115 | 11.3 | 98.8 | 98.8 |
| `legacy.txt` | 3.0 KiB | 42 | 11.3 | 100.0 | 100.0 |

The first EPUB attempt took 886 ms, which the median masks. The largest EPUB reached approximately 252 MiB of combined resident memory. The large PDF exercises 320 text pages, and the larger KF8 fixture is about 552 KiB. Use image-heavy PDF and multi-megabyte KF8 inputs before setting release performance targets.

The harness passed 36 normal runs and nine protected or malformed checks. The [prototype instructions](../Prototypes/Reader/README.md) reproduce the raw JSON-lines output.

## License and maintenance

The prototype pins [foliate-js at `78914aef`](https://github.com/johnfactotum/foliate-js/tree/78914aef4466eb960965702401634c2cb348e9b1). The selected permissive licenses are compatible with GPLv3 according to the Free Software Foundation’s license list. The prototype retains the MIT, BSD-3-Clause and SJCL BSD notices in its bundle. The upstream lockfile identifies the dependency sources, and the build verifies the fetched inputs before staging them. The shipped minified modules would need a verified source-to-bundle build and all matching source and notices at release time. [Compatibility list](https://www.gnu.org/licenses/license-list.html) · [Leaf third-party notices](../THIRD_PARTY_NOTICES.md)

The pin plus a small, reviewable patch keeps the library replaceable. The patch restricts both reader iframe paths and checks both headers of a hybrid MOBI/KF8 before parsing protected content. The renderer uses native PDFKit for PDF. Leaf’s later release process can omit PDF.js, unused foliate-js modules and all test fixtures.
