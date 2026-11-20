# Releasing Leaf

GitHub Actions tests the shared Xcode scheme and the two Swift packages on Apple Silicon with Xcode 27.2. Pull requests, pushes to `main` and manual branch runs upload a DMG for testing. A push of a `vMAJOR.MINOR.PATCH` tag also publishes a GitHub Release. [GitHub runner image and Xcode versions](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md#xcode)

## Prepare a release

Start from a reviewed commit that passed the macOS workflow. For example, to release version 0.1.1, create and push the tag from that commit.

```sh
git tag -a v0.1.1 -m "Leaf 0.1.1"
git push origin refs/tags/v0.1.1
```

The tag sets the app version. The release includes `Leaf-0.1.1-arm64.dmg`, `Leaf-0.1.1-source.tar.gz` and `SHA256SUMS`. The source archive comes from the commit that produced the app and includes the vendored sources and build scripts. The DMG presents Leaf and an Applications shortcut in a Finder window. The app bundle contains the license notices. Each version tag publishes a new release with its own assets.

## Signing and notarization

With no signing secrets configured, the tag produces an ad-hoc signed preview. Gatekeeper may block downloaded previews. To publish notarized builds, configure all five GitHub Actions secrets in the repository.

| Secret | Value |
| --- | --- |
| `LEAF_CERTIFICATE_P12` | Base64 of a password-protected PKCS#12 export of one Developer ID Application certificate and its private key |
| `LEAF_CERTIFICATE_PASSWORD` | Password for the PKCS#12 export |
| `LEAF_NOTARY_KEY` | Base64 of the team App Store Connect API key file used by the notary service |
| `LEAF_NOTARY_KEY_ID` | App Store Connect API key ID |
| `LEAF_NOTARY_ISSUER_ID` | App Store Connect API issuer ID |

The packaging script imports the identity into a temporary keychain, signs the app and DMG, submits the DMG to Apple and staples the accepted ticket. Publication stops if credentials are incomplete or signing or notarization fails. Keep private keys out of the repository. [Apple notarization guidance](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## Check the published release

Download the three release assets to the same folder and run `shasum -a 256 -c SHA256SUMS`. On a clean Apple Silicon Mac running macOS 26 or later, open the downloaded DMG, check that Finder shows the drag-to-Applications window, then copy and launch Leaf. For a notarized release, confirm that Gatekeeper accepts a normal first launch and run `xcrun stapler validate Leaf-0.1.1-arm64.dmg` to check the attached ticket.

The checked-in [installer design](../Design/README.md) lets CI package the Finder layout with native macOS utilities.
