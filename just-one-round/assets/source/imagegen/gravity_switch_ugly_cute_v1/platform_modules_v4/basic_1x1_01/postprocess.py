from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw" / "generated-transparent.png"
PROCESSED = ROOT / "processed"
PREVIEWS = ROOT / "previews"
PROCESSED.mkdir(exist_ok=True)
PREVIEWS.mkdir(exist_ok=True)

BLACK_PLUM = (31, 18, 36, 255)
DEEP_PLUM = (44, 27, 48, 255)
DARK_VIOLET = (59, 37, 62, 255)
BRUISED_VIOLET = (77, 49, 77, 255)
MUTED_OLIVE = (79, 84, 34, 255)
PALETTE = (
    BLACK_PLUM,
    DEEP_PLUM,
    DARK_VIOLET,
    BRUISED_VIOLET,
    MUTED_OLIVE,
)


def distance(
    left: tuple[int, int, int],
    right: tuple[int, int, int],
) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten(image: Image.Image) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, BLACK_PLUM)
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source.getpixel((x, y))
            if alpha < 128:
                continue
            output.putpixel(
                (x, y),
                min(
                    PALETTE,
                    key=lambda color: distance(
                        (red, green, blue),
                        color[:3],
                    ),
                ),
            )
    return output


source = Image.open(RAW).convert("RGBA")
bounds = source.getchannel("A").getbbox()
if bounds is None:
    raise RuntimeError("Generated source contains no opaque tile.")

subject = source.crop(bounds)
side = max(subject.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.alpha_composite(
    subject,
    ((side - subject.width) // 2, (side - subject.height) // 2),
)
tile = flatten(square.resize((48, 48), Image.Resampling.LANCZOS))

# This candidate defines the quieter v4 connector family. Opposite sides are
# derived from the same generated samples, so copies meet without gaps.
top_inner = tile.crop((3, 1, 45, 3))
left_inner = tile.crop((1, 3, 3, 45))
tile.paste(BLACK_PLUM, (0, 0, 48, 1))
tile.paste(BLACK_PLUM, (0, 47, 48, 48))
tile.paste(BLACK_PLUM, (0, 0, 1, 48))
tile.paste(BLACK_PLUM, (47, 0, 48, 48))
tile.paste(top_inner, (3, 1))
tile.paste(ImageOps.flip(top_inner), (3, 45))
tile.paste(left_inner, (1, 3))
tile.paste(ImageOps.mirror(left_inner), (45, 3))
tile.paste(BLACK_PLUM, (0, 0, 3, 3))
tile.paste(BLACK_PLUM, (45, 0, 48, 3))
tile.paste(BLACK_PLUM, (0, 45, 3, 48))
tile.paste(BLACK_PLUM, (45, 45, 48, 48))
tile.save(PROCESSED / "scrap_basic_1x1_01.png")

tile.resize((576, 576), Image.Resampling.NEAREST).save(
    PREVIEWS / "scrap_basic_1x1_01_12x.png",
)

join_test = Image.new("RGBA", (144, 144), BLACK_PLUM)
for row in range(3):
    for column in range(3):
        join_test.alpha_composite(tile, (column * 48, row * 48))
join_test.resize((576, 576), Image.Resampling.NEAREST).save(
    PREVIEWS / "join_test_3x3_4x.png",
)
