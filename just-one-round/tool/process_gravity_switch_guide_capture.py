from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (
    ROOT
    / "assets/source/runtime_capture/gravity_switch/current_runtime_live_app.jpg"
)
RUNTIME_DIR = ROOT / "assets/images/gravity_switch_v2"


def replace_player_with_runtime_background(image: Image.Image) -> Image.Image:
    cleaned = image.copy()
    # The player occupies x=60..130 and y=410..480 in the current iPhone 17
    # runtime capture. Copy the same corridor slice from immediately to its
    # right, including the floor seam, before adding animated runtime sprites.
    patch = image.crop((140, 410, 210, 480))
    cleaned.paste(patch, (60, 410))
    return cleaned


def main() -> None:
    capture = Image.open(SOURCE).convert("RGB")
    if capture.size != (350, 762):
        raise ValueError(f"unexpected runtime capture size: {capture.size}")

    cleaned = replace_player_with_runtime_background(capture)

    # 350 / 449 ~= 0.78, matching the established portrait home preview.
    home = cleaned.crop((0, 120, 350, 569))
    home.save(RUNTIME_DIR / "current_runtime_home.png", optimize=True)

    # Landscape crop centered on the real floor/ceiling corridor.
    guide = cleaned.crop((0, 245, 350, 505))
    guide.save(RUNTIME_DIR / "current_runtime_guide.png", optimize=True)


if __name__ == "__main__":
    main()
