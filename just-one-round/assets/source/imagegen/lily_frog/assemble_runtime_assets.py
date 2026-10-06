from __future__ import annotations

import json
import colorsys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "assets/source/imagegen/lily_frog"
RUNTIME = ROOT / "assets/images/lily_frog"


def recolor_green_pixels(
    image: Image.Image,
    *,
    lily: bool,
) -> Image.Image:
    """Separate frog and lily values without changing any sprite geometry."""
    result = image.copy().convert("RGBA")
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha <= 8:
                continue
            hue, saturation, value = colorsys.rgb_to_hsv(
                red / 255, green / 255, blue / 255
            )
            if not (0.14 <= hue <= 0.48 and saturation >= 0.24):
                continue
            if lily:
                hue = hue * 0.35 + 0.205 * 0.65
                saturation = max(0.42, saturation * 0.74)
                value = min(1.0, value * 1.08 + 0.07)
            elif (
                hue < 0.30
                and value >= 0.48
                and ((x % 56 - 28) / 14) ** 2 + ((y % 56 - 35) / 13) ** 2
                <= 1
            ):
                # Keep the broad belly/readable highlights warm and pale.
                hue = 0.185
                saturation = min(0.58, saturation * 0.66)
                value = min(0.90, value * 0.90 + 0.08)
            else:
                hue = hue * 0.25 + 0.385 * 0.75
                saturation = min(1.0, saturation * 1.20 + 0.06)
                value = max(0.14, value * 0.68)
            recolored = colorsys.hsv_to_rgb(hue, saturation, value)
            pixels[x, y] = tuple(round(channel * 255) for channel in recolored) + (
                alpha,
            )
    return result


def average_opaque_luminance(image: Image.Image) -> float:
    values = []
    for red, green, blue, alpha in image.convert("RGBA").getdata():
        if alpha > 32 and max(red, green, blue) > 54:
            values.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    return sum(values) / len(values)


def average_opaque_rgb(image: Image.Image) -> list[float]:
    pixels = [
        (red, green, blue)
        for red, green, blue, alpha in image.convert("RGBA").getdata()
        if alpha > 32
    ]
    return [
        round(sum(pixel[channel] for pixel in pixels) / len(pixels), 2)
        for channel in range(3)
    ]


def numbered_frames(folder: Path, prefix: str) -> list[Path]:
    return sorted(
        folder.glob(f"{prefix}-*.png"),
        key=lambda path: int(path.stem.rsplit("-", 1)[1]),
    )


def assemble_frog() -> dict[str, object]:
    rows = [
        numbered_frames(SOURCE / "v3/frog/orbit/processed", "idle"),
        numbered_frames(SOURCE / "v3/frog/jump/processed", "jump"),
        numbered_frames(SOURCE / "v3/frog/landing/processed", "landing"),
        numbered_frames(SOURCE / "v3/frog/success/processed", "success")[:2]
        + numbered_frames(SOURCE / "v3/frog/failure/processed", "failure")[2:],
    ]
    atlas = Image.new("RGBA", (224, 224), (0, 0, 0, 0))
    for row, frames in enumerate(rows):
        if len(frames) != 4:
            raise ValueError(f"frog row {row}: expected 4 frames, got {len(frames)}")
        for column, frame_path in enumerate(frames):
            frame = Image.open(frame_path).convert("RGBA")
            if frame.size != (80, 80):
                raise ValueError(f"{frame_path}: expected 80x80, got {frame.size}")
            frame = frame.resize((56, 56), Image.Resampling.NEAREST)
            atlas.alpha_composite(frame, (column * 56, row * 56))
    atlas = recolor_green_pixels(atlas, lily=False)
    output = RUNTIME / "frog_actions_atlas.png"
    atlas.save(output)
    return {
        "path": str(output.relative_to(ROOT)),
        "size": atlas.size,
        "grid": [4, 4],
        "average_opaque_luminance": round(average_opaque_luminance(atlas), 2),
        "palette": "deep emerald body, warm pale belly",
    }


