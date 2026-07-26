#!/usr/bin/env python3

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIR = ROOT / "assets/images/apple_game_v2"
SOURCE_DIR = ROOT / "assets/source/guide_composite/apple_game_v2/guide_drag_sprite"
CAPTURE_DIR = ROOT / "assets/source/runtime_capture/apple_game_v2"

APPLE_ATLAS = RUNTIME_DIR / "apple_faces_atlas.png"
POP_ATLAS = RUNTIME_DIR / "apple_pop_sheet.png"
COMBO_ATLAS = RUNTIME_DIR / "apple_combo_burst_sheet.png"
FONT = ROOT / "assets/fonts/Galmuri11-Bold.ttf"
FULL_CAPTURE = CAPTURE_DIR / "home_gameplay_full.png"

GUIDE_RUNTIME = RUNTIME_DIR / "guide_drag_sprite.png"
GUIDE_SOURCE = SOURCE_DIR / "guide_drag_sprite.png"
GUIDE_QC = SOURCE_DIR / "qc/guide_drag_sprite_4x.png"
GUIDE_SHEET_RUNTIME = RUNTIME_DIR / "guide_drag_sprite_sheet.png"
GUIDE_SHEET_SOURCE = SOURCE_DIR / "guide_drag_sprite_sheet.png"
GUIDE_SHEET_QC = SOURCE_DIR / "qc/guide_drag_sprite_sheet_2x.png"
GUIDE_FRAMES_DIR = SOURCE_DIR / "frames"
GUIDE_META = SOURCE_DIR / "pipeline-meta.json"
TARGET_SHEET_RUNTIME = RUNTIME_DIR / "guide_target_pop_sprite_sheet.png"
TARGET_SHEET_SOURCE = SOURCE_DIR / "guide_target_pop_sprite_sheet.png"
TARGET_SHEET_QC = SOURCE_DIR / "qc/guide_target_pop_sprite_sheet_2x.png"
TARGET_FRAMES_DIR = SOURCE_DIR / "target_pop_frames"
SPARSE_SHEET_RUNTIME = RUNTIME_DIR / "guide_sparse_pop_sprite_sheet.png"
SPARSE_SHEET_SOURCE = SOURCE_DIR / "guide_sparse_pop_sprite_sheet.png"
SPARSE_SHEET_QC = SOURCE_DIR / "qc/guide_sparse_pop_sprite_sheet_2x.png"
SPARSE_FRAMES_DIR = SOURCE_DIR / "sparse_pop_frames"

HOME_RUNTIME = RUNTIME_DIR / "home_gameplay_hero.png"
HOME_META = CAPTURE_DIR / "pipeline-meta.json"

SCENE_SIZE = (246, 176)
FRAME_COUNT = 8
FRAME_DURATION_MS = 175
OUTCOME_FRAME_COUNT = 12
OUTCOME_FRAME_DURATION_MS = 125
CELL_SIZE = 42
BOARD_PADDING = 8
BOARD_VALUES = (
    (7, 4, 6, 8, 2),
    (3, 1, 9, 5, 4),
    (6, 2, 8, 1, 7),
)
SPARSE_BOARD_VALUES = (
    (7, 2, 3, 8, 2),
    (3, None, 5, 5, 4),
    (6, 2, 8, 1, 7),
)


def _paste_rgba(canvas: Image.Image, image: Image.Image, xy: tuple[int, int]) -> None:
    canvas.alpha_composite(image, dest=xy)


def _draw_number(
    canvas: Image.Image,
    draw: ImageDraw.ImageDraw,
    value: int,
    cell_left: int,
    cell_top: int,
) -> None:
    font = ImageFont.truetype(str(FONT), 16)
    label = str(value)
    box = draw.textbbox((0, 0), label, font=font, stroke_width=0)
    width = box[2] - box[0]
    height = box[3] - box[1]
    x = round(cell_left + (CELL_SIZE - width) / 2)
    y = round(cell_top + (CELL_SIZE - height) / 2 + 3 - box[1])
    shadow = (89, 31, 44, 255)
    for offset in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        draw.text((x + offset[0], y + offset[1]), label, font=font, fill=shadow)
    draw.text((x, y), label, font=font, fill=(255, 243, 196, 255))


