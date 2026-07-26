#!/usr/bin/env python3
"""Render deterministic app-logo color variants from the splash typography."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


PROJECT_ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = PROJECT_ROOT / "assets/fonts/Galmuri11-Bold.ttf"
OUTPUT_DIR = (
    PROJECT_ROOT / "assets/source/brand/ttak-logo-20260727"
)

CANVAS_SIZE = 1024
TEXT = "딱"
FONT_SIZE = 704
LETTER_SPACING = -56
SHADOW_OFFSET = (29, 41)
OPTICAL_OFFSET = (30, 0)

VARIANTS = (
    {
        "id": "01-current-brand",
        "name_ko": "현재 브랜드",
        "background": "#101827",
        "fill": "#FFF4D6",
        "shadow": "#B87714",
    },
    {
        "id": "02-signal-yellow",
        "name_ko": "시그널 옐로",
        "background": "#101827",
        "fill": "#FFD23F",
        "shadow": "#B87714",
    },
    {
        "id": "03-punch-coral",
        "name_ko": "펀치 코랄",
        "background": "#101827",
        "fill": "#FF6B6B",
        "shadow": "#A83F50",
    },
    {
        "id": "04-game-mint",
        "name_ko": "게임 민트",
        "background": "#09101D",
        "fill": "#54D6A1",
        "shadow": "#218260",
    },
    {
        "id": "05-neon-arcade",
        "name_ko": "네온 아케이드",
        "background": "#2B163E",
        "fill": "#55DDF5",
        "shadow": "#D84B9E",
    },
    {
        "id": "06-paper-ink",
        "name_ko": "페이퍼 잉크",
        "background": "#FFF4D6",
        "fill": "#101827",
        "shadow": "#FF6B6B",
    },
)


def draw_spaced_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[float, float],
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: str,
) -> None:
    x, y = xy
    for character in text:
        draw.text((round(x), round(y)), character, font=font, fill=fill)
        x += font.getlength(character) + LETTER_SPACING


def text_bounds(font: ImageFont.FreeTypeFont) -> tuple[int, int, int, int]:
    glyph_boxes = []
    x = 0.0
    for character in TEXT:
        left, top, right, bottom = font.getbbox(character)
        glyph_boxes.append((x + left, top, x + right, bottom))
        x += font.getlength(character) + LETTER_SPACING
    return (
        round(min(box[0] for box in glyph_boxes)),
        round(min(box[1] for box in glyph_boxes)),
        round(max(box[2] for box in glyph_boxes)),
        round(max(box[3] for box in glyph_boxes)),
    )


def render_logo(variant: dict[str, str], font: ImageFont.FreeTypeFont) -> Image.Image:
    image = Image.new(
        "RGB",
        (CANVAS_SIZE, CANVAS_SIZE),
        variant["background"],
    )
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = text_bounds(font)
    combined_width = (right - left) + SHADOW_OFFSET[0]
    combined_height = (bottom - top) + SHADOW_OFFSET[1]
    origin_x = (
        (CANVAS_SIZE - combined_width) / 2
        - left
        + OPTICAL_OFFSET[0]
    )
    origin_y = (
        (CANVAS_SIZE - combined_height) / 2
        - top
        + OPTICAL_OFFSET[1]
    )

    draw_spaced_text(
        draw,
        (
            origin_x + SHADOW_OFFSET[0],
            origin_y + SHADOW_OFFSET[1],
        ),
        TEXT,
        font,
        variant["shadow"],
    )
    draw_spaced_text(
        draw,
        (origin_x, origin_y),
        TEXT,
        font,
        variant["fill"],
    )
    return image


def make_contact_sheet(
    rendered: list[tuple[dict[str, str], Image.Image]],
    label_font: ImageFont.FreeTypeFont,
) -> Image.Image:
    columns = 3
    tile_size = 480
    label_height = 86
    gap = 28
    outer = 40
    rows = 2
    width = outer * 2 + columns * tile_size + (columns - 1) * gap
    height = outer * 2 + rows * (tile_size + label_height) + (rows - 1) * gap
    sheet = Image.new("RGB", (width, height), "#E8E4DA")
    draw = ImageDraw.Draw(sheet)

    for index, (variant, image) in enumerate(rendered):
        column = index % columns
        row = index // columns
        x = outer + column * (tile_size + gap)
        y = outer + row * (tile_size + label_height + gap)
        tile = image.resize((tile_size, tile_size), Image.Resampling.LANCZOS)
        sheet.paste(tile, (x, y))
        label = f"{index + 1}. {variant['name_ko']}"
        label_box = draw.textbbox((0, 0), label, font=label_font)
        label_width = label_box[2] - label_box[0]
        draw.text(
            (x + (tile_size - label_width) / 2, y + tile_size + 20),
            label,
            font=label_font,
            fill="#101827",
        )
    return sheet


def make_small_size_qc(
    rendered: list[tuple[dict[str, str], Image.Image]],
) -> Image.Image:
    sizes = (180, 120, 60, 48)
    cell_width = 224
    row_height = 210
    header_height = 54
    label_width = 160
    board = Image.new(
        "RGB",
        (
            label_width + len(sizes) * cell_width,
            header_height + len(rendered) * row_height,
        ),
        "#D8D4CA",
    )
    draw = ImageDraw.Draw(board)
    qc_font = ImageFont.truetype(FONT_PATH, 26)

    for column, size in enumerate(sizes):
        label = f"{size}px"
        label_box = draw.textbbox((0, 0), label, font=qc_font)
        label_width_px = label_box[2] - label_box[0]
        draw.text(
            (
                label_width
                + column * cell_width
                + (cell_width - label_width_px) / 2,
                12,
            ),
            label,
            font=qc_font,
            fill="#101827",
        )

    for row, (variant, image) in enumerate(rendered):
        row_y = header_height + row * row_height
        draw.text(
            (14, row_y + 88),
            str(row + 1),
            font=qc_font,
            fill="#101827",
        )
        for column, size in enumerate(sizes):
            x = label_width + column * cell_width + (cell_width - size) // 2
            y = row_y + (row_height - size) // 2
            preview = image.resize((size, size), Image.Resampling.LANCZOS)
            board.paste(preview, (x, y))
    return board


def validate_output(path: Path) -> None:
    with Image.open(path) as image:
        if image.size != (CANVAS_SIZE, CANVAS_SIZE):
            raise ValueError(f"Unexpected size for {path}: {image.size}")
        if image.mode != "RGB":
            raise ValueError(f"App icon must be opaque RGB: {path} is {image.mode}")
        background = image.getpixel((0, 0))
        bounds = image.getbbox()
        if bounds != (0, 0, CANVAS_SIZE, CANVAS_SIZE):
            raise ValueError(f"Canvas coverage failed for {path}: {bounds}")
        for corner in (
            (0, 0),
            (CANVAS_SIZE - 1, 0),
            (0, CANVAS_SIZE - 1),
            (CANVAS_SIZE - 1, CANVAS_SIZE - 1),
        ):
            if image.getpixel(corner) != background:
                raise ValueError(f"Corner contamination in {path}: {corner}")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    logo_font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    label_font = ImageFont.truetype(FONT_PATH, 30)
    rendered = []

    for variant in VARIANTS:
        image = render_logo(variant, logo_font)
        output_path = OUTPUT_DIR / f"ttak-{variant['id']}.png"
        image.save(output_path, optimize=True)
        validate_output(output_path)
        rendered.append((variant, image))

    contact_sheet = make_contact_sheet(rendered, label_font)
    contact_sheet.save(OUTPUT_DIR / "ttak-logo-variants.png", optimize=True)
    small_qc = make_small_size_qc(rendered)
    small_qc.save(OUTPUT_DIR / "qc-small-size.png", optimize=True)

    contract = {
        "asset_family": "ttak-logo",
        "method": "deterministic font rendering; no generative image model",
        "master_reference": "lib/app/startup_intro.dart",
        "font": str(FONT_PATH.relative_to(PROJECT_ROOT)),
        "font_license": "SIL Open Font License 1.1",
        "text": TEXT,
        "canvas": [CANVAS_SIZE, CANVAS_SIZE],
        "font_size": FONT_SIZE,
        "letter_spacing": LETTER_SPACING,
        "shadow_offset": list(SHADOW_OFFSET),
        "optical_offset": list(OPTICAL_OFFSET),
        "output_mode": "RGB, opaque, square corners",
        "variants": list(VARIANTS),
    }
    (OUTPUT_DIR / "asset-contract.json").write_text(
        json.dumps(contract, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
