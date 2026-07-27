from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "artifacts/app_store/raw"
OUT = ROOT / "artifacts/app_store/final"
PIXEL_FONT = ROOT / "assets/fonts/Galmuri11-Bold.ttf"
BODY_FONT = Path("/System/Library/Fonts/AppleSDGothicNeo.ttc")

W, H = 1290, 2796

NAVY = "#101827"
DEEP = "#09101d"
SURFACE = "#1d2a3d"
SURFACE_LIGHT = "#2c3c52"
BORDER = "#9cb3c9"
CREAM = "#fff4d6"
MUTED = "#a9b8c7"
YELLOW = "#ffd23f"
ORANGE = "#ff873a"
ORANGE_DARK = "#ed642b"
MINT = "#54d6a1"
PURPLE = "#5a2d82"
PURPLE_DEEP = "#281632"
CYAN = "#25e4f2"


def pixel(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(PIXEL_FONT), size)


def body(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(BODY_FONT), size)


def load(name: str) -> Image.Image:
    return Image.open(RAW / name).convert("RGB")


def rounded(image: Image.Image, radius: int) -> Image.Image:
    image = image.convert("RGBA")
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1),
        radius=radius,
        fill=255,
    )
    result = Image.new("RGBA", image.size)
    result.paste(image, (0, 0), mask)
    return result


