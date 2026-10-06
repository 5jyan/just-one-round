from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
RUNTIME = ROOT / "assets/images/net_boat/sea_background.png"
OUTPUT = Path(__file__).with_name("sea_background_clean_360x960.png")

# Source-image coordinates for the runtime water enclosed by the rock wall.
PLAY_RECT = (42, 266, 318, 752)
# This strip is visually inspected clear water throughout PLAY_RECT's height.
DONOR_RECT = (82, 266, 278, 752)


def main() -> None:
    image = Image.open(RUNTIME).convert("RGBA")
    donor = image.crop(DONOR_RECT)
    width = PLAY_RECT[2] - PLAY_RECT[0]
    height = PLAY_RECT[3] - PLAY_RECT[1]
    clear_water = donor.resize((width, height), Image.Resampling.BICUBIC)
    image.paste(clear_water, PLAY_RECT[:2])
    image.save(OUTPUT)
    image.save(RUNTIME)


if __name__ == "__main__":
    main()
