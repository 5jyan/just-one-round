from pathlib import Path
from PIL import Image, ImageDraw

SIZE = 32
FRAMES = 4
OUT = Path(__file__).with_name('ant_crawler_sheet.png')

# The ant is intentionally hand-authored at the runtime pixel scale so the
# silhouette stays legible against the dirt background without introducing
# anti-aliased edges or a second visual style.
BG = (0, 0, 0, 0)
DARK = (50, 24, 16, 255)
MID = (102, 45, 23, 255)
WARM = (166, 78, 30, 255)
HIGHLIGHT = (226, 137, 54, 255)

sheet = Image.new('RGBA', (SIZE * FRAMES, SIZE), BG)
for frame in range(FRAMES):
    draw = ImageDraw.Draw(sheet)
    ox = frame * SIZE
    stride = frame % 2

    def rect(x0, y0, x1, y1, color):
        draw.rectangle((ox + x0, y0, ox + x1, y1), fill=color)

    def line(points, color, width=1):
        draw.line([(ox + x, y) for x, y in points], fill=color, width=width)

    # Tiny ground shadow makes the crawler read as part of the scene.
    rect(9, 25, 24, 26, (40, 21, 15, 145))
    rect(12, 27, 21, 27, (40, 21, 15, 80))

    # Abdomen, thorax, and head: a clear three-part ant silhouette.
    rect(8, 14, 15, 21, DARK)
    rect(9, 13, 15, 20, MID)
    rect(10, 14, 14, 18, WARM)
    rect(14, 15, 19, 21, DARK)
    rect(15, 15, 18, 19, MID)
    rect(16, 16, 18, 18, HIGHLIGHT)
    rect(18, 11, 24, 18, DARK)
    rect(19, 11, 23, 16, MID)
    rect(20, 12, 22, 14, WARM)
    rect(22, 15, 24, 17, HIGHLIGHT)
    rect(23, 14, 24, 15, DARK)  # mandible

    # Eye and two antennae.
    rect(21, 12, 22, 13, (255, 218, 122, 255))
    line([(20, 11), (19, 8), (17, 7)], DARK, 1)
    line([(22, 11), (23, 8), (25, 7)], DARK, 1)
    rect(16, 6, 17, 7, HIGHLIGHT)
    rect(25, 6, 26, 7, HIGHLIGHT)

    # Six articulated legs. Alternate frames shift the feet by one pixel to
    # make the insect visibly crawl while it waits for the target.
    if stride == 0:
        legs = [
            (14, 16, 10, 13), (15, 18, 10, 21), (15, 20, 12, 24),
            (17, 16, 21, 13), (17, 18, 22, 21), (17, 20, 20, 24),
        ]
    else:
        legs = [
            (14, 16, 11, 12), (15, 18, 11, 22), (15, 20, 13, 24),
            (17, 16, 22, 14), (17, 18, 23, 20), (17, 20, 21, 25),
        ]
    for x0, y0, x1, y1 in legs:
        line([(x0, y0), (x1, y1)], DARK, 2)
        # A warm foot pixel keeps the motion visible at 1x display scale.
        rect(x1, y1, x1 + 1, y1 + 1, WARM)

    # A pair of small abdominal highlights gives the crawler a readable rhythm.
    rect(10 + stride, 16, 11 + stride, 17, HIGHLIGHT)
    rect(12 + stride, 19, 13 + stride, 20, MID)

sheet.save(OUT)
print(OUT)
