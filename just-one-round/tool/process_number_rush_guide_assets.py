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
HERO_CROP = (0, 360, 1206, 1906)
HERO_SIZE = (1206, 1546)


def build_home_preview() -> None:
    capture = Image.open(FULL_CAPTURE)
    if capture.size != SOURCE_SIZE:
        raise ValueError(f"Unexpected Number Rush capture size: {capture.size}")

    RUNTIME_OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    hero = capture.convert("RGB").crop(HERO_CROP)
    if hero.size != HERO_SIZE:
        raise ValueError(f"Unexpected Number Rush hero size: {hero.size}")
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
                    "width": HERO_SIZE[0],
                    "height": HERO_SIZE[1],
                },
                "processing": (
                    "lossless gameplay crop containing the live TIME/NEXT HUD "
                    "and complete 5x5 board; no generative edits"
                ),
                "capture_note": (
                    "Live TAP 50 board using the original procedural cabinet; "
                    "the complete 5x5 board remains mechanically plausible."
                ),
                "art_contract": {
                    "home_aspect_ratio": 0.78,
                    "content_occupancy": "edge-to-edge gameplay hero",
                    "filter_quality": "nearest-neighbor / none",
                    "safe_core": "TIME, NEXT, and the complete 5x5 board",
                    "viewport_crop": "fixed approved portrait crop",
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
