#!/usr/bin/env python3
"""Deterministically process the approved v12 forward-fall ImageGen sheet."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[5]
RAW = ROOT / "raw_generated/player_forward_fall_v12_raw.png"
PROMPT = ROOT / "prompt.txt"
QC_DIR = ROOT / "qc"
DELIVERY = PROJECT / "assets/images/western_duel/first_person/player_forward_fall_v12"
V11_FRAME = PROJECT / "assets/images/western_duel/first_person/player_detail_idle_v11/frame_01.png"
GENERATE2DSPRITE = Path("/Users/saulpark/.codex/skills/generate2dsprite/scripts/generate2dsprite.py")
IMAGEGEN_SOURCE = Path(
    "/Users/saulpark/.codex/generated_images/01a0e7e9-6965-7fd1-a6b0-3339f3ecf0fe/"
    "exec-4b6bab55-d3b0-4808-aa24-bb92ec135b90.png"
)

CELL_W, CELL_H = 540, 1080
SOURCE_ROWS, SOURCE_COLS = 2, 4
FRAME_COUNT = 8
ALPHA_FLOOR = 32
MAGENTA_THRESHOLD = 100
EDGE_THRESHOLD = 150
FRAME_DURATION_MS = 80
REFERENCE_BBOX = (113, 306, 427, 1040)


def _load_processor():
    spec = importlib.util.spec_from_file_location("generate2dsprite", GENERATE2DSPRITE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GENERATE2DSPRITE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


PROCESSOR = _load_processor()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def magenta_like(red: int, green: int, blue: int) -> bool:
    flat_key = (
        red >= 165
        and blue >= 120
        and green <= 145
        and abs(red - blue) <= 115
    )
    purple_spill = (
        red >= 55
        and blue >= 45
        and blue >= red * 0.60
        and green < min(red, blue) * 0.75
    )
    return flat_key or purple_spill


def clean_sheet(raw: Image.Image) -> tuple[Image.Image, dict[str, int]]:
    """Use generate2dsprite chroma cleanup, then remove low-alpha fringe."""

    cleaned = PROCESSOR.remove_bg_magenta(
        raw.convert("RGBA").copy(), MAGENTA_THRESHOLD, EDGE_THRESHOLD
    )
    pixels = cleaned.load()
    alpha_floor_removed = 0
    magenta_removed = 0
    for y in range(cleaned.height):
        for x in range(cleaned.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha < ALPHA_FLOOR:
                if alpha:
                    alpha_floor_removed += 1
                pixels[x, y] = (0, 0, 0, 0)
            elif magenta_like(red, green, blue):
                magenta_removed += 1
                pixels[x, y] = (0, 0, 0, 0)
    return cleaned, {
        "alpha_floor": ALPHA_FLOOR,
        "alpha_floor_removed_pixels": alpha_floor_removed,
        "magenta_like_removed_pixels": magenta_removed,
    }


def split_frames(cleaned: Image.Image) -> tuple[list[Image.Image], list[list[int]]]:
    x_bounds = [round(index * cleaned.width / SOURCE_COLS) for index in range(SOURCE_COLS + 1)]
    y_bounds = [round(index * cleaned.height / SOURCE_ROWS) for index in range(SOURCE_ROWS + 1)]
    frames = []
    for row in range(SOURCE_ROWS):
        for col in range(SOURCE_COLS):
            frames.append(
                cleaned.crop((x_bounds[col], y_bounds[row], x_bounds[col + 1], y_bounds[row + 1]))
            )
    return frames, [x_bounds, y_bounds]


def bbox(image: Image.Image) -> tuple[int, int, int, int]:
    found = image.getchannel("A").getbbox()
    if found is None:
        raise ValueError("fall frame has no opaque subject after cleanup")
    return found


def resize_and_place(frames: list[Image.Image], bboxes: list[tuple[int, int, int, int]]):
    first = bboxes[0]
    first_height = first[3] - first[1]
    reference_height = REFERENCE_BBOX[3] - REFERENCE_BBOX[1]
    scale = reference_height / first_height
    target_center_x = (REFERENCE_BBOX[0] + REFERENCE_BBOX[2]) / 2
    first_center_x = (first[0] + first[2]) / 2
    x_translation = target_center_x - first_center_x * scale
    baseline_y = REFERENCE_BBOX[3]
    y_translation = baseline_y - first[3] * scale
    output = []
    output_bboxes = []
    scales = []
    for frame, frame_bbox in zip(frames, bboxes):
        x0, y0, x1, y1 = frame_bbox
        subject = frame.crop(frame_bbox)
        size = (
            max(1, round(subject.width * scale)),
            max(1, round(subject.height * scale)),
        )
        subject = subject.resize(size, Image.Resampling.NEAREST)
        paste_x = round(x_translation + x0 * scale)
        paste_y = round(y_translation + y0 * scale)
        if paste_x < 0 or paste_y < 0 or paste_x + subject.width > CELL_W or paste_y + subject.height > CELL_H:
            raise ValueError(
                f"frame {len(output) + 1} exceeds delivery cell: "
                f"paste=({paste_x},{paste_y}) size={subject.size}"
            )
        canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        canvas.alpha_composite(subject, (paste_x, paste_y))
        output.append(canvas)
        output_bboxes.append(canvas.getchannel("A").getbbox())
        scales.append(scale)
    return output, output_bboxes, {
        "common_scale": scale,
        "first_frame_source_bbox": list(first),
        "first_frame_source_height": first_height,
        "reference_bbox": list(REFERENCE_BBOX),
        "x_translation": x_translation,
        "y_translation": y_translation,
        "target_body_center_x": target_center_x,
        "baseline_y": baseline_y,
        "per_frame_scale": scales,
    }


def write_atlas(frames: list[Image.Image], path: Path, rows: int, cols: int) -> None:
    sheet = Image.new("RGBA", (cols * CELL_W, rows * CELL_H), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, cols)
        sheet.alpha_composite(frame, (col * CELL_W, row * CELL_H))
    sheet.save(path)


def write_qc_contact_sheet(frames: list[Image.Image], path: Path) -> None:
    thumb_w, thumb_h = CELL_W // 2, CELL_H // 2
    sheet = Image.new("RGBA", (thumb_w * 4, thumb_h * 2), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, 4)
        thumb = frame.resize((thumb_w, thumb_h), Image.Resampling.NEAREST)
        sheet.alpha_composite(thumb, (col * thumb_w, row * thumb_h))
    sheet.save(path)


def write_gif(frames: list[Image.Image], path: Path) -> None:
    PROCESSOR.save_transparent_gif(frames, path, FRAME_DURATION_MS)


def main() -> None:
    DELIVERY.mkdir(parents=True, exist_ok=True)
    QC_DIR.mkdir(parents=True, exist_ok=True)

    raw = Image.open(RAW).convert("RGBA")
    cleaned, cleanup = clean_sheet(raw)
    cleaned.save(ROOT / "raw-sheet-clean.png")
    frames, bounds = split_frames(cleaned)
    source_bboxes = [bbox(frame) for frame in frames]
    delivered, output_bboxes, scale = resize_and_place(frames, source_bboxes)

    for index, frame in enumerate(delivered, start=1):
        frame.save(DELIVERY / f"frame_{index:02d}.png")
    write_atlas(delivered, DELIVERY / "sheet-transparent.png", rows=4, cols=2)
    write_gif(delivered, DELIVERY / "animation.gif")
    write_qc_contact_sheet(delivered, QC_DIR / "contact-sheet.png")
    write_gif(delivered, QC_DIR / "animation.gif")

    source_edge_touch = [
        index + 1
        for index, (frame, frame_bbox) in enumerate(zip(frames, source_bboxes))
        if frame_bbox[0] <= 0
        or frame_bbox[1] <= 0
        or frame_bbox[2] >= frame.width
        or frame_bbox[3] >= frame.height
    ]
    output_edge_touch = [
        index + 1
        for index, frame_bbox in enumerate(output_bboxes)
        if frame_bbox[0] <= 0
        or frame_bbox[1] <= 0
        or frame_bbox[2] >= CELL_W
        or frame_bbox[3] >= CELL_H
    ]
    frame_heights = [box[3] - box[1] for box in output_bboxes]
    frame_widths = [box[2] - box[0] for box in output_bboxes]
    prompt_text = PROMPT.read_text(encoding="utf-8")
    raw_hash = sha256(RAW)
    output_hashes = [sha256(DELIVERY / f"frame_{index:02d}.png") for index in range(1, FRAME_COUNT + 1)]
    provenance = {
        "schema": "western_duel.player_forward_fall_v12.provenance.v1",
        "generation_method": "built-in image_gen source; deterministic postprocess only",
        "prompt": prompt_text,
        "prompt_sha256": sha256(PROMPT),
        "source": {
            "raw_source": str(IMAGEGEN_SOURCE),
            "copied_raw": str(RAW.relative_to(PROJECT)),
            "raw_dimensions": list(raw.size),
            "raw_mode": raw.mode,
            "raw_sha256": raw_hash,
            "raw_alpha_bbox": list(raw.getchannel("A").getbbox() or ()),
            "cleaned_sha256": sha256(ROOT / "raw-sheet-clean.png"),
        },
        "layout": {
            "source_grid": [SOURCE_ROWS, SOURCE_COLS],
            "source_order": "left_to_right_then_down",
            "source_cell_bounds_x": bounds[0],
            "source_cell_bounds_y": bounds[1],
            "source_cell_sizes": [list(frame.size) for frame in frames],
            "delivery_grid": [4, 2],
            "delivery_cell": [CELL_W, CELL_H],
            "delivery_atlas": [CELL_W * 2, CELL_H * 4],
        },
        "scale": scale,
        "anchors": {
            "reference_asset": str(V11_FRAME.relative_to(PROJECT)),
            "reference_bbox": list(REFERENCE_BBOX),
            "policy": "one scale from cleaned frame 1; one shared x/y mapping from frame 1 body center and grounded baseline; later fall poses retain natural source-coordinate descent and bbox shrink",
            "common_x_translation": scale["x_translation"],
            "common_y_translation": scale["y_translation"],
            "source_bboxes": [list(box) for box in source_bboxes],
            "output_bboxes": [list(box) for box in output_bboxes],
        },
        "cleanup": {
            "processor": str(GENERATE2DSPRITE),
            "processor_operation": "remove_bg_magenta",
            "magenta_threshold": MAGENTA_THRESHOLD,
            "edge_threshold": EDGE_THRESHOLD,
            "alpha_floor": cleanup["alpha_floor"],
            "alpha_floor_removed_pixels": cleanup["alpha_floor_removed_pixels"],
            "magenta_like_removed_pixels": cleanup["magenta_like_removed_pixels"],
            "component_filter": "none; generated body remains intact",
            "resampling": "nearest",
            "creative_redraw": False,
        },
        "runtime": {
            "placement": {"x": -254, "y": "height - 680"},
            "frame_duration_ms": [FRAME_DURATION_MS] * FRAME_COUNT,
            "frame_count": FRAME_COUNT,
        },
        "qc": {
            "source_edge_touch_frames": source_edge_touch,
            "output_edge_touch_frames": output_edge_touch,
            "empty_frames": [],
            "common_scale": scale["common_scale"],
            "first_frame_source_height": scale["first_frame_source_height"],
            "output_widths": frame_widths,
            "output_heights": frame_heights,
            "max_output_width": max(frame_widths),
            "min_horizontal_margin": min(
                min(box[0], CELL_W - box[2]) for box in output_bboxes
            ),
            "frame_sha256": output_hashes,
        },
    }
    (ROOT / "provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    (DELIVERY / "pipeline-meta.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
