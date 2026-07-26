import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
GENERATED = Path(
    "/Users/saulpark/.codex/generated_images/"
    "019f93be-bc77-7a53-bd07-0c7171ae892c/"
    "call_WULvL64EhYCSSZio4lCfDGNX.png"
)
SOURCE = ROOT / "assets/source/imagegen/apple_game_v2/background_phone_overscan"
RUNTIME = ROOT / "assets/images/apple_game_v2/apple_game_background.png"

RUNTIME_SIZE = (408, 880)
WORLD_RECT = (-24, -80, 384, 800)
SAFE_CORE = (0, 0, 360, 720)
MAX_PHONE_VIEWPORT = (0, -60, 360, 780)
FONT = ROOT / "assets/fonts/Galmuri11-Bold.ttf"


def main() -> None:
    SOURCE.mkdir(parents=True, exist_ok=True)
    raw_copy = SOURCE / "raw-background.png"
    shutil.copy2(GENERATED, raw_copy)

    raw = Image.open(raw_copy).convert("RGB")
    target_ratio = RUNTIME_SIZE[0] / RUNTIME_SIZE[1]
    crop_height = round(raw.width / target_ratio)
    crop_top = (raw.height - crop_height) // 2
    crop_box = (0, crop_top, raw.width, crop_top + crop_height)
    cropped = raw.crop(crop_box)
    background = cropped.resize(RUNTIME_SIZE, Image.Resampling.NEAREST)
    background.save(RUNTIME)

    qc = SOURCE / "qc"
    qc.mkdir(exist_ok=True)
    background.resize((816, 1760), Image.Resampling.NEAREST).save(
        qc / "apple_game_background_2x.png"
    )
    _write_gameplay_previews(background, qc)

    metadata = {
        "raw": str(raw_copy),
        "runtime": str(RUNTIME),
        "rawSize": list(raw.size),
        "sourceCrop": list(crop_box),
        "runtimeSize": list(RUNTIME_SIZE),
        "sampling": "nearest-neighbor",
        "worldRect": list(WORLD_RECT),
        "gameplaySafeCore": list(SAFE_CORE),
        "maximumTargetViewport": list(MAX_PHONE_VIEWPORT),
        "cameraCenter": [180, 360],
        "supportedPortraitAspectRatios": ["16:9", "21:9"],
        "scopeExceptions": [
            "foldable unfolded displays",
            "flip cover displays",
            "tablets",
        ],
    }
    (SOURCE / "pipeline-meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _write_gameplay_previews(background: Image.Image, qc: Path) -> None:
    atlas = Image.open(
        ROOT / "assets/images/apple_game_v2/apple_faces_atlas.png"
    ).convert("RGBA")
    font = ImageFont.truetype(str(FONT), 18)
    values = [
        [2, 8, 1, 3, 1, 2, 7, 6],
        [2, 6, 1, 5, 2, 4, 4, 3],
        [6, 9, 9, 3, 2, 1, 1, 5],
        [1, 9, 3, 7, 5, 1, 1, 4],
        [9, 6, 7, 4, 5, 7, 6, 8],
        [5, 4, 2, 3, 2, 5, 8, 1],
        [7, 5, 8, 5, 8, 9, 1, 2],
        [7, 5, 2, 7, 6, 3, 2, 9],
        [3, 4, 8, 9, 4, 7, 1, 6],
        [5, 8, 3, 2, 1, 2, 1, 7],
        [3, 1, 7, 2, 5, 7, 3, 4],
        [8, 2, 4, 6, 3, 1, 9, 5],
        [4, 6, 2, 8, 1, 9, 3, 7],
        [1, 5, 9, 2, 6, 4, 8, 3],
    ]
    viewports = {
        "canonical_360x720": (0, 0, 360, 720),
        "iphone_17_360x780": (0, -30, 360, 750),
        "tall_phone_360x840": (0, -60, 360, 780),
    }
    for name, viewport in viewports.items():
        left, top, right, bottom = viewport
        source_box = (
            left - WORLD_RECT[0],
            top - WORLD_RECT[1],
            right - WORLD_RECT[0],
            bottom - WORLD_RECT[1],
        )
        preview = background.crop(source_box).convert("RGBA")
        draw = ImageDraw.Draw(preview)
        for row, row_values in enumerate(values):
            for column, value in enumerate(row_values):
                world_x = 12 + column * 42
                world_y = 98 + row * 42
                atlas_column = (value - 1) % 3
                atlas_row = (value - 1) // 3
                apple = atlas.crop(
                    (
                        atlas_column * 42,
                        atlas_row * 42,
                        (atlas_column + 1) * 42,
                        (atlas_row + 1) * 42,
                    )
                )
                x = world_x - left
                y = world_y - top
                preview.alpha_composite(apple, (x, y))
                label = str(value)
                text_box = draw.textbbox((0, 0), label, font=font, stroke_width=1)
                text_width = text_box[2] - text_box[0]
                text_height = text_box[3] - text_box[1]
                draw.text(
                    (
                        x + (42 - text_width) / 2,
                        y + (42 - text_height) / 2 + 1,
                    ),
                    label,
                    font=font,
                    fill="#FFF3C4",
                    stroke_width=1,
                    stroke_fill="#591F2C",
                )
        preview.save(qc / f"gameplay_{name}.png")


if __name__ == "__main__":
    main()
