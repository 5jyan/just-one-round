from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
SOURCE_DIR = ROOT / "assets/source/imagegen/net_boat_v7"
RUNTIME_DIR = ROOT / "assets/images/net_boat"


def build_wake_atlas() -> None:
    output = Image.new("RGBA", (256, 32), (0, 0, 0, 0))
    frame_dir = SOURCE_DIR / "shark_wake_processed"
    for frame in range(4):
        source = Image.open(frame_dir / f"hover-{frame + 1}.png").convert("RGBA")
        # The processor normalizes to 64x64. Keep the centered 64x32 strip
        # used by Flame while retaining every authored wake pixel.
        wake = source.crop((0, 16, 64, 48))
        pixels = []
        for red, green, blue, alpha in wake.getdata():
            if alpha == 0:
                pixels.append((0, 0, 0, 0))
                continue
            light = max(red, green, blue)
            pixels.append(
                (
                    min(255, 95 + int(light * 0.45)),
                    min(255, 165 + int(light * 0.33)),
                    min(255, 185 + int(light * 0.27)),
                    int(alpha * 0.55),
                )
            )
        wake.putdata(pixels)
        output.alpha_composite(wake, (frame * 64, 0))
    output.save(RUNTIME_DIR / "shark_wake_atlas.png", optimize=True)


def build_shallower_fin_atlas() -> None:
    source = Image.open(RUNTIME_DIR / "shark_atlas.png").convert("RGBA")
    output = Image.new("RGBA", (256, 32), (0, 0, 0, 0))

    for frame in range(4):
        cell = source.crop((frame * 64, 0, (frame + 1) * 64, 48))
        mask = Image.new("L", cell.size, 0)
        draw = ImageDraw.Draw(mask)
        # Stop the visible base three source pixels earlier than v6. This
        # leaves the authored tip intact but makes the fin feel submerged.
        draw.polygon([(22, 18), (30, 6), (35, 6), (41, 18)], fill=255)
        alpha = Image.composite(
            cell.getchannel("A"), Image.new("L", cell.size, 0), mask
        )
        cell.putalpha(alpha)
        output.alpha_composite(cell.crop((0, 2, 64, 26)), (frame * 64, 4))

    output.save(RUNTIME_DIR / "shark_fin_atlas.png", optimize=True)


def main() -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    build_wake_atlas()
    build_shallower_fin_atlas()


if __name__ == "__main__":
    main()
