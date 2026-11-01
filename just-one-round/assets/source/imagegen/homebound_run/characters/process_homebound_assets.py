#!/usr/bin/env python3
"""Deterministic extraction and nearest-neighbour packaging for Homebound Run art.

Creative pixels come from built-in Image Gen.  This script only removes the
approved chroma background, extracts generated cells, reduces them to the
locked base grid, scales them by 4x, and writes QC metadata/previews.
"""

from __future__ import annotations

import argparse
import colorsys
import json
import math
from pathlib import Path
from typing import Iterable

from PIL import Image


MAGENTA = (255, 0, 255)
BASE_SCALE = 4


def looks_magenta(r: int, g: int, b: int) -> bool:
    """Reject solid magenta and anti-aliased magenta fringe without eating skin."""
    return r >= 190 and b >= 150 and g <= 155 and r - g >= 70 and b - g >= 35


def clean_chroma(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _a = pixels[x, y]
            if looks_magenta(r, g, b):
                pixels[x, y] = (*MAGENTA, 0)
    # Image Gen may leave a one-to-three-pixel dark-purple halo where the
    # solid magenta meets a stepped contour.  Remove only hue-matched pixels
    # that are still connected to the transparent outside; this preserves the
    # student's navy shadows and brick-red backpack interiors.
    for _pass in range(8):
        remove: list[tuple[int, int]] = []
        for y in range(rgba.height):
            for x in range(rgba.width):
                r, g, b, a = pixels[x, y]
                if a == 0:
                    continue
                hue, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                magenta_fringe = 0.74 <= hue <= 0.90 and saturation >= 0.40 and value >= 0.12
                if not magenta_fringe:
                    continue
                adjacent_clear = False
                for nx in range(max(0, x - 1), min(rgba.width, x + 2)):
                    for ny in range(max(0, y - 1), min(rgba.height, y + 2)):
                        if pixels[nx, ny][3] == 0:
                            adjacent_clear = True
                            break
                    if adjacent_clear:
                        break
                if adjacent_clear:
                    remove.append((x, y))
        for x, y in remove:
            pixels[x, y] = (*MAGENTA, 0)
    return rgba


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    return alpha.getbbox()


def bbox_size(bbox: tuple[int, int, int, int] | None) -> tuple[int, int]:
    if bbox is None:
        return (0, 0)
    return (bbox[2] - bbox[0], bbox[3] - bbox[1])


def scale_nearest(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.NEAREST)


def make_transparent_canvas_fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    source = image
    scale = min(size[0] / source.width, size[1] / source.height)
    width = max(1, round(source.width * scale))
    height = max(1, round(source.height * scale))
    scaled = scale_nearest(source, (width, height))
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(scaled, ((size[0] - width) // 2, (size[1] - height) // 2), scaled)
    return canvas


def crop_portrait_slot(
    clean_cell: Image.Image,
    base_size: tuple[int, int],
    *,
    center_on_subject: bool = True,
) -> tuple[Image.Image, dict[str, object]]:
    """Crop a portrait runtime slot while retaining the full generated height."""
    bbox = alpha_bbox(clean_cell)
    if bbox is None:
        raise ValueError("Generated cell is empty after chroma cleanup")
    base_width, base_height = base_size
    crop_width = round(clean_cell.height * base_width / base_height)
    subject_center_x = (bbox[0] + bbox[2]) / 2 if center_on_subject else clean_cell.width / 2
    x0 = round(subject_center_x - crop_width / 2)
    x0 = max(0, min(clean_cell.width - crop_width, x0))
    x1 = x0 + crop_width
    if bbox[0] < x0 or bbox[2] > x1:
        raise ValueError(f"Subject is wider than the portrait slot: bbox={bbox}, crop={(x0, 0, x1, clean_cell.height)}")
    cropped = clean_chroma(clean_cell.crop((x0, 0, x1, clean_cell.height)))
    base = scale_nearest(cropped, base_size)
    runtime = scale_nearest(base, (base_width * BASE_SCALE, base_height * BASE_SCALE))
    return runtime, {
        "source_bbox": list(bbox),
        "source_bbox_size": list(bbox_size(bbox)),
        "source_crop": [x0, 0, x1, clean_cell.height],
        "base_size": list(base_size),
        "runtime_size": [base_width * BASE_SCALE, base_height * BASE_SCALE],
    }


def split_cells(image: Image.Image, rows: int, cols: int) -> Iterable[tuple[int, Image.Image]]:
    cell_width = image.width // cols
    cell_height = image.height // rows
    for row in range(rows):
        for col in range(cols):
            box = (col * cell_width, row * cell_height, (col + 1) * cell_width, (row + 1) * cell_height)
            yield row * cols + col, image.crop(box)


def final_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    return alpha_bbox(image)


def frame_qc(image: Image.Image, expected_size: tuple[int, int]) -> dict[str, object]:
    bbox = final_bbox(image)
    width, height = bbox_size(bbox)
    if bbox is None:
        return {
            "empty": True,
            "edge_touch": False,
            "size": list(expected_size),
            "bbox": None,
            "subject_size": [0, 0],
            "bottom_padding": expected_size[1],
        }
    return {
        "empty": False,
        "edge_touch": bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= expected_size[0] or bbox[3] >= expected_size[1],
        "size": list(expected_size),
        "bbox": list(bbox),
        "subject_size": [width, height],
        "bottom_padding": expected_size[1] - bbox[3],
        "anchor_y_normalized": bbox[3] / expected_size[1],
    }


def write_gif(frames: list[Image.Image], path: Path, duration_ms: int) -> None:
    if not frames:
        return
    rgba_frames = [frame.convert("RGBA") for frame in frames]
    rgba_frames[0].save(
        path,
        format="GIF",
        save_all=True,
        append_images=rgba_frames[1:],
        duration=duration_ms,
        loop=0,
        disposal=2,
        transparency=0,
    )


def contact_sheet(frames: list[Image.Image], scale: int = 2) -> Image.Image:
    if not frames:
        raise ValueError("No frames for contact sheet")
    width = frames[0].width * scale
    height = frames[0].height * scale
    sheet = Image.new("RGBA", (width * len(frames), height), (36, 42, 66, 255))
    for index, frame in enumerate(frames):
        preview = scale_nearest(frame, (width, height))
        sheet.paste(preview, (index * width, 0), preview)
    return sheet


def common_metadata(
    *,
    input_path: Path,
    raw: Image.Image,
    operation: str,
    base_size: tuple[int, int],
    runtime_size: tuple[int, int],
    frame_order: list[str],
    source_frames: list[dict[str, object]],
    runtime_frames: list[Image.Image],
) -> dict[str, object]:
    qc = [frame_qc(frame, runtime_size) for frame in runtime_frames]
    body_heights = [int(item["subject_size"][1]) for item in qc if not item["empty"]]
    anchors = [float(item["anchor_y_normalized"]) for item in qc if not item["empty"]]
    mean = sum(body_heights) / len(body_heights) if body_heights else 0.0
    scale_cv = (
        math.sqrt(sum((value - mean) ** 2 for value in body_heights) / len(body_heights)) / mean
        if body_heights and mean
        else 0.0
    )
    anchor_std = (
        math.sqrt(sum((value - sum(anchors) / len(anchors)) ** 2 for value in anchors) / len(anchors))
        if anchors
        else 0.0
    )
    return {
        "asset": "homebound_run",
        "operation": operation,
        "input": str(input_path),
        "raw_size": [raw.width, raw.height],
        "base_cell": list(base_size),
        "runtime_cell": list(runtime_size),
        "integer_scale": BASE_SCALE,
        "frame_order": frame_order,
        "source_frames": source_frames,
        "qc": {
            "frames": qc,
            "empty_count": sum(1 for item in qc if item["empty"]),
            "edge_touch_count": sum(1 for item in qc if item["edge_touch"]),
            "body_height_mean": mean,
            "body_height_cv": scale_cv,
            "anchor_y_std": anchor_std,
            "bottom_padding_min": min((int(item["bottom_padding"]) for item in qc), default=0),
            "bottom_padding_max": max((int(item["bottom_padding"]) for item in qc), default=0),
        },
        "processing": {
            "chroma_key": "#FF00FF",
            "resampling": "nearest",
            "source_creative": "built-in image_gen",
            "source_art_is_not_procedurally_drawn": True,
        },
    }


def process_portrait_sheet(args: argparse.Namespace) -> None:
    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    frame_dir = output_dir / "frames"
    qc_dir = output_dir / "qc"
    frame_dir.mkdir(parents=True, exist_ok=True)
    qc_dir.mkdir(parents=True, exist_ok=True)
    raw = Image.open(input_path).convert("RGBA")
    cleaned = clean_chroma(raw)
    base_size = tuple(args.base_size)
    runtime_size = tuple(value * BASE_SCALE for value in base_size)
    labels = args.labels
    frames: list[Image.Image] = []
    source_frames: list[dict[str, object]] = []
    for index, cell in split_cells(cleaned, args.rows, args.cols):
        if index >= len(labels):
            break
        runtime, details = crop_portrait_slot(cell, base_size)
        if args.anchor_bottom is not None:
            bbox = alpha_bbox(runtime)
            if bbox is None:
                raise ValueError(f"Generated cell {labels[index]} is empty before anchor alignment")
            delta_y = args.anchor_bottom - bbox[3]
            aligned = Image.new("RGBA", runtime.size, (0, 0, 0, 0))
            aligned.paste(runtime, (0, delta_y), runtime)
            aligned_bbox = alpha_bbox(aligned)
            if aligned_bbox is None or aligned_bbox[1] < 0 or aligned_bbox[3] > runtime.height:
                raise ValueError(f"Shared bottom anchor clipped cell {labels[index]}: {aligned_bbox}")
            runtime = aligned
            details["anchor_bottom_target"] = args.anchor_bottom
            details["anchor_translation_y"] = delta_y
        frames.append(runtime)
        source_frames.append({"index": index, "label": labels[index], **details})
        runtime.save(frame_dir / f"{labels[index]}.png")

    if len(frames) != len(labels):
        raise ValueError(f"Expected {len(labels)} cells, extracted {len(frames)}")
    sheet = Image.new("RGBA", (runtime_size[0] * len(frames), runtime_size[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        sheet.paste(frame, (index * runtime_size[0], 0), frame)
    sheet.save(output_dir / args.runtime_name)
    write_gif(frames, qc_dir / f"{Path(args.runtime_name).stem}.gif", args.duration)
    contact_sheet(frames, scale=2).save(qc_dir / f"{Path(args.runtime_name).stem}_contact_2x.png")
    metadata = common_metadata(
        input_path=input_path,
        raw=raw,
        operation=args.operation,
        base_size=base_size,
        runtime_size=runtime_size,
        frame_order=labels,
        source_frames=source_frames,
        runtime_frames=frames,
    )
    (qc_dir / f"{Path(args.runtime_name).stem}_qc.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    if metadata["qc"]["empty_count"] or metadata["qc"]["edge_touch_count"]:
        raise ValueError(f"Final QC failed: {metadata['qc']}")
    print(json.dumps({"runtime": str((output_dir / args.runtime_name).resolve()), "qc": metadata["qc"]}, indent=2))


def process_pack(args: argparse.Namespace) -> None:
    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    qc_dir = output_dir / "qc"
    output_dir.mkdir(parents=True, exist_ok=True)
    qc_dir.mkdir(parents=True, exist_ok=True)
    raw = Image.open(input_path).convert("RGBA")
    cleaned = clean_chroma(raw)
    base_size = tuple(args.base_size)
    runtime_size = tuple(value * BASE_SCALE for value in base_size)
    frames: list[Image.Image] = []
    source_frames: list[dict[str, object]] = []
    labels = args.labels
    for index, cell in split_cells(cleaned, args.rows, args.cols):
        if index >= len(labels):
            break
        bbox = alpha_bbox(cell)
        if bbox is None:
            raise ValueError(f"Pack cell {labels[index]} is empty")
        cropped = clean_chroma(cell.crop(bbox))
        inner_size = (
            max(1, round(base_size[0] * args.inner_scale)),
            max(1, round(base_size[1] * args.inner_scale)),
        )
        inner = make_transparent_canvas_fit(cropped, inner_size)
        base = Image.new("RGBA", base_size, (0, 0, 0, 0))
        base.paste(inner, ((base_size[0] - inner.width) // 2, (base_size[1] - inner.height) // 2), inner)
        runtime = scale_nearest(base, runtime_size)
        frames.append(runtime)
        source_frames.append({"index": index, "label": labels[index], "source_bbox": list(bbox), "source_bbox_size": list(bbox_size(bbox))})
        runtime.save(output_dir / f"{labels[index]}.png")
    if len(frames) != len(labels):
        raise ValueError(f"Expected {len(labels)} pack cells, extracted {len(frames)}")
    contact_sheet(frames, scale=4).save(qc_dir / "items_contact_4x.png")
    metadata = common_metadata(
        input_path=input_path,
        raw=raw,
        operation=args.operation,
        base_size=base_size,
        runtime_size=runtime_size,
        frame_order=labels,
        source_frames=source_frames,
        runtime_frames=frames,
    )
    (qc_dir / "items_qc.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    if metadata["qc"]["empty_count"] or metadata["qc"]["edge_touch_count"]:
        raise ValueError(f"Final QC failed: {metadata['qc']}")
    print(json.dumps({"outputs": [str((output_dir / f'{label}.png').resolve()) for label in labels], "qc": metadata["qc"]}, indent=2))


def process_transparent_pack(args: argparse.Namespace) -> None:
    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    qc_dir = output_dir / "qc"
    output_dir.mkdir(parents=True, exist_ok=True)
    qc_dir.mkdir(parents=True, exist_ok=True)
    raw = Image.open(input_path).convert("RGBA")
    cleaned = clean_chroma(raw)
    base_size = tuple(args.base_size)
    runtime_size = tuple(value * BASE_SCALE for value in base_size)
    bbox = alpha_bbox(cleaned)
    if bbox is None:
        raise ValueError("Transparent pack is empty")
    # Preserve the generated composition (including the lower-foreground
    # placement) while adding a deterministic transparent safety margin. This
    # also prevents source-edge-touching fists or jacket hems from becoming
    # runtime-edge clipping after nearest-neighbour scaling.
    inner_size = (
        max(1, round(base_size[0] * args.inner_scale)),
        max(1, round(base_size[1] * args.inner_scale)),
    )
    inner = make_transparent_canvas_fit(cleaned, inner_size)
    base = Image.new("RGBA", base_size, (0, 0, 0, 0))
    base.paste(inner, ((base_size[0] - inner.width) // 2, (base_size[1] - inner.height) // 2), inner)
    runtime = scale_nearest(base, runtime_size)
    runtime.save(output_dir / args.runtime_name)
    metadata = common_metadata(
        input_path=input_path,
        raw=raw,
        operation=args.operation,
        base_size=base_size,
        runtime_size=runtime_size,
        frame_order=[args.runtime_name],
        source_frames=[{"source_bbox": list(bbox), "source_bbox_size": list(bbox_size(bbox))}],
        runtime_frames=[runtime],
    )
    runtime_preview = scale_nearest(runtime, (runtime.width * 2, runtime.height * 2))
    runtime_preview.save(qc_dir / f"{Path(args.runtime_name).stem}_2x.png")
    (qc_dir / f"{Path(args.runtime_name).stem}_qc.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    if metadata["qc"]["empty_count"] or metadata["qc"]["edge_touch_count"]:
        raise ValueError(f"Final QC failed: {metadata['qc']}")
    print(json.dumps({"runtime": str((output_dir / args.runtime_name).resolve()), "qc": metadata["qc"]}, indent=2))


def parse_size(value: str) -> tuple[int, int]:
    try:
        width, height = (int(part) for part in value.lower().split("x", 1))
    except Exception as exc:  # pragma: no cover - command-line guard
        raise argparse.ArgumentTypeError("size must look like WIDTHxHEIGHT") from exc
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError("size must be positive")
    return width, height


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    portrait = subparsers.add_parser("portrait-sheet")
    portrait.add_argument("--input", required=True)
    portrait.add_argument("--output-dir", required=True)
    portrait.add_argument("--runtime-name", required=True)
    portrait.add_argument("--operation", required=True)
    portrait.add_argument("--rows", type=int, required=True)
    portrait.add_argument("--cols", type=int, required=True)
    portrait.add_argument("--base-size", type=parse_size, default=(48, 72))
    portrait.add_argument("--labels", nargs="+", required=True)
    portrait.add_argument("--duration", type=int, default=125)
    portrait.add_argument("--anchor-bottom", type=int, default=None)
    portrait.set_defaults(func=process_portrait_sheet)

    pack = subparsers.add_parser("item-pack")
    pack.add_argument("--input", required=True)
    pack.add_argument("--output-dir", required=True)
    pack.add_argument("--operation", required=True)
    pack.add_argument("--rows", type=int, required=True)
    pack.add_argument("--cols", type=int, required=True)
    pack.add_argument("--base-size", type=parse_size, default=(16, 16))
    pack.add_argument("--labels", nargs="+", required=True)
    pack.add_argument("--inner-scale", type=float, default=0.80)
    pack.set_defaults(func=process_pack)

    transparent = subparsers.add_parser("transparent-pack")
    transparent.add_argument("--input", required=True)
    transparent.add_argument("--output-dir", required=True)
    transparent.add_argument("--runtime-name", required=True)
    transparent.add_argument("--operation", required=True)
    transparent.add_argument("--base-size", type=parse_size, required=True)
    transparent.add_argument("--chroma", action="store_true")
    transparent.add_argument("--inner-scale", type=float, default=0.86)
    transparent.set_defaults(func=process_transparent_pack)
    return parser


if __name__ == "__main__":
    parser = build_parser()
    arguments = parser.parse_args()
    arguments.func(arguments)
