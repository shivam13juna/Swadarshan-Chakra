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

# The cycle-of-ages dial and its hour hand, supplied in dial_pictures like the five in 5_pictures.
dial_names = ["yuga_chakra_v2.png", "white_clock_hand.png"]
dial = root / "Sources/SwadarshanChakra/Resources/Dial"
if sorted(p.name for p in dial.iterdir() if not p.name.startswith(".")) != sorted(dial_names):
    raise SystemExit("Dial must contain exactly the supplied yuga chakra and clock hand.")
for name in dial_names:
    original, bundled = root / "dial_pictures" / name, dial / name
    if not original.is_file() or original.read_bytes() != bundled.read_bytes():
        raise SystemExit(f"Bundled dial picture must match the supplied {name} exactly.")
    print(f"Dial → {name}: original verified")
