#!/usr/bin/env python3
"""Deterministically key, extract, pixel-grid, align, and QC v3 student art."""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path

from PIL import Image


HERE = Path(__file__).resolve().parent
CHARACTERS = HERE.parents[1]
PROCESSOR_PATH = CHARACTERS / "process_homebound_assets.py"
SPEC = importlib.util.spec_from_file_location("homebound_processor", PROCESSOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load established processor at {PROCESSOR_PATH}")
processor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(processor)

BASE_SIZE = (96, 144)
RUNTIME_SIZE = (192, 288)
DEFAULT_BASELINE = 272


def align_bottom(frame: Image.Image, target: int) -> tuple[Image.Image, int]:
    bbox = frame.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("Empty frame after chroma cleanup")
    shift_y = target - bbox[3]
    aligned = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    aligned.paste(frame, (0, shift_y), frame)
    aligned_bbox = aligned.getchannel("A").getbbox()
    if aligned_bbox is None or aligned_bbox[1] < 0 or aligned_bbox[3] > frame.height:
        raise ValueError(f"Shared bottom anchor clips frame: {aligned_bbox}")
    return aligned, shift_y


def contact_sheet(frames: list[Image.Image], scale: int, bg=(36, 42, 66, 255)) -> Image.Image:
    if not frames:
        raise ValueError("No frames")
    width, height = frames[0].width * scale, frames[0].height * scale
    result = Image.new("RGBA", (width * len(frames), height), bg)
    for index, frame in enumerate(frames):
        preview = frame.resize((width, height), Image.Resampling.NEAREST)
        result.paste(preview, (index * width, 0), preview)
    return result


def pairwise_differences(frames: list[Image.Image]) -> list[int]:
    differences: list[int] = []
    for left, right in zip(frames, frames[1:]):
        a, b = left.convert("RGBA"), right.convert("RGBA")
        differences.append(sum(1 for x, y in zip(a.getdata(), b.getdata()) if x != y))
    return differences


def make_metadata(
    *, input_path: Path, raw: Image.Image, operation: str, labels: list[str],
    details: list[dict[str, object]], frames: list[Image.Image], baseline: int | None,
    prompt_path: Path | None, reference_path: Path | None,
) -> dict[str, object]:
    qc_frames = [processor.frame_qc(frame, RUNTIME_SIZE) for frame in frames]
    heights = [int(item["subject_size"][1]) for item in qc_frames if not item["empty"]]
    anchors = [float(item["bbox"][3]) for item in qc_frames if not item["empty"]]
    mean_height = sum(heights) / len(heights) if heights else 0.0
    height_cv = (
        math.sqrt(sum((h - mean_height) ** 2 for h in heights) / len(heights)) / mean_height
        if heights and mean_height else 0.0
    )
    anchor_std = (
        math.sqrt(sum((y - sum(anchors) / len(anchors)) ** 2 for y in anchors) / len(anchors))
        if anchors else 0.0
    )
    alpha_values = set()
    colors = set()
    for frame in frames:
        alpha_values.update(frame.getchannel("A").getdata())
        colors.update(frame.getdata())
    return {
        "schema": "homebound_run.character_asset_qc.v2",
        "asset": "homebound_run",
        "operation": operation,
        "input": str(input_path),
        "raw_size": [raw.width, raw.height],
        "source_reference": str(reference_path) if reference_path else None,
        "prompt": str(prompt_path) if prompt_path else None,
        "base_cell": list(BASE_SIZE),
        "runtime_cell": list(RUNTIME_SIZE),
        "display_size": [96, 144],
        "display_scale": 0.5,
        "integer_scale": 2,
        "runtime_art_pixel": "1 logical pixel",
        "frame_order": labels,
        "source_frames": details,
        "qc": {
            "frames": qc_frames,
            "empty_count": sum(bool(item["empty"]) for item in qc_frames),
            "edge_touch_count": sum(bool(item["edge_touch"]) for item in qc_frames),
            "body_height_mean": mean_height,
            "body_height_cv": height_cv,
            "anchor_y_std": anchor_std,
            "bottom_padding_min": min((int(item["bottom_padding"]) for item in qc_frames), default=0),
            "bottom_padding_max": max((int(item["bottom_padding"]) for item in qc_frames), default=0),
            "pairwise_changed_pixels": pairwise_differences(frames),
            "alpha_values": sorted(alpha_values),
            "color_count": len(colors),
        },
        "processing": {
            "chroma_key": "#FF00FF",
            "resampling": "nearest",
            "source_creative": "built-in image_gen",
            "source_art_is_not_procedurally_drawn": True,
            "processor": str(Path(__file__).resolve()),
            "established_chroma_and_crop_functions": str(PROCESSOR_PATH),
            "alignment": "shared alpha-bottom baseline in runtime cell",
            "baseline_y": baseline,
        },
    }


def process(args: argparse.Namespace) -> None:
    input_path = Path(args.input).resolve()
    output_dir = Path(args.output_dir).resolve()
    frame_dir, qc_dir = output_dir / "frames", output_dir / "qc"
    frame_dir.mkdir(parents=True, exist_ok=True)
    qc_dir.mkdir(parents=True, exist_ok=True)

    raw = Image.open(input_path).convert("RGBA")
    if raw.width % args.cols or raw.height % args.rows:
        raise ValueError(f"Raw image {raw.size} does not divide evenly into {args.cols}x{args.rows}")
    cleaned = processor.clean_chroma(raw)
    frames: list[Image.Image] = []
    source_frames: list[dict[str, object]] = []
    for index, cell in processor.split_cells(cleaned, args.rows, args.cols):
        if index >= len(args.labels):
            break
        four_x, metadata = processor.crop_portrait_slot(cell, BASE_SIZE)
        runtime = four_x.resize(RUNTIME_SIZE, Image.Resampling.NEAREST)
        shift = 0
        if args.anchor_bottom is not None:
            runtime, shift = align_bottom(runtime, args.anchor_bottom)
        frame_meta = {
            "index": index,
            "label": args.labels[index],
            **metadata,
            "intermediate_size": list(four_x.size),
            "runtime_size": list(RUNTIME_SIZE),
            "anchor_bottom_target": args.anchor_bottom,
            "anchor_translation_y": shift,
        }
        frames.append(runtime)
        source_frames.append(frame_meta)
        runtime.save(frame_dir / f"{args.labels[index]}.png")
    if len(frames) != len(args.labels):
        raise ValueError(f"Expected {len(args.labels)} frames, found {len(frames)}")

    sheet = Image.new("RGBA", (RUNTIME_SIZE[0] * len(frames), RUNTIME_SIZE[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.paste(frame, (index * RUNTIME_SIZE[0], 0), frame)
    sheet.save(output_dir / args.runtime_name)
    processor.write_gif(frames, qc_dir / f"{Path(args.runtime_name).stem}.gif", args.duration)
    contact_sheet(frames, 2).save(qc_dir / f"{Path(args.runtime_name).stem}_contact_2x.png")
    display_frames = [frame.resize((96, 144), Image.Resampling.NEAREST) for frame in frames]
    contact_sheet(display_frames, 1).save(qc_dir / f"{Path(args.runtime_name).stem}_display_1x.png")

    metadata = make_metadata(
        input_path=input_path,
        raw=raw,
        operation=args.operation,
        labels=args.labels,
        details=source_frames,
        frames=frames,
        baseline=args.anchor_bottom,
        prompt_path=Path(args.prompt).resolve() if args.prompt else None,
        reference_path=Path(args.reference).resolve() if args.reference else None,
    )
    metadata_path = qc_dir / f"{Path(args.runtime_name).stem}_qc.json"
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    if metadata["qc"]["empty_count"] or metadata["qc"]["edge_touch_count"]:
        raise ValueError(f"Final QC failed; see {metadata_path}")
    print(json.dumps({"runtime": str(output_dir / args.runtime_name), "qc": metadata["qc"]}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--runtime-name", required=True)
    parser.add_argument("--operation", required=True)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--labels", nargs="+", required=True)
    parser.add_argument("--duration", type=int, default=125)
    parser.add_argument("--anchor-bottom", type=int, default=DEFAULT_BASELINE)
    parser.add_argument("--prompt")
    parser.add_argument("--reference")
    process(parser.parse_args())


if __name__ == "__main__":
    main()
