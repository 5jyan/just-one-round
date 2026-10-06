#!/usr/bin/env python3
"""Assemble the approved Wind Darts v3 UI sprites.

This processor deliberately has no drawing primitives for new artwork.  It only
cleans the alpha supplied by ImageGen, crops complete subjects, applies the
approved quiet paper brightness normalization, and performs nearest-neighbour
base-grid assembly.  Pass the two ImageGen raw files explicitly so the script
can run on another checkout without relying on a machine-specific generated
image path.

Usage:
    python3 tool/assemble_wind_darts_ui.py \
      --paper-raw /path/to/paper.png \
      --gauge-raw /path/to/gauge.png

The gauge source is one transparent 1536x1024 image containing an upper frame
and a lower fill.  Its two horizontal bands are detected independently and
written to their exact runtime canvases.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageChops, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
WIND_DARTS = ROOT / "assets" / "images" / "wind_darts"
SOURCE_ROOT = ROOT / "assets" / "source" / "imagegen" / "wind_darts"
V3_ROOT = SOURCE_ROOT / "v3_ui"
QC_ROOT = V3_ROOT / "qc"
PIPELINE_META = SOURCE_ROOT / "pipeline-meta.json"

ALPHA_THRESHOLD = 8
NEAREST = Image.Resampling.NEAREST


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--paper-raw",
        type=Path,
        required=True,
        help="ImageGen RGBA paper source; copied to v3_ui/paper_raw.png",
    )
    parser.add_argument(
        "--gauge-raw",
        type=Path,
        required=True,
        help="ImageGen RGBA gauge sheet; copied to v3_ui/gauge_raw.png",
    )
    parser.add_argument(
        "--paper-prompt",
        type=Path,
        help="Optional exact prompt file to preserve beside paper_raw.png",
    )
    parser.add_argument(
        "--gauge-prompt",
        type=Path,
        help="Optional exact prompt file to preserve beside gauge_raw.png",
    )
    parser.add_argument(
        "--skip-composite",
        action="store_true",
        help="Skip the optional 360x640 composition when board/pub assets are absent",
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_source(path: Path, label: str) -> Path:
    if not path.is_file():
        raise FileNotFoundError(f"{label} source does not exist: {path}")
    return path


def copy_source(path: Path, name: str) -> Path:
    destination = V3_ROOT / name
    shutil.copyfile(path, destination)
    return destination


def clean_alpha(image: Image.Image, threshold: int = ALPHA_THRESHOLD) -> Image.Image:
    """Remove only near-zero generated fringe while preserving source alpha."""

    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    # A hard cutoff prevents invisible ImageGen specks from creating a giant
    # crop box.  Alpha values at or above the threshold remain untouched.
    keep = alpha.point(lambda value: 255 if value >= threshold else 0)
    cleaned_alpha = ImageChops.multiply(alpha, keep)
    rgba.putalpha(cleaned_alpha)
    return rgba


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("ImageGen source has no visible alpha subject")
    return bbox


def crop_alpha_subject(image: Image.Image) -> Image.Image:
    return image.crop(alpha_bbox(image))


def dim_paper_if_bright(image: Image.Image) -> tuple[Image.Image, float]:
    """Quiet the supplied parchment against the dark pub by 12% when needed."""

    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    visible = alpha.getbbox()
    if visible is None:
        return rgba, 1.0
    rgb = rgba.convert("RGB")
    stats = rgb.crop(visible).getdata()
    # The approved raw render is bright oatmeal.  Keep the normalization
    # deterministic and small; avoid repainting or inventing paper texture.
    luma = sum((0.2126 * r + 0.7152 * g + 0.0722 * b) for r, g, b in stats) / max(
        1, len(stats)
    )
    factor = 0.88 if luma > 165 else 1.0
    if factor != 1.0:
        rgb = ImageEnhance.Brightness(rgb).enhance(factor)
    rgb.putalpha(alpha)
    return rgb, factor


def fit_wide_with_source_margin(
    subject: Image.Image,
    target: tuple[int, int],
    margin: int = 2,
    vertical_margin: int = 0,
) -> Image.Image:
    """Fit a wide subject with a two-source-pixel horizontal safe margin.

    Gauge frame/fill ratios are intentionally wide enough that a large margin
    on all four sides would shrink them or distort their approved trough
    geometry. We reserve a small source-grid margin on every side while
    retaining the full-width horizontal treatment.
    """

    target_w, target_h = target
    width = max(1, target_w - margin * 2)
    height = max(1, target_h - vertical_margin * 2)
    # The generated frame/fill ratios are close to their exact runtime
    # contracts.  A deterministic fit to the inner contract preserves the
    # intended full-width trough instead of shrinking it to a narrow strip.
    resized = subject.resize((width, height), NEAREST)
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    x = margin
    y = vertical_margin
    canvas.alpha_composite(resized, (x, y))
    return canvas


def fit_paper(subject: Image.Image) -> Image.Image:
    """Assemble a 120x160 source grid with two-pixel margins, then export 2x."""

    target_base = (120, 160)
    usable = (116, 156)
    source_w, source_h = subject.size
    scale = min(usable[0] / source_w, usable[1] / source_h)
    width = max(1, round(source_w * scale))
    height = max(1, round(source_h * scale))
    resized = subject.resize((width, height), NEAREST)
    base = Image.new("RGBA", target_base, (0, 0, 0, 0))
    x = (target_base[0] - width) // 2
    y = (target_base[1] - height) // 2
    base.alpha_composite(resized, (x, y))
    return base.resize((240, 320), NEAREST)


def row_band_bboxes(image: Image.Image) -> list[tuple[int, int, int, int]]:
    """Return upper/lower alpha subjects while ignoring diffuse glow tails.

    The generated sheet has a handful of low-area alpha rows below the upper
    frame.  The main object is selected from rows carrying at least 20% of the
    sheet width, then expanded through directly adjacent alpha rows so stepped
    corners and attached shadows remain in the crop.
    """

    alpha = image.getchannel("A")
    width, height = image.size
    midpoint = height // 2
    row_counts: list[int] = []
    alpha_rows = alpha.load()
    for y in range(height):
        row_counts.append(sum(1 for x in range(width) if alpha_rows[x, y] >= ALPHA_THRESHOLD))
    boxes: list[tuple[int, int, int, int]] = []
    for y0, y1 in ((0, midpoint), (midpoint, height)):
        significant = [
            y for y in range(y0, y1) if row_counts[y] >= max(20, width // 5)
        ]
        if not significant:
            raise ValueError(f"Gauge band {y0}:{y1} has no substantial alpha subject")
        main_start, main_end = min(significant), max(significant)
        start = main_start
        while start > y0 and row_counts[start - 1] > 0:
            start -= 1
        end = main_end + 1
        x0, x1 = width, 0
        for y in range(start, end):
            for x in range(width):
                if alpha_rows[x, y] >= ALPHA_THRESHOLD:
                    x0 = min(x0, x)
                    x1 = max(x1, x + 1)
        if x0 >= x1:
            raise ValueError(f"Gauge band {y0}:{y1} has no visible alpha subject")
        boxes.append((x0, start, x1, end))
    if boxes[0][1] >= boxes[1][1]:
        raise ValueError(f"Gauge bands are not ordered top-to-bottom: {boxes}")
    return boxes


def process_paper(raw_path: Path) -> tuple[Path, dict]:
    image = clean_alpha(Image.open(raw_path))
    normalized, brightness_factor = dim_paper_if_bright(image)
    subject = crop_alpha_subject(normalized)
    output = fit_paper(subject)
    destination = WIND_DARTS / "score_parchment.png"
    output.save(destination, format="PNG", optimize=False)
    return destination, {
        "raw_dimensions": list(image.size),
        "raw_mode": image.mode,
        "raw_alpha_bbox": list(alpha_bbox(image)),
        "subject_dimensions": list(subject.size),
        "base_grid": [120, 160],
        "output_dimensions": list(output.size),
        "output_sha256": sha256(destination),
        "display_scale": 2,
        "subject_margin_base_pixels": 2,
        "brightness_factor": brightness_factor,
        "alpha_threshold": ALPHA_THRESHOLD,
        "resampling": "nearest-neighbor",
    }


def process_gauge(raw_path: Path) -> tuple[dict[str, Path], dict]:
    image = clean_alpha(Image.open(raw_path))
    boxes = row_band_bboxes(image)
    names = (
        ("frame", (320, 36), "aim_gauge_frame.png"),
        ("fill", (304, 12), "aim_gauge_fill.png"),
    )
    outputs: dict[str, Path] = {}
    entries: dict[str, dict] = {}
    for (role, target_base, filename), box in zip(names, boxes):
        subject = image.crop(box)
        output_base = fit_wide_with_source_margin(
            subject,
            target_base,
            margin=2,
            vertical_margin=2 if role == "frame" else 1,
        )
        output = output_base.resize((target_base[0] * 2, target_base[1] * 2), NEAREST)
        destination = WIND_DARTS / filename
        output.save(destination, format="PNG", optimize=False)
        outputs[role] = destination
        entries[role] = {
            "raw_dimensions": list(image.size),
            "raw_mode": image.mode,
            "raw_alpha_bbox": list(box),
            "subject_dimensions": list(subject.size),
            "base_grid": list(target_base),
            "output_dimensions": list(output.size),
            "output_sha256": sha256(destination),
            "display_scale": 2,
            "subject_margin_base_pixels": {
                "horizontal": 2,
                "vertical": 2 if role == "frame" else 1,
            },
            "alpha_threshold": ALPHA_THRESHOLD,
            "resampling": "nearest-neighbor",
            "source_band": "upper" if role == "frame" else "lower",
        }
    return outputs, entries


def alpha_report(path: Path, allow_edge_axes: Iterable[str] = ()) -> dict:
    image = Image.open(path).convert("RGBA")
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise AssertionError(f"{path} is empty")
    width, height = image.size
    allowed = set(allow_edge_axes)
    edge_axes = []
    if bbox[0] == 0 or bbox[2] == width:
        edge_axes.append("horizontal")
    if bbox[1] == 0 or bbox[3] == height:
        edge_axes.append("vertical")
    touches_edge = bool(edge_axes)
    unexpected_edges = [axis for axis in edge_axes if axis not in allowed]
    if unexpected_edges:
        raise AssertionError(f"{path} subject touches output edge: {bbox} / {image.size}")
    return {
        "dimensions": list(image.size),
        "mode": image.mode,
        "alpha_bbox": list(bbox),
        "alpha_pixels": sum(alpha.histogram()[1:]),
        "alpha_partial_pixels": sum(alpha.histogram()[1:255]),
        "touches_edge": touches_edge,
        "allowed_edge_axes": sorted(allowed),
        "edge_axes": sorted(set(edge_axes)),
    }


def darken_pub_crop() -> Image.Image:
    path = WIND_DARTS / "pub_interior.png"
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    target_w, target_h = 360, 640
    scale = max(target_w / width, target_h / height)
    resized = image.resize((round(width * scale), round(height * scale)), NEAREST)
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    canvas = resized.crop((left, top, left + target_w, top + target_h))
    canvas = ImageEnhance.Brightness(canvas).enhance(0.56)
    overlay = Image.new("RGBA", canvas.size, (20, 13, 7, 78))
    canvas.alpha_composite(overlay)
    return canvas


def make_composition_qc() -> Path | None:
    board_path = WIND_DARTS / "board_face.png"
    pub_path = WIND_DARTS / "pub_interior.png"
    paper_path = WIND_DARTS / "score_parchment.png"
    frame_path = WIND_DARTS / "aim_gauge_frame.png"
    fill_path = WIND_DARTS / "aim_gauge_fill.png"
    if not all(path.is_file() for path in (board_path, pub_path, paper_path, frame_path, fill_path)):
        return None

    canvas = darken_pub_crop()
    board = Image.open(board_path).convert("RGBA").resize((286, 286), NEAREST)
    canvas.alpha_composite(board, ((360 - board.width) // 2, 198))
    parchment = Image.open(paper_path).convert("RGBA").resize((120, 160), NEAREST)
    canvas.alpha_composite(parchment, (120, 72))
    frame = Image.open(frame_path).convert("RGBA").resize((320, 36), NEAREST)
    fill = Image.open(fill_path).convert("RGBA").resize((304, 12), NEAREST)
    canvas.alpha_composite(frame, (20, 580))
    canvas.alpha_composite(fill, (28, 592))
    destination = QC_ROOT / "composition-360x640.png"
    canvas.convert("RGB").save(destination, format="PNG", optimize=False)
    return destination


def source_entry(path: Path, prompt_name: str | None = None) -> dict:
    entry = {
        "path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
        "sha256": sha256(path),
        "dimensions": list(Image.open(path).size),
        "mode": Image.open(path).mode,
        "provenance": "Codex built-in ImageGen",
    }
    if prompt_name:
        prompt = V3_ROOT / prompt_name
        if prompt.is_file():
            entry["prompt"] = str(prompt.relative_to(ROOT))
            entry["prompt_sha256"] = sha256(prompt)
    return entry


def update_pipeline_meta(meta: dict, processing_meta: dict, sources: dict) -> None:
    assets = meta.setdefault("assets", {})
    assets.update(
        {
            "score_parchment.png": {
                "source": "assets/source/imagegen/wind_darts/v3_ui/paper_raw.png plus deterministic alpha crop/nearest assembly",
                "dimensions": [240, 320],
                "alpha": True,
                "runtime_role": "blank score parchment UI panel",
                "runtime_filter": "nearest",
            },
            "aim_gauge_frame.png": {
                "source": "assets/source/imagegen/wind_darts/v3_ui/gauge_raw.png upper band plus deterministic alpha crop/nearest assembly",
                "dimensions": [640, 72],
                "alpha": True,
                "runtime_role": "full aim gauge frame",
                "runtime_filter": "nearest",
            },
            "aim_gauge_fill.png": {
                "source": "assets/source/imagegen/wind_darts/v3_ui/gauge_raw.png lower band plus deterministic alpha crop/nearest assembly",
                "dimensions": [608, 24],
                "alpha": True,
                "runtime_role": "aim gauge fill",
                "runtime_filter": "nearest",
            },
        }
    )
    meta["v3_ui"] = {
        "status": "approved_production",
        "master_reference": "assets/images/wind_darts/pub_interior.png",
        "style": "quiet aged parchment and matte dark bronze/oatmeal gauge textures; crisp clustered pixel art",
        "source_images": sources,
        "outputs": {
            "score_parchment.png": processing_meta["paper"],
            "aim_gauge_frame.png": processing_meta["gauge"]["frame"],
            "aim_gauge_fill.png": processing_meta["gauge"]["fill"],
        },
        "processor": "tool/assemble_wind_darts_ui.py",
        "resampling": "nearest-neighbor only",
        "creative_edits": False,
        "qc": processing_meta["qc"],
    }


def write_processing_meta(meta: dict) -> None:
    destination = V3_ROOT / "processing-meta.json"
    destination.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")


def main() -> int:
    args = parse_args()
    paper_raw = ensure_source(args.paper_raw.resolve(), "paper")
    gauge_raw = ensure_source(args.gauge_raw.resolve(), "gauge")
    V3_ROOT.mkdir(parents=True, exist_ok=True)
    QC_ROOT.mkdir(parents=True, exist_ok=True)
    WIND_DARTS.mkdir(parents=True, exist_ok=True)

    paper_copy = copy_source(paper_raw, "paper_raw.png")
    gauge_copy = copy_source(gauge_raw, "gauge_raw.png")
    for prompt, name in ((args.paper_prompt, "paper.prompt.txt"), (args.gauge_prompt, "gauge.prompt.txt")):
        if prompt is not None:
            ensure_source(prompt.resolve(), "prompt")
            destination = V3_ROOT / name
            if prompt.resolve() != destination.resolve():
                shutil.copyfile(prompt, destination)

    paper_output, paper_meta = process_paper(paper_copy)
    gauge_outputs, gauge_meta = process_gauge(gauge_copy)
    paper_qc = alpha_report(paper_output)
    frame_qc = alpha_report(gauge_outputs["frame"])
    fill_qc = alpha_report(gauge_outputs["fill"])

    composition = None if args.skip_composite else make_composition_qc()
    if composition is not None:
        composition_meta = {"path": str(composition.relative_to(ROOT)), "dimensions": [360, 640]}
    else:
        composition_meta = {"pending": True, "reason": "board_face.png or pub_interior.png unavailable"}

    processing_meta = {
        "contract": {
            "paper_output": [240, 320],
            "gauge_frame_output": [640, 72],
            "gauge_fill_output": [608, 24],
            "base_grid_scale": 2,
            "runtime_frame_rect": [20, 580, 320, 36],
            "runtime_fill_rect": [28, 592, 304, 12],
        },
        "sources": {
            "paper": source_entry(paper_copy, "paper.prompt.txt"),
            "gauge": source_entry(gauge_copy, "gauge.prompt.txt"),
        },
        "paper": paper_meta,
        "gauge": gauge_meta,
        "processing": {
            "alpha_threshold": ALPHA_THRESHOLD,
            "crop": "tight alpha subject crop; upper/lower horizontal bands for gauge",
            "resampling": "nearest-neighbor",
            "creative_raster_drawing": False,
            "paper_brightness_normalization": "12% deterministic dim when visible mean luma exceeds 165",
        },
        "qc": {
            "paper": paper_qc,
            "frame": frame_qc,
            "fill": fill_qc,
            "composition": composition_meta,
        },
    }
    write_processing_meta(processing_meta)

    pipeline = json.loads(PIPELINE_META.read_text()) if PIPELINE_META.exists() else {"game": "wind_darts"}
    update_pipeline_meta(
        pipeline,
        processing_meta,
        {
            "paper": source_entry(paper_copy, "paper.prompt.txt"),
            "gauge": source_entry(gauge_copy, "gauge.prompt.txt"),
        },
    )
    PIPELINE_META.write_text(json.dumps(pipeline, ensure_ascii=False, indent=2) + "\n")

    print(f"paper: {paper_output}")
    print(f"gauge frame: {gauge_outputs['frame']}")
    print(f"gauge fill: {gauge_outputs['fill']}")
    print(f"processing metadata: {V3_ROOT / 'processing-meta.json'}")
    if composition is not None:
        print(f"composition QC: {composition}")
    else:
        print("composition QC: pending board_face.png and pub_interior.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
