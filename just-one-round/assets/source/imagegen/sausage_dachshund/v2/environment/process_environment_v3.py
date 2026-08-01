"""Bake the approved 9x15, 32px board into the accepted kitchen background."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageStat


BASE_SIZE = (180, 320)
RUNTIME_SIZE = (360, 640)
BOARD = (18, 56, 162, 296)
CELL = 16
COLUMNS = 9
ROWS = 15


def _channel_mean(image: Image.Image) -> tuple[int, int, int]:
    return tuple(round(value) for value in ImageStat.Stat(image).mean[:3])


def build(source: Path, output: Path, metadata: Path) -> None:
    raw = Image.open(source).convert("RGB")
    base = raw.resize(BASE_SIZE, Image.Resampling.LANCZOS)

    generated_surface = base.crop((20, 66, 157, 276))
    generated_surface = generated_surface.filter(ImageFilter.MedianFilter(7))
    generated_surface = generated_surface.resize(
        (BOARD[2] - BOARD[0], BOARD[3] - BOARD[1]),
        Image.Resampling.BICUBIC,
    )
    base.paste(generated_surface, BOARD[:2])

    draw = ImageDraw.Draw(base)
    seam = (3, 27, 34)
    deep_seam = (2, 18, 25)
    edge_light = (5, 66, 72)
    outer = (2, 19, 26)

    draw.rectangle(
        (BOARD[0] - 1, BOARD[1] - 1, BOARD[2], BOARD[3]),
        outline=outer,
        width=2,
    )

    for column in range(COLUMNS + 1):
        x = BOARD[0] + column * CELL
        draw.line((x, BOARD[1], x, BOARD[3]), fill=deep_seam, width=1)
        if 0 < column < COLUMNS:
            draw.line((x + 1, BOARD[1] + 1, x + 1, BOARD[3] - 1), fill=edge_light)

    for row in range(ROWS + 1):
        y = BOARD[1] + row * CELL
        draw.line((BOARD[0], y, BOARD[2], y), fill=deep_seam, width=1)
        if 0 < row < ROWS:
            draw.line((BOARD[0] + 1, y + 1, BOARD[2] - 1, y + 1), fill=edge_light)

    for column in range(COLUMNS + 1):
        for row in range(ROWS + 1):
            x = BOARD[0] + column * CELL
            y = BOARD[1] + row * CELL
            draw.rectangle((x - 1, y - 1, x + 1, y + 1), fill=seam)
            draw.point((x, y), fill=(1, 14, 20))

    runtime = base.resize(RUNTIME_SIZE, Image.Resampling.NEAREST)
    output.parent.mkdir(parents=True, exist_ok=True)
    runtime.save(output, optimize=True)

    board_world = (36, 112, 324, 592)
    board_crop = runtime.crop(board_world)
    meta = {
        "source": str(source),
        "source_size": list(raw.size),
        "base_size": list(BASE_SIZE),
        "runtime_size": list(RUNTIME_SIZE),
        "board_rect_world": [36, 112, 288, 480],
        "grid": {"columns": COLUMNS, "rows": ROWS, "cell_size_world": 32},
        "safe_core_world": [0, 0, 360, 640],
        "filtering": "180x320 creative base, nearest-neighbor 2x runtime",
        "board_rgb_mean": list(_channel_mean(board_crop)),
        "creative_source": "accepted V2 Image Gen kitchen source",
        "geometry": "deterministically rebaked into the single runtime background",
    }
    metadata.parent.mkdir(parents=True, exist_ok=True)
    metadata.write_text(json.dumps(meta, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.output, args.metadata)


if __name__ == "__main__":
    main()
