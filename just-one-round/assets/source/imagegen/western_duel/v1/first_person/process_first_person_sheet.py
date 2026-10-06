#!/usr/bin/env python3
"""Deterministically key and fit generated first-person Western game art."""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image


def remove_magenta(image: Image.Image) -> Image.Image:
    rgba = np.array(image.convert("RGBA"))
    rgb = rgba[:, :, :3].astype(np.int16)
    red, green, blue = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    key = (
        (red > 145)
        & (blue > 110)
        & (green < 115)
        & ((red - green) > 55)
        & ((blue - green) > 45)
    )
    rgba[key, 3] = 0
    return Image.fromarray(rgba)


def keep_largest_alpha_component(frame: Image.Image) -> tuple[Image.Image, dict[str, int]]:
    rgba = np.array(frame.convert("RGBA"))
    mask = rgba[:, :, 3] > 0
    visited = np.zeros(mask.shape, dtype=bool)
    coordinates = np.argwhere(mask)
    largest: list[tuple[int, int]] = []
    component_count = 0
    height, width = mask.shape

    for start_y, start_x in coordinates:
        y, x = int(start_y), int(start_x)
        if visited[y, x]:
            continue
        component_count += 1
        visited[y, x] = True
        pending = deque([(y, x)])
        component = [(y, x)]
        while pending:
            current_y, current_x = pending.popleft()
            for next_y in range(max(0, current_y - 1), min(height, current_y + 2)):
                for next_x in range(max(0, current_x - 1), min(width, current_x + 2)):
                    if mask[next_y, next_x] and not visited[next_y, next_x]:
                        visited[next_y, next_x] = True
                        pending.append((next_y, next_x))
                        component.append((next_y, next_x))
        if len(component) > len(largest):
            largest = component

    if largest:
        keep = np.zeros(mask.shape, dtype=bool)
        ys, xs = zip(*largest)
        keep[np.asarray(ys), np.asarray(xs)] = True
        removed_pixels = int(np.count_nonzero(mask & ~keep))
        rgba[~keep, 3] = 0
    else:
        removed_pixels = 0
    return Image.fromarray(rgba), {
        "alpha_components": component_count,
        "removed_component_pixels": removed_pixels,
    }


