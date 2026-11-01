"""Deterministic post-processing for the generated temple_run asset family.

The creative pixels in this folder come from ImageGen.  This script only performs
chroma-key cleanup, fixed-cell extraction, alpha cleanup, integer-contract
resizing, path seam conditioning, and QC metadata/preview generation.
"""

from __future__ import annotations

import json
import math
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
PROCESSED = ROOT / "processed"
QC = ROOT / "qc"
# ROOT = <repo>/assets/source/imagegen/temple_run; assets is parents[2].
RUNTIME = ROOT.parents[2] / "images" / "temple_run"


def save(im: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG", optimize=True)


def chroma_key_magenta(im: Image.Image) -> Image.Image:
    """Remove ImageGen's pink/magenta key field without touching warm skin/gold."""

    rgba = np.asarray(im.convert("RGBA")).copy()
    rgb = rgba[:, :, :3].astype(np.int16)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    # ImageGen's requested magenta is often a pink gradient rather than exact
    # #FF00FF.  The background remains blue/red dominant and green poor.
    magenta = (r > 125) & (b > 125) & (g < 125) & (r > g * 1.35) & (b > g * 1.35)
    # Only flood key-colour pixels connected to a cell boundary.  This avoids
    # erasing a rare magenta-like detail embedded in a generated subject.
    h, w = magenta.shape
    seen = np.zeros_like(magenta, dtype=bool)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        if magenta[0, x]: q.append((0, x))
        if magenta[h - 1, x]: q.append((h - 1, x))
    for y in range(h):
        if magenta[y, 0]: q.append((y, 0))
        if magenta[y, w - 1]: q.append((y, w - 1))
    while q:
        y, x = q.popleft()
        if seen[y, x] or not magenta[y, x]:
            continue
        seen[y, x] = True
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and magenta[ny, nx] and not seen[ny, nx]:
                q.append((ny, nx))
    # Clear every magenta-like pixel, including antialias fringe.  Leaving a
    # low-alpha pink fringe and then resizing it produces a visible neon halo.
    rgba[magenta, :] = 0
    return Image.fromarray(rgba, "RGBA")


def alpha_cleanup(im: Image.Image, threshold: int = 18) -> Image.Image:
    rgba = np.asarray(im.convert("RGBA")).copy()
    a = rgba[:, :, 3]
    a[a < threshold] = 0
    rgba[a == 0, :3] = 0
    rgba[:, :, 3] = a
    return Image.fromarray(rgba, "RGBA")


def extract_cell(im: Image.Image, row: int, col: int, rows: int, cols: int) -> Image.Image:
    w, h = im.size
    x0, x1 = round(col * w / cols), round((col + 1) * w / cols)
    y0, y1 = round(row * h / rows), round((row + 1) * h / rows)
    return im.crop((x0, y0, x1, y1))


def resize_fixed(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize RGBA through premultiplied alpha to prevent keyed-colour bleed."""
    if "A" not in im.getbands():
        return im.resize(size, Image.Resampling.LANCZOS)
    rgba = np.asarray(im.convert("RGBA")).astype(np.float32)
    alpha = rgba[:, :, 3] / 255.0
    premul = rgba[:, :, :3] * alpha[:, :, None]
    channels = [
        Image.fromarray(np.clip(premul[:, :, i], 0, 255).astype(np.uint8), "L").resize(size, Image.Resampling.LANCZOS)
        for i in range(3)
    ]
    alpha_im = Image.fromarray(np.clip(rgba[:, :, 3], 0, 255).astype(np.uint8), "L").resize(size, Image.Resampling.LANCZOS)
    out_a = np.asarray(alpha_im).astype(np.float32)
    out_rgb = np.stack([np.asarray(ch).astype(np.float32) for ch in channels], axis=-1)
    denom = np.maximum(out_a[:, :, None] / 255.0, 1e-6)
    out_rgb = np.clip(out_rgb / denom, 0, 255)
    out = np.dstack([out_rgb.astype(np.uint8), np.clip(out_a, 0, 255).astype(np.uint8)])
    out[out[:, :, 3] == 0, :3] = 0
    return Image.fromarray(out, "RGBA")


def translate_rgba(im: Image.Image, dx: int, dy: int) -> Image.Image:
    """Translate a transparent sprite without wrapping pixels around edges."""
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(im, (dx, dy))
    return out


def gif_frame(im: Image.Image) -> Image.Image:
    """Build a palette frame with an explicit transparent index."""
    rgba = im.convert("RGBA")
    rgb = rgba.convert("RGB")
    palette = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    pal = palette.getpalette()
    pal[255 * 3 : 255 * 3 + 3] = [0, 0, 0]
    palette.putpalette(pal)
    data = np.asarray(palette).copy()
    data[np.asarray(rgba)[:, :, 3] < 128] = 255
    palette = Image.fromarray(data.astype(np.uint8), "P")
    palette.putpalette(pal)
    palette.info["transparency"] = 255
    return palette


def opaque_background(raw: Path, out: Path, size=(720, 1280)) -> None:
    im = Image.open(raw).convert("RGB")
    # The generated source is 2:3.  Crop symmetrically to the requested 9:16
    # runtime plate, retaining the authored center lane and gate.
    target_ratio = size[0] / size[1]
    source_ratio = im.width / im.height
    if source_ratio > target_ratio:
        crop_w = round(im.height * target_ratio)
        left = (im.width - crop_w) // 2
        im = im.crop((left, 0, left + crop_w, im.height))
    elif source_ratio < target_ratio:
        crop_h = round(im.width / target_ratio)
        top = (im.height - crop_h) // 2
        im = im.crop((0, top, im.width, top + crop_h))
    save(im.resize(size, Image.Resampling.LANCZOS), out)


def average_edge_condition(im: Image.Image, band: int = 16) -> Image.Image:
    """Make a generated square material safe for repeat tiling.

    This is a low-impact deterministic seam treatment: opposite edge bands are
    cross-faded and their boundary rows/columns are averaged.  It does not add
    new artwork or draw stones.
    """

    arr = np.asarray(im.convert("RGB")).astype(np.float32)
    h, w, _ = arr.shape
    band = min(band, w // 8, h // 8)
    out = arr.copy()
    for i in range(band):
        t = (i + 1) / (band + 1)
        left = arr[:, i]
        right = arr[:, w - band + i]
        blend = left * t + right * (1 - t)
        out[:, i] = blend
        out[:, w - band + i] = blend
        top = arr[i, :]
        bottom = arr[h - band + i, :]
        blend_tb = top * t + bottom * (1 - t)
        out[i, :] = (out[i, :] + blend_tb) / 2
        out[h - band + i, :] = (out[h - band + i, :] + blend_tb) / 2
    # Exact edge equality makes repeated strips visually continuous.
    out[:, -1] = out[:, 0]
    out[-1, :] = out[0, :]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def alpha_bbox(im: Image.Image, threshold=24):
    a = np.asarray(im.convert("RGBA"))[:, :, 3]
    ys, xs = np.where(a >= threshold)
    if len(xs) == 0:
        return None
    return [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]


def edge_touch(im: Image.Image, threshold=24, margin=2):
    a = np.asarray(im.convert("RGBA"))[:, :, 3] >= threshold
    if not a.any():
        return True
    return bool(a[:margin].any() or a[-margin:].any() or a[:, :margin].any() or a[:, -margin:].any())


def split_pack(raw: Path, names: list[str], size: tuple[int, int], out_dir: Path) -> dict:
    im = alpha_cleanup(Image.open(raw), threshold=18)
    rows = cols = 2
    frames = []
    for idx, name in enumerate(names):
        cell = extract_cell(im, idx // cols, idx % cols, rows, cols)
        cell = alpha_cleanup(cell, threshold=18)
        cell = resize_fixed(cell, size)
        out = out_dir / f"{name}.png"
        save(cell, out)
        frames.append({"name": name, "size": list(cell.size), "alpha_bbox": alpha_bbox(cell), "edge_touch": edge_touch(cell)})
    return {"source": str(raw.relative_to(ROOT)), "frames": frames}


def write_run_frames() -> dict:
    raw = chroma_key_magenta(Image.open(RAW / "runner_run_raw.png"))
    frames = []
    run_dir = PROCESSED / "runner_run"
    run_dir.mkdir(parents=True, exist_ok=True)
    # The generated poses are coherent but their scarf/arm silhouettes create
    # small optical x shifts.  Recenter the body family and share one feet line
    # so the runner does not jitter while cycling.
    x_offsets = [-5, 10, -2, 8]
    baseline = 184
    for idx in range(4):
        cell = extract_cell(raw, idx // 2, idx % 2, 2, 2)
        cell = alpha_cleanup(cell, threshold=18)
        cell = resize_fixed(cell, (128, 192))
        before = alpha_bbox(cell)
        dy = baseline - before[3] if before else 0
        cell = translate_rgba(cell, x_offsets[idx], dy)
        name = f"run-{idx + 1}.png"
        save(cell, run_dir / name)
        frames.append({"name": name, "size": [128, 192], "alpha_bbox": alpha_bbox(cell), "x_offset": x_offsets[idx], "baseline_y": baseline, "edge_touch": edge_touch(cell)})
    sheet = Image.new("RGBA", (128 * 4, 192), (0, 0, 0, 0))
    for idx in range(4):
        sheet.alpha_composite(Image.open(run_dir / f"run-{idx + 1}.png"), (idx * 128, 0))
    save(sheet, RUNTIME / "runner_run.png")
    gif_frames = [gif_frame(Image.open(run_dir / f"run-{idx + 1}.png")) for idx in range(4)]
    gif_frames[0].save(
        PROCESSED / "runner_run.gif",
        save_all=True,
        append_images=gif_frames[1:],
        duration=110,
        loop=0,
        disposal=2,
        transparency=255,
    )
    # A small nearest-neighbour enlargement is useful for visual inspection.
    save(sheet.resize((1024, 384), Image.Resampling.NEAREST), QC / "runner_run_8x.png")
    bg = Image.new("RGBA", sheet.size, (42, 102, 69, 255))
    bg.alpha_composite(sheet)
    save(bg.resize((1024, 384), Image.Resampling.NEAREST), QC / "runner_run_on_green_8x.png")
    return {"source": "raw/runner_run_raw.png", "sheet": [512, 192], "gif": "processed/runner_run.gif (110ms loop)", "frames": frames}


def write_single_runner(name: str, size=(128, 192)) -> dict:
    im = alpha_cleanup(Image.open(RAW / f"runner_{name}_raw.png"), threshold=24)
    im = resize_fixed(im, size)
    before = alpha_bbox(im)
    baseline = 184
    dy = baseline - before[3] if before else 0
    im = translate_rgba(im, 0, dy)
    out = RUNTIME / f"runner_{name}.png"
    save(im, out)
    save(im.resize((512, 768), Image.Resampling.NEAREST), QC / f"runner_{name}_4x.png")
    return {"source": f"raw/runner_{name}_raw.png", "size": list(size), "alpha_bbox": alpha_bbox(im), "baseline_y": baseline, "vertical_offset": dy, "edge_touch": edge_touch(im)}


def write_single_prop(raw_name: str, runtime_name: str, size=(256, 256)) -> dict:
    im = alpha_cleanup(Image.open(RAW / raw_name), threshold=18)
    im = resize_fixed(im, size)
    out = RUNTIME / runtime_name
    save(im, out)
    return {"source": f"raw/{raw_name}", "runtime": f"assets/images/temple_run/{runtime_name}", "size": list(size), "alpha_bbox": alpha_bbox(im), "edge_touch": edge_touch(im)}


def write_preview(items: list[tuple[str, Path]], out: Path, columns=4, cell=(256, 256)) -> None:
    rows = math.ceil(len(items) / columns)
    canvas = Image.new("RGBA", (columns * cell[0], rows * cell[1]), (34, 49, 38, 255))
    draw = ImageDraw.Draw(canvas)
    for idx, (label, path) in enumerate(items):
        x, y = (idx % columns) * cell[0], (idx // columns) * cell[1]
        im = Image.open(path).convert("RGBA")
        thumb = ImageOps.contain(im, (cell[0] - 24, cell[1] - 36), Image.Resampling.LANCZOS)
        canvas.alpha_composite(thumb, (x + (cell[0] - thumb.width) // 2, y + 8))
        draw.text((x + 8, y + cell[1] - 22), label, fill=(248, 235, 183, 255))
    save(canvas, out)


def main() -> None:
    RUNTIME.mkdir(parents=True, exist_ok=True)
    PROCESSED.mkdir(parents=True, exist_ok=True)
    QC.mkdir(parents=True, exist_ok=True)
    manifest = {
        "generated_by": "ImageGen; deterministic postprocess only",
        "background": {},
        "path": {},
        "runner": {},
        "obstacles": {},
        "collectibles": {},
        "guardian": {},
    }

    opaque_background(RAW / "jungle_background_raw.png", RUNTIME / "jungle_background.png")
    manifest["background"] = {
        "source": "raw/jungle_background_raw.png",
        "source_size": list(Image.open(RAW / "jungle_background_raw.png").size),
        "runtime": "assets/images/temple_run/jungle_background.png",
        "runtime_size": [720, 1280],
        "crop": "center crop from 2:3 source to 9:16 runtime plate",
        "center_lane": "clear misty valley; no static road or runner",
    }

    path = Image.open(RAW / "temple_path_raw.png").convert("RGB")
    path = average_edge_condition(path.resize((512, 512), Image.Resampling.LANCZOS), band=20)
    save(path, RUNTIME / "temple_path.png")
    manifest["path"] = {"source": "raw/temple_path_raw.png", "runtime": "assets/images/temple_run/temple_path.png", "size": [512, 512], "repeat": "horizontal and vertical; equalized opposite edge bands"}

    manifest["runner"]["run"] = write_run_frames()
    manifest["runner"]["jump"] = write_single_runner("jump")
    manifest["runner"]["slide"] = write_single_runner("slide")

    obstacle_names = ["obstacle_hurdle_pack_reference", "obstacle_arch", "obstacle_rubble_pack_reference", "obstacle_pillar_variant"]
    manifest["obstacles"] = split_pack(RAW / "obstacle_pack_raw.png", obstacle_names, (256, 256), PROCESSED / "obstacles")
    manifest["obstacles"]["hurdle"] = write_single_prop("obstacle_hurdle_raw_v2.png", "obstacle_hurdle.png")
    manifest["obstacles"]["rubble"] = write_single_prop("obstacle_rubble_raw_v2.png", "obstacle_rubble.png")
    manifest["obstacles"]["arch"] = write_single_prop("obstacle_arch_raw_v2.png", "obstacle_arch.png") if (RAW / "obstacle_arch_raw_v2.png").exists() else {
        "source": "raw/obstacle_pack_raw.png",
        "runtime": "assets/images/temple_run/obstacle_arch.png",
        "size": [256, 256],
    }

    collectible_names = ["coin", "magnet", "shield", "boost"]
    manifest["collectibles"] = split_pack(RAW / "collectibles_pack_raw.png", collectible_names, (128, 128), PROCESSED / "collectibles")
    for name in collectible_names:
        save(Image.open(PROCESSED / "collectibles" / f"{name}.png"), RUNTIME / f"{name}.png")

    guardian = alpha_cleanup(Image.open(RAW / "guardian_raw.png"), threshold=18).resize((256, 256), Image.Resampling.LANCZOS)
    save(guardian, RUNTIME / "guardian.png")
    save(guardian.resize((768, 768), Image.Resampling.NEAREST), QC / "guardian_3x.png")
    manifest["guardian"] = {"source": "raw/guardian_raw.png", "runtime": "assets/images/temple_run/guardian.png", "size": [256, 256], "alpha_bbox": alpha_bbox(guardian), "edge_touch": edge_touch(guardian)}

    write_preview(
        [("hurdle", RUNTIME / "obstacle_hurdle.png"), ("arch", RUNTIME / "obstacle_arch.png"), ("rubble", RUNTIME / "obstacle_rubble.png"), ("coin", RUNTIME / "coin.png"), ("magnet", RUNTIME / "magnet.png"), ("shield", RUNTIME / "shield.png"), ("boost", RUNTIME / "boost.png"), ("guardian", RUNTIME / "guardian.png")],
        QC / "temple_run_assets_contact.png",
    )
    (QC / "qc-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
