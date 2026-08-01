#!/usr/bin/env python3
"""Extend generated modular coat pixels through approved open connector edges."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def _alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("input image has no visible pixels")
    return bbox


def _extend_left(image: Image.Image, inset: int) -> None:
    left, top, _, bottom = _alpha_bbox(image)
    sample_x = min(image.width - 1, left + inset)
    strip = image.crop((sample_x, top, sample_x + 1, bottom))
    for x in range(sample_x + 1):
        image.paste(strip, (x, top))


def _extend_right(image: Image.Image, inset: int) -> None:
    _, top, right, bottom = _alpha_bbox(image)
    sample_x = max(0, right - inset - 1)
    strip = image.crop((sample_x, top, sample_x + 1, bottom))
    for x in range(sample_x, image.width):
        image.paste(strip, (x, top))


def _extend_up(image: Image.Image, inset: int) -> None:
    left, top, right, _ = _alpha_bbox(image)
    sample_y = min(image.height - 1, top + inset)
    strip = image.crop((left, sample_y, right, sample_y + 1))
    for y in range(sample_y + 1):
        image.paste(strip, (left, y))


def _extend_down(image: Image.Image, inset: int) -> None:
    left, _, right, bottom = _alpha_bbox(image)
    sample_y = max(0, bottom - inset - 1)
    strip = image.crop((left, sample_y, right, sample_y + 1))
    for y in range(sample_y, image.height):
        image.paste(strip, (left, y))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--edges",
        nargs="+",
        choices=("left", "right", "up", "down"),
        required=True,
    )
    parser.add_argument("--inset", type=int, default=5)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGBA")
    for edge in args.edges:
        {
            "left": _extend_left,
            "right": _extend_right,
            "up": _extend_up,
            "down": _extend_down,
        }[edge](image, args.inset)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)


if __name__ == "__main__":
    main()
