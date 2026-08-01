from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/beat_the_dealer/trump_v2"
RUNTIME = ROOT / "assets/images/beat_the_dealer"
PROCESSED = SOURCE / "processed"
QC = SOURCE / "qc"
MAGENTA = (255, 0, 255)


def keyed(image: Image.Image, tolerance: int = 30) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _ = pixels[x, y]
            distance = abs(r - 255) + abs(g) + abs(b - 255)
            is_key = distance <= tolerance or (r >= 210 and g <= 80 and b >= 150)
            pixels[x, y] = (r, g, b, 0 if is_key else 255)
    return rgba


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("empty keyed image")
    return bbox


def fit_sprite(
    image: Image.Image,
    size: tuple[int, int],
    *,
    inset: int = 1,
    bottom: int = 1,
) -> Image.Image:
    crop = image.crop(alpha_bbox(image))
    usable_w = size[0] - inset * 2
    usable_h = size[1] - inset - bottom
    scale = min(usable_w / crop.width, usable_h / crop.height)
    resized = crop.resize(
        (max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
        Image.Resampling.NEAREST,
    )
    # Re-quantize after the creative-source reduction so runtime scaling stays crisp.
    alpha = resized.getchannel("A").point(lambda value: 255 if value >= 96 else 0)
    resized.putalpha(alpha)
    output = Image.new("RGBA", size)
    x = (size[0] - resized.width) // 2
    y = size[1] - bottom - resized.height
    output.alpha_composite(resized, (x, y))
    return output


def save_zoom(image: Image.Image, name: str, scale: int = 8) -> None:
    image.resize(
        (image.width * scale, image.height * scale),
        Image.Resampling.NEAREST,
    ).save(QC / name)


def process_background() -> None:
    raw = Image.open(SOURCE / "background/raw/background.png").convert("RGB")
    half = raw.resize((180, 420), Image.Resampling.LANCZOS)
    runtime = half.resize((360, 840), Image.Resampling.NEAREST)
    runtime.save(RUNTIME / "background_map_v2.png")
    runtime.save(PROCESSED / "background_map_v2.png")


def process_characters() -> None:
    raw = keyed(Image.open(SOURCE / "characters/raw/characters.png"))
    dealer = fit_sprite(raw.crop((140, 60, 980, 880)), (56, 56))
    player = fit_sprite(raw.crop((1060, 300, 1510, 890)), (40, 40))
    dealer.save(RUNTIME / "dealer_idle_v2.png")
    player.save(RUNTIME / "player_idle_v2.png")
    dealer.save(PROCESSED / "dealer_idle_v2.png")
    player.save(PROCESSED / "player_idle_v2.png")
    save_zoom(dealer, "dealer_idle_v2-8x.png")
    save_zoom(player, "player_idle_v2-8x.png")


def pixel_suit(kind: int, color: tuple[int, int, int, int]) -> Image.Image:
    # 8x8 code-native UI glyph; creative card decoration comes from Image Gen.
    masks = (
        ("00011000", "00111100", "01111110", "11111111", "11111111", "00111100", "00011000", "00111100"),
        ("01100110", "11111111", "11111111", "01111110", "00111100", "00011000", "00000000", "00000000"),
        ("00011000", "00111100", "01111110", "11111111", "01111110", "00111100", "00011000", "00000000"),
        ("00011000", "00111100", "10111101", "11111111", "00111100", "00011000", "00111100", "00000000"),
    )
    image = Image.new("RGBA", (8, 8))
    draw = ImageDraw.Draw(image)
    for y, row in enumerate(masks[kind]):
        for x, bit in enumerate(row):
            if bit == "1":
                draw.point((x, y), fill=color)
    return image


def process_cards() -> None:
    raw = keyed(Image.open(SOURCE / "cards/raw/card-art-atlas.png"))
    face_atlas = Image.new("RGBA", (96, 84))
    rows = ((32, 455), (468, 872), (875, 1250))
    for row_index, (top, bottom) in enumerate(rows):
        for column in range(4):
            left = column * raw.width // 4
            right = (column + 1) * raw.width // 4
            portrait = fit_sprite(
                raw.crop((left, top, right, bottom)),
                (24, 28),
                inset=1,
                bottom=1,
            )
            face_atlas.alpha_composite(portrait, (column * 24, row_index * 28))
    face_atlas.save(RUNTIME / "royal_faces_v2.png")
    face_atlas.save(PROCESSED / "royal_faces_v2.png")
    save_zoom(face_atlas, "royal_faces_v2-4x.png", scale=4)

    suits = Image.new("RGBA", (32, 8))
    for index in range(4):
        color = (40, 31, 53, 255) if index in (0, 3) else (201, 57, 72, 255)
        suits.alpha_composite(pixel_suit(index, color), (index * 8, 0))
    suits.save(RUNTIME / "suit_icons_v2.png")
    suits.save(PROCESSED / "suit_icons_v2.png")
    save_zoom(suits, "suit_icons_v2-8x.png")

    card_front = Image.new("RGBA", (32, 44), (248, 239, 210, 255))
    draw = ImageDraw.Draw(card_front)
    draw.rectangle((0, 0, 31, 43), fill=(43, 29, 54, 255))
    draw.rectangle((1, 1, 30, 42), fill=(211, 183, 130, 255))
    draw.rectangle((2, 2, 29, 41), fill=(255, 248, 224, 255))
    draw.point((3, 3), fill=(255, 255, 240, 255))
    card_front.save(RUNTIME / "card_front_v2.png")
    card_front.save(PROCESSED / "card_front_v2.png")

    back_crop = raw.crop((190, 1238, 482, 1510))
    card_back = fit_sprite(back_crop, (32, 44), inset=1, bottom=1)
    # Fill behind the generated motif so the back remains opaque.
    opaque_back = Image.new("RGBA", (32, 44), (36, 31, 65, 255))
    opaque_back.alpha_composite(card_back)
    opaque_back.save(RUNTIME / "card_back_v2.png")
    opaque_back.save(PROCESSED / "card_back_v2.png")

    chip = fit_sprite(raw.crop((510, 1220, 830, 1515)), (20, 20), inset=0, bottom=0)
    chip.save(RUNTIME / "coin_v2.png")
    chip.save(PROCESSED / "coin_v2.png")
    save_zoom(card_front, "card_front_v2-8x.png")
    save_zoom(opaque_back, "card_back_v2-8x.png")
    save_zoom(chip, "coin_v2-8x.png")


def write_metadata() -> None:
    metadata = {
        "pipeline": "built-in-imagegen-plus-deterministic-postprocess",
        "safeCore": [0, 0, 360, 640],
        "authoredWorld": [0, -100, 360, 840],
        "cameraCenter": [180, 320],
        "filter": "nearest-neighbor",
        "assets": {
            "background_map_v2.png": [360, 840],
            "dealer_idle_v2.png": [56, 56],
            "player_idle_v2.png": [40, 40],
            "card_front_v2.png": [32, 44],
            "card_back_v2.png": [32, 44],
            "suit_icons_v2.png": [32, 8],
            "royal_faces_v2.png": [96, 84],
            "coin_v2.png": [20, 20],
        },
        "display": {
            "dealer_idle_v2.png": [112, 112],
            "player_idle_v2.png": [80, 80],
            "card": [64, 88],
            "coin_v2.png": [40, 40],
        },
    }
    (SOURCE / "pipeline-meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def write_scale_comparison() -> None:
    comparison = Image.new("RGBA", (520, 150), (22, 18, 38, 255))
    draw = ImageDraw.Draw(comparison)
    samples = [
        ("dealer 56→112", RUNTIME / "dealer_idle_v2.png", (112, 112)),
        ("chick 40→80", RUNTIME / "player_idle_v2.png", (80, 80)),
        (
            "apple 42",
            ROOT / "assets/images/apple_game_v2/apple_faces_atlas.png",
            (42, 42),
        ),
        (
            "mite 48",
            ROOT
            / "assets/images/gravity_switch_v2/player_magnet_mite_sheet_v3.png",
            (48, 48),
        ),
    ]
    x = 12
    for label, path, display_size in samples:
        image = Image.open(path).convert("RGBA")
        if "atlas" in path.name or "sheet" in path.name:
            image = image.crop((0, 0, display_size[0], display_size[1]))
        image = image.resize(display_size, Image.Resampling.NEAREST)
        comparison.alpha_composite(image, (x, 116 - image.height))
        draw.text((x, 128), label, fill=(238, 230, 245, 255))
        x += max(display_size[0], 96) + 18
    comparison.save(QC / "pixel-scale-comparison.png")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    PROCESSED.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)
    process_background()
    process_characters()
    process_cards()
    write_metadata()
    write_scale_comparison()


if __name__ == "__main__":
    main()
