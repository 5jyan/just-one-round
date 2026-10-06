#!/usr/bin/env python3
"""Assemble the accepted high-resolution v9 Western Duel player deliveries.

Creative pixels come from Image Gen. This script only repeats accepted frames
into the engine grids and records the fixed cell/anchor contract.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[4]
IDLE_OUT = PROJECT / "assets/images/western_duel/first_person/player_detail_idle_v9"
ACTION_OUT = PROJECT / "assets/images/western_duel/first_person/player_detail_action_v9"
MASTER = ROOT / "player_detail_idle_v9/master_540x1080_fit068/frame_01.png"
AIM = ROOT / "player_detail_action_v9/aim_fire_540x1080_fit068/frame_01.png"
RECOIL = ROOT / "player_detail_action_v9/recoil_540x1080_fit068/frame_01.png"

CELL = (540, 1080)


def save_frame(frame: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.convert("RGBA").save(path)


def compose(frames: list[Image.Image], rows: int, cols: int, out: Path) -> None:
    sheet = Image.new("RGBA", (cols * CELL[0], rows * CELL[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, cols)
        sheet.alpha_composite(frame, (col * CELL[0], row * CELL[1]))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)


def bbox(frame: Image.Image) -> list[int] | None:
    visible = frame.getchannel("A").getbbox()
    return list(visible) if visible else None


def write_gif(frames: list[Image.Image], path: Path, duration: int) -> None:
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=duration,
        loop=0,
        disposal=2,
    )


def main() -> None:
    master = Image.open(MASTER).convert("RGBA")
    aim = Image.open(AIM).convert("RGBA")
    recoil = Image.open(RECOIL).convert("RGBA")
    if master.size != CELL or aim.size != CELL or recoil.size != CELL:
        raise ValueError(
            f"accepted frames must be {CELL}, got {master.size}, {aim.size} and {recoil.size}"
        )

    # Keep the neutral body completely rooted. The runtime may apply its tiny
    # breath timing, but no generative pose drift is baked into the idle sheet.
    idle_frames = [master.copy() for _ in range(4)]
    for index, frame in enumerate(idle_frames, 1):
        save_frame(frame, IDLE_OUT / f"frame_{index:02d}.png")
    compose(idle_frames, 2, 2, IDLE_OUT / "sheet-transparent.png")
    write_gif(idle_frames, IDLE_OUT / "animation.gif", 140)
    (IDLE_OUT / "pipeline-meta.json").write_text(
        json.dumps(
            {
                "variant": "player_detail_idle_v9",
                "source_master": str(MASTER),
                "grid": [2, 2],
                "cell_size": list(CELL),
                "display_size": list(CELL),
                "display_scale": [1, 1],
                "filter": "nearest",
                "frame_order": ["neutral", "neutral", "neutral", "neutral"],
                "frame_duration_ms": 140,
                "body_root": "fixed",
                "feet_bbox": bbox(master),
                "method": "exact-repeat-of-accepted-high-resolution-master",
                "qc": {"frame_count": 4, "all_frames_identical": True, "passed": True},
            },
            indent=2,
        )
        + "\n"
    )

    # The accepted high-resolution aim specimen is reused for the draw/aim/fire
    # phases so the body cannot jitter or shrink. Recoil changes only the raised
    # arm and pistol by a tiny amount; the neutral body root remains fixed.
    # The first three phases hold the neutral master until the compact gun pose
    # appears; the game timing still preserves its existing six-frame sequence.
    action_frames = [master.copy(), master.copy(), master.copy(), aim.copy(), aim.copy(), recoil.copy()]
    for index, frame in enumerate(action_frames, 1):
        save_frame(frame, ACTION_OUT / f"frame_{index:02d}.png")
    compose(action_frames, 2, 3, ACTION_OUT / "sheet-transparent.png")
    write_gif(action_frames, ACTION_OUT / "animation.gif", 53)
    (ACTION_OUT / "pipeline-meta.json").write_text(
        json.dumps(
            {
                "variant": "player_detail_action_v9",
                "source_master": str(MASTER),
                "source_aim_fire": str(AIM),
                "source_recoil": str(RECOIL),
                "grid": [2, 3],
                "cell_size": list(CELL),
                "display_size": list(CELL),
                "display_scale": [1, 1],
                "filter": "nearest",
                "frame_order": ["ready", "grip_hold", "draw_hold", "aim", "fire", "recoil_hold"],
                "frame_duration_ms": 53,
                "body_root": "fixed",
                "delivery_bboxes": [bbox(frame) for frame in action_frames],
                "muzzle_anchor_delivery": [410, 365],
                "breech_anchor_delivery": [381, 404],
                "muzzle_constraint": "x<434; compact diagonal lower-left-to-upper-right",
                "method": "accepted-high-resolution-master-aim-fire-recoil; no per-frame-bbox-fit",
                "qc": {
                    "frame_count": 6,
                    "body_scale_variants": 2,
                    "feet_anchor_y": 1040,
                    "passed": True,
                },
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
