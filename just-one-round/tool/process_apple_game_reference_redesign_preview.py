import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/apple_game_reference_redesign"
OUTPUT = ROOT / "artifacts/apple_game_reference_redesign"
RUNTIME_OUTPUT = ROOT / "assets/images/apple_game"
FONT_PATH = ROOT / "assets/fonts/Galmuri11-Bold.ttf"
QC_OUTPUT = SOURCE / "qc"


def keep_largest_alpha_component(
    image: Image.Image, threshold: int = 20
) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    width, height = rgba.size
    pixels = alpha.load()
    visited = bytearray(width * height)
    largest: list[tuple[int, int]] = []

    for y in range(height):
        for x in range(width):
            index = y * width + x
            if visited[index] or pixels[x, y] <= threshold:
                continue
            stack = [(x, y)]
            visited[index] = 1
            component: list[tuple[int, int]] = []
            while stack:
                current_x, current_y = stack.pop()
                component.append((current_x, current_y))
                for next_y in range(
                    max(0, current_y - 1), min(height, current_y + 2)
                ):
                    for next_x in range(
                        max(0, current_x - 1), min(width, current_x + 2)
                    ):
                        next_index = next_y * width + next_x
                        if (
                            visited[next_index]
                            or pixels[next_x, next_y] <= threshold
                        ):
                            continue
                        visited[next_index] = 1
                        stack.append((next_x, next_y))
            if len(component) > len(largest):
                largest = component

    clean_alpha = Image.new("L", rgba.size, 0)
    clean_pixels = clean_alpha.load()
    for x, y in largest:
        clean_pixels[x, y] = pixels[x, y]
    rgba.putalpha(clean_alpha)
    return rgba


def contain(image: Image.Image, size: tuple[int, int], padding: int) -> Image.Image:
    usable_width = size[0] - padding * 2
    usable_height = size[1] - padding * 2
    scale = min(usable_width / image.width, usable_height / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.NEAREST,
    )
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2),
    )
    return canvas


