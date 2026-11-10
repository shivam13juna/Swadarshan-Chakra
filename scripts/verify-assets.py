#!/usr/bin/env python3
"""Fail packaging if stage artwork or branding differs from the supplied originals."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
names = ["pic_1.png", "pic_2.jpg", "pic_3.png", "pic_4.png", "pic_5.png"]
destination = root / "Sources/SwadarshanChakra/Resources/Artwork"
actual_names = sorted(p.name for p in destination.iterdir() if not p.name.startswith("."))
if actual_names != sorted(names):
    raise SystemExit("Artwork must contain exactly the five explicitly assigned pictures.")
for number, name in enumerate(names, start=1):
    original = root / "5_pictures" / name
    packaged = destination / name
    if not original.is_file() or not packaged.is_file():
        raise SystemExit(f"Missing supplied artwork: {name}")
    if hashlib.sha256(original.read_bytes()).digest() != hashlib.sha256(packaged.read_bytes()).digest():
        raise SystemExit(f"Bundled artwork differs from the owner's original: {name}")
    print(f"stage_{number:02d} → {name}: original verified")

icon = root / "icon.png"
bundled_icon = root / "Sources/SwadarshanChakra/Resources/Branding/icon.png"
if not icon.is_file() or not bundled_icon.is_file() or icon.read_bytes() != bundled_icon.read_bytes():
    raise SystemExit("Bundled branding must match the supplied icon.png exactly.")
print("Brand icon → icon.png: original verified")
