from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "processed" / "clean.png"
OUTPUT = ROOT / "player-master-candidate-32.png"
DISPLAY_PREVIEW = ROOT / "player-master-candidate-64.png"
PIXEL_PREVIEW = ROOT / "player-master-candidate-8x.png"
CONTEXT_PREVIEW = ROOT / "player-master-context-preview.png"
BACKGROUND = ROOT.parents[3] / "images" / "dung_dodge_v2" / "background_map.png"
GROUND = ROOT.parents[3] / "images" / "dung_dodge_v2" / "ground_strip.png"
RUNTIME_DIR = ROOT.parents[3] / "images" / "dung_dodge_v2"

# Kept deliberately tiny so the character reads like authored pixel art at 32 px,
# rather than a detailed illustration that was merely downscaled.
PALETTE = (
    (62, 30, 58, 255),    # deep plum outline / pupil / mouth
    (177, 202, 54, 255),  # sour-lime body
    (112, 145, 48, 255),  # lower-body green
    (255, 239, 157, 255), # cream belly / eye / tooth
    (244, 85, 43, 255),   # tomato-orange back bumps
)


def color_distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


image = Image.open(SOURCE).convert("RGBA")
result = Image.new("RGBA", image.size, (0, 0, 0, 0))

for y in range(image.height):
    for x in range(image.width):
        red, green, blue, alpha = image.getpixel((x, y))
        if alpha < 128:
            continue
        result.putpixel(
            (x, y),
            min(PALETTE, key=lambda color: color_distance((red, green, blue), color[:3])),
        )

result.save(OUTPUT)
result.resize((64, 64), Image.Resampling.NEAREST).save(DISPLAY_PREVIEW)
result.resize((256, 256), Image.Resampling.NEAREST).save(PIXEL_PREVIEW)

# The game contract loads four 32x32 cells from a 2x2 sheet. Until dedicated
# motion frames are approved, repeat the accepted master without inventing
# unreviewed poses or allowing the anchor to jump.
sheet = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
for row in range(2):
    for column in range(2):
        sheet.alpha_composite(result, (column * 32, row * 32))
sheet.save(ROOT / "player-idle-sheet.png")
sheet.save(ROOT / "player-run-sheet.png")
sheet.save(RUNTIME_DIR / "player_idle_sheet.png")
sheet.save(RUNTIME_DIR / "player_run_sheet.png")

context = Image.open(BACKGROUND).convert("RGBA")
ground = Image.open(GROUND).convert("RGBA").resize(
    (360, 96),
    Image.Resampling.NEAREST,
)
context.alpha_composite(ground, (0, 544))
context.alpha_composite(
    result.resize((64, 64), Image.Resampling.NEAREST),
    (148, 480),
)
context.save(CONTEXT_PREVIEW)
