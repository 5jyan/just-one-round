#!/usr/bin/env python3
"""Deterministic postprocess for the Image Gen plaster-wall family.

Creative pixels come only from the preserved Image Gen raws in ``raw/``. This
script performs aspect-preserving normalization, nearest-neighbour reduction
to the approved 256x192 authored grid, 4x nearest runtime export, transparent
feature cleanup/compositing, and machine-readable QC metadata.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
AUTHORED = ROOT / "processed" / "authored"
RUNTIME = ROOT / "processed" / "runtime"
QC = ROOT / "qc"
FEATURE_CUTOUTS = ROOT / "processed" / "feature-cutouts"
# ``ROOT`` is .../just-one-round/assets/source/imagegen/homebound_run/
# plaster_walls_v1; parents[4] is the app root (just-one-round).
REPO_ROOT = ROOT.parents[4]
RUNTIME_EXPORT = REPO_ROOT / "assets" / "images" / "homebound_run"

AUTHORED_SIZE = (256, 192)
RUNTIME_SIZE = (1024, 768)
SCALE = 4
WORLD_FOOTPRINT_M = (7.333, 5.5)
SIDE_RESERVED_AUTHORED = 16
SIDE_RESERVED_RUNTIME = SIDE_RESERVED_AUTHORED * SCALE

# Rectangles are authored-grid coordinates, x0/y0 inclusive, x1/y1 exclusive.
# They intentionally keep 16 authored pixels (64 runtime pixels) clear at both
# side edges. The lower bounds leave the generated features in the quieter
# lower half while preserving the shared bottom contact material.
FEATURES = {
    "wall_window": {
        "raw": RAW / "window_feature_raw.png",
        "rect": (78, 74, 178, 134),
        "description": "one small inset window",
        "prompt": "raw/window_feature_prompt.txt",
    },
    "wall_door": {
        "raw": RAW / "door_feature_raw.png",
        "rect": (92, 111, 160, 190),
        "description": "one simple Korean metal or painted-wood door",
        "prompt": "raw/door_feature_prompt.txt",
    },
    "wall_mural": {
        "raw": RAW / "mural_feature_raw.png",
        "rect": (64, 92, 180, 160),
        "description": "one small hand-painted blue-flowers mural, no text",
        "prompt": "raw/mural_feature_prompt.txt",
    },
}


def crop_to_aspect(image: Image.Image, aspect: float) -> tuple[Image.Image, tuple[int, int, int, int]]:
    width, height = image.size
    current = width / height
    if current > aspect:
        crop_width = round(height * aspect)
        left = (width - crop_width) // 2
        box = (left, 0, left + crop_width, height)
    elif current < aspect:
        crop_height = round(width / aspect)
        top = (height - crop_height) // 2
        box = (0, top, width, top + crop_height)
    else:
        box = (0, 0, width, height)
    return image.crop(box), box


def normalize_opaque(path: Path) -> tuple[Image.Image, tuple[int, int, int, int]]:
    source = Image.open(path).convert("RGB")
    cropped, box = crop_to_aspect(source, AUTHORED_SIZE[0] / AUTHORED_SIZE[1])
    return cropped.resize(AUTHORED_SIZE, Image.Resampling.NEAREST), box


def edge_profile(image: Image.Image) -> list[tuple[int, int, int]]:
    """Average the opposing source-edge pixels into a shared y-profile."""
    rgb = image.convert("RGB")
    profile: list[tuple[int, int, int]] = []
    for y in range(rgb.height):
        left = rgb.getpixel((0, y))
        right = rgb.getpixel((rgb.width - 1, y))
        profile.append(tuple((a + b) // 2 for a, b in zip(left, right)))
    return profile


def condition_vertical_seams(image: Image.Image, profile: list[tuple[int, int, int]]) -> Image.Image:
    """Blend only the reserved 16px side strips toward one shared profile.

    The first and last authored columns become byte-identical at every y. The
    interior of each feature remains untouched because every approved feature
    starts at x>=16 and ends at x<=240.
    """
    if image.size != AUTHORED_SIZE:
        raise ValueError(f"seam conditioning expects {AUTHORED_SIZE}, got {image.size}")
    output = image.convert("RGB").copy()
    source = image.convert("RGB")
    for y, common in enumerate(profile):
        for offset in range(SIDE_RESERVED_AUTHORED):
            # offset 0 is exact common edge; offset 15 preserves the inner
            # reserved-strip pixel and the intervening pixels blend linearly.
            weight = offset / (SIDE_RESERVED_AUTHORED - 1)
            left_original = source.getpixel((offset, y))
            right_original = source.getpixel((AUTHORED_SIZE[0] - 1 - offset, y))
            left = tuple(round(common[i] * (1 - weight) + left_original[i] * weight) for i in range(3))
            right = tuple(round(common[i] * (1 - weight) + right_original[i] * weight) for i in range(3))
            output.putpixel((offset, y), left)
            output.putpixel((AUTHORED_SIZE[0] - 1 - offset, y), right)
    return output


def clean_feature(source: Image.Image, kind: str) -> Image.Image:
    image = source.convert("RGBA")
    alpha = image.getchannel("A")
    # Remove low-alpha antialias/fringe pixels; creative edges remain opaque
    # and are then held on the approved authored grid by nearest sampling.
    cleaned = image.copy()
    pixels = cleaned.load()
    for y in range(cleaned.height):
        for x in range(cleaned.width):
            red, green, blue, opacity = pixels[x, y]
            if opacity < 128:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            # Generated transparent cutouts occasionally contain a bright cyan
            # matte fringe. Remove only neon fringe; retain muted teal panes and
            # blue mural paint used by the approved palette.
            if blue > 180 and blue > red + 85 and green > red + 45:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            # The transparent generator can leave a pale plaster-colour halo
            # around an otherwise clean cutout. Keep intentional pale glass or
            # flower highlights only where their feature context supports them.
            pale_wall = red >= 175 and green >= 165 and blue >= 145 and max(red, green, blue) - min(red, green, blue) < 70
            near_cutout_edge = (
                x < int(cleaned.width * 0.16)
                or x >= int(cleaned.width * 0.84)
                or y < int(cleaned.height * 0.16)
                or y >= int(cleaned.height * 0.84)
            )
            if pale_wall:
                if kind == "window" and near_cutout_edge and y < int(cleaned.height * 0.78):
                    pixels[x, y] = (0, 0, 0, 0)
                    continue
                if kind == "door" and near_cutout_edge and y < int(cleaned.height * 0.92):
                    pixels[x, y] = (0, 0, 0, 0)
                    continue
            # Every surviving source pixel becomes binary alpha. Runtime walls
            # are opaque, and feature compositing must never introduce a soft
            # antialias fringe at the authored-grid boundary.
            pixels[x, y] = (red, green, blue, 255)
    bbox = cleaned.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"transparent feature has no visible pixels: {source}")
    return cleaned.crop(bbox)


def composite_feature(master: Image.Image, spec: dict[str, object]) -> tuple[Image.Image, tuple[int, int, int, int]]:
    rect = tuple(spec["rect"])  # type: ignore[arg-type]
    x0, y0, x1, y1 = rect
    description = str(spec["description"])
    kind = "window" if "window" in description else "door" if "door" in description else "mural"
    feature = clean_feature(Image.open(spec["raw"]), kind)  # type: ignore[arg-type]
    target_size = (x1 - x0, y1 - y0)
    feature = feature.resize(target_size, Image.Resampling.NEAREST)
    output = master.convert("RGBA").copy()
    output.alpha_composite(feature, (x0, y0))
    return output.convert("RGB"), rect


def runtime_export(name: str, authored: Image.Image) -> Path:
    path = RUNTIME / f"{name}.png"
    runtime = authored.resize(RUNTIME_SIZE, Image.Resampling.NEAREST).convert("RGB")
    runtime.save(path, "PNG", optimize=False)
    export = RUNTIME_EXPORT / f"{name}.png"
    export.parent.mkdir(parents=True, exist_ok=True)
    runtime.save(export, "PNG", optimize=False)
    return export


def write_contact_sheet(items: list[tuple[str, Image.Image]]) -> None:
    thumb_w, thumb_h = 512, 384
    label_h = 28
    sheet = Image.new("RGB", (thumb_w * 2, (thumb_h + label_h) * 3), (30, 34, 48))
    draw = ImageDraw.Draw(sheet)
    for index, (name, image) in enumerate(items):
        x = (index % 2) * thumb_w
        y = (index // 2) * (thumb_h + label_h)
        thumb = image.resize((thumb_w, thumb_h), Image.Resampling.NEAREST)
        sheet.paste(thumb, (x, y))
        draw.rectangle((x, y + thumb_h, x + thumb_w, y + thumb_h + label_h), fill=(30, 34, 48))
        draw.text((x + 8, y + thumb_h + 6), name, fill=(240, 236, 220))
    sheet.save(QC / "plaster_walls_contact_sheet.png", "PNG", optimize=False)


def main() -> None:
    for directory in (AUTHORED, RUNTIME, QC, FEATURE_CUTOUTS, RUNTIME_EXPORT):
        directory.mkdir(parents=True, exist_ok=True)

    master, master_crop = normalize_opaque(RAW / "master_plain_raw.png")
    shared_edge_profile = edge_profile(master)
    master = condition_vertical_seams(master, shared_edge_profile)
    # Preserve an explicit master name and use it as the exact compositing plate.
    master.save(AUTHORED / "wall_plaster_a.png", "PNG", optimize=False)
    runtime_export("wall_plaster_a", master)

    variant_b, variant_crop = normalize_opaque(RAW / "plaster_b_raw.png")
    # Side margins and bottom contact material are shared with the master so
    # runtime tiles connect quietly even when the center marks vary.
    variant_b.paste(master.crop((0, 0, SIDE_RESERVED_AUTHORED, AUTHORED_SIZE[1])), (0, 0))
    variant_b.paste(
        master.crop((AUTHORED_SIZE[0] - SIDE_RESERVED_AUTHORED, 0, AUTHORED_SIZE[0], AUTHORED_SIZE[1])),
        (AUTHORED_SIZE[0] - SIDE_RESERVED_AUTHORED, 0),
    )
    variant_b.paste(master.crop((0, AUTHORED_SIZE[1] - 6, AUTHORED_SIZE[0], AUTHORED_SIZE[1])), (0, AUTHORED_SIZE[1] - 6))
    variant_b = condition_vertical_seams(variant_b, shared_edge_profile)
    variant_b.save(AUTHORED / "wall_plaster_b.png", "PNG", optimize=False)
    runtime_export("wall_plaster_b", variant_b)

    output_items: list[tuple[str, Image.Image]] = [
        ("wall_plaster_a", master),
        ("wall_plaster_b", variant_b),
    ]
    feature_metadata: dict[str, dict[str, object]] = {}
    for name, spec in FEATURES.items():
        description = str(spec["description"])
        kind = "window" if "window" in description else "door" if "door" in description else "mural"
        cleaned_cutout = clean_feature(Image.open(spec["raw"]), kind)  # type: ignore[arg-type]
        cleaned_cutout.save(FEATURE_CUTOUTS / f"{name}_clean.png", "PNG", optimize=False)
        image, rect = composite_feature(master, spec)
        image = condition_vertical_seams(image, shared_edge_profile)
        image.save(AUTHORED / f"{name}.png", "PNG", optimize=False)
        runtime_export(name, image)
        x0, y0, x1, y1 = rect
        feature_metadata[name] = {
            "description": spec["description"],
            "raw": str(spec["raw"].relative_to(ROOT)),
            "prompt": spec["prompt"],
            "authored_rect_xyxy": list(rect),
            "normalized_rect_xyxy": [x0 / 256, y0 / 192, x1 / 256, y1 / 192],
            "runtime_rect_xyxy": [x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE],
            "source_bottom_contact": {
                "wall_plate_bottom_authored_y": AUTHORED_SIZE[1],
                "feature_bottom_authored_y": y1,
                "feature_bottom_runtime_y": y1 * SCALE,
                "note": "door leaves a two-authored-pixel contact buffer; window and mural stay above the shared ground row",
            },
        }
        output_items.append((name, image))

    write_contact_sheet(output_items)

    max_edge_delta = 0
    max_profile_delta = 0
    for _, image in output_items:
        rgb = image.convert("RGB")
        for y, common in enumerate(shared_edge_profile):
            left = rgb.getpixel((0, y))
            right = rgb.getpixel((AUTHORED_SIZE[0] - 1, y))
            max_edge_delta = max(max_edge_delta, *(abs(left[i] - right[i]) for i in range(3)))
            max_profile_delta = max(max_profile_delta, *(abs(left[i] - common[i]) for i in range(3)))
    seam_qc = {
        "all_five_first_last_columns_exact": max_edge_delta == 0,
        "max_left_right_channel_delta": max_edge_delta,
        "max_common_profile_channel_delta": max_profile_delta,
        "reserved_strip_authored_px": SIDE_RESERVED_AUTHORED,
        "profile_source": "normalized master wall_plaster_a opposing edge average before conditioning",
    }

    metadata = {
        "schema": "homebound_run.plaster_walls_v1.qc.v1",
        "game": "homebound_run",
        "family": "plaster_walls_v1",
        "creative_source": "built-in image_gen only",
        "master_reference": "raw/master_plain_raw.png",
        "generation_manifest": "generation-manifest.json",
        "master_style_reference": "../characters/processed/student_run/frames/L-contact.png",
        "authored_size": list(AUTHORED_SIZE),
        "runtime_size": list(RUNTIME_SIZE),
        "nearest_scale": SCALE,
        "world_footprint_m": list(WORLD_FOOTPRINT_M),
        "visual_contract": {
            "camera": "front-on orthographic planar wall; no baked perspective",
            "palette": "warm off-white/cream plaster with cool blue-gray lower weathering, restrained navy shadows, muted teal/blue accents",
            "lighting": "warm upper-right with cool lower shadows",
            "texture": "quiet deliberate 2x clusters; mostly blank upper wall; no micro-noise",
            "forbidden": ["sky", "road", "rooftop", "roof", "border", "pilaster", "readable text", "characters", "vehicles"],
        },
        "source_bottom_contact": {"authored_y": 192, "runtime_y": 768, "role": "flat wall-ground contact; runtime owns road/roof/caps"},
        "reserved_plain_edges": {
            "authored_px": [SIDE_RESERVED_AUTHORED, SIDE_RESERVED_AUTHORED],
            "runtime_px": [SIDE_RESERVED_RUNTIME, SIDE_RESERVED_RUNTIME],
            "left_range": [0, SIDE_RESERVED_AUTHORED],
            "right_range": [AUTHORED_SIZE[0] - SIDE_RESERVED_AUTHORED, AUTHORED_SIZE[0]],
        },
        "assets": {
            "wall_plaster_a": {"authored": "processed/authored/wall_plaster_a.png", "runtime": "processed/runtime/wall_plaster_a.png", "export": "assets/images/homebound_run/wall_plaster_a.png", "raw": "raw/master_plain_raw.png", "crop_box_xyxy": list(master_crop)},
            "wall_plaster_b": {"authored": "processed/authored/wall_plaster_b.png", "runtime": "processed/runtime/wall_plaster_b.png", "export": "assets/images/homebound_run/wall_plaster_b.png", "raw": "raw/plaster_b_raw.png", "crop_box_xyxy": list(variant_crop)},
        },
        "features": feature_metadata,
        "processing": {
            "aspect": "4:3 center crop with no axis stretch",
            "authored": "nearest-neighbor to 256x192 from raw creative source",
            "runtime": "nearest-neighbor 4x to 1024x768",
            "transparent_feature_cleanup": "alpha<128 removed; bright cyan matte fringe removed; no creative repaint",
            "variant_b_seam_conditioning": "copy master left/right 16 authored px and bottom 6 authored rows",
            "vertical_seam_conditioning": "all five authored plates use the master normalized left/right edge average as a common y-profile; first and last authored columns are exact matches and reserved 16px strips are linearly blended",
            "contact_sheet": "qc/plaster_walls_contact_sheet.png",
        },
        "seam_qc": seam_qc,
    }
    metadata["features"].update({})
    for name, spec in FEATURES.items():
        metadata["assets"][name] = {  # type: ignore[index]
            "authored": f"processed/authored/{name}.png",
            "runtime": f"processed/runtime/{name}.png",
            "export": f"assets/images/homebound_run/{name}.png",
            "raw": str(spec["raw"].relative_to(ROOT)),
            "clean_cutout": f"processed/feature-cutouts/{name}_clean.png",
        }
    (QC / "pipeline-meta.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    # A small machine check for the handoff contract.
    for name, _ in output_items:
        authored_path = AUTHORED / f"{name}.png"
        runtime_path = RUNTIME / f"{name}.png"
        authored = Image.open(authored_path)
        runtime = Image.open(runtime_path)
        if authored.size != AUTHORED_SIZE or authored.mode != "RGB":
            raise AssertionError(f"bad authored output: {authored_path} {authored.size} {authored.mode}")
        if runtime.size != RUNTIME_SIZE or runtime.mode != "RGB":
            raise AssertionError(f"bad runtime output: {runtime_path} {runtime.size} {runtime.mode}")
        if runtime.getextrema()[0] is None:
            raise AssertionError(f"empty runtime output: {runtime_path}")


if __name__ == "__main__":
    main()
