from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[4]
SOURCE = Path(__file__).resolve().parent
RUNTIME = ROOT / "assets/images/net_boat"


def _source_frame(name: str, index: int, cell: int, label: str = "swim") -> Image.Image:
    path = SOURCE / name / "processed" / f"{label}-{index + 1}.png"
    image = Image.open(path).convert("RGBA")
    if image.size != (cell, cell):
        raise ValueError(f"{path} is {image.size}, expected {(cell, cell)}")
    return image


def _center_crop(image: Image.Image, width: int, height: int) -> Image.Image:
    left = (image.width - width) // 2
    top = (image.height - height) // 2
    return image.crop((left, top, left + width, top + height))


def _build_strip(name: str, source_cell: int, width: int, height: int) -> Image.Image:
    output = Image.new("RGBA", (width * 4, height), (0, 0, 0, 0))
    for index in range(4):
        frame = _center_crop(_source_frame(name, index, source_cell), width, height)
        output.alpha_composite(frame, (index * width, 0))
    return output


def _build_shark_fin_strip() -> Image.Image:
    output = Image.new("RGBA", (74 * 4, 38), (0, 0, 0, 0))
    for index in range(4):
        shark = _source_frame("shark", index, 74)
        # The processed shark has a stable center anchor. This mask exposes only
        # the dorsal fin and a thin waterline base, matching the gameplay hitbox.
        mask = Image.new("L", shark.size, 0)
        draw = ImageDraw.Draw(mask)
        draw.polygon([(26, 31), (33, 17), (42, 17), (49, 31)], fill=255)
        alpha = Image.composite(
            shark.getchannel("A"), Image.new("L", shark.size, 0), mask
        )
        shark.putalpha(alpha)
        fin = shark.crop((0, 3, 74, 41))
        output.alpha_composite(fin, (index * 74, 0))
    return output


def _recolor_wake(frame: Image.Image) -> Image.Image:
    pixels = []
    for red, green, blue, alpha in frame.getdata():
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
    frame.putdata(pixels)
    return frame


def _build_wake_strip() -> Image.Image:
    output = Image.new("RGBA", (72 * 4, 36), (0, 0, 0, 0))
    for index in range(4):
        frame = _source_frame("shark_wake", index, 72, label="hover")
        output.alpha_composite(_recolor_wake(_center_crop(frame, 72, 36)), (index * 72, 0))
    return output


def _save(image: Image.Image, filename: str) -> None:
    image.save(RUNTIME / filename, optimize=True)


def _build_qc_contact_sheet() -> None:
    names = [
        "sardine_atlas.png",
        "piranha_atlas.png",
        "marlin_atlas.png",
        "shark_fin_atlas.png",
        "shark_wake_atlas.png",
        "whale_atlas.png",
    ]
    atlases = [(name, Image.open(RUNTIME / name).convert("RGBA")) for name in names]
    scale = 2
    width = max(image.width * scale for _, image in atlases) + 48
    heights = [max(44, image.height * scale + 24) for _, image in atlases]
    sheet = Image.new("RGBA", (width, sum(heights) + 16), (5, 18, 25, 255))
    draw = ImageDraw.Draw(sheet)
    y = 12
    for (name, atlas), row_height in zip(atlases, heights):
        draw.text((12, y), name.removesuffix("_atlas.png"), fill=(255, 240, 190, 255))
        enlarged = atlas.resize(
            (atlas.width * scale, atlas.height * scale), Image.Resampling.NEAREST
        )
        sheet.alpha_composite(enlarged, (36, y + 18))
        y += row_height
    sheet.save(SOURCE / "qc-contact-sheet.png", optimize=True)


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    sardine = Image.open(
        SOURCE / "sardine/processed/sheet-transparent.png"
    ).convert("RGBA")
    if sardine.size != (56, 56):
        raise ValueError(f"sardine sheet is {sardine.size}, expected (56, 56)")
    _save(sardine, "sardine_atlas.png")
    _save(_build_strip("piranha", 28, 28, 28), "piranha_atlas.png")
    _save(_build_strip("marlin", 56, 56, 38), "marlin_atlas.png")
    _save(_build_shark_fin_strip(), "shark_fin_atlas.png")
    _save(_build_wake_strip(), "shark_wake_atlas.png")
    _save(_build_strip("whale", 160, 160, 106), "whale_atlas.png")
    _build_qc_contact_sheet()


if __name__ == "__main__":
    main()
