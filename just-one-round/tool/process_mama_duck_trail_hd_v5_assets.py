from __future__ import annotations

import hashlib
import importlib.util
import json
from collections.abc import Iterable
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail"
HD_SOURCE = SOURCE / "hd_v5"
RUNTIME = ROOT / "assets/images/mama_duck_trail"
QC = HD_SOURCE / "qc"

DUCK_CELL = 72
WOLF_CELL = 96
TILE_CELL = 36
ROWS = 2
COLS = 3
DUCK_BASELINE = 68
WOLF_BASELINE = 92
TILE_BORDER = (54, 43, 30, 255)


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


def frame(
    sheet: Image.Image,
    index: int,
    *,
    cell: int,
    columns: int = COLS,
) -> Image.Image:
    row, column = divmod(index, columns)
    return sheet.crop(
        (
            column * cell,
            row * cell,
            (column + 1) * cell,
            (row + 1) * cell,
        )
    )


def align_baseline(sprite: Image.Image, baseline: int) -> Image.Image:
    rgba = sprite.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("empty sprite")
    shift = baseline - bbox[3]
    shifted = Image.new("RGBA", rgba.size)
    shifted.alpha_composite(rgba, (0, shift))
    shifted_bbox = shifted.getchannel("A").getbbox()
    if shifted_bbox is None or shifted_bbox[3] != baseline:
        raise ValueError(f"could not align baseline to {baseline}: {shifted_bbox}")
    return shifted


def align_sheet(sheet: Image.Image, *, cell: int, baseline: int) -> Image.Image:
    output = Image.new("RGBA", sheet.size)
    for index in range(ROWS * COLS):
        sprite = align_baseline(frame(sheet, index, cell=cell), baseline)
        row, column = divmod(index, COLS)
        output.alpha_composite(sprite, (column * cell, row * cell))
    return output


def validate_frames(
    sheet: Image.Image,
    *,
    name: str,
    cell: int,
    baseline: int,
) -> list[dict[str, object]]:
    expected = (cell * COLS, cell * ROWS)
    if sheet.size != expected:
        raise ValueError(f"{name}: expected {expected}, got {sheet.size}")

    hashes: set[str] = set()
    records: list[dict[str, object]] = []
    for index in range(ROWS * COLS):
        sprite = frame(sheet, index, cell=cell)
        bbox = sprite.getchannel("A").getbbox()
        if bbox is None:
            raise ValueError(f"{name} frame {index + 1} is empty")
        if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= cell or bbox[3] >= cell:
            raise ValueError(f"{name} frame {index + 1} touches an edge: {bbox}")
        if bbox[3] != baseline:
            raise ValueError(
                f"{name} frame {index + 1} baseline {bbox[3]} != {baseline}"
            )
        digest = hashlib.sha256(sprite.tobytes()).hexdigest()
        if digest in hashes:
            raise ValueError(f"{name} frame {index + 1} is duplicated")
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


def validate_single(
    sprite: Image.Image,
    *,
    name: str,
    cell: int,
    baseline: int,
) -> dict[str, object]:
    if sprite.size != (cell, cell):
        raise ValueError(f"{name}: expected {(cell, cell)}, got {sprite.size}")
    bbox = sprite.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"{name} is empty")
    if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= cell or bbox[3] >= cell:
        raise ValueError(f"{name} touches an edge: {bbox}")
    if bbox[3] != baseline:
        raise ValueError(f"{name} baseline {bbox[3]} != {baseline}")
    return {
        "bbox": list(bbox),
        "feet_baseline_y": bbox[3],
        "sha256": hashlib.sha256(sprite.tobytes()).hexdigest(),
    }


def load_processed(relative: str) -> Image.Image:
    return Image.open(HD_SOURCE / relative).convert("RGBA")


