#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

cd "$(dirname "$0")"
source_dir="$PWD"
root="$source_dir/../.."
out="$root/build/native-reader"
app="$out/LeafNativeReaderProbe.app"
resources="$app/Contents/Resources"
fixtures="$resources/Fixtures"
reader_fixtures="$root/build/reader-probe/LeafReaderProbe.app/Contents/Resources/Fixtures"
mkdir -p "$out/zipfoundation" "$out/libmobi" "$app/Contents/MacOS" "$resources/Notices" "$fixtures"

download() {
    if [[ ! -s "$out/$2" ]]; then
        curl --fail --silent --show-error --location --max-time 90 "$1" -o "$out/$2.part"
        mv "$out/$2.part" "$out/$2"
    fi
}

download https://codeload.github.com/weichsel/ZIPFoundation/tar.gz/refs/tags/0.9.20 zipfoundation.tar.gz
download https://codeload.github.com/bfabiszewski/libmobi/tar.gz/906274205c11944b628da1c553b255acb1af7c55 libmobi.tar.gz
download 'https://github.com/IDPF/epub3-samples/releases/download/20230704/accessible_epub_3.epub?download=1' idpf-accessible.epub
download 'https://github.com/IDPF/epub3-samples/releases/download/20230704/internallinks.epub?download=1' idpf-links.epub
(
    cd "$out"
    shasum -a 256 -c <<'CHECKSUMS'
3ddad93f81480d141f15d9b8bdc276a21c5242446c179672c2e787799a423b5e  zipfoundation.tar.gz
ec260e472d4db1bcbf8c479ee470bd2a2b2b822f14313604c76e667a684e1dfa  libmobi.tar.gz
67f75b8e3cd1abe4bb143d91d5424191d5af3115c9d26ff029a38e19f8d16feb  idpf-accessible.epub
deaf03a1843f52cc5e4cedb226ca8659610efe1be5e810fccf615bcb549238aa  idpf-links.epub
CHECKSUMS
)
tar -xzf "$out/zipfoundation.tar.gz" -C "$out/zipfoundation" --strip-components 1
tar -xzf "$out/libmobi.tar.gz" -C "$out/libmobi" --strip-components 1
cp "$out/zipfoundation/LICENSE" "$resources/Notices/ZIPFoundation.txt"
cp "$out/libmobi/COPYING" "$out/libmobi-LICENSE.txt"
cp "$out"/idpf-{accessible,links}.epub "$fixtures/"
if [[ -d "$reader_fixtures" ]]; then
    cp "$reader_fixtures"/{small,large,fixed,protected,malformed}.epub "$fixtures/"
fi
/usr/bin/python3 fixtures.py "$fixtures"

xcrun --sdk macosx swiftc -target arm64-apple-macosx26.0 -O -emit-library -static -emit-module \
    -module-name ZIPFoundation -emit-module-path "$out/ZIPFoundation.swiftmodule" \
    "$out/zipfoundation/Sources/ZIPFoundation/"*.swift ZIPDirectory.swift -o "$out/libZIPFoundation.a"
xcrun --sdk macosx swiftc -swift-version 6 -target arm64-apple-macosx26.0 -O -parse-as-library \
    -I "$out" -L "$out" -lZIPFoundation NativeReaderApp.swift NativeEPUB.swift EPUBChapter.swift \
    -o "$app/Contents/MacOS/LeafNativeReaderProbe"

cp "$root/Prototypes/Reader/Info.plist" "$app/Contents/"
plist="$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string LeafNativeReaderProbe "$plist"
plutil -replace CFBundleIdentifier -string ai.alano.Leaf.NativeReaderProbe "$plist"
plutil -replace CFBundleName -string 'Leaf Native Reader Probe' "$plist"
codesign --force --sign - --entitlements "$root/Leaf/Leaf.entitlements" "$app"
codesign --verify --strict "$app"

# Match the upstream core build with zlib enabled and encryption and XML writer disabled.
mobi="$out/libmobi/src"
xcrun --sdk macosx clang -arch arm64 -mmacosx-version-min=26.0 -std=gnu99 -O2 \
    -DPACKAGE_VERSION='"0.12"' -DHAVE_UNISTD_H -DHAVE_STRDUP -DMOBI_INLINE=inline -I "$mobi" \
    kindle-probe.c "$mobi"/{buffer,compression,debug,index,memory,meta,parse_rawml,read,structure,util,write}.c \
    -lz -o "$out/kindle-probe"
printf '%s\n' "$app"