def fit_subject(frame: Image.Image, target_extent: int, cell_size: int) -> Image.Image:
    frame = frame.convert("RGBA")
    bbox = frame.getbbox()
    if bbox is None:
        raise ValueError("empty source frame")
    subject = frame.crop(bbox)
    source_radius = alpha_rotation_radius(subject)
    scale = (target_extent / 2 - 1.5) / source_radius
    resized = subject.resize(
        (
            max(1, round(subject.width * scale)),
            max(1, round(subject.height * scale)),
        ),
        Image.Resampling.NEAREST,
    )
    cell = Image.new("RGBA", (cell_size, cell_size), (0, 0, 0, 0))
    x = (cell_size - resized.width) // 2
    y = (cell_size - resized.height) // 2
    cell.alpha_composite(resized, (x, y))
    return cell


def alpha_rotation_radius(frame: Image.Image) -> float:
    alpha = frame.getchannel("A")
    center_x = frame.width / 2
    center_y = frame.height / 2
    radius = 0.0
    for y in range(frame.height):
        for x in range(frame.width):
            if alpha.getpixel((x, y)) <= 8:
                continue
            radius = max(
                radius,
                ((x + 0.5 - center_x) ** 2 + (y + 0.5 - center_y) ** 2)
                ** 0.5,
            )
    return radius


def remove_radial_protrusions(subject: Image.Image) -> Image.Image:
    """Remove generator tabs outside the leaf's inscribed circular contour."""
    cleaned = subject.copy().convert("RGBA")
    center_x = (cleaned.width - 1) / 2
    center_y = (cleaned.height - 1) / 2
    radius = min(cleaned.width, cleaned.height) / 2 - 0.5
    pixels = cleaned.load()
    for y in range(cleaned.height):
        for x in range(cleaned.width):
            if ((x - center_x) ** 2 + (y - center_y) ** 2) ** 0.5 > radius:
                red, green, blue, _ = pixels[x, y]
                pixels[x, y] = (red, green, blue, 0)
    return cleaned


def lily_master_frames() -> tuple[list[Image.Image], list[list[int]]]:
    source = Image.open(
        SOURCE / "v5/lily/processed/raw-sheet-transparent.png"
    ).convert("RGBA")
    masters = []
    source_bounds = []
    for index in range(3):
        left = round(source.width * index / 3)
        right = round(source.width * (index + 1) / 3)
        column = source.crop((left, 0, right, source.height))
        bbox = column.getbbox()
        if bbox is None:
            raise ValueError(f"lily master {index}: empty column")
        if bbox[0] <= 0 or bbox[1] <= 0 or bbox[2] >= column.width or bbox[3] >= column.height:
            raise ValueError(f"lily master {index}: source touches its column edge")
        masters.append(remove_radial_protrusions(column.crop(bbox)))
        source_bounds.append([left + bbox[0], bbox[1], left + bbox[2], bbox[3]])
    return masters, source_bounds


def assemble_lilies() -> dict[str, object]:
    masters, source_bounds = lily_master_frames()
    atlas = Image.new("RGBA", (1280, 768), (0, 0, 0, 0))
    target_extents = [128, 160, 176, 192, 208]
    occupied = []
    rotation_radii = []
    processed = SOURCE / "v5/lily/processed"
    for row, master in enumerate(masters):
        for column, target_extent in enumerate(target_extents):
            frame = recolor_green_pixels(
                fit_subject(master, target_extent, 256), lily=True
            )
            radius = alpha_rotation_radius(frame)
            if radius > target_extent / 2:
                raise ValueError(
                    f"lily {row},{column}: rotation radius {radius:.2f} exceeds "
                    f"the {target_extent}px diameter contract"
                )
            frame.save(processed / f"single-{row * 5 + column + 1}.png")
            atlas.alpha_composite(frame, (column * 256, row * 256))
            occupied.append(frame.getbbox())
            rotation_radii.append(round(radius, 3))
    output = RUNTIME / "lily_pad_atlas.png"
    atlas.save(output)
    return {
        "path": str(output.relative_to(ROOT)),
        "size": atlas.size,
        "grid": [3, 5],
        "occupied_bounds": occupied,
        "rotation_radii": rotation_radii,
        "source_bounds": source_bounds,
        "source_version": "v5",
        "contour_cleanup": "inscribed-circle alpha trim",
        "average_opaque_luminance": round(average_opaque_luminance(atlas), 2),
        "palette": "pale yellow-green",
    }


