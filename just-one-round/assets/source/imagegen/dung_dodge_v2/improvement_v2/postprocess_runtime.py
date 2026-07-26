from pathlib import Path
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT.parents[3] / "images" / "dung_dodge_v2"

CHARACTER_PALETTE = (
    (62, 30, 58, 255),
    (177, 202, 54, 255),
    (112, 145, 48, 255),
    (255, 239, 157, 255),
    (244, 85, 43, 255),
    (208, 86, 104, 255),
)
POOP_PALETTE = (
    (62, 30, 58, 255),
    (142, 78, 43, 255),
    (101, 53, 45, 255),
    (211, 157, 43, 255),
    (244, 85, 43, 255),
    (255, 239, 157, 255),
)
GROUND_PALETTE = (
    (62, 30, 58, 255),
    (177, 202, 54, 255),
    (112, 145, 48, 255),
    (142, 78, 43, 255),
    (101, 53, 45, 255),
    (127, 80, 124, 255),
    (255, 239, 157, 255),
)


def distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def flatten_palette(image: Image.Image, palette: tuple[tuple[int, int, int, int], ...]) -> Image.Image:
    source = image.convert("RGBA")
    result = Image.new("RGBA", source.size, (0, 0, 0, 0))
    source_pixels = source.load()
    result_pixels = result.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source_pixels[x, y]
            if alpha < 128:
                continue
            result_pixels[x, y] = min(
                palette,
                key=lambda color: distance((red, green, blue), color[:3]),
            )
    return result


def process_sheet(name: str, runtime_name: str, palette: tuple[tuple[int, int, int, int], ...]) -> None:
    processed = ROOT / name / "processed"
    sheet_path = processed / "sheet-transparent.png"
    preserved_path = processed / "sheet-transparent-prepalette.png"
    if not preserved_path.exists():
        shutil.copy2(sheet_path, preserved_path)
    flattened = flatten_palette(Image.open(preserved_path), palette)
    flattened.save(sheet_path)
    flattened.save(RUNTIME / runtime_name)

    cell_size = 32 if name.startswith("player_") else 24
    for row in range(2):
        for column in range(2):
            frame = flattened.crop(
                (
                    column * cell_size,
                    row * cell_size,
                    (column + 1) * cell_size,
                    (row + 1) * cell_size,
                )
            )
            frame.save(processed / f"runtime-frame-{row * 2 + column + 1}.png")


def process_ground() -> None:
    processed = ROOT / "ground" / "processed"
    source = Image.open(processed / "ground-transparent.png").convert("RGBA")
    pixels = source.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and red > 180 and blue > 150 and green < 110:
                pixels[x, y] = (0, 0, 0, 0)
    alpha = source.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError("Ground chroma-key result is empty.")
    source = source.crop(bounds)

    # Remove decorative grass tufts above the first continuous collision row.
    alpha = source.getchannel("A")
    first_continuous_row = None
    for y in range(source.height):
        opaque = sum(alpha.getpixel((x, y)) >= 128 for x in range(source.width))
        if opaque >= int(source.width * 0.995):
            first_continuous_row = y
            break
    if first_continuous_row is None:
        raise RuntimeError("Ground has no continuous horizontal contact row.")
    source = source.crop((0, first_continuous_row, source.width, source.height))
    source = source.resize((180, 48), Image.Resampling.NEAREST)
    source = flatten_palette(source, GROUND_PALETTE)
    contact_lime = (177, 202, 54, 255)
    for x in range(source.width):
        source.putpixel((x, 0), contact_lime)

    # Collision-bearing strip must remain a fully opaque rectangle.
    if source.getchannel("A").getbbox() != (0, 0, 180, 48):
        raise RuntimeError("Ground does not fill the full 180x48 collision rectangle.")
    source.save(processed / "ground-strip.png")
    source.save(RUNTIME / "ground_strip.png")


process_sheet("player_idle", "player_idle_sheet.png", CHARACTER_PALETTE)
process_sheet("player_run", "player_run_sheet.png", CHARACTER_PALETTE)
process_sheet("poop", "poop_fall_sheet.png", POOP_PALETTE)
process_ground()
