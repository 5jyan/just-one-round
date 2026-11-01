#!/usr/bin/env python3
"""Assemble independently generated poses into the fixed Homebound run strip."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

from PIL import Image


CELL = (192, 288)
DISPLAY = (96, 144)
ORDER = ["L-contact", "L-passing", "R-contact", "R-passing"]


def bbox(frame: Image.Image):
    return frame.getchannel("A").getbbox()


def qc_frame(frame: Image.Image) -> dict[str, object]:
    bounds = bbox(frame)
    if bounds is None:
        return {"empty": True, "edge_touch": False, "bbox": None, "size": list(CELL)}
    x0, y0, x1, y1 = bounds
    return {
        "empty": False,
        "edge_touch": x0 <= 0 or y0 <= 0 or x1 >= CELL[0] or y1 >= CELL[1],
        "bbox": [x0, y0, x1, y1],
        "subject_size": [x1 - x0, y1 - y0],
        "bottom_padding": CELL[1] - y1,
        "anchor_y_normalized": y1 / CELL[1],
        "size": list(CELL),
    }


def contact_sheet(frames: list[Image.Image], scale: int, bg=(36, 42, 66, 255)) -> Image.Image:
    width, height = CELL[0] * scale, CELL[1] * scale
    sheet = Image.new("RGBA", (width * len(frames), height), bg)
    for index, frame in enumerate(frames):
        preview = frame.resize((width, height), Image.Resampling.NEAREST)
        sheet.paste(preview, (index * width, 0), preview)
    return sheet


def changed_pixels(left: Image.Image, right: Image.Image) -> int:
    return sum(1 for a, b in zip(left.getdata(), right.getdata()) if a != b)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--frames", nargs=4, required=True)
    parser.add_argument("--raw-sources", nargs=4, required=True)
    parser.add_argument("--prompts", nargs=4, required=True)
    parser.add_argument("--duration", type=int, default=125)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    frame_dir, qc_dir = output_dir / "frames", output_dir / "qc"
    frame_dir.mkdir(parents=True, exist_ok=True)
    qc_dir.mkdir(parents=True, exist_ok=True)

    frames: list[Image.Image] = []
    source_frames: list[dict[str, object]] = []
    for index, frame_path in enumerate(args.frames):
        frame = Image.open(frame_path).convert("RGBA")
        if frame.size != CELL:
            raise ValueError(f"Frame {frame_path} has size {frame.size}; expected {CELL}")
        label = ORDER[index]
        frames.append(frame)
        frame.save(frame_dir / f"{label}.png")
        source_frames.append({
            "index": index,
            "label": label,
            "processed_frame": str(Path(frame_path).resolve()),
            "source_raw": str(Path(args.raw_sources[index]).resolve()),
            "prompt": str(Path(args.prompts[index]).resolve()),
            "base_cell": [96, 144],
            "runtime_cell": list(CELL),
            "integer_scale": 2,
            "anchor_bottom_target": 272,
        })

    sheet = Image.new("RGBA", (CELL[0] * 4, CELL[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.paste(frame, (CELL[0] * index, 0), frame)
    sheet.save(output_dir / "student_run.png")
    frames[0].save(
        qc_dir / "student_run.gif",
        format="GIF",
        save_all=True,
        append_images=frames[1:],
        duration=args.duration,
        loop=0,
        disposal=2,
        transparency=0,
    )
    contact_sheet(frames, 2).save(qc_dir / "student_run_contact_2x.png")
    display_frames = [frame.resize(DISPLAY, Image.Resampling.NEAREST) for frame in frames]
    contact_sheet(display_frames, 1).save(qc_dir / "student_run_display_1x.png")

    frame_qc = [qc_frame(frame) for frame in frames]
    body_heights = [int(item["subject_size"][1]) for item in frame_qc if not item["empty"]]
    anchors = [float(item["bbox"][3]) for item in frame_qc if not item["empty"]]
    mean_height = sum(body_heights) / len(body_heights)
    height_cv = math.sqrt(sum((height - mean_height) ** 2 for height in body_heights) / len(body_heights)) / mean_height
    anchor_std = math.sqrt(sum((y - sum(anchors) / len(anchors)) ** 2 for y in anchors) / len(anchors))
    alpha_values = sorted({int(alpha) for frame in frames for alpha in frame.getchannel("A").getdata()})
    colors = {color for frame in frames for color in frame.getdata()}

    metadata = {
        "schema": "homebound_run.character_asset_qc.v2",
        "asset": "homebound_run",
        "operation": "student_run_v3_final_assembly",
        "runtime_path": "assets/images/homebound_run/student_run.png",
        "runtime_size": [CELL[0] * 4, CELL[1]],
        "runtime_cell": list(CELL),
        "base_cell": [96, 144],
        "display_size": list(DISPLAY),
        "display_scale": 0.5,
        "integer_scale": 2,
        "runtime_art_pixel": "1 logical pixel",
        "frame_order": ORDER,
        "shared_baseline_y": 272,
        "fps": 8,
        "source_frames": source_frames,
        "qc": {
            "frames": frame_qc,
            "empty_count": sum(bool(item["empty"]) for item in frame_qc),
            "edge_touch_count": sum(bool(item["edge_touch"]) for item in frame_qc),
            "body_height_mean": mean_height,
            "body_height_cv": height_cv,
            "anchor_y_std": anchor_std,
            "bottom_padding_min": min(int(item["bottom_padding"]) for item in frame_qc),
            "bottom_padding_max": max(int(item["bottom_padding"]) for item in frame_qc),
            "pairwise_changed_pixels": [changed_pixels(left, right) for left, right in zip(frames, frames[1:])],
            "alpha_values": alpha_values,
            "color_count": len(colors),
        },
        "processing": {
            "source_creative": "built-in image_gen",
            "chroma_key": "#FF00FF",
            "resampling": "nearest",
            "source_art_is_not_procedurally_drawn": True,
            "processor": "process_student_v3.py",
            "assembly": "horizontal row strip in established runtime order",
            "alpha_binary": alpha_values == [0, 255],
        },
    }
    (qc_dir / "student_run_qc.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    if metadata["qc"]["empty_count"] or metadata["qc"]["edge_touch_count"]:
        raise ValueError(f"Runtime QC failed; see {qc_dir / 'student_run_qc.json'}")
    if height_cv > 0.08 or anchor_std > 0.05:
        raise ValueError(f"Run scale/anchor QC failed; see {qc_dir / 'student_run_qc.json'}")
    print(json.dumps({"runtime": str(output_dir / "student_run.png"), "qc": metadata["qc"]}, indent=2))


if __name__ == "__main__":
    main()
