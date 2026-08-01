#!/usr/bin/env python3
"""Build the approved trump_v3 runtime bundle from generated source art."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/beat_the_dealer/trump_v3"
RUNTIME = ROOT / "assets/images/beat_the_dealer"
QC = SOURCE / "qc"
MAGENTA = (255, 0, 255)


def key_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, _ = pixels[x, y]
            distance = abs(red - 255) + green + abs(blue - 255)
            alpha = (
                0
                if distance < 90
                or (red > 180 and blue > 180 and green < 150)
                else 255
            )
            pixels[x, y] = (red, green, blue, alpha)
    return rgba


def alpha_crop(image: Image.Image, padding: int = 0) -> Image.Image:
    box = image.getchannel("A").getbbox()
    if box is None:
        raise ValueError("No foreground survived chroma key")
    left = max(0, box[0] - padding)
    top = max(0, box[1] - padding)
    right = min(image.width, box[2] + padding)
    bottom = min(image.height, box[3] + padding)
    return image.crop((left, top, right, bottom))


def sanitize_transparency(image: Image.Image) -> Image.Image:
    """Remove invisible chroma residue without touching visible edge pixels."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha < 16:
                pixels[x, y] = (0, 0, 0, 0)
    return rgba


def fit(image: Image.Image, size: tuple[int, int], padding: int = 0) -> Image.Image:
    target = Image.new("RGBA", size)
    max_width = size[0] - padding * 2
    max_height = size[1] - padding * 2
    scale = min(max_width / image.width, max_height / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )
    x = (size[0] - resized.width) // 2
    y = (size[1] - resized.height) // 2
    target.alpha_composite(resized, (x, y))
    return target


def build_card_front() -> Image.Image:
    image = Image.new("RGBA", (72, 100))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((1, 2, 71, 99), radius=6, fill=(41, 31, 48, 180))
    draw.rounded_rectangle(
        (0, 0, 71, 97),
        radius=6,
        fill=(255, 249, 224, 255),
        outline=(55, 43, 62, 255),
        width=2,
    )
    draw.rounded_rectangle(
        (3, 3, 68, 94),
        radius=4,
        outline=(226, 203, 155, 255),
        width=1,
    )
    draw.line((7, 92, 64, 92), fill=(241, 222, 183, 255), width=1)
    return image


def polygon(draw: ImageDraw.ImageDraw, points: list[tuple[int, int]], color: tuple[int, ...]) -> None:
    draw.polygon(points, fill=color)


def suit_icon(kind: int) -> Image.Image:
    image = Image.new("RGBA", (12, 12))
    draw = ImageDraw.Draw(image)
    red = (202, 49, 66, 255)
    black = (38, 31, 48, 255)
    color = red if kind in (1, 2) else black
    if kind == 0:  # spade
        polygon(draw, [(6, 1), (2, 5), (2, 7), (4, 8), (5, 7), (5, 9), (4, 10), (8, 10), (7, 9), (7, 7), (8, 8), (10, 7), (10, 5)], color)
    elif kind == 1:  # heart
        polygon(draw, [(2, 2), (4, 1), (6, 3), (8, 1), (10, 2), (10, 5), (6, 10), (2, 5)], color)
    elif kind == 2:  # diamond
        polygon(draw, [(6, 1), (10, 6), (6, 10), (2, 6)], color)
    else:  # club
        draw.ellipse((4, 1, 8, 5), fill=color)
        draw.ellipse((2, 4, 6, 8), fill=color)
        draw.ellipse((6, 4, 10, 8), fill=color)
        polygon(draw, [(5, 6), (7, 6), (7, 9), (8, 10), (4, 10), (5, 9)], color)
    return image


def save_suit_atlas() -> None:
    atlas = Image.new("RGBA", (48, 12))
    for index in range(4):
        atlas.alpha_composite(suit_icon(index), (index * 12, 0))
    atlas.save(RUNTIME / "suit_icons_v3.png")


