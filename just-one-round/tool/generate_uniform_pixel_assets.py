#!/usr/bin/env python3
"""Generate the game's palette-locked, one-cell pixel-art source assets."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "images"

GREEN = (48, 169, 79, 255)
GREEN_LIGHT = (103, 200, 76, 255)
GREEN_DARK = (33, 133, 66, 255)
YELLOW = (239, 226, 55, 255)
EYE = (76, 61, 39, 255)
WHITE = (255, 255, 255, 255)


def _dinosaur(frame: int) -> Image.Image:
    image = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    # A deliberately borderless silhouette. Every coordinate is one source cell.
    silhouette = [
        (3, 1, 6, 1), (2, 2, 8, 2), (1, 3, 9, 5), (0, 4, 9, 6),
        (4, 6, 10, 8), (6, 8, 11, 11), (7, 10, 13, 13),
        (8, 12, 16, 15), (8, 14, 20, 18), (10, 17, 19, 19),
        (18, 15, 21, 17), (20, 13, 22, 16), (22, 10, 23, 15),
    ]
    for x0, y0, x1, y1 in silhouette:
        draw.rectangle((x0, y0, x1, y1), fill=GREEN)

    # Legs and the two-frame walking change are also exactly one-cell edits.
    if frame == 1:
        draw.rectangle((10, 18, 12, 21), fill=GREEN_DARK)
        draw.rectangle((9, 21, 12, 22), fill=GREEN_DARK)
        draw.rectangle((16, 18, 18, 22), fill=GREEN_DARK)
        draw.rectangle((16, 22, 19, 22), fill=GREEN_DARK)
    else:
        draw.rectangle((10, 18, 12, 22), fill=GREEN_DARK)
        draw.rectangle((10, 22, 13, 22), fill=GREEN_DARK)
        draw.rectangle((16, 18, 18, 21), fill=GREEN_DARK)
        draw.rectangle((15, 21, 18, 22), fill=GREEN_DARK)

    # Highlights and belly are internal colors, never an exterior contour.
    draw.rectangle((3, 2, 6, 2), fill=GREEN_LIGHT)
    draw.rectangle((1, 3, 5, 3), fill=GREEN_LIGHT)
    draw.rectangle((7, 5, 8, 12), fill=GREEN_LIGHT)
    draw.rectangle((9, 11, 12, 14), fill=GREEN_LIGHT)
    draw.rectangle((12, 13, 16, 16), fill=GREEN_LIGHT)
    draw.rectangle((17, 15, 20, 16), fill=GREEN_LIGHT)
    draw.rectangle((21, 13, 22, 14), fill=GREEN_LIGHT)
    draw.rectangle((7, 9, 7, 13), fill=YELLOW)
    draw.rectangle((8, 13, 9, 16), fill=YELLOW)
    draw.rectangle((9, 16, 11, 17), fill=YELLOW)

    # Interior facial details are warm dark brown instead of black.
    draw.point((6, 3), fill=WHITE)
    draw.point((7, 3), fill=EYE)
    draw.rectangle((1, 5, 3, 5), fill=GREEN_DARK)
    draw.rectangle((5, 8, 6, 8), fill=GREEN_DARK)
    return image


def _cloud(width: int, height: int, small: bool = False) -> Image.Image:
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    tint = (198, 247, 251, 255)
    if small:
        draw.rectangle((0, 12, width - 1, height - 1), fill=WHITE)
        draw.polygon(
            [(3, 12), (3, 10), (6, 10), (6, 7), (10, 7), (10, 5),
             (15, 5), (15, 7), (18, 7), (18, 10), (21, 10), (21, 12)],
            fill=WHITE,
        )
        draw.polygon(
            [(16, 12), (16, 8), (20, 8), (20, 5), (24, 5), (24, 3),
             (30, 3), (30, 5), (34, 5), (34, 8), (38, 8), (38, 12)],
            fill=WHITE,
        )
        draw.polygon(
            [(34, 12), (34, 9), (37, 9), (37, 7), (41, 7), (41, 9),
             (44, 9), (44, 12)],
            fill=WHITE,
        )
    else:
        draw.rectangle((0, 16, width - 1, height - 1), fill=WHITE)
        draw.polygon(
            [(1, 16), (1, 13), (5, 13), (5, 10), (9, 10), (9, 7),
             (14, 7), (14, 10), (18, 10), (18, 16)],
            fill=WHITE,
        )
        draw.polygon(
            [(13, 16), (13, 10), (17, 10), (17, 6), (22, 6), (22, 3),
             (29, 3), (29, 6), (34, 6), (34, 10), (38, 10), (38, 16)],
            fill=WHITE,
        )
        draw.polygon(
            [(31, 16), (31, 11), (35, 11), (35, 7), (40, 7), (40, 5),
             (46, 5), (46, 8), (50, 8), (50, 12), (54, 12), (54, 16)],
            fill=WHITE,
        )

    draw.rectangle((0, height - 3, width - 1, height - 1), fill=tint)
    return image


def _ground() -> Image.Image:
    width, height = 120, 29
    image = Image.new("RGBA", (width, height), (143, 93, 67, 255))
    draw = ImageDraw.Draw(image)
    grass = (105, 183, 63, 255)
    grass_light = (132, 201, 69, 255)
    grass_dark = (54, 137, 51, 255)
    soil_light = (170, 112, 78, 255)
    soil_dark = (112, 70, 57, 255)

    draw.rectangle((0, 0, width - 1, 4), fill=grass_light)
    draw.rectangle((0, 5, width - 1, 7), fill=grass)
    draw.rectangle((0, 8, width - 1, 9), fill=grass_dark)
    for x in range(width):
        if x % 7 in (0, 1):
            draw.point((x, 4), fill=grass)
        if x % 9 in (2, 3):
            draw.point((x, 7), fill=grass_dark)
        if x % 11 == 5:
            draw.point((x, 9), fill=grass)

    # Soil uses single source-cell clusters; no dark perimeter line.
    for y in range(11, height):
        for x in range(width):
            key = (x * 17 + y * 11 + (x // 5) * 3) % 23
            if key in (0, 1, 7):
                draw.point((x, y), fill=soil_light)
            elif key in (4, 12):
                draw.point((x, y), fill=soil_dark)
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    _dinosaur(1).save(OUT / "dinosaur_side_left_1_uniform.png")
    _dinosaur(2).save(OUT / "dinosaur_side_left_2_uniform.png")
    _cloud(57, 22).save(OUT / "pixel_cloud_uniform.png")
    _cloud(46, 17, small=True).save(OUT / "pixel_cloud_small_uniform.png")
    _ground().save(OUT / "pixel_ground_uniform.png")


if __name__ == "__main__":
    main()
