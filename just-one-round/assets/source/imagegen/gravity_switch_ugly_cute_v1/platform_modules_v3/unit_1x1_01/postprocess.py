from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw" / "generated-transparent.png"
PROCESSED = ROOT / "processed"
PREVIEWS = ROOT / "previews"
PROCESSED.mkdir(exist_ok=True)
PREVIEWS.mkdir(exist_ok=True)

DEEP_PLUM = (48, 27, 52, 255)
DARK_VIOLET = (67, 39, 69, 255)
BRUISED_VIOLET = (96, 61, 91, 255)
LIGHT_VIOLET = (135, 88, 117, 255)
DARK_OLIVE = (78, 96, 39, 255)
MUTED_OLIVE = (112, 132, 48, 255)
SOUR_LIME = (171, 195, 54, 255)
DIRTY_CREAM = (232, 218, 133, 255)
TOMATO = (226, 76, 38, 255)

PALETTE = (
    DEEP_PLUM,
    DARK_VIOLET,
    BRUISED_VIOLET,
    LIGHT_VIOLET,
    DARK_OLIVE,
    MUTED_OLIVE,
    SOUR_LIME,
    DIRTY_CREAM,
    TOMATO,
)


def color_distance(
    left: tuple[int, int, int],
    right: tuple[int, int, int],
) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten(image: Image.Image) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, DEEP_PLUM)
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if alpha < 128:
                continue
            output.putpixel(
                (x, y),
                min(
                    PALETTE,
                    key=lambda color: color_distance(
                        (red, green, blue),
                        color[:3],
                    ),
                ),
            )
    return output


source = Image.open(RAW).convert("RGBA")
bounds = source.getchannel("A").getbbox()
if bounds is None:
    raise RuntimeError("Generated source contains no opaque subject.")

subject = source.crop(bounds)
side = max(subject.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.alpha_composite(
    subject,
    ((side - subject.width) // 2, (side - subject.height) // 2),
)
tile = flatten(square.resize((48, 48), Image.Resampling.LANCZOS))

# Freeze a universal three-pixel connector contract. Opposite edges are derived
# from the same generated edge samples, and the outermost row is solid, so any
# future module can meet this unit without a gap or mismatched protrusion.
top_inner = tile.crop((3, 1, 45, 3))
left_inner = tile.crop((1, 3, 3, 45))
tile.paste(DEEP_PLUM, (0, 0, 48, 1))
tile.paste(DEEP_PLUM, (0, 47, 48, 48))
tile.paste(DEEP_PLUM, (0, 0, 1, 48))
tile.paste(DEEP_PLUM, (47, 0, 48, 48))
tile.paste(top_inner, (3, 1))
tile.paste(ImageOps.flip(top_inner), (3, 45))
tile.paste(left_inner, (1, 3))
tile.paste(ImageOps.mirror(left_inner), (45, 3))
tile.paste(DEEP_PLUM, (0, 0, 3, 3))
tile.paste(DEEP_PLUM, (45, 0, 48, 3))
tile.paste(DEEP_PLUM, (0, 45, 3, 48))
tile.paste(DEEP_PLUM, (45, 45, 48, 48))
tile.save(PROCESSED / "scrap_module_1x1_01.png")

tile.resize((576, 576), Image.Resampling.NEAREST).save(
    PREVIEWS / "scrap_module_1x1_01_12x.png",
)

join_test = Image.new("RGBA", (144, 144), DEEP_PLUM)
for row in range(3):
    for column in range(3):
        join_test.alpha_composite(tile, (column * 48, row * 48))
join_test.save(PREVIEWS / "join_test_3x3.png")
join_test.resize((576, 576), Image.Resampling.NEAREST).save(
    PREVIEWS / "join_test_3x3_4x.png",
)