def number_center(
    canvas: Image.Image,
    value: int,
    x: int,
    y: int,
    font: ImageFont.FreeTypeFont,
) -> None:
    draw = ImageDraw.Draw(canvas)
    label = str(value)
    box = draw.textbbox((0, 0), label, font=font)
    width = box[2] - box[0]
    height = box[3] - box[1]
    draw.text(
        (x + (48 - width) / 2, y + (48 - height) / 2 - 3),
        label,
        font=font,
        fill="#FFF3C4",
        stroke_width=2,
        stroke_fill="#591F2C",
    )


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    RUNTIME_OUTPUT.mkdir(parents=True, exist_ok=True)
    QC_OUTPUT.mkdir(parents=True, exist_ok=True)

    sheet = Image.open(SOURCE / "apple-face-removal-rgba.png").convert("RGBA")
    cell_width = sheet.width // 3
    cell_height = sheet.height // 3
    atlas = Image.new("RGBA", (144, 144), (0, 0, 0, 0))
    sprites = []
    for index in range(9):
        # Several generated variants have flat or truncated side silhouettes.
        # Numbers are rendered at runtime, so every value shares the clean,
        # fully rounded first apple silhouette.
        source_index = 0
        source_column = source_index % 3
        source_row = source_index // 3
        cell = sheet.crop(
            (
                source_column * cell_width,
                source_row * cell_height,
                (source_column + 1) * cell_width,
                (source_row + 1) * cell_height,
            )
        )
        cell = keep_largest_alpha_component(cell)
        bounds = cell.getchannel("A").getbbox()
        sprite = contain(cell.crop(bounds), (48, 48), padding=3)
        sprites.append(sprite)
        output_column = index % 3
        output_row = index // 3
        atlas.alpha_composite(sprite, (output_column * 48, output_row * 48))
    atlas.save(OUTPUT / "apple_plain_variants_atlas_144.png")
    atlas.save(RUNTIME_OUTPUT / "apple_faces_atlas.png")

    background_source = Image.open(
        SOURCE / "foliage-background-raw.png"
    ).convert("RGB")
    crop_width = round(background_source.height * 0.5)
    crop_left = (background_source.width - crop_width) // 2
    background_crop = background_source.crop(
        (crop_left, 0, crop_left + crop_width, background_source.height)
    )
    background = background_crop.resize((360, 720), Image.Resampling.NEAREST)
    background.save(OUTPUT / "foliage_background_360x720.png")
    background.save(RUNTIME_OUTPUT / "apple_game_background.png")

    font = ImageFont.truetype(str(FONT_PATH), 23)
    number_preview = Image.new("RGBA", (432, 48), (5, 27, 25, 255))
    for index, sprite in enumerate(sprites):
        x = index * 48
        number_preview.alpha_composite(sprite, (x, 0))
        number_center(number_preview, index + 1, x, 0, font)
    number_preview.resize((1296, 144), Image.Resampling.NEAREST).save(
        OUTPUT / "apple_numbers_1_to_9_preview_3x.png"
    )
    atlas.resize((1152, 1152), Image.Resampling.NEAREST).save(
        QC_OUTPUT / "apple_faces_atlas_8x.png"
    )
    background.resize((180, 360), Image.Resampling.NEAREST).save(
        QC_OUTPUT / "apple_game_background_half.png"
    )

    gameplay = background.convert("RGBA")
    values = [
        [2, 8, 1, 3, 1, 2, 7, 6],
        [2, 6, 1, 5, 2, 4, 4, 3],
        [6, 9, 9, 3, 2, 1, 1, 5],
        [1, 9, 3, 7, 5, 1, 1, 4],
        [9, 6, 7, 4, 5, 7, 6, 8],
        [5, 4, 2, 3, 2, 5, 8, 1],
        [7, 5, 8, 5, 8, 9, 1, 2],
        [7, 5, 2, 7, 6, 3, 2, 9],
        [3, 4, 8, 9, 4, 7, 1, 6],
        [5, 8, 3, 2, 1, 2, 1, 7],
        [3, 1, 7, 2, 5, 7, 3, 4],
        [8, 2, 4, 6, 3, 1, 9, 5],
        [4, 6, 2, 8, 1, 9, 3, 7],
        [1, 5, 9, 2, 6, 4, 8, 3],
    ]
    left = 11
    top = 65
    for row, row_values in enumerate(values):
        for column, value in enumerate(row_values):
            x = left + column * 42
            y = top + row * 42
            apple = sprites[value - 1].resize((40, 40), Image.Resampling.NEAREST)
            gameplay.alpha_composite(apple, (x, y))
    gameplay.save(QC_OUTPUT / "gameplay_layout_360x720.png")

    metadata = {
        "sources": {
            "appleAtlas": str(SOURCE / "apple-face-removal-rgba.png"),
            "background": str(SOURCE / "foliage-background-raw.png"),
        },
        "runtime": {
            "appleAtlas": {
                "path": str(RUNTIME_OUTPUT / "apple_faces_atlas.png"),
                "size": [144, 144],
                "cellSize": [48, 48],
                "safePadding": 3,
            },
            "background": {
                "path": str(RUNTIME_OUTPUT / "apple_game_background.png"),
                "size": [360, 720],
                "crop": [crop_left, 0, crop_left + crop_width, background_source.height],
            },
        },
        "sampling": "nearest-neighbor",
        "frameCorrections": {
            "values1To9": "all use source variant 1 to prevent number-dependent clipped silhouettes"
        },
        "boardContract": {
            "columns": 8,
            "rows": 14,
            "left": 10,
            "top": 64,
            "cellSize": 42,
            "appleSize": 40,
        },
    }
    (QC_OUTPUT / "apple_runtime_adaptation.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