def assemble_golden_lilies() -> dict[str, object]:
    source_folder = SOURCE / "golden_lily_v1/processed"
    frames = numbered_frames(source_folder, "golden")[:3]
    if len(frames) != 3:
        raise ValueError(f"golden lily: expected 3 frames, got {len(frames)}")
    atlas = Image.new("RGBA", (768, 256), (0, 0, 0, 0))
    occupied = []
    rotation_radii = []
    for column, frame_path in enumerate(frames):
        frame = fit_subject(Image.open(frame_path), 128, 256)
        radius = alpha_rotation_radius(frame)
        if radius > 64:
            raise ValueError(
                f"golden lily {column}: rotation radius {radius:.2f} exceeds 64px"
            )
        atlas.alpha_composite(frame, (column * 256, 0))
        occupied.append(frame.getbbox())
        rotation_radii.append(round(radius, 3))
    output = RUNTIME / "golden_lily_pad_atlas.png"
    atlas.save(output)
    return {
        "path": str(output.relative_to(ROOT)),
        "size": atlas.size,
        "grid": [1, 3],
        "occupied_display_diameter": 128,
        "occupied_bounds": occupied,
        "rotation_radii": rotation_radii,
        "source_version": "golden_lily_v1",
        "palette": "polished 24K gold",
        "average_opaque_rgb": average_opaque_rgb(atlas),
        "average_opaque_luminance": round(average_opaque_luminance(atlas), 2),
    }


def assemble_fly_collect_fx() -> dict[str, object]:
    source_folder = SOURCE / "fly_collect_fx_v1/processed"
    frames = numbered_frames(source_folder, "collect")[:5]
    if len(frames) != 5:
        raise ValueError(f"fly collect FX: expected 5 frames, got {len(frames)}")
    atlas = Image.new("RGBA", (320, 64), (0, 0, 0, 0))
    occupied = []
    for column, frame_path in enumerate(frames):
        frame = Image.open(frame_path).convert("RGBA")
        if frame.size != (64, 64):
            raise ValueError(f"{frame_path}: expected 64x64, got {frame.size}")
        if frame.getbbox() is None:
            raise ValueError(f"{frame_path}: empty collection effect frame")
        atlas.alpha_composite(frame, (column * 64, 0))
        occupied.append(frame.getbbox())
    output = RUNTIME / "fly_collect_fx_atlas.png"
    atlas.save(output)
    return {
        "path": str(output.relative_to(ROOT)),
        "size": atlas.size,
        "frames": 5,
        "duration_ms": 280,
        "occupied_bounds": occupied,
        "anchor": "center",
    }


