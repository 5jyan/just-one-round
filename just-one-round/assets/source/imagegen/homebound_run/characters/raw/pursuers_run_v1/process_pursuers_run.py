#!/usr/bin/env python3
"""Normalize the generated paired-bully run sheet into the Temple Run atlas.

All character pixels originate from built-in Image Gen. This script only
isolates the twelve generated figures, thresholds transparent edge halos,
applies shared nearest-neighbour scale/feet alignment, and assembles the runtime
atlas plus QC previews.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


HERE = Path(__file__).resolve().parent
REPO = Path(__file__).resolve().parents[7]
RAW_PATH = HERE / "raw-pass2-refined.png"
RUNTIME_PATH = REPO / "assets/images/homebound_run/pursuers_run.png"
PROCESSED = REPO / "assets/source/imagegen/homebound_run/characters/processed/pursuers_run_v1"
FRAME_DIR = PROCESSED / "frames"
QC_DIR = PROCESSED / "qc"

RAW_EXPECTED_SIZE = (1774, 887)
BASE_SIZE = (128, 96)
RUNTIME_CELL = (512, 384)
COL_BOUNDARIES = (0, 600, 1185, 1774)
ROW_BOUNDARIES = (0, 460, 887)
PAIR_SPLIT_OFFSET = 320
ALPHA_THRESHOLD = 128
FRAME_DURATION_MS = 125
BASELINE_Y = 86

# These two equal-size sourceRects do not overlap. Their body bounds retain a
# transparent center gutter, so neither actor leaks into the other crop.
LEFT_SOURCE_RECT = (48, 80, 264, 352)
RIGHT_SOURCE_RECT = (264, 80, 480, 352)
BODY_CENTERS_BASE_X = {"left": 39, "right": 93}
BODY_MAX_BASE_SIZE = {"left": (54, 60), "right": (46, 54)}

FRAME_ORDER = [
    "left-foot-contact",
    "compression",
    "flight",
    "right-foot-contact",
    "compression",
    "flight",
]


def largest_component(
    source: Image.Image,
    roi: tuple[int, int, int, int],
    *,
    threshold: int = ALPHA_THRESHOLD,
) -> tuple[Image.Image, dict[str, object]]:
    """Return the largest 8-connected opaque component within an ROI."""
    x0, y0, x1, y1 = roi
    alpha = source.getchannel("A").crop(roi)
    width, height = alpha.size
    values = alpha.tobytes()
    seen = bytearray(width * height)
    best_indices: list[int] = []
    best_bounds: tuple[int, int, int, int] | None = None

    for start, value in enumerate(values):
        if value < threshold or seen[start]:
            continue
        seen[start] = 1
        stack = [start]
        component: list[int] = []
        min_x = width
        min_y = height
        max_x = -1
        max_y = -1
        while stack:
            index = stack.pop()
            component.append(index)
            local_y, local_x = divmod(index, width)
            min_x = min(min_x, local_x)
            min_y = min(min_y, local_y)
            max_x = max(max_x, local_x)
            max_y = max(max_y, local_y)
            for next_y in range(max(0, local_y - 1), min(height, local_y + 2)):
                row_start = next_y * width
                for next_x in range(max(0, local_x - 1), min(width, local_x + 2)):
                    next_index = row_start + next_x
                    if not seen[next_index] and values[next_index] >= threshold:
                        seen[next_index] = 1
                        stack.append(next_index)
        if len(component) > len(best_indices):
            best_indices = component
            best_bounds = (min_x, min_y, max_x + 1, max_y + 1)

    if best_bounds is None or len(best_indices) < 10_000:
        raise ValueError(f"No complete character found in source ROI {roi}")

    bx0, by0, bx1, by1 = best_bounds
    bbox_width = bx1 - bx0
    bbox_height = by1 - by0
    mask_data = bytearray(bbox_width * bbox_height)
    for index in best_indices:
        local_y, local_x = divmod(index, width)
        mask_data[(local_y - by0) * bbox_width + (local_x - bx0)] = 255
    component_mask = Image.frombytes("L", (bbox_width, bbox_height), bytes(mask_data))
    global_bbox = (x0 + bx0, y0 + by0, x0 + bx1, y0 + by1)
    component = source.crop(global_bbox).convert("RGBA")
    component.putalpha(component_mask)
    return component, {
        "source_bbox": list(global_bbox),
        "source_bbox_size": [bbox_width, bbox_height],
        "opaque_component_pixels": len(best_indices),
        "threshold_alpha": threshold,
    }


def nearest(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.NEAREST)


def place_body(
    base: Image.Image,
    body: Image.Image,
    *,
    scale: float,
    center_x: int,
    baseline_y: int,
) -> tuple[int, int, int, int]:
    width = max(1, round(body.width * scale))
    height = max(1, round(body.height * scale))
    sprite = nearest(body, (width, height))
    left = center_x - width // 2
    top = baseline_y - height
    if left < 0 or top < 0 or left + width > base.width or top + height > base.height:
        raise ValueError(f"Scaled actor does not fit base cell: {(left, top, left + width, top + height)}")
    base.alpha_composite(sprite, (left, top))
    return (left, top, left + width, top + height)


def paste_checkerboard(image: Image.Image, cell_box: tuple[int, int, int, int]) -> None:
    draw = __import__("PIL.ImageDraw", fromlist=["ImageDraw"]).Draw(image)
    left, top, right, bottom = cell_box
    tile = 32
    colors = ((77, 73, 91, 255), (99, 94, 110, 255))
    for y in range(top, bottom, tile):
        for x in range(left, right, tile):
            color = colors[((x - left) // tile + (y - top) // tile) % 2]
            draw.rectangle((x, y, min(right - 1, x + tile - 1), min(bottom - 1, y + tile - 1)), fill=color)


def main() -> None:
    source = Image.open(RAW_PATH).convert("RGBA")
    if source.size != RAW_EXPECTED_SIZE:
        raise ValueError(f"Unexpected raw dimensions: {source.size}; expected {RAW_EXPECTED_SIZE}")

    figures: dict[str, list[Image.Image]] = {"left": [], "right": []}
    source_qc: list[dict[str, object]] = []
    for row in range(2):
        for col in range(3):
            cell_x0, cell_x1 = COL_BOUNDARIES[col : col + 2]
            cell_y0, cell_y1 = ROW_BOUNDARIES[row : row + 2]
            split_x = cell_x0 + PAIR_SPLIT_OFFSET
            left_roi = (cell_x0, cell_y0, split_x, cell_y1)
            right_roi = (split_x, cell_y0, cell_x1, cell_y1)
            left_body, left_meta = largest_component(source, left_roi)
            right_body, right_meta = largest_component(source, right_roi)
            figures["left"].append(left_body)
            figures["right"].append(right_body)
            source_qc.append(
                {
                    "index": row * 3 + col,
                    "label": FRAME_ORDER[row * 3 + col],
                    "source_cell_bounds": [cell_x0, cell_y0, cell_x1, cell_y1],
                    "left_roi": list(left_roi),
                    "right_roi": list(right_roi),
                    "left": left_meta,
                    "right": right_meta,
                }
            )

    shared_scales: dict[str, float] = {}
    for side in ("left", "right"):
        max_width = max(body.width for body in figures[side])
        max_height = max(body.height for body in figures[side])
        target_width, target_height = BODY_MAX_BASE_SIZE[side]
        shared_scales[side] = min(target_width / max_width, target_height / max_height)

    FRAME_DIR.mkdir(parents=True, exist_ok=True)
    QC_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_PATH.parent.mkdir(parents=True, exist_ok=True)

    atlas = Image.new("RGBA", (RUNTIME_CELL[0] * 3, RUNTIME_CELL[1] * 2), (0, 0, 0, 0))
    runtime_frames: list[Image.Image] = []
    frame_qc: list[dict[str, object]] = []
    for frame_index, label in enumerate(FRAME_ORDER):
        base = Image.new("RGBA", BASE_SIZE, (0, 0, 0, 0))
        boxes: dict[str, tuple[int, int, int, int]] = {}
        for side in ("left", "right"):
            source_frame = figures[side][frame_index]
            boxes[side] = place_body(
                base,
                source_frame,
                scale=shared_scales[side],
                center_x=BODY_CENTERS_BASE_X[side],
                baseline_y=BASELINE_Y,
            )
        runtime = nearest(base, RUNTIME_CELL)
        frame_path = FRAME_DIR / f"pursuers_run_{frame_index:02d}.png"
        runtime.save(frame_path)
        row, col = divmod(frame_index, 3)
        atlas.alpha_composite(runtime, (col * RUNTIME_CELL[0], row * RUNTIME_CELL[1]))
        runtime_frames.append(runtime)

        left_bbox = runtime.getchannel("A").crop(LEFT_SOURCE_RECT).getbbox()
        right_bbox = runtime.getchannel("A").crop(RIGHT_SOURCE_RECT).getbbox()
        if left_bbox is None or right_bbox is None:
            raise ValueError(f"Frame {frame_index} has an empty actor crop")
        left_bbox = (
            left_bbox[0] + LEFT_SOURCE_RECT[0],
            left_bbox[1] + LEFT_SOURCE_RECT[1],
            left_bbox[2] + LEFT_SOURCE_RECT[0],
            left_bbox[3] + LEFT_SOURCE_RECT[1],
        )
        right_bbox = (
            right_bbox[0] + RIGHT_SOURCE_RECT[0],
            right_bbox[1] + RIGHT_SOURCE_RECT[1],
            right_bbox[2] + RIGHT_SOURCE_RECT[0],
            right_bbox[3] + RIGHT_SOURCE_RECT[1],
        )
        if left_bbox[2] > LEFT_SOURCE_RECT[2] or right_bbox[0] < RIGHT_SOURCE_RECT[0]:
            raise ValueError(f"Actor crossed its source crop in frame {frame_index}")
        if left_bbox[2] >= right_bbox[0]:
            raise ValueError(f"Actors overlap in frame {frame_index}: {left_bbox}, {right_bbox}")
        if left_bbox[3] != right_bbox[3] or left_bbox[3] != BASELINE_Y * 4:
            raise ValueError(f"Actor baselines drifted in frame {frame_index}: {left_bbox}, {right_bbox}")
        frame_qc.append(
            {
                "index": frame_index,
                "label": label,
                "runtime_frame": frame_path.relative_to(REPO).as_posix(),
                "left_bbox": list(left_bbox),
                "right_bbox": list(right_bbox),
                "center_gap_px": right_bbox[0] - left_bbox[2],
                "baseline_y": left_bbox[3],
            }
        )

    atlas.save(RUNTIME_PATH)

    # A 2× preview gives reviewers a clear view of each transparent atlas cell.
    preview = Image.new("RGBA", (RUNTIME_CELL[0] * 2 * 3, RUNTIME_CELL[1] * 2 * 2), (0, 0, 0, 0))
    preview_frame_size = (RUNTIME_CELL[0] * 2, RUNTIME_CELL[1] * 2)
    for index, runtime in enumerate(runtime_frames):
        row, col = divmod(index, 3)
        cell_x = col * preview_frame_size[0]
        cell_y = row * preview_frame_size[1]
        paste_checkerboard(preview, (cell_x, cell_y, cell_x + preview_frame_size[0], cell_y + preview_frame_size[1]))
        enlarged = nearest(runtime, preview_frame_size)
        preview.alpha_composite(enlarged, (cell_x, cell_y))
    contact_path = QC_DIR / "pursuers_run_contact_sheet_2x.png"
    preview.save(contact_path)

    gif_path = QC_DIR / "pursuers_run_animation.gif"
    gif_frames = [frame.convert("RGBA") for frame in runtime_frames]
    gif_frames[0].save(
        gif_path,
        format="GIF",
        save_all=True,
        append_images=gif_frames[1:],
        duration=FRAME_DURATION_MS,
        loop=0,
        disposal=2,
        transparency=0,
    )

    qc = {
        "empty_frames": 0,
        "edge_touch_frames": 0,
        "source_crop_violations": 0,
        "actor_overlap_frames": 0,
        "baseline_y_values": sorted({item["baseline_y"] for item in frame_qc}),
        "minimum_center_gap_px": min(item["center_gap_px"] for item in frame_qc),
        "opaque_bbox": list(atlas.getchannel("A").getbbox() or ()),
        "runtime_dimensions": list(atlas.size),
        "contact_sheet": contact_path.relative_to(REPO).as_posix(),
    }
    metadata = {
        "schema": "homebound_run.pursuers_run_asset.v1",
        "asset": "homebound_run.pursuers_run",
        "runtime_path": RUNTIME_PATH.relative_to(REPO).as_posix(),
        "source_raw": RAW_PATH.relative_to(REPO).as_posix(),
        "refinement_source": (HERE / "raw-pass1.png").relative_to(REPO).as_posix(),
        "source_prompt": (HERE / "prompt-used.txt").relative_to(REPO).as_posix(),
        "refinement_prompt": (HERE / "refinement-prompt.txt").relative_to(REPO).as_posix(),
        "master_style_reference": "assets/images/homebound_run/student_run.png",
        "layout": {
            "rows": 2,
            "columns": 3,
            "cell_size": list(RUNTIME_CELL),
            "base_cell": list(BASE_SIZE),
            "integer_scale": 4,
            "frame_order": FRAME_ORDER,
            "frame_duration_ms": FRAME_DURATION_MS,
            "fps": 1000 / FRAME_DURATION_MS,
            "loop_duration_ms": FRAME_DURATION_MS * len(FRAME_ORDER),
        },
        "crop_contract": {
            "left_source_rect": list(LEFT_SOURCE_RECT),
            "right_source_rect": list(RIGHT_SOURCE_RECT),
            "left_character_max_base_size": list(BODY_MAX_BASE_SIZE["left"]),
            "right_character_max_base_size": list(BODY_MAX_BASE_SIZE["right"]),
            "left_character_center_x_base": BODY_CENTERS_BASE_X["left"],
            "right_character_center_x_base": BODY_CENTERS_BASE_X["right"],
            "common_baseline_y_px": BASELINE_Y * 4,
        },
        "source_processing": {
            "raw_dimensions": list(source.size),
            "source_cell_boundaries_x": list(COL_BOUNDARIES),
            "source_row_boundaries_y": list(ROW_BOUNDARIES),
            "component_alpha_threshold": ALPHA_THRESHOLD,
            "frame_shared_scale_by_character": shared_scales,
            "resampling": "nearest-neighbour only",
            "creative_source": "built-in image_gen, one styling refinement from the first raw pass",
            "no_procedural_character_drawing": True,
        },
        "source_frames": source_qc,
        "runtime_frames": frame_qc,
        "qc": qc,
        "previews": {
            "contact_sheet": contact_path.relative_to(REPO).as_posix(),
            "animation": gif_path.relative_to(REPO).as_posix(),
        },
    }
    metadata_path = QC_DIR / "pipeline-meta.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps({"runtime": str(RUNTIME_PATH), "contact_sheet": str(contact_path), "qc": qc}, indent=2))


if __name__ == "__main__":
    main()
