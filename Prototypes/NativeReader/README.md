# Native Reader Probe

This standalone macOS probe evaluates reflowable EPUB in SwiftUI and MOBI/KF8 parsing in a separate command-line tool. The EPUB app uses the same sandbox entitlements as Leaf. The Kindle tool links a pinned libmobi build with encryption support disabled.

Build both tools from the repository root on Apple Silicon. The first build fetches pinned source archives and two IDPF sample publications. Xcode Command Line Tools and Python 3 are sufficient.

```sh
bash Prototypes/NativeReader/build.sh
open build/native-reader/LeafNativeReaderProbe.app
```

In the app, select **Open** for a local reflowable EPUB, or choose a publication in **Samples**. Use **Contents**, the section buttons, or an internal link in the text to navigate.

The full check reuses the generated and Kindle fixtures from the earlier probe. Build the earlier probe first if that cache is unavailable, then rebuild the native probe so it can stage the EPUB fixtures.

```sh
bash Prototypes/Reader/build.sh
bash Prototypes/NativeReader/build.sh
/usr/bin/python3 Prototypes/NativeReader/check.py
```

The EPUB app also accepts `--inspect <fixture-name>` from its executable. The Kindle tool accepts a local unprotected MOBI or AZW3 path. See the [native reading decision](../../docs/native-reader-evaluation.md) for the compatibility findings, measurement method and integration gates.
