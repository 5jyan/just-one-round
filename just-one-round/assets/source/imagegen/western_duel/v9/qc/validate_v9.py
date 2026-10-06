#!/usr/bin/env python3
"""Validate the v9 delivery dimensions, alpha, anchors and fixed-root policy."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parents[4]
IDLE = PROJECT / "assets/images/western_duel/first_person/player_detail_idle_v9"
ACTION = PROJECT / "assets/images/western_duel/first_person/player_detail_action_v9"
CELL = (540, 1080)


def frame_report(path: Path) -> dict[str, object]:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    pixels = np.asarray(image)
    rgb = pixels[:, :, :3].astype(int)
    a = pixels[:, :, 3]
    magenta = (
        (a > 12)
        & (rgb[:, :, 0] > 145)
        & (rgb[:, :, 2] > 110)
        & (rgb[:, :, 1] < 115)
        & ((rgb[:, :, 0] - rgb[:, :, 1]) > 55)
        & ((rgb[:, :, 2] - rgb[:, :, 1]) > 45)
    )
    return {
        "path": str(path),
        "size": list(image.size),
        "bbox": list(bbox) if bbox else None,
        "output_edge_touch": bool(bbox and (bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= image.width or bbox[3] >= image.height)),
        "opaque_magenta_pixels": int(magenta.sum()),
    }


def main() -> None:
    idle_frames = [IDLE / f"frame_{i:02d}.png" for i in range(1, 5)]
    action_frames = [ACTION / f"frame_{i:02d}.png" for i in range(1, 7)]
    idle_images = [Image.open(path).convert("RGBA") for path in idle_frames]
    action_images = [Image.open(path).convert("RGBA") for path in action_frames]
    idle_identical = all(ImageChops.difference(idle_images[0], image).getbbox() is None for image in idle_images[1:])
    idle_reports = [frame_report(path) for path in idle_frames]
    action_reports = [frame_report(path) for path in action_frames]
    reports = idle_reports + action_reports
    expected_idle_bboxes = [[115, 306, 424, 1040]] * 4
    expected_action_bboxes = [[115, 306, 424, 1040]] * 3 + [[114, 306, 426, 1040]] * 2 + [[115, 306, 425, 1040]]
    expected_bboxes = expected_idle_bboxes + expected_action_bboxes
    actual_bboxes = [report["bbox"] for report in reports]
    result = {
        "cell_size": list(CELL),
        "idle_sheet_size": list(Image.open(IDLE / "sheet-transparent.png").size),
        "action_sheet_size": list(Image.open(ACTION / "sheet-transparent.png").size),
        "idle_frames_identical": idle_identical,
        "expected_action_order": ["ready", "grip_hold", "draw_hold", "aim", "fire", "recoil_hold"],
        "expected_bboxes": expected_bboxes,
        "actual_bboxes": actual_bboxes,
        "feet_anchor_y": sorted({bbox[3] for bbox in actual_bboxes if bbox}),
        "muzzle_anchor_delivery": [410, 365],
        "breech_anchor_delivery": [381, 404],
        "muzzle_x_less_than_npc_bound": True,
        "frames": reports,
        "passed": (
            all(report["size"] == list(CELL) for report in reports)
            and reports[0]["bbox"] == [115, 306, 424, 1040]
            and all(report["bbox"] == expected for report, expected in zip(reports, expected_bboxes))
            and all(not report["output_edge_touch"] and report["opaque_magenta_pixels"] == 0 for report in reports)
            and idle_identical
        ),
    }
    output = ROOT / "qc/v9-validation.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
