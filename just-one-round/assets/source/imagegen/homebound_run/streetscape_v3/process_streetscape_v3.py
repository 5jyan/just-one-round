#!/usr/bin/env python3
"""Deterministic postprocess for homebound streetscape_v3.

Creative pixels come only from built-in ImageGen raw outputs. This processor
hardens alpha, fits each approved cutout to its authored base canvas, and
exports nearest-neighbor 4x runtime PNGs plus machine-readable QC metadata.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parent
APP_ROOT = ROOT.parents[4]
RUNTIME_ROOT = APP_ROOT / "assets" / "images" / "homebound_run"
AUTHORED_ROOT = ROOT / "processed" / "authored"
RUNTIME_PROCESSED_ROOT = ROOT / "processed" / "runtime"
QC_ROOT = ROOT / "qc"

PLATES: dict[str, dict[str, Any]] = {
    "streetscape_barricade": {
        "raw": ROOT / "barricade" / "raw" / "street_barricade_raw.png",
        "base_size": (128, 64),
        "runtime_size": (512, 256),
        "margin": 4,
        "role": "low grounded jump barricade",
        "geometry": {
            "semantic_action": "jump",
            "contact": "bottom alpha baseline",
        },
    },
    "streetscape_scaffold_crossbeam": {
        "raw": ROOT / "scaffold_crossbeam" / "raw" / "street_scaffold_crossbeam_raw.png",
        "base_size": (128, 128),
        "runtime_size": (512, 512),
        "margin": 6,
        "role": "supported low-clearance slide scaffold",
        "geometry": {
            "semantic_action": "slide",
            "total_height_m": 2.9,
            "opening_height_m": 1.0,
            "post_width_m": 0.12,
            "opening_alpha_rect_authored": (27, 79, 101, 122),
            "solid_hoarding_alpha_rect_authored": (27, 35, 101, 79),
            "contact": "bottom alpha baseline",
        },
    },
    "streetscape_covered_pallet_materials": {
        "raw": ROOT / "covered_pallets" / "raw" / "street_covered_pallet_specimen_raw.png",
        "base_size": (128, 96),
        "runtime_size": (512, 384),
        "role": "front-side-top tarp and pallet material atlas",
        "atlas_faces": {
            "front": {
                "source_box": (400, 335, 850, 775),
                "target_box": (0, 0, 64, 64),
            },
            "side": {
                "source_box": (1450, 350, 1630, 710),
                "target_box": (64, 0, 96, 64),
            },
            "top": {
                "source_box": (680, 220, 880, 320),
                "target_box": (0, 64, 64, 96),
            },
        },
        "geometry": {
            "cuboid_width_m": 1.056,
            "cuboid_height_m": 1.25,
            "cuboid_depth_m": 0.75,
            "continuous_bank_length_m": 6.0,
            "material_uv_authored": {
                "front": (0, 0, 64, 64),
                "side": (64, 0, 96, 64),
                "top": (0, 64, 64, 96),
            },
        },
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def binary_alpha(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    rgba.putalpha(alpha)
    if alpha.getbbox() is None:
        raise ValueError("transparent raw image has no visible subject after alpha threshold")
    return rgba


def fit_transparent(image: Image.Image, target: tuple[int, int], margin: int) -> tuple[Image.Image, tuple[int, int, int, int]]:
    cleaned = binary_alpha(image)
    alpha = cleaned.getchannel("A")
    bbox = alpha.getbbox()
    assert bbox is not None
    subject = cleaned.crop(bbox)
    target_width, target_height = target
    usable_width = max(1, target_width - margin * 2)
    usable_height = max(1, target_height - margin * 2)
    scale = min(usable_width / subject.width, usable_height / subject.height)
    scaled_size = (
        max(1, round(subject.width * scale)),
        max(1, round(subject.height * scale)),
    )
    scaled = subject.resize(scaled_size, Image.Resampling.NEAREST)
    output = Image.new("RGBA", target, (0, 0, 0, 0))
    left = (target_width - scaled.width) // 2
    top = target_height - margin - scaled.height
    output.alpha_composite(scaled, (left, top))
    return output, tuple(bbox)


def atlas_from_specimen(
    image: Image.Image,
    target: tuple[int, int],
    faces: dict[str, dict[str, tuple[int, int, int, int]]],
) -> tuple[Image.Image, dict[str, Any], tuple[int, int, int, int]]:
    cleaned = binary_alpha(image)
    source_alpha = cleaned.getchannel("A")
    source_bbox = source_alpha.getbbox()
    assert source_bbox is not None
    atlas = Image.new("RGBA", target, (0, 0, 0, 0))
    face_meta: dict[str, Any] = {}
    face_root = ROOT / "processed" / "material-faces"
    face_root.mkdir(parents=True, exist_ok=True)
    for face_name, face in faces.items():
        source_box = tuple(face["source_box"])
        target_box = tuple(face["target_box"])
        source_patch = cleaned.crop(source_box)
        target_size = (target_box[2] - target_box[0], target_box[3] - target_box[1])
        patch = source_patch.resize(target_size, Image.Resampling.NEAREST)
        atlas.alpha_composite(patch, (target_box[0], target_box[1]))
        face_path = face_root / f"streetscape_covered_pallet_{face_name}.png"
        patch.save(face_path, "PNG", optimize=False)
        face_alpha = patch.getchannel("A")
        face_meta[face_name] = {
            "source_box_raw": list(source_box),
            "target_box_authored": list(target_box),
            "target_size_authored": list(target_size),
            "processed_face": str(face_path),
            "source_patch_alpha_bbox": list(source_patch.getchannel("A").getbbox() or (0, 0, 0, 0)),
            "face_alpha_bbox": list(face_alpha.getbbox() or (0, 0, 0, 0)),
        }
    return atlas, face_meta, tuple(source_bbox)


def process_asset(name: str, spec: dict[str, Any]) -> dict[str, Any]:
    raw_path = Path(spec["raw"])
    if not raw_path.is_file():
        raise FileNotFoundError(raw_path)
    source = Image.open(raw_path)
    face_meta: dict[str, Any] | None = None
    if "atlas_faces" in spec:
        authored, face_meta, raw_bbox = atlas_from_specimen(
            source,
            spec["base_size"],
            spec["atlas_faces"],
        )
    else:
        authored, raw_bbox = fit_transparent(source, spec["base_size"], spec["margin"])
    authored_path = AUTHORED_ROOT / f"{name}.png"
    processed_runtime_path = RUNTIME_PROCESSED_ROOT / f"{name}.png"
    runtime_path = RUNTIME_ROOT / f"{name}.png"
    authored_path.parent.mkdir(parents=True, exist_ok=True)
    processed_runtime_path.parent.mkdir(parents=True, exist_ok=True)
    runtime_path.parent.mkdir(parents=True, exist_ok=True)
    authored.save(authored_path, "PNG", optimize=False)
    runtime = authored.resize(spec["runtime_size"], Image.Resampling.NEAREST)
    runtime.save(processed_runtime_path, "PNG", optimize=False)
    runtime.save(runtime_path, "PNG", optimize=False)
    alpha = authored.getchannel("A")
    authored_bbox = alpha.getbbox()
    assert authored_bbox is not None
    runtime_alpha = runtime.getchannel("A")
    runtime_bbox = runtime_alpha.getbbox()
    assert runtime_bbox is not None
    result: dict[str, Any] = {
        "name": name,
        "role": spec["role"],
        "geometry": spec.get("geometry", {}),
        "raw": str(raw_path),
        "raw_size": list(source.size),
        "raw_sha256": sha256(raw_path),
        "raw_alpha_bbox_threshold_128": list(raw_bbox),
        "authored": str(authored_path),
        "authored_size": list(authored.size),
        "authored_alpha_bbox": list(authored_bbox),
        "authored_alpha_edge_max": max(
            max(alpha.crop((0, 0, alpha.width, 1)).getdata()),
            max(alpha.crop((0, alpha.height - 1, alpha.width, alpha.height)).getdata()),
            max(alpha.crop((0, 0, 1, alpha.height)).getdata()),
            max(alpha.crop((alpha.width - 1, 0, alpha.width, alpha.height)).getdata()),
        ),
        "runtime": str(runtime_path),
        "runtime_size": list(runtime.size),
        "runtime_alpha_bbox": list(runtime_bbox),
        "runtime_alpha_edge_max": max(
            max(runtime_alpha.crop((0, 0, runtime_alpha.width, 1)).getdata()),
            max(runtime_alpha.crop((0, runtime_alpha.height - 1, runtime_alpha.width, runtime_alpha.height)).getdata()),
            max(runtime_alpha.crop((0, 0, 1, runtime_alpha.height)).getdata()),
            max(runtime_alpha.crop((runtime_alpha.width - 1, 0, runtime_alpha.width, runtime_alpha.height)).getdata()),
        ),
        "fit_margin_authored": spec.get("margin"),
        "scale": "nearest_neighbor_4x",
    }
    if face_meta is not None:
        result["atlas_faces"] = face_meta
        result["atlas_layout"] = {
            "front": [0, 0, 64, 64],
            "side": [64, 0, 96, 64],
            "top": [0, 64, 64, 96],
            "remaining_authored_canvas": "transparent",
        }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", choices=["all", *PLATES], default="all")
    args = parser.parse_args()
    names = list(PLATES) if args.asset == "all" else [args.asset]
    report_path = QC_ROOT / "pipeline-meta.json"
    QC_ROOT.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = {
        "schema": "homebound_run.streetscape_v3_qc.v1",
        "creative_source": "built-in ImageGen",
        "processing": "binary alpha cleanup, transparent fit, nearest-neighbor 4x",
        "assets": {},
    }
    for name in names:
        report["assets"][name] = process_asset(name, PLATES[name])
    if report_path.exists() and args.asset != "all":
        old = json.loads(report_path.read_text())
        old.update({key: value for key, value in report.items() if key != "assets"})
        old.setdefault("assets", {}).update(report["assets"])
        report = old
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
