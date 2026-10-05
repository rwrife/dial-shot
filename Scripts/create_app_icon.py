#!/usr/bin/env python3
"""Rebuild the opaque 1024px Dial Shot App Store icon (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
output = root / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
output.parent.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), "#142c30")
d = ImageDraw.Draw(image)
d.ellipse((154, 154, 870, 870), fill="#f4e8d1")
d.ellipse((214, 214, 810, 810), fill="#b26736")
d.ellipse((246, 246, 778, 778), fill="#503022")
d.ellipse((344, 344, 680, 680), outline="#f4e8d1", width=28)
d.arc((315, 350, 709, 744), 208, 342, fill="#f4e8d1", width=28)
image.save(output, format="PNG", optimize=True)
print(output)
