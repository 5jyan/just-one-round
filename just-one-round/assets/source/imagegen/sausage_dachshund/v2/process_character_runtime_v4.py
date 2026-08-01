"""Build 32px, seam-safe runtime atlases from the approved V3 dachshund."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
RUNTIME = ROOT / "assets/images/sausage_dachshund"
QC = Path(__file__).resolve().parent / "qc"

SOURCE_FRAME = 96
RUNTIME_FRAME = 32

SHEETS = {
    "dog_head_walk_atlas_v3.png": ("dog_head_walk_atlas_v4.png", 4, 4),
    "dog_head_eat_atlas_v3.png": ("dog_head_eat_atlas_v4.png", 4, 4),
    "dog_body_atlas_v3.png": ("dog_body_atlas_v4.png", 3, 2),
    "dog_tail_walk_atlas_v3.png": ("dog_tail_walk_atlas_v4.png", 4, 4),
}

BODY_EDGES = (
    ("left", "right"),
    ("up", "down"),
    ("left", "down"),
    ("up", "right"),
    ("right", "down"),
    ("left", "up"),
)

DIRECTION_BACK_EDGE = ("up", "right", "left", "down")


def _resize_frame(frame: Image.Image) -> Image.Image:
    """Downsample one frame independently so neighboring atlas cells never bleed."""
    rgba = frame.convert("RGBA")
    cleaned = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    cleaned.alpha_composite(rgba)
    return cleaned.resize(
        (RUNTIME_FRAME, RUNTIME_FRAME),
        Image.Resampling.LANCZOS,
        reducing_gap=3.0,
    )


def _paste_connector(
    frame: Image.Image,
    *,
    edge: str,
    horizontal_profile: Image.Image,
    vertical_profile: Image.Image,
) -> None:
    """Copy a shared two-pixel coat cross-section through an open module edge."""
    band = 2
    if edge in {"left", "right"}:
        sample = horizontal_profile.crop(
            (
                RUNTIME_FRAME // 2,
                0,
                RUNTIME_FRAME // 2 + band,
                RUNTIME_FRAME,
            )
        )
        x = 0 if edge == "left" else RUNTIME_FRAME - band
        frame.paste(sample, (x, 0))
        return

    sample = vertical_profile.crop(
        (
            0,
            RUNTIME_FRAME // 2,
            RUNTIME_FRAME,
            RUNTIME_FRAME // 2 + band,
        )
    )
    y = 0 if edge == "up" else RUNTIME_FRAME - band
    frame.paste(sample, (0, y))


def _frames(source: Image.Image, rows: int, columns: int) -> list[Image.Image]:
    return [
        _resize_frame(
            source.crop(
                (
                    column * SOURCE_FRAME,
                    row * SOURCE_FRAME,
                    (column + 1) * SOURCE_FRAME,
                    (row + 1) * SOURCE_FRAME,
                )
            )
        )
        for row in range(rows)
        for column in range(columns)
    ]


def _assemble(frames: list[Image.Image], rows: int, columns: int) -> Image.Image:
    output = Image.new(
        "RGBA",
        (columns * RUNTIME_FRAME, rows * RUNTIME_FRAME),
        (0, 0, 0, 0),
    )
    for index, frame in enumerate(frames):
        output.alpha_composite(
            frame,
            (
                (index % columns) * RUNTIME_FRAME,
                (index // columns) * RUNTIME_FRAME,
            ),
        )
    return output


def main() -> None:
    body_source = Image.open(RUNTIME / "dog_body_atlas_v3.png").convert("RGBA")
    body_frames = _frames(body_source, 3, 2)
    horizontal_profile = body_frames[0].copy()
    vertical_profile = body_frames[1].copy()

    results: list[dict[str, object]] = []
    previews: dict[str, Image.Image] = {}

    for source_name, (output_name, rows, columns) in SHEETS.items():
        source = Image.open(RUNTIME / source_name).convert("RGBA")
        frames = _frames(source, rows, columns)

        if source_name == "dog_body_atlas_v3.png":
            if len(frames) != len(BODY_EDGES):
                raise ValueError("body atlas must contain exactly six modules")
            for frame, edges in zip(frames, BODY_EDGES):
                for edge in edges:
                    _paste_connector(
                        frame,
                        edge=edge,
                        horizontal_profile=horizontal_profile,
                        vertical_profile=vertical_profile,
                    )
        else:
            for index, frame in enumerate(frames):
                _paste_connector(
                    frame,
                    edge=DIRECTION_BACK_EDGE[index // 4],
                    horizontal_profile=horizontal_profile,
                    vertical_profile=vertical_profile,
                )

        atlas = _assemble(frames, rows, columns)
        output = RUNTIME / output_name
        atlas.save(output, optimize=True)
        previews[output_name] = atlas
        results.append(
            {
                "source": str((RUNTIME / source_name).relative_to(ROOT)),
                "output": str(output.relative_to(ROOT)),
                "source_frame_size": [SOURCE_FRAME, SOURCE_FRAME],
                "runtime_frame_size": [RUNTIME_FRAME, RUNTIME_FRAME],
                "atlas_size": list(atlas.size),
                "rows": rows,
                "columns": columns,
            }
        )

    QC.mkdir(parents=True, exist_ok=True)
    (QC / "character-runtime-v4.json").write_text(
        json.dumps(
            {
                "identity": "approved V3 dachshund",
                "display_cell_size": [32, 32],
                "runtime_filter": "nearest-neighbor",
                "frame_resampling": "per-cell Lanczos 96-to-32",
                "connector_profile": "shared two-pixel cross-section at every open edge",
                "frame_order": ["down", "left", "right", "up"],
                "walk_frames_per_direction": 4,
                "eat_frames_per_direction": 4,
                "body_module_order": [
                    "left-right",
                    "up-down",
                    "left-down",
                    "up-right",
                    "right-down",
                    "left-up",
                ],
                "sheets": results,
            },
            indent=2,
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
