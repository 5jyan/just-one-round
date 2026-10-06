#!/usr/bin/env python3
"""Deterministically recolor accepted bald mole frames into the golden variant."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def gold_color(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    r, g, b = rgb
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    # Keep the darkest outline, eyes, brows, and whisker ink high contrast.
    # Brown fur below this level is handled separately so the body does not
    # remain the same dull chestnut as the source reference.
    if luma < 44:
        return (62, 31, 8)
    # Claws and cream face marks become warm ivory highlights.
    if r > 174 and g > 148 and b > 108 and (r - b) < 100:
        return (255, 238, 175)
    # Keep the small rosy details on the ears and cheeks warm instead of
    # flattening them into the yellow fur ramp.
    if (
        r > 140
        and g < 130
        and b < 115
        and (r - g) > 55
        and (g - b) < 32
    ):
        return (235, 116, 35)
    # Facial ink such as the nose and smile is darker than the fur, but still
    # above the outline threshold. Preserve it as deep brown for readability.
    if luma < 82 and r < 145 and g < 78 and b < 55:
        return (83, 42, 10)
    # Everything else in the brown fur ramp gets a stronger yellow-gold
    # palette. The midtones are intentionally brighter than the source so the
    # final-event mole reads as a reward target at a glance.
    if luma < 110:
        return (174, 102, 8)
    if luma < 145:
        return (214, 146, 18)
    if luma < 180:
        return (238, 181, 43)
    if luma < 215:
        return (251, 210, 84)
    return (255, 230, 133)


def recolor(path: Path, output: Path) -> None:
    src = Image.open(path).convert("RGBA")
    dst = Image.new("RGBA", src.size, (0, 0, 0, 0))
    pixels = []
    for r, g, b, a in src.getdata():
        if a < 128:
            pixels.append((0, 0, 0, 0))
        else:
            nr, ng, nb = gold_color((r, g, b))
            pixels.append((nr, ng, nb, 255))
    dst.putdata(pixels)
    output.parent.mkdir(parents=True, exist_ok=True)
    dst.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    paths = sorted(p for p in args.input_dir.glob("*.png") if not p.name.startswith("raw"))
    if not paths:
        raise SystemExit(f"No processed PNGs found in {args.input_dir}")
    for path in paths:
        recolor(path, args.output_dir / path.name)


if __name__ == "__main__":
    main()