def save_small_suit_atlas() -> None:
    """Build crisp, symmetric 8px corner glyphs inside padded 10px cells."""
    atlas = Image.new("RGBA", (40, 10))
    # The previous 6px font glyphs collapsed the heart, diamond, and club
    # into nearly identical blobs at the card's native 10px display size.
    # Keep the atlas and runtime cell unchanged, but author deliberate 8px
    # masks so every suit keeps a readable silhouette at nearest-neighbor.
    # Imported from the user's saved Downloads Piskel file
    # (suit_icons_small_v5-20260801-113838.piskel). Keep the exact 10x10
    # cells and 8x8 glyphs authored there.
    patterns = (
        (
            "...##...",
            "..####..",
            ".######.",
            "########",
            "########",
            "#..##..#",
            "...##...",
            "..####..",
        ),
        (
            ".##..##.",
            "########",
            "########",
            ".######.",
            ".######.",
            "..####..",
            "...##...",
            "........",
        ),
        (
            # v5's odd-width diamond is expanded to the nearest even-width
            # masks so the 10x10 runtime cell remains horizontally symmetric.
            "...##...",
            "..####..",
            ".######.",
            "########",
            "########",
            ".######.",
            "..####..",
            "...##...",
        ),
        (
            "..####..",
            "..####..",
            "..####..",
            "########",
            "########",
            "########",
            "...##...",
            "..####..",
        ),
    )
    colors = (
        (38, 31, 48, 255),
        (202, 49, 66, 255),
        (202, 49, 66, 255),
        (38, 31, 48, 255),
    )
    for index, pattern in enumerate(patterns):
        for y, row in enumerate(pattern):
            for x, visible in enumerate(row):
                if visible == "#":
                    atlas.putpixel((index * 10 + x + 1, y + 1), colors[index])
    atlas.save(RUNTIME / "suit_icons_small_v3.png")


def save_rank_atlas() -> None:
    """Bake the approved Pillow rank rendering for exact runtime parity."""
    ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
    font_path = ROOT / "assets/fonts/Galmuri11-Bold.ttf"
    rank_font = ImageFont.truetype(str(font_path), 14)
    ten_font = ImageFont.truetype(str(font_path), 11)
    colors = [(38, 31, 48, 255), (202, 49, 66, 255)]
    atlas = Image.new("RGBA", (234, 36))
    for row, color in enumerate(colors):
        for column, rank in enumerate(ranks):
            cell = Image.new("RGBA", (18, 18))
            ImageDraw.Draw(cell).text(
                (0, 0),
                rank,
                font=ten_font if rank == "10" else rank_font,
                fill=color,
            )
            atlas.alpha_composite(cell, (column * 18, row * 18))
    atlas.save(RUNTIME / "rank_glyphs_v3.png")


def save_royal_atlas() -> None:
    source = key_magenta(Image.open(SOURCE / "cards/raw/royal-master.png"))
    atlas = Image.new("RGBA", (144, 120))
    cell_width = source.width / 3
    cell_height = source.height / 2
    for row in range(2):
        for column in range(3):
            crop = source.crop(
                (
                    round(column * cell_width),
                    round(row * cell_height),
                    round((column + 1) * cell_width),
                    round((row + 1) * cell_height),
                )
            )
            portrait = sanitize_transparency(
                fit(alpha_crop(crop), (48, 60), padding=1)
            )
            atlas.alpha_composite(portrait, (column * 48, row * 60))
    atlas.save(RUNTIME / "royal_faces_v3.png")


def save_card_back() -> None:
    source = alpha_crop(
        key_magenta(Image.open(SOURCE / "cards/raw/card-back-master.png"))
    )
    card = sanitize_transparency(
        source.resize((72, 100), Image.Resampling.LANCZOS)
    )
    card.save(RUNTIME / "card_back_v3.png")


