from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail/duckling_v4"
RUNTIME = ROOT / "assets/images/mama_duck_trail"
QC = SOURCE / "qc"

CELL = 36
ROWS = 2
COLS = 3


def hard_quantize(image: Image.Image, colors: int = 24) -> Image.Image:
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


def frame(sheet: Image.Image, index: int) -> Image.Image:
    row, column = divmod(index, COLS)
    return sheet.crop(
        (
            column * CELL,
            row * CELL,
            (column + 1) * CELL,
            (row + 1) * CELL,
        )
    )


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("empty sprite frame")
    return bbox


def validate_sheet(sheet: Image.Image, name: str) -> list[dict[str, object]]:
    if sheet.size != (COLS * CELL, ROWS * CELL):
        raise ValueError(f"{name}: expected 108x72, got {sheet.size}")

    hashes: set[str] = set()
    records: list[dict[str, object]] = []
    for index in range(ROWS * COLS):
        sprite = frame(sheet, index)
        bbox = alpha_bbox(sprite)
        if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= CELL or bbox[3] >= CELL:
            raise ValueError(f"{name} frame {index + 1} touches a cell edge: {bbox}")
        digest = hashlib.sha256(sprite.tobytes()).hexdigest()
        if digest in hashes:
            raise ValueError(f"{name} frame {index + 1} duplicates an earlier frame")
        hashes.add(digest)
        records.append(
            {
                "index": index + 1,
                "bbox": list(bbox),
                "feet_baseline_y": bbox[3],
                "sha256": digest,
            }
        )
    return records


def build_life_face(idle: Image.Image) -> Image.Image:
    # The gameplay sprite is 36px, but the HUD slot is 20px. Preserve the
    # expressive head and shrink only this derived UI representation.
    head = idle.crop((7, 4, 29, 24)).resize(
        (19, 17),
        Image.Resampling.NEAREST,
    )
    face = Image.new("RGBA", (20, 20))
    face.alpha_composite(head, ((20 - head.width) // 2, 1))
    return hard_quantize(face, 20)


def build_qc_sheet(
    walk: Image.Image,
    cheer: Image.Image,
    idle: Image.Image,
    life: Image.Image,
) -> None:
    canvas = Image.new("RGBA", (720, 360), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 14), "MAMA DUCKLING V4 - RUNTIME QC", fill=(236, 240, 229))

    for index in range(6):
        sprite = frame(walk, index).resize((108, 108), Image.Resampling.NEAREST)
        x = 12 + (index % 3) * 118
        y = 36 + (index // 3) * 118
        canvas.alpha_composite(sprite, (x, y))

    for index in range(6):
        sprite = frame(cheer, index).resize((72, 72), Image.Resampling.NEAREST)
        x = 388 + (index % 3) * 96
        y = 42 + (index // 3) * 92
        canvas.alpha_composite(sprite, (x, y))

    canvas.alpha_composite(
        idle.resize((72, 72), Image.Resampling.NEAREST),
        (422, 250),
    )
    canvas.alpha_composite(
        life.resize((80, 80), Image.Resampling.NEAREST),
        (550, 246),
    )
    draw.text((422, 330), "IDLE", fill=(236, 240, 229))
    draw.text((550, 330), "LIFE FACE", fill=(236, 240, 229))
    canvas.save(QC / "duckling_v4_runtime_qc.png")


def build_pixel_scale_comparison(idle: Image.Image) -> None:
    canvas = Image.new("RGBA", (360, 180), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    old_sheet = Image.open(
        ROOT
        / "assets/source/imagegen/mama_duck_trail/duckling_walk_v3/"
        "processed/sheet-transparent.png"
    ).convert("RGBA")
    old_idle = frame(old_sheet, 0)
    dung_sheet = Image.open(
        ROOT / "assets/images/dung_dodge_v2/player_run_sheet.png"
    ).convert("RGBA")
    dung_frame = dung_sheet.crop((0, 0, 32, 32))

    entries = [
        ("OLD DUCK 72PX", old_idle, 72, 24),
        ("NEW DUCK 72PX", idle, 72, 144),
        ("CALIBRATION 64PX", dung_frame, 64, 268),
    ]
    for label, image, size, x in entries:
        canvas.alpha_composite(
            image.resize((size, size), Image.Resampling.NEAREST),
            (x, 48),
        )
        draw.text((x, 132), label, fill=(236, 240, 229))
    draw.text((16, 14), "ACTUAL RUNTIME PIXEL-SCALE COMPARISON", fill=(236, 240, 229))
    canvas.save(QC / "duckling_v4_pixel_scale_comparison.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)

    walk = hard_quantize(
        Image.open(SOURCE / "walk/processed/sheet-transparent.png"),
    )
    cheer = hard_quantize(
        Image.open(SOURCE / "cheer/processed/sheet-transparent.png"),
    )
    walk_records = validate_sheet(walk, "walk")
    cheer_records = validate_sheet(cheer, "cheer")

    idle = frame(walk, 0)
    life = build_life_face(idle)

    walk.save(RUNTIME / "duckling_walk_sheet.png")
    cheer.save(RUNTIME / "duckling_cheer_sheet.png")
    idle.save(RUNTIME / "duckling_idle.png")
    life.save(RUNTIME / "duckling_life_face.png")

    build_qc_sheet(walk, cheer, idle, life)
    build_pixel_scale_comparison(idle)

    metadata = {
        "identity": "mama-duckling-v4",
        "master": "master/raw/master-chroma.png",
        "reference": "user-provided duckling pixel-art board",
        "canonical_art_pixel": "2 logical pixels",
        "source_cell": [36, 36],
        "display_size": [72, 72],
        "scale": 2,
        "anchor": "feet",
        "palette_colors": 24,
        "runtime": {
            "duckling_walk_sheet.png": {
                "size": [108, 72],
                "layout": [2, 3],
                "frame_seconds": 0.09,
                "frames": walk_records,
            },
            "duckling_cheer_sheet.png": {
                "size": [108, 72],
                "layout": [2, 3],
                "frame_seconds": 0.125,
                "frames": cheer_records,
            },
            "duckling_idle.png": {"size": [36, 36], "derived_from": "walk-1"},
            "duckling_life_face.png": {
                "size": [20, 20],
                "derived_from": "duckling_idle.png",
                "display_size": [40, 40],
            },
        },
        "processor_qc": {
            "walk": "walk/processed/pipeline-meta.json",
            "cheer": "cheer/processed/pipeline-meta.json",
            "cheer_anchor_y_limit": 0.06,
            "note": (
                "The generated cheer source measured 0.0542 normalized anchor "
                "standard deviation; deterministic feet alignment produces an "
                "identical runtime baseline in every frame."
            ),
        },
    }
    (SOURCE / "asset-contract-v4.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
