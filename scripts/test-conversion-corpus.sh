#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

if [[ $# != 2 ]]; then
    printf 'Usage: bash %s SAMPLE_DIRECTORY REPORT.json\n' "$0" >&2
    exit 2
fi

samples=$(cd "$1" && pwd -P)
report="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
cd "$(dirname "$0")/.."
work="$PWD/build/conversion-corpus.noindex"
derived="${LEAF_CORPUS_DERIVED_DATA:-$work/xcode}"
mkdir -p "$work"
work=$(mktemp -d "$work/run.XXXXXXXX")
trap 'rm -rf "$work"' EXIT

xcodebuild -project Leaf.xcodeproj -scheme Leaf -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" build
products="$derived/Build/Products/Debug"
binary="$products/Leaf.app/Contents/MacOS"
module_map="$derived/Build/Intermediates.noindex/GeneratedModuleMaps/CLibMobi.modulemap"
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$work/modules" \
    -I "$products" -Xcc "-fmodule-map-file=$module_map" scripts/ConversionCorpus.swift \
    "$binary/Leaf.debug.dylib" -Xlinker -rpath -Xlinker "$binary" -o "$work/leaf-corpus"
"$work/leaf-corpus" "$samples" "$report" "$work"
