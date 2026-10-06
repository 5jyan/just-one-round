from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets/images/net_boat/shark_atlas.png"
OUTPUT = ROOT / "assets/images/net_boat/shark_fin_atlas.png"


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    output = Image.new("RGBA", (256, 32), (0, 0, 0, 0))

    for frame in range(4):
        cell = source.crop((frame * 64, 0, (frame + 1) * 64, 48))
        # Preserve the authored dorsal-fin pixels while masking away every
        # part of the head, body and tail. The low base stays just below the
        # water line, so only the fin silhouette reads during play.
        mask = Image.new("L", cell.size, 0)
        draw = ImageDraw.Draw(mask)
        draw.polygon([(20, 21), (30, 6), (35, 6), (43, 21)], fill=255)
        alpha = cell.getchannel("A")
        alpha = Image.composite(alpha, Image.new("L", cell.size, 0), mask)
        cell.putalpha(alpha)

        fin = cell.crop((0, 2, 64, 26))
        output.alpha_composite(fin, (frame * 64, 4))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    output.save(OUTPUT, optimize=True)


if __name__ == "__main__":
    main()
