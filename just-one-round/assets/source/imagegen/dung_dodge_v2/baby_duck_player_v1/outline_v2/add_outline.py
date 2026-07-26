from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageFilter


OUTLINE = (42, 25, 56, 255)


def add_outline(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    alpha = image.getchannel("A")
    solid = alpha.point(lambda value: 255 if value >= 128 else 0)
    expanded = solid.filter(ImageFilter.MaxFilter(3))
    outline_mask = ImageChops.subtract(expanded, solid)

    outlined = Image.new("RGBA", image.size, OUTLINE)
    canvas = Image.new("RGBA", image.size, (0, 0, 0, 0))
    canvas.alpha_composite(Image.composite(outlined, canvas, outline_mask))
    canvas.alpha_composite(image)
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: add_outline.py INPUT OUTPUT")
    add_outline(Path(sys.argv[1]), Path(sys.argv[2]))
