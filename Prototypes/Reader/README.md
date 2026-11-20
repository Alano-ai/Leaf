# Leaf Reader Probe

This standalone SwiftUI app exercises EPUB, MOBI, AZW3, PDF and TXT using local files. It uses the Xcode SDK, Python 3 from Xcode Command Line Tools, and macOS command-line utilities. The build downloads pinned, checksum-verified test inputs and stages them under `build/reader-probe/`. Once cached, the build and normal reader session work without a connection.

## Build and run

Run these commands from the repository root on Apple Silicon.

```sh
bash Prototypes/Reader/build.sh
open build/reader-probe/LeafReaderProbe.app
```

Use **Samples** to open a PDF or TXT, or **Open** to choose your own unprotected file. The toolbar provides paging, chapter navigation when present, and PDF zoom.

On the tested macOS version, WebKit terminates its content process when the app sandbox has no network-client entitlement. The comparison build gives only the standalone prototype that entitlement. Its custom resource scheme, content policy and navigation restrictions serve local reading. Use the comparison build to try EPUB, MOBI or AZW3.

```sh
bash Prototypes/Reader/build.sh --webkit-network-entitlement
open build/reader-probe/LeafReaderProbeWebKit.app
```

## Reproduce the checks

Build both variants, then run the following command in a macOS desktop session. The harness briefly listens on `127.0.0.1:47881` to check that EPUB content makes no requests to a reachable test endpoint. It writes latency, sampled memory, and functional checks as JSON lines.

```sh
/usr/bin/python3 Prototypes/Reader/benchmark.py > build/reader-probe/results.jsonl
```

The generated prototype bundles contain local test fixtures. See [the decision record](../../docs/reader-engine-evaluation.md) for results and [third-party notices](../../THIRD_PARTY_NOTICES.md) for sources.
