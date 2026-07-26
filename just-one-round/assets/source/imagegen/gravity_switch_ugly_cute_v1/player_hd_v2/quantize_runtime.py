from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
PROCESSED = ROOT / "processed"
SOURCE = PROCESSED / "sheet-transparent.png"
OUTPUT = PROCESSED / "player-magnet-mite-sheet.png"

PALETTE = (
    (52, 28, 57, 255),    # deep plum outline and face
    (77, 46, 79, 255),    # plum edge accent
    (112, 145, 48, 255),  # olive shadow
    (177, 202, 54, 255),  # sour-lime body
    (207, 224, 82, 255),  # lime highlight
    (255, 239, 157, 255), # cream eye
    (244, 85, 43, 255),   # orange-red magnetic nub
    (177, 54, 38, 255),   # dark nub edge
)


def nearest_palette_color(pixel: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
    red, green, blue, alpha = pixel
    if alpha < 128:
        return (0, 0, 0, 0)
    return min(
        PALETTE,
        key=lambda color: (
            (red - color[0]) ** 2
            + (green - color[1]) ** 2
            + (blue - color[2]) ** 2
        ),
    )


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    quantized = Image.new("RGBA", source.size)
    quantized.putdata([nearest_palette_color(pixel) for pixel in source.getdata()])
    quantized.save(OUTPUT)

    frames = []
    for index, (column, row) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1)), 1):
        frame = quantized.crop((column * 48, row * 48, (column + 1) * 48, (row + 1) * 48))
        frame.save(PROCESSED / f"magnet-mite-runtime-{index}.png")
        frames.append(frame)

    frames[0].save(
        PROCESSED / "animation-runtime.gif",
        save_all=True,
        append_images=frames[1:],
        duration=110,
        loop=0,
        disposal=2,
    )
    quantized.resize((768, 768), Image.Resampling.NEAREST).save(
        PROCESSED / "player-magnet-mite-sheet-8x.png"
    )


if __name__ == "__main__":
    main()
