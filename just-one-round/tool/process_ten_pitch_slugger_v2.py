"""Prepare generated hitter sheets for the Sprite Forge chroma-key processor."""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/ten_pitch_slugger/slugger_v2"
GENERATED = Path.home() / ".codex/generated_images/01a0c149-8b79-78c1-b3f6-ab9d38d50ec4"
FILES = {
    "idle": "exec-6d27c0e6-c613-4f77-ab7d-6ebc917901e2.png",
    "swing": "exec-297945a5-0e5f-4ac0-a5e9-4ac350a5d381.png",
    "whiff": "exec-9e23ef25-21a7-44f3-9e23-9b7ae86c97f2.png",
    "result": "exec-fcd129ff-6b63-4d00-ad3d-c22fae4c4c57.png",
}

for action, filename in FILES.items():
    directory = SOURCE / action
    directory.mkdir(parents=True, exist_ok=True)
    original = directory / "raw-alpha.png"
    image = Image.open(original if original.exists() else GENERATED / filename).convert("RGBA")
    image.save(directory / "raw-alpha.png")
    background = Image.new("RGBA", image.size, (255, 0, 255, 255))
    background.alpha_composite(image)
    background.convert("RGB").save(directory / "raw.png")

    processed = directory / "processed/sheet-transparent.png"
    if processed.exists():
        sheet = Image.open(processed).convert("RGBA")
        pixels = sheet.load()
        for y in range(sheet.height):
            for x in range(sheet.width):
                red, green, blue, alpha = pixels[x, y]
                if alpha > 8 and red > 170 and blue > 130 and green < 100 and blue > red * 0.65:
                    pixels[x, y] = (red, green, blue, 0)
        sheet.save(processed)
        sheet.save(ROOT / f"assets/images/ten_pitch_slugger/batter_slugger_{action}_v2.png")
