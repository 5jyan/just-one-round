#!/usr/bin/env python3
"""Assemble the six Vision-isolated upper-body poses into runtime cells."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets/source/imagegen/western_duel/v6/player_upperbody_draw"
INSTANCE_DIR = SOURCE_ROOT / "v2-vision-instances"
DELIVERY_DIR = SOURCE_ROOT / "delivery_560x560"
RUNTIME_DIR = ROOT / "assets/images/western_duel/first_person/player_upperbody_draw_v6"
PROCESSOR_DIR = Path.home() / ".codex/skills/generate2dsprite/scripts"

CELL = (560, 560)
GRID = (2, 3)
EXPECTED_SOURCE_BOUNDS = [
    [119, 43, 340, 497],
    [632, 43, 851, 497],
    [1143, 43, 1444, 497],
    [59, 553, 466, 991],
    [582, 553, 1000, 991],
    [1095, 553, 1483, 991],
]
FRAME_OFFSETS = [(62, 28), (90, 28), (199, 28), (92, 64), (87, 27), (111, 60)]
VERTICAL_SCALE = 0.93
RUNTIME_DISPLAY_SIZE = (360, 560)
RUNTIME_ORIGIN = (-60, "viewport_height / 2 - 160")
MUZZLE_ANCHOR_CELL = (499, 150)


def _source_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError("Vision produced an empty player pose")
    return bounds


def main() -> None:
    if not PROCESSOR_DIR.is_dir():
        raise FileNotFoundError(f"sprite processor directory is missing: {PROCESSOR_DIR}")
    sys.path.insert(0, str(PROCESSOR_DIR))
    from generate2dsprite import save_transparent_gif

    DELIVERY_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    frame_records: list[dict[str, object]] = []

    for index, (expected, offset) in enumerate(
        zip(EXPECTED_SOURCE_BOUNDS, FRAME_OFFSETS), start=1
    ):
        source_path = INSTANCE_DIR / f"instance_{index:02}.png"
        with Image.open(source_path) as source:
            image = source.convert("RGBA")
        actual = _source_bounds(image)
        if list(actual) != expected:
            raise ValueError(
                f"Vision mask drifted for frame {index}: expected {expected}, got {actual}"
            )

        crop = image.crop(actual)
        output_height = round(crop.height * VERTICAL_SCALE)
        scaled = crop.resize((crop.width, output_height), Image.Resampling.NEAREST)
        frame = Image.new("RGBA", CELL, (0, 0, 0, 0))
        frame.alpha_composite(scaled, offset)
        bounds = _source_bounds(frame)
        left, top, right, bottom = bounds
        if left < 16 or top < 16 or right > CELL[0] - 16 or bottom > CELL[1] - 16:
            raise ValueError(f"frame {index} has unsafe runtime cell bounds: {bounds}")

        frame_path = DELIVERY_DIR / f"frame_{index:02}.png"
        frame.save(frame_path, optimize=True)
        frames.append(frame)
        frame_records.append(
            {
                "frame": index,
                "source_instance": str(source_path.relative_to(ROOT)),
                "vision_source_bbox": list(actual),
                "scale_xy": [1, VERTICAL_SCALE],
                "offset_cell": list(offset),
                "output_bbox": list(bounds),
                "output_edge_touch": False,
                "pants_or_legs": False,
            }
        )

    if len(frames) != 6:
        raise ValueError(f"expected six action frames, got {len(frames)}")

    atlas = Image.new("RGBA", (CELL[0] * GRID[1], CELL[1] * GRID[0]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, column = divmod(index, GRID[1])
        atlas.alpha_composite(frame, (column * CELL[0], row * CELL[1]))

    atlas_path = DELIVERY_DIR / "sheet-transparent.png"
    atlas.save(atlas_path, optimize=True)
    atlas.save(RUNTIME_DIR / "sheet-transparent.png", optimize=True)
    save_transparent_gif(frames, DELIVERY_DIR / "animation.gif", duration=53)

    metadata = {
        "asset": "western_duel_player_upperbody_draw_v6",
        "source_image": str((SOURCE_ROOT / "raw-sheet-v2-with-background.png").relative_to(ROOT)),
        "foreground_extraction": "macOS Vision VNGenerateForegroundInstanceMaskRequest; six isolated instances",
        "delivery_cell": list(CELL),
        "grid": list(GRID),
        "delivery_size": list(atlas.size),
        "runtime_display_size": list(RUNTIME_DISPLAY_SIZE),
        "runtime_scale": [RUNTIME_DISPLAY_SIZE[0] / CELL[0], 1],
        "runtime_origin": {"x": RUNTIME_ORIGIN[0], "y": RUNTIME_ORIGIN[1]},
        "filter": "nearest",
        "excluded_content": "trousers, thighs, knees, lower legs, and boots are absent from every frame",
        "muzzle_anchor_cell_local": list(MUZZLE_ANCHOR_CELL),
        "muzzle_anchor_screen": [261, "viewport_height / 2 - 10"],
        "timing_seconds_per_frame": 0.0525,
        "fire_frame_index": 4,
        "frames": frame_records,
    }
    (DELIVERY_DIR / "delivery-meta.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print(atlas_path)
    print(RUNTIME_DIR / "sheet-transparent.png")


if __name__ == "__main__":
    main()