def _build_guide_board(
    atlas: Image.Image,
    values: tuple[tuple[int | None, ...], ...] = BOARD_VALUES,
) -> tuple[Image.Image, int, int]:
    canvas = Image.new("RGBA", SCENE_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas, "RGBA")
    board_width = len(values[0]) * CELL_SIZE + BOARD_PADDING * 2
    board_height = len(values) * CELL_SIZE + BOARD_PADDING * 2
    board_left = (SCENE_SIZE[0] - board_width) // 2
    board_top = (SCENE_SIZE[1] - board_height) // 2
    content_left = board_left + BOARD_PADDING
    content_top = board_top + BOARD_PADDING

    draw.rectangle(
        (
            board_left,
            board_top,
            board_left + board_width - 1,
            board_top + board_height - 1,
        ),
        fill=(1, 27, 25, 185),
    )

    for row, row_values in enumerate(values):
        for column, value in enumerate(row_values):
            if value is None:
                continue
            source_column = (value - 1) % 3
            source_row = (value - 1) // 3
            apple = atlas.crop(
                (
                    source_column * CELL_SIZE,
                    source_row * CELL_SIZE,
                    (source_column + 1) * CELL_SIZE,
                    (source_row + 1) * CELL_SIZE,
                )
            )
            x = content_left + column * CELL_SIZE
            y = content_top + row * CELL_SIZE
            _paste_rgba(canvas, apple, (x, y))
            _draw_number(canvas, draw, value, x, y)
    return canvas, content_left, content_top


