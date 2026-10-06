from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path(__file__).resolve().parent
RUNTIME = ROOT / "assets/images/net_boat"


def _sheet(name: str) -> Image.Image:
    return Image.open(SOURCE / name / "processed/sheet-transparent.png").convert("RGBA")


def _frame(sheet: Image.Image, index: int, cell: int) -> Image.Image:
    x = (index % 2) * cell
    y = (index // 2) * cell
    return sheet.crop((x, y, x + cell, y + cell))


def _center_crop(image: Image.Image, width: int, height: int) -> Image.Image:
    left = (image.width - width) // 2
    top = (image.height - height) // 2
    return image.crop((left, top, left + width, top + height))


def _strip(name: str, cell: int, height: int) -> Image.Image:
    source = _sheet(name)
    output = Image.new("RGBA", (cell * 4, height), (0, 0, 0, 0))
    for index in range(4):
        output.alpha_composite(
            _center_crop(_frame(source, index, cell), cell, height),
            (index * cell, 0),
        )
    return output


def _assert_frames(
    name: str,
    atlas: Image.Image,
    width: int,
    height: int,
    *,
    grid: bool = False,
) -> None:
    partial_alpha = 0
    for index in range(4):
        x = (index % 2) * width if grid else index * width
        y = (index // 2) * height if grid else 0
        frame = atlas.crop((x, y, x + width, y + height))
        bbox = frame.getbbox()
        if bbox is None:
            raise ValueError(f"{name} frame {index + 1} is empty")
        if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= width or bbox[3] >= height:
            raise ValueError(f"{name} frame {index + 1} touches edge: {bbox}")
        partial_alpha += sum(
            1 for alpha in frame.getchannel("A").getdata() if 0 < alpha < 255
        )
    if partial_alpha == 0:
        raise ValueError(f"{name} unexpectedly lost smooth alpha edges")


def _contact_sheet(atlases: list[tuple[str, Image.Image]]) -> None:
    width = max(image.width for _, image in atlases) + 56
    heights = [image.height + 34 for _, image in atlases]
    output = Image.new("RGBA", (width, sum(heights) + 16), (4, 17, 24, 255))
    draw = ImageDraw.Draw(output)
    y = 12
    for name, atlas in atlases:
        draw.text((12, y), name, fill=(255, 240, 190, 255))
        output.alpha_composite(atlas, (44, y + 18))
        y += atlas.height + 34
    output.save(SOURCE / "qc-contact-sheet.png", optimize=True)


def main() -> None:
    sardine = _sheet("sardine")
    piranha = _strip("piranha", 84, 84)
    marlin = _strip("marlin", 168, 114)
    if sardine.size != (168, 168):
        raise ValueError(f"Unexpected sardine sheet size: {sardine.size}")
    _assert_frames("sardine", sardine, 84, 84, grid=True)
    _assert_frames("piranha", piranha, 84, 84)
    _assert_frames("marlin", marlin, 168, 114)
    atlases = [("sardine", sardine), ("piranha", piranha), ("marlin", marlin)]
    RUNTIME.mkdir(parents=True, exist_ok=True)
    for name, atlas in atlases:
        atlas.save(RUNTIME / f"{name}_atlas.png", optimize=True)
    _contact_sheet(atlases)


if __name__ == "__main__":
    main()
