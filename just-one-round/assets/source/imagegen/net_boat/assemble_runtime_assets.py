from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets/source/imagegen/net_boat"
RUNTIME = ROOT / "assets/images/net_boat"
RUNTIME.mkdir(parents=True, exist_ok=True)


def rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


sail = rgba(SOURCE / "boat_sail_processed/sheet-transparent.png")
turn = rgba(SOURCE / "boat_turn_processed/sheet-transparent.png")
navigation = Image.new("RGBA", (192, 128))
for row in range(4):
    navigation.paste(sail.crop((0, row * 32, 128, (row + 1) * 32)), (0, row * 32))
    navigation.paste(turn.crop((0, row * 32, 64, (row + 1) * 32)), (128, row * 32))
navigation.save(RUNTIME / "boat_navigation_atlas.png", optimize=True)

result_source = rgba(SOURCE / "boat_result_processed/sheet-transparent.png")
result = Image.new("RGBA", (128, 64))
for row in range(2):
    left = result_source.crop((0, row * 32, 32, (row + 1) * 32))
    right = result_source.crop((32, row * 32, 64, (row + 1) * 32))
    for col, frame in enumerate((left, right, left, right)):
        result.paste(frame, (col * 32, row * 32))
result.save(RUNTIME / "boat_result_atlas.png", optimize=True)

for processed, output in (
    ("fish_processed", "fish_atlas.png"),
    ("shark_processed", "shark_atlas.png"),
    ("reef_processed", "reef_modules_atlas.png"),
    ("net_fx_processed", "net_capture_fx_atlas.png"),
):
    rgba(SOURCE / processed / "sheet-transparent.png").save(
        RUNTIME / output, optimize=True
    )

background = Image.open(SOURCE / "sea_background_raw.png").convert("RGB")
scaled_height = round(background.height * 180 / background.width)
background = background.resize((180, scaled_height), Image.Resampling.NEAREST)
top = max(0, (scaled_height - 480) // 2)
background.crop((0, top, 180, top + 480)).save(
    RUNTIME / "sea_background.png", optimize=True
)