def _draw_selection(
    canvas: Image.Image,
    content_left: int,
    content_top: int,
    *,
    row: int,
    column: int,
    width: int,
    height: int,
) -> None:
    left = content_left + column * CELL_SIZE
    top = content_top + row * CELL_SIZE
    right = left + width * CELL_SIZE - 1
    bottom = top + height * CELL_SIZE - 1
    overlay = Image.new("RGBA", SCENE_SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    draw.rectangle(
        (left, top, right, bottom),
        fill=(255, 243, 196, 72),
        outline=(255, 210, 74, 255),
        width=3,
    )
    canvas.alpha_composite(overlay)


def _draw_sum_badge(
    canvas: Image.Image,
    content_left: int,
    content_top: int,
    *,
    column: int,
    width: int,
) -> None:
    draw = ImageDraw.Draw(canvas, "RGBA")
    font = ImageFont.truetype(str(FONT), 12)
    label = "10 / 10"
    text_box = draw.textbbox((0, 0), label, font=font)
    text_width = text_box[2] - text_box[0]
    text_height = text_box[3] - text_box[1]
    center_x = content_left + (column + width / 2) * CELL_SIZE
    badge_width = text_width + 12
    badge_height = 19
    badge_left = round(center_x - badge_width / 2)
    badge_top = max(0, content_top - BOARD_PADDING - badge_height)
    draw.rectangle(
        (
            badge_left,
            badge_top,
            badge_left + badge_width,
            badge_top + badge_height,
        ),
        fill=(3, 17, 39, 238),
        outline=(255, 210, 74, 255),
        width=2,
    )
    text_x = badge_left + (badge_width - text_width) // 2
    text_y = badge_top + (badge_height - text_height) // 2 - text_box[1]
    draw.text((text_x, text_y), label, font=font, fill=(255, 243, 196, 255))


def _remove_cells(
    values: tuple[tuple[int | None, ...], ...],
    cells: list[tuple[int, int]],
) -> tuple[tuple[int | None, ...], ...]:
    result = [list(row) for row in values]
    for row, column in cells:
        result[row][column] = None
    return tuple(tuple(row) for row in result)


def _paste_effect_centered(
    canvas: Image.Image,
    effect: Image.Image,
    content_left: int,
    content_top: int,
    cell: tuple[int, int],
) -> None:
    row, column = cell
    center_x = content_left + column * CELL_SIZE + CELL_SIZE // 2
    center_y = content_top + row * CELL_SIZE + CELL_SIZE // 2
    _paste_rgba(
        canvas,
        effect,
        (center_x - effect.width // 2, center_y - effect.height // 2),
    )


def _build_pop_frames(
    apple_atlas: Image.Image,
    pop_atlas: Image.Image,
    combo_atlas: Image.Image,
    *,
    values: tuple[tuple[int | None, ...], ...],
    selected_cells: list[tuple[int, int]],
    selection_row: int,
    selection_column: int,
    selection_width: int,
    selection_height: int,
    combo_tier: int,
) -> list[Image.Image]:
    frames: list[Image.Image] = []
    removal_start = 3
    for frame_index in range(OUTCOME_FRAME_COUNT):
        removed_cells = [
            cell
            for cell_index, cell in enumerate(selected_cells)
            if frame_index >= removal_start + cell_index
        ]
        frame_values = _remove_cells(values, removed_cells)
        frame, content_left, content_top = _build_guide_board(
            apple_atlas,
            frame_values,
        )

        if frame_index < removal_start:
            _draw_selection(
                frame,
                content_left,
                content_top,
                row=selection_row,
                column=selection_column,
                width=selection_width,
                height=selection_height,
            )
            _draw_sum_badge(
                frame,
                content_left,
                content_top,
                column=selection_column,
                width=selection_width,
            )

        for cell_index, cell in enumerate(selected_cells):
            pop_frame = frame_index - (removal_start + cell_index)
            if 0 <= pop_frame < 4:
                pop = pop_atlas.crop(
                    (
                        pop_frame * 40,
                        0,
                        (pop_frame + 1) * 40,
                        40,
                    )
                )
                _paste_effect_centered(
                    frame,
                    pop,
                    content_left,
                    content_top,
                    cell,
                )

        final_start = removal_start + len(selected_cells) - 1
        combo_frame = frame_index - final_start
        if 0 <= combo_frame < 4:
            combo = combo_atlas.crop(
                (
                    combo_frame * 32,
                    combo_tier * 32,
                    (combo_frame + 1) * 32,
                    (combo_tier + 1) * 32,
                )
            )
            combo_size = 64 if combo_tier == 0 else 96
            combo = combo.resize(
                (combo_size, combo_size),
                Image.Resampling.NEAREST,
            )
            _paste_effect_centered(
                frame,
                combo,
                content_left,
                content_top,
                selected_cells[-1],
            )
        frames.append(frame)
    return frames


def _save_animation_sheet(
    frames: list[Image.Image],
    *,
    runtime_path: Path,
    source_path: Path,
    qc_path: Path,
    frames_dir: Path,
    frame_prefix: str,
) -> Image.Image:
    frames_dir.mkdir(parents=True, exist_ok=True)
    qc_path.parent.mkdir(parents=True, exist_ok=True)
    sheet = Image.new(
        "RGBA",
        (SCENE_SIZE[0] * len(frames), SCENE_SIZE[1]),
        (0, 0, 0, 0),
    )
    for frame_index, frame in enumerate(frames):
        frame.save(
            frames_dir / f"{frame_prefix}_{frame_index:02d}.png",
            optimize=True,
        )
        sheet.alpha_composite(frame, dest=(frame_index * SCENE_SIZE[0], 0))
    sheet.save(runtime_path, optimize=True)
    sheet.save(source_path, optimize=True)
    sheet.resize(
        (sheet.width * 2, sheet.height * 2),
        Image.Resampling.NEAREST,
    ).save(qc_path, optimize=True)
    return sheet


def _draw_drag_overlay(
    canvas: Image.Image,
    content_left: int,
    content_top: int,
    frame_index: int,
) -> None:
    if frame_index == 0:
        return

    selected_columns = 1 if frame_index <= 3 else 2
    selection_left = content_left + CELL_SIZE
    selection_top = content_top
    selection_right = selection_left + CELL_SIZE * selected_columns - 1
    selection_bottom = selection_top + CELL_SIZE - 1
    overlay = Image.new("RGBA", SCENE_SIZE, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay, "RGBA")
    overlay_draw.rectangle(
        (selection_left, selection_top, selection_right, selection_bottom),
        fill=(255, 243, 196, 72),
        outline=(255, 210, 74, 255),
        width=3,
    )
    canvas.alpha_composite(overlay)

    draw = ImageDraw.Draw(canvas, "RGBA")
    arrow_y = content_top - BOARD_PADDING - 7
    arrow_start = selection_left + CELL_SIZE // 2
    drag_progress = {
        1: 0.0,
        2: 0.34,
        3: 0.68,
        4: 1.0,
        5: 1.0,
    }.get(frame_index)
    if drag_progress is not None:
        arrow_end = round(arrow_start + CELL_SIZE * drag_progress)
        if arrow_end > arrow_start:
            draw.line(
                (arrow_start, arrow_y, arrow_end, arrow_y),
                fill=(255, 210, 74, 255),
                width=3,
            )
            draw.polygon(
                (
                    (arrow_end, arrow_y),
                    (arrow_end - 6, arrow_y - 4),
                    (arrow_end - 6, arrow_y + 4),
                ),
                fill=(255, 210, 74, 255),
            )
        marker_size = 9 if frame_index != 5 else 11
        marker_half = marker_size // 2
        draw.rectangle(
            (
                arrow_end - marker_half,
                arrow_y - marker_half,
                arrow_end + marker_half,
                arrow_y + marker_half,
            ),
            fill=(255, 243, 196, 255),
            outline=(89, 31, 44, 255),
            width=2,
        )


def build_guide_sprite() -> None:
    atlas = Image.open(APPLE_ATLAS).convert("RGBA")
    if atlas.size != (126, 126):
        raise ValueError(f"Unexpected apple atlas size: {atlas.size}")

    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    GUIDE_QC.parent.mkdir(parents=True, exist_ok=True)
    GUIDE_FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)

    frames: list[Image.Image] = []
    for frame_index in range(FRAME_COUNT):
        frame, content_left, content_top = _build_guide_board(atlas)
        _draw_drag_overlay(frame, content_left, content_top, frame_index)
        frame.save(
            GUIDE_FRAMES_DIR / f"guide_drag_frame_{frame_index:02d}.png",
            optimize=True,
        )
        frames.append(frame)

    final_frame = frames[-1]
    final_frame.save(GUIDE_RUNTIME, optimize=True)
    final_frame.save(GUIDE_SOURCE, optimize=True)
    final_frame.resize(
        (SCENE_SIZE[0] * 4, SCENE_SIZE[1] * 4),
        Image.Resampling.NEAREST,
    ).save(GUIDE_QC, optimize=True)

    sheet = Image.new(
        "RGBA",
        (SCENE_SIZE[0] * FRAME_COUNT, SCENE_SIZE[1]),
        (0, 0, 0, 0),
    )
    for frame_index, frame in enumerate(frames):
        sheet.alpha_composite(frame, dest=(frame_index * SCENE_SIZE[0], 0))
    sheet.save(GUIDE_SHEET_RUNTIME, optimize=True)
    sheet.save(GUIDE_SHEET_SOURCE, optimize=True)
    sheet.resize(
        (sheet.width * 2, sheet.height * 2),
        Image.Resampling.NEAREST,
    ).save(GUIDE_SHEET_QC, optimize=True)

    GUIDE_META.write_text(
        json.dumps(
            {
                "asset": "apple_game_v2 animated guide drag sprite",
                "method": "deterministic composition from active runtime apple atlas",
                "master_references": [
                    str(APPLE_ATLAS.relative_to(ROOT)),
                    str(POP_ATLAS.relative_to(ROOT)),
                    str(COMBO_ATLAS.relative_to(ROOT)),
                ],
                "runtime_output": str(GUIDE_SHEET_RUNTIME.relative_to(ROOT)),
                "source_output": str(GUIDE_SHEET_SOURCE.relative_to(ROOT)),
                "static_reference": str(GUIDE_RUNTIME.relative_to(ROOT)),
                "frame_dimensions": list(SCENE_SIZE),
                "sheet_dimensions": list(sheet.size),
                "frame_count": FRAME_COUNT,
                "frame_duration_ms": FRAME_DURATION_MS,
                "loop_duration_ms": FRAME_COUNT * FRAME_DURATION_MS,
                "sheet_layout": "8 columns x 1 row; left-to-right",
                "frame_order": [
                    "idle",
                    "press first apple",
                    "drag one-third",
                    "drag two-thirds",
                    "reach second apple",
                    "hold with touch pulse",
                    "hold selected pair",
                    "hold selected pair",
                ],
                "apple_source_cell": [CELL_SIZE, CELL_SIZE],
                "apple_display_size": [CELL_SIZE, CELL_SIZE],
                "board": {
                    "rows": len(BOARD_VALUES),
                    "columns": len(BOARD_VALUES[0]),
                    "padding": BOARD_PADDING,
                    "values": BOARD_VALUES,
                },
                "selection": {
                    "start": [0, 1],
                    "end": [0, 2],
                    "size": [CELL_SIZE * 2, CELL_SIZE],
                },
                "filtering": "nearest-neighbor",
                "generated_art": False,
                "related_animations": {
                    "target_pop": str(TARGET_SHEET_RUNTIME.relative_to(ROOT)),
                    "sparse_pop": str(SPARSE_SHEET_RUNTIME.relative_to(ROOT)),
                },
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def build_pop_guide_sprites() -> None:
    apple_atlas = Image.open(APPLE_ATLAS).convert("RGBA")
    pop_atlas = Image.open(POP_ATLAS).convert("RGBA")
    combo_atlas = Image.open(COMBO_ATLAS).convert("RGBA")
    if apple_atlas.size != (126, 126):
        raise ValueError(f"Unexpected apple atlas size: {apple_atlas.size}")
    if pop_atlas.size != (160, 40):
        raise ValueError(f"Unexpected pop atlas size: {pop_atlas.size}")
    if combo_atlas.size != (128, 96):
        raise ValueError(f"Unexpected combo atlas size: {combo_atlas.size}")

    target_frames = _build_pop_frames(
        apple_atlas,
        pop_atlas,
        combo_atlas,
        values=BOARD_VALUES,
        selected_cells=[(0, 1), (0, 2)],
        selection_row=0,
        selection_column=1,
        selection_width=2,
        selection_height=1,
        combo_tier=0,
    )
    target_sheet = _save_animation_sheet(
        target_frames,
        runtime_path=TARGET_SHEET_RUNTIME,
        source_path=TARGET_SHEET_SOURCE,
        qc_path=TARGET_SHEET_QC,
        frames_dir=TARGET_FRAMES_DIR,
        frame_prefix="guide_target_pop_frame",
    )

    sparse_frames = _build_pop_frames(
        apple_atlas,
        pop_atlas,
        combo_atlas,
        values=SPARSE_BOARD_VALUES,
        selected_cells=[(0, 1), (0, 2), (1, 2)],
        selection_row=0,
        selection_column=1,
        selection_width=2,
        selection_height=2,
        combo_tier=1,
    )
    sparse_sheet = _save_animation_sheet(
        sparse_frames,
        runtime_path=SPARSE_SHEET_RUNTIME,
        source_path=SPARSE_SHEET_SOURCE,
        qc_path=SPARSE_SHEET_QC,
        frames_dir=SPARSE_FRAMES_DIR,
        frame_prefix="guide_sparse_pop_frame",
    )

    if target_sheet.size != (2952, 176):
        raise ValueError(f"Unexpected target sheet size: {target_sheet.size}")
    if sparse_sheet.size != (2952, 176):
        raise ValueError(f"Unexpected sparse sheet size: {sparse_sheet.size}")


def build_home_preview() -> None:
    capture = Image.open(FULL_CAPTURE).convert("RGB")
    if capture.size != (1206, 2622):
        raise ValueError(f"Unexpected simulator capture size: {capture.size}")

    # Keep the portrait hero ratio while ending between complete apple rows.
    crop = (0, 439, 1206, 1985)
    hero = capture.crop(crop)
    if hero.size != (1206, 1546):
        raise ValueError(f"Unexpected hero size: {hero.size}")
    hero.save(HOME_RUNTIME, optimize=True)
    HOME_META.write_text(
        json.dumps(
            {
                "captured_at": "2026-07-26",
                "source": "iPhone 17 iOS Simulator runtime capture",
                "source_file": str(FULL_CAPTURE.relative_to(CAPTURE_DIR)),
                "runtime_output": str(HOME_RUNTIME.relative_to(ROOT)),
                "source_dimensions": list(capture.size),
                "crop": {
                    "x": crop[0],
                    "y": crop[1],
                    "width": crop[2] - crop[0],
                    "height": crop[3] - crop[1],
                },
                "processing": (
                    "lossless PNG crop aligned between complete apple rows; "
                    "no generative edits"
                ),
                "capture_note": (
                    "Live Apple Game 2 board after the built-in timed apple "
                    "drops; no capture-only gameplay changes."
                ),
                "art_contract": {
                    "home_aspect_ratio": 0.78,
                    "apple_source_cell": [CELL_SIZE, CELL_SIZE],
                    "apple_display_size": [CELL_SIZE, CELL_SIZE],
                    "filter_quality": "nearest-neighbor / none",
                },
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> None:
    build_guide_sprite()
    build_pop_guide_sprites()
    build_home_preview()


if __name__ == "__main__":
    main()
