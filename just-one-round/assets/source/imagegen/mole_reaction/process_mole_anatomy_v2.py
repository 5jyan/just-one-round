#!/usr/bin/env python3
"""Extract the v2 mole anatomy sheets into deterministic runtime atlases.

The idle generation occasionally contains a light checkerboard baked into the
image.  We remove only border-connected bright neutral pixels, then keep the
largest 8-connected subject component in each source quadrant.  This preserves
the mole's nose, whiskers, digging paws, and claws while dropping detached
generation artifacts.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


SOURCE_CELL = 627
RUNTIME_CELL = 256
SHEET_SIZE = 512
TARGET_WIDTH = 188
TARGET_HEIGHT = 232
BOTTOM_ANCHOR = 236
ALPHA_THRESHOLD = 96


def _remove_border_checkerboard(image: Image.Image) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA")).copy()
    rgb = rgba[:, :, :3].astype(np.int16)
    alpha = rgba[:, :, 3]
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    luma = rgb.mean(axis=2)
    # The checker is made of near-neutral, bright tiles.  Dark neutral outline
    # pixels are intentionally excluded so the outer pixel contour survives.
    candidate = (alpha > 0) & (spread <= 10) & (luma >= 160)

    height, width = candidate.shape
    visited = np.zeros_like(candidate, dtype=bool)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        if candidate[0, x]:
            visited[0, x] = True
            queue.append((0, x))
        if candidate[height - 1, x] and not visited[height - 1, x]:
            visited[height - 1, x] = True
            queue.append((height - 1, x))
    for y in range(height):
        if candidate[y, 0] and not visited[y, 0]:
            visited[y, 0] = True
            queue.append((y, 0))
        if candidate[y, width - 1] and not visited[y, width - 1]:
            visited[y, width - 1] = True
            queue.append((y, width - 1))

    while queue:
        y, x = queue.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < height and 0 <= nx < width:
                if candidate[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((ny, nx))

    rgba[visited, 3] = 0
    return Image.fromarray(rgba, mode="RGBA")


def _largest_component(alpha: np.ndarray) -> np.ndarray:
    mask = alpha >= ALPHA_THRESHOLD
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    best: list[tuple[int, int]] = []
    for y in range(height):
        for x in range(width):
            if not mask[y, x] or visited[y, x]:
                continue
            component: list[tuple[int, int]] = []
            queue: deque[tuple[int, int]] = deque([(y, x)])
            visited[y, x] = True
            while queue:
                cy, cx = queue.popleft()
                component.append((cy, cx))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if not dy and not dx:
                            continue
                        ny, nx = cy + dy, cx + dx
                        if (
                            0 <= ny < height
                            and 0 <= nx < width
                            and mask[ny, nx]
                            and not visited[ny, nx]
                        ):
                            visited[ny, nx] = True
                            queue.append((ny, nx))
            if len(component) > len(best):
                best = component
    selected = np.zeros_like(mask, dtype=bool)
    for y, x in best:
        selected[y, x] = True
    return selected


def _process_frame(frame: Image.Image) -> Image.Image:
    rgba = np.asarray(frame.convert("RGBA")).copy()
    component = _largest_component(rgba[:, :, 3])
    rgba[~component, 3] = 0
    bbox = Image.fromarray(rgba[:, :, 3], mode="L").getbbox()
    if bbox is None:
        raise ValueError("source quadrant contains no subject")
    cropped = Image.fromarray(rgba, mode="RGBA").crop(bbox)
    scale = min(TARGET_WIDTH / cropped.width, TARGET_HEIGHT / cropped.height)
    size = (
        max(1, round(cropped.width * scale)),
        max(1, round(cropped.height * scale)),
    )
    resized = cropped.resize(size, Image.Resampling.NEAREST)
    cell = Image.new("RGBA", (RUNTIME_CELL, RUNTIME_CELL), (0, 0, 0, 0))
    x = (RUNTIME_CELL - resized.width) // 2
    y = BOTTOM_ANCHOR - resized.height
    cell.alpha_composite(resized, (x, y))
    return cell


def extract_sheet(path: Path) -> Image.Image:
    image = _remove_border_checkerboard(Image.open(path).convert("RGBA"))
    output = Image.new("RGBA", (SHEET_SIZE, SHEET_SIZE), (0, 0, 0, 0))
    for index in range(4):
        x = (index % 2) * SOURCE_CELL
        y = (index // 2) * SOURCE_CELL
        frame = image.crop((x, y, x + SOURCE_CELL, y + SOURCE_CELL))
        output.alpha_composite(
            _process_frame(frame),
            ((index % 2) * RUNTIME_CELL, (index // 2) * RUNTIME_CELL),
        )
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, source_name in (
        ("idle", "idle-raw-sheet.png"),
        ("hurt", "hurt-raw-sheet.png"),
        ("thumbs_up", "thumbs-up-raw-sheet.png"),
    ):
        path = args.input_dir / source_name
        if not path.exists():
            raise SystemExit(f"Missing source sheet: {path}")
        extract_sheet(path).save(args.output_dir / f"{name}_sheet.png")


if __name__ == "__main__":
    main()
