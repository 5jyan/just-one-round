#!/usr/bin/env python3
"""Convert generated app-icon concepts to a strict low-resolution pixel grid."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageOps


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = (
    PROJECT_ROOT / "assets/source/imagegen/app_icon_concepts_20260727"
)

CONCEPTS = {
    "concept-a-red-button": Path(
        "/Users/saulpark/.codex/generated_images/"
        "019f9ef9-07f1-70f2-bb91-1d0e670a88eb/"
        "call_KBmte3JKPnzvhGgxnyWH465g.png"
    ),
    "concept-b-trophy-one": Path(
        "/Users/saulpark/.codex/generated_images/"
        "019f9ef9-07f1-70f2-bb91-1d0e670a88eb/"
        "call_9VVXF6DEAw6nnBqslv1MJ1R3.png"
    ),
    "concept-c-one-coin": Path(
        "/Users/saulpark/.codex/generated_images/"
        "019f9ef9-07f1-70f2-bb91-1d0e670a88eb/"
        "call_Sfi5MLCuVuGUe1oDllayJwtV.png"
    ),
    "concept-d-start-lever": Path(
        "/Users/saulpark/.codex/generated_images/"
        "019f9ef9-07f1-70f2-bb91-1d0e670a88eb/"
        "call_Sh7yzA9QNy0UEWxHgEgZ2giB.png"
    ),
    "concept-e-crowned-one": Path(
        "/Users/saulpark/.codex/generated_images/"
        "019f9ef9-07f1-70f2-bb91-1d0e670a88eb/"
        "call_zuvkI7oLh6R4LiZKR4D1sw5F.png"
    ),
}

LOGICAL_SIZE = 32
MASTER_SIZE = 1024
PALETTE_COLORS = 12


def process_concept(name: str, source: Path) -> Image.Image:
    destination = OUTPUT_ROOT / name
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination / "raw-output.png")

    with Image.open(source) as generated:
        rgb = ImageOps.fit(generated.convert("RGB"), (MASTER_SIZE, MASTER_SIZE))
        logical = rgb.resize(
            (LOGICAL_SIZE, LOGICAL_SIZE),
            resample=Image.Resampling.BOX,
        )
        logical = logical.quantize(
            colors=PALETTE_COLORS,
            method=Image.Quantize.MEDIANCUT,
            dither=Image.Dither.NONE,
        ).convert("RGB")
        logical.save(destination / "icon-32.png", optimize=True)

        master = logical.resize(
            (MASTER_SIZE, MASTER_SIZE),
            resample=Image.Resampling.NEAREST,
        )
        master.save(destination / "icon-1024.png", optimize=True)
        return master


def main() -> None:
    missing = [str(path) for path in CONCEPTS.values() if not path.is_file()]
    if missing:
        raise SystemExit(f"Missing generated sources: {missing}")

    masters = [process_concept(name, source) for name, source in CONCEPTS.items()]

    thumb_size = 256
    gutter = 20
    sheet = Image.new(
        "RGB",
        (
            thumb_size * len(masters) + gutter * (len(masters) - 1),
            thumb_size,
        ),
        "#15131d",
    )
    for index, master in enumerate(masters):
        thumb = master.resize(
            (thumb_size, thumb_size),
            resample=Image.Resampling.NEAREST,
        )
        sheet.paste(thumb, (index * (thumb_size + gutter), 0))
    sheet.save(OUTPUT_ROOT / "concepts-contact-sheet.png", optimize=True)

    metadata = {
        "pipeline": "built-in-imagegen-plus-deterministic-pixel-postprocess",
        "logical_size": [LOGICAL_SIZE, LOGICAL_SIZE],
        "master_size": [MASTER_SIZE, MASTER_SIZE],
        "palette_colors": PALETTE_COLORS,
        "downsample_filter": "Pillow BOX",
        "upscale_filter": "Pillow NEAREST",
        "alpha": False,
        "concepts": {
            name: {
                "generated_source": str(source),
                "raw_copy": f"{name}/raw-output.png",
                "logical_output": f"{name}/icon-32.png",
                "master_output": f"{name}/icon-1024.png",
                "prompt": f"{name}/prompt-used.txt",
            }
            for name, source in CONCEPTS.items()
        },
    }
    (OUTPUT_ROOT / "pipeline-meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