def save_sprites() -> None:
    mappings = {
        "dealer_idle": "dealer_idle_sheet_v3.png",
        "dealer_deal": "dealer_deal_sheet_v3.png",
        "dealer_win": "dealer_win_sheet_v3.png",
        "dealer_lose": "dealer_lose_sheet_v3.png",
        "player_idle": "player_idle_sheet_v3.png",
        "player_win": "player_win_sheet_v3.png",
        "player_lose": "player_lose_sheet_v3.png",
        "chip_fx": "chip_fx_sheet_v3.png",
    }
    for source_name, runtime_name in mappings.items():
        sanitize_transparency(
            Image.open(SOURCE / source_name / "processed/sheet-transparent.png")
        ).save(RUNTIME / runtime_name)
    sanitize_transparency(
        Image.open(SOURCE / "dealer_idle/processed/idle-1.png")
    ).save(RUNTIME / "dealer_idle_frame_v3.png")
    sanitize_transparency(
        Image.open(SOURCE / "player_idle/processed/idle-1.png")
    ).save(RUNTIME / "player_idle_frame_v3.png")
    chip = sanitize_transparency(
        Image.open(SOURCE / "chip_fx/processed/impact-1.png")
    )
    chip.save(RUNTIME / "coin_v3.png")


def save_background() -> None:
    source = Image.open(RUNTIME / "background_map_v2.png").convert("RGB")
    source = ImageEnhance.Color(source).enhance(0.94)
    source = ImageEnhance.Contrast(source).enhance(1.04)
    overlay = Image.new("RGBA", source.size)
    draw = ImageDraw.Draw(overlay)
    draw.rectangle((0, 0, 360, 290), fill=(14, 10, 32, 24))
    draw.rectangle((0, 575, 360, 840), fill=(14, 10, 32, 20))
    Image.alpha_composite(source.convert("RGBA"), overlay).convert("RGB").save(
        RUNTIME / "background_map_v3.png"
    )


def save_qc_sheet() -> None:
    sheet = Image.new("RGBA", (720, 420), (24, 17, 39, 255))
    card_front = Image.open(RUNTIME / "card_front_v3.png").convert("RGBA")
    card_back = Image.open(RUNTIME / "card_back_v3.png").convert("RGBA")
    royals = Image.open(RUNTIME / "royal_faces_v3.png").convert("RGBA")
    suits = Image.open(RUNTIME / "suit_icons_v3.png").convert("RGBA")
    dealer = Image.open(RUNTIME / "dealer_deal_sheet_v3.png").convert("RGBA")
    player = Image.open(RUNTIME / "player_win_sheet_v3.png").convert("RGBA")
    sheet.alpha_composite(card_front.resize((144, 200), Image.Resampling.NEAREST), (24, 24))
    sheet.alpha_composite(card_back.resize((144, 200), Image.Resampling.NEAREST), (184, 24))
    sheet.alpha_composite(royals.resize((288, 240), Image.Resampling.NEAREST), (344, 24))
    sheet.alpha_composite(suits.resize((384, 96), Image.Resampling.NEAREST), (24, 292))
    sheet.alpha_composite(dealer.resize((192, 128), Image.Resampling.NEAREST), (448, 280))
    sheet.alpha_composite(player.resize((96, 96), Image.Resampling.NEAREST), (624, 304))
    sheet.save(QC / "asset-contact-sheet-v3.png")


