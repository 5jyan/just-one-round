from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageStat


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail"
RUNTIME = ROOT / "assets/images/mama_duck_trail"
TILE_SOURCE = SOURCE / "ground_tile_v4"
WOLF_SOURCE = SOURCE / "wolf_v4"
QC = SOURCE / "v4_full_assets_qc"

TILE_CELL = 36
WOLF_CELL = 48
ROWS = 2
COLS = 3
LEGACY_RUNTIME_HASHES = {
    "marsh_tiles_atlas.png": (
        "2f4c5ca8a5031015d302213d79149ca7c7a69f5b0cc4d2d3e58d8321780ac6dc"
    ),
    "wolf_idle.png": (
        "5e824d8adc4ef9aa9c2077cd18bfc61ac614327938a085bfc450485c25d8a67c"
    ),
    "wolf_failure_sheet.png": (
        "56fa1dcb5bef5f89d3b541675d78d1f020ec9c5926b3e440341d7f602f7bbe2d"
    ),
}


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


def average_rgb(a: tuple[int, ...], b: tuple[int, ...]) -> tuple[int, int, int]:
    return tuple(round((a[index] + b[index]) / 2) for index in range(3))


def periodic_border(tile: Image.Image, band: int = 2) -> Image.Image:
    result = tile.convert("RGB").copy()
    pixels = result.load()
    for offset in range(band):
        left = offset
        right = result.width - 1 - offset
        for y in range(result.height):
            color = average_rgb(pixels[left, y], pixels[right, y])
            pixels[left, y] = color
            pixels[right, y] = color
    for offset in range(band):
        top = offset
        bottom = result.height - 1 - offset
        for x in range(result.width):
            color = average_rgb(pixels[x, top], pixels[x, bottom])
            pixels[x, top] = color
            pixels[x, bottom] = color
    return result


def outer_band_mean(image: Image.Image, band: int = 4) -> tuple[float, float, float]:
    rgb = image.convert("RGB")
    pixels: list[tuple[int, int, int]] = []
    for y in range(rgb.height):
        for x in range(rgb.width):
            if (
                x < band
                or x >= rgb.width - band
                or y < band
                or y >= rgb.height - band
            ):
                pixels.append(rgb.getpixel((x, y)))
    strip = Image.new("RGB", (len(pixels), 1))
    strip.putdata(pixels)
    return tuple(ImageStat.Stat(strip).mean)


def match_outer_mud(image: Image.Image, reference: Image.Image) -> Image.Image:
    current = outer_band_mean(image)
    target = outer_band_mean(reference)
    channels = image.convert("RGB").split()
    adjusted = [
        channel.point(
            lambda value, offset=round(target[index] - current[index]): max(
                0, min(255, value + offset)
            )
        )
        for index, channel in enumerate(channels)
    ]
    return Image.merge("RGB", adjusted)


def blend_to_master_edges(
    image: Image.Image,
    master: Image.Image,
    fade_width: int = 7,
) -> Image.Image:
    generated = image.convert("RGB")
    base = master.convert("RGB")
    result = Image.new("RGB", generated.size)
    output = result.load()
    generated_pixels = generated.load()
    base_pixels = base.load()
    for y in range(generated.height):
        for x in range(generated.width):
            distance = min(x, y, generated.width - 1 - x, generated.height - 1 - y)
            amount = min(1.0, distance / fade_width)
            output[x, y] = tuple(
                round(
                    base_pixels[x, y][channel] * (1 - amount)
                    + generated_pixels[x, y][channel] * amount
                )
                for channel in range(3)
            )
    return result


def tile_frame(atlas: Image.Image, index: int) -> Image.Image:
    row, column = divmod(index, 3)
    return atlas.crop(
        (
            column * TILE_CELL,
            row * TILE_CELL,
            (column + 1) * TILE_CELL,
            (row + 1) * TILE_CELL,
        )
    )


