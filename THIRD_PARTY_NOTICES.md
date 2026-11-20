# Third-party notices

The standalone reader prototype fetches the following source and fixtures into the ignored `build/reader-probe/` directory. Its build preserves license texts under `Contents/Resources/Notices/`. The Leaf application target uses the system SDK.

| Component | License | Provenance |
| --- | --- | --- |
| foliate-js | MIT, John Factotum | [Pinned source, license and build files](https://github.com/johnfactotum/foliate-js/tree/78914aef4466eb960965702401634c2cb348e9b1) |
| zip.js 2.8.22 | BSD-3-Clause, Gildas Lormeau | [Source package and license](https://registry.npmjs.org/@zip.js/zip.js/-/zip.js-2.8.22.tgz) |
| SJCL code bundled by zip.js | BSD-2-Clause option, Emily Stark, Mike Hamburg and Dan Boneh at Stanford University | [Upstream license](https://github.com/bitwiseshiftleft/sjcl/blob/1.0.8/LICENSE.txt) |
| fflate 0.8.2 | MIT, Arjun Barrett | [Source package and license](https://registry.npmjs.org/fflate/-/fflate-0.8.2.tgz) |
| IBM Plex Mono | SIL Open Font License 1.1, test fixture font | [Pinned font and license](https://github.com/google/fonts/tree/633f3200539c52ee0aba2dfd7f46921417a81877/ofl/ibmplexmono) |

The prototype uses foliate-js’s checked-in zip.js and fflate bundles. The versions listed above are from the pinned upstream lockfile. The ZIP bundle includes the SJCL codec, which is why its notice is included. `foliate.patch` changes the iframe sandbox on both layout paths and adds protected-book rejection to the MOBI/KF8 parser.

The libmobi sample books are downloaded for local verification only. Production distribution should omit test books and fonts, preserve the license and copyright notices for included code, and make the corresponding source and build inputs available for the exact release. [Pinned libmobi fixtures](https://github.com/bfabiszewski/libmobi/tree/906274205c11944b628da1c553b255acb1af7c55/tests/samples) · [GNU GPLv3 distribution terms](https://www.gnu.org/licenses/gpl-3.0.html)
