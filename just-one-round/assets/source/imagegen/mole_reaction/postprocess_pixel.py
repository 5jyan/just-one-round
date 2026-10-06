#!/usr/bin/env python3
"""Apply deterministic hard-alpha and shared-palette cleanup to generated sprites."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def hard_alpha(image: Image.Image, threshold: int = 128) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if value >= threshold else 0)
    rgba.putalpha(alpha)
    return rgba


def shared_palette(images: list[Image.Image], colors: int) -> Image.Image:
    width = max((image.width for image in images), default=1)
    height = sum(image.height for image in images) or 1
    sample = Image.new("RGB", (width, height), (0, 0, 0))
    y = 0
    for image in images:
        rgba = image.convert("RGBA")
        rgb = Image.new("RGB", rgba.size, (0, 0, 0))
        rgb.paste(rgba.convert("RGB"), mask=rgba.getchannel("A"))
        sample.paste(rgb, (0, y))
        y += image.height
    return sample.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def process_paths(inputs: list[Path], output_dir: Path, colors: int, alpha_threshold: int) -> None:
    images = [hard_alpha(Image.open(path), alpha_threshold) for path in inputs]
    palette = shared_palette(images, colors)
    output_dir.mkdir(parents=True, exist_ok=True)
    for path, image in zip(inputs, images):
        rgb = image.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
        rgb.putalpha(image.getchannel("A"))
        rgb.save(output_dir / path.name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--colors", type=int, default=28)
    parser.add_argument("--alpha-threshold", type=int, default=128)
    args = parser.parse_args()
    paths = sorted(
        path
        for path in args.input_dir.glob("*.png")
        if path.name not in {"raw-sheet.png", "raw-sheet-clean.png"}
    )
    if not paths:
        raise SystemExit(f"No processed PNGs found in {args.input_dir}")
    process_paths(paths, args.output_dir, args.colors, args.alpha_threshold)


if __name__ == "__main__":
    main()
