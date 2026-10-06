from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets/source/imagegen/net_boat_v2"
PROCESSED = SOURCE / "processed"
RUNTIME = ROOT / "assets/images/net_boat"
RUNTIME.mkdir(parents=True, exist_ok=True)


def rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


sail = rgba(PROCESSED / "boat_sail/sheet-transparent.png")
turn = rgba(PROCESSED / "boat_turn/sheet-transparent.png")
navigation = Image.new("RGBA", (384, 256))
for row in range(4):
    navigation.paste(sail.crop((0, row * 64, 256, (row + 1) * 64)), (0, row * 64))
    navigation.paste(turn.crop((0, row * 64, 128, (row + 1) * 64)), (256, row * 64))
navigation.save(RUNTIME / "boat_navigation_atlas.png", optimize=True)

success = rgba(PROCESSED / "boat_success/sheet-transparent.png")
failure = rgba(PROCESSED / "boat_failure/sheet-transparent.png")
result = Image.new("RGBA", (256, 128))
for index in range(4):
    source_x = (index % 2) * 64
    source_y = (index // 2) * 64
    result.paste(success.crop((source_x, source_y, source_x + 64, source_y + 64)), (index * 64, 0))
    result.paste(failure.crop((source_x, source_y, source_x + 64, source_y + 64)), (index * 64, 64))
result.save(RUNTIME / "boat_result_atlas.png", optimize=True)

for processed, output in (
    ("fish", "fish_atlas.png"),
    ("shark", "shark_atlas.png"),
    ("reef", "reef_modules_atlas.png"),
    ("net_fx", "net_capture_fx_atlas.png"),
):
    rgba(PROCESSED / processed / "sheet-transparent.png").save(
        RUNTIME / output, optimize=True
    )

background = Image.open(SOURCE / "raw/sea_background_raw.png").convert("RGB")
background = background.resize((360, 960), Image.Resampling.NEAREST)
background.save(RUNTIME / "sea_background.png", optimize=True)