def wolf_frame(sheet: Image.Image, index: int) -> Image.Image:
    row, column = divmod(index, COLS)
    return sheet.crop(
        (
            column * WOLF_CELL,
            row * WOLF_CELL,
            (column + 1) * WOLF_CELL,
            (row + 1) * WOLF_CELL,
        )
    )


def build_tile_atlas() -> tuple[Image.Image, list[dict[str, object]]]:
    master = Image.open(TILE_SOURCE / "master/ground_tile_master.png").convert("RGB")
    master = periodic_border(master, band=1)
    raw = Image.open(TILE_SOURCE / "atlas/raw/raw-atlas.png").convert("RGB")
    if raw.width % 3 != 0 or raw.height % 3 != 0:
        raise ValueError(f"tile raw atlas is not divisible by 3: {raw.size}")
    raw_cell_width = raw.width // 3
    raw_cell_height = raw.height // 3

    cells: list[Image.Image] = []
    for index in range(9):
        row, column = divmod(index, 3)
        generated = raw.crop(
            (
                column * raw_cell_width,
                row * raw_cell_height,
                (column + 1) * raw_cell_width,
                (row + 1) * raw_cell_height,
            )
        ).resize((TILE_CELL, TILE_CELL), Image.Resampling.NEAREST)
        if index == 0:
            cell = master.copy()
        else:
            cell = blend_to_master_edges(
                match_outer_mud(generated, master),
                master,
            )
        cells.append(cell)

    atlas = Image.new("RGB", (TILE_CELL * 3, TILE_CELL * 3))
    for index, cell in enumerate(cells):
        row, column = divmod(index, 3)
        atlas.paste(cell, (column * TILE_CELL, row * TILE_CELL))
    atlas = atlas.quantize(
        colors=24,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGBA")

    records: list[dict[str, object]] = []
    hashes: set[str] = set()
    for index in range(9):
        cell = tile_frame(atlas, index)
        digest = hashlib.sha256(cell.tobytes()).hexdigest()
        if digest in hashes:
            raise ValueError(f"tile {index} duplicates an earlier tile")
        hashes.add(digest)
        left = list(cell.crop((0, 0, 1, TILE_CELL)).get_flattened_data())
        right = list(
            cell.crop((TILE_CELL - 1, 0, TILE_CELL, TILE_CELL)).get_flattened_data()
        )
        top = list(cell.crop((0, 0, TILE_CELL, 1)).get_flattened_data())
        bottom = list(
            cell.crop((0, TILE_CELL - 1, TILE_CELL, TILE_CELL)).get_flattened_data()
        )
        if left != right or top != bottom:
            raise ValueError(f"tile {index} does not have an exact periodic edge")
        records.append(
            {
                "index": index,
                "sha256": digest,
                "periodic_edges": True,
            }
        )
    return atlas, records


def build_wolf_assets() -> tuple[
    Image.Image,
    Image.Image,
    dict[str, object],
    list[dict[str, object]],
]:
    idle_source = Image.open(
        WOLF_SOURCE / "master/wolf_idle_master.png"
    ).convert("RGBA")
    idle = hard_quantize_alpha(
        ImageEnhance.Contrast(
            ImageEnhance.Brightness(idle_source).enhance(1.08)
        ).enhance(1.04),
        20,
    )
    idle_bbox = idle.getchannel("A").getbbox()
    if idle.size != (WOLF_CELL, WOLF_CELL) or idle_bbox is None:
        raise ValueError(f"invalid wolf idle: {idle.size}, {idle_bbox}")

    failure = hard_quantize_alpha(
        ImageEnhance.Contrast(
            ImageEnhance.Brightness(
                Image.open(
                    WOLF_SOURCE / "failure/processed/sheet-transparent.png"
                ).convert("RGBA")
            ).enhance(1.08)
        ).enhance(1.04),
        20,
    )
    if failure.size != (WOLF_CELL * COLS, WOLF_CELL * ROWS):
        raise ValueError(f"invalid wolf failure sheet size: {failure.size}")

    hashes: set[str] = set()
    frame_records: list[dict[str, object]] = []
    for index in range(ROWS * COLS):
        frame = wolf_frame(failure, index)
        bbox = frame.getchannel("A").getbbox()
        if bbox is None:
            raise ValueError(f"wolf frame {index + 1} is empty")
        if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= WOLF_CELL or bbox[3] >= WOLF_CELL:
            raise ValueError(f"wolf frame {index + 1} touches an edge: {bbox}")
        if bbox[3] != 46:
            raise ValueError(
                f"wolf frame {index + 1} baseline is {bbox[3]}, expected 46"
            )
        digest = hashlib.sha256(frame.tobytes()).hexdigest()
        if digest in hashes:
            raise ValueError(f"wolf frame {index + 1} duplicates an earlier frame")
        hashes.add(digest)
        frame_records.append(
            {
                "index": index + 1,
                "bbox": list(bbox),
                "feet_baseline_y": bbox[3],
                "sha256": digest,
            }
        )
    idle_record = {
        "bbox": list(idle_bbox),
        "feet_baseline_y": idle_bbox[3],
        "sha256": hashlib.sha256(idle.tobytes()).hexdigest(),
    }
    return idle, failure, idle_record, frame_records


def load_guide_builder():
    path = SOURCE / "qc/build_guide_composites.py"
    spec = importlib.util.spec_from_file_location("mama_duck_guide_builder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rebuild_composites() -> None:
    guide = load_guide_builder()
    guide.build_guides()


def build_qc(tile_atlas: Image.Image, wolf_idle: Image.Image, wolf_sheet: Image.Image) -> None:
    QC.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (1200, 700), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 14), "MAMA DUCK TRAIL V4 - FULL ASSET QC", fill=(236, 240, 229))

    atlas_large = tile_atlas.resize((324, 324), Image.Resampling.NEAREST)
    canvas.alpha_composite(atlas_large, (18, 44))
    draw.text((18, 374), "3x3 TILE ATLAS / 108PX REVIEW CELLS", fill=(236, 240, 229))

    board = Image.new("RGBA", (360, 504))
    layout = [
        0, 1, 2, 3, 4,
        4, 3, 1, 0, 2,
        2, 5, 6, 7, 1,
        3, 7, 5, 6, 0,
        1, 0, 4, 2, 3,
        4, 6, 5, 7, 2,
        0, 3, 1, 4, 8,
    ]
    for index, tile_index in enumerate(layout):
        row, column = divmod(index, 5)
        tile = tile_frame(tile_atlas, tile_index).resize(
            (72, 72), Image.Resampling.NEAREST
        )
        board.alpha_composite(tile, (column * 72, row * 72))
    canvas.alpha_composite(board, (366, 44))
    draw.text((366, 556), "5x7 MIXED RUNTIME BOARD", fill=(236, 240, 229))

    footprints = Image.open(RUNTIME / "footprints_atlas.png").convert("RGBA")
    footprint = footprints.crop((0, 0, 24, 24)).resize(
        (48, 48), Image.Resampling.NEAREST
    )
    footprint_preview = tile_frame(tile_atlas, 4).resize(
        (144, 144), Image.Resampling.NEAREST
    )
    footprint_preview.alpha_composite(
        footprint.resize((96, 96), Image.Resampling.NEAREST),
        (24, 24),
    )
    canvas.alpha_composite(footprint_preview, (18, 430))
    draw.text((18, 582), "FOOTPRINT READABILITY", fill=(236, 240, 229))

    for index in range(6):
        sprite = wolf_frame(wolf_sheet, index).resize(
            (96, 96), Image.Resampling.NEAREST
        )
        x = 762 + (index % 2) * 126
        y = 44 + (index // 2) * 126
        canvas.alpha_composite(sprite, (x, y))
        draw.text((x + 22, y + 100), f"WOLF {index + 1}", fill=(236, 240, 229))

    mother = Image.open(RUNTIME / "mother_duck_idle.png").convert("RGBA")
    baby = Image.open(RUNTIME / "duckling_idle.png").convert("RGBA")
    canvas.alpha_composite(
        mother.resize((72, 72), Image.Resampling.NEAREST),
        (762, 458),
    )
    canvas.alpha_composite(
        baby.resize((72, 72), Image.Resampling.NEAREST),
        (842, 458),
    )
    canvas.alpha_composite(
        wolf_idle.resize((96, 96), Image.Resampling.NEAREST),
        (918, 442),
    )
    draw.text((762, 548), "MOTHER 72", fill=(236, 240, 229))
    draw.text((842, 548), "BABY 72", fill=(236, 240, 229))
    draw.text((924, 548), "WOLF 96", fill=(236, 240, 229))
    canvas.save(QC / "ground_tiles_and_wolf_runtime_qc.png")

    frames = [wolf_frame(wolf_sheet, index) for index in range(6)]
    frames[0].save(
        QC / "wolf_failure_v4.gif",
        save_all=True,
        append_images=frames[1:],
        duration=167,
        loop=0,
        disposal=2,
    )


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    old_hashes = LEGACY_RUNTIME_HASHES

    tile_atlas, tile_records = build_tile_atlas()
    wolf_idle, wolf_sheet, wolf_idle_record, wolf_records = build_wolf_assets()
    tile_atlas.save(RUNTIME / "marsh_tiles_atlas.png")
    wolf_idle.save(RUNTIME / "wolf_idle.png")
    wolf_sheet.save(RUNTIME / "wolf_failure_sheet.png")

    rebuild_composites()
    build_qc(tile_atlas, wolf_idle, wolf_sheet)

    contract = {
        "status": "integrated",
        "preserved_behavior": {
            "rules": True,
            "scoring": True,
            "lives": True,
            "controls": True,
            "failure_duration_seconds": 1.0,
            "tile_selection": "indices 0-4 mud, 5-7 puddles",
        },
        "art_contract": {
            "canonical_art_pixel": "2 logical pixels",
            "viewport": [360, 640],
            "filtering": "nearest-neighbor",
            "wolf_runtime_palette_adjustment": {
                "brightness": 1.08,
                "contrast": 1.04,
                "reason": "separate the gray-brown silhouette from warm mud",
            },
        },
        "runtime": {
            "marsh_tiles_atlas.png": {
                "size": [108, 108],
                "layout": [3, 3],
                "cell": [36, 36],
                "display": [72, 72],
                "palette_colors": 24,
                "tiles": tile_records,
            },
            "wolf_idle.png": {
                "size": [48, 48],
                "display": [96, 96],
                **wolf_idle_record,
            },
            "wolf_failure_sheet.png": {
                "size": [144, 96],
                "layout": [2, 3],
                "cell": [48, 48],
                "display": [96, 96],
                "total_duration_seconds": 1.0,
                "frames": wolf_records,
            },
        },
        "old_runtime_hashes": old_hashes,
        "sources": {
            "tile_master": "ground_tile_v4/master/ground_tile_master.png",
            "tile_master_prompt": "ground_tile_v4/master_candidate/prompt-used.txt",
            "tile_atlas_prompt": "ground_tile_v4/atlas/prompt-used.txt",
            "tile_atlas_raw": "ground_tile_v4/atlas/raw/raw-atlas.png",
            "wolf_master": "wolf_v4/master/wolf_idle_master.png",
            "wolf_master_prompt": "wolf_v4/master_candidate/prompt-used.txt",
            "wolf_failure_prompt": "wolf_v4/failure/prompt-used.txt",
            "wolf_failure_raw": "wolf_v4/failure/raw/raw-sheet.png",
            "wolf_processor": "wolf_v4/failure/processed/pipeline-meta.json",
        },
        "recomposed": [
            "guide_observe.png",
            "guide_recall.png",
            "guide_failure.png",
            "home_gameplay_hero.png",
        ],
    }
    (SOURCE / "asset-contract-v4-full.json").write_text(
        json.dumps(contract, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
