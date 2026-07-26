from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/source/imagegen/number_rush_arcade_v2"
RUNTIME = ROOT / "assets/images/number_rush"


def _normalize_sheet(
    source_path: Path,
    output_path: Path,
    *,
    columns: int,
    rows: int,
    output_cell: int,
    padding: int,
) -> list[dict[str, object]]:
    source = Image.open(source_path).convert("RGBA")
    source_cell_width = source.width // columns
    source_cell_height = source.height // rows
    atlas = Image.new(
        "RGBA",
        (columns * output_cell, rows * output_cell),
        (0, 0, 0, 0),
    )
    frames: list[dict[str, object]] = []

    for row in range(rows):
        for column in range(columns):
            frame_index = row * columns + column
            cell_box = (
                column * source_cell_width,
                row * source_cell_height,
                (column + 1) * source_cell_width,
                (row + 1) * source_cell_height,
            )
            cell = source.crop(cell_box)
            alpha_box = cell.getchannel("A").getbbox()
            if alpha_box is None:
                raise ValueError(f"Frame {frame_index} is empty")
            subject = cell.crop(alpha_box)
            available = output_cell - padding * 2
            scale = min(available / subject.width, available / subject.height)
            target_size = (
                max(1, round(subject.width * scale)),
                max(1, round(subject.height * scale)),
            )
            subject = subject.resize(target_size, Image.Resampling.NEAREST)
            x = column * output_cell + (output_cell - subject.width) // 2
            y = row * output_cell + (output_cell - subject.height) // 2
            atlas.alpha_composite(subject, (x, y))
            frames.append(
                {
                    "index": frame_index,
                    "source_cell": list(cell_box),
                    "source_subject_bounds": list(alpha_box),
                    "runtime_rect": [
                        column * output_cell,
                        row * output_cell,
                        output_cell,
                        output_cell,
                    ],
                }
            )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output_path)
    return frames


def main() -> None:
    cabinet = Image.open(SOURCE / "cabinet/cabinet-alpha.png").convert("RGBA")
    cabinet = cabinet.resize((360, 640), Image.Resampling.NEAREST)
    cabinet.save(RUNTIME / "arcade_cabinet_body.png")

    button_frames = _normalize_sheet(
        SOURCE / "buttons/sheet-alpha.png",
        RUNTIME / "number_button_states.png",
        columns=3,
        rows=2,
        output_cell=56,
        padding=1,
    )
    fx_frames = _normalize_sheet(
        SOURCE / "fx/sheet-alpha.png",
        RUNTIME / "arcade_fx_sheet.png",
        columns=4,
        rows=2,
        output_cell=64,
        padding=2,
    )
    metadata = {
        "cabinet_body": {
            "path": "assets/images/number_rush/arcade_cabinet_body.png",
            "source": "cabinet/cabinet-alpha.png",
            "source_size": [941, 1672],
            "runtime_size": [360, 640],
            "role": "non-interactive body layer behind the fixed gameplay UI",
        },
        "button_sheet": {
            "path": "assets/images/number_rush/number_button_states.png",
            "layout": "2 rows x 3 columns",
            "cell": [56, 56],
            "order": [
                "idle",
                "correct_pressed",
                "cleared",
                "wrong",
                "target_25",
                "completion",
            ],
            "frames": button_frames,
        },
        "fx_sheet": {
            "path": "assets/images/number_rush/arcade_fx_sheet.png",
            "layout": "2 rows x 4 columns",
            "cell": [64, 64],
            "order": [
                "spark",
                "compact_burst",
                "thin_ring",
                "large_ring",
                "wrong_crackle",
                "amber_star",
                "completion_burst",
                "fading_particles",
            ],
            "frames": fx_frames,
        },
        "rendering": {
            "filter": "nearest-neighbor",
            "logical_art_pixel": "approximately 2x2",
            "button_display_size": [56, 56],
            "fx_default_display_size": [64, 64],
        },
    }
    (SOURCE / "pipeline-meta.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
