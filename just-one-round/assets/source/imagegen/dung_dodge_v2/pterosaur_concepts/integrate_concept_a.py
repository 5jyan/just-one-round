from collections import deque
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parents[3]
RUNTIME_BACKGROUND = ASSETS / "images" / "dung_dodge_v2" / "background_map.png"
SPRITE = ROOT / "processed" / "concept-a-runtime-large.png"
PROCESSED = ROOT / "processed"
QC = ROOT / "qc"
BACKUP = ROOT / "background-before-concept-a.png"
CLEAN_BACKGROUND = PROCESSED / "background-without-large-pterosaur.png"
COMPOSITE = PROCESSED / "background-with-concept-a.png"

OLD_PTEROSAUR_SEED = (220, 246)
SEARCH_BOUNDS = (120, 180, 310, 320)
SPRITE_POSITION = (95, 183)


def is_sky(pixel: tuple[int, int, int]) -> bool:
    red, green, blue = pixel
    return red < 70 and green > 125 and blue > 135 and green - red > 65 and blue - red > 80


def connected_non_sky_component(image: Image.Image) -> set[tuple[int, int]]:
    x0, y0, x1, y1 = SEARCH_BOUNDS
    candidates = {
        (x, y)
        for y in range(y0, y1)
        for x in range(x0, x1)
        if not is_sky(image.getpixel((x, y)))
    }
    if OLD_PTEROSAUR_SEED not in candidates:
        raise ValueError("Could not locate the embedded large pterosaur")

    component = {OLD_PTEROSAUR_SEED}
    queue = deque([OLD_PTEROSAUR_SEED])
    candidates.remove(OLD_PTEROSAUR_SEED)
    while queue:
        x, y = queue.popleft()
        for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if neighbor in candidates:
                candidates.remove(neighbor)
                component.add(neighbor)
                queue.append(neighbor)
    return component


def dilate(points: set[tuple[int, int]], radius: int) -> set[tuple[int, int]]:
    expanded: set[tuple[int, int]] = set()
    for x, y in points:
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                expanded.add((x + dx, y + dy))
    return expanded


def remove_embedded_pterosaur(source: Image.Image) -> Image.Image:
    clean = source.copy()
    mask = dilate(connected_non_sky_component(source), radius=2)

    row_colors: dict[int, tuple[int, int, int]] = {}
    for y in {point[1] for point in mask}:
        sky_pixels = [
            source.getpixel((x, y))
            for x in range(source.width)
            if (x, y) not in mask and is_sky(source.getpixel((x, y)))
        ]
        if not sky_pixels:
            raise ValueError(f"No clean sky samples found on row {y}")
        row_colors[y] = tuple(int(median(channel)) for channel in zip(*sky_pixels))

    for x, y in mask:
        if not (0 <= x < source.width and 0 <= y < source.height):
            continue
        base = row_colors[y]
        sample_x = (x + 127) % source.width
        sample = source.getpixel((sample_x, y))
        if is_sky(sample) and (sample_x, y) not in mask:
            sampled_row = row_colors[y]
            residual = tuple(max(-4, min(4, sample[i] - sampled_row[i])) for i in range(3))
            fill = tuple(max(0, min(255, base[i] + residual[i])) for i in range(3))
        else:
            fill = base
        clean.putpixel((x, y), fill)
    return clean


def make_qc(before: Image.Image, after: Image.Image) -> None:
    board = Image.new("RGB", (720, 960), (20, 24, 30))
    board.paste(before, (0, 0))
    board.paste(after, (360, 0))
    draw = ImageDraw.Draw(board)
    font = ImageFont.load_default(size=24)
    for x, label in ((12, "BEFORE"), (372, "CONCEPT A APPLIED")):
        bounds = draw.textbbox((0, 0), label, font=font)
        width = bounds[2] - bounds[0]
        draw.rounded_rectangle((x, 12, x + width + 20, 48), radius=8, fill=(24, 27, 38))
        draw.text((x + 10, 19), label, font=font, fill=(255, 246, 210))
    board.save(QC / "concept-a-background-before-after.png")


def main() -> None:
    PROCESSED.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)
    if not BACKUP.exists():
        Image.open(RUNTIME_BACKGROUND).convert("RGB").save(BACKUP)

    before = Image.open(BACKUP).convert("RGB")
    clean = remove_embedded_pterosaur(before)
    clean.save(CLEAN_BACKGROUND)

    sprite = Image.open(SPRITE).convert("RGBA")
    composite = clean.convert("RGBA")
    composite.alpha_composite(sprite, SPRITE_POSITION)
    composite = composite.convert("RGB")
    composite.save(COMPOSITE)
    composite.save(RUNTIME_BACKGROUND)
    make_qc(before, composite)


if __name__ == "__main__":
    main()
