#!/usr/bin/env python3
"""Build the v10 quick-draw delivery from ImageGen source batches.

This file only performs deterministic sprite processing: alpha cleanup, source
cell extraction, fixed-root normalization, arm/weapon compositing onto the
accepted v9 master, atlas assembly, and machine-readable QC.  The right-arm
and revolver pixels in the selected poses all originate in the ImageGen batch
PNGs kept beside this script; the v9 frames provide only the approved static
body/root and the exact aim reference for frame 8.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[5]
RUNTIME = PROJECT / "assets/images/western_duel/first_person/player_detail_action_v10"
V9 = PROJECT / "assets/images/western_duel/first_person"

CELL_W, CELL_H = 540, 1080
GRID_ROWS, GRID_COLS = 4, 4
TARGET_BODY_BBOX = (115, 306, 424, 1040)
TARGET_BODY_HEIGHT = TARGET_BODY_BBOX[3] - TARGET_BODY_BBOX[1]
ALPHA_THRESHOLD = 13
# All ImageGen v10 batches use the same 887x1774 source canvas.  The first
# accepted neutral cell's stable core is 608 source pixels high; use one
# shared scale for every pose and only translate each pose to its feet anchor.
SOURCE_CORE_BBOX = (95, 136, 338, 744)
SOURCE_CORE_HEIGHT = SOURCE_CORE_BBOX[3] - SOURCE_CORE_BBOX[1]
SOURCE_TO_OUTPUT_SCALE = TARGET_BODY_HEIGHT / SOURCE_CORE_HEIGHT

BATCHES = {
    "a": ROOT / "raw_generated/batch_a_draw_2x2_generated.png",
    "b": ROOT / "raw_generated/batch_b_near_aim_2x2_generated.png",
    "c": ROOT / "raw_generated/batch_c_recoil_2x2_generated.png",
    "d": ROOT / "raw_generated/batch_d_recovery_2x2_generated.png",
    "e": ROOT / "raw_generated/batch_e_draw_progression_2x2_generated.png",
    "f": ROOT / "raw_generated/batch_f_damped_return_2x2_generated.png",
}


def clean_alpha(image: Image.Image) -> Image.Image:
    """Drop ImageGen's low-alpha chroma fringe while keeping antialiased edges."""

    image = image.convert("RGBA")
    alpha = image.getchannel("A").point(
        lambda value: value if value >= ALPHA_THRESHOLD else 0
    )
    image.putalpha(alpha)
    return image


def split_batch(image: Image.Image) -> list[Image.Image]:
    image = clean_alpha(image)
    width, height = image.size
    frames: list[Image.Image] = []
    for row in range(2):
        for col in range(2):
            x0 = round(col * width / 2)
            x1 = round((col + 1) * width / 2)
            y0 = round(row * height / 2)
            y1 = round((row + 1) * height / 2)
            frames.append(image.crop((x0, y0, x1, y1)))
    return frames


def bbox(image: Image.Image, *, x_limit: float | None = None) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    if x_limit is None:
        return alpha.getbbox()
    mask = Image.new("L", image.size, 0)
    mask.paste(alpha.crop((0, 0, int(image.width * x_limit), image.height)), (0, 0))
    return mask.getbbox()


def normalize_source_frame(image: Image.Image) -> Image.Image:
    """Map a generated 443x887-ish source cell onto the 540x1080 v9 root."""

    image = clean_alpha(image)
    core = bbox(image, x_limit=0.76)
    if core is None:
        raise ValueError("generated frame has no body core")

    # The accepted v9 raw source used the same ImageGen canvas and maps its
    # stable body height to 734 output pixels.  Use one fixed scale for every
    # v10 frame; only the creative arm/weapon silhouette is allowed to change.
    scale = SOURCE_TO_OUTPUT_SCALE
    out_w = max(1, round(image.width * scale))
    out_h = max(1, round(image.height * scale))
    scaled = image.resize((out_w, out_h), Image.Resampling.NEAREST)

    tx = TARGET_BODY_BBOX[0] - round(core[0] * scale)
    ty = TARGET_BODY_BBOX[3] - round(core[3] * scale)
    canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, (tx, ty))
    return canvas


