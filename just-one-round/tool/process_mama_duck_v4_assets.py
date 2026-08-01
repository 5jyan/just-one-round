from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail/mother_duck_v4"
RUNTIME = ROOT / "assets/images/mama_duck_trail"
QC = SOURCE / "qc"

CELL = 36
ROWS = 2
COLS = 3
PALETTE_COLORS = 32
FEET_BASELINE_Y = 34


def hard_quantize(image: Image.Image, colors: int = PALETTE_COLORS) -> Image.Image:
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


def validate_sprite(image: Image.Image, name: str) -> dict[str, object]:
    if image.size != (CELL, CELL):
        raise ValueError(f"{name}: expected 36x36, got {image.size}")
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"{name}: sprite is empty")
    if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= CELL or bbox[3] >= CELL:
        raise ValueError(f"{name}: sprite touches an edge: {bbox}")
    if bbox[3] != FEET_BASELINE_Y:
        raise ValueError(
            f"{name}: expected feet baseline {FEET_BASELINE_Y}, got {bbox[3]}"
        )
    return {
        "bbox": list(bbox),
        "feet_baseline_y": bbox[3],
        "sha256": hashlib.sha256(image.tobytes()).hexdigest(),
    }


def validate_walk(sheet: Image.Image) -> list[dict[str, object]]:
    if sheet.size != (COLS * CELL, ROWS * CELL):
        raise ValueError(f"walk: expected 108x72, got {sheet.size}")

    records: list[dict[str, object]] = []
    hashes: set[str] = set()
    for index in range(ROWS * COLS):
        sprite = frame(sheet, index)
        record = validate_sprite(sprite, f"walk frame {index + 1}")
        digest = str(record["sha256"])
        if digest in hashes:
            raise ValueError(f"walk frame {index + 1} duplicates an earlier frame")
        hashes.add(digest)
        record["index"] = index + 1
        records.append(record)
    return records


