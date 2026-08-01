from __future__ import annotations

import colorsys
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
FOOD_ATLAS = ROOT / "assets/images/midnight_snake/midnight_food_atlas.png"
RUNTIME_DIR = ROOT / "assets/images/midnight_snake"
SOURCE_DIR = (
    ROOT / "assets/source/imagegen/midnight_snake/golden_sausage/processed"
)
MOUSE_SOURCE = (
    ROOT
    / "assets/source/imagegen/midnight_snake/mouse_walk/processed"
    / "sheet-transparent.png"
)


def _golden_pixel(pixel: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    red, green, blue, alpha = pixel
    if alpha == 0:
        return 0, 0, 0, 0

    _, saturation, value = colorsys.rgb_to_hsv(
        red / 255,
        green / 255,
        blue / 255,
    )
    if value < 0.2:
        target_hue = 34 / 360
        target_saturation = max(0.72, saturation)
        target_value = value * 0.92
    else:
        target_hue = 46 / 360
        target_saturation = max(0.74, saturation * 0.9)
        target_value = min(1.0, value * 1.14 + 0.08)

    golden_red, golden_green, golden_blue = colorsys.hsv_to_rgb(
        target_hue,
        target_saturation,
        target_value,
    )
    return (
        round(golden_red * 255),
        round(golden_green * 255),
        round(golden_blue * 255),
        alpha,
    )


def build_golden_sausage() -> Path:
    source = Image.open(FOOD_ATLAS).convert("RGBA")
    frames = [
        source.crop((0, row * 32, 32, (row + 1) * 32))
        for row in range(2)
    ]
    recolored_frames: list[Image.Image] = []
    for frame in frames:
        recolored = Image.new("RGBA", frame.size)
        recolored.putdata(
            [_golden_pixel(pixel) for pixel in frame.get_flattened_data()]
        )

        opaque = [
            (index, pixel)
            for index, pixel in enumerate(recolored.get_flattened_data())
            if pixel[3] >= 240
        ]
        brightest = sorted(
            opaque,
            key=lambda item: sum(item[1][:3]),
            reverse=True,
        )[:8]
        pixels = list(recolored.get_flattened_data())
        for index, (_, _, _, alpha) in brightest:
            pixels[index] = (255, 249, 196, alpha)
        recolored.putdata(pixels)
        recolored_frames.append(recolored)

    sheet = Image.new("RGBA", (32, 64))
    for row, frame in enumerate(recolored_frames):
        sheet.alpha_composite(frame, (0, row * 32))

    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    runtime_path = RUNTIME_DIR / "golden_sausage_sheet.png"
    sheet.save(runtime_path)
    sheet.save(SOURCE_DIR / "sheet-transparent.png")

    preview = sheet.resize((256, 512), Image.Resampling.NEAREST)
    preview.save(SOURCE_DIR / "preview-8x.png")
    return runtime_path


def install_mouse_atlas() -> Path:
    mouse = Image.open(MOUSE_SOURCE).convert("RGBA")
    if mouse.size != (64, 128):
        raise ValueError(f"unexpected mouse atlas size: {mouse.size}")
    runtime_path = RUNTIME_DIR / "mouse_walk_atlas.png"
    mouse.save(runtime_path)
    return runtime_path


def main() -> None:
    golden_path = build_golden_sausage()
    mouse_path = install_mouse_atlas()
    metadata = {
        "golden_sausage": {
            "source": str(FOOD_ATLAS.relative_to(ROOT)),
            "runtime": str(golden_path.relative_to(ROOT)),
            "sheet": {"rows": 2, "columns": 1, "cell": [32, 32]},
            "method": "deterministic HSV palette adaptation with ivory highlights",
        },
        "mouse": {
            "source": str(MOUSE_SOURCE.relative_to(ROOT)),
            "runtime": str(mouse_path.relative_to(ROOT)),
            "sheet": {
                "rows": 4,
                "columns": 2,
                "cell": [32, 32],
                "row_order": ["down", "left", "right", "up"],
            },
            "method": "built-in image generation and chroma-key sprite processing",
        },
    }
    metadata_path = (
        ROOT
        / "assets/source/imagegen/midnight_snake/bonus-assets-runtime.json"
    )
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(golden_path)
    print(mouse_path)


if __name__ == "__main__":
    main()
