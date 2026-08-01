from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail"
HD_SOURCE = SOURCE / "hd_v6"
RUNTIME = ROOT / "assets/images/mama_duck_trail"
QC = HD_SOURCE / "qc"

FOOTPRINT_CELL = 48
FOOTPRINT_ROWS = 3
FOOTPRINT_COLUMNS = 4
BACKGROUND_SIZE = (180, 420)
BACKGROUND_WORLD_RECT = (0, -100, 360, 740)


def hard_quantize_alpha(image: Image.Image, colors: int) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    rgb = rgba.convert("RGB").quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGBA")
    rgb.putalpha(alpha)
    pixels = rgb.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            if pixels[x, y][3] == 0:
                pixels[x, y] = (0, 0, 0, 0)
    return rgb


def frame(sheet: Image.Image, index: int) -> Image.Image:
    row, column = divmod(index, FOOTPRINT_COLUMNS)
    return sheet.crop(
        (
            column * FOOTPRINT_CELL,
            row * FOOTPRINT_CELL,
            (column + 1) * FOOTPRINT_CELL,
            (row + 1) * FOOTPRINT_CELL,
        )
    )


def build_footprints() -> tuple[Image.Image, list[dict[str, object]]]:
    source = Image.open(
        HD_SOURCE / "footprints/processed/sheet-transparent.png"
    ).convert("RGBA")
    expected = (
        FOOTPRINT_CELL * FOOTPRINT_COLUMNS,
        FOOTPRINT_CELL * FOOTPRINT_ROWS,
    )
    if source.size != expected:
        raise ValueError(f"footprints expected {expected}, got {source.size}")
    atlas = hard_quantize_alpha(source, 32)

    records: list[dict[str, object]] = []
    hashes: set[str] = set()
    for index in range(FOOTPRINT_ROWS * FOOTPRINT_COLUMNS):
        sprite = frame(atlas, index)
        bbox = sprite.getchannel("A").getbbox()
        if bbox is None:
            raise ValueError(f"footprint {index + 1} is empty")
        if (
            bbox[0] <= 0
            or bbox[1] <= 0
            or bbox[2] >= FOOTPRINT_CELL
            or bbox[3] >= FOOTPRINT_CELL
        ):
            raise ValueError(f"footprint {index + 1} touches an edge: {bbox}")
        digest = hashlib.sha256(sprite.tobytes()).hexdigest()
        if digest in hashes:
            raise ValueError(f"footprint {index + 1} duplicates another frame")
        hashes.add(digest)
        records.append(
            {
                "index": index + 1,
                "row_role": ("preview", "entered", "wrong")[index // 4],
                "direction": ("up", "right", "down", "left")[index % 4],
                "bbox": list(bbox),
                "sha256": digest,
            }
        )
    return atlas, records


def build_life_face() -> Image.Image:
    duckling = Image.open(RUNTIME / "duckling_idle.png").convert("RGBA")
    if duckling.size != (72, 72):
        raise ValueError(f"unexpected duckling idle size: {duckling.size}")
    head = duckling.crop((14, 7, 58, 48)).resize(
        (23, 22),
        Image.Resampling.NEAREST,
    )
    face = Image.new("RGBA", (24, 24))
    face.alpha_composite(head, ((24 - head.width) // 2, 1))
    face = hard_quantize_alpha(face, 32)
    bbox = face.getchannel("A").getbbox()
    if bbox is None or bbox[0] < 0 or bbox[1] < 0:
        raise ValueError(f"invalid life face: {bbox}")
    return face


def build_background() -> tuple[Image.Image, dict[str, object]]:
    raw = Image.open(
        SOURCE / "marsh_background_v3/raw/raw-background.png"
    ).convert("RGBA")
    target_ratio = BACKGROUND_SIZE[0] / BACKGROUND_SIZE[1]
    crop_width = round(raw.height * target_ratio)
    if crop_width > raw.width:
        raise ValueError(f"background raw is too narrow: {raw.size}")
    left = (raw.width - crop_width) // 2
    crop_box = (left, 0, left + crop_width, raw.height)
    cropped = raw.crop(crop_box)
    background = cropped.resize(BACKGROUND_SIZE, Image.Resampling.NEAREST)
    background = hard_quantize_alpha(background, 24).convert("RGB")
    return background, {
        "raw_size": [raw.width, raw.height],
        "crop_box": list(crop_box),
        "runtime_size": list(BACKGROUND_SIZE),
        "world_rect": list(BACKGROUND_WORLD_RECT),
        "source_to_world_scale": 2,
    }


def build_qc(
    footprints: Image.Image,
    life_face: Image.Image,
    background: Image.Image,
) -> None:
    QC.mkdir(parents=True, exist_ok=True)
    tall = background.resize((360, 840), Image.Resampling.NEAREST).convert("RGBA")
    canonical = tall.crop((0, 100, 360, 740))

    canvas = Image.new("RGBA", (920, 660), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 14), "MAMA DUCK TRAIL HD V6 - LAYOUT QC", fill="white")
    canvas.alpha_composite(canonical, (18, 42))
    draw.text((18, 632), "CANONICAL 360x640 CROP", fill="white")

    tall_preview = tall.resize((270, 630), Image.Resampling.NEAREST)
    canvas.alpha_composite(tall_preview, (394, 22))
    draw.text((394, 632), "AUTHORED 360x840", fill="white")

    for index in range(12):
        sprite = frame(footprints, index)
        x = 686 + (index % 4) * 54
        y = 54 + (index // 4) * 64
        canvas.alpha_composite(sprite, (x, y))
    draw.text((686, 252), "48PX FOOTPRINTS", fill="white")
    canvas.alpha_composite(
        life_face.resize((96, 96), Image.Resampling.NEAREST),
        (734, 300),
    )
    draw.text((726, 404), "24PX LIFE FACE", fill="white")
    canvas.save(QC / "layout_asset_comparison.png")

    wolf_sheet = Image.open(RUNTIME / "wolf_failure_sheet.png").convert("RGBA")
    wolf_frames = []
    for index in range(6):
        row, column = divmod(index, 3)
        wolf_frames.append(
            wolf_sheet.crop(
                (
                    column * 96,
                    row * 96,
                    (column + 1) * 96,
                    (row + 1) * 96,
                )
            )
        )
    wolf_frames[0].save(
        QC / "wolf_mouth_open_timeline.gif",
        save_all=True,
        append_images=wolf_frames[1:],
        duration=[100, 100, 240, 160, 200, 200],
        loop=0,
        disposal=2,
    )


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)

    footprints, footprint_records = build_footprints()
    life_face = build_life_face()
    background, background_record = build_background()

    footprints.save(RUNTIME / "footprints_atlas.png")
    life_face.save(RUNTIME / "duckling_life_face.png")
    background.save(RUNTIME / "marsh_background.png")
    build_qc(footprints, life_face, background)

    contract = {
        "status": "processed",
        "version": "hd-v6-layout",
        "viewport": {
            "gameplay_safe_core": [0, 0, 360, 640],
            "maximum_target_viewport": [0, -70, 360, 710],
            "authored_canvas": list(BACKGROUND_WORLD_RECT),
            "camera_center": [180, 320],
            "fixed_visible_width": 360,
        },
        "runtime": {
            "duckling_life_face.png": {
                "size": [24, 24],
                "display": [48, 48],
                "scale": 2,
                "source": "duckling_idle.png",
            },
            "footprints_atlas.png": {
                "size": [192, 144],
                "layout": [3, 4],
                "cell": [48, 48],
                "display": [48, 48],
                "scale": 1,
                "palette_limit": 32,
                "frames": footprint_records,
            },
            "marsh_background.png": background_record,
        },
        "removed_runtime_effect": {
            "asset": "feather_poof_sheet.png",
            "file_preserved": True,
            "loader_and_render_usage_removed": True,
        },
        "wolf_failure_timeline_seconds": {
            "closed": [0.0, 0.10],
            "opening": [0.10, 0.20],
            "wide_open_hold": [0.20, 0.44],
            "swallow": [0.44, 0.60],
            "chew": [0.60, 0.80],
            "satisfied": [0.80, 1.0],
        },
        "preserved_behavior": {
            "board_geometry": True,
            "input_coordinates": True,
            "collision": True,
            "rules": True,
            "score": True,
            "lives": True,
            "failure_duration_seconds": 1.0,
        },
        "processor_qc": {
            "footprints": "footprints/processed/pipeline-meta.json",
            "layout_review": "qc/layout_asset_comparison.png",
            "wolf_timeline_preview": "qc/wolf_mouth_open_timeline.gif",
            "runtime_simulator": "qc/runtime_simulator_iphone17pro.png",
        },
        "recomposed": [
            "guide_observe.png",
            "guide_recall.png",
            "guide_failure.png",
            "home_gameplay_hero.png",
        ],
    }
    (HD_SOURCE / "asset-contract-hd-v6.json").write_text(
        json.dumps(contract, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
