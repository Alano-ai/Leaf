# Third-party notices

## Leaf application

The application builds and links the pinned sources in [Dependencies/ReaderLibraries](Dependencies/ReaderLibraries). Xcode uses this local Swift package without fetching dependencies. The app bundle includes the third-party license texts under `Contents/Resources/Licenses/`, the GPLv3 text at `Contents/Resources/LICENSE`, and this notice.

| Component | License | Source provenance |
| --- | --- | --- |
| ZIPFoundation 0.9.20, Thomas Zoechling and contributors | MIT | [Pinned release source](https://github.com/weichsel/ZIPFoundation/tree/0.9.20), source archive SHA-256 `3ddad93f81480d141f15d9b8bdc276a21c5242446c179672c2e787799a423b5e` |
| libmobi 0.12, Bartek Fabiszewski | LGPL-3.0-or-later | [Pinned revision `90627420`](https://github.com/bfabiszewski/libmobi/tree/906274205c11944b628da1c553b255acb1af7c55), source archive SHA-256 `ec260e472d4db1bcbf8c479ee470bd2a2b2b822f14313604c76e667a684e1dfa` |

ZIPFoundation retains its upstream privacy manifest and uses the system Compression framework. The Leaf additions validate the ZIP central directory, member boundaries, and encryption flags before opening an EPUB archive. This entry point accepts single-disk ZIP32 with stored or deflated members.

The libmobi target builds its reader with system zlib and uses system libxml2 to reconstruct the in-memory book navigation. Its encryption sources are omitted. Leaf changed `opf.c` on 2026-11-20 to remove per-book process-wide XML cleanup so that concurrent parsers can keep using libxml2. The package manifest records the build configuration, and the vendored file headers retain their upstream license and copyright notices.

Keep these license texts and notices with any release and provide the complete corresponding source for the exact build, including the bundled library sources and build instructions. [GNU GPLv3 and LGPLv3 terms](https://www.gnu.org/licenses/lgpl%2Bgpl-3.0-standalone.html)

## Standalone prototypes

The standalone reader prototype fetches the following source and fixtures into the ignored `build/reader-probe/` directory. Its build preserves license texts under `Contents/Resources/Notices/`.

| Component | License | Provenance |
| --- | --- | --- |
| foliate-js | MIT, John Factotum | [Pinned source, license and build files](https://github.com/johnfactotum/foliate-js/tree/78914aef4466eb960965702401634c2cb348e9b1) |
| zip.js 2.8.22 | BSD-3-Clause, Gildas Lormeau | [Source package and license](https://registry.npmjs.org/@zip.js/zip.js/-/zip.js-2.8.22.tgz) |
| SJCL code bundled by zip.js | BSD-2-Clause option, Emily Stark, Mike Hamburg and Dan Boneh at Stanford University | [Upstream license](https://github.com/bitwiseshiftleft/sjcl/blob/1.0.8/LICENSE.txt) |
| fflate 0.8.2 | MIT, Arjun Barrett | [Source package and license](https://registry.npmjs.org/fflate/-/fflate-0.8.2.tgz) |
| IBM Plex Mono | SIL Open Font License 1.1, test fixture font | [Pinned font and license](https://github.com/google/fonts/tree/633f3200539c52ee0aba2dfd7f46921417a81877/ofl/ibmplexmono) |

The prototype uses foliate-js’s checked-in zip.js and fflate bundles. The versions listed above are from the pinned upstream lockfile. The ZIP bundle includes the SJCL codec, which is why its notice is included. `foliate.patch` changes the iframe sandbox on both layout paths and adds protected-book rejection to the MOBI/KF8 parser.

The libmobi sample books are downloaded for local verification only. Production distribution should omit test books and fonts, preserve the license and copyright notices for included code, and make the corresponding source and build inputs available for the exact release. [Pinned libmobi fixtures](https://github.com/bfabiszewski/libmobi/tree/906274205c11944b628da1c553b255acb1af7c55/tests/samples) · [GNU GPLv3 distribution terms](https://www.gnu.org/licenses/gpl-3.0.html)

The [native reader probe](Prototypes/NativeReader/README.md) also stages the following materials under `build/native-reader/`.

| Component | License or terms | Provenance |
| --- | --- | --- |
| ZIPFoundation 0.9.20 | MIT, Thomas Zoechling | [Pinned release source and license](https://github.com/weichsel/ZIPFoundation/tree/0.9.20) |
| libmobi 0.12 | LGPL-3.0-or-later, Bartek Fabiszewski | [Pinned source and COPYING](https://github.com/bfabiszewski/libmobi/tree/906274205c11944b628da1c553b255acb1af7c55) |
| Accessible EPUB 3 and Internal Links | IDPF sample publications used for local evaluation. Retain the notices in their package metadata. | [Sample descriptions and licensing](https://idpf.github.io/epub3-samples/30/samples.html) |
