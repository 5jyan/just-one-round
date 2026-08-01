from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "assets/images/mama_duck_trail"
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail"
QC = SOURCE / "qc"


def hard_quantize(image: Image.Image, colors: int) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    rgb = rgba.convert("RGB").quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )
    result = rgb.convert("RGBA")
    result.putalpha(alpha)
    return result


def save_quantized(source: Path, destination: Path, colors: int) -> Image.Image:
    image = hard_quantize(Image.open(source), colors)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)
    return image


def frame(sheet: Image.Image, index: int, columns: int, cell: int) -> Image.Image:
    row, column = divmod(index, columns)
    return sheet.crop(
        (column * cell, row * cell, (column + 1) * cell, (row + 1) * cell)
    )


def build_tiles() -> Image.Image:
    raw = Image.open(SOURCE / "marsh_tiles_v3/raw/raw-atlas.png").convert("RGBA")
    raw_cell = raw.width // 3
    atlas = Image.new("RGBA", (108, 108))
    for index in range(9):
        row, column = divmod(index, 3)
        tile = raw.crop(
            (
                column * raw_cell + 8,
                row * raw_cell + 8,
                (column + 1) * raw_cell - 8,
                (row + 1) * raw_cell - 8,
            )
        ).resize((36, 36), Image.Resampling.NEAREST)
        tile = hard_quantize(tile, 22)
        atlas.alpha_composite(tile, (column * 36, row * 36))
    atlas.save(RUNTIME / "marsh_tiles_atlas.png")
    return atlas