def restore_static_head(result: Image.Image) -> None:
    """Restore only opaque accepted head/hat pixels, never a transparent box."""

    mask = MASTER.getchannel("A").crop((0, 0, 360, 438))
    mask = mask.point(lambda value: 255 if value > 0 else 0)
    result.paste(MASTER.crop((0, 0, 360, 438)), (0, 0), mask)


def translate_image(image: Image.Image, offset_x: int, offset_y: int) -> Image.Image:
    if offset_x == 0 and offset_y == 0:
        return image
    return image.transform(
        image.size,
        Image.Transform.AFFINE,
        (1, 0, -offset_x, 0, 1, -offset_y),
        resample=Image.Resampling.NEAREST,
    )


def composite_arm(
    source: Image.Image,
    *,
    clear_holster: bool,
    source_is_normalized: bool = False,
    offset_x: int = 0,
    offset_y: int = 0,
) -> Image.Image:
    normalized = source.copy() if source_is_normalized else normalize_source_frame(source)
    normalized = translate_image(normalized, offset_x, offset_y)
    broad_mask = Image.new("L", normalized.size, 0)
    ImageDraw.Draw(broad_mask).polygon(
        [
            (250, 430),
            (300, 408),
            (350, 300),
            (470, 255),
            (535, 305),
            (535, 570),
            (470, 690),
            (405, 760),
            (300, 760),
            (258, 700),
            (245, 560),
        ],
        fill=255,
    )
    ImageDraw.Draw(broad_mask).rectangle((0, 0, 334, 437), fill=0)
    # The broad hard mask selects the generated arm/weapon region while the
    # master remains the complete underlay, including transparent pixels in
    # the generated source.
    result = Image.composite(normalized, MASTER, broad_mask)
    restore_static_head(result)
    result.paste(MASTER.crop((0, 438, 245, 760)), (0, 438))
    result.paste(MASTER.crop((0, 600, 300, 760)), (0, 600))
    result.paste(MASTER.crop((0, 760, CELL_W, CELL_H)), (0, 760))
    if clear_holster:
        result.paste(AIM.crop((300, 650, 432, 790)), (300, 650))
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_sheet(frames: list[Image.Image], path: Path) -> None:
    sheet = Image.new("RGBA", (GRID_COLS * CELL_W, GRID_ROWS * CELL_H), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, GRID_COLS)
        sheet.alpha_composite(frame, (col * CELL_W, row * CELL_H))
    sheet.save(path)


def write_gif(frames: list[Image.Image], path: Path, durations: list[int]) -> None:
    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        disposal=2,
    )


def visible_bbox(image: Image.Image) -> list[int] | None:
    found = image.getchannel("A").getbbox()
    return list(found) if found else None


def make_qc(frames: list[Image.Image], source_labels: list[str]) -> dict[str, object]:
    bboxes = [visible_bbox(frame) for frame in frames]
    body_roots = [bbox(frame, x_limit=0.76) for frame in frames]
    return {
        "frame_count": len(frames),
        "cell_size": [CELL_W, CELL_H],
        "grid": [GRID_ROWS, GRID_COLS],
        "source_labels": source_labels,
        "delivery_bboxes": bboxes,
        "body_root_bboxes": [list(item) if item else None for item in body_roots],
        "body_root_head_y": [item[1] if item else None for item in body_roots],
        "body_root_feet_y": [item[3] if item else None for item in body_roots],
        "empty_frames": [index + 1 for index, item in enumerate(bboxes) if item is None],
        "output_edge_touch_frames": [
            index + 1
            for index, item in enumerate(bboxes)
            if item and (item[0] <= 0 or item[1] <= 0 or item[2] >= CELL_W or item[3] >= CELL_H)
        ],
    }


def save_normalized_preview() -> None:
    out = ROOT / "batches/normalized"
    out.mkdir(parents=True, exist_ok=True)
    for name, path in BATCHES.items():
        for index, frame in enumerate(split_batch(Image.open(path)), 1):
            normalize_source_frame(frame).save(out / f"{name}_{index:02d}.png")