def build_runtime_qc(
    idle: Image.Image,
    walk: Image.Image,
    hug: Image.Image,
) -> None:
    canvas = Image.new("RGBA", (900, 500), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 14), "MAMA DUCK V4 - RUNTIME QC", fill=(236, 240, 229))

    for index in range(6):
        sprite = frame(walk, index).resize((108, 108), Image.Resampling.NEAREST)
        x = 18 + (index % 3) * 118
        y = 44 + (index // 3) * 132
        canvas.alpha_composite(sprite, (x, y))
        draw.text((x + 34, y + 110), f"WALK {index + 1}", fill=(236, 240, 229))

    idle_large = idle.resize((144, 144), Image.Resampling.NEAREST)
    hug_large = hug.resize((144, 144), Image.Resampling.NEAREST)
    canvas.alpha_composite(idle_large, (404, 54))
    canvas.alpha_composite(hug_large, (590, 54))
    draw.text((454, 204), "IDLE", fill=(236, 240, 229))
    draw.text((640, 204), "HUG", fill=(236, 240, 229))

    baby = Image.open(RUNTIME / "duckling_cheer_sheet.png").convert("RGBA")
    baby = frame(baby, 2).resize((144, 144), Image.Resampling.NEAREST)
    canvas.alpha_composite(hug_large, (496, 278))
    canvas.alpha_composite(baby, (496, 278))
    draw.text((486, 432), "RUNTIME HUG OVERLAY", fill=(236, 240, 229))
    canvas.save(QC / "mother_duck_v4_runtime_qc.png")

    walk_frames = [frame(walk, index) for index in range(ROWS * COLS)]
    walk_frames[0].save(
        QC / "mother_duck_v4_walk.gif",
        save_all=True,
        append_images=walk_frames[1:],
        duration=110,
        loop=0,
        disposal=2,
    )


def build_pixel_scale_comparison(idle: Image.Image) -> None:
    canvas = Image.new("RGBA", (420, 190), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    baby = Image.open(RUNTIME / "duckling_idle.png").convert("RGBA")
    calibration_sheet = Image.open(
        ROOT / "assets/images/dung_dodge_v2/player_run_sheet.png"
    ).convert("RGBA")
    calibration = calibration_sheet.crop((0, 0, 32, 32))

    entries = [
        ("CALIBRATION 64PX", calibration, 64, 30),
        ("BABY 72PX", baby, 72, 166),
        ("MOTHER 72PX", idle, 72, 302),
    ]
    for label, image, size, x in entries:
        canvas.alpha_composite(
            image.resize((size, size), Image.Resampling.NEAREST),
            (x, 52),
        )
        draw.text((x - 6, 136), label, fill=(236, 240, 229))
    draw.text((18, 16), "ACTUAL RUNTIME PIXEL-SCALE COMPARISON", fill=(236, 240, 229))
    canvas.save(QC / "mother_duck_v4_pixel_scale_comparison.png")


def load_guide_builder():
    path = (
        ROOT
        / "assets/source/imagegen/mama_duck_trail/qc/build_guide_composites.py"
    )
    spec = importlib.util.spec_from_file_location("mama_duck_guide_builder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rebuild_mother_composites() -> None:
    guide = load_guide_builder()
    destination = guide.ROUTE[-1][:2]

    observe, observe_prints = guide.base_scene()
    guide.place_prints(observe, observe_prints, 0, len(guide.ROUTE))
    observe.alpha_composite(
        guide.character("mother_duck_idle.png", 72),
        guide.cell_sprite_position(*destination, 72),
    )
    observe.save(RUNTIME / "guide_observe.png")

    recall, recall_prints = guide.base_scene()
    guide.place_prints(recall, recall_prints, 1, 4)
    recall.alpha_composite(
        guide.character("mother_duck_idle.png", 72),
        guide.cell_sprite_position(*destination, 72),
    )
    recall.save(RUNTIME / "guide_recall.png")

    hero, hero_prints = guide.base_scene()
    guide.place_prints(hero, hero_prints, 1, 4)
    hero.alpha_composite(
        guide.character("mother_duck_idle.png", 72),
        guide.cell_sprite_position(*destination, 72),
    )
    hero.save(RUNTIME / "home_gameplay_hero.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)

    idle = Image.open(SOURCE / "master/mother_idle_master.png").convert("RGBA")
    walk = hard_quantize(
        Image.open(SOURCE / "walk/processed/sheet-transparent.png")
    )
    hug = hard_quantize(Image.open(SOURCE / "hug/processed/single-1.png"))

    idle_record = validate_sprite(idle, "idle")
    walk_records = validate_walk(walk)
    hug_record = validate_sprite(hug, "hug")

    idle.save(RUNTIME / "mother_duck_idle.png")
    walk.save(RUNTIME / "mother_duck_walk_sheet.png")
    hug.save(RUNTIME / "mother_duck_hug.png")

    rebuild_mother_composites()
    build_runtime_qc(idle, walk, hug)
    build_pixel_scale_comparison(idle)

    metadata = {
        "identity": "mama-duck-v4-headscarf",
        "approved_master": "master/mother_idle_master.png",
        "raw_master": "master/raw-master-chroma.png",
        "canonical_art_pixel": "2 logical pixels",
        "source_cell": [36, 36],
        "display_size": [72, 72],
        "scale": 2,
        "anchor": "feet",
        "feet_baseline_y": FEET_BASELINE_Y,
        "palette_colors_walk_and_hug": PALETTE_COLORS,
        "runtime": {
            "mother_duck_idle.png": {
                "size": [36, 36],
                "source": "approved master",
                **idle_record,
            },
            "mother_duck_walk_sheet.png": {
                "size": [108, 72],
                "layout": [2, 3],
                "frame_seconds": 0.11,
                "frames": walk_records,
            },
            "mother_duck_hug.png": {
                "size": [36, 36],
                "composition": "mother only; baby overlays at runtime",
                **hug_record,
            },
        },
        "derived_composites": [
            "guide_observe.png",
            "guide_recall.png",
            "home_gameplay_hero.png",
        ],
        "unchanged_composites": ["guide_failure.png"],
        "processor_qc": {
            "walk": "walk/processed/pipeline-meta.json",
            "hug": "hug/processed/pipeline-meta.json",
            "scale_profile": "character-scale-profile.json",
            "review_sheet": "qc/mother_duck_v4_runtime_qc.png",
            "walk_preview": "qc/mother_duck_v4_walk.gif",
        },
    }
    (SOURCE / "asset-contract-v4.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
