"""Prepare the approved V2 dachshund atlases for 28px runtime cells."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
RUNTIME = ROOT / "assets/images/sausage_dachshund"
QC = Path(__file__).resolve().parent / "qc"

SHEETS = {
    "dog_head_walk_atlas_v2.png": "dog_head_walk_atlas_v3.png",
    "dog_head_eat_atlas_v2.png": "dog_head_eat_atlas_v3.png",
    "dog_body_atlas_v2.png": "dog_body_atlas_v3.png",
    "dog_tail_walk_atlas_v2.png": "dog_tail_walk_atlas_v3.png",
}


def _is_chroma_fringe(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, alpha = pixel
    if alpha == 0:
        return False
    if alpha <= 8 and (red != 0 or green != 0 or blue != 0):
        return True
    magenta = (
        red >= 8
        and blue >= 8
        and red > green * 1.35
        and blue > green * 1.20
        and red + blue - green * 2 > 12
    )
    green_key = alpha < 96 and green > 60 and green > red * 1.25 and green > blue * 1.15
    blue_key = alpha < 96 and blue > 60 and blue > red * 1.25 and blue > green * 1.25
    return magenta or green_key or blue_key


def _nearest_clean_color(
    image: Image.Image,
    x: int,
    y: int,
    *,
    max_radius: int = 5,
) -> tuple[int, int, int]:
    width, height = image.size
    for radius in range(1, max_radius + 1):
        candidates: list[tuple[int, int, int, int]] = []
        for yy in range(max(0, y - radius), min(height, y + radius + 1)):
            for xx in range(max(0, x - radius), min(width, x + radius + 1)):
                if max(abs(xx - x), abs(yy - y)) != radius:
                    continue
                pixel = image.getpixel((xx, yy))
                if pixel[3] > 96 and not _is_chroma_fringe(pixel):
                    candidates.append(pixel)
        if candidates:
            candidates.sort(key=lambda value: value[3], reverse=True)
            selected = candidates[: min(5, len(candidates))]
            return tuple(
                round(sum(pixel[channel] for pixel in selected) / len(selected))
                for channel in range(3)
            )
    return (28, 29, 27)


def clean_sheet(source: Path, output: Path) -> dict[str, object]:
    image = Image.open(source).convert("RGBA")
    original = image.copy()
    pixels = image.load()
    cleaned = 0
    contrast_adjusted = 0

    for y in range(image.height):
        for x in range(image.width):
            pixel = original.getpixel((x, y))
            if not _is_chroma_fringe(pixel):
                continue
            if pixel[3] <= 8:
                red, green, blue = (0, 0, 0)
            else:
                red, green, blue = _nearest_clean_color(original, x, y)
            pixels[x, y] = (red, green, blue, pixel[3])
            cleaned += 1

    # The approved charcoal coat was authored against a white preview. Lift
    # only its neutral midtones so it stays black-and-tan but remains legible
    # on the dark teal gameplay floor. Preserve the near-black outline and the
    # saturated tan markings.
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            darkest = min(red, green, blue)
            lightest = max(red, green, blue)
            if alpha <= 64 or lightest < 30 or lightest > 115:
                continue
            if lightest - darkest > 34:
                continue
            pixels[x, y] = (
                min(255, round(red * 1.20 + 8)),
                min(255, round(green * 1.20 + 8)),
                min(255, round(blue * 1.18 + 8)),
                alpha,
            )
            contrast_adjusted += 1

    for _ in range(3):
        snapshot = image.copy()
        pass_cleaned = 0
        for y in range(image.height):
            for x in range(image.width):
                pixel = snapshot.getpixel((x, y))
                if not _is_chroma_fringe(pixel):
                    continue
                if pixel[3] <= 8:
                    red, green, blue = (0, 0, 0)
                else:
                    red, green, blue = _nearest_clean_color(snapshot, x, y)
                pixels[x, y] = (red, green, blue, pixel[3])
                pass_cleaned += 1
        cleaned += pass_cleaned
        if pass_cleaned == 0:
            break

    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, optimize=True)
    remaining = sum(
        1 for pixel in image.getdata() if _is_chroma_fringe(pixel)
    )
    return {
        "source": str(source.relative_to(ROOT)),
        "output": str(output.relative_to(ROOT)),
        "size": list(image.size),
        "frame_size": [96, 96],
        "display_size": [28, 28],
        "cleaned_chroma_pixels": cleaned,
        "contrast_adjusted_pixels": contrast_adjusted,
        "remaining_chroma_pixels": remaining,
    }


def main() -> None:
    results = [
        clean_sheet(RUNTIME / source, RUNTIME / output)
        for source, output in SHEETS.items()
    ]
    QC.mkdir(parents=True, exist_ok=True)
    (QC / "character-runtime-v3.json").write_text(
        json.dumps(
            {
                "identity": "approved V2 dachshund",
                "runtime_frame_size": [96, 96],
                "display_cell_size": [28, 28],
                "runtime_filter": "medium",
                "frame_order": ["down", "left", "right", "up"],
                "walk_frames_per_direction": 4,
                "eat_frames_per_direction": 4,
                "body_module_order": [
                    "left-right",
                    "up-down",
                    "left-down",
                    "up-right",
                    "right-down",
                    "left-up",
                ],
                "sheets": results,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