def assemble_strip(
    source_folder: Path,
    prefix: str,
    cell_size: int,
    output_name: str,
    subject_extent: int | None = None,
) -> dict[str, object]:
    frames = numbered_frames(source_folder, prefix)
    if len(frames) != 4:
        raise ValueError(f"{prefix}: expected 4 frames, got {len(frames)}")
    strip = Image.new("RGBA", (cell_size * 4, cell_size), (0, 0, 0, 0))
    for index, frame_path in enumerate(frames):
        frame = Image.open(frame_path).convert("RGBA")
        if frame.size != (cell_size, cell_size):
            raise ValueError(
                f"{frame_path}: expected {cell_size}x{cell_size}, got {frame.size}"
            )
        if subject_extent is not None:
            frame = fit_subject(frame, subject_extent, cell_size)
        strip.alpha_composite(frame, (index * cell_size, 0))
    output = RUNTIME / output_name
    strip.save(output)
    return {
        "path": str(output.relative_to(ROOT)),
        "size": strip.size,
        "frames": 4,
        "subject_extent": subject_extent,
        "occupied_bounds": [
            strip.crop((index * cell_size, 0, (index + 1) * cell_size, cell_size)).getbbox()
            for index in range(4)
        ],
    }


def assemble_water_fx() -> dict[str, object]:
    atlas = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    rows = [
        (SOURCE / "v3/water/ripple/processed", "impact"),
        (SOURCE / "v3/water/splash/processed", "impact"),
    ]
    for row, (folder, prefix) in enumerate(rows):
        frames = numbered_frames(folder, prefix)
        if len(frames) != 4:
            raise ValueError(f"{prefix}: expected 4 frames, got {len(frames)}")
        for column, frame_path in enumerate(frames):
            frame = Image.open(frame_path).convert("RGBA")
            if frame.size != (64, 64):
                raise ValueError(f"{frame_path}: expected 64x64, got {frame.size}")
            atlas.alpha_composite(frame, (column * 64, row * 64))
    output = RUNTIME / "water_fx_atlas.png"
    atlas.save(output)
    return {"path": str(output.relative_to(ROOT)), "size": atlas.size, "grid": [2, 4]}


def process_background() -> dict[str, object]:
    raw = Image.open(SOURCE / "background_v1/raw-background.png").convert("RGB")
    target_ratio = 180 / 480
    raw_ratio = raw.width / raw.height
    if raw_ratio > target_ratio:
        crop_width = round(raw.height * target_ratio)
        left = (raw.width - crop_width) // 2
        cropped = raw.crop((left, 0, left + crop_width, raw.height))
        crop_box = [left, 0, left + crop_width, raw.height]
    else:
        crop_height = round(raw.width / target_ratio)
        top = (raw.height - crop_height) // 2
        cropped = raw.crop((0, top, raw.width, top + crop_height))
        crop_box = [0, top, raw.width, top + crop_height]
    background = cropped.resize((180, 480), Image.Resampling.NEAREST)
    output = RUNTIME / "pond_background.png"
    background.save(output)
    return {
        "path": str(output.relative_to(ROOT)),
        "size": background.size,
        "source_crop": crop_box,
        "world_rect": [0, -160, 360, 960],
    }


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    report = {
        "frog": assemble_frog(),
        "lilies": assemble_lilies(),
        "golden_lilies": assemble_golden_lilies(),
        "fly": assemble_strip(
            SOURCE / "v3/fly/processed",
            "hover",
            32,
            "fly_sheet.png",
            subject_extent=24,
        ),
        "fly_collect_fx": assemble_fly_collect_fx(),
        "water_fx": assemble_water_fx(),
        "background": process_background(),
        "art_pixel_world_size": 2,
        "filter": "nearest-neighbor",
        "approved_replacements": [
            "frog_actions_atlas.png",
            "lily_pad_atlas.png",
            "golden_lily_pad_atlas.png",
            "fly_sheet.png",
            "fly_collect_fx_atlas.png",
            "water_fx_atlas.png",
        ],
    }
    frog_luminance = report["frog"]["average_opaque_luminance"]
    lily_luminance = report["lilies"]["average_opaque_luminance"]
    if lily_luminance < frog_luminance + 18:
        raise ValueError(
            f"palette contrast failed: lily={lily_luminance}, frog={frog_luminance}"
        )
    report["palette_luminance_gap"] = round(lily_luminance - frog_luminance, 2)
    (SOURCE / "runtime-qc.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
