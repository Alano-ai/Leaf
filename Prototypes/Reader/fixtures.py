# SPDX-License-Identifier: GPL-3.0-only
"""Generate deterministic fixtures with owned content and stage public samples."""
import random
import shutil
import struct
import sys
import zipfile
import zlib
from pathlib import Path


def png(size, seed):
    generator = random.Random(seed)
    pixels = b"".join(b"\x00" + generator.randbytes(size * 3) for _ in range(size))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def epub(path, font, chapters, image_size, *, protected=False, fixed=False):
    def xhtml(body):
        return f'<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh"><head><title>Leaf fixture</title>' \
               '<meta name="viewport" content="width=960,height=620"/>' \
               '<link rel="stylesheet" href="style.css"/></head><body>' + body + '</body></html>'

    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as book:
        book.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        book.writestr("META-INF/container.xml",
                      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
                      '<rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/>'
                      '</rootfiles></container>')
        manifest = [
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
            '<item id="css" href="style.css" media-type="text/css"/>',
            '<item id="font" href="probe.ttf" media-type="font/ttf"/>',
        ]
        spine = []
        toc = []
        for index in range(1, chapters + 1):
            page = f"chapter-{index}"
            manifest.append(f'<item id="{page}" href="{page}.xhtml" media-type="application/xhtml+xml"/>')
            manifest.append(f'<item id="image-{index}" href="{page}.png" media-type="image/png"/>')
            spine.append(f'<itemref idref="{page}"/>')
            toc.append(f'<li><a href="{page}.xhtml">Chapter {index}</a></li>')
            text = '<p>山海之间，Leaf tests mixed Chinese and Latin typography.</p>'
            probes = '''<script id="book-script-probe">document.documentElement.dataset.bookScriptRan = 'yes';</script>
                <img id="offline-probe" src="http://127.0.0.1:47881/leaf.png" alt=""/>
                <img id="local-file-probe" src="file:///System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns" alt=""/>''' if index == 1 else ""
            body = f'<h1>Chapter {index}</h1><img id="book-image" src="{page}.png" alt="Sample image"/>' \
                   f'{probes}{text * (1 if fixed else 70)}'
            book.writestr(f"{page}.xhtml", xhtml(body))
            book.writestr(f"{page}.png", png(image_size, index))
        rendition = '<meta property="rendition:layout">pre-paginated</meta>' if fixed else ""
        book.writestr("book.opf",
                      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">'
                      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">'
                      'urn:leaf:fixture</dc:identifier><dc:title>Leaf fixture</dc:title><dc:language>zh</dc:language>'
                      '<meta property="dcterms:modified">2026-11-20T00:00:00Z</meta>' + rendition
                      + "</metadata><manifest>" + "".join(manifest) + "</manifest><spine>"
                      + "".join(spine) + "</spine></package>")
        book.writestr("nav.xhtml", xhtml('<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="toc"><ol>'
                                        + "".join(toc) + "</ol></nav>"))
        book.writestr("style.css", '@font-face {font-family: Probe; src: url(probe.ttf)}'
                                  'body {font-family: Probe, serif} #book-image {width:120px;height:auto}')
        book.write(font, "probe.ttf")
        if protected:
            book.writestr("META-INF/encryption.xml", "<encryption/>")


def pdf(path, count):
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               f'<< /Type /Pages /Count {count} /Kids [{" ".join(f"{4 + i * 2} 0 R" for i in range(count))}] >>'.encode(),
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    for i in range(count):
        objects.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 540 720] '
                       f'/Resources << /Font << /F1 3 0 R >> >> /Contents {5 + i * 2} 0 R >>'.encode())
        lines = f"BT /F1 18 Tf 40 660 Td (Leaf PDF page {i + 1}) Tj\n" + (
            "0 -18 Td (Native PDFKit renders this fixture.) Tj\n" * 25) + "ET"
        stream = lines.encode()
        objects.append(f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream")
    with path.open("wb") as file:
        file.write(b"%PDF-1.4\n")
        offsets = [0]
        for index, obj in enumerate(objects, 1):
            offsets.append(file.tell())
            file.write(f"{index} 0 obj\n".encode() + obj + b"\nendobj\n")
        xref = file.tell()
        file.write(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
        for offset in offsets[1:]:
            file.write(f"{offset:010d} 00000 n \n".encode())
        file.write(f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())


samples, fixtures = map(Path, sys.argv[1:3])
font = samples / "IBMPlexMono-Regular.ttf"
epub(fixtures / "small.epub", font, 3, 48)
epub(fixtures / "large.epub", font, 38, 360)
epub(fixtures / "fixed.epub", font, 3, 48, fixed=True)
epub(fixtures / "protected.epub", font, 2, 48, protected=True)
(fixtures / "malformed.epub").write_bytes(b"PK\x03\x04truncated")
for output, source in {
    "small.mobi": "sample-cp1252",
    "large.mobi": "sample-dict-fileversion4",
    "small.azw3": "sample-obfuscated-fonts",
    "large.azw3": "sample-multimedia",
}.items():
    shutil.copyfile(samples / f"{source}.mobi", fixtures / output)
mobi = bytearray((fixtures / "small.mobi").read_bytes())
first_record = struct.unpack_from(">I", mobi, 78)[0]
struct.pack_into(">H", mobi, first_record + 12, 1)
(fixtures / "protected.mobi").write_bytes(mobi)
kf8 = bytearray((fixtures / "small.azw3").read_bytes())
first_record = struct.unpack_from(">I", kf8, 78)[0]
struct.pack_into(">H", kf8, first_record + 12, 1)
(fixtures / "protected.azw3").write_bytes(kf8)
(fixtures / "malformed.mobi").write_bytes(b"invalid Kindle data")
(fixtures / "malformed.azw3").write_bytes(b"invalid Kindle data")
pdf(fixtures / "small.pdf", 3)
pdf(fixtures / "large.pdf", 320)
(fixtures / "malformed.pdf").write_bytes(b"%PDF-1.4\ninvalid")
line = "山海之间 · Leaf renders mixed Chinese and Latin text.\n"
(fixtures / "small.txt").write_bytes((line * 55).encode("utf-8"))
(fixtures / "large.txt").write_bytes((line * 28000).encode("utf-16"))
(fixtures / "legacy.txt").write_bytes((line * 55).encode("gb18030"))
(fixtures / "malformed.txt").write_bytes(b"\x00\x00\x81")
