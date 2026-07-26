from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/apple_game_redesign"
OUTPUT = ROOT / "artifacts/apple_game_redesign"


def contain(image: Image.Image, size: tuple[int, int], padding: int) -> Image.Image:
    usable = (size[0] - padding * 2, size[1] - padding * 2)
    scale = min(usable[0] / image.width, usable[1] / image.height)
    resized = image.resize(
        (round(image.width * scale), round(image.height * scale)),
        Image.Resampling.NEAREST,
    )
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2),
    )
    return canvas


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    apple_raw = Image.open(SOURCE / "apple-plain-chroma-rgba.png").convert("RGBA")
    bounds = apple_raw.getchannel("A").getbbox()
    apple = contain(apple_raw.crop(bounds), (48, 48), padding=2)
    apple.save(OUTPUT / "apple_plain_48.png")

    background_raw = Image.open(SOURCE / "leaf-background-raw.png").convert("RGB")
    background = background_raw.resize((180, 320), Image.Resampling.NEAREST)
    background.save(OUTPUT / "leaf_background_180x320.png")

    numbered = Image.new("RGBA", (432, 144), (18, 38, 22, 255))
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11-Bold.ttf"), 69)
    draw = ImageDraw.Draw(numbered)
    apple_large = apple.resize((144, 144), Image.Resampling.NEAREST)
    for value in range(1, 10):
        x = (value - 1) * 48
        numbered.alpha_composite(apple, (x, 0))
        label = str(value)
        small_font = ImageFont.truetype(
            str(ROOT / "assets/fonts/Galmuri11-Bold.ttf"),
            23,
        )
        box = draw.textbbox((0, 0), label, font=small_font, stroke_width=0)
        width = box[2] - box[0]
        height = box[3] - box[1]
        draw.text(
            (x + (48 - width) / 2, (48 - height) / 2 - 3),
            label,
            font=small_font,
            fill="#FFF3C4",
            stroke_width=2,
            stroke_fill="#591F2C",
        )
    numbered.crop((0, 0, 432, 48)).resize(
        (1296, 144),
        Image.Resampling.NEAREST,
    ).save(OUTPUT / "apple_numbers_1_to_9_preview_3x.png")

    gameplay = background.resize((360, 640), Image.Resampling.NEAREST).convert("RGBA")
    draw_game = ImageDraw.Draw(gameplay)
    board_font = ImageFont.truetype(
        str(ROOT / "assets/fonts/Galmuri11-Bold.ttf"),
        23,
    )
    values = [
        [2, 8, 1, 3, 1, 2, 7],
        [2, 6, 1, 5, 2, 4, 4],
        [6, 9, 9, 3, 2, 1, 1],
        [1, 9, 3, 7, 5, 1, 1],
        [9, 6, 7, 4, 5, 7, 6],
        [5, 4, 2, 3, 2, 5, 8],
        [7, 5, 8, 5, 8, 9, 1],
        [7, 5, 2, 7, 6, 3, 2],
        [3, 4, 8, 9, 4, 7, 1],
        [5, 8, 3, 2, 1, 2, 1],
        [3, 1, 7, 2, 5, 7, 3],
    ]
    left = 12
    top = 88
    for row, row_values in enumerate(values):
        for column, value in enumerate(row_values):
            x = left + column * 48
            y = top + row * 48
            gameplay.alpha_composite(apple, (x, y))
            label = str(value)
            box = draw_game.textbbox((0, 0), label, font=board_font)
            width = box[2] - box[0]
            height = box[3] - box[1]
            draw_game.text(
                (x + (48 - width) / 2, y + (48 - height) / 2 - 3),
                label,
                font=board_font,
                fill="#FFF3C4",
                stroke_width=2,
                stroke_fill="#591F2C",
            )
    gameplay.save(OUTPUT / "gameplay_concept_360x640.png")


if __name__ == "__main__":
    main()
