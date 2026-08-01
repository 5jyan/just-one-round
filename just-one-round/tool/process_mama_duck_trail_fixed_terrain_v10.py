"""Build the approved fixed wetland board from the ImageGen raw source.

The creative source remains in assets/source/imagegen; this script only applies
the exact aspect crop, nearest-neighbor base-grid resize, and palette cleanup
needed by the runtime contract.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail/fixed_marsh_terrain_v10"
RUNTIME = ROOT / "assets/images/mama_duck_trail"
QC = SOURCE / "qc"
RAW = SOURCE / "raw-board.png"
RUNTIME_SIZE = (180, 252)
WORLD_RECT = (0, 68, 360, 572)


def build_board() -> tuple[Image.Image, dict[str, object]]:
    raw = Image.open(RAW).convert("RGB")
    target_ratio = RUNTIME_SIZE[0] / RUNTIME_SIZE[1]
    crop_width = round(raw.height * target_ratio)
    if crop_width <= raw.width:
        left = (raw.width - crop_width) // 2
        crop_box = (left, 0, left + crop_width, raw.height)
    else:
        crop_height = round(raw.width / target_ratio)
        top = (raw.height - crop_height) // 2
        crop_box = (0, top, raw.width, top + crop_height)
    cropped = raw.crop(crop_box)
    board = cropped.resize(RUNTIME_SIZE, Image.Resampling.NEAREST)
    board = board.quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    return board, {
        "raw_size": [raw.width, raw.height],
        "crop_box": list(crop_box),
        "runtime_size": list(RUNTIME_SIZE),
        "display_size": [360, 504],
        "world_rect": list(WORLD_RECT),
        "source_to_world_scale": 2,
        "palette_limit": 48,
        "sha256": hashlib.sha256(board.tobytes()).hexdigest(),
    }


def build_qc(board: Image.Image) -> None:
    QC.mkdir(parents=True, exist_ok=True)
    board.resize((720, 1008), Image.Resampling.NEAREST).save(QC / "fixed_marsh_board_4x.png")
    board.resize((360, 504), Image.Resampling.NEAREST).save(QC / "fixed_marsh_board_runtime.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    board, record = build_board()
    board.save(RUNTIME / "marsh_board_map.png")
    build_qc(board)
    contract = {
        "status": "processed",
        "version": "fixed-marsh-terrain-v10",
        "composition": {
            "terrain_is_fixed": True,
            "random_tile_selection_removed": True,
            "decorative_only": True,
            "board_cells": [7, 5],
            "cell_world_size": [72, 72],
        },
        "viewport": {
            "gameplay_safe_core": [0, 0, 360, 640],
            "maximum_target_viewport": [0, -70, 360, 710],
            "authored_canvas": [0, -100, 360, 740],
            "camera_center": [180, 320],
        },
        "runtime": {"marsh_board_map.png": record},
        "layers": [
            {"name": "marsh_background", "world_rect": [0, -100, 360, 740], "role": "background"},
            {"name": "marsh_board_map", "world_rect": list(WORLD_RECT), "role": "fixed decorative terrain"},
            {"name": "footprints", "world_rect": [0, 68, 360, 572], "role": "gameplay cue"},
            {"name": "actors", "world_rect": [0, 68, 360, 572], "role": "gameplay actors"},
        ],
        "preserved_behavior": {
            "path_generation": True,
            "input_coordinates": True,
            "collision": True,
            "score": True,
            "lives": True,
            "failure_duration_seconds": 1.0,
        },
        "qc": {
            "native_preview": "qc/fixed_marsh_board_runtime.png",
            "nearest_neighbor_preview": "qc/fixed_marsh_board_4x.png",
        },
    }
    (SOURCE / "pipeline-meta.json").write_text(json.dumps(contract, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
