import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/apple_game_orchard_background"
RUNTIME = ROOT / "assets/images/apple_game/apple_game_background.png"
ARTIFACTS = ROOT / "artifacts/apple_game_orchard_background"
QC = SOURCE / "qc"


def main() -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)

    raw = Image.open(SOURCE / "orchard-background-raw-v2.png").convert("RGB")
    crop_top = 120
    crop_height = raw.height - crop_top
    crop_width = crop_height // 2
    crop_left = (raw.width - crop_width) // 2
    raw = raw.crop(
        (crop_left, crop_top, crop_left + crop_width, crop_top + crop_height)
    )

    background = raw.resize((360, 720), Image.Resampling.NEAREST)
    background.save(RUNTIME)
    background.save(ARTIFACTS / "orchard_background_360x720.png")
    background.resize((720, 1440), Image.Resampling.NEAREST).save(
        QC / "orchard_background_2x.png"
    )

    metadata = {
        "reference": (
            "/var/folders/6f/kxqn2_p531dc7fjqdh8__s3h0000gn/T/"
            "codex-clipboard-31240054-eee9-4c93-99ea-880792260274.png"
        ),
        "raw": str(SOURCE / "orchard-background-raw-v2.png"),
        "runtime": str(RUNTIME),
        "rawSize": [887, 1774],
        "sourceCrop": [crop_left, crop_top, crop_left + crop_width, 1774],
        "runtimeSize": [360, 720],
        "sampling": "nearest-neighbor",
        "composition": {
            "sky": [0, 55],
            "treeCanopy": [55, 660],
            "shortGrass": [660, 720],
            "board": [10, 64, 346, 656],
        },
    }
    (QC / "orchard_background_runtime.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
