"""Composite approved generated details onto the accepted yellow duck poses."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
SOURCE = Path(__file__).resolve().parent
IMAGES = ROOT / "assets/images/mama_duck_trail"


def detail(name: str, size: tuple[int, int]) -> Image.Image:
    image = Image.open(SOURCE / f"{name}_raw.png").convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value >= 16 else 0).getbbox()
    assert bbox is not None
    image = image.crop(bbox).resize(size, Image.Resampling.NEAREST)
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if name == "mud":
                red, green, blue = (round(channel * 0.8) for channel in (red, green, blue))
            pixels[x, y] = (red, green, blue, 255 if alpha >= 128 else 0)
    return image


DETAILS = {
    "grubby": (detail("mud", (14, 12)), (39, 39)),
    "scarf": (detail("scarf", (17, 10)), (27, 46)),
}

for variant, (overlay, (left, top)) in DETAILS.items():
    for action in ("walk", "cheer"):
        original = Image.open(IMAGES / f"duckling_{action}_sheet.png").convert(
            "RGBA"
        )
        result = Image.new("RGBA", original.size)
        for row in range(2):
            for column in range(3):
                cell = original.crop(
                    (column * 72, row * 72, (column + 1) * 72, (row + 1) * 72)
                )
                cell.alpha_composite(overlay, (left, top))
                result.paste(cell, (column * 72, row * 72))
        result.save(IMAGES / f"duckling_{variant}_{action}_sheet.png")