def save_all_cards_qc() -> None:
    gallery = Image.new("RGBA", (936, 400), (24, 17, 39, 255))
    front = Image.open(RUNTIME / "card_front_v3.png").convert("RGBA")
    suits = Image.open(RUNTIME / "suit_icons_v3.png").convert("RGBA")
    small_suits = Image.open(
        RUNTIME / "suit_icons_small_v3.png"
    ).convert("RGBA")
    rank_glyphs = Image.open(RUNTIME / "rank_glyphs_v3.png").convert("RGBA")
    royals = Image.open(RUNTIME / "royal_faces_v3.png").convert("RGBA")
    ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
    pip_positions = {
        2: [(36, 27), (36, 73)],
        3: [(36, 27), (36, 50), (36, 73)],
        4: [(24, 29), (48, 29), (24, 71), (48, 71)],
        5: [(24, 29), (48, 29), (36, 50), (24, 71), (48, 71)],
        6: [(24, 27), (48, 27), (24, 50), (48, 50), (24, 73), (48, 73)],
        7: [(24, 25), (48, 25), (36, 37), (24, 50), (48, 50), (24, 75), (48, 75)],
        8: [(24, 25), (48, 25), (36, 37), (24, 50), (48, 50), (36, 63), (24, 75), (48, 75)],
        9: [(24, 24), (48, 24), (24, 41), (48, 41), (36, 50), (24, 59), (48, 59), (24, 76), (48, 76)],
        10: [(24, 23), (48, 23), (36, 34), (24, 41), (48, 41), (24, 59), (48, 59), (36, 66), (24, 77), (48, 77)],
    }
    for suit_index in range(4):
        icon = suits.crop((suit_index * 12, 0, suit_index * 12 + 12, 12))
        small_icon = small_suits.crop(
            (suit_index * 10, 0, suit_index * 10 + 10, 10)
        )
        for rank_index, rank in enumerate(ranks):
            card = front.copy()
            corner = Image.new("RGBA", card.size)
            rank_row = 1 if suit_index in (1, 2) else 0
            rank_glyph = rank_glyphs.crop(
                (
                    rank_index * 18,
                    rank_row * 18,
                    rank_index * 18 + 18,
                    rank_row * 18 + 18,
                )
            )
            corner.alpha_composite(rank_glyph, (7, 5))
            if rank_index < 10:
                corner.alpha_composite(small_icon, (8, 21))
            else:
                corner.alpha_composite(icon, (7, 21))
            card.alpha_composite(corner)
            card.alpha_composite(corner.rotate(180))
            if rank_index >= 10:
                portrait = royals.crop(
                    (
                        (rank_index - 10) * 48,
                        60 if suit_index in (1, 2) else 0,
                        (rank_index - 9) * 48,
                        120 if suit_index in (1, 2) else 60,
                    )
                )
                card.alpha_composite(portrait, (12, 20))
            elif rank_index == 0:
                card.alpha_composite(
                    icon.resize((24, 24), Image.Resampling.NEAREST),
                    (24, 38),
                )
            else:
                for center_x, center_y in pip_positions[rank_index + 1]:
                    pip = icon.rotate(180) if center_y > 50 else icon
                    card.alpha_composite(pip, (center_x - 6, center_y - 6))
            gallery.alpha_composite(card, (rank_index * 72, suit_index * 100))
    gallery.save(QC / "all-52-cards-runtime-contract.png")


def save_animation_qc() -> None:
    canvas = Image.new("RGBA", (1024, 680), (24, 17, 39, 255))
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11-Bold.ttf"), 16)
    draw = ImageDraw.Draw(canvas)
    entries = [
        ("DEALER IDLE 4F", "dealer_idle_sheet_v3.png", (24, 42), 2),
        ("DEALER DEAL 6F", "dealer_deal_sheet_v3.png", (312, 42), 2),
        ("DEALER WIN 4F", "dealer_win_sheet_v3.png", (720, 42), 2),
        ("DEALER LOSE 4F", "dealer_lose_sheet_v3.png", (24, 344), 2),
        ("PLAYER IDLE 4F", "player_idle_sheet_v3.png", (312, 344), 2),
        ("PLAYER WIN 4F", "player_win_sheet_v3.png", (528, 344), 2),
        ("PLAYER LOSE 4F", "player_lose_sheet_v3.png", (744, 344), 2),
        ("CHIP FX 4F", "chip_fx_sheet_v3.png", (744, 560), 2),
    ]
    for label, filename, position, scale in entries:
        image = Image.open(RUNTIME / filename).convert("RGBA")
        enlarged = image.resize(
            (image.width * scale, image.height * scale),
            Image.Resampling.NEAREST,
        )
        draw.text((position[0], position[1] - 24), label, font=font, fill=(255, 225, 106, 255))
        canvas.alpha_composite(enlarged, position)
    canvas.save(QC / "animation-contact-sheet-v3.png")


