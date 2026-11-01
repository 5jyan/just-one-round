#!/usr/bin/env python3
"""Build the approved neighborhood wall family from preserved sources.

ImageGen and the existing environment raws provide every creative pixel. This
script only performs deterministic aspect crops, nearest-neighbor authored-grid
normalization, architectural insert compositing, edge conditioning, runtime
export, and QC metadata.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
AUTHORED = ROOT / "processed" / "authored"
RUNTIME = ROOT / "processed" / "runtime"
QC = ROOT / "qc"
APP_ROOT = ROOT.parents[4]
PLASTER_AUTHORED = (
    APP_ROOT
    / "assets"
    / "source"
    / "imagegen"
    / "homebound_run"
    / "plaster_walls_v1"
    / "processed"
    / "authored"
    / "wall_plaster_a.png"
)
RUNTIME_EXPORT = APP_ROOT / "assets" / "images" / "homebound_run"

AUTHORED_SIZE = (256, 192)
RUNTIME_SIZE = (1024, 768)
SCALE = 4
WORLD_FOOTPRINT_M = (7.333, 5.5)
SIDE_RESERVED_AUTHORED = 16
SIDE_RESERVED_RUNTIME = SIDE_RESERVED_AUTHORED * SCALE

# All rectangles use authored-grid x0/y0 inclusive, x1/y1 exclusive pixels.
# Insert plates end at y=192 so their source image owns a flat ground contact.
INSERTS: dict[str, dict[str, object]] = {
    "wall_house_garden": {
        "source": RAW / "facade_homes_source_raw.png",
        "original_source": "../environment/facade_homes/raw.png",
        "prompt": "raw/facade_homes_source_prompt.txt",
        "crop_box_xyxy": (512, 0, 1792, 768),
        "authored_rect_xyxy": (28, 72, 228, 192),
        "description": "complete residential entry bay with canopy, gate, hedge, meter, and pipes",
        "features": {
            "door": (120, 104, 162, 177),
            "awning": (96, 77, 188, 100),
            "canopy": (96, 77, 188, 100),
            "hedge": (28, 104, 94, 132),
        },
        # The canopy bounds are derived from the visible roof in the preserved
        # raw source, not guessed from the target UV rectangle. Coordinates are
        # global pixels in facade_homes_source_raw.png.
        "feature_source_boxes": {
            "awning": (947, 32, 1536, 179),
            "canopy": (947, 32, 1536, 179),
        },
    },
    "wall_shopfront": {
        "source": RAW / "facade_shops_source_raw.png",
        "original_source": "../environment/facade_shops/raw.png",
        "prompt": "raw/facade_shops_source_prompt.txt",
        "crop_box_xyxy": (100, 0, 1000, 768),
        "authored_rect_xyxy": (57, 72, 198, 192),
        "description": "complete closed roller-shutter shop bay with awning and cream frame",
        "features": {
            "window": (63, 87, 179, 188),
            "shutter": (63, 87, 179, 188),
            "awning": (62, 75, 179, 98),
        },
    },
    "wall_schoolfront": {
        "source": RAW / "facade_school_source_raw.png",
        "original_source": "../environment/facade_school/raw.png",
        "prompt": "raw/facade_school_source_prompt.txt",
        "crop_box_xyxy": (256, 0, 1792, 768),
        "authored_rect_xyxy": (28, 72, 228, 192),
        "description": "complete school window, railing, brick, and cream-column band",
        "features": {
            "window": (34, 91, 222, 132),
            "railing": (34, 132, 222, 166),
        },
    },
    "wall_constructionfront": {
        "source": RAW / "facade_construction_source_raw.png",
        "original_source": "../environment/facade_construction/raw.png",
        "prompt": "raw/facade_construction_source_prompt.txt",
        "crop_box_xyxy": (0, 0, 2161, 728),
        "authored_rect_xyxy": (23, 88, 233, 192),
        "description": "complete corrugated hoarding run with supports, brick base, and temporary gate",
        "features": {
            "door": (133, 102, 183, 189),
        },
    },
}

HOUSE_FEATURES: dict[str, dict[str, object]] = {
    "wall_house_brick": {
        "source": RAW / "wall_house_brick_raw.png",
        "prompt": "raw/wall_house_brick_prompt.txt",
        "description": "full warm-red-brick two-story Korean house wall plate",
        "main_panel": (16, 0, 240, 192),
        "features": {
            "door": (147, 91, 195, 175),
            "window": [(51, 13, 127, 63), (185, 9, 218, 57)],
            "awning": (124, 69, 188, 94),
            "eave": [(31, 0, 143, 22), (183, 6, 221, 20)],
            "hedge": (17, 43, 162, 79),
        },
    },
    "wall_house_sage": {
        "source": RAW / "wall_house_sage_raw.png",
        "prompt": "raw/wall_house_sage_prompt.txt",
        "description": "full sage-and-blue-grey two-story Korean house wall plate",
        "main_panel": (16, 0, 240, 192),
        "features": {
            "door": (147, 91, 195, 175),
            "window": [(51, 13, 127, 63), (185, 9, 218, 57)],
            "awning": (124, 69, 188, 94),
            "eave": [(31, 0, 143, 22), (183, 6, 221, 20)],
            "hedge": (17, 43, 162, 79),
        },
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
    cropped, crop_box = crop_to_aspect(source, AUTHORED_SIZE[0] / AUTHORED_SIZE[1])
    return cropped.resize(AUTHORED_SIZE, Image.Resampling.NEAREST), crop_box


def edge_profile(image: Image.Image) -> list[tuple[int, int, int]]:
    rgb = image.convert("RGB")
    return [
        tuple((a + b) // 2 for a, b in zip(rgb.getpixel((0, y)), rgb.getpixel((rgb.width - 1, y))))
        for y in range(rgb.height)
    ]


def condition_vertical_seams(image: Image.Image, profile: list[tuple[int, int, int]]) -> Image.Image:
    """Use the common plaster profile only inside the reserved 16px margins."""
    if image.size != AUTHORED_SIZE:
        raise ValueError(f"expected {AUTHORED_SIZE}, got {image.size}")
    source = image.convert("RGB")
    output = source.copy()
    for y, common in enumerate(profile):
        for offset in range(SIDE_RESERVED_AUTHORED):
            weight = offset / (SIDE_RESERVED_AUTHORED - 1)
            left_original = source.getpixel((offset, y))
            right_original = source.getpixel((AUTHORED_SIZE[0] - 1 - offset, y))
            left = tuple(round(common[i] * (1 - weight) + left_original[i] * weight) for i in range(3))
            right = tuple(round(common[i] * (1 - weight) + right_original[i] * weight) for i in range(3))
            output.putpixel((offset, y), left)
            output.putpixel((AUTHORED_SIZE[0] - 1 - offset, y), right)
    return output


def composite_insert(base: Image.Image, spec: dict[str, object]) -> Image.Image:
    crop_box = tuple(spec["crop_box_xyxy"])  # type: ignore[arg-type]
    rect = tuple(spec["authored_rect_xyxy"])  # type: ignore[arg-type]
    source = Image.open(spec["source"]).convert("RGB")  # type: ignore[arg-type]
    source_crop = source.crop(crop_box)
    x0, y0, x1, y1 = rect
    insert = source_crop.resize((x1 - x0, y1 - y0), Image.Resampling.NEAREST)
    output = base.convert("RGB").copy()
    output.paste(insert, (x0, y0))
    return output


def runtime_export(name: str, authored: Image.Image) -> None:
    runtime = authored.convert("RGB").resize(RUNTIME_SIZE, Image.Resampling.NEAREST)
    runtime_path = RUNTIME / f"{name}.png"
    export_path = RUNTIME_EXPORT / f"{name}.png"
    runtime.save(runtime_path, "PNG", optimize=False)
    export_path.parent.mkdir(parents=True, exist_ok=True)
    runtime.save(export_path, "PNG", optimize=False)


def rect_dict(rect: tuple[int, int, int, int]) -> dict[str, object]:
    x0, y0, x1, y1 = rect
    return {
        "authored_rect_xyxy": list(rect),
        "normalized_rect_xyxy": [x0 / 256, y0 / 192, x1 / 256, y1 / 192],
        "runtime_rect_xyxy": [x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE],
    }


def insert_transform_proof(spec: dict[str, object]) -> dict[str, object]:
    """Record the crop-to-authored affine mapping behind an insert UV."""
    crop_x0, crop_y0, crop_x1, crop_y1 = tuple(spec["crop_box_xyxy"])  # type: ignore[arg-type]
    target_x0, target_y0, target_x1, target_y1 = tuple(spec["authored_rect_xyxy"])  # type: ignore[arg-type]
    scale_x = (target_x1 - target_x0) / (crop_x1 - crop_x0)
    scale_y = (target_y1 - target_y0) / (crop_y1 - crop_y0)
    offset_x = target_x0 - crop_x0 * scale_x
    offset_y = target_y0 - crop_y0 * scale_y
    return {
        "source_coordinates": "global pixels in preserved raw source",
        "source_crop_xyxy": [crop_x0, crop_y0, crop_x1, crop_y1],
        "target_authored_rect_xyxy": [target_x0, target_y0, target_x1, target_y1],
        "scale_xy": [scale_x, scale_y],
        "offset_xy": [offset_x, offset_y],
        "formula": "authored_x = offset_x + source_x * scale_x; authored_y = offset_y + source_y * scale_y",
        "corner_proof": [
            {"source_xy": [crop_x0, crop_y0], "authored_xy": [target_x0, target_y0]},
            {"source_xy": [crop_x1, crop_y1], "authored_xy": [target_x1, target_y1]},
        ],
    }


def feature_transform_proof(spec: dict[str, object]) -> dict[str, object]:
    """Derive source feature bounds through the same crop/insert mapping."""
    crop_x0, crop_y0, crop_x1, crop_y1 = tuple(spec["crop_box_xyxy"])  # type: ignore[arg-type]
    target_x0, target_y0, target_x1, target_y1 = tuple(spec["authored_rect_xyxy"])  # type: ignore[arg-type]
    scale_x = (target_x1 - target_x0) / (crop_x1 - crop_x0)
    scale_y = (target_y1 - target_y0) / (crop_y1 - crop_y0)
    output: dict[str, object] = {}
    for name, source_rect in dict(spec.get("feature_source_boxes", {})).items():
        sx0, sy0, sx1, sy1 = tuple(source_rect)  # type: ignore[arg-type]
        derived_float = [
            target_x0 + (sx0 - crop_x0) * scale_x,
            target_y0 + (sy0 - crop_y0) * scale_y,
            target_x0 + (sx1 - crop_x0) * scale_x,
            target_y0 + (sy1 - crop_y0) * scale_y,
        ]
        derived_authored = [round(value) for value in derived_float]
        output[name] = {
            "source_bbox_xyxy": [sx0, sy0, sx1, sy1],
            "derived_float_authored_xyxy": derived_float,
            "derived_authored_rect_xyxy": derived_authored,
            "rounding": "nearest authored-grid boundary",
        }
    return output


def feature_metadata(features: dict[str, object]) -> dict[str, object]:
    output: dict[str, object] = {}
    for kind, rects in features.items():
        if isinstance(rects, list) and rects and isinstance(rects[0], (list, tuple)):
            entries = [rect_dict(tuple(rect)) for rect in rects]  # type: ignore[arg-type]
            output[kind] = entries
        else:
            entry = rect_dict(tuple(rects))  # type: ignore[arg-type]
            if kind == "door":
                entry["estimated_world_height_m"] = round(
                    (tuple(rects)[3] - tuple(rects)[1]) / AUTHORED_SIZE[1] * WORLD_FOOTPRINT_M[1], 3  # type: ignore[index]
                )
            output[kind] = entry
    return output


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_contact_sheet(items: list[tuple[str, Image.Image]]) -> None:
    thumb_size = (512, 384)
    label_h = 30
    columns = 2
    rows = (len(items) + columns - 1) // columns
    sheet = Image.new("RGB", (thumb_size[0] * columns, (thumb_size[1] + label_h) * rows), (30, 34, 48))
    draw = ImageDraw.Draw(sheet)
    for index, (name, image) in enumerate(items):
        x = (index % columns) * thumb_size[0]
        y = (index // columns) * (thumb_size[1] + label_h)
        sheet.paste(image.resize(thumb_size, Image.Resampling.NEAREST), (x, y))
        draw.rectangle((x, y + thumb_size[1], x + thumb_size[0], y + thumb_size[1] + label_h), fill=(30, 34, 48))
        draw.text((x + 8, y + thumb_size[1] + 7), name, fill=(240, 236, 220))
    sheet.save(QC / "neighborhood_contact_sheet.png", "PNG", optimize=False)


def seam_qc(plates: list[Image.Image], profile: list[tuple[int, int, int]]) -> dict[str, object]:
    """Return numeric proof for the shared first/last-column seam contract."""
    max_first_family_channel_delta = 0
    max_last_family_channel_delta = 0
    max_left_right_channel_delta = 0
    max_common_profile_channel_delta = 0
    first_last_columns_exact = True
    for y in range(AUTHORED_SIZE[1]):
        first_values = [plate.getpixel((0, y)) for plate in plates]
        last_values = [plate.getpixel((AUTHORED_SIZE[0] - 1, y)) for plate in plates]
        if any(value != first_values[0] for value in first_values[1:]):
            first_last_columns_exact = False
        if any(value != last_values[0] for value in last_values[1:]):
            first_last_columns_exact = False
        for value in first_values[1:]:
            max_first_family_channel_delta = max(
                max_first_family_channel_delta,
                max(abs(value[i] - first_values[0][i]) for i in range(3)),
            )
        for value in last_values[1:]:
            max_last_family_channel_delta = max(
                max_last_family_channel_delta,
                max(abs(value[i] - last_values[0][i]) for i in range(3)),
            )
        for plate in plates:
            left = plate.getpixel((0, y))
            right = plate.getpixel((AUTHORED_SIZE[0] - 1, y))
            max_left_right_channel_delta = max(
                max_left_right_channel_delta,
                max(abs(left[i] - right[i]) for i in range(3)),
            )
            max_common_profile_channel_delta = max(
                max_common_profile_channel_delta,
                max(abs(left[i] - profile[y][i]) for i in range(3)),
                max(abs(right[i] - profile[y][i]) for i in range(3)),
            )
    return {
        "first_last_columns_exact_across_family": first_last_columns_exact,
        "max_first_family_channel_delta": max_first_family_channel_delta,
        "max_last_family_channel_delta": max_last_family_channel_delta,
        "max_left_right_channel_delta": max_left_right_channel_delta,
        "max_common_profile_channel_delta": max_common_profile_channel_delta,
        "reserved_strip_authored_px": SIDE_RESERVED_AUTHORED,
        "reserved_strip_runtime_px": SIDE_RESERVED_RUNTIME,
        "profile_source": "accepted plaster wall_plaster_a opposing edge average",
    }


def main() -> None:
    for directory in (AUTHORED, RUNTIME, QC, RUNTIME_EXPORT):
        directory.mkdir(parents=True, exist_ok=True)

    plaster = Image.open(PLASTER_AUTHORED).convert("RGB")
    if plaster.size != AUTHORED_SIZE:
        raise ValueError(f"accepted plaster plate is {plaster.size}, expected {AUTHORED_SIZE}")
    profile = edge_profile(plaster)
    items: list[tuple[str, Image.Image]] = []
    plates: list[Image.Image] = []
    assets: dict[str, dict[str, object]] = {}

    for name, spec in HOUSE_FEATURES.items():
        authored, crop_box = normalize_opaque(spec["source"])  # type: ignore[arg-type]
        authored = condition_vertical_seams(authored, profile)
        authored_path = AUTHORED / f"{name}.png"
        authored.save(authored_path, "PNG", optimize=False)
        runtime_export(name, authored)
        items.append((name, authored))
        plates.append(authored)
        assets[name] = {
            "kind": "new_imagegen_house_plate",
            "authored": str(authored_path.relative_to(ROOT)),
            "runtime": str((RUNTIME / f"{name}.png").relative_to(ROOT)),
            "export": str((RUNTIME_EXPORT / f"{name}.png").relative_to(APP_ROOT)),
            "raw": str(Path(spec["source"]).relative_to(ROOT)),
            "prompt": spec["prompt"],
            "crop_box_xyxy": list(crop_box),
            "main_panel": rect_dict(tuple(spec["main_panel"])),  # type: ignore[arg-type]
            "features": feature_metadata(spec["features"]),  # type: ignore[arg-type]
            "source_bottom_contact": {
                "authored_y": AUTHORED_SIZE[1],
                "runtime_y": RUNTIME_SIZE[1],
                "note": "full wall plate remains opaque and owns a straight source bottom contact",
            },
        }

    for name, spec in INSERTS.items():
        authored = composite_insert(plaster, spec)
        authored = condition_vertical_seams(authored, profile)
        authored_path = AUTHORED / f"{name}.png"
        authored.save(authored_path, "PNG", optimize=False)
        runtime_export(name, authored)
        items.append((name, authored))
        plates.append(authored)
        rect = tuple(spec["authored_rect_xyxy"])  # type: ignore[arg-type]
        assets[name] = {
            "kind": "adapted_existing_environment_raw",
            "authored": str(authored_path.relative_to(ROOT)),
            "runtime": str((RUNTIME / f"{name}.png").relative_to(ROOT)),
            "export": str((RUNTIME_EXPORT / f"{name}.png").relative_to(APP_ROOT)),
            "raw": str(Path(spec["source"]).relative_to(ROOT)),
            "original_source": spec["original_source"],
            "prompt": spec["prompt"],
            "crop_box_xyxy": list(spec["crop_box_xyxy"]),
            "main_panel": rect_dict(rect),
            "features": feature_metadata(spec["features"]),  # type: ignore[arg-type]
            "transform_proof": insert_transform_proof(spec),
            "feature_transform_proof": feature_transform_proof(spec),
            "source_bottom_contact": {
                "authored_y": AUTHORED_SIZE[1],
                "runtime_y": RUNTIME_SIZE[1],
                "insert_bottom_authored_y": rect[3],
                "insert_bottom_runtime_y": rect[3] * SCALE,
                "note": "complete source insert owns its lower contact; surrounding plate remains accepted plaster",
            },
        }

    write_contact_sheet(items)

    metadata = {
        "schema": "homebound_run.neighborhood_v1.qc.v1",
        "game": "homebound_run",
        "family": "neighborhood_v1",
        "creative_source": "built-in image_gen for two house plates; preserved existing environment raws for four adapted plates",
        "master_style_reference": "../plaster_walls_v1/processed/authored/wall_plaster_a.png",
        "authored_size": list(AUTHORED_SIZE),
        "runtime_size": list(RUNTIME_SIZE),
        "nearest_scale": SCALE,
        "world_footprint_m": list(WORLD_FOOTPRINT_M),
        "visual_contract": {
            "camera": "front-on orthographic planar wall; no baked perspective",
            "palette": "muted warm red brick and desaturated sage/blue-grey house fields, cream plaster, terracotta brick, faded teal, dark navy outlines",
            "lighting": "warm upper-right with cool lower contact weathering",
            "texture": "quiet deliberate 2x clusters and broad readable masses; no micro-noise",
            "forbidden": ["sky", "road", "rooftop", "roof cap", "border", "pilaster", "readable text", "characters", "vehicles"],
        },
        "reserved_plain_edges": {
            "authored_px": [SIDE_RESERVED_AUTHORED, SIDE_RESERVED_AUTHORED],
            "runtime_px": [SIDE_RESERVED_RUNTIME, SIDE_RESERVED_RUNTIME],
            "left_range": [0, SIDE_RESERVED_AUTHORED],
            "right_range": [AUTHORED_SIZE[0] - SIDE_RESERVED_AUTHORED, AUTHORED_SIZE[0]],
            "profile_source": "accepted plaster wall_plaster_a opposing edge average",
        },
        "assets": assets,
        "processing": {
            "aspect": "4:3 center crop with no axis stretch",
            "authored": "nearest-neighbor to 256x192 from native creative/raw source",
            "runtime": "nearest-neighbor 4x to 1024x768",
            "adapted_inserts": "nearest-neighbor crop and composite onto accepted wall_plaster_a authored plate",
            "vertical_seam_conditioning": "all six plates use the accepted plaster opposing edge average as a common y-profile; first and last authored columns match exactly and only reserved 16px strips are blended",
            "contact_sheet": "qc/neighborhood_contact_sheet.png",
        },
        "seam_qc": seam_qc(plates, profile),
    }

    for plate in assets.values():
        plate["raw_sha256"] = sha256(ROOT / str(plate["raw"]))
    (QC / "pipeline-meta.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "schema": "homebound_run.neighborhood_v1.generation_manifest.v1",
        "creative_sources": {
            "wall_house_brick": {
                "raw": "raw/wall_house_brick_raw.png",
                "prompt": "raw/wall_house_brick_prompt.txt",
                "tool": "built-in image_gen",
                "native_size": list(Image.open(RAW / "wall_house_brick_raw.png").size),
                "references": [
                    "../../../../images/homebound_run/wall_plaster_a.png",
                    "../environment/facade_homes/raw.png",
                ],
            },
            "wall_house_sage": {
                "raw": "raw/wall_house_sage_raw.png",
                "prompt": "raw/wall_house_sage_prompt.txt",
                "tool": "built-in image_gen",
                "native_size": list(Image.open(RAW / "wall_house_sage_raw.png").size),
                "references": [
                    "raw/wall_house_brick_raw.png",
                    "../../../../images/homebound_run/wall_plaster_a.png",
                ],
            },
        },
        "adapted_existing_raws": {
            name: {
                "raw": str(spec["source"].relative_to(ROOT)),
                "original_source": spec["original_source"],
                "prompt": spec["prompt"],
                "crop_box_xyxy": list(spec["crop_box_xyxy"]),
                "authored_rect_xyxy": list(spec["authored_rect_xyxy"]),
            }
            for name, spec in INSERTS.items()
        },
    }
    (ROOT / "generation-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