def build_life_face(idle: Image.Image) -> Image.Image:
    head = idle.crop((14, 7, 58, 48)).resize(
        (19, 18),
        Image.Resampling.NEAREST,
    )
    face = Image.new("RGBA", (20, 20))
    face.alpha_composite(head, ((20 - head.width) // 2, 1))
    return hard_quantize_alpha(face, 24)


def build_ducks() -> tuple[dict[str, object], dict[str, Image.Image]]:
    duck_idle = hard_quantize_alpha(
        align_baseline(
            load_processed("duckling/master/processed/sheet-transparent.png"),
            DUCK_BASELINE,
        ),
        48,
    )
    duck_walk = hard_quantize_alpha(
        align_sheet(
            load_processed("duckling/walk/processed/sheet-transparent.png"),
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        48,
    )
    duck_cheer = hard_quantize_alpha(
        align_sheet(
            load_processed("duckling/cheer/processed/sheet-transparent.png"),
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        48,
    )
    life_face = build_life_face(duck_idle)

    mother_idle = hard_quantize_alpha(
        align_baseline(
            load_processed("mother/master/processed/sheet-transparent.png"),
            DUCK_BASELINE,
        ),
        64,
    )
    mother_walk = hard_quantize_alpha(
        align_sheet(
            load_processed("mother/walk/processed/sheet-transparent.png"),
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        64,
    )
    mother_hug = hard_quantize_alpha(
        align_baseline(
            load_processed("mother/hug/processed/sheet-transparent.png"),
            DUCK_BASELINE,
        ),
        64,
    )

    records = {
        "duckling_idle.png": validate_single(
            duck_idle,
            name="duckling idle",
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        "duckling_walk_sheet.png": validate_frames(
            duck_walk,
            name="duckling walk",
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        "duckling_cheer_sheet.png": validate_frames(
            duck_cheer,
            name="duckling cheer",
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        "mother_duck_idle.png": validate_single(
            mother_idle,
            name="mother idle",
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        "mother_duck_walk_sheet.png": validate_frames(
            mother_walk,
            name="mother walk",
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
        "mother_duck_hug.png": validate_single(
            mother_hug,
            name="mother hug",
            cell=DUCK_CELL,
            baseline=DUCK_BASELINE,
        ),
    }
    images = {
        "duckling_idle.png": duck_idle,
        "duckling_walk_sheet.png": duck_walk,
        "duckling_cheer_sheet.png": duck_cheer,
        "duckling_life_face.png": life_face,
        "mother_duck_idle.png": mother_idle,
        "mother_duck_walk_sheet.png": mother_walk,
        "mother_duck_hug.png": mother_hug,
    }
    return records, images


def build_wolf() -> tuple[dict[str, object], dict[str, Image.Image]]:
    def tune(image: Image.Image) -> Image.Image:
        bright = ImageEnhance.Brightness(image).enhance(1.08)
        return ImageEnhance.Contrast(bright).enhance(1.04)

    idle = hard_quantize_alpha(
        align_baseline(
            tune(load_processed("wolf/master/processed/sheet-transparent.png")),
            WOLF_BASELINE,
        ),
        48,
    )
    failure = hard_quantize_alpha(
        align_sheet(
            tune(load_processed("wolf/failure/processed/sheet-transparent.png")),
            cell=WOLF_CELL,
            baseline=WOLF_BASELINE,
        ),
        48,
    )
    records = {
        "wolf_idle.png": validate_single(
            idle,
            name="wolf idle",
            cell=WOLF_CELL,
            baseline=WOLF_BASELINE,
        ),
        "wolf_failure_sheet.png": validate_frames(
            failure,
            name="wolf failure",
            cell=WOLF_CELL,
            baseline=WOLF_BASELINE,
        ),
    }
    return records, {
        "wolf_idle.png": idle,
        "wolf_failure_sheet.png": failure,
    }


def add_tile_borders(atlas: Image.Image) -> Image.Image:
    rgba = atlas.convert("RGBA")
    if rgba.size != (TILE_CELL * 3, TILE_CELL * 3):
        raise ValueError(f"unexpected tile atlas size: {rgba.size}")
    output = rgba.copy()
    draw = ImageDraw.Draw(output)
    for row in range(3):
        for column in range(3):
            left = column * TILE_CELL
            top = row * TILE_CELL
            right = left + TILE_CELL - 1
            bottom = top + TILE_CELL - 1
            draw.rectangle((left, top, right, bottom), outline=TILE_BORDER, width=1)
    return output


def tile_records(atlas: Image.Image) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for index in range(9):
        tile = frame(atlas, index, cell=TILE_CELL)
        pixels = tile.load()
        border_ok = all(
            pixels[x, 0] == TILE_BORDER and pixels[x, TILE_CELL - 1] == TILE_BORDER
            for x in range(TILE_CELL)
        ) and all(
            pixels[0, y] == TILE_BORDER and pixels[TILE_CELL - 1, y] == TILE_BORDER
            for y in range(TILE_CELL)
        )
        if not border_ok:
            raise ValueError(f"tile {index} border is incomplete")
        records.append(
            {
                "index": index,
                "sha256": hashlib.sha256(tile.tobytes()).hexdigest(),
                "one_pixel_inner_border": True,
            }
        )
    return records


def load_guide_builder():
    path = SOURCE / "qc/build_guide_composites.py"
    spec = importlib.util.spec_from_file_location("mama_duck_guide_builder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_runtime_qc(
    old_assets: dict[str, Image.Image],
    new_assets: dict[str, Image.Image],
) -> None:
    QC.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (900, 440), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 14), "MAMA DUCK TRAIL HD V5 - ACTUAL SIZE QC", fill="white")

    columns = [
        ("BABY", "duckling_idle.png", 72),
        ("MOTHER", "mother_duck_idle.png", 72),
        ("WOLF", "wolf_idle.png", 96),
    ]
    for column, (label, name, size) in enumerate(columns):
        x = 24 + column * 288
        old = old_assets[name].resize((size, size), Image.Resampling.NEAREST)
        new = new_assets[name]
        canvas.alpha_composite(old, (x, 68))
        canvas.alpha_composite(new, (x + 122, 68))
        draw.text((x, 46), f"{label}  OLD / HD", fill="white")
        draw.text((x, 172), "runtime size", fill=(236, 240, 229))

    tile_atlas = new_assets["marsh_tiles_atlas.png"]
    board = Image.new("RGBA", (360, 144))
    for index in range(10):
        tile_index = (index * 5 + index // 3) % 9
        tile = frame(tile_atlas, tile_index, cell=TILE_CELL).resize(
            (72, 72),
            Image.Resampling.NEAREST,
        )
        board.alpha_composite(tile, ((index % 5) * 72, (index // 5) * 72))
    canvas.alpha_composite(board, (24, 242))
    draw.text((24, 398), "APPROVED 4-LOGICAL-PIXEL CELL SEPARATION", fill="white")

    for index in range(3):
        wolf = frame(
            new_assets["wolf_failure_sheet.png"],
            index + 2,
            cell=WOLF_CELL,
        )
        canvas.alpha_composite(wolf, (484 + index * 126, 256))
    draw.text((484, 362), "HD WOLF FAILURE FRAMES", fill="white")
    canvas.save(QC / "runtime_quality_comparison.png")

    failure_frames = [
        frame(new_assets["wolf_failure_sheet.png"], index, cell=WOLF_CELL)
        for index in range(6)
    ]
    failure_frames[0].save(
        QC / "wolf_failure_hd_v5.gif",
        save_all=True,
        append_images=failure_frames[1:],
        duration=167,
        loop=0,
        disposal=2,
    )

    for family, name, duration in [
        ("duckling", "duckling_walk_sheet.png", 90),
        ("mother", "mother_duck_walk_sheet.png", 110),
    ]:
        frames = [
            frame(new_assets[name], index, cell=DUCK_CELL) for index in range(6)
        ]
        frames[0].save(
            QC / f"{family}_walk_hd_v5.gif",
            save_all=True,
            append_images=frames[1:],
            duration=duration,
            loop=0,
            disposal=2,
        )


def dimensions(images: Iterable[tuple[str, Image.Image]]) -> dict[str, list[int]]:
    return {name: [image.width, image.height] for name, image in images}


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)

    old_assets = {
        "duckling_idle.png": Image.open(
            SOURCE / "duckling_v4/master/processed/idle-1.png"
        ).convert("RGBA"),
        "mother_duck_idle.png": Image.open(
            SOURCE / "mother_duck_v4/master/mother_idle_master.png"
        ).convert("RGBA"),
        "wolf_idle.png": Image.open(
            SOURCE / "wolf_v4/master/wolf_idle_master.png"
        ).convert("RGBA"),
    }

    duck_records, duck_assets = build_ducks()
    wolf_records, wolf_assets = build_wolf()
    bordered_tiles = add_tile_borders(
        Image.open(RUNTIME / "marsh_tiles_atlas.png").convert("RGBA")
    )
    tile_meta = tile_records(bordered_tiles)

    new_assets = {
        **duck_assets,
        **wolf_assets,
        "marsh_tiles_atlas.png": bordered_tiles,
    }
    for name, image in new_assets.items():
        image.save(RUNTIME / name)

    guide = load_guide_builder()
    guide.build_guides()
    build_runtime_qc(old_assets, new_assets)

    contract = {
        "status": "integrated",
        "version": "hd-v5",
        "approved_exception": {
            "source_cells_are_native_runtime_size": True,
            "reason": "preserve detail from the approved high-resolution masters",
            "effective_cluster_rule": (
                "mostly 2 logical pixels; isolated 1px face and fur accents"
            ),
        },
        "preserved_behavior": {
            "controls": True,
            "rules": True,
            "scoring": True,
            "lives": True,
            "collision": True,
            "render_sizes": True,
            "animation_timing": True,
        },
        "runtime_dimensions": dimensions(new_assets.items()),
        "cells": {
            "duck": [DUCK_CELL, DUCK_CELL],
            "wolf": [WOLF_CELL, WOLF_CELL],
            "tile": [TILE_CELL, TILE_CELL],
        },
        "display_sizes": {
            "duck": [72, 72],
            "wolf": [96, 96],
            "tile": [72, 72],
        },
        "palette_limits": {"duckling": 48, "mother": 64, "wolf": 48},
        "baselines": {"duck": DUCK_BASELINE, "wolf": WOLF_BASELINE},
        "tile_separation": {
            "source_border_each_side": 1,
            "combined_display_width": 4,
            "color": list(TILE_BORDER),
            "opaque": True,
        },
        "frame_records": {**duck_records, **wolf_records},
        "tile_records": tile_meta,
        "processor_sources": {
            "duckling": "duckling_v4",
            "mother": "mother_duck_v4",
            "wolf": "wolf_v4",
        },
        "processor_qc": {
            "duckling_walk": "duckling/walk/processed/pipeline-meta.json",
            "duckling_cheer": "duckling/cheer/processed/pipeline-meta.json",
            "mother_walk": "mother/walk/processed/pipeline-meta.json",
            "mother_hug": "mother/hug/processed/pipeline-meta.json",
            "wolf_failure": "wolf/failure/processed/pipeline-meta.json",
            "runtime_review": "qc/runtime_quality_comparison.png",
            "runtime_capture": "qc/runtime_actual_360x640.png",
        },
        "recomposed": [
            "guide_observe.png",
            "guide_recall.png",
            "guide_failure.png",
            "home_gameplay_hero.png",
        ],
    }
    (HD_SOURCE / "asset-contract-hd-v5.json").write_text(
        json.dumps(contract, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
