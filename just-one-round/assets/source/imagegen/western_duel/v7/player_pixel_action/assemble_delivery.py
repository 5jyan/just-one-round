#!/usr/bin/env python3
"""Assemble the rectangular Western Duel delivery atlas from QC'd square frames.

The Sprite Forge processor uses square cells.  Its 540px frames are centered
cropped to the approved 270x540 delivery cell; the crop is intentionally
transparent-only and is rejected if any opaque pixel would be lost.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


FRAME_NAMES = (
    "ready",
    "grip",
    "draw",
    "aim",
    "fire",
    "recoil",
)


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int] | None:
    return image.getchannel("A").getbbox()


def assemble(input_sheet: Path, output_dir: Path, runtime_dir: Path) -> None:
    source = Image.open(input_sheet).convert("RGBA")
    if source.size != (1620, 1080):
        raise ValueError(f"expected 1620x1080 QC sheet, got {source.size}")

    output_dir.mkdir(parents=True, exist_ok=True)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    delivery_frames: list[Image.Image] = []
    crop_left = 135
    crop_right = 405
    for index, name in enumerate(FRAME_NAMES):
        column = index % 3
        row = index // 3
        native = source.crop((column * 540, row * 540, (column + 1) * 540, (row + 1) * 540))
        delivery = native.crop((crop_left, 0, crop_right, 540))
        native_bbox = alpha_bbox(native)
        delivery_bbox = alpha_bbox(delivery)
        if native_bbox and delivery_bbox is None:
            raise ValueError(f"frame {index} lost its subject in the delivery crop")
        if native_bbox:
            x0, y0, x1, y1 = native_bbox
            if x0 < crop_left or x1 > crop_right:
                raise ValueError(
                    f"frame {index} subject exceeds crop: bbox={native_bbox}, "
                    f"crop=({crop_left},0,{crop_right},540)"
                )
        delivery.save(output_dir / f"frame_{index + 1:02d}.png")
        delivery.save(runtime_dir / f"frame_{index + 1:02d}.png")
        delivery_frames.append(delivery)

    sheet = Image.new("RGBA", (810, 1080), (0, 0, 0, 0))
    for index, frame in enumerate(delivery_frames):
        sheet.alpha_composite(frame, ((index % 3) * 270, (index // 3) * 540))
    sheet.save(output_dir / "sheet-transparent.png")
    sheet.save(runtime_dir / "sheet-transparent.png")
    delivery_frames[0].save(
        output_dir / "animation.gif",
        save_all=True,
        append_images=delivery_frames[1:],
        duration=53,
        loop=0,
        disposal=2,
        transparency=0,
    )
    delivery_frames[0].save(
        runtime_dir / "animation.gif",
        save_all=True,
        append_images=delivery_frames[1:],
        duration=53,
        loop=0,
        disposal=2,
        transparency=0,
    )
    metadata = {
        "source_sheet": str(input_sheet),
        "source_cell": {"width": 540, "height": 540},
        "delivery_cell": {"width": 270, "height": 540},
        "crop": {"left": crop_left, "top": 0, "right": crop_right, "bottom": 540},
        "sheet": {"columns": 3, "rows": 2, "width": 810, "height": 1080},
        "frames": list(FRAME_NAMES),
        "duration_ms": 53,
        "display_scale": {"x": 2, "y": 2},
        "raw_body_preserved": True,
        "crop_policy": "centered transparent-only crop; reject any opaque pixel loss",
    }
    (output_dir / "delivery-meta.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    (runtime_dir / "pipeline-meta.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    assemble(args.input, args.output_dir, args.runtime_dir)


if __name__ == "__main__":
    main()
