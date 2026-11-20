# SPDX-License-Identifier: GPL-3.0-only
"""Finder layout for the reusable, app-free installer image."""
from pathlib import Path

format = "UDZO"
filesystem = "HFS+"
size = "24m"
background = str(Path(defines["background"]).resolve())
symlinks = {"Applications": "/Applications"}
window_rect = ((160, 120), (620, 380))
icon_size = 96
text_size = 14
icon_locations = {"Leaf.app": (187, 185), "Applications": (433, 185)}
