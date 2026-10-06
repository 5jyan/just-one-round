#!/usr/bin/env python3
"""Process the approved Western Duel action sheet at one shared body scale.

The generic processor fits each frame independently.  That would shrink the
horizontal aim frames around their revolver.  This small deterministic pass
locks the scale to the neutral action frames and only translates each complete
body/weapon component to the shared feet line.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import deque
from pathlib import Path

from PIL import Image


def largest_component(image: Image.Image, min_alpha: int) -> tuple[Image.Image, int]:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] <= min_alpha:
                pixels[x, y] = (0, 0, 0, 0)

    alpha = rgba.getchannel("A")
    visited: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            if alpha.getpixel((x, y)) == 0 or (x, y) in visited:
                continue
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited.add((x, y))
            component: list[tuple[int, int]] = []
            while queue:
                cx, cy = queue.popleft()
                component.append((cx, cy))
                for nx, ny in (
                    (cx - 1, cy),
                    (cx + 1, cy),
                    (cx, cy - 1),
                    (cx, cy + 1),
                ):
                    if (
                        0 <= nx < width
                        and 0 <= ny < height
                        and alpha.getpixel((nx, ny)) > 0
                        and (nx, ny) not in visited
                    ):
                        visited.add((nx, ny))
                        queue.append((nx, ny))
            components.append(component)

    if not components:
        raise ValueError("empty frame after alpha cleanup")
    keep = max(components, key=len)
    keep_set = set(keep)
    for y in range(height):
        for x in range(width):
            if (x, y) not in keep_set:
                pixels[x, y] = (0, 0, 0, 0)
    return rgba, len(components)


def process(args: argparse.Namespace) -> None:
    source = Image.open(args.input).convert("RGBA")
    output = args.output_dir
    output.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    reports: list[dict[str, object]] = []
    cell_width = source.width // args.cols
    cell_height = source.height // args.rows

    for index in range(args.rows * args.cols):
        row, col = divmod(index, args.cols)
        x0, y0 = col * cell_width, row * cell_height
        x1, y1 = (col + 1) * cell_width, (row + 1) * cell_height
        cleaned, component_count = largest_component(
            source.crop((x0, y0, x1, y1)), args.alpha_threshold
        )
        bbox = cleaned.getchannel("A").getbbox()
        if bbox is None:
            raise ValueError(f"frame {index + 1} is empty")
        subject = cleaned.crop(bbox)
        new_width = max(1, round(subject.width * args.scale))
        new_height = max(1, round(subject.height * args.scale))
        scaled = subject.resize((new_width, new_height), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", (args.cell_width, args.cell_height), (0, 0, 0, 0))
        paste_x = (args.cell_width - new_width) // 2
        paste_y = args.feet_y - new_height
        if paste_x < 0 or paste_y < 0:
            raise ValueError(f"frame {index + 1} does not fit at locked scale")
        canvas.alpha_composite(scaled, (paste_x, paste_y))
        output_bbox = canvas.getchannel("A").getbbox()
        if output_bbox is None or output_bbox[0] <= 0 or output_bbox[1] <= 0:
            raise ValueError(f"frame {index + 1} touches the output top/left edge")
        if output_bbox[2] >= args.cell_width or output_bbox[3] >= args.cell_height:
            raise ValueError(f"frame {index + 1} touches the output right/bottom edge")
        name = f"frame_{index + 1:02d}.png"
        canvas.save(output / name)
        frames.append(canvas)
        reports.append(
            {
                "output": name,
                "grid": [row, col],
                "source_cell_rect": [x0, y0, x1, y1],
                "source_bbox": list(bbox),
                "source_size": list(subject.size),
                "source_edge_touch": bool(
                    bbox[0] <= 0
                    or bbox[1] <= 0
                    or bbox[2] >= cell_width
                    or bbox[3] >= cell_height
                ),
                "output_bbox": list(output_bbox),
                "output_size": [new_width, new_height],
                "component_count": component_count,
                "locked_scale": args.scale,
                "feet_y": args.feet_y,
            }
        )

    sheet = Image.new("RGBA", (args.cols * args.cell_width, args.rows * args.cell_height))
    for index, frame in enumerate(frames):
        row, col = divmod(index, args.cols)
        sheet.alpha_composite(frame, (col * args.cell_width, row * args.cell_height))
    sheet.save(output / "sheet-transparent.png")
    frames[0].save(
        output / "animation.gif",
        save_all=True,
        append_images=frames[1:],
        duration=args.duration_ms,
        loop=0,
        disposal=2,
    )
    body_scale_samples = [
        report["output_size"][1] / args.cell_height for report in reports
    ]
    anchor_y_samples = [
        report["output_bbox"][3] / args.cell_height for report in reports
    ]
    body_scale_mean = sum(body_scale_samples) / len(body_scale_samples)
    body_scale_cv = math.sqrt(
        sum((sample - body_scale_mean) ** 2 for sample in body_scale_samples)
        / len(body_scale_samples)
    ) / body_scale_mean
    anchor_y_mean = sum(anchor_y_samples) / len(anchor_y_samples)
    anchor_y_std = math.sqrt(
        sum((sample - anchor_y_mean) ** 2 for sample in anchor_y_samples)
        / len(anchor_y_samples)
    )
    max_body_scale_cv = 0.08
    max_anchor_y_std = 0.05
    metadata = {
        "input": str(args.input),
        "source_size": list(source.size),
        "grid": [args.rows, args.cols],
        "cell_size": [args.cell_width, args.cell_height],
        "filter": "nearest",
        "alpha_threshold": args.alpha_threshold,
        "locked_scale": args.scale,
        "feet_y": args.feet_y,
        "duration_ms": args.duration_ms,
        "frame_order": ["ready", "grip", "draw", "aim", "fire", "recoil"],
        "frames": reports,
        "qc": {
            "empty_frames": [],
            "output_edge_touch_frames": [],
            "source_edge_touch_frames_reviewed": [
                report["grid"] for report in reports if report["source_edge_touch"]
            ],
            "body_scale_locked": True,
            "body_scale_samples": body_scale_samples,
            "body_scale_mean": body_scale_mean,
            "body_scale_cv": body_scale_cv,
            "anchor_y_samples": anchor_y_samples,
            "anchor_y_mean": anchor_y_mean,
            "anchor_y_std": anchor_y_std,
            "max_body_scale_cv": max_body_scale_cv,
            "max_anchor_y_std": max_anchor_y_std,
            "passed": body_scale_cv <= max_body_scale_cv
            and anchor_y_std <= max_anchor_y_std,
        },
    }
    (output / "pipeline-meta.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--rows", type=int, default=2)
    parser.add_argument("--cols", type=int, default=3)
    parser.add_argument("--cell-width", type=int, default=270)
    parser.add_argument("--cell-height", type=int, default=540)
    parser.add_argument("--scale", type=float, required=True)
    parser.add_argument("--feet-y", type=int, default=520)
    parser.add_argument("--alpha-threshold", type=int, default=16)
    parser.add_argument("--duration-ms", type=int, default=53)
    process(parser.parse_args())


if __name__ == "__main__":
    main()
