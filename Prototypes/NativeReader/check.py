# SPDX-License-Identifier: GPL-3.0-only
"""Run the native EPUB and Kindle checks and print measured samples."""
import re
import statistics
import subprocess
from pathlib import Path


root = Path(__file__).resolve().parents[2] / "build"
native = root / "native-reader"
epub = native / "LeafNativeReaderProbe.app/Contents/MacOS/LeafNativeReaderProbe"
kindle_fixtures = root / "reader-probe/LeafReaderProbe.app/Contents/Resources/Fixtures"
kindle = native / "kindle-probe"


def run(command, status):
    result = subprocess.run(["/usr/bin/time", "-l", *map(str, command)],
                            capture_output=True, text=True, timeout=20, check=False)
    if result.returncode != status:
        raise RuntimeError(f"{command[-1]} exited {result.returncode}\n{result.stdout}{result.stderr}")
    peak = re.search(r"^\s*(\d+)\s+maximum resident set size", result.stderr, re.MULTILINE)
    return result.stdout.strip(), result.stderr, int(peak[1]) / 2**20 if peak else None


def normal(command, required):
    readings = [run(command, 0) for _ in range(3)]
    fields = [dict(field.split("=", 1) for field in stdout.split()) for stdout, _, _ in readings]
    for field in fields:
        assert all(field.get(key) == value for key, value in required.items()), field
        if "readable_sections" in field:
            assert field["sections"] == field["readable_sections"], field
            assert field["script_visible"] == "false", field
    timings = {key: round(statistics.median(float(item[key]) for item in fields), 2)
               for key in ("prepare_ms", "jump_ms") if key in fields[0]}
    details = {key: value for key, value in fields[0].items() if key not in timings}
    peaks = [item[2] for item in readings if item[2] is not None]
    print(Path(command[-1]).name, details, timings, f"peak RSS {max(peaks):.1f} MiB", flush=True)


def reject(command, status, reason):
    stdout, stderr, _ = run(command, status)
    assert reason in stdout + stderr, (stdout, stderr)
    print(Path(command[-1]).name, reason, flush=True)


normal([epub, "--inspect", "small.epub"], {"sections": "3", "toc": "3", "images": "1"})
normal([epub, "--inspect", "large.epub"], {"sections": "38", "toc": "38", "images": "1"})
normal([epub, "--inspect", "legacy.epub"], {"toc": "2", "images": "0", "links": "1", "jump_fragment": "true"})
normal([epub, "--inspect", "idpf-accessible.epub"], {"sections": "22", "images": "1", "jump_fragment": "true"})
normal([epub, "--inspect", "idpf-links.epub"], {"sections": "7", "images": "1", "jump_fragment": "true"})
reject([epub, "--inspect", "fixed.epub"], 2, "supports reflowable EPUB only")
reject([epub, "--inspect", "protected.epub"], 2, "Protected EPUB")
reject([epub, "--inspect", "malformed.epub"], 2, "Invalid or unsupported EPUB ZIP")
reject([epub, "--inspect", "oversize-chapter.epub"], 2, "resource limits")
reject([epub, "--inspect", "remote-entity.epub"], 2, "Unreadable EPUB markup")

for name, required in (
    ("small.mobi", {"version": "6", "images": "3", "toc_entries": "2"}),
    ("large.mobi", {"version": "4"}),
    ("small.azw3", {"version": "8", "fonts": "1"}),
    ("large.azw3", {"version": "8", "toc_entries": "2", "images": "3"}),
):
    normal([kindle, kindle_fixtures / name], required)
for suffix in ("mobi", "azw3"):
    reject([kindle, kindle_fixtures / f"protected.{suffix}"], 3, "Protected MOBI/KF8")
    reject([kindle, kindle_fixtures / f"malformed.{suffix}"], 2, "Invalid MOBI/KF8")
