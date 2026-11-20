#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

version=${1:-}
output=${2:-build/distribution}
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ $# -le 2 && $version =~ $version_pattern ]] || fail "Usage: bash scripts/package-dmg.sh MAJOR.MINOR.PATCH [output-directory]"
[[ $(uname -m) == arm64 ]] || fail "Run this script on an Apple Silicon Mac."

cd "$(dirname "$0")/.."
signed=false
if [[ -n ${LEAF_CERTIFICATE_P12:-}${LEAF_CERTIFICATE_PASSWORD:-}${LEAF_NOTARY_KEY:-}${LEAF_NOTARY_KEY_ID:-}${LEAF_NOTARY_ISSUER_ID:-} ]]; then
    : "${LEAF_CERTIFICATE_P12:?Set LEAF_CERTIFICATE_P12 for a Developer ID release.}"
    : "${LEAF_CERTIFICATE_PASSWORD:?Set LEAF_CERTIFICATE_PASSWORD for a Developer ID release.}"
    : "${LEAF_NOTARY_KEY:?Set LEAF_NOTARY_KEY for a Developer ID release.}"
    : "${LEAF_NOTARY_KEY_ID:?Set LEAF_NOTARY_KEY_ID for a Developer ID release.}"
    : "${LEAF_NOTARY_ISSUER_ID:?Set LEAF_NOTARY_ISSUER_ID for a Developer ID release.}"
    export -n LEAF_CERTIFICATE_P12 LEAF_CERTIFICATE_PASSWORD LEAF_NOTARY_KEY \
        LEAF_NOTARY_KEY_ID LEAF_NOTARY_ISSUER_ID
    signed=true
fi

mkdir -p "$output"
output=$(cd "$output" && pwd -P)
work=$(mktemp -d "$output/.package.XXXXXXXX")
keychain=
mounted=false
mount_point="$work/mount"
cleanup() {
    if [[ $mounted == true ]]; then
        hdiutil detach "$mount_point" >&2 || return 1
    fi
    if [[ -n $keychain ]]; then
        security delete-keychain "$keychain" >&2 || return 1
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

build="$work/DerivedData"
xcodebuild -project Leaf.xcodeproj -scheme Leaf -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build" \
    ARCHS=arm64 MARKETING_VERSION="$version" build

staging="$work/staging"
mkdir -p "$staging"
app="$staging/Leaf.app"
ditto "$build/Build/Products/Release/Leaf.app" "$app"
ln -s /Applications "$staging/Applications"
cp LICENSE THIRD_PARTY_NOTICES.md "$staging/"
ditto Dependencies/ReaderLibraries/Licenses "$staging/Licenses"

if [[ $signed == true ]]; then
    # Keep the imported identity in a disposable keychain.
    mkdir -m 700 "$work/signing"
    certificate="$work/signing/DeveloperID.p12"
    notary_key="$work/signing/NotaryKey.p8"
    printf '%s' "$LEAF_CERTIFICATE_P12" | base64 -D > "$certificate"
    printf '%s' "$LEAF_NOTARY_KEY" | base64 -D > "$notary_key"
    keychain="$work/signing/release.keychain-db"
    keychain_password=$(openssl rand -hex 24)
    security create-keychain -p "$keychain_password" "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security import "$certificate" -k "$keychain" -f pkcs12 \
        -P "$LEAF_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"
    identity=$(security find-identity -v -p codesigning "$keychain" | awk '/"Developer ID Application:/{ print $2 }')
    [[ $identity =~ ^[A-Fa-f0-9]{40}$ ]] || fail "Provide exactly one valid Developer ID Application signing identity."
    codesign --force --sign "$identity" --keychain "$keychain" --options runtime --timestamp \
        --entitlements Leaf/Leaf.entitlements "$app"
fi

codesign --verify --deep --strict "$app"
name="Leaf-$version-arm64.dmg"
dmg="$work/$name"
hdiutil create -volname "Leaf $version" -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"

if [[ $signed == true ]]; then
    codesign --sign "$identity" --keychain "$keychain" --timestamp "$dmg"
    result="$work/notary-result.plist"
    xcrun notarytool submit "$dmg" --key "$notary_key" --key-id "$LEAF_NOTARY_KEY_ID" \
        --issuer "$LEAF_NOTARY_ISSUER_ID" --wait --timeout 15m --output-format plist > "$result"
    plutil -p "$result"
    [[ $(plutil -extract status raw "$result") == Accepted ]] || fail "Apple did not accept the disk image."
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
fi

hdiutil verify "$dmg"
mkdir "$mount_point"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$dmg"
mounted=true
mounted_app="$mount_point/Leaf.app"
codesign --verify --deep --strict "$mounted_app"
[[ $(lipo -archs "$mounted_app/Contents/MacOS/Leaf") == arm64 ]] || fail "The app must contain an arm64 executable."
[[ $(plutil -extract CFBundleShortVersionString raw "$mounted_app/Contents/Info.plist") == "$version" ]] \
    || fail "The app version does not match the requested version."
[[ $(readlink "$mount_point/Applications") == /Applications ]] || fail "The Applications link is missing."
cmp LICENSE "$mount_point/LICENSE"
cmp THIRD_PARTY_NOTICES.md "$mount_point/THIRD_PARTY_NOTICES.md"
diff -r Dependencies/ReaderLibraries/Licenses "$mount_point/Licenses"
hdiutil detach "$mount_point"
mounted=false

mv "$dmg" "$output/$name"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
    printf 'notarized=%s\n' "$signed" >> "$GITHUB_OUTPUT"
fi
printf 'Created %s\n' "$output/$name"