def background(top: str, bottom: str, dots: str) -> Image.Image:
    image = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(image)
    c0 = tuple(int(top[i : i + 2], 16) for i in (1, 3, 5))
    c1 = tuple(int(bottom[i : i + 2], 16) for i in (1, 3, 5))
    for y in range(H):
        t = y / (H - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))
        draw.line((0, y, W, y), fill=color)
    for y in range(72, H, 104):
        offset = 46 if (y // 104) % 2 else 0
        for x in range(-20 + offset, W, 104):
            draw.rectangle((x, y, x + 5, y + 5), fill=dots)
    return image


def header(
    canvas: Image.Image,
    title_lines: list[str],
    subtitle_lines: list[str],
    *,
    label: str,
    title_color: str = CREAM,
    subtitle_color: str = CREAM,
    label_fill: str = NAVY,
    label_text: str = YELLOW,
) -> None:
    draw = ImageDraw.Draw(canvas)
    label_font = pixel(40)
    bbox = draw.textbbox((0, 0), label, font=label_font)
    lw = bbox[2] - bbox[0]
    draw.rounded_rectangle((74, 70, 74 + lw + 54, 145), radius=18, fill=label_fill)
    draw.text((101, 89), label, font=label_font, fill=label_text)

    title_font = pixel(104 if len(title_lines) == 1 else 90)
    y = 198
    for line in title_lines:
        draw.text((72, y), line, font=title_font, fill=title_color)
        y += 126

    subtitle_font = body(47)
    y += 24
    for line in subtitle_lines:
        draw.text((76, y), line, font=subtitle_font, fill=subtitle_color)
        y += 65


def clean_apple_home() -> Image.Image:
    screen = load("apple-home.png")
    d = ImageDraw.Draw(screen)
    # Replace developer-only preview values with plausible representative content.
    d.rectangle((36, 1795, 1173, 2150), fill=NAVY)
    d.text((48, 1818), "사과게임", font=pixel(56), fill=CREAM)
    d.text((48, 1948), "오늘 93명 도전 중 · 현재 최고 124개", font=body(34), fill=MUTED)
    d.text((48, 2035), "내 기록 84개 · 17등", font=body(37), fill=MINT)
    d.rectangle((0, 2540, screen.width, screen.height), fill=NAVY)
    return screen


def phone(screen: Image.Image, width: int, *, cream_frame: bool = True) -> Image.Image:
    height = round(width * screen.height / screen.width)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)
    screen = rounded(screen, max(52, width // 12))
    bezel = max(22, width // 30)
    frame = Image.new(
        "RGBA",
        (screen.width + bezel * 2, screen.height + bezel * 2),
        (0, 0, 0, 0),
    )
    d = ImageDraw.Draw(frame)
    outer = CREAM if cream_frame else "#151515"
    d.rounded_rectangle(
        (0, 0, frame.width - 1, frame.height - 1),
        radius=max(72, width // 9),
        fill=outer,
        outline=DEEP,
        width=max(8, width // 85),
    )
    d.rounded_rectangle(
        (
            bezel - 5,
            bezel - 5,
            frame.width - bezel + 4,
            frame.height - bezel + 4,
        ),
        radius=max(60, width // 11),
        fill=DEEP,
    )
    frame.alpha_composite(screen, (bezel, bezel))
    return frame


def paste_with_shadow(
    canvas: Image.Image,
    art: Image.Image,
    x: int,
    y: int,
    *,
    angle: float = 0,
    shadow_opacity: int = 135,
) -> None:
    if angle:
        art = art.rotate(
            angle,
            resample=Image.Resampling.BICUBIC,
            expand=True,
            fillcolor=(0, 0, 0, 0),
        )
    alpha = art.getchannel("A")
    blur = alpha.filter(ImageFilter.GaussianBlur(34))
    shadow = Image.new("RGBA", art.size, (4, 10, 18, shadow_opacity))
    shadow.putalpha(blur.point(lambda p: round(p * shadow_opacity / 255)))
    base = canvas.convert("RGBA")
    base.alpha_composite(shadow, (x + 28, y + 42))
    base.alpha_composite(art, (x, y))
    canvas.paste(base.convert("RGB"))


def make_page_1() -> Image.Image:
    canvas = background(ORANGE, ORANGE_DARK, "#ff9f61")
    header(
        canvas,
        ["하루에 딱 한 판!"],
        ["매일 공개되는 미니게임에", "도전하세요"],
        label="딱한판만",
    )
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((974, 69, 1214, 145), radius=18, fill=NAVY)
    draw.text((1022, 88), "1 DAY", font=pixel(40), fill=CYAN)
    art = phone(clean_apple_home(), 825)
    rotated = art.rotate(
        6.5,
        resample=Image.Resampling.BICUBIC,
        expand=True,
        fillcolor=(0, 0, 0, 0),
    )
    paste_with_shadow(canvas, rotated, (W - rotated.width) // 2 + 55, 620)
    draw = ImageDraw.Draw(canvas)
    draw.polygon([(0, 2540), (420, 2395), (540, H), (0, H)], fill=YELLOW)
    draw.rectangle((0, H - 34, W, H), fill=NAVY)
    return canvas


def game_preview(name: str, title: str, accent: str) -> Image.Image:
    source = load(name)
    crop = source.crop((48, 340, 1158, 1815))
    card = Image.new("RGB", (535, 770), SURFACE)
    d = ImageDraw.Draw(card)
    preview = crop.resize((487, 647), Image.Resampling.LANCZOS)
    card.paste(preview, (24, 24))
    d.rectangle((24, 670, 511, 744), fill=DEEP)
    d.rectangle((24, 670, 34, 744), fill=accent)
    title_font = pixel(34)
    title_box = d.textbbox((0, 0), title, font=title_font)
    title_width = title_box[2] - title_box[0]
    d.text(((535 - title_width) / 2, 686), title, font=title_font, fill=CREAM)
    return rounded(card, 30)


def make_page_2() -> Image.Image:
    canvas = background(NAVY, DEEP, "#202d41")
    header(
        canvas,
        ["오늘은 어떤 게임?"],
        ["매일 랜덤으로 오늘의 미니게임이", "공개돼요"],
        label="RANDOM",
        label_fill=YELLOW,
        label_text=NAVY,
    )
    cards = [
        game_preview("apple-home.png", "사과게임", "#ff4f4f"),
        game_preview("gravity-home.png", "중력 스위치", "#8de04f"),
        game_preview("dung-home.png", "똥피하기", "#27cfda"),
        game_preview("tap50-home.png", "탭50", "#ee43cb"),
    ]
    positions = [(72, 690), (683, 690), (72, 1545), (683, 1545)]
    for card, (x, y) in zip(cards, positions):
        paste_with_shadow(canvas, card, x, y, shadow_opacity=100)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((334, 2440, 956, 2548), radius=28, fill=YELLOW)
    d.text((404, 2470), "오늘의 게임은 단 하나", font=pixel(42), fill=NAVY)
    return canvas


def make_page_3() -> Image.Image:
    canvas = background("#f4e7ca", "#e2ceb0", "#ead7ba")
    header(
        canvas,
        ["보고 시작하면", "덜 억울해요"],
        ["조작법과 종료 조건을", "시작 전에 확인하세요"],
        label="HOW TO PLAY",
        title_color=NAVY,
        subtitle_color="#39485b",
        label_fill=NAVY,
        label_text=YELLOW,
    )
    art = phone(load("dung-guide-page1.png"), 855, cream_frame=False)
    paste_with_shadow(canvas, art, (W - art.width) // 2, 735, angle=-2.2)
    return canvas


def make_page_4() -> Image.Image:
    canvas = background(PURPLE, PURPLE_DEEP, "#704093")
    header(
        canvas,
        ["오직 한 번의 기회"],
        ["한 번의 실수가", "오늘의 기록을 바꿔요"],
        label="ONE CHANCE",
        label_fill=YELLOW,
        label_text=NAVY,
    )
    art = phone(load("gravity-gameplay.png"), 865)
    paste_with_shadow(canvas, art, (W - art.width) // 2 + 34, 625, angle=4.0)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((72, 2460, 505, 2568), radius=25, fill=YELLOW)
    d.text((126, 2490), "TAP TO FLIP", font=pixel(42), fill=NAVY)
    return canvas


def representative_ranking() -> Image.Image:
    screen = load("ranking-apple.png")
    d = ImageDraw.Draw(screen)
    d.rectangle((0, 145, screen.width, screen.height), fill=SURFACE)
    d.text((56, 166), "DAILY LEADERBOARD", font=pixel(28), fill=YELLOW)
    d.text((56, 215), "오늘의 랭킹", font=pixel(68), fill=CREAM)
    d.text((1080, 198), "×", font=body(64), fill=CREAM)

    # Summary
    values = [("93명", "오늘 도전자"), ("124개", "현재 최고"), ("17등", "내 순위")]
    centers = [200, 603, 1006]
    for i, ((value, label), cx) in enumerate(zip(values, centers)):
        vb = d.textbbox((0, 0), value, font=pixel(64))
        d.text((cx - (vb[2] - vb[0]) / 2, 345), value, font=pixel(64), fill=CREAM)
        lb = d.textbbox((0, 0), label, font=body(31))
        d.text((cx - (lb[2] - lb[0]) / 2, 435), label, font=body(31), fill=MUTED)
        if i < 2:
            d.rectangle((400 + i * 403, 335, 403 + i * 403, 488), fill=SURFACE_LIGHT)

    d.text((56, 555), "전체 랭킹", font=pixel(50), fill=CREAM)
    d.text((920, 573), "ALL PLAYERS", font=pixel(26), fill=YELLOW)

    rows = [
        (1, "작은공룡", "124개"),
        (2, "졸린감자", "117개"),
        (3, "한번만더", "109개"),
        (4, "공룡발자국", "103개"),
        (5, "퇴근요정", "98개"),
        (None, "•••", ""),
        (16, "말랑주먹", "86개"),
        (17, "딱한판만", "84개"),
        (18, "느린번개", "82개"),
    ]
    y = 655
    row_h = 148
    for rank, name, score in rows:
        if rank is None:
            d.text((560, y + 28), name, font=body(40), fill=MUTED)
            y += 105
            continue
        is_me = rank == 17
        fill = "#4d5046" if is_me else DEEP
        outline = YELLOW if is_me else SURFACE_LIGHT
        d.rectangle((56, y, 1150, y + row_h), fill=fill, outline=outline, width=4)
        rank_color = YELLOW if rank == 1 else "#c27b0d" if rank == 3 else BORDER
        d.text((92, y + 41), str(rank), font=pixel(48), fill=rank_color)
        d.text((226, y + 46), name, font=body(37), fill=CREAM if is_me else MUTED)
        if is_me:
            d.rectangle((468, y + 45, 535, y + 105), fill=YELLOW)
            d.text((486, y + 52), "나", font=pixel(28), fill=NAVY)
        sb = d.textbbox((0, 0), score, font=pixel(42))
        d.text((1100 - (sb[2] - sb[0]), y + 43), score, font=pixel(42), fill=MINT)
        y += row_h + 22
    return screen


def make_page_5() -> Image.Image:
    canvas = background(ORANGE, "#d94b30", "#ff9f61")
    header(
        canvas,
        ["오늘 몇 등까지", "갈 수 있을까?"],
        ["같은 게임에 도전한 사람들과", "기록으로 승부하세요"],
        label="DAILY RANK",
    )
    art = phone(representative_ranking(), 865)
    paste_with_shadow(canvas, art, (W - art.width) // 2, 725, angle=-1.8)
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pages = [
        ("01-daily-one-round.png", make_page_1()),
        ("02-random-games.png", make_page_2()),
        ("03-how-to-play.png", make_page_3()),
        ("04-gravity-gameplay.png", make_page_4()),
        ("05-daily-ranking.png", make_page_5()),
    ]
    for name, image in pages:
        image.convert("RGB").save(OUT / name, format="PNG", optimize=True)
        print(OUT / name)


if __name__ == "__main__":
    main()