MASTER = Image.open(V9 / "player_detail_idle_v9/frame_01.png").convert("RGBA")
AIM = Image.open(V9 / "player_detail_action_v9/frame_04.png").convert("RGBA")


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    (ROOT / "batches/normalized").mkdir(parents=True, exist_ok=True)
    save_normalized_preview()

    cells = {name: split_batch(Image.open(path)) for name, path in BATCHES.items()}

    # Ordered delivery: ready, grip, three rising draw poses, two near-aim
    # transitions, exact accepted aim/fire frame, compact recoil, damped return.
    # The selected source cells are deliberately mixed across inspected
    # ImageGen batches; no generated whole-body frame is used as the root.
    source_plan: list[tuple[str, int, bool, int, int]] = [
        ("v9_idle", 0, False, 0, 0),
        ("a", 1, False, 0, 0),
        ("e", 0, True, -10, 0),
        ("e", 1, True, 0, 0),
        ("a", 2, True, -15, 0),
        ("a", 3, True, -18, -2),
        ("b", 2, True, -25, -3),
        ("v9_aim", 0, True, 0, 0),
        ("c", 1, True, -35, 0),
        ("f", 2, True, -36, -8),
        ("f", 3, True, -37, -8),
        ("d", 1, True, -42, -5),
        ("d", 2, True, -46, -7),
        ("d", 3, True, -39, -7),
        ("b", 3, True, -29, -7),
        ("f", 3, True, -37, -12),
    ]

    frames: list[Image.Image] = []
    labels: list[str] = []
    pose_transforms: list[list[int]] = []
    for source_name, cell_index, clear_holster, offset_x, offset_y in source_plan:
        if source_name == "v9_idle":
            frame = MASTER.copy()
        elif source_name == "v9_aim":
            frame = composite_arm(
                AIM,
                clear_holster=True,
                source_is_normalized=True,
                offset_x=offset_x,
                offset_y=offset_y,
            )
        else:
            # Every generated pose is composited over the accepted v9 master;
            # the hard mask and static restore boxes keep the body root fixed.
            frame = composite_arm(
                cells[source_name][cell_index],
                clear_holster=clear_holster,
                offset_x=offset_x,
                offset_y=offset_y,
            )
        frames.append(frame)
        labels.append(f"{source_name}:{cell_index + 1}")
        pose_transforms.append([offset_x, offset_y])

    for index, frame in enumerate(frames, 1):
        frame.save(RUNTIME / f"frame_{index:02d}.png")
    write_sheet(frames, RUNTIME / "sheet-transparent.png")
    durations = [30] * 7 + [40] * 9
    write_gif(frames, RUNTIME / "animation.gif", durations)

    qc = make_qc(frames, labels)
    qc["pose_transforms_xy"] = pose_transforms
    metadata = {
        "variant": "player_detail_action_v10",
        "source_batches": {name: {"path": str(path), "sha256": sha256(path)} for name, path in BATCHES.items()},
        "source_master": str(V9 / "player_detail_idle_v9/frame_01.png"),
        "source_exact_aim": str(V9 / "player_detail_action_v9/frame_04.png"),
        "source_raw_sheet_size": [887, 1774],
        "source_raw_cell_size_approx": [443.5, 887],
        "runtime_static_body_source_size": [540, 1080],
        "grid": [GRID_ROWS, GRID_COLS],
        "cell_size": [CELL_W, CELL_H],
        "display_size": [CELL_W, CELL_H],
        "display_scale": [1, 1],
        "filter": "nearest",
        "frame_order": [
            "ready",
            "grip_tighten",
            "draw_low",
            "draw_mid",
            "draw_high",
            "near_aim",
            "aim_settle",
            "fire_exact_v9",
            "recoil_1",
            "recoil_2",
            "recoil_3",
            "recoil_4",
            "return_1",
            "return_2",
            "return_3",
            "return_stable",
        ],
        "frame_duration_ms": durations,
        "fire_frame_index": 7,
        "fire_frame_number": 8,
        "body_root": "accepted_v9_master_fixed",
        "composition": "ImageGen arm-and-revolver pixels composited over fixed v9 body; v9 aim reused exactly for frame 8",
        "muzzle_contract": {
            "aim_reference": [410, 365],
            "breech_reference": [381, 404],
            "direction": "compact diagonal lower-left to upper-right toward centered opponent",
            "recoil_max_displacement_px": 10,
        },
        "qc": qc,
    }
    metadata["frame_sha256"] = [
        hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames
    ]
    metadata["unique_frame_count"] = len(set(metadata["frame_sha256"]))
    (RUNTIME / "pipeline-meta.json").write_text(json.dumps(metadata, indent=2) + "\n")


if __name__ == "__main__":
    main()
