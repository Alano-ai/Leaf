# Native ebook reading evaluation

The second evaluation used an Apple M2 with 8 GiB RAM, macOS 27.2.1 and Xcode 27.2. It explored a renderer that uses Leaf’s current sandbox permissions. See the [WebKit evaluation](reader-engine-evaluation.md) for the preceding comparison.

## Decision

| Area | Next step | Evidence |
| --- | --- | --- |
| Reflowable EPUB | Advance the native renderer to a scoped library integration | The SwiftUI probe follows EPUB 2 and EPUB 3 reading order, renders basic text and images, and follows table-of-contents entries and anchors. |
| Full EPUB compatibility | Keep fixed layout and stylesheet fidelity as explicit scope decisions | The prototype applies its own typography. Publisher CSS, embedded fonts, SVG, complex tables, ruby, vertical writing and media have no dedicated rendering in this prototype. Declared fixed layout is rejected. |
| MOBI and AZW3 | Advance libmobi as a decoder candidate | The probe recovered text and resource records for MOBI 4 and 6, standalone KF8 and hybrid KF8. The MOBI 6 and hybrid KF8 samples exposed navigation indexes. The main reader still needs a safe HTML and resource adapter, rendering tests and broader legacy navigation coverage. |

The recommended next integration is unprotected, reflowable EPUB through the existing import, catalog and position APIs. Set expectations for supported layout and preserve a clear error for fixed or protected books. Validate archive and chapter limits across a wider corpus before enabling arbitrary EPUB imports by default. Use the scoped reader to open the later TXT-to-EPUB output.

## Checks

- The EPUB app uses bounded, in-memory ZIP extraction with checksums and never writes archive members to the filesystem. It caps input bytes, member count, declared archive expansion, individual chapter and image bytes, decoded image pixels and XML depth. Header processing and ZIP64 need further malformed-input coverage before integration.
- The formatter traverses parsed XHTML and builds SwiftUI text and raster images. It accepts chapter-relative references only within the book. The EPUB 2 fixture exercises an NCX entry, percent-encoded Chinese filenames and target fragments. Its external and out-of-book links are inert, the remote image is absent, and script text is skipped. The XML check rejects external DTDs and the archive check rejects a chapter above the size limit.
- EPUB samples include the earlier generated small and large publications and two [IDPF publications](https://idpf.github.io/epub3-samples/30/samples.html). Fixed-layout, protected and malformed fixtures are rejected. At present any EPUB encryption manifest is rejected, including EPUB font obfuscation.
- The Kindle build compiles the libmobi core with the system zlib and with encryption and XML writer disabled. It checks both headers of hybrid books before starting markup parsing. The tool reports extracted markup, image and font records and the Kindle navigation index. It performs no layout, and the native renderer needs to validate references and handle legacy HTML before consuming this output.

The automated matrix completed 27 normal runs and nine rejection checks. All 22 sections of Accessible EPUB 3 and all 7 sections of Internal Links produced readable blocks. In the desktop EPUB 2 check, clicking the inline link opened the Chinese-named chapter and reached the target heading. The Leaf Xcode suite passed all nine existing tests.

## Performance

The probe ran each normal fixture three times. EPUB preparation ends when the initial chapter has been converted to native blocks. A jump measures preparing the table of contents target. Kindle preparation includes reading the source and reconstructing its markup and resources. Memory is the highest process RSS reported by macOS `time -l` during the full inspection, including traversing every EPUB section. WebKit’s prior evaluation measures a post-layout first view and a group of processes.

| Sample | Median preparation (ms) | Median EPUB jump (ms) | Peak RSS (MiB) |
| --- | ---: | ---: | ---: |
| Generated small EPUB | 3.99 | 1.98 | 90.0 |
| Generated 14.19 MiB EPUB | 10.21 | 1.98 | 107.1 |
| EPUB 2 with NCX | 2.17 | 0.09 | 88.8 |
| IDPF Accessible EPUB 3 | 4.71 | 1.36 | 150.8 |
| IDPF Internal Links | 3.90 | 1.50 | 110.0 |
| MOBI 6 | 1.90 | — | 2.2 |
| MOBI 4 dictionary | 45.98 | — | 20.3 |
| Standalone KF8 | 0.42 | — | 2.1 |
| Hybrid KF8 | 1.73 | — | 2.8 |

## Dependencies and distribution

ZIPFoundation 0.9.20 supplies ZIP reading under MIT and uses the system Compression framework. The macOS 27.2 SDK has a libarchive link stub and lacks the corresponding headers, which makes ZIPFoundation the simpler explicit dependency for this probe. Its public iterator stops at encrypted or invalid entries. The prototype compiles a small extension alongside the pinned source to verify that the iterator visited the full declared directory. Production should maintain and test this validation as an explicit upstream API or reviewed patch. libmobi is available under LGPL-3.0-or-later. For any future GPLv3 distribution, package the matching source, build inputs and required notices with the chosen license treatment. [ZIPFoundation release](https://github.com/weichsel/ZIPFoundation/tree/0.9.20) · [libmobi source](https://github.com/bfabiszewski/libmobi/tree/906274205c11944b628da1c553b255acb1af7c55) · [GNU license compatibility](https://www.gnu.org/licenses/gpl-faq.html) · [Third-party notices](../THIRD_PARTY_NOTICES.md)
