#!/usr/bin/env python3
"""Rebuild the hitter-view mound from the approved regulation projection.

The script adapts the accepted V3 background only: it removes the oversized
generated mound with perspective-matched grass sampled from the same image,
then reuses the accepted mound texture inside the exact projected 18-foot
circle. All final mound pixels are authored on the project's 2x2 art grid.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[5]
RUNTIME = ROOT / "assets/images/ten_pitch_slugger"
SOURCE = ROOT / "assets/source/imagegen/ten_pitch_slugger/field_v4"
INPUT = RUNTIME / "background_hitter_v3.png"
OUTPUT = RUNTIME / "background_hitter_v4.png"
PREVIEW = RUNTIME / "background_preview_v4.png"
QC = SOURCE / "qc"

ORIGIN_X = 180.0
ORIGIN_Y = 565.0
SCALE_X = 1.783
SCALE_Y = 1.489
PERSPECTIVE = 0.00487
MOUND_CENTER_INCHES = 59.0 * 12.0
MOUND_RADIUS_INCHES = 9.0 * 12.0


def project(x_inches: float, y_inches: float) -> tuple[float, float]:
    denominator = 1.0 + PERSPECTIVE * y_inches
    return (
        ORIGIN_X + SCALE_X * x_inches / denominator,
        ORIGIN_Y - SCALE_Y * y_inches / denominator,
    )


def remove_old_mound(image: Image.Image) -> Image.Image:
    clean = image.copy()
    source = image.load()
    target = clean.load()
    center_x, center_y = 179.0, 328.0
    radius_x, radius_y = 74.0, 12.0
    vanishing_y = 287.0
    sample_offset_y = 28

    for y in range(315, 342):
        normalized_y = (y - center_y) / radius_y
        if abs(normalized_y) > 1.0:
            continue
        half_width = radius_x * math.sqrt(1.0 - normalized_y * normalized_y)
        for x in range(
            max(0, math.floor(center_x - half_width)),
            min(image.width, math.ceil(center_x + half_width) + 1),
        ):
            sample_y = min(image.height - 1, y + sample_offset_y)
            perspective_ratio = (sample_y - vanishing_y) / max(
                1.0, y - vanishing_y
            )
            sample_x = round(center_x + (x - center_x) * perspective_ratio)
            sample_x = max(0, min(image.width - 1, sample_x))
            target[x, y] = source[sample_x, sample_y]
    return clean


def projected_mound_mask() -> Image.Image:
    # Author the silhouette at half resolution, then enlarge by exactly 2x.
    mask_half = Image.new("L", (180, 360), 0)
    points = []
    for step in range(180):
        angle = math.tau * step / 180.0
        x = MOUND_RADIUS_INCHES * math.cos(angle)
        y = MOUND_CENTER_INCHES + MOUND_RADIUS_INCHES * math.sin(angle)
        screen_x, screen_y = project(x, y)
        points.append((round(screen_x / 2.0), round(screen_y / 2.0)))
    ImageDraw.Draw(mask_half).polygon(points, fill=255)
    return mask_half.resize((360, 720), Image.Resampling.NEAREST)


def rebuild() -> None:
    background = Image.open(INPUT).convert("RGB")
    clean = remove_old_mound(background)
    mask = projected_mound_mask()
    bounds = mask.getbbox()
    if bounds is None:
        raise RuntimeError("Projected mound mask is empty")

    # Reuse the accepted mound material, reducing it at half resolution so its
    # smallest texture clusters remain 2x2 logical pixels at runtime.
    old_mound = background.crop((106, 316, 252, 340))
    half_size = (
        max(1, math.ceil((bounds[2] - bounds[0]) / 2)),
        max(1, math.ceil((bounds[3] - bounds[1]) / 2)),
    )
    texture_half = old_mound.resize(half_size, Image.Resampling.NEAREST)
    texture = texture_half.resize(
        (bounds[2] - bounds[0], bounds[3] - bounds[1]),
        Image.Resampling.NEAREST,
    )
    mound_layer = Image.new("RGB", background.size)
    mound_layer.paste(texture, bounds[:2])
    clean.paste(mound_layer, mask=mask)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    clean.save(OUTPUT, optimize=True)
    clean.crop((0, 105, 360, 565)).save(PREVIEW, optimize=True)

    QC.mkdir(parents=True, exist_ok=True)
    comparison = Image.new("RGB", (720, 240), (15, 24, 37))
    comparison.paste(background.crop((0, 260, 360, 500)), (0, 0))
    comparison.paste(clean.crop((0, 260, 360, 500)), (360, 0))
    comparison.save(QC / "mound-before-after.png", optimize=True)
    (QC / "processor-meta.json").write_text(
        json.dumps(
            {
                "input": str(INPUT.relative_to(ROOT)),
                "outputs": [
                    str(OUTPUT.relative_to(ROOT)),
                    str(PREVIEW.relative_to(ROOT)),
                ],
                "method": "same-image grass sampling plus projected mound texture reuse",
                "mound_mask_bounds": list(bounds),
                "art_pixel": 2,
                "preview_crop": [0, 105, 360, 460],
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    rebuild()
