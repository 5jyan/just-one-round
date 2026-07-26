from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
ALPHA_INPUT = ROOT / "processed" / "player-game-over-alpha-v2.png"
RUNTIME_OUTPUT = (
    ROOT.parents[3] / "images" / "dung_dodge_v2" / "player_game_over.png"
)
PREVIEW_OUTPUT = ROOT / "qc" / "player-game-over-8x.png"
META_OUTPUT = ROOT / "qc" / "runtime-qc.json"

CANVAS_SIZE = 64
SUBJECT_MAX = 60
BOTTOM_MARGIN = 2
ALPHA_THRESHOLD = 128

PALETTE = (
    (42, 25, 56),
    (60, 45, 72),
    (44, 105, 113),
    (70, 128, 132),
    (92, 149, 152),
    (117, 174, 175),
    (190, 125, 27),
    (240, 183, 43),
    (255, 210, 79),
    (213, 138, 99),
    (245, 197, 139),
    (255, 239, 178),
    (230, 102, 74),
)


def nearest_palette(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(
        PALETTE,
        key=lambda candidate: sum(
            (candidate[channel] - rgb[channel]) ** 2 for channel in range(3)
        ),
    )


def main() -> None:
    source = Image.open(ALPHA_INPUT).convert("RGBA")
    alpha = source.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value >= ALPHA_THRESHOLD else 0).getbbox()
    if bbox is None:
        raise RuntimeError("Generated source contains no opaque subject.")

    cropped = source.crop(bbox)
    scale = min(SUBJECT_MAX / cropped.width, SUBJECT_MAX / cropped.height)
    runtime_size = (
        max(1, round(cropped.width * scale)),
        max(1, round(cropped.height * scale)),
    )
    reduced = cropped.resize(runtime_size, Image.Resampling.LANCZOS)

    cleaned = Image.new("RGBA", runtime_size, (0, 0, 0, 0))
    source_pixels = reduced.load()
    target_pixels = cleaned.load()
    for y in range(runtime_size[1]):
        for x in range(runtime_size[0]):
            red, green, blue, alpha_value = source_pixels[x, y]
            if alpha_value < ALPHA_THRESHOLD:
                continue
            palette_rgb = nearest_palette((red, green, blue))
            target_pixels[x, y] = (*palette_rgb, 255)

    canvas = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    offset_x = (CANVAS_SIZE - runtime_size[0]) // 2
    offset_y = CANVAS_SIZE - BOTTOM_MARGIN - runtime_size[1]
    canvas.alpha_composite(cleaned, (offset_x, offset_y))

    RUNTIME_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(RUNTIME_OUTPUT)
    canvas.resize(
        (CANVAS_SIZE * 8, CANVAS_SIZE * 8),
        Image.Resampling.NEAREST,
    ).save(PREVIEW_OUTPUT)

    output_alpha = canvas.getchannel("A")
    output_bbox = output_alpha.getbbox()
    opaque_pixels = sum(1 for value in output_alpha.getdata() if value == 255)
    metadata = {
        "input": str(ALPHA_INPUT.relative_to(ROOT.parents[3])),
        "runtime_output": str(RUNTIME_OUTPUT.relative_to(ROOT.parents[3])),
        "canvas": [CANVAS_SIZE, CANVAS_SIZE],
        "subject_bounds": list(output_bbox) if output_bbox else None,
        "display_size": [128, 128],
        "display_scale": 2,
        "filter": "nearest-neighbor",
        "palette": [list(color) for color in PALETTE],
        "opaque_pixels": opaque_pixels,
        "transparent_corners": all(
            canvas.getpixel(position)[3] == 0
            for position in (
                (0, 0),
                (CANVAS_SIZE - 1, 0),
                (0, CANVAS_SIZE - 1),
                (CANVAS_SIZE - 1, CANVAS_SIZE - 1),
            )
        ),
        "edge_touches": {
            "left": bool(output_bbox and output_bbox[0] == 0),
            "top": bool(output_bbox and output_bbox[1] == 0),
            "right": bool(output_bbox and output_bbox[2] == CANVAS_SIZE),
            "bottom": bool(output_bbox and output_bbox[3] == CANVAS_SIZE),
        },
    }
    META_OUTPUT.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
