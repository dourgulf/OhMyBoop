#!/usr/bin/env python3
"""Rebuild the approved flat icon assets (requires Pillow; not needed to build the app)."""
import colorsys
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/design/ohmyboop-icon-v2.png"
ASSETS = ROOT / "Resources/Assets.xcassets"
OUTPUT = ASSETS / "AppIcon.appiconset"
PALETTE = ((36, 85, 255), (255, 229, 0), (0, 240, 200))


def main():
    source = Image.open(SOURCE).convert("RGB")
    assert source.width == source.height, "App icon source must be square"
    pixels = []
    for r, g, b in (source.getpixel((x, y)) for y in range(source.height) for x in range(source.width)):
        hue, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        # The generated checkerboard is neutral gray. Keep only the three
        # saturated shapes, snapping their interiors to the approved palette.
        if saturation < 0.5 or value < 0.4:
            pixels.append((0, 0, 0, 0))
        else:
            index = 1 if 0.08 < hue < 0.23 else 2 if 0.3 < hue < 0.52 else 0
            pixels.append((*PALETTE[index], 255))
    clean = Image.new("RGBA", source.size)
    clean.putdata(pixels)
    # BOX coverage antialiasing introduces only boundary blends, not gradients.
    master = clean.resize((1024, 1024), Image.Resampling.BOX)
    master.save(ROOT / "docs/design/ohmyboop-icon-production.png")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    info = {"author": "xcode", "version": 1}
    (ASSETS / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
    images = []
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{size}x{size}@{scale}x.png"
            master.resize((size * scale, size * scale), Image.Resampling.BOX).save(OUTPUT / name)
            images.append({"filename": name, "idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x"})
    (OUTPUT / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
    print(f"Generated {len(images)} app icon slots in {OUTPUT}")


if __name__ == "__main__":
    main()
