from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path(__file__).resolve().parent
RUNTIME = ROOT / "assets/images/net_boat"


def _harden_and_quantize(image: Image.Image, colors: int) -> Image.Image:
    source = image.convert("RGBA")
    alpha = source.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    rgb = Image.new("RGB", source.size, (4, 17, 24))
    rgb.paste(source.convert("RGB"), mask=alpha)
    quantized = rgb.quantize(
        colors=colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    ).convert("RGBA")
    quantized.putalpha(alpha)
    return quantized


def _frame(sheet: Image.Image, index: int, cell: int) -> Image.Image:
    x = (index % 2) * cell
    y = (index // 2) * cell
    return sheet.crop((x, y, x + cell, y + cell))


def _center_crop(image: Image.Image, width: int, height: int) -> Image.Image:
    left = (image.width - width) // 2
    top = (image.height - height) // 2
    return image.crop((left, top, left + width, top + height))


def _processed_sheet(name: str, colors: int) -> Image.Image:
    path = SOURCE / name / "processed/sheet-transparent.png"
    return _harden_and_quantize(Image.open(path), colors)


def _build_sardine() -> Image.Image:
    sheet = _processed_sheet("sardine", 12)
    if sheet.size != (56, 56):
        raise ValueError(f"Unexpected sardine sheet size: {sheet.size}")
    return sheet


def _build_strip(name: str, colors: int, cell: int, height: int) -> Image.Image:
    source = _processed_sheet(name, colors)
    output = Image.new("RGBA", (cell * 4, height), (0, 0, 0, 0))
    for index in range(4):
        frame = _center_crop(_frame(source, index, cell), cell, height)
        output.alpha_composite(frame, (index * cell, 0))
    return output


def _assert_runtime_contract(
    name: str,
    atlas: Image.Image,
    cell_width: int,
    cell_height: int,
    grid: bool = False,
) -> None:
    for index in range(4):
        if grid:
            x = (index % 2) * cell_width
            y = (index // 2) * cell_height
        else:
            x = index * cell_width
            y = 0
        frame = atlas.crop((x, y, x + cell_width, y + cell_height))
        bbox = frame.getbbox()
        if bbox is None:
            raise ValueError(f"{name} frame {index + 1} is empty")
        if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= cell_width or bbox[3] >= cell_height:
            raise ValueError(f"{name} frame {index + 1} touches edge: {bbox}")
        if any(alpha not in (0, 255) for alpha in frame.getchannel("A").getdata()):
            raise ValueError(f"{name} frame {index + 1} has fractional alpha")


def _build_qc_contact_sheet(atlases: list[tuple[str, Image.Image]]) -> None:
    scale = 4
    width = max(image.width * scale for _, image in atlases) + 56
    heights = [image.height * scale + 34 for _, image in atlases]
    sheet = Image.new("RGBA", (width, sum(heights) + 16), (4, 17, 24, 255))
    draw = ImageDraw.Draw(sheet)
    y = 12
    for name, atlas in atlases:
        draw.text((12, y), name, fill=(255, 240, 190, 255))
        enlarged = atlas.resize(
            (atlas.width * scale, atlas.height * scale),
            Image.Resampling.NEAREST,
        )
        sheet.alpha_composite(enlarged, (44, y + 18))
        y += atlas.height * scale + 34
    sheet.save(SOURCE / "qc-contact-sheet.png", optimize=True)


def main() -> None:
    atlases = [
        ("sardine", _build_sardine()),
        ("piranha", _build_strip("piranha", 16, 28, 28)),
        ("marlin", _build_strip("marlin", 20, 56, 38)),
    ]
    _assert_runtime_contract("sardine", atlases[0][1], 28, 28, grid=True)
    _assert_runtime_contract("piranha", atlases[1][1], 28, 28)
    _assert_runtime_contract("marlin", atlases[2][1], 56, 38)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    for name, atlas in atlases:
        atlas.save(RUNTIME / f"{name}_atlas.png", optimize=True)
    _build_qc_contact_sheet(atlases)


if __name__ == "__main__":
    main()
