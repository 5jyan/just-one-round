"""Align the approved victory sprite grids to western_duel's existing cells."""

from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
SOURCE = Path(__file__).resolve().parent
RUNTIME = ROOT / "assets/images/western_duel"


def write_atlas(source: Path, destination: Path, size, frame_transform):
    destination.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (size[0] * 2, size[1] * 3))
    for index in range(6):
        frame = Image.open(source / f"attack-{index + 1}.png").convert("RGBA")
        delivered = clean_magenta_fringe(frame_transform(frame))
        delivered.save(destination / f"frame_{index + 1:02}.png")
        atlas.alpha_composite(delivered, ((index % 2) * size[0], (index // 2) * size[1]))
    atlas.save(destination / "sheet-transparent.png")


def clean_magenta_fringe(image, *, min_alpha=32, alpha_scale=1):
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha < min_alpha or (
                red + blue > 40
                and green * 3 < min(red, blue)
                and max(red, blue) < min(red, blue) * 2
            ):
                pixels[x, y] = (0, 0, 0, 0)
            elif alpha_scale != 1:
                pixels[x, y] = (red, green, blue, min(255, alpha * alpha_scale))
    return image


def player(frame):
    # One shared transform preserves frame-to-frame anatomy. Its first frame
    # matches the v11 action atlas's body box and the offscreen viewport crop.
    scaled = frame.resize((844, 844), Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", (540, 1080))
    canvas.alpha_composite(scaled, (-148, 247))
    return canvas


def opponent(frame):
    # Same 128x184 cell/foot line as opponent_draw_fire_close.
    return frame.crop((28, 0, 156, 184))


def main():
    write_atlas(
        SOURCE / "player_victory",
        RUNTIME / "first_person/player_victory_v14",
        (540, 1080),
        player,
    )
    write_atlas(
        SOURCE / "opponent_victory",
        RUNTIME / "first_person/opponent_victory_v14",
        (128, 184),
        opponent,
    )
    smoke = RUNTIME / "fx/victory_smoke_v14"
    smoke.mkdir(parents=True, exist_ok=True)
    for name in ("sheet-transparent.png", *(f"fx-{i}.png" for i in range(1, 5))):
        image = clean_magenta_fringe(
            Image.open(SOURCE / "victory_smoke" / name).convert("RGBA"),
            min_alpha=2,
            alpha_scale=3,
        )
        target = smoke / (name if name.startswith("sheet") else f"frame_{int(name[3]) :02}.png")
        image.save(target)


if __name__ == "__main__":
    main()
