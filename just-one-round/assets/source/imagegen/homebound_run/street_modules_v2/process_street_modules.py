#!/usr/bin/env python3
"""Normalize the complete street facade plates for runtime.

All architectural pixels come from the preserved built-in ImageGen raws. The
pipeline only performs deterministic 4:3 normalization, nearest-neighbor
authored-grid reduction, 4x runtime export, clean material swatch extraction,
feature UV metadata, contact-sheet generation, and QC.
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
SWATCHES = ROOT / "processed" / "material-swatches"
QC = ROOT / "qc"
APP_ROOT = ROOT.parents[4]
RUNTIME_EXPORT = APP_ROOT / "assets" / "images" / "homebound_run"

AUTHORED_SIZE = (256, 192)
RUNTIME_SIZE = (1024, 768)
SCALE = 4
WORLD_FOOTPRINT_M = (7.333, 5.5)

# Authored-grid x0/y0 inclusive, x1/y1 exclusive rectangles. These are
# measured from the normalized 256x192 plates, then converted to runtime UVs.
PLATES: dict[str, dict[str, object]] = {
    "street_house_brick": {
        "raw": RAW / "street_brickhouse_raw.png",
        "prompt": "raw/street_brickhouse_prompt.txt",
        "description": "complete full-bleed warm red brick two-story house facade",
        "material": "warm terracotta and muted red brick",
        "material_swatch": (8, 128, 40, 160),
        "features": {
            "door": (149, 108, 188, 192),
            "entry_frame": (141, 88, 190, 192),
            "window": [(31, 25, 117, 73), (160, 25, 206, 75)],
            "awning": (123, 82, 206, 92),
            "canopy": (123, 82, 206, 92),
            "sill": [(31, 69, 117, 79), (160, 70, 206, 80)],
            "meter": (210, 106, 226, 127),
            "planter": (17, 50, 138, 94),
        },
        "references": [
            "../../../../images/homebound_run/wall_house_brick.png",
            "../environment/facade_homes/raw.png",
        ],
        "generator_output": "$HOME/.codex/generated_images/01a160a0-6cd8-71e0-b824-1ac41fde3ce7/exec-96b79bb1-7497-4667-86cf-28eca540de81.png",
    },
    "street_house_sage": {
        "raw": RAW / "street_sagehouse_raw.png",
        "prompt": "raw/street_sagehouse_prompt.txt",
        "description": "complete full-bleed desaturated sage and blue-grey two-story house facade",
        "material": "desaturated sage green and blue-grey painted facade",
        "material_swatch": (8, 144, 40, 176),
        "features": {
            "door": (149, 112, 193, 192),
            "entry_frame": (136, 84, 196, 192),
            "window": [(33, 25, 130, 70), (160, 25, 210, 71), (33, 100, 105, 144)],
            "awning": (134, 81, 211, 89),
            "canopy": (134, 81, 211, 89),
            "sill": [(33, 66, 130, 76), (160, 67, 210, 77), (33, 139, 100, 145)],
            "meter": (214, 102, 230, 123),
            "planter": (18, 49, 146, 91),
        },
        "references": [
            "raw/street_brickhouse_raw.png",
            "../../../../images/homebound_run/wall_house_sage.png",
        ],
        "generator_output": "$HOME/.codex/generated_images/01a160a0-6cd8-71e0-b824-1ac41fde3ce7/exec-7d0e72f4-d46b-48f9-b385-a61925468163.png",
    },
    "street_shopfront": {
        "raw": RAW / "street_shopfront_raw.png",
        "prompt": "raw/street_shopfront_prompt.txt",
        "description": "complete full-bleed two-story neighborhood shop with teal shutter",
        "material": "faded teal and deep blue-green shop facade",
        "material_swatch": (144, 0, 176, 32),
        "features": {
            "door": (186, 116, 214, 192),
            "entry_frame": (181, 100, 217, 192),
            "shutter": (30, 110, 178, 192),
            "window": [(28, 31, 65, 66), (82, 31, 160, 66), (181, 31, 218, 67)],
            "awning": (11, 83, 179, 100),
            "sill": [(28, 62, 65, 71), (79, 63, 164, 70), (181, 63, 218, 72)],
            "meter": (226, 108, 242, 127),
        },
        "references": [
            "raw/street_brickhouse_raw.png",
        ],
        "generator_output": "$HOME/.codex/generated_images/01a160a0-6cd8-71e0-b824-1ac41fde3ce7/exec-54454804-4100-4c5f-8044-e9fb7b508c34.png",
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


def normalize_raw(path: Path) -> tuple[Image.Image, tuple[int, int, int, int]]:
    source = Image.open(path).convert("RGB")
    cropped, crop_box = crop_to_aspect(source, AUTHORED_SIZE[0] / AUTHORED_SIZE[1])
    return cropped.resize(AUTHORED_SIZE, Image.Resampling.NEAREST), crop_box


def rect_dict(rect: tuple[int, int, int, int]) -> dict[str, object]:
    x0, y0, x1, y1 = rect
    data: dict[str, object] = {
        "authored_rect_xyxy": list(rect),
        "normalized_rect_xyxy": [x0 / 256, y0 / 192, x1 / 256, y1 / 192],
        "runtime_rect_xyxy": [x0 * SCALE, y0 * SCALE, x1 * SCALE, y1 * SCALE],
    }
    if y1 > y0:
        data["vertical_span_world_m"] = round((y1 - y0) / AUTHORED_SIZE[1] * WORLD_FOOTPRINT_M[1], 3)
    return data


def feature_metadata(features: dict[str, object]) -> dict[str, object]:
    output: dict[str, object] = {}
    for kind, rects in features.items():
        if isinstance(rects, list) and rects and isinstance(rects[0], (list, tuple)):
            output[kind] = [rect_dict(tuple(rect)) for rect in rects]  # type: ignore[arg-type]
        else:
            output[kind] = rect_dict(tuple(rects))  # type: ignore[arg-type]
    return output


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def runtime_export(name: str, authored: Image.Image) -> None:
    runtime = authored.convert("RGB").resize(RUNTIME_SIZE, Image.Resampling.NEAREST)
    runtime_path = RUNTIME / f"{name}.png"
    export_path = RUNTIME_EXPORT / f"{name}.png"
    runtime.save(runtime_path, "PNG", optimize=False)
    export_path.parent.mkdir(parents=True, exist_ok=True)
    runtime.save(export_path, "PNG", optimize=False)


def write_contact_sheet(items: list[tuple[str, Image.Image]]) -> None:
    thumb_size = (512, 384)
    label_h = 30
    sheet = Image.new("RGB", (thumb_size[0] * len(items), thumb_size[1] + label_h), (30, 34, 48))
    draw = ImageDraw.Draw(sheet)
    for index, (name, image) in enumerate(items):
        x = index * thumb_size[0]
        sheet.paste(image.resize(thumb_size, Image.Resampling.NEAREST), (x, 0))
        draw.rectangle((x, thumb_size[1], x + thumb_size[0], thumb_size[1] + label_h), fill=(30, 34, 48))
        draw.text((x + 8, thumb_size[1] + 7), name, fill=(240, 236, 220))
    sheet.save(QC / "street_modules_contact_sheet.png", "PNG", optimize=False)


def write_swatch_sheet(swatches: list[tuple[str, Image.Image]]) -> None:
    scale = 8
    label_h = 28
    sheet = Image.new("RGB", (32 * scale * len(swatches), 32 * scale + label_h), (30, 34, 48))
    draw = ImageDraw.Draw(sheet)
    for index, (name, swatch) in enumerate(swatches):
        x = index * 32 * scale
        sheet.paste(swatch.resize((32 * scale, 32 * scale), Image.Resampling.NEAREST), (x, 0))
        draw.text((x + 4, 32 * scale + 6), name, fill=(240, 236, 220))
    sheet.save(QC / "street_material_swatches.png", "PNG", optimize=False)


def main() -> None:
    for directory in (AUTHORED, RUNTIME, SWATCHES, QC, RUNTIME_EXPORT):
        directory.mkdir(parents=True, exist_ok=True)

    items: list[tuple[str, Image.Image]] = []
    swatches: list[tuple[str, Image.Image]] = []
    assets: dict[str, dict[str, object]] = {}

    for name, spec in PLATES.items():
        authored, crop_box = normalize_raw(spec["raw"])  # type: ignore[arg-type]
        authored_path = AUTHORED / f"{name}.png"
        authored.save(authored_path, "PNG", optimize=False)
        runtime_export(name, authored)
        items.append((name, authored))

        swatch_rect = tuple(spec["material_swatch"])  # type: ignore[arg-type]
        swatch = authored.crop(swatch_rect).convert("RGB")
        if swatch.size != (32, 32):
            raise ValueError(f"material swatch for {name} is {swatch.size}, expected 32x32")
        swatch_path = SWATCHES / f"{name}_material_32x32.png"
        swatch.save(swatch_path, "PNG", optimize=False)
        swatches.append((name, swatch))

        assets[name] = {
            "kind": "fullbleed_imagegen_facade",
            "authored": str(authored_path.relative_to(ROOT)),
            "runtime": str((RUNTIME / f"{name}.png").relative_to(ROOT)),
            "export": str((RUNTIME_EXPORT / f"{name}.png").relative_to(APP_ROOT)),
            "raw": str(Path(spec["raw"]).relative_to(ROOT)),
            "prompt": spec["prompt"],
            "crop_box_xyxy": list(crop_box),
            "front_source_rect": rect_dict((0, 0, 256, 192)),
            "fullbleed": True,
            "material": spec["material"],
            "material_swatch": {
                **rect_dict(swatch_rect),
                "source": str(swatch_path.relative_to(ROOT)),
                "authored_size": [32, 32],
                "world_size_m": [round(32 / 256 * WORLD_FOOTPRINT_M[0], 4), round(32 / 192 * WORLD_FOOTPRINT_M[1], 4)],
                "clean_material_only": True,
                "selection_note": "measured feature-free facade material patch; no object or cast shadow",
            },
            "features": feature_metadata(spec["features"]),  # type: ignore[arg-type]
            "door_contract": {
                "bottom_authored_y": 192,
                "target_height_world_m": 2.1,
                "measured_height_world_m": feature_metadata({"door": spec["features"]["door"]})["door"]["vertical_span_world_m"],  # type: ignore[index]
            },
            "source_bottom_contact": {
                "authored_y": 192,
                "runtime_y": 768,
                "role": "facade material owns the lower contact; runtime geometry supplies road/depth",
            },
            "raw_sha256": sha256(Path(spec["raw"])),  # type: ignore[arg-type]
        }

    write_contact_sheet(items)
    write_swatch_sheet(swatches)

    metadata = {
        "schema": "homebound_run.street_modules_v2.qc.v1",
        "game": "homebound_run",
        "family": "street_modules_v2",
        "creative_source": "built-in image_gen only",
        "authored_size": list(AUTHORED_SIZE),
        "runtime_size": list(RUNTIME_SIZE),
        "nearest_scale": SCALE,
        "world_footprint_m": list(WORLD_FOOTPRINT_M),
        "visual_contract": {
            "camera": "front-on orthographic full facade plane; no baked perspective",
            "material": "each plate reaches all four edges with its own brick, sage/blue-grey, or teal building material",
            "proportions": "upright two-story facade crop; grounded door or shutter at bottom; no visible roof",
            "lighting": "warm diffuse upper-right with cool recesses; no large baked projection shadows",
            "texture": "quiet refined 32-bit clusters and broad readable material fields",
            "forbidden": ["white border", "surrounding plaster canvas", "sky", "road", "ground plane", "roof slope", "rooftop", "perspective", "isometric view", "readable text", "characters", "vehicles"],
        },
        "assets": assets,
        "processing": {
            "aspect": "native 4:3 source retained; center crop only if needed",
            "authored": "nearest-neighbor to 256x192 from native creative source",
            "runtime": "nearest-neighbor 4x to 1024x768",
            "front_source_rect": "always full authored plate [0,0,256,192]; no trimmed content bbox",
            "material_swatches": "deterministic 32x32 authored extracts preserved under processed/material-swatches",
            "contact_sheet": "qc/street_modules_contact_sheet.png",
        },
    }
    (QC / "pipeline-meta.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    manifest = {
        "schema": "homebound_run.street_modules_v2.generation_manifest.v1",
        "tool": "built-in image_gen",
        "plates": {
            name: {
                "raw": str(Path(spec["raw"]).relative_to(ROOT)),
                "prompt": spec["prompt"],
                "native_size": list(Image.open(spec["raw"]).size),  # type: ignore[arg-type]
                "references": spec["references"],
                "generator_output": spec["generator_output"],
            }
            for name, spec in PLATES.items()
        },
        "contract": {
            "authored_size": list(AUTHORED_SIZE),
            "runtime_size": list(RUNTIME_SIZE),
            "world_footprint_m": list(WORLD_FOOTPRINT_M),
            "fullbleed": True,
            "no_white_canvas": True,
        },
    }
    (ROOT / "generation-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
