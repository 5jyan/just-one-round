#!/usr/bin/env python3
"""Deterministic postprocess for the two generated Temple Run hazard variants.

Creative pixels are kept in each variant's raw/ directory. This file only
removes transparent fringe, fits the accepted source into the base contract,
and emits a 4x nearest-neighbor runtime copy.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).parent
RUNTIME_ROOT = ROOT.parents[4] / "assets" / "images" / "homebound_run"
VARIANTS = {
    "obstacle_jump_variant": ("obstacle_jump_variant_v1", (128, 64), 4),
    "obstacle_slide_variant": ("obstacle_slide_variant_v1", (128, 128), 6),
}


def remove_fringe(image: Image.Image) -> Image.Image:
    output = image.convert("RGBA")
    alpha = output.getchannel("A")
    for y in range(output.height):
        for x in range(output.width):
            if alpha.getpixel((x, y)) < 32:
                r, g, b, _ = output.getpixel((x, y))
                output.putpixel((x, y), (r, g, b, 0))
    if output.getchannel("A").getbbox() is None:
        raise ValueError("generated obstacle has no visible alpha")
    return output


def process(name: str, directory: str, size: tuple[int, int], margin: int) -> dict[str, object]:
    source_path = ROOT / directory / "raw" / f"{name}_raw.png"
    source = remove_fringe(Image.open(source_path))
    bbox = source.getchannel("A").getbbox()
    assert bbox is not None
    subject = source.crop(bbox)
    target_width, target_height = size
    usable_width = max(1, target_width - margin * 2)
    usable_height = max(1, target_height - margin * 2)
    scale = min(usable_width / subject.width, usable_height / subject.height)
    scaled = subject.resize(
        (max(1, round(subject.width * scale)), max(1, round(subject.height * scale))),
        Image.Resampling.NEAREST,
    )
    base = Image.new("RGBA", size, (0, 0, 0, 0))
    left = (target_width - scaled.width) // 2
    top = target_height - margin - scaled.height
    base.alpha_composite(scaled, (left, top))
    processed_dir = ROOT / directory / "processed"
    qc_dir = ROOT / directory / "qc"
    processed_dir.mkdir(parents=True, exist_ok=True)
    qc_dir.mkdir(parents=True, exist_ok=True)
    base_path = processed_dir / f"{name}.png"
    runtime_path = RUNTIME_ROOT / f"{name}.png"
    base.save(base_path, "PNG", optimize=False)
    runtime = base.resize((target_width * 4, target_height * 4), Image.Resampling.NEAREST)
    runtime.save(runtime_path, "PNG", optimize=False)
    report = {
        "raw": str(source_path),
        "raw_size": list(source.size),
        "source_alpha_bbox": list(bbox),
        "base": str(base_path),
        "base_size": list(size),
        "runtime": str(runtime_path),
        "runtime_size": [target_width * 4, target_height * 4],
        "processed_alpha_bbox": list(base.getchannel("A").getbbox() or (0, 0, 0, 0)),
        "nearest_neighbor": True,
        "margin": margin,
    }
    (qc_dir / "postprocess-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    report = {name: process(name, *spec) for name, spec in VARIANTS.items()}
    (ROOT / "qc" / "obstacle-variants-report.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )


if __name__ == "__main__":
    main()
