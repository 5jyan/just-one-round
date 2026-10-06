from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path(__file__).resolve().parent
RUNTIME = ROOT / "assets" / "images" / "net_boat"


def build_strip(name: str, cell: int, output_height: int) -> None:
    source = Image.open(SOURCE / name / "processed" / "sheet-transparent.png").convert("RGBA")
    output = Image.new("RGBA", (cell * 4, output_height))
    crop_top = (cell - output_height) // 2
    for index in range(4):
        source_x = (index % 2) * cell
        source_y = (index // 2) * cell + crop_top
        frame = source.crop((source_x, source_y, source_x + cell, source_y + output_height))
        output.paste(frame, (index * cell, 0), frame)
    output.save(RUNTIME / f"{name}_atlas.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    build_strip("piranha", 24, 24)
    build_strip("marlin", 48, 32)
    build_strip("shark", 64, 48)
    build_strip("whale", 144, 96)


if __name__ == "__main__":
    main()
