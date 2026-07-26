from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SCREENSHOT = ROOT / "artifacts/app_store/main-screen.png"
OUTPUT = ROOT / "artifacts/app_store/main-app-store.png"
FONT = ROOT / "assets/fonts/Galmuri11-Bold.ttf"

WIDTH, HEIGHT = 1206, 2622
ORANGE = "#ff873a"
ORANGE_DARK = "#ee662b"
NAVY = "#0d1829"
CREAM = "#fff4d6"
YELLOW = "#ffd23f"


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1),
        radius=radius,
        fill=255,
    )
    result = Image.new("RGBA", image.size)
    result.paste(image, (0, 0), mask)
    return result


def make_phone() -> Image.Image:
    screen = Image.open(SCREENSHOT).convert("RGB")
    # The simulator account runs in test mode; keep the real UI capture while
    # removing the internal-only badge from the App Store artwork.
    screen_draw = ImageDraw.Draw(screen)
    screen_draw.rectangle((892, 1828, 1165, 1932), fill=NAVY)
    screen_width = 770
    screen_height = round(screen_width * screen.height / screen.width)
    screen = screen.resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    screen = rounded_image(screen.convert("RGBA"), 78)

    bezel = 28
    phone = Image.new(
        "RGBA",
        (screen.width + bezel * 2, screen.height + bezel * 2),
        (0, 0, 0, 0),
    )
    draw = ImageDraw.Draw(phone)
    draw.rounded_rectangle(
        (0, 0, phone.width - 1, phone.height - 1),
        radius=108,
        fill=CREAM,
        outline=NAVY,
        width=11,
    )
    draw.rounded_rectangle(
        (bezel - 5, bezel - 5, phone.width - bezel + 4, phone.height - bezel + 4),
        radius=84,
        fill=NAVY,
    )
    phone.alpha_composite(screen, (bezel, bezel))
    return phone


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas = Image.new("RGB", (WIDTH, HEIGHT), ORANGE)
    draw = ImageDraw.Draw(canvas)

    # Original template's bright orange field, with a little arcade texture.
    draw.polygon([(0, 1840), (WIDTH, 1510), (WIDTH, HEIGHT), (0, HEIGHT)], fill=ORANGE_DARK)
    for y in range(80, HEIGHT, 96):
        offset = 28 if (y // 96) % 2 else 0
        for x in range(-20 + offset, WIDTH, 96):
            draw.rectangle((x, y, x + 5, y + 5), fill="#ff9a55")

    label_font = ImageFont.truetype(str(FONT), 42)
    title_font = ImageFont.truetype(str(FONT), 112)
    subtitle_font = ImageFont.truetype(str(FONT), 49)

    label = "딱한판만"
    label_box = draw.textbbox((0, 0), label, font=label_font)
    label_w = label_box[2] - label_box[0]
    draw.rounded_rectangle((74, 78, 74 + label_w + 58, 151), radius=18, fill=NAVY)
    draw.text((103, 96), label, font=label_font, fill=YELLOW)

    draw.text((72, 222), "하루에 딱 한 판!", font=title_font, fill="white")
    draw.text((75, 378), "매일 새로운 게임에", font=subtitle_font, fill=CREAM)
    draw.text((75, 447), "도전하세요", font=subtitle_font, fill=CREAM)

    # A small score motif connects the promotional frame to the in-app arcade art.
    draw.rounded_rectangle((902, 78, 1137, 151), radius=18, fill=NAVY)
    draw.text((941, 96), "1 DAY", font=label_font, fill="#25e4f2")

    phone = make_phone()
    rotated = phone.rotate(
        7,
        resample=Image.Resampling.BICUBIC,
        expand=True,
        fillcolor=(0, 0, 0, 0),
    )
    shadow = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
    shadow_mask = rotated.getchannel("A").filter(ImageFilter.GaussianBlur(34))
    shadow.putalpha(shadow_mask)
    shadow_color = Image.new("RGBA", rotated.size, (6, 15, 27, 150))
    shadow_color.putalpha(shadow_mask.point(lambda p: round(p * 0.58)))

    x = (WIDTH - rotated.width) // 2 + 42
    y = 610
    canvas_rgba = canvas.convert("RGBA")
    canvas_rgba.alpha_composite(shadow_color, (x + 24, y + 46))
    canvas_rgba.alpha_composite(rotated, (x, y))

    # Bottom accent remains behind the device and gives the frame a finished edge.
    accent = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    accent_draw = ImageDraw.Draw(accent)
    accent_draw.polygon([(0, 2450), (420, 2320), (530, HEIGHT), (0, HEIGHT)], fill=YELLOW)
    accent_draw.rectangle((0, 2588, WIDTH, HEIGHT), fill=NAVY)
    canvas_rgba.alpha_composite(accent)

    canvas_rgba.convert("RGB").save(OUTPUT, quality=95)
    print(OUTPUT)


if __name__ == "__main__":
    main()
