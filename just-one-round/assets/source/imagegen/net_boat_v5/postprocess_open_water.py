from pathlib import Path

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path(__file__).with_name("sea_background_open_water_raw.png")
OUTPUT = Path(__file__).with_name("sea_background_open_water_360x960.png")
RUNTIME = ROOT / "assets/images/net_boat/sea_background.png"


def main() -> None:
    image = Image.open(SOURCE).convert("RGBA")
    image = image.resize((180, 480), Image.Resampling.LANCZOS)
    image = ImageEnhance.Color(image).enhance(0.9)
    teal = Image.new("RGBA", image.size, (0, 54, 42, 24))
    image = Image.alpha_composite(image, teal)
    image = image.resize((360, 960), Image.Resampling.NEAREST)
    image.save(OUTPUT)
    image.save(RUNTIME)


if __name__ == "__main__":
    main()
