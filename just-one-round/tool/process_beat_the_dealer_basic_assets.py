#!/usr/bin/env python3
"""Build the approved Beat the Dealer basic runtime asset pack."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw


PROJECT = Path(__file__).resolve().parents[1]
SOURCE = (
    PROJECT
    / "assets"
    / "source"
    / "imagegen"
    / "beat_the_dealer"
    / "basic_pack"
)
RUNTIME = PROJECT / "assets" / "images" / "beat_the_dealer"
QC = SOURCE / "qc"
CHROMA_HELPER = (
    Path.home()
    / ".codex"
    / "skills"
    / ".system"
    / "imagegen"
    / "scripts"
    / "remove_chroma_key.py"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hard_chroma(source: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "python3",
            str(CHROMA_HELPER),
            "--input",
            str(source),
            "--out",
            str(output),
            "--auto-key",
            "border",
            "--tolerance",
            "30",
            "--despill",
            "--force",
        ],
        check=True,
    )


def remove_residual_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and red > 150 and blue > 150 and green < 40:
                pixels[x, y] = (0, 0, 0, 0)
    return rgba


def fit_sprite(
    source: Image.Image,
    *,
    cell: tuple[int, int],
    bounds: tuple[int, int],
    bottom_padding: int = 1,
) -> tuple[Image.Image, dict[str, object]]:
    cleaned = remove_residual_magenta(source)
    alpha = cleaned.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise RuntimeError("No visible sprite pixels after chroma removal")
    cropped = cleaned.crop(bbox)
    cropped.thumbnail(bounds, Image.Resampling.NEAREST)
    output = Image.new("RGBA", cell, (0, 0, 0, 0))
    x = (cell[0] - cropped.width) // 2
    y = cell[1] - bottom_padding - cropped.height
    output.alpha_composite(cropped, (x, y))
    return output, {
        "source_bbox": list(bbox),
        "subject_size": [cropped.width, cropped.height],
        "cell_size": list(cell),
        "offset": [x, y],
        "anchor": "bottom-center",
    }


def save_nearest_preview(image: Image.Image, output: Path, scale: int) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    image.resize(
        (image.width * scale, image.height * scale),
        Image.Resampling.NEAREST,
    ).save(output)


def build_background() -> dict[str, object]:
    source = SOURCE / "background" / "raw" / "background-map.png"
    image = Image.open(source).convert("RGB")
    target_ratio = 3 / 7
    current_ratio = image.width / image.height
    if current_ratio > target_ratio:
        crop_width = round(image.height * target_ratio)
        left = (image.width - crop_width) // 2
        crop_box = (left, 0, left + crop_width, image.height)
    else:
        crop_height = round(image.width / target_ratio)
        top = (image.height - crop_height) // 2
        crop_box = (0, top, image.width, top + crop_height)
    cropped = image.crop(crop_box)
    runtime = cropped.resize((180, 420), Image.Resampling.NEAREST)
    output = RUNTIME / "background_map.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    runtime.save(output)
    return {
        "raw": str(source.relative_to(PROJECT)),
        "raw_sha256": sha256(source),
        "crop_box": list(crop_box),
        "runtime": str(output.relative_to(PROJECT)),
        "runtime_size": [180, 420],
        "display_size": [360, 840],
        "world_rect": [0, -100, 360, 840],
        "safe_core": [0, 0, 360, 640],
        "camera_center": [180, 320],
    }


def build_character(
    family: str,
    raw_name: str,
    output_name: str,
    *,
    cell: tuple[int, int],
    bounds: tuple[int, int],
    display: tuple[int, int],
) -> dict[str, object]:
    raw = SOURCE / family / "raw" / raw_name
    alpha = SOURCE / family / "processed" / f"{Path(raw_name).stem}-alpha.png"
    hard_chroma(raw, alpha)
    runtime, geometry = fit_sprite(
        Image.open(alpha),
        cell=cell,
        bounds=bounds,
    )
    output = RUNTIME / output_name
    runtime.save(output)
    save_nearest_preview(runtime, SOURCE / family / "qc" / f"{Path(output_name).stem}-8x.png", 8)
    return {
        "raw": str(raw.relative_to(PROJECT)),
        "raw_sha256": sha256(raw),
        "alpha_source": str(alpha.relative_to(PROJECT)),
        "runtime": str(output.relative_to(PROJECT)),
        "display_size": list(display),
        "scale": display[0] // cell[0],
        "chroma": {
            "mode": "hard",
            "auto_key": "border",
            "tolerance": 30,
            "despill": True,
            "residual_magenta_cleanup": "r>150, b>150, g<40",
        },
        **geometry,
    }


def build_props() -> dict[str, object]:
    raw = SOURCE / "props" / "raw" / "props-chroma.png"
    alpha = SOURCE / "props" / "processed" / "props-alpha.png"
    hard_chroma(raw, alpha)
    sheet = remove_residual_magenta(Image.open(alpha))
    alpha_channel = sheet.getchannel("A")
    occupied_columns = [
        x
        for x in range(sheet.width)
        if alpha_channel.crop((x, 0, x + 1, sheet.height)).getbbox()
    ]
    runs: list[tuple[int, int]] = []
    if occupied_columns:
        start = previous = occupied_columns[0]
        for x in occupied_columns[1:]:
            if x > previous + 1:
                if previous + 1 - start > 10:
                    runs.append((start, previous + 1))
                start = x
            previous = x
        if previous + 1 - start > 10:
            runs.append((start, previous + 1))
    if len(runs) != 3:
        raise RuntimeError(f"Expected 3 prop column runs, found {runs}")
    specs = [
        (
            "card_front.png",
            (runs[0][0], 0, runs[0][1], sheet.height),
            (24, 32),
            (22, 30),
            (48, 64),
        ),
        (
            "card_back.png",
            (runs[1][0], 0, runs[1][1], sheet.height),
            (24, 32),
            (22, 30),
            (48, 64),
        ),
        (
            "coin.png",
            (runs[2][0], 0, runs[2][1], sheet.height),
            (16, 16),
            (14, 14),
            (32, 32),
        ),
    ]
    outputs: dict[str, object] = {}
    for name, region, cell, bounds, display in specs:
        sprite, geometry = fit_sprite(
            sheet.crop(region),
            cell=cell,
            bounds=bounds,
        )
        output = RUNTIME / name
        sprite.save(output)
        save_nearest_preview(
            sprite,
            SOURCE / "props" / "qc" / f"{Path(name).stem}-8x.png",
            8,
        )
        outputs[name] = {
            "runtime": str(output.relative_to(PROJECT)),
            "display_size": list(display),
            "scale": display[0] // cell[0],
            "source_region": list(region),
            **geometry,
        }
    return {
        "raw": str(raw.relative_to(PROJECT)),
        "raw_sha256": sha256(raw),
        "alpha_source": str(alpha.relative_to(PROJECT)),
        "chroma": {
            "mode": "hard",
            "auto_key": "border",
            "tolerance": 30,
            "despill": True,
            "residual_magenta_cleanup": "r>150, b>150, g<40",
        },
        "outputs": outputs,
    }


def checkerboard(size: tuple[int, int], block: int = 8) -> Image.Image:
    image = Image.new("RGB", size, "#151328")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], block):
        for x in range(0, size[0], block):
            if (x // block + y // block) % 2:
                draw.rectangle((x, y, x + block - 1, y + block - 1), fill="#211c38")
    return image


def build_pixel_scale_comparison() -> None:
    canvas = checkerboard((520, 176), 8).convert("RGBA")
    items = [
        (
            "new dealer 48→96",
            RUNTIME / "dealer_idle.png",
            (96, 96),
        ),
        (
            "new chick 32→64",
            RUNTIME / "player_idle.png",
            (64, 64),
        ),
        (
            "duck 32→64",
            PROJECT / "assets" / "images" / "dung_dodge_v2" / "player_run_sheet.png",
            (64, 64),
        ),
        (
            "mite 48→48",
            PROJECT
            / "assets"
            / "images"
            / "gravity_switch_v2"
            / "player_magnet_mite_sheet_v3.png",
            (48, 48),
        ),
        (
            "apple 42→42",
            PROJECT / "assets" / "images" / "apple_game_v2" / "apple_faces_atlas.png",
            (42, 42),
        ),
    ]
    draw = ImageDraw.Draw(canvas)
    x = 12
    baseline = 128
    for label, path, display in items:
        image = Image.open(path).convert("RGBA")
        if "player_run_sheet" in str(path):
            image = image.crop((0, 0, 32, 32))
        elif "player_magnet_mite" in str(path):
            image = image.crop((0, 0, 48, 48))
        elif "apple_faces" in str(path):
            image = image.crop((0, 0, 42, 42))
        image = image.resize(display, Image.Resampling.NEAREST)
        canvas.alpha_composite(image, (x, baseline - image.height))
        draw.text((x, 142), label, fill="#f4ead3")
        x += max(display[0], 84) + 14
    canvas.save(QC / "pixel-scale-comparison.png")


def build_composite_preview() -> None:
    background = Image.open(RUNTIME / "background_map.png").convert("RGBA")
    authored = background.resize((360, 840), Image.Resampling.NEAREST)
    core = authored.crop((0, 100, 360, 740))
    dealer = Image.open(RUNTIME / "dealer_idle.png").convert("RGBA").resize(
        (96, 96), Image.Resampling.NEAREST
    )
    player = Image.open(RUNTIME / "player_idle.png").convert("RGBA").resize(
        (64, 64), Image.Resampling.NEAREST
    )
    card_front = Image.open(RUNTIME / "card_front.png").convert("RGBA").resize(
        (48, 64), Image.Resampling.NEAREST
    )
    card_back = Image.open(RUNTIME / "card_back.png").convert("RGBA").resize(
        (48, 64), Image.Resampling.NEAREST
    )
    coin = Image.open(RUNTIME / "coin.png").convert("RGBA").resize(
        (32, 32), Image.Resampling.NEAREST
    )
    core.alpha_composite(dealer, (132, 92))
    core.alpha_composite(card_front, (112, 292))
    core.alpha_composite(card_back, (200, 292))
    core.alpha_composite(coin, (24, 28))
    core.alpha_composite(player, (148, 444))
    core.save(QC / "runtime-composite-360x640.png")
    authored.alpha_composite(dealer, (132, 192))
    authored.alpha_composite(card_front, (112, 392))
    authored.alpha_composite(card_back, (200, 392))
    authored.alpha_composite(coin, (24, 128))
    authored.alpha_composite(player, (148, 544))
    authored.save(QC / "runtime-composite-360x840.png")


def validate_outputs() -> dict[str, object]:
    expected = {
        "background_map.png": ((180, 420), "RGB"),
        "dealer_idle.png": ((48, 48), "RGBA"),
        "player_idle.png": ((32, 32), "RGBA"),
        "card_front.png": ((24, 32), "RGBA"),
        "card_back.png": ((24, 32), "RGBA"),
        "coin.png": ((16, 16), "RGBA"),
    }
    report: dict[str, object] = {}
    for name, (size, mode) in expected.items():
        path = RUNTIME / name
        image = Image.open(path)
        if image.size != size:
            raise RuntimeError(f"{name}: expected {size}, got {image.size}")
        if image.mode != mode:
            raise RuntimeError(f"{name}: expected {mode}, got {image.mode}")
        entry: dict[str, object] = {
            "size": list(image.size),
            "mode": image.mode,
            "sha256": sha256(path),
        }
        if mode == "RGBA":
            alpha = image.getchannel("A")
            values = list(alpha.getdata())
            if alpha.getbbox() is None:
                raise RuntimeError(f"{name}: sprite is fully transparent")
            if alpha.getpixel((0, 0)) != 0:
                raise RuntimeError(f"{name}: top-left corner is not transparent")
            if any(0 < value < 255 for value in values):
                raise RuntimeError(f"{name}: contains partial alpha")
            entry["opaque_pixels"] = sum(value == 255 for value in values)
            entry["transparent_pixels"] = sum(value == 0 for value in values)
        report[name] = entry
    return report


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)
    metadata = {
        "game_id": "beat_the_dealer",
        "contract": {
            "safe_core": [0, 0, 360, 640],
            "maximum_viewport": [0, -100, 360, 840],
            "art_pixel": "approximately 2x2 logical pixels",
            "filter": "nearest-neighbor",
            "runtime_integration": False,
        },
        "background": build_background(),
        "dealer": build_character(
            "dealer",
            "dealer-idle-chroma-v2.png",
            "dealer_idle.png",
            cell=(48, 48),
            bounds=(44, 44),
            display=(96, 96),
        ),
        "player": build_character(
            "player",
            "player-idle-chroma.png",
            "player_idle.png",
            cell=(32, 32),
            bounds=(28, 28),
            display=(64, 64),
        ),
        "props": build_props(),
    }
    build_pixel_scale_comparison()
    build_composite_preview()
    metadata["validation"] = validate_outputs()
    metadata["qc"] = [
        str((QC / "pixel-scale-comparison.png").relative_to(PROJECT)),
        str((QC / "runtime-composite-360x640.png").relative_to(PROJECT)),
        str((QC / "runtime-composite-360x840.png").relative_to(PROJECT)),
    ]
    (SOURCE / "pipeline-meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(metadata["validation"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
