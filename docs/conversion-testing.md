# Conversion corpus testing

Use a mix of complete books and specification fixtures. Keep the sample files, downloads and test reports under the ignored `build/` directory. Check the license for each downloaded edition before redistributing its source or converted copies.

| Source | Useful coverage |
| --- | --- |
| [GITenberg](https://github.com/GITenberg) | Project Gutenberg books organized as one Git repository per book. Useful for whole-book TXT, editions with long chapters, and a range of languages and typographic conventions. Check the rights metadata for the selected book. |
| [Standard Ebooks](https://standardebooks.org/ebooks) | Edited, whole-book EPUB and AZW3 editions. Contributions are dedicated to the public domain via CC0, with underlying text and art evaluated for the U.S. public domain. [Example edition license](https://github.com/standardebooks/mary-shelley_frankenstein/blob/master/LICENSE.md) |
| [IDPF EPUB 3 Samples](https://github.com/IDPF/epub3-samples) | Illustrated books, CJK and Arabic, tables, fonts and layout variants. The sample table lists exceptions to the default CC BY-SA 3.0 license. [Download table](https://idpf.github.io/epub3-samples/30/samples.html) |
| [W3C EPUB Tests](https://github.com/w3c/epub-tests) | Targeted tests for packaging, manifest fallbacks, navigation, fixed layout and other features. Some fixtures intentionally exercise features outside Leaf’s scope. [License](https://github.com/w3c/epub-tests/blob/main/LICENSE.md) · [OPDS catalog](https://w3c.github.io/epub-tests/opds/opds.json) |

## Run the local corpus

Place the selected files together in a directory. Include independently generated MOBI and PDF inputs where available. The runner uses the same Swift conversion code and readers as the app and works offline.

```sh
mkdir -p build/conversion-corpus.noindex
bash scripts/test-conversion-corpus.sh /path/to/samples build/conversion-corpus.noindex/report.json
```

The report records each source filename and its SHA-256, the target format, the local checks on both files, and the outcome. Each attempt reopens the result and verifies the source checksum. Unsupported inputs and cases without usable text are counted separately. A failed conversion or unreadable result causes a nonzero exit. Format counts and successful reopens cover a subset of conversion correctness. Test rendering with an independent reader and verify the actual delivery method on a Kindle before claiming device compatibility. [Amazon Kindle transfer guidance](https://digprjsurvey.amazon.com/csad/help/node/TCUBEdEkbIhK07ysFu)
