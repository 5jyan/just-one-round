from pathlib import Path
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT.parents[3] / "images" / "dung_dodge_v2"

CHARACTER_PALETTE = (
    (58, 28, 55, 255),
    (83, 48, 69, 255),
    (96, 132, 45, 255),
    (132, 170, 49, 255),
    (177, 202, 54, 255),
    (208, 222, 75, 255),
    (255, 239, 157, 255),
    (244, 85, 43, 255),
    (255, 137, 55, 255),
    (208, 86, 104, 255),
)
POOP_PALETTE = (
    (58, 28, 55, 255),
    (83, 48, 69, 255),
    (101, 53, 45, 255),
    (142, 78, 43, 255),
    (184, 105, 47, 255),
    (211, 143, 43, 255),
    (244, 137, 40, 255),
    (255, 239, 157, 255),
    (255, 250, 201, 255),
)
GROUND_PALETTE = (
    (58, 28, 55, 255),
    (83, 48, 69, 255),
    (101, 53, 45, 255),
    (142, 78, 43, 255),
    (178, 100, 46, 255),
    (112, 145, 48, 255),
    (177, 202, 54, 255),
    (211, 157, 43, 255),
    (127, 80, 124, 255),
    (255, 239, 157, 255),
)


def distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten(image: Image.Image, palette: tuple[tuple[int, int, int, int], ...]) -> Image.Image:
    source = image.convert("RGBA")
    output = Image.new("RGBA", source.size, (0, 0, 0, 0))
    source_pixels = source.load()
    output_pixels = output.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source_pixels[x, y]
            if alpha < 128:
                continue
            output_pixels[x, y] = min(
                palette,
                key=lambda color: distance((red, green, blue), color[:3]),
            )
    return output


def process_sheet(folder: str, runtime_name: str, palette) -> None:
    processed = ROOT / folder / "processed"
    sheet = processed / "sheet-transparent.png"
    original = processed / "sheet-transparent-prepalette.png"
    if not original.exists():
        shutil.copy2(sheet, original)
    result = flatten(Image.open(original), palette)
    result.save(sheet)
    result.save(RUNTIME / runtime_name)


def process_ground() -> None:
    processed = ROOT / "ground" / "processed"
    source = Image.open(processed / "ground-transparent.png").convert("RGBA")
    pixels = source.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and red > 175 and blue > 145 and green < 125:
                pixels[x, y] = (0, 0, 0, 0)

    bounds = source.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError("Ground chroma-key result is empty.")
    strip = source.crop(bounds)

    # Limit vertical correction to a modest 72px content band. This removes
    # most of the old stretch while avoiding an unnaturally empty lower half.
    strip = strip.resize((360, 72), Image.Resampling.NEAREST)
    result = Image.new("RGBA", (360, 96), GROUND_PALETTE[0])
    result.alpha_composite(strip, (0, 0))
    result = flatten(result, GROUND_PALETTE)

    contact_lime = (177, 202, 54, 255)
    for x in range(360):
        result.putpixel((x, 0), contact_lime)
    if result.getchannel("A").getbbox() != (0, 0, 360, 96):
        raise RuntimeError("Ground must fill the 360x96 runtime rectangle.")
    result.save(processed / "ground-strip.png")
    result.save(RUNTIME / "ground_strip.png")


process_sheet("player_idle", "player_idle_sheet.png", CHARACTER_PALETTE)
process_sheet("player_run", "player_run_sheet.png", CHARACTER_PALETTE)
process_sheet("poop", "poop_fall_sheet.png", POOP_PALETTE)
process_ground()
