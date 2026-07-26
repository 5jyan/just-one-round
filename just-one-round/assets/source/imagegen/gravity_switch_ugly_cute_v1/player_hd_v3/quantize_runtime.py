import argparse
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent

PALETTE = (
    (52, 28, 57, 255),
    (77, 46, 79, 255),
    (112, 145, 48, 255),
    (177, 202, 54, 255),
    (207, 224, 82, 255),
    (255, 239, 157, 255),
    (244, 85, 43, 255),
    (177, 54, 38, 255),
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
    parser = argparse.ArgumentParser()
    parser.add_argument("--processed-dir", default="processed")
    args = parser.parse_args()
    processed = ROOT / args.processed_dir
    source_path = processed / "sheet-transparent.png"
    output_path = processed / "player-magnet-mite-sheet.png"

    source = Image.open(source_path).convert("RGBA")
    quantized = Image.new("RGBA", source.size)
    quantized.putdata([nearest_palette_color(pixel) for pixel in source.getdata()])
    quantized.save(output_path)

    frames = []
    for index, (column, row) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1)), 1):
        frame = quantized.crop((column * 48, row * 48, (column + 1) * 48, (row + 1) * 48))
        frame.save(processed / f"magnet-mite-runtime-{index}.png")
        frames.append(frame)

    frames[0].save(
        processed / "animation-runtime.gif",
        save_all=True,
        append_images=frames[1:],
        duration=110,
        loop=0,
        disposal=2,
    )
    quantized.resize((768, 768), Image.Resampling.NEAREST).save(
        processed / "player-magnet-mite-sheet-8x.png"
    )


if __name__ == "__main__":
    main()
