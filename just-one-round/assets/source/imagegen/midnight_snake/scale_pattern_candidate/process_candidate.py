from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw-tile-transparent.png"
OUTPUT = ROOT / "snake_scale_pattern_candidate.png"
QC = ROOT / "qc"
GAMEPLAY_REFERENCE = (
    ROOT.parent
    / "unified_head"
    / "qc"
    / "simulator-unified-corner-live.png"
)

MOTIF_BOUNDS = (427, 142, 508, 197)
ART_SIZE = 16
DISPLAY_SCALE = 2
MOTIF_SIZE = (4, 3)
DARK = (76, 38, 10, 255)
AMBER = (220, 152, 25, 255)
CREAM = (255, 237, 164, 255)


def normalize_motif() -> Image.Image:
    raw = Image.open(RAW).convert("RGBA")
    motif = raw.crop(MOTIF_BOUNDS).resize(
        MOTIF_SIZE,
        Image.Resampling.NEAREST,
    )
    pixels = []
    for red, green, blue, alpha in motif.getdata():
        if alpha < 128:
            pixels.append((0, 0, 0, 0))
        elif red < 140:
            pixels.append(DARK)
        elif red > 245 and green > 220:
            pixels.append(CREAM)
        else:
            pixels.append(AMBER)
    motif.putdata(pixels)
    return motif


def paste_wrapped(
    target: Image.Image,
    source: Image.Image,
    left: int,
    top: int,
) -> None:
    for source_y in range(source.height):
        for source_x in range(source.width):
            pixel = source.getpixel((source_x, source_y))
            if pixel[3] == 0:
                continue
            target.putpixel(
                ((left + source_x) % target.width, (top + source_y) % target.height),
                pixel,
            )


def build_tile() -> Image.Image:
    motif = normalize_motif()
    art = Image.new("RGBA", (ART_SIZE, ART_SIZE), (0, 0, 0, 0))
    for left, top in ((1, 1), (9, 1), (5, 9), (13, 9)):
        paste_wrapped(art, motif, left, top)
    return art.resize(
        (ART_SIZE * DISPLAY_SCALE, ART_SIZE * DISPLAY_SCALE),
        Image.Resampling.NEAREST,
    )


def tile_image(tile: Image.Image, size: tuple[int, int]) -> Image.Image:
    repeated = Image.new("RGBA", size, (0, 0, 0, 0))
    for top in range(0, size[1], tile.height):
        for left in range(0, size[0], tile.width):
            repeated.alpha_composite(tile, (left, top))
    return repeated


def build_gameplay_preview(tile: Image.Image) -> None:
    screenshot = Image.open(GAMEPLAY_REFERENCE).convert("RGBA")
    repeated = tile_image(tile, screenshot.size)
    source = screenshot.load()
    overlay = repeated.load()
    for y in range(screenshot.height):
        for x in range(screenshot.width):
            red, green, blue, _ = source[x, y]
            is_body_gold = (
                abs(red - AMBER[0]) <= 28
                and abs(green - AMBER[1]) <= 28
                and blue <= 70
            )
            if not is_body_gold:
                overlay[x, y] = (0, 0, 0, 0)
    screenshot.alpha_composite(repeated)
    screenshot.save(QC / "gameplay-preview.png")


def main() -> None:
    QC.mkdir(parents=True, exist_ok=True)
    tile = build_tile()
    tile.save(OUTPUT)
    tile.resize((256, 256), Image.Resampling.NEAREST).save(
        QC / "tile-8x.png"
    )

    repeated = tile_image(tile, (128, 128))
    backdrop = Image.new("RGBA", repeated.size, (220, 152, 25, 255))
    backdrop.alpha_composite(repeated)
    backdrop.resize((512, 512), Image.Resampling.NEAREST).save(
        QC / "repeat-4x.png"
    )
    build_gameplay_preview(tile)


if __name__ == "__main__":
    main()
