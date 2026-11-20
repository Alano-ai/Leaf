#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

cd "$(dirname "$0")"
source_dir="$PWD"
out="$source_dir/../../build/reader-probe"
upstream="$out/upstream"
revision=78914aef4466eb960965702401634c2cb348e9b1
archive_sha=4878cd5f04073af5046ea543da73a963a7f9e1a4b30ddc63ac86cea5adf02f38
libmobi=906274205c11944b628da1c553b255acb1af7c55
font_revision=633f3200539c52ee0aba2dfd7f46921417a81877
app="$out/LeafReaderProbe.app"
entitlements=ReaderProbe.entitlements
case "${1:-}" in
    "") ;;
    --webkit-network-entitlement)
        app="$out/LeafReaderProbeWebKit.app"
        entitlements="$out/WebKitProbe.entitlements"
        ;;
    *) printf 'Usage: %s [--webkit-network-entitlement]\n' "$0" >&2; exit 2 ;;
esac
resources="$app/Contents/Resources"
web="$resources/Web"
fixtures="$resources/Fixtures"
notices="$resources/Notices"

download() {
    if [[ ! -s "$2" ]]; then
        curl --fail --silent --show-error --location --max-time 90 "$1" -o "$2.part"
        mv "$2.part" "$2"
    fi
}

mkdir -p "$upstream" "$out/samples" "$web/foliate/vendor" "$fixtures" "$notices" "$app/Contents/MacOS"
download "https://codeload.github.com/johnfactotum/foliate-js/tar.gz/$revision" "$out/foliate-js.tar.gz"
printf '%s  %s\n' "$archive_sha" "$out/foliate-js.tar.gz" | shasum -a 256 -c
tar -xzf "$out/foliate-js.tar.gz" -C "$upstream" --strip-components 1

for sample in sample-cp1252 sample-dict-fileversion4 sample-obfuscated-fonts sample-multimedia; do
    download "https://raw.githubusercontent.com/bfabiszewski/libmobi/$libmobi/tests/samples/$sample.mobi" "$out/samples/$sample.mobi"
done
font_base="https://raw.githubusercontent.com/google/fonts/$font_revision/ofl/ibmplexmono"
download "$font_base/IBMPlexMono-Regular.ttf" "$out/samples/IBMPlexMono-Regular.ttf"
download "$font_base/OFL.txt" "$out/samples/IBMPlexMono-OFL.txt"
download "https://registry.npmjs.org/@zip.js/zip.js/-/zip.js-2.8.22.tgz" "$out/zip.js-2.8.22.tgz"
download "https://registry.npmjs.org/fflate/-/fflate-0.8.2.tgz" "$out/fflate-0.8.2.tgz"
download "https://raw.githubusercontent.com/bitwiseshiftleft/sjcl/1.0.8/LICENSE.txt" "$out/sjcl-LICENSE.txt"

(
    cd "$out"
    shasum -a 256 -c <<'CHECKSUMS'
e77aa8f99d65f12bc7b5d71f272a2a4a8f36fe6d5c00e9b95c8a926b145ad088  samples/sample-cp1252.mobi
e73f3c552205fabdf426d28b5742d98e157f5bc8ea353fd2c029be0d91ad8aee  samples/sample-dict-fileversion4.mobi
34fc67043eeeaa6563481d6ea2fea1b5349cb73e459a1f10e3aa09186f56302e  samples/sample-obfuscated-fonts.mobi
a301cce8187f1f1ea9562196c46328ca75585da280d4b742827cebd4698697c9  samples/sample-multimedia.mobi
6a3412f058c7d8dfd9170c41e85ade48e5156ecb89356110ca57a0a27734af46  samples/IBMPlexMono-Regular.ttf
7e6b2818edbd8f6a01ae80641cc8f16a51080d08fb4e532be3a0b6f74adb07da  samples/IBMPlexMono-OFL.txt
33861767acfb736702739a267a9324bf4bc7ef57e83aa10089767a4056dc8c54  zip.js-2.8.22.tgz
61fd5061e2fc8e5e3e3129f7f2fec7bd78a313e1bf4becbf1cc1cc9998d141dc  fflate-0.8.2.tgz
ef430277d3cca1d3e7cdb6d4a61d7ff1eb208c4c2058602d2b361aaab60cd9c0  sjcl-LICENSE.txt
CHECKSUMS
)

for module in view epub epubcfi mobi paginator fixed-layout progress overlayer text-walker; do
    cp "$upstream/$module.js" "$web/foliate/"
done
cp "$upstream/vendor/"{zip,fflate}.js "$web/foliate/vendor/"
cp "$upstream/LICENSE" "$notices/foliate-js.txt"
tar -xOzf "$out/zip.js-2.8.22.tgz" package/LICENSE > "$notices/zip.js.txt"
tar -xOzf "$out/fflate-0.8.2.tgz" package/LICENSE > "$notices/fflate.txt"
cp "$out/sjcl-LICENSE.txt" "$notices/sjcl.txt"
cp "$out/samples/IBMPlexMono-OFL.txt" "$notices/IBM-Plex-Mono.txt"
patch --silent -d "$web/foliate" -p0 < foliate.patch
cp Web/index.html Web/reader.js "$web/"

/usr/bin/python3 fixtures.py "$out/samples" "$fixtures"
xcrun --sdk macosx swift protected-pdf.swift "$fixtures/protected.pdf"
cp Info.plist "$app/Contents/"
if [[ "$entitlements" != ReaderProbe.entitlements ]]; then
    cp ReaderProbe.entitlements "$entitlements"
    /usr/libexec/PlistBuddy -c 'Add :com.apple.security.network.client bool true' "$entitlements"
    plutil -replace CFBundleIdentifier -string ai.alano.Leaf.ReaderProbeWebKit "$app/Contents/Info.plist"
fi
xcrun --sdk macosx swiftc -swift-version 6 -target arm64-apple-macosx26.0 -O -parse-as-library \
    ReaderProbe.swift WebReader.swift -o "$app/Contents/MacOS/LeafReaderProbe"
codesign --force --sign - --entitlements "$entitlements" "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
