#!/usr/bin/env python3
"""Blend a canonical generated coat cross-section into modular open edges."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def _vertical_strip(profile: Image.Image) -> Image.Image:
    x = profile.width // 2
    return profile.crop((x, 0, x + 1, profile.height))


def _horizontal_strip(profile: Image.Image) -> Image.Image:
    y = profile.height // 2
    return profile.crop((0, y, profile.width, y + 1))


def _blend_edge(
    image: Image.Image,
    profile: Image.Image,
    edge: str,
    band: int,
) -> None:
    if edge in {"left", "right"}:
        strip = _vertical_strip(profile)
        for depth in range(band):
            x = depth if edge == "left" else image.width - depth - 1
            source = image.crop((x, 0, x + 1, image.height))
            weight = 1.0 - depth / band
            image.paste(Image.blend(source, strip, weight), (x, 0))
        return

    strip = _horizontal_strip(profile)
    for depth in range(band):
        y = depth if edge == "up" else image.height - depth - 1
        source = image.crop((0, y, image.width, y + 1))
        weight = 1.0 - depth / band
        image.paste(Image.blend(source, strip, weight), (0, y))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--edges",
        nargs="+",
        choices=("left", "right", "up", "down"),
        required=True,
    )
    parser.add_argument("--band", type=int, default=8)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGBA")
    profile = Image.open(args.profile).convert("RGBA")
    if image.size != profile.size:
        raise ValueError("input and profile must use the same frame size")

    for edge in args.edges:
        _blend_edge(image, profile, edge, args.band)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)


if __name__ == "__main__":
    main()
