#!/usr/bin/env python3
"""Assemble the approved v11 Western Duel player delivery.

The creative pixels come from the preserved v11 ImageGen sheets beside this
file. This script only performs deterministic chroma cleanup, component
filtering, one shared nearest-neighbor scale per source batch, root alignment,
master compositing, atlas assembly, and QC metadata.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[5]
RUNTIME_ROOT = PROJECT / "assets/images/western_duel/first_person"
RUNTIME_IDLE = RUNTIME_ROOT / "player_detail_idle_v11"
RUNTIME_ACTION = RUNTIME_ROOT / "player_detail_action_v11"

CELL_W, CELL_H = 540, 1080
IDLE_ROWS, IDLE_COLS = 2, 2
ACTION_ROWS, ACTION_COLS = 4, 4
ACTION_FRAME_COUNT = 16
TARGET_BODY_BBOX = (115, 306, 424, 1040)
TARGET_BODY_HEIGHT = TARGET_BODY_BBOX[3] - TARGET_BODY_BBOX[1]
ALPHA_THRESHOLD = 16
SOURCE_X_LIMIT = 0.76

MASTER_PATH = ROOT / "master_540x1080/frame_01.png"
BATCHES = {
    "batch_1": ROOT / "batch_1/player_detail_action_v11_batch_1_raw.png",
    "batch_2": ROOT / "batch_2/player_detail_action_v11_batch_2_raw.png",
    "batch_3": ROOT / "batch_3/player_detail_batch_3_raw.png",
    "batch_4": ROOT / "batch_4/player_detail_action_v11_batch_4_raw.png",
}
# Measured after v11 chroma cleanup and largest-component filtering. The
# selected scale is shared by all four poses in each raw batch; only pose
# translation to the fixed body root is allowed afterward.
SOURCE_BODY_HEIGHTS = {
    "batch_1": 604,
    "batch_2": 642,
    "batch_3": 601,
    "batch_4": 604,
}


def _magenta_like(red: int, green: int, blue: int) -> bool:
    """Recognize the flat magenta key without removing warm orange cloth."""

    flat_key = (
        red >= 165
        and blue >= 120
        and green <= 145
        and abs(red - blue) <= 115
    )
    # Some v11 cells contain a fully opaque purple edge from the magenta
    # background. It is chroma spill rather than the approved warm orange
    # cloth: blue is at least as strong as red while green is much lower.
    purple_spill = (
        red >= 55
        and blue >= 45
        and blue >= red * 0.60
        and green < min(red, blue) * 0.75
    )
    return flat_key or purple_spill


def clean_alpha(image: Image.Image) -> Image.Image:
    """Remove key color and low-alpha contour spill from a generated sheet."""

    image = image.convert("RGBA")
    pixels = list(image.getdata())
    cleaned: list[tuple[int, int, int, int]] = []
    for red, green, blue, alpha in pixels:
        if alpha < ALPHA_THRESHOLD or _magenta_like(red, green, blue):
            cleaned.append((0, 0, 0, 0))
        else:
            cleaned.append((red, green, blue, alpha))
    image.putdata(cleaned)
    return image


def _largest_component_mask(alpha: Image.Image) -> Image.Image:
    """Return a binary mask for the largest 8-connected opaque component."""

    width, height = alpha.size
    values = alpha.tobytes()
    seen = bytearray(width * height)
    largest: list[int] = []
    for start, value in enumerate(values):
        if value == 0 or seen[start]:
            continue
        seen[start] = 1
        stack = [start]
        component: list[int] = []
        while stack:
            index = stack.pop()
            component.append(index)
            x = index % width
            y = index // width
            left = max(0, x - 1)
            right = min(width - 1, x + 1)
            top = max(0, y - 1)
            bottom = min(height - 1, y + 1)
            for neighbor_y in range(top, bottom + 1):
                row = neighbor_y * width
                for neighbor_x in range(left, right + 1):
                    neighbor = row + neighbor_x
                    if not seen[neighbor] and values[neighbor] != 0:
                        seen[neighbor] = 1
                        stack.append(neighbor)
        if len(component) > len(largest):
            largest = component

    mask = bytearray(width * height)
    for index in largest:
        mask[index] = 255
    return Image.frombytes("L", (width, height), bytes(mask))


def keep_largest_component(image: Image.Image) -> Image.Image:
    result = image.copy()
    mask = _largest_component_mask(result.getchannel("A"))
    result.putalpha(mask)
    return result


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
            frames.append(keep_largest_component(image.crop((x0, y0, x1, y1))))
    return frames


def bbox(image: Image.Image, *, x_limit: float | None = None) -> tuple[int, int, int, int] | None:
    alpha = image.getchannel("A")
    if x_limit is None:
        return alpha.getbbox()
    return alpha.crop((0, 0, int(image.width * x_limit), image.height)).getbbox()


def normalize_source_frame(image: Image.Image, batch_name: str) -> Image.Image:
    """Scale one batch uniformly, then translate it to the accepted body root."""

    core = bbox(image, x_limit=SOURCE_X_LIMIT)
    if core is None:
        raise ValueError(f"{batch_name} frame has no stable body core")
    observed_height = core[3] - core[1]
    expected_height = SOURCE_BODY_HEIGHTS[batch_name]
    if abs(observed_height - expected_height) > 4:
        raise ValueError(
            f"{batch_name} body height changed: observed={observed_height}, "
            f"expected={expected_height}"
        )
    scale = TARGET_BODY_HEIGHT / expected_height
    scaled = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.NEAREST,
    )
    tx = TARGET_BODY_BBOX[0] - round(core[0] * scale)
    ty = TARGET_BODY_BBOX[3] - round(core[3] * scale)
    canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, (tx, ty))
    return canvas


def translate_image(image: Image.Image, offset_x: int, offset_y: int) -> Image.Image:
    if offset_x == 0 and offset_y == 0:
        return image
    return image.transform(
        image.size,
        Image.Transform.AFFINE,
        (1, 0, -offset_x, 0, 1, -offset_y),
        resample=Image.Resampling.NEAREST,
    )


def restore_static_head(result: Image.Image, master: Image.Image) -> None:
    """Restore opaque master head pixels without restoring transparent boxes."""

    mask = master.getchannel("A").crop((0, 0, 360, 438))
    mask = mask.point(lambda value: 255 if value > 0 else 0)
    result.paste(master.crop((0, 0, 360, 438)), (0, 0), mask)


def composite_arm(
    normalized: Image.Image,
    master: Image.Image,
    *,
    clear_holster: bool,
    aim_holster_patch: Image.Image,
    aim_normalized: Image.Image,
    offset_x: int = 0,
    offset_y: int = 0,
) -> Image.Image:
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
    # The generated head/hat is one connected component in this upper crop,
    # while a small gun highlight can be a separate component. Clear only the
    # former so the static master head wins without cutting weapon pixels.
    guard_box = (0, 0, 374, 389)
    guard_source = normalized.crop(guard_box)
    guard_mask = _largest_component_mask(guard_source.getchannel("A"))
    guard_pixels = guard_mask.load()
    broad_pixels = broad_mask.load()
    for y in range(guard_box[1], guard_box[3]):
        for x in range(guard_box[0], guard_box[2]):
            if guard_pixels[x, y] > 0:
                broad_pixels[x, y] = 0
    # Image.composite uses transparent generated pixels too, so stale master
    # arm pixels cannot survive inside the selected action region.
    result = Image.composite(normalized, master, broad_mask)
    restore_static_head(result, master)
    result.paste(master.crop((0, 438, 245, 760)), (0, 438))
    result.paste(master.crop((0, 600, 300, 760)), (0, 600))
    # Keep the exposed torso connected where the generated arm mask leaves a
    # transparent notch. Only zero-alpha pixels may be filled from the new
    # v11 aim vest; generated arm pixels remain untouched.
    result_pixels = result.load()
    aim_pixels = aim_normalized.load()
    for y in range(552, 614):
        for x in range(245, 327):
            if result_pixels[x, y][3] == 0 and aim_pixels[x, y][3] > 0:
                result_pixels[x, y] = aim_pixels[x, y]
    if clear_holster:
        # This patch is taken from the new v11 exact-aim source frame; it
        # clears the old closed holster while preserving the new empty cavity.
        result.paste(aim_holster_patch, (300, 650))
    # Restore the full lower body last so a transparent holster patch cannot
    # cut away the right trouser silhouette at its lower edge.
    result.paste(master.crop((0, 760, CELL_W, CELL_H)), (0, 760))
    return result


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_sheet(frames: list[Image.Image], path: Path, columns: int, rows: int) -> None:
    sheet = Image.new("RGBA", (columns * CELL_W, rows * CELL_H), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        row, col = divmod(index, columns)
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


def magenta_residual_pixels(image: Image.Image) -> int:
    count = 0
    for red, green, blue, alpha in image.getdata():
        if alpha >= ALPHA_THRESHOLD and _magenta_like(red, green, blue):
            count += 1
    return count


def make_qc(frames: list[Image.Image], labels: list[str]) -> dict[str, object]:
    hashes = [hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames]
    bboxes = [visible_bbox(frame) for frame in frames]
    roots = [bbox(frame, x_limit=SOURCE_X_LIMIT) for frame in frames]
    return {
        "frame_count": len(frames),
        "cell_size": [CELL_W, CELL_H],
        "grid": [ACTION_ROWS, ACTION_COLS],
        "source_labels": labels,
        "delivery_bboxes": bboxes,
        "body_root_bboxes": [list(item) if item else None for item in roots],
        "body_root_head_y": [item[1] if item else None for item in roots],
        "body_root_feet_y": [item[3] if item else None for item in roots],
        "empty_frames": [index + 1 for index, item in enumerate(bboxes) if item is None],
        "output_edge_touch_frames": [
            index + 1
            for index, item in enumerate(bboxes)
            if item and (item[0] <= 0 or item[1] <= 0 or item[2] >= CELL_W or item[3] >= CELL_H)
        ],
        "magenta_residual_pixels": [magenta_residual_pixels(frame) for frame in frames],
        "frame_sha256": hashes,
        "unique_frame_count": len(set(hashes)),
    }


def save_idle(master: Image.Image) -> None:
    RUNTIME_IDLE.mkdir(parents=True, exist_ok=True)
    frames = [master.copy() for _ in range(4)]
    for index, frame in enumerate(frames, 1):
        frame.save(RUNTIME_IDLE / f"frame_{index:02d}.png")
    write_sheet(frames, RUNTIME_IDLE / "sheet-transparent.png", IDLE_COLS, IDLE_ROWS)
    write_gif(frames, RUNTIME_IDLE / "animation.gif", [750] * 4)
    metadata = {
        "variant": "player_detail_idle_v11",
        "source_master": str(MASTER_PATH),
        "source_master_sha256": sha256(MASTER_PATH),
        "cell_size": [CELL_W, CELL_H],
        "grid": [IDLE_ROWS, IDLE_COLS],
        "display_size": [CELL_W, CELL_H],
        "display_scale": [1, 1],
        "filter": "nearest",
        "frame_order": ["master", "master", "master", "master"],
        "frame_duration_ms": [750] * 4,
        "breathing_runtime": {
            "cycle_seconds": 3,
            "amplitude": 0.009,
            "waist_source_y": 650,
        },
        "qc": {
            "exact_master_repeats": True,
            "frame_sha256": [hashlib.sha256(frame.tobytes()).hexdigest() for frame in frames],
        },
    }
    (RUNTIME_IDLE / "pipeline-meta.json").write_text(json.dumps(metadata, indent=2) + "\n")


def main() -> None:
    master = Image.open(MASTER_PATH).convert("RGBA")
    if master.size != (CELL_W, CELL_H):
        raise ValueError(f"master size is {master.size}, expected {(CELL_W, CELL_H)}")
    save_idle(master)

    raw_cells = {
        name: split_batch(Image.open(path)) for name, path in BATCHES.items()
    }
    normalized = {
        name: [normalize_source_frame(frame, name) for frame in frames]
        for name, frames in raw_cells.items()
    }
    source_core_heights = {
        name: [
            (bbox(frame, x_limit=SOURCE_X_LIMIT)[3] - bbox(frame, x_limit=SOURCE_X_LIMIT)[1])
            if bbox(frame, x_limit=SOURCE_X_LIMIT)
            else None
            for frame in frames
        ]
        for name, frames in raw_cells.items()
    }

    # Batch 2 cell 4 is pose 8, the exact firing aim source. Reuse only its
    # new v11 holster patch for subsequent draw/recoil poses.
    aim_normalized = normalized["batch_2"][3]
    aim_holster_patch = aim_normalized.crop((300, 650, 432, 790))
    source_plan: list[tuple[str, int, bool, int, int]] = [
        ("master", 0, False, 0, 0),
        ("batch_1", 1, False, 0, 1),
        ("batch_1", 2, True, -4, 5),
        ("batch_1", 3, True, -4, 8),
        ("batch_2", 0, True, -20, -2),
        ("batch_2", 1, True, -20, -4),
        ("batch_2", 2, True, -18, -3),
        ("batch_2", 3, True, -23, -5),
        ("batch_3", 0, True, -10, -2),
        ("batch_3", 1, True, -9, 3),
        ("batch_3", 2, True, -10, 4),
        ("batch_3", 3, True, -6, 3),
        ("batch_4", 0, True, 0, -1),
        ("batch_4", 1, True, -2, -1),
        ("batch_4", 2, True, -2, 0),
        ("batch_4", 3, True, 0, -2),
    ]

    frames: list[Image.Image] = []
    labels: list[str] = []
    for source_name, cell_index, clear_holster, offset_x, offset_y in source_plan:
        if source_name == "master":
            frame = master.copy()
        else:
            frame = composite_arm(
                normalized[source_name][cell_index],
                master,
                clear_holster=clear_holster,
                aim_holster_patch=aim_holster_patch,
                aim_normalized=aim_normalized,
                offset_x=offset_x,
                offset_y=offset_y,
            )
        frames.append(frame)
        labels.append("master" if source_name == "master" else f"{source_name}:{cell_index + 1}")

    RUNTIME_ACTION.mkdir(parents=True, exist_ok=True)
    for index, frame in enumerate(frames, 1):
        frame.save(RUNTIME_ACTION / f"frame_{index:02d}.png")
    write_sheet(frames, RUNTIME_ACTION / "sheet-transparent.png", ACTION_COLS, ACTION_ROWS)
    durations = [30] * 7 + [40] * 9
    write_gif(frames, RUNTIME_ACTION / "animation.gif", durations)

    qc = make_qc(frames, labels)
    metadata = {
        "variant": "player_detail_action_v11",
        "source_batches": {
            name: {"path": str(path), "sha256": sha256(path)}
            for name, path in BATCHES.items()
        },
        "source_master": str(MASTER_PATH),
        "source_master_sha256": sha256(MASTER_PATH),
        "source_raw_sheet_size": [887, 1774],
        "source_raw_cell_size_approx": [443.5, 887],
        "source_core_heights": SOURCE_BODY_HEIGHTS,
        "observed_source_core_heights": source_core_heights,
        "runtime_static_body_source_size": [CELL_W, CELL_H],
        "grid": [ACTION_ROWS, ACTION_COLS],
        "cell_size": [CELL_W, CELL_H],
        "display_size": [CELL_W, CELL_H],
        "display_scale": [1, 1],
        "filter": "nearest",
        "frame_order": [
            "ready",
            "grip_tighten",
            "draw_low",
            "draw_mid",
            "near_aim_1",
            "near_aim_2",
            "near_aim_3",
            "fire_exact",
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
        "body_root": {
            "bbox": list(TARGET_BODY_BBOX),
            "alignment": "per-pose translation after one shared scale per source batch",
        },
        "composition": (
            "v11 ImageGen arm-and-revolver pixels composited over the fixed v11 "
            "master; transparent pixels clear the selected arm region; opaque "
            "head and static master boxes are restored; v11 frame 8 supplies "
            "the empty-holster patch"
        ),
        "muzzle_contract": {
            "aim_reference": [410, 365],
            "breech_reference": [381, 404],
            "direction": "compact diagonal lower-left to upper-right toward centered opponent",
            "recoil_max_displacement_px": 10,
        },
        "qc": qc,
    }
    (RUNTIME_ACTION / "pipeline-meta.json").write_text(
        json.dumps(metadata, indent=2) + "\n"
    )
    print(json.dumps({"idle": str(RUNTIME_IDLE), "action": str(RUNTIME_ACTION), "qc": qc}, indent=2))


if __name__ == "__main__":
    main()
