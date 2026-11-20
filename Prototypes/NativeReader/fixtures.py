# SPDX-License-Identifier: GPL-3.0-only
"""Build a small EPUB 2 fixture with an NCX and local, blocked, and labeled content."""
import sys
import zipfile
from pathlib import Path


out = Path(sys.argv[1])
with zipfile.ZipFile(out / "legacy.epub", "w", zipfile.ZIP_DEFLATED) as book:
    book.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    book.writestr("META-INF/container.xml",
                  '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
                  '<rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/>'
                  '</rootfiles></container>')
    book.writestr("OPS/book.opf",
                  '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="identity">'
                  '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                  '<dc:identifier id="identity">urn:leaf:native-probe</dc:identifier>'
                  '<dc:title>Leaf NCX fixture</dc:title><dc:language>zh</dc:language></metadata>'
                  '<manifest><item id="toc" href="reader.ncx" media-type="application/x-dtbncx+xml"/>'
                  '<item id="first" href="chapters/first.xhtml" media-type="application/xhtml+xml"/>'
                  '<item id="second" href="chapters/山海.xhtml" media-type="application/xhtml+xml"/>'
                  '</manifest><spine toc="toc"><itemref idref="first"/><itemref idref="second"/></spine>'
                  '</package>')
    book.writestr("OPS/reader.ncx", '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
                  '<head><meta name="dtb:uid" content="urn:leaf:native-probe"/></head>'
                  '<docTitle><text>Leaf NCX fixture</text></docTitle><navMap>'
                  '<navPoint id="p1" playOrder="1"><navLabel><text>Chapter one</text></navLabel>'
                  '<content src="chapters/first.xhtml"/></navPoint>'
                  '<navPoint id="p2" playOrder="2"><navLabel><text>第二章</text></navLabel>'
                  '<content src="chapters/%E5%B1%B1%E6%B5%B7.xhtml#destination"/></navPoint></navMap></ncx>')
    book.writestr("OPS/chapters/first.xhtml",
                  '<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>First</title></head>'
                  '<body><h1>Chapter one</h1><p>Read <em>text</em> from the EPUB archive.</p>'
                  '<p><a href="%E5%B1%B1%E6%B5%B7.xhtml#destination">Go to 第二章</a> '
                  '<a href="https://example.invalid/">External label</a> '
                  '<a href="../../../../outside.xhtml">Outside label</a> '
                  '<a href="file:///tmp/leaf-content">File label</a></p>'
                  '<script>BOOK_SCRIPT_MARKER</script>'
                  '<img src="https://example.invalid/picture.png" alt="Remote fixture"/>'
                  '</body></html>')
    book.writestr("OPS/chapters/山海.xhtml",
                  '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title></head>'
                  '<body><h1 id="destination">第二章</h1><p>山海之间</p></body></html>')

for name, replacement in (
    ("oversize-chapter.epub", "<html><body>" + "a" * 4_000_000 + "</body></html>"),
    ("remote-entity.epub", '<!DOCTYPE html SYSTEM "https://example.invalid/book.dtd"><html><body>Text</body></html>'),
):
    with zipfile.ZipFile(out / "legacy.epub") as original, zipfile.ZipFile(out / name, "w") as changed:
        for entry in original.infolist():
            data = replacement if entry.filename == "OPS/chapters/first.xhtml" else original.read(entry)
            changed.writestr(entry, data)