def process_frame(
    frame: Image.Image,
    width: int,
    height: int,
    fit: float,
    anchor: str,
    alpha_threshold: int,
    largest_component_only: bool,
    scale_x: float,
    scale_y: float,
    offset_x: int,
    offset_y: int,
) -> tuple[Image.Image, dict[str, object]]:
    if alpha_threshold:
        alpha = frame.getchannel("A")
        alpha = alpha.point(lambda value: 0 if value <= alpha_threshold else value)
        frame.putalpha(alpha)
    component_report = {"alpha_components": 1, "removed_component_pixels": 0}
    if largest_component_only:
        frame, component_report = keep_largest_alpha_component(frame)
    alpha = frame.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("empty frame after background removal")

    subject = frame.crop(bbox)
    source_width, source_height = subject.size
    max_width = max(1, int(width * fit))
    max_height = max(1, int(height * fit))
    scale = min(max_width / source_width, max_height / source_height)
    out_width = max(1, round(source_width * scale))
    out_height = max(1, round(source_height * scale))
    subject = subject.resize((out_width, out_height), Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    x = (width - out_width) // 2
    y = height - out_height - 2 if anchor == "bottom" else (height - out_height) // 2
    canvas.alpha_composite(subject, (x, y))
    if scale_x != 1 or scale_y != 1 or offset_x or offset_y:
        transformed = canvas.resize(
            (max(1, round(width * scale_x)), max(1, round(height * scale_y))),
            Image.Resampling.NEAREST,
        )
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        canvas.alpha_composite(transformed, (offset_x, offset_y))
    output_bbox = canvas.getchannel("A").getbbox()
    if output_bbox is None:
        raise ValueError("frame became empty during processing")
    if output_bbox[0] <= 0 or output_bbox[1] <= 0 or output_bbox[2] >= width or output_bbox[3] >= height:
        raise ValueError(f"output subject touches cell edge: {output_bbox}")

    return canvas, {
        "source_bbox": list(bbox),
        "source_subject_size": [source_width, source_height],
        "output_bbox": list(output_bbox),
        "output_subject_size": [out_width, out_height],
        "scale": scale,
        "anchor": anchor,
        "post_transform": {
            "scale_x": scale_x,
            "scale_y": scale_y,
            "offset_x": offset_x,
            "offset_y": offset_y,
        },
        "output_edge_touch": False,
        **component_report,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--cell-width", required=True, type=int)
    parser.add_argument("--cell-height", required=True, type=int)
    parser.add_argument("--rows", default=1, type=int)
    parser.add_argument("--cols", default=1, type=int)
    parser.add_argument("--fit", default=0.9, type=float)
    parser.add_argument("--anchor", choices=("center", "bottom"), default="bottom")
    parser.add_argument("--scale-x", default=1, type=float)
    parser.add_argument("--scale-y", default=1, type=float)
    parser.add_argument("--offset-x", default=0, type=int)
    parser.add_argument("--offset-y", default=0, type=int)
    parser.add_argument("--key", choices=("alpha", "magenta"), default="magenta")
    parser.add_argument("--alpha-threshold", default=0, type=int)
    parser.add_argument("--keep-largest-component", action="store_true")
    parser.add_argument("--duration-ms", default=120, type=int)
    args = parser.parse_args()

    if args.rows < 1 or args.cols < 1 or not 0 < args.fit <= 1:
        parser.error("rows/cols must be positive and fit must be in (0, 1]")
    if not 0 < args.scale_x <= 1 or not 0 < args.scale_y <= 1:
        parser.error("scale-x and scale-y must be in (0, 1]")
    if not 0 <= args.alpha_threshold <= 255:
        parser.error("alpha threshold must be in [0, 255]")

    raw = Image.open(args.input).convert("RGBA")
    if args.key == "magenta":
        raw = remove_magenta(raw)
    if raw.width < args.cols or raw.height < args.rows:
        raise ValueError("raw sheet must be at least as large as the requested grid")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    frame_reports: list[dict[str, object]] = []
    for row in range(args.rows):
        for col in range(args.cols):
            # Image generators occasionally return dimensions that are one pixel
            # off an even grid. Partition by rounded proportional boundaries so
            # no source row/column is dropped and neighboring frames stay aligned.
            x0 = round(col * raw.width / args.cols)
            x1 = round((col + 1) * raw.width / args.cols)
            y0 = round(row * raw.height / args.rows)
            y1 = round((row + 1) * raw.height / args.rows)
            raw_frame = raw.crop(
                (x0, y0, x1, y1)
            )
            processed, report = process_frame(
                raw_frame,
                args.cell_width,
                args.cell_height,
                args.fit,
                args.anchor,
                args.alpha_threshold,
                args.keep_largest_component,
                args.scale_x,
                args.scale_y,
                args.offset_x,
                args.offset_y,
            )
            label = f"frame_{len(frames) + 1:02d}.png"
            processed.save(args.output_dir / label)
            frames.append(processed)
            report.update({"grid": [row, col], "source_cell_rect": [x0, y0, x1, y1], "output": label})
            frame_reports.append(report)

    sheet = Image.new("RGBA", (args.cols * args.cell_width, args.rows * args.cell_height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, args.cols)
        sheet.alpha_composite(frame, (col * args.cell_width, row * args.cell_height))
    sheet.save(args.output_dir / "sheet-transparent.png")

    if len(frames) > 1:
        preview_frames = [frame.convert("RGBA") for frame in frames]
        preview_frames[0].save(
            args.output_dir / "animation.gif",
            save_all=True,
            append_images=preview_frames[1:],
            duration=args.duration_ms,
            loop=0,
            disposal=2,
        )

    metadata = {
        "input": str(args.input),
        "source_sheet_size": list(raw.size),
        "grid": [args.rows, args.cols],
        "cell_size": [args.cell_width, args.cell_height],
        "filter": "nearest",
        "key": args.key,
        "alpha_threshold": args.alpha_threshold,
        "fit": args.fit,
        "anchor": args.anchor,
        "post_transform": {
            "scale_x": args.scale_x,
            "scale_y": args.scale_y,
            "offset_x": args.offset_x,
            "offset_y": args.offset_y,
        },
        "frames": frame_reports,
        "qc": {
            "frame_count": len(frames),
            "empty_frames": 0,
            "output_edge_touch_frames": [],
            "passed": True,
        },
    }
    (args.output_dir / "pipeline-meta.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata["qc"], indent=2))


if __name__ == "__main__":
    main()
