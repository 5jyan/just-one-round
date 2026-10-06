#!/usr/bin/env python3
"""Center-crop and nearest-neighbor fit the Western duel saloon background."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--width", type=int, default=180)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGB")
    target_ratio = args.width / args.height
    source_ratio = image.width / image.height
    if source_ratio > target_ratio:
        crop_width = round(image.height * target_ratio)
        left = (image.width - crop_width) // 2
        crop_box = (left, 0, left + crop_width, image.height)
    else:
        crop_height = round(image.width / target_ratio)
        top = (image.height - crop_height) // 2
        crop_box = (0, top, image.width, top + crop_height)

    fitted = image.crop(crop_box).resize((args.width, args.height), Image.Resampling.NEAREST)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fitted.save(args.output)
    metadata = {
        "input": str(args.input),
        "source_size": list(image.size),
        "crop_box": list(crop_box),
        "output": str(args.output),
        "output_size": [args.width, args.height],
        "filter": "nearest",
        "qc": {
            "aspect_matches_contract": fitted.width / fitted.height == target_ratio,
            "passed": fitted.size == (args.width, args.height),
        },
    }
    args.output.with_name("pipeline-meta.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata["qc"], indent=2))


if __name__ == "__main__":
    main()
