from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageStat


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/mama_duck_trail"
RUNTIME = ROOT / "assets/images/mama_duck_trail"
TILE_DIR = SOURCE / "ground_tile_v4/master_candidate"
WOLF_DIR = SOURCE / "wolf_v4/master_candidate"


def quantize_opaque(image: Image.Image, colors: int) -> Image.Image:
    return image.convert("RGB").quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGB")


def quantize_alpha(image: Image.Image, colors: int) -> Image.Image:
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


def edge_difference(tile: Image.Image) -> dict[str, float]:
    rgb = tile.convert("RGB")
    left = rgb.crop((0, 0, 1, rgb.height))
    right = rgb.crop((rgb.width - 1, 0, rgb.width, rgb.height))
    top = rgb.crop((0, 0, rgb.width, 1))
    bottom = rgb.crop((0, rgb.height - 1, rgb.width, rgb.height))
    horizontal = ImageStat.Stat(
        Image.fromarray(
            abs(
                __import__("numpy").asarray(left, dtype="int16")
                - __import__("numpy").asarray(right, dtype="int16")
            ).astype("uint8")
        )
    ).mean
    vertical = ImageStat.Stat(
        Image.fromarray(
            abs(
                __import__("numpy").asarray(top, dtype="int16")
                - __import__("numpy").asarray(bottom, dtype="int16")
            ).astype("uint8")
        )
    ).mean
    return {
        "left_right_mean_rgb_delta": round(sum(horizontal) / 3, 2),
        "top_bottom_mean_rgb_delta": round(sum(vertical) / 3, 2),
    }


def build_tile() -> tuple[Image.Image, dict[str, float]]:
    raw = Image.open(TILE_DIR / "raw/ground-tile-master.png").convert("RGB")
    if raw.width != raw.height:
        side = min(raw.size)
        left = (raw.width - side) // 2
        top = (raw.height - side) // 2
        raw = raw.crop((left, top, left + side, top + side))
    tile = raw.resize((36, 36), Image.Resampling.NEAREST)
    tile = quantize_opaque(tile, 18)
    tile.save(TILE_DIR / "ground_tile_candidate.png")
    return tile, edge_difference(tile)


def build_wolf() -> tuple[Image.Image, tuple[int, int, int, int]]:
    wolf = quantize_alpha(
        Image.open(WOLF_DIR / "processed/single-1.png"),
        20,
    )
    bbox = wolf.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("wolf candidate is empty")
    if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= 48 or bbox[3] >= 48:
        raise ValueError(f"wolf candidate touches an edge: {bbox}")
    wolf.save(WOLF_DIR / "wolf_idle_candidate.png")
    return wolf, bbox


def tile_frame(atlas: Image.Image, index: int, columns: int, cell: int) -> Image.Image:
    row, column = divmod(index, columns)
    return atlas.crop(
        (column * cell, row * cell, (column + 1) * cell, (row + 1) * cell)
    )


def build_qc(tile: Image.Image, wolf: Image.Image) -> None:
    qc_dir = SOURCE / "v4_master_candidates_qc"
    qc_dir.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGBA", (720, 480), (23, 45, 56, 255))
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 14), "MAMA DUCK TRAIL V4 - MASTER CANDIDATES", fill=(236, 240, 229))

    tile_large = tile.resize((72, 72), Image.Resampling.NEAREST).convert("RGBA")
    for row in range(3):
        for column in range(3):
            canvas.alpha_composite(tile_large, (20 + column * 72, 48 + row * 72))
    draw.text((20, 272), "3x3 TILE REPEAT / 72PX PER TILE", fill=(236, 240, 229))

    footprints = Image.open(RUNTIME / "footprints_atlas.png").convert("RGBA")
    footprint = tile_frame(footprints, 0, 4, 24).resize(
        (48, 48), Image.Resampling.NEAREST
    )
    footprint_tile = tile_large.copy()
    footprint_tile.alpha_composite(footprint, (12, 12))
    canvas.alpha_composite(footprint_tile.resize((144, 144), Image.Resampling.NEAREST), (270, 48))
    draw.text((270, 200), "FOOTPRINT READABILITY", fill=(236, 240, 229))

    mother = Image.open(RUNTIME / "mother_duck_idle.png").convert("RGBA")
    baby = Image.open(RUNTIME / "duckling_idle.png").convert("RGBA")
    canvas.alpha_composite(
        mother.resize((72, 72), Image.Resampling.NEAREST),
        (456, 54),
    )
    canvas.alpha_composite(
        baby.resize((72, 72), Image.Resampling.NEAREST),
        (540, 54),
    )
    canvas.alpha_composite(
        wolf.resize((96, 96), Image.Resampling.NEAREST),
        (604, 38),
    )
    draw.text((456, 144), "MOTHER 72", fill=(236, 240, 229))
    draw.text((540, 144), "BABY 72", fill=(236, 240, 229))
    draw.text((608, 144), "WOLF 96", fill=(236, 240, 229))

    old_wolf = Image.open(RUNTIME / "wolf_idle.png").convert("RGBA")
    canvas.alpha_composite(
        old_wolf.resize((96, 96), Image.Resampling.NEAREST),
        (470, 230),
    )
    canvas.alpha_composite(
        wolf.resize((96, 96), Image.Resampling.NEAREST),
        (590, 230),
    )
    draw.text((470, 334), "OLD WOLF", fill=(236, 240, 229))
    draw.text((590, 334), "NEW WOLF", fill=(236, 240, 229))

    canvas.alpha_composite(tile_large, (270, 300))
    canvas.alpha_composite(
        wolf.resize((96, 96), Image.Resampling.NEAREST),
        (258, 288),
    )
    draw.text((250, 400), "WOLF ON NEW TILE", fill=(236, 240, 229))
    canvas.save(qc_dir / "ground_tile_and_wolf_candidates.png")


def main() -> None:
    tile, seam = build_tile()
    wolf, wolf_bbox = build_wolf()
    build_qc(tile, wolf)

    contract = {
        "status": "accepted_as_v4_masters",
        "runtime_replacement": True,
        "integration_contract": "asset-contract-v4-full.json",
        "ground_tile": {
            "path": "ground_tile_v4/master_candidate/ground_tile_candidate.png",
            "source_size": [36, 36],
            "display_size": [72, 72],
            "opaque": True,
            "palette_colors": 18,
            "seam_qc": seam,
        },
        "wolf": {
            "path": "wolf_v4/master_candidate/wolf_idle_candidate.png",
            "source_size": [48, 48],
            "display_size": [96, 96],
            "alpha": True,
            "palette_colors": 20,
            "bbox": list(wolf_bbox),
            "feet_baseline_y": wolf_bbox[3],
            "reeds": 3,
        },
        "preserved_runtime": [
            "assets/images/mama_duck_trail/marsh_tiles_atlas.png",
            "assets/images/mama_duck_trail/wolf_idle.png",
            "assets/images/mama_duck_trail/wolf_failure_sheet.png",
        ],
    }
    (SOURCE / "v4-master-candidate-contract.json").write_text(
        json.dumps(contract, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
