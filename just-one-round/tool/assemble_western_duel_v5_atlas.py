#!/usr/bin/env python3
"""Assemble the QC-passed generated frames into 360x720 runtime cells."""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "assets/source/imagegen/western_duel/v5/player_full_body_draw"
RUNTIME_DIR = ROOT / "assets/images/western_duel/first_person/player_full_body_draw_v5"
DELIVERY_DIR = SOURCE_ROOT / "delivery_360x720"
PROCESSOR_DIR = Path.home() / ".codex/skills/generate2dsprite/scripts"

CELL = (360, 720)
SQUARE_CELL = (720, 720)
CROP_BOX = (180, 0, 540, 720)
SAFE_BOUNDS = (54, 108, 306, 612)
FRAME_SOURCES = [
    (SOURCE_ROOT / "processed_360x720_candidate_v3", "full_body_draw-1.png"),
    (SOURCE_ROOT / "processed_360x720_candidate_v3", "full_body_draw-2.png"),
    (SOURCE_ROOT / "processed_360x720_candidate_v3", "full_body_draw-3.png"),
    (SOURCE_ROOT / "processed_360x720_candidate_v3", "full_body_draw-4.png"),
    (SOURCE_ROOT / "shot_frame_processed_720_candidate", "shot_pose-1.png"),
    (SOURCE_ROOT / "processed_360x720_candidate_v3", "full_body_draw-6.png"),
]


def _check_pipeline(path: Path) -> dict[str, object]:
    metadata = json.loads(path.read_text(encoding="utf-8"))
    if not metadata.get("qc_config", {}).get("strict_qc"):
        raise ValueError(f"strict QC was not enabled for {path}")
    for key in ("edge_touch_frames", "source_edge_touch_frames", "output_edge_touch_frames", "empty_frames", "paste_clamped_frames"):
        if metadata.get(key):
            raise ValueError(f"{key} is not empty in {path}")
    summary = metadata.get("qc_summary", {})
    if summary.get("body_scale_cv", 1) > 0.08:
        raise ValueError(f"body scale drift exceeds 8% in {path}")
    if summary.get("anchor_y_std", 1) > 0.05:
        raise ValueError(f"feet anchor drift exceeds 5% in {path}")
    return metadata


def main() -> None:
    if not PROCESSOR_DIR.is_dir():
        raise FileNotFoundError(f"sprite processor directory is missing: {PROCESSOR_DIR}")
    sys.path.insert(0, str(PROCESSOR_DIR))
    from generate2dsprite import save_transparent_gif

    sequence_meta = _check_pipeline(SOURCE_ROOT / "processed_360x720_candidate_v3/pipeline-meta.json")
    shot_meta = _check_pipeline(SOURCE_ROOT / "shot_frame_processed_720_candidate/pipeline-meta.json")
    if len(sequence_meta.get("frames", [])) != 6 or len(shot_meta.get("frames", [])) != 1:
        raise ValueError("Unexpected frame count in processor metadata")

    frames: list[Image.Image] = []
    frame_records: list[dict[str, object]] = []
    DELIVERY_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    for index, (directory, filename) in enumerate(FRAME_SOURCES, start=1):
        path = directory / filename
        with Image.open(path) as source:
            if source.size != SQUARE_CELL:
                raise ValueError(f"unexpected processed cell size at {path}: {source.size}")
            frame = source.convert("RGBA").crop(CROP_BOX)

        bounds = frame.getchannel("A").getbbox()
        if bounds is None:
            raise ValueError(f"frame {index} is empty")
        left, top, right, bottom = bounds
        safe_left, safe_top, safe_right, safe_bottom = SAFE_BOUNDS
        baseline_shift = safe_bottom - bottom
        if baseline_shift < 0 or baseline_shift > 2:
            raise ValueError(f"frame {index} feet baseline drifted: bbox bottom {bottom}")
        if baseline_shift:
            aligned = Image.new("RGBA", CELL, (0, 0, 0, 0))
            aligned.alpha_composite(frame, (0, baseline_shift))
            frame = aligned
            bounds = frame.getchannel("A").getbbox()
            if bounds is None:
                raise ValueError(f"frame {index} became empty during baseline alignment")
            left, top, right, bottom = bounds
        if left < safe_left or top < safe_top or right > safe_right or bottom != safe_bottom:
            raise ValueError(f"frame {index} escapes the approved safe bounds: {bounds}")

        frames.append(frame)
        frame.save(DELIVERY_DIR / f"frame_{index:02}.png")
        frame_records.append(
            {
                "frame": index,
                "source": str(path.relative_to(ROOT)),
                "output_bbox": [left, top, right, bottom],
                "output_edge_touch": False,
                "feet_baseline_y": bottom,
                "baseline_shift_y": baseline_shift,
            }
        )

    if len(frames) != 6:
        raise ValueError(f"expected 6 frames, got {len(frames)}")

    atlas = Image.new("RGBA", (CELL[0] * 3, CELL[1] * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, column = divmod(index, 3)
        atlas.alpha_composite(frame, (column * CELL[0], row * CELL[1]))

    atlas.save(DELIVERY_DIR / "sheet-transparent.png", optimize=True)
    atlas.save(RUNTIME_DIR / "sheet-transparent.png", optimize=True)
    save_transparent_gif(frames, DELIVERY_DIR / "animation.gif", duration=53)

    metadata = {
        "asset": "western_duel_player_full_body_draw_v5",
        "source_images": [
            "assets/source/imagegen/western_duel/v5/player_full_body_draw/player_draw_shoot_raw_v3.png",
            "assets/source/imagegen/western_duel/v5/player_full_body_draw/player_shot_frame_raw.png",
        ],
        "processor": "generate2dsprite.py process; strict QC; largest connected body component",
        "source_processor_cell": list(SQUARE_CELL),
        "delivery_cell": list(CELL),
        "grid": [2, 3],
        "delivery_size": list(atlas.size),
        "filter": "nearest",
        "runtime_display_size": [360, 720],
        "runtime_scale": 1,
        "crop_from_processed_square_cell": list(CROP_BOX),
        "approved_safe_bounds": list(SAFE_BOUNDS),
        "feet_baseline_y": 612,
        "muzzle_anchor_cell_local": [288, 280],
        "muzzle_anchor_note": "Measured from the separate, strict-QC single-frame firing pose; FX is placed at the barrel tip.",
        "timing_seconds_per_frame": 0.0525,
        "fire_frame_index": 4,
        "frames": frame_records,
    }
    (DELIVERY_DIR / "delivery-meta.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print(DELIVERY_DIR)
    print(RUNTIME_DIR / "sheet-transparent.png")


if __name__ == "__main__":
    main()