def build_life_face(duckling_idle: Image.Image) -> Image.Image:
    # Crop only the expressive head; the previous icon accidentally included
    # the full body and therefore read as tiny beneath the LIVES label.
    head = duckling_idle.crop((9, 3, 27, 22)).resize(
        (19, 18), Image.Resampling.NEAREST
    )
    face = Image.new("RGBA", (20, 20))
    face.alpha_composite(head, ((20 - head.width) // 2, 1))
    face = hard_quantize(face, 18)
    face.save(RUNTIME / "duckling_life_face.png")
    return face


def build_background() -> Image.Image:
    raw = Image.open(
        SOURCE / "marsh_background_v3/raw/raw-background.png"
    ).convert("RGBA")
    source_ratio = raw.width / raw.height
    target_ratio = 180 / 320
    if source_ratio > target_ratio:
        crop_width = round(raw.height * target_ratio)
        left = (raw.width - crop_width) // 2
        raw = raw.crop((left, 0, left + crop_width, raw.height))
    elif source_ratio < target_ratio:
        crop_height = round(raw.width / target_ratio)
        top = (raw.height - crop_height) // 2
        raw = raw.crop((0, top, raw.width, top + crop_height))
    background = raw.resize((180, 320), Image.Resampling.NEAREST)
    background = hard_quantize(background, 24).convert("RGB")
    background.save(RUNTIME / "marsh_background.png")
    return background.convert("RGBA")


def build_contact_sheet(assets: dict[str, Image.Image]) -> None:
    canvas = Image.new("RGBA", (640, 360), (23, 45, 56, 255))
    tile = frame(assets["tiles"], 5, 3, 36).resize(
        (144, 144), Image.Resampling.NEAREST
    )
    canvas.alpha_composite(tile, (16, 16))

    placements = [
        ("duckling", 184, 20, 144),
        ("mother", 344, 20, 144),
        ("wolf", 500, 12, 128),
        ("cheer", 184, 190, 144),
        ("footprints", 360, 196, 96),
        ("life", 490, 210, 80),
        ("reeds", 570, 202, 72),
    ]
    for key, x, y, size in placements:
        image = assets[key].resize((size, size), Image.Resampling.NEAREST)
        canvas.alpha_composite(image, (x, y))
    canvas.save(QC / "asset_quality_v3_contact_sheet.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)

    duckling_walk = save_quantized(
        SOURCE / "duckling_walk_v3/processed/sheet-transparent.png",
        RUNTIME / "duckling_walk_sheet.png",
        24,
    )
    duckling_cheer = save_quantized(
        SOURCE / "duckling_cheer_v3/processed/sheet-transparent.png",
        RUNTIME / "duckling_cheer_sheet.png",
        24,
    )
    mother_walk = save_quantized(
        SOURCE / "mother_walk_v3/processed/sheet-transparent.png",
        RUNTIME / "mother_duck_walk_sheet.png",
        26,
    )
    mother_hug = save_quantized(
        SOURCE / "mother_hug_v3/processed/sheet-transparent.png",
        RUNTIME / "mother_duck_hug.png",
        26,
    )
    footprints = save_quantized(
        SOURCE / "footprints_v2/processed/sheet-transparent.png",
        RUNTIME / "footprints_atlas.png",
        8,
    )
    reeds_source = Image.open(
        SOURCE / "marsh_reeds_v3/processed_24/sheet-transparent.png"
    ).convert("RGBA")
    reeds_source = ImageEnhance.Brightness(reeds_source).enhance(1.45)
    reeds_source = ImageEnhance.Contrast(reeds_source).enhance(1.12)
    reeds = hard_quantize(reeds_source, 18)
    reeds.save(RUNTIME / "marsh_reeds_atlas.png")
    wolf = save_quantized(
        RUNTIME / "wolf_failure_sheet.png",
        RUNTIME / "wolf_failure_sheet.png",
        18,
    )
    save_quantized(
        RUNTIME / "wolf_idle.png",
        RUNTIME / "wolf_idle.png",
        18,
    )
    save_quantized(
        RUNTIME / "feather_poof_sheet.png",
        RUNTIME / "feather_poof_sheet.png",
        12,
    )

    duckling_idle = frame(duckling_walk, 0, 3, 36)
    duckling_idle.save(RUNTIME / "duckling_idle.png")
    mother_idle = frame(mother_walk, 0, 3, 36)
    mother_idle.save(RUNTIME / "mother_duck_idle.png")
    life = build_life_face(duckling_idle)
    tiles = build_tiles()
    background = build_background()

    build_contact_sheet(
        {
            "tiles": tiles,
            "duckling": duckling_idle,
            "mother": mother_idle,
            "wolf": frame(wolf, 2, 3, 48),
            "cheer": frame(duckling_cheer, 2, 3, 36),
            "footprints": frame(footprints, 0, 4, 24),
            "life": life,
            "reeds": frame(reeds, 0, 3, 24),
            "background": background,
        }
    )

    metadata = {
        "viewport": [360, 640],
        "canonical_art_pixel": "2 logical pixels",
        "assets": {
            "duckling_idle.png": {"cell": [36, 36], "display": [72, 72]},
            "duckling_walk_sheet.png": {
                "layout": [2, 3],
                "cell": [36, 36],
                "display": [72, 72],
            },
            "duckling_cheer_sheet.png": {
                "layout": [2, 3],
                "cell": [36, 36],
                "display": [72, 72],
                "frame_seconds": 0.125,
                "loops": 2,
            },
            "mother_duck_idle.png": {"cell": [36, 36], "display": [72, 72]},
            "mother_duck_walk_sheet.png": {
                "layout": [2, 3],
                "cell": [36, 36],
                "display": [72, 72],
            },
            "mother_duck_hug.png": {"cell": [36, 36], "display": [72, 72]},
            "marsh_tiles_atlas.png": {
                "layout": [3, 3],
                "cell": [36, 36],
                "display": [72, 72],
            },
            "footprints_atlas.png": {
                "layout": [3, 4],
                "cell": [24, 24],
                "display": [48, 48],
            },
            "duckling_life_face.png": {
                "cell": [20, 20],
                "display": [40, 40],
            },
            "marsh_reeds_atlas.png": {
                "layout": [2, 3],
                "cell": [24, 24],
                "display": [48, 48],
            },
            "marsh_background.png": {
                "cell": [180, 320],
                "display": [360, 640],
            },
        },
    }
    (SOURCE / "asset-contract-v3.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
