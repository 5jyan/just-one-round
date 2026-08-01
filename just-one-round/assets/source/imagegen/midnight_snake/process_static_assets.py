from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance


ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT.parents[2] / "images" / "midnight_snake"


def pixel_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    half = image.resize((size[0] // 2, size[1] // 2), Image.Resampling.LANCZOS)
    return half.resize(size, Image.Resampling.NEAREST)


def build_background() -> None:
    source = Image.open(ROOT / "background" / "raw-background.png").convert("RGB")
    target_ratio = 360 / 640
    source_ratio = source.width / source.height
    if source_ratio > target_ratio:
        width = round(source.height * target_ratio)
        left = (source.width - width) // 2
        source = source.crop((left, 0, left + width, source.height))
    else:
        height = round(source.width / target_ratio)
        top = (source.height - height) // 2
        source = source.crop((0, top, source.width, top + height))

    image = pixel_resize(source, (360, 640))
    image = ImageEnhance.Color(image).enhance(0.92)
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # The gameplay floor is the board itself. These lines are baked into the
    # environment so runtime never floats a second tile layer over the room.
    left, top, cell = 36, 112, 32
    right, bottom = left + 9 * cell, top + 15 * cell
    draw.rounded_rectangle(
        (left - 3, top - 3, right + 3, bottom + 3),
        radius=5,
        fill=(4, 28, 31, 46),
        outline=(6, 17, 21, 210),
        width=3,
    )
    for row in range(15):
        for column in range(9):
            x0 = left + column * cell
            y0 = top + row * cell
            shade = 17 if (row + column) % 2 == 0 else 8
            draw.rectangle(
                (x0 + 1, y0 + 1, x0 + cell - 1, y0 + cell - 1),
                fill=(5, 73 + shade, 77 + shade, 34),
            )
    for column in range(10):
        x = left + column * cell
        draw.line((x, top, x, bottom), fill=(3, 28, 32, 205), width=2)
    for row in range(16):
        y = top + row * cell
        draw.line((left, y, right, y), fill=(3, 28, 32, 205), width=2)
    for row in range(16):
        for column in range(10):
            x = left + column * cell
            y = top + row * cell
            draw.rectangle((x - 2, y - 2, x + 2, y + 2), fill=(2, 18, 22, 235))

    Image.alpha_composite(image.convert("RGBA"), overlay).save(
        RUNTIME / "apartment_background.png"
    )


def build_skin_tile() -> None:
    source = Image.open(ROOT / "skin" / "raw-tile.png").convert("RGB")
    side = min(source.size)
    source = source.crop(
        (
            (source.width - side) // 2,
            (source.height - side) // 2,
            (source.width + side) // 2,
            (source.height + side) // 2,
        )
    )
    quarter = source.resize((16, 16), Image.Resampling.LANCZOS)
    tile = Image.new("RGB", (32, 32))
    tile.paste(quarter, (0, 0))
    tile.paste(quarter.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (16, 0))
    tile.paste(quarter.transpose(Image.Transpose.FLIP_TOP_BOTTOM), (0, 16))
    tile.paste(quarter.transpose(Image.Transpose.ROTATE_180), (16, 16))
    tile.save(RUNTIME / "snake_skin_tile.png")


if __name__ == "__main__":
    RUNTIME.mkdir(parents=True, exist_ok=True)
    build_background()
    build_skin_tile()
