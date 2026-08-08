#!/usr/bin/env python3
"""Assemble approved ramen-timer sources into deterministic runtime PNGs."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets/source/imagegen/ramen_timer"
V2_SOURCE = SOURCE / "ui_refresh_v2"
RUNTIME = ROOT / "assets/images/ramen_timer"


def load_rgba(path: Path, expected_size: tuple[int, int] | None = None) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    if expected_size is not None and image.size != expected_size:
        raise ValueError(f"{path} is {image.size}, expected {expected_size}")
    return image


def finish_pixel_frame(image: Image.Image) -> Image.Image:
    """Remove key-color residue and keep runtime pixel edges fully crisp."""
    output = image.convert("RGBA")
    pixels = output.load()
    for y in range(output.height):
        for x in range(output.width):
            red, green, blue, alpha = pixels[x, y]
            magenta_distance = (
                (red - 255) ** 2 + green**2 + (blue - 255) ** 2
            ) ** 0.5
            if alpha < 96 or magenta_distance < 150:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (red, green, blue, 255)
    return output


def assemble_grid(
    frame_paths: list[Path],
    *,
    columns: int,
    rows: int,
    cell_size: int,
    output: Path,
) -> None:
    if len(frame_paths) != columns * rows:
        raise ValueError(f"{output.name} needs {columns * rows} frames")
    sheet = Image.new(
        "RGBA",
        (columns * cell_size, rows * cell_size),
        (0, 0, 0, 0),
    )
    for index, frame_path in enumerate(frame_paths):
        frame = finish_pixel_frame(
            load_rgba(frame_path, (cell_size, cell_size))
        )
        x = (index % columns) * cell_size
        y = (index // columns) * cell_size
        sheet.alpha_composite(frame, (x, y))
    sheet.save(output)


def center_crop_to_ratio(image: Image.Image, ratio: float) -> Image.Image:
    width, height = image.size
    current = width / height
    if current > ratio:
        cropped_width = round(height * ratio)
        left = (width - cropped_width) // 2
        return image.crop((left, 0, left + cropped_width, height))
    if current < ratio:
        cropped_height = round(width / ratio)
        top = (height - cropped_height) // 2
        return image.crop((0, top, width, top + cropped_height))
    return image


def build_background() -> None:
    raw = Image.open(SOURCE / "office_background/raw.png").convert("RGB")
    cropped = center_crop_to_ratio(raw, 180 / 400)
    runtime = cropped.resize((180, 400), Image.Resampling.NEAREST)
    runtime = ImageEnhance.Brightness(runtime).enhance(1.15)
    runtime = ImageEnhance.Contrast(runtime).enhance(1.06)
    runtime = ImageEnhance.Color(runtime).enhance(1.08)
    runtime.save(RUNTIME / "office_background.png")


def build_counter() -> None:
    cleaned = load_rgba(SOURCE / "counter_front/processed/raw_transparent.png")
    bbox = cleaned.getbbox()
    if bbox is None:
        raise ValueError("counter_front contains no visible pixels")
    subject = cleaned.crop(bbox)
    subject = center_crop_to_ratio(subject, 180 / 72)
    runtime = subject.resize((180, 72), Image.Resampling.NEAREST)
    runtime = ImageEnhance.Brightness(runtime).enhance(1.08)
    runtime = ImageEnhance.Contrast(runtime).enhance(1.12)
    runtime = ImageEnhance.Color(runtime).enhance(1.05)
    finish_pixel_frame(runtime).save(RUNTIME / "counter_front.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)

    assemble_grid(
        [
            V2_SOURCE / f"raccoon_idle/processed/idle-{index}.png"
            for index in range(1, 5)
        ],
        columns=4,
        rows=1,
        cell_size=48,
        output=RUNTIME / "raccoon_idle_sheet.png",
    )

    pose_names = [
        "watch_clock",
        "steam_startle",
        "add_scallions",
        "add_egg",
        "open_lid",
        "perfect",
        "too_early",
        "too_late",
    ]
    assemble_grid(
        [
            SOURCE
            / f"ui_refresh_v2/raccoon_poses/{name}/processed/{name}-1.png"
            for name in pose_names
        ],
        columns=4,
        rows=2,
        cell_size=48,
        output=RUNTIME / "raccoon_pose_atlas.png",
    )

    assemble_grid(
        [
            SOURCE / f"ramen_cup/processed/cup-{index}.png"
            for index in range(1, 5)
        ],
        columns=4,
        rows=1,
        cell_size=32,
        output=RUNTIME / "ramen_cup_atlas.png",
    )

    load_rgba(
        SOURCE / "ramen_fx/processed/sheet-transparent.png",
        (96, 64),
    ).save(RUNTIME / "ramen_fx_atlas.png")
    result_names = ["perfect", "too_early", "too_late"]
    assemble_grid(
        [
            V2_SOURCE / f"ramen_result/{name}/processed/{name}-1.png"
            for name in result_names
        ],
        columns=3,
        rows=1,
        cell_size=64,
        output=RUNTIME / "ramen_result_atlas.png",
    )

    build_background()
    build_counter()

    manifest = {
        "version": 2,
        "source_contract": "assets/source/imagegen/ramen_timer/ui_refresh_v2",
        "runtime_root": "assets/images/ramen_timer",
        "pixel_filter": "nearest",
        "apparent_foreground_pixel": "2x2 logical pixels",
        "assets": {
            "office_background.png": {
                "size": [180, 400],
                "display_size": [360, 800],
                "world_rect": [0, -80, 360, 800],
            },
            "counter_front.png": {
                "size": [180, 72],
                "display_size": [360, 144],
                "world_rect": [0, 432, 360, 144],
            },
            "raccoon_idle_sheet.png": {
                "size": [192, 48],
                "layout": [4, 1],
                "cell": [48, 48],
                "display_cell": [96, 96],
            },
            "raccoon_pose_atlas.png": {
                "size": [192, 96],
                "layout": [4, 2],
                "cell": [48, 48],
                "display_cell": [96, 96],
                "order": pose_names,
            },
            "ramen_cup_atlas.png": {
                "size": [128, 32],
                "layout": [4, 1],
                "cell": [32, 32],
                "order": ["closed", "scallions", "egg", "open"],
            },
            "ramen_fx_atlas.png": {
                "size": [96, 64],
                "layout": [3, 2],
                "cell": [32, 32],
                "order": [
                    "steam_a",
                    "steam_b",
                    "scallion_drop",
                    "egg_drop",
                    "sparkle",
                    "sweat",
                ],
            },
            "ramen_result_atlas.png": {
                "size": [192, 64],
                "layout": [3, 1],
                "cell": [64, 64],
                "order": result_names,
            },
        },
    }
    (SOURCE / "runtime_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
