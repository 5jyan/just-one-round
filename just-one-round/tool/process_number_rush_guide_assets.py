#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
CAPTURE_DIR = ROOT / "assets/source/runtime_capture/number_rush"
FULL_CAPTURE = CAPTURE_DIR / "home_gameplay_full.png"
RUNTIME_OUTPUT = ROOT / "assets/images/number_rush/home_gameplay_hero.png"
META_OUTPUT = CAPTURE_DIR / "pipeline-meta.json"

SOURCE_SIZE = (1206, 2622)
HERO_CROP = (0, 240, 1206, 1906)
HERO_SIZE = (1206, 1546)
CAPTURE_CLOSE_REPAIR_SIZE = (190, 120)
HERO_BACKGROUND = (2, 7, 21)


def build_home_preview() -> None:
    capture = Image.open(FULL_CAPTURE)
    if capture.size != SOURCE_SIZE:
        raise ValueError(f"Unexpected Number Rush capture size: {capture.size}")

    RUNTIME_OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    capture = capture.convert("RGB")
    hero_crop = capture.crop(HERO_CROP)
    repair_width, repair_height = CAPTURE_CLOSE_REPAIR_SIZE
    clean_corner = capture.crop(
        (
            SOURCE_SIZE[0] - repair_width,
            HERO_CROP[1],
            SOURCE_SIZE[0],
            HERO_CROP[1] + repair_height,
        )
    ).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    hero_crop.paste(clean_corner, (0, 0))

    scale = min(
        HERO_SIZE[0] / hero_crop.width,
        HERO_SIZE[1] / hero_crop.height,
    )
    scaled_size = (
        round(hero_crop.width * scale),
        round(hero_crop.height * scale),
    )
    scaled = hero_crop.resize(scaled_size, Image.Resampling.NEAREST)
    hero = Image.new("RGB", HERO_SIZE, HERO_BACKGROUND)
    hero.paste(scaled, ((HERO_SIZE[0] - scaled.width) // 2, 0))
    hero.save(RUNTIME_OUTPUT, optimize=True)

    META_OUTPUT.write_text(
        json.dumps(
            {
                "captured_at": "2026-07-26",
                "source": "iPhone iOS Simulator runtime capture",
                "source_file": str(FULL_CAPTURE.relative_to(CAPTURE_DIR)),
                "runtime_output": str(RUNTIME_OUTPUT.relative_to(ROOT)),
                "source_dimensions": list(SOURCE_SIZE),
                "crop": {
                    "x": HERO_CROP[0],
                    "y": HERO_CROP[1],
                    "width": HERO_CROP[2] - HERO_CROP[0],
                    "height": HERO_CROP[3] - HERO_CROP[1],
                },
                "processing": (
                    "runtime gameplay crop containing the live TIME/NEXT HUD "
                    "and complete 5x5 board, uniformly scaled into the fixed "
                    "home card so the upper and lower cabinet edges remain "
                    "visible; the captured close-control overlap is restored "
                    "from the cabinet's symmetric clean corner"
                ),
                "capture_note": (
                    "Live TAP 50 board using the original procedural cabinet; "
                    "the complete 5x5 board remains mechanically plausible."
                ),
                "art_contract": {
                    "home_aspect_ratio": 0.78,
                    "content_occupancy": (
                        "uniformly scaled gameplay hero with narrow side insets"
                    ),
                    "filter_quality": "nearest-neighbor / none",
                    "safe_core": "TIME, NEXT, and the complete 5x5 board",
                    "viewport_crop": (
                        "fixed portrait crop with complete cabinet screen edges"
                    ),
                },
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    build_home_preview()
