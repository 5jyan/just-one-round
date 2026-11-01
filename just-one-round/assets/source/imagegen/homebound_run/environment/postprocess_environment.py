#!/usr/bin/env python3
"""Deterministic postprocessing for the approved homebound environment art.

Creative pixels must come from built-in Image Gen. This script only performs
crop/fit, chroma-key cleanup, nearest-neighbor scaling, and asphalt edge
conditioning so the runtime files have the locked dimensions.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


ASSETS = {
    "alley_background": ((216, 480), "opaque", 0),
    "asphalt": ((128, 128), "opaque", 0),
    "facade_school": ((128, 96), "opaque", 0),
    "facade_shops": ((128, 96), "opaque", 0),
    "facade_homes": ((128, 96), "opaque", 0),
    "facade_construction": ((128, 96), "opaque", 0),
    "obstacle_hurdle": ((128, 64), "transparent", 4),
    "obstacle_shutter": ((128, 128), "transparent", 6),
    "obstacle_stack": ((64, 96), "transparent", 4),
    "home_gate": ((128, 128), "transparent", 6),
}


def centered_crop_box(width: int, height: int, aspect: float) -> tuple[int, int, int, int]:
    current = width / height
    if current > aspect:
        new_width = max(1, round(height * aspect))
        left = (width - new_width) // 2
        return (left, 0, left + new_width, height)
    new_height = max(1, round(width / aspect))
    top = (height - new_height) // 2
    return (0, top, width, top + new_height)


def crop_to_aspect(image: Image.Image, aspect: float) -> Image.Image:
    return image.crop(centered_crop_box(image.width, image.height, aspect))


def opaque_fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_width, target_height = size
    cropped = crop_to_aspect(image.convert("RGB"), target_width / target_height)
    return cropped.resize(size, Image.Resampling.NEAREST).convert("RGB")


def is_magenta(red: int, green: int, blue: int) -> bool:
    # The raw contract requests exact #FF00FF. The small tolerance removes
    # only chroma-key fringe and leaves brick red and warm highlights intact.
    return (
        red >= 80
        and blue >= 100
        and green <= 80
        and red - green >= 50
        and blue - green >= 80
    )


def remove_chroma(image: Image.Image) -> Image.Image:
    source = image.convert("RGBA")
    pixels = source.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0 or is_magenta(red, green, blue):
                pixels[x, y] = (red, green, blue, 0)
    bbox = source.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("transparent source has no visible subject")
    # Remove isolated low-alpha chroma fringes around the subject. This is a
    # deterministic cleanup pass, not a creative repaint.
    alpha = source.getchannel("A")
    for y in range(source.height):
        for x in range(source.width):
            if alpha.getpixel((x, y)) < 32:
                source.putpixel((x, y), (*source.getpixel((x, y))[:3], 0))
    return source


def transparent_fit(image: Image.Image, size: tuple[int, int], margin: int) -> tuple[Image.Image, tuple[int, int, int, int]]:
    cleaned = remove_chroma(image)
    bbox = cleaned.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("transparent source has no visible subject")
    subject = cleaned.crop(bbox)
    target_width, target_height = size
    usable_width = max(1, target_width - margin * 2)
    usable_height = max(1, target_height - margin * 2)
    scale = min(usable_width / subject.width, usable_height / subject.height)
    scaled_size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    scaled = subject.resize(scaled_size, Image.Resampling.NEAREST)
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    left = (target_width - scaled.width) // 2
    top = target_height - margin - scaled.height
    output.alpha_composite(scaled, (left, top))
    return output, bbox


def condition_tile(image: Image.Image) -> Image.Image:
    """Make opposite tile edges agree without inventing new material."""
    # Keep the generated tile quiet at the authored 128px scale. Palette
    # reduction is deterministic cleanup of generated pixels, with no drawn
    # marks or new geometry.
    output = image.convert("RGB").quantize(
        colors=8,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")
    width, height = output.size
    for x in range(width):
        top = output.getpixel((x, 0))
        bottom = output.getpixel((x, height - 1))
        blend = tuple((a + b) // 2 for a, b in zip(top, bottom))
        output.putpixel((x, 0), blend)
        output.putpixel((x, height - 1), blend)
    for y in range(height):
        left = output.getpixel((0, y))
        right = output.getpixel((width - 1, y))
        blend = tuple((a + b) // 2 for a, b in zip(left, right))
        output.putpixel((0, y), blend)
        output.putpixel((width - 1, y), blend)
    return output


def process(root: Path, runtime_root: Path) -> dict[str, object]:
    base_root = root / "processed" / "base"
    runtime_processed_root = root / "processed" / "runtime"
    base_root.mkdir(parents=True, exist_ok=True)
    runtime_processed_root.mkdir(parents=True, exist_ok=True)
    runtime_root.mkdir(parents=True, exist_ok=True)
    report: dict[str, object] = {"schema": "homebound_run.environment_qc.v1", "assets": {}}
    for name, (size, mode, margin) in ASSETS.items():
        asset_root = root / name
        raw = asset_root / "raw.png"
        if not raw.is_file():
            raise FileNotFoundError(f"missing creative raw image: {raw}")
        source = Image.open(raw)
        crop_box: tuple[int, int, int, int] | None = None
        if mode == "opaque":
            crop_box = centered_crop_box(source.width, source.height, size[0] / size[1])
            base = opaque_fit(source, size)
            if name == "asphalt":
                base = condition_tile(base)
        else:
            base, bbox = transparent_fit(source, size, margin)
        base_path = base_root / f"{name}.png"
        runtime_processed_path = runtime_processed_root / f"{name}.png"
        runtime_path = runtime_root / "assets" / "images" / "homebound_run" / f"{name}.png"
        base.save(base_path, "PNG", optimize=False)
        runtime = base.resize((size[0] * 4, size[1] * 4), Image.Resampling.NEAREST)
        runtime.save(runtime_processed_path, "PNG", optimize=False)
        runtime.save(runtime_path, "PNG", optimize=False)
        alpha = base.getchannel("A") if base.mode == "RGBA" else None
        edge_alpha = 0
        if alpha is not None:
            edge_alpha = max(
                max(alpha.crop((0, 0, alpha.width, 1)).getdata()),
                max(alpha.crop((0, alpha.height - 1, alpha.width, alpha.height)).getdata()),
                max(alpha.crop((0, 0, 1, alpha.height)).getdata()),
                max(alpha.crop((alpha.width - 1, 0, alpha.width, alpha.height)).getdata()),
            )
            processed_bbox = alpha.getbbox()
        else:
            processed_bbox = None
        item: dict[str, object] = {
            "raw": str(raw),
            "raw_size": list(source.size),
            "base": str(base_path),
            "base_size": list(size),
            "runtime": str(runtime_path),
            "runtime_size": [size[0] * 4, size[1] * 4],
            "mode": mode,
            "edge_alpha_max": edge_alpha,
        }
        if mode == "transparent":
            item["source_alpha_bbox"] = list(bbox)
            item["processed_alpha_bbox"] = list(processed_bbox or (0, 0, 0, 0))
            if processed_bbox:
                occupied_width = processed_bbox[2] - processed_bbox[0]
                occupied_height = processed_bbox[3] - processed_bbox[1]
                item["occupied_ratio_width_to_height"] = round(occupied_width / occupied_height, 3)
        else:
            item["source_crop_box"] = list(crop_box or (0, 0, source.width, source.height))
        report["assets"][name] = item
    (root / "qc" / "postprocess-report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).parent)
    parser.add_argument("--runtime-root", type=Path, default=Path(__file__).parents[5])
    args = parser.parse_args()
    process(args.root, args.runtime_root)


if __name__ == "__main__":
    main()
