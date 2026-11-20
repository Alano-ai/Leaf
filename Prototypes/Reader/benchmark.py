# SPDX-License-Identifier: GPL-3.0-only
"""Run the local sample matrix and record timings and sampled RSS."""
import argparse
import http.client
import json
import subprocess
import tempfile
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


WEB = ["small.epub", "large.epub", "fixed.epub", "small.mobi", "large.mobi", "small.azw3", "large.azw3"]
NATIVE = ["small.pdf", "large.pdf", "small.txt", "large.txt", "legacy.txt"]
INVALID = {
    "protected.epub": "Protected EPUB",
    "protected.mobi": "Protected MOBI/KF8",
    "protected.azw3": "Protected MOBI/KF8",
    "protected.pdf": "Protected PDF",
    "malformed.epub": "File format is not recognized",
    "malformed.mobi": "Invalid MOBI/KF8",
    "malformed.azw3": "Invalid MOBI/KF8",
    "malformed.pdf": "Invalid PDF",
    "malformed.txt": "No readable",
}


def processes():
    output = subprocess.check_output(["/bin/ps", "-axo", "pid=,rss=,comm="], text=True)
    return {int(pid): (int(rss), command) for pid, rss, command in
            (line.split(maxsplit=2) for line in output.splitlines() if line.strip())}


def run(app, filename):
    before = processes()
    executable = app / "Contents/MacOS/LeafReaderProbe"
    app_peak = webkit_peak = combined_peak = 0
    # A file keeps diagnostics readable without a pipe back-pressure risk.
    with tempfile.TemporaryFile(mode="w+t") as log:
        process = subprocess.Popen([executable, "--benchmark", filename], stdout=log, stderr=log)
        deadline = time.monotonic() + 30
        while process.poll() is None and time.monotonic() < deadline:
            snapshot = processes()
            own = snapshot.get(process.pid, (0, ""))[0]
            webkit = sum(rss for pid, (rss, command) in snapshot.items()
                         if pid not in before and "com.apple.WebKit." in command)
            app_peak = max(app_peak, own)
            webkit_peak = max(webkit_peak, webkit)
            combined_peak = max(combined_peak, own + webkit)
            time.sleep(0.04)
        if process.poll() is None:
            process.kill()
            process.wait()
        log.seek(0)
        stdout = log.read()
    result = next((json.loads(line.removeprefix("PROBE_RESULT ")) for line in stdout.splitlines()
                   if line.startswith("PROBE_RESULT ")), None)
    if result is None:
        raise RuntimeError(f"{filename} produced no result (exit {process.returncode})\n{stdout}")
    result.update(appPeakMiB=round(app_peak / 1024, 1), webKitPeakMiB=round(webkit_peak / 1024, 1),
                  combinedPeakMiB=round(combined_peak / 1024, 1))
    return result


def check_normal(result):
    name = result["file"]
    assert "error" not in result, result
    assert result["turnMs"], result
    if name.endswith(".pdf"):
        assert result["zoom"], result
    expected_encoding = {"small.txt": "UTF-8", "large.txt": "UTF-16", "legacy.txt": "GB18030"}
    if name in expected_encoding:
        assert result["encoding"] == expected_encoding[name], result
        assert result["containsFixtureChinese"], result
    if name in WEB:
        first = result["firstPage"]
        assert first["textVisible"] and first["cfi"], result
        assert not first["scriptRan"] and not first["remoteImageLoaded"] and not first["localFileLoaded"], result
        if name.endswith(".epub"):
            assert first["images"] > 0 and first["fonts"] > 0 and first["scriptPresent"], result
            assert first["fixedLayout"] == (name == "fixed.epub"), result
        if name in {"small.mobi", "large.azw3"}:
            assert first["images"] > 0, result
        if name == "small.azw3":
            assert first["fonts"] > 0, result
        if name.endswith(".azw3"):
            assert first["kindleVersion"] >= 8, result
        if name.endswith(".mobi"):
            assert first["kindleVersion"] < 8, result
        if len(first["chapters"]) > 1:
            assert result["jump"], result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repetitions", type=int, default=3)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2] / "build/reader-probe"
    native = root / "LeafReaderProbe.app"
    web = root / "LeafReaderProbeWebKit.app"
    with zipfile.ZipFile(web / "Contents/Resources/Fixtures/small.epub") as sample:
        image = sample.read("chapter-1.png")
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(image)))
            self.end_headers()
            self.wfile.write(image)

        def log_message(self, format, *args):
            pass

    with HTTPServer(("127.0.0.1", 47881), Handler) as server:
        listener = threading.Thread(target=server.serve_forever, daemon=True)
        listener.start()
        try:
            control = http.client.HTTPConnection("127.0.0.1", 47881, timeout=3)
            control.request("GET", "/control.png")
            assert control.getresponse().read() == image
            control.close()
            for name in WEB + NATIVE:
                for _ in range(args.repetitions):
                    result = run(web if name in WEB else native, name)
                    print(json.dumps(result, ensure_ascii=False), flush=True)
                    check_normal(result)
            for name, expected in INVALID.items():
                app = native if name.endswith((".txt", ".pdf")) else web
                result = run(app, name)
                print(json.dumps(result, ensure_ascii=False), flush=True)
                assert expected in result.get("error", ""), result
            no_entitlement = run(native, "small.epub")
            print(json.dumps({"withoutNetworkEntitlement": no_entitlement}, ensure_ascii=False), flush=True)
            print(json.dumps({"loopbackRequests": requests}), flush=True)
            assert requests == ["/control.png"], requests
        finally:
            server.shutdown()
            listener.join()


if __name__ == "__main__":
    main()