def save_scale_calibration_qc() -> None:
    canvas = Image.new("RGBA", (720, 220), (24, 17, 39, 255))
    font = ImageFont.truetype(str(ROOT / "assets/fonts/Galmuri11-Bold.ttf"), 12)
    draw = ImageDraw.Draw(canvas)
    samples = [
        ("DODGE HERO", "32→64", ROOT / "assets/images/dung_dodge_v2/player_run_sheet.png", (32, 32), (64, 64)),
        ("DODGE HAZARD", "24→48", ROOT / "assets/images/dung_dodge_v2/poop_fall_sheet.png", (24, 24), (48, 48)),
        ("DODGE FX", "16→32", ROOT / "assets/images/dung_dodge_v2/dust_sheet.png", (16, 16), (32, 32)),
        ("DEALER", "64→128", RUNTIME / "dealer_idle_sheet_v3.png", (64, 64), (128, 128)),
        ("PLAYER", "48→96", RUNTIME / "player_idle_sheet_v3.png", (48, 48), (96, 96)),
        ("CHIP FX", "24→48", RUNTIME / "chip_fx_sheet_v3.png", (24, 24), (48, 48)),
    ]
    for index, (label, scale_label, path, source_size, display_size) in enumerate(samples):
        center_x = index * 120 + 60
        source = Image.open(path).convert("RGBA").crop((0, 0, source_size[0], source_size[1]))
        displayed = source.resize(display_size, Image.Resampling.NEAREST)
        position = (center_x - display_size[0] // 2, 62)
        canvas.alpha_composite(displayed, position)
        label_width = draw.textbbox((0, 0), label, font=font)[2]
        scale_width = draw.textbbox((0, 0), scale_label, font=font)[2]
        draw.text((center_x - label_width // 2, 12), label, font=font, fill=(235, 225, 246, 255))
        draw.text((center_x - scale_width // 2, 32), scale_label, font=font, fill=(255, 225, 106, 255))
    canvas.save(QC / "pixel-scale-calibration-v3.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)
    build_card_front().save(RUNTIME / "card_front_v3.png")
    save_card_back()
    save_suit_atlas()
    save_small_suit_atlas()
    save_rank_atlas()
    save_royal_atlas()
    save_sprites()
    save_background()
    save_qc_sheet()
    save_all_cards_qc()
    save_animation_qc()
    save_scale_calibration_qc()
    contract = {
        "version": "trump_v3",
        "card": [72, 100],
        "suitCell": [12, 12],
        "smallSuitCell": [10, 10],
        "smallSuitGlyph": [8, 8],
        "smallSuitClubSource": "club_lobe_v2_raw.png (reference)",
        "smallSuitClubRuntimeMask": "square-lobe-8x8",
        "rankCell": [18, 18],
        "rankOrder": ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"],
        "rankRows": ["black", "red"],
        "royalCell": [48, 60],
        "royalOrder": ["black-J", "black-Q", "black-K", "red-J", "red-Q", "red-K"],
        "dealer": {"cell": [64, 64], "idle": 4, "deal": 6, "win": 4, "lose": 4},
        "player": {"cell": [48, 48], "idle": 4, "win": 4, "lose": 4},
        "chipFx": {"cell": [24, 24], "frames": 4},
        "filter": "nearest-neighbor at runtime",
    }
    (SOURCE / "pipeline-meta.json").write_text(
        json.dumps(contract, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
