from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/apple_game"
OUTPUT = ROOT / "assets/images/apple_game"
ARTIFACTS = ROOT / "artifacts/apple_game"


def contain(image: Image.Image, size: tuple[int, int], padding: int = 0) -> Image.Image:
    target_w, target_h = size
    usable_w = target_w - padding * 2
    usable_h = target_h - padding * 2
    scale = min(usable_w / image.width, usable_h / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.NEAREST,
    )
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        ((target_w - resized.width) // 2, (target_h - resized.height) // 2),
    )
    return canvas


def trim(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    return image.crop(bounds) if bounds else image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)

    faces = Image.open(SOURCE / "apple-faces-chroma-rgba.png").convert("RGBA")
    cell_w = faces.width // 3
    cell_h = faces.height // 3
    atlas = Image.new("RGBA", (144, 144), (0, 0, 0, 0))
    for index in range(9):
        col = index % 3
        row = index // 3
        cell = faces.crop(
            (col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h)
        )
        sprite = contain(trim(cell), (48, 48), padding=3)
        atlas.alpha_composite(sprite, (col * 48, row * 48))
    atlas.save(OUTPUT / "apple_faces_atlas.png")

    numbered = atlas.resize((576, 576), Image.Resampling.NEAREST)
    draw = ImageDraw.Draw(numbered)
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11-Bold.ttf"), 88)
    for index in range(9):
        col = index % 3
        row = index // 3
        center = (col * 192 + 96, row * 192 + 97)
        label = str(index + 1)
        box = draw.textbbox((0, 0), label, font=font, stroke_width=0)
        width = box[2] - box[0]
        height = box[3] - box[1]
        draw.text(
            (center[0] - width / 2, center[1] - height / 2 - 8),
            label,
            font=font,
            fill="#FFF3C4",
            stroke_width=7,
            stroke_fill="#591F2C",
        )
    numbered.save(ARTIFACTS / "apple_faces_numbered_preview_4x.png")

    background = Image.open(SOURCE / "background-raw.png").convert("RGB")
    background.resize((180, 320), Image.Resampling.NEAREST).save(
        OUTPUT / "apple_game_background.png"
    )

    ui = Image.open(SOURCE / "ui-pack-chroma-rgba.png").convert("RGBA")
    half_w = ui.width // 2
    half_h = ui.height // 2
    cells = [
        ui.crop((0, 0, half_w, half_h)),
        ui.crop((half_w, 0, ui.width, half_h)),
        ui.crop((0, half_h, half_w, ui.height)),
        ui.crop((half_w, half_h, ui.width, ui.height)),
    ]
    specs = [
        ("apple_board_frame.png", (180, 220), 4),
        ("apple_title_badge.png", (160, 72), 2),
        ("apple_time_badge.png", (64, 64), 2),
        ("apple_success_stamp.png", (64, 64), 2),
    ]
    for cell, (filename, size, padding) in zip(cells, specs):
        contain(trim(cell), size, padding=padding).save(OUTPUT / filename)

    effect = Image.open(SOURCE / "pop-effect-chroma-rgba.png").convert("RGBA")
    effect_cell_w = effect.width // 4
    strip = Image.new("RGBA", (192, 48), (0, 0, 0, 0))
    for index in range(4):
        cell = effect.crop(
            (index * effect_cell_w, 0, (index + 1) * effect_cell_w, effect.height)
        )
        strip.alpha_composite(
            contain(trim(cell), (48, 48), padding=3),
            (index * 48, 0),
        )
    strip.save(OUTPUT / "apple_pop_sheet.png")


if __name__ == "__main__":
    main()
