from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageFilter


SOURCE_CELL = 64
TARGET_CELL = 32
ROWS = 2
COLS = 2
OUTLINE = (42, 25, 56, 255)
PALETTE = (
    OUTLINE,
    (53, 106, 112, 255),
    (92, 150, 152, 255),
    (122, 180, 174, 255),
    (201, 123, 85, 255),
    (240, 173, 121, 255),
    (169, 110, 6, 255),
    (227, 178, 17, 255),
    (255, 240, 194, 255),
)


def nearest_palette_color(red: int, green: int, blue: int) -> tuple[int, int, int, int]:
    return min(
        PALETTE,
        key=lambda color: (
            (red - color[0]) ** 2
            + (green - color[1]) ** 2
            + (blue - color[2]) ** 2
        ),
    )


def remaster_frame(frame: Image.Image) -> Image.Image:
    reduced = frame.resize(
        (TARGET_CELL, TARGET_CELL),
        resample=Image.Resampling.NEAREST,
    ).convert("RGBA")

    pixels = reduced.load()
    for y in range(TARGET_CELL):
        for x in range(TARGET_CELL):
            red, green, blue, alpha = pixels[x, y]
            pixels[x, y] = (
                (0, 0, 0, 0)
                if alpha < 128
                else nearest_palette_color(red, green, blue)
            )

    solid = reduced.getchannel("A")
    expanded = solid.filter(ImageFilter.MaxFilter(3))
    outline_mask = ImageChops.subtract(expanded, solid)
    outline_layer = Image.new("RGBA", reduced.size, OUTLINE)
    transparent = Image.new("RGBA", reduced.size, (0, 0, 0, 0))
    result = Image.composite(outline_layer, transparent, outline_mask)
    result.alpha_composite(reduced)
    return result


def remaster_sheet(source: Path, destination: Path) -> None:
    sheet = Image.open(source).convert("RGBA")
    if sheet.size != (SOURCE_CELL * COLS, SOURCE_CELL * ROWS):
        raise ValueError(f"unexpected source sheet size: {sheet.size}")

    output = Image.new(
        "RGBA",
        (TARGET_CELL * COLS, TARGET_CELL * ROWS),
        (0, 0, 0, 0),
    )
    for row in range(ROWS):
        for column in range(COLS):
            left = column * SOURCE_CELL
            top = row * SOURCE_CELL
            frame = sheet.crop(
                (left, top, left + SOURCE_CELL, top + SOURCE_CELL)
            )
            output.alpha_composite(
                remaster_frame(frame),
                (column * TARGET_CELL, row * TARGET_CELL),
            )

    destination.parent.mkdir(parents=True, exist_ok=True)
    output.save(destination)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: remaster_native32.py INPUT OUTPUT")
    remaster_sheet(Path(sys.argv[1]), Path(sys.argv[2]))
