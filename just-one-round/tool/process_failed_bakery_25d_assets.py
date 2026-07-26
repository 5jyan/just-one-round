#!/usr/bin/env python3
"""Build runtime-ready Failed Bakery 2.5D assets from generated sources."""

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/failed_bakery_25d"
RUNTIME = ROOT / "assets/images/failed_bakery_25d"
ARTIFACTS = ROOT / "artifacts/failed_bakery_25d"


def nearest_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.NEAREST)


def alpha_crop(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("transparent frame has no visible pixels")
    return rgba.crop(bbox)


def remove_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = []
    for red, green, blue, _ in rgba.getdata():
        is_key = (
            red >= 200
            and blue >= 180
            and green <= 120
            and red + blue - green * 2 >= 220
        )
        pixels.append((red, green, blue, 0 if is_key else 255))
    rgba.putdata(pixels)
    return rgba


def split_grid(
    image: Image.Image,
    *,
    rows: int,
    columns: int,
) -> list[Image.Image]:
    frames = []
    for row in range(rows):
        top = round(row * image.height / rows)
        bottom = round((row + 1) * image.height / rows)
        for column in range(columns):
            left = round(column * image.width / columns)
            right = round((column + 1) * image.width / columns)
            frames.append(image.crop((left, top, right, bottom)))
    return frames


def fill_transparent_nearest(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    source = list(rgba.getdata())
    opaque = [
        (index % rgba.width, index // rgba.width, pixel)
        for index, pixel in enumerate(source)
        if pixel[3] >= 128
    ]
    if not opaque:
        raise ValueError("texture cell has no opaque pixels")
    output = []
    for index, pixel in enumerate(source):
        if pixel[3] >= 128:
            output.append((pixel[0], pixel[1], pixel[2], 255))
            continue
        x = index % rgba.width
        y = index // rgba.width
        _, _, nearest = min(
            opaque,
            key=lambda candidate: abs(candidate[0] - x) + abs(candidate[1] - y),
        )
        output.append((nearest[0], nearest[1], nearest[2], 255))
    rgba.putdata(output)
    return rgba


def assemble_grid(
    frames: list[Image.Image],
    *,
    columns: int,
    cell_size: tuple[int, int],
) -> Image.Image:
    rows = (len(frames) + columns - 1) // columns
    atlas = Image.new(
        "RGBA",
        (columns * cell_size[0], rows * cell_size[1]),
        (0, 0, 0, 0),
    )
    for index, frame in enumerate(frames):
        x = (index % columns) * cell_size[0]
        y = (index // columns) * cell_size[1]
        atlas.alpha_composite(frame, (x, y))
    return atlas


def process_texture_source(
    *,
    family: str,
    rows: int,
    columns: int,
    cell_size: tuple[int, int],
    frame_prefix: str,
    inset_fraction: tuple[float, float],
) -> list[Image.Image]:
    family_root = SOURCE / family
    processed = family_root / "processed"
    processed.mkdir(parents=True, exist_ok=True)
    raw_path = family_root / "raw/raw-atlas.png"
    raw = remove_magenta(Image.open(raw_path))
    frames = []
    metadata = {
        "input": str(raw_path.relative_to(ROOT)),
        "rows": rows,
        "columns": columns,
        "cell_size": list(cell_size),
        "chroma_key": "#FF00FF",
        "resample": "nearest-neighbor",
        "frames": [],
    }
    for index, source_frame in enumerate(
        split_grid(raw, rows=rows, columns=columns),
        start=1,
    ):
        cropped = alpha_crop(source_frame)
        inset_x = round(cropped.width * inset_fraction[0])
        inset_y = round(cropped.height * inset_fraction[1])
        if inset_x or inset_y:
            cropped = cropped.crop(
                (
                    inset_x,
                    inset_y,
                    cropped.width - inset_x,
                    cropped.height - inset_y,
                ),
            )
        texture = nearest_resize(cropped, cell_size)
        texture = fill_transparent_nearest(texture)
        output_path = processed / f"{frame_prefix}-{index}.png"
        texture.save(output_path)
        frames.append(texture)
        metadata["frames"].append(
            {
                "name": output_path.name,
                "source_size": list(source_frame.size),
                "crop_size": list(cropped.size),
                "output_size": list(texture.size),
                "opaque": texture.getchannel("A").getextrema() == (255, 255),
            },
        )
    (processed / "pipeline-meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return frames


def build_cake_atlases() -> None:
    top_frames = process_texture_source(
        family="cake-top-v2",
        rows=2,
        columns=3,
        cell_size=(40, 40),
        frame_prefix="cake-top",
        inset_fraction=(0.08, 0.08),
    )
    top_atlas = assemble_grid(top_frames, columns=3, cell_size=(40, 40))
    top_atlas.save(SOURCE / "cake-top-v2/processed/sheet-opaque.png")
    top_atlas.save(RUNTIME / "cake_top_atlas.png")

    face_frames = process_texture_source(
        family="cake-side-v2",
        rows=3,
        columns=2,
        cell_size=(40, 8),
        frame_prefix="cake-side",
        inset_fraction=(0.025, 0),
    )
    face_frames: list[Image.Image] = []
    plain_frames: list[Image.Image] = []
    processed = SOURCE / "cake-side-v2/processed"
    for index in range(1, 7):
        face = Image.open(processed / f"cake-side-{index}.png").convert("RGBA")
        face_frames.append(face)
        sample_left = face.width - max(4, face.width // 5)
        material_sample = face.crop((sample_left, 0, face.width, face.height))
        plain_frames.append(nearest_resize(material_sample, (40, 8)))

    assemble_grid(
        face_frames,
        columns=2,
        cell_size=(40, 8),
    ).save(RUNTIME / "cake_side_face_atlas.png")
    assemble_grid(
        plain_frames,
        columns=2,
        cell_size=(40, 8),
    ).save(RUNTIME / "cake_side_plain_atlas.png")


def build_background() -> None:
    raw = Image.open(SOURCE / "background/raw/raw-background.png").convert("RGB")
    target_ratio = 9 / 16
    current_ratio = raw.width / raw.height
    if current_ratio > target_ratio:
        crop_width = round(raw.height * target_ratio)
        left = (raw.width - crop_width) // 2
        raw = raw.crop((left, 0, left + crop_width, raw.height))
    else:
        crop_height = round(raw.width / target_ratio)
        top = (raw.height - crop_height) // 2
        raw = raw.crop((0, top, raw.width, top + crop_height))
    nearest_resize(raw, (180, 320)).save(RUNTIME / "bakery_background_3q.png")


def copy_processed_assets() -> None:
    copies = {
        SOURCE / "baker-reactions/processed/sheet-transparent.png":
            RUNTIME / "baker_reaction_sheet.png",
        SOURCE / "crumb-burst/processed/sheet-transparent.png":
            RUNTIME / "crumb_burst_sheet.png",
    }
    for source, destination in copies.items():
        Image.open(source).save(destination)


def build_preview() -> None:
    background = Image.open(RUNTIME / "bakery_background_3q.png").convert("RGBA")
    background = nearest_resize(background, (360, 640))
    preview = Image.new("RGBA", (1024, 640), (9, 16, 29, 255))
    preview.alpha_composite(background, (0, 0))

    assets = [
        (RUNTIME / "cake_top_atlas.png", 3, (396, 16)),
        (RUNTIME / "cake_side_face_atlas.png", 4, (396, 280)),
        (RUNTIME / "cake_side_plain_atlas.png", 4, (396, 400)),
        (RUNTIME / "baker_reaction_sheet.png", 3, (816, 16)),
        (RUNTIME / "crumb_burst_sheet.png", 5, (832, 236)),
    ]
    for path, scale, position in assets:
        image = Image.open(path).convert("RGBA")
        enlarged = nearest_resize(image, (image.width * scale, image.height * scale))
        preview.alpha_composite(enlarged, position)
    preview.save(ARTIFACTS / "asset-preview.png")


def validate() -> None:
    expected = {
        "bakery_background_3q.png": ((180, 320), "RGB"),
        "cake_top_atlas.png": ((120, 80), "RGBA"),
        "cake_side_face_atlas.png": ((80, 24), "RGBA"),
        "cake_side_plain_atlas.png": ((80, 24), "RGBA"),
        "baker_reaction_sheet.png": ((64, 64), "RGBA"),
        "crumb_burst_sheet.png": ((32, 32), "RGBA"),
    }
    for name, (size, mode) in expected.items():
        image = Image.open(RUNTIME / name)
        if image.size != size:
            raise ValueError(f"{name}: expected {size}, got {image.size}")
        if image.mode != mode:
            raise ValueError(f"{name}: expected {mode}, got {image.mode}")
        if mode == "RGBA":
            extrema = image.getchannel("A").getextrema()
            expected_alpha = (
                (255, 255)
                if name.startswith("cake_")
                else (0, 255)
            )
            if extrema != expected_alpha:
                raise ValueError(f"{name}: invalid alpha extrema {extrema}")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    build_cake_atlases()
    build_background()
    copy_processed_assets()
    validate()
    build_preview()


if __name__ == "__main__":
    main()
