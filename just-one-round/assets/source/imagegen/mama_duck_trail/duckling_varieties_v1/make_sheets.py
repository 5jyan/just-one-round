"""Adapt the accepted duckling animation to two imagegen color identities.

The original six poses and alpha are kept pixel-for-pixel so the new types
share its 72px cell, 50px body height, and y=68 feet baseline.
"""

from colorsys import rgb_to_hsv
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
IMAGES = ROOT / "assets/images/mama_duck_trail"


def recolor(name: str, variant: str) -> None:
    image = Image.open(IMAGES / f"duckling_{name}_sheet.png").convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0 or y % 72 >= 59:
                continue
            hue, saturation, value = rgb_to_hsv(red / 255, green / 255, blue / 255)
            if not (0.105 <= hue <= 0.17 and saturation >= 0.24 and value >= 0.32):
                continue
            shade = max(0.0, min(1.0, (value - 0.32) / 0.68))
            if variant == "cream":
                pixels[x, y] = (
                    round(135 + shade * 120),
                    round(117 + shade * 130),
                    round(91 + shade * 143),
                    alpha,
                )
            else:
                pixels[x, y] = (
                    round(80 + shade * 133),
                    round(48 + shade * 104),
                    round(29 + shade * 82),
                    alpha,
                )
    image.save(IMAGES / f"duckling_{variant}_{name}_sheet.png")


for type_name in ("cream", "brown"):
    for action in ("walk", "cheer"):
        recolor(action, type_name)
