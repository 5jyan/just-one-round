"""Compose generated material art inside exact dartboard masks; extract sprites."""
import json
import math
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/source/imagegen/wind_darts/v2'
OUTPUT = ROOT / 'assets/images/wind_darts'
GENERATED = Path('/Users/saulpark/.codex/generated_images/01a0fa27-9370-79b0-998b-e459146fa6e2')
ORDER = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]


def material(tile, tint, strength=0.32, size=288):
    # Palette normalization preserves the generated wear and fibers, while
    # reducing value noise. A 2px base grid matches the reference's clusters.
    pixels = np.asarray(tile.resize((size // 2, size // 2), Image.Resampling.NEAREST), dtype=float)
    lum = pixels[..., :3].mean(axis=2)
    spread = max(float(lum.std()), 1)
    shade = np.clip((lum - np.median(lum)) / spread, -1.5, 1.5)
    shade = np.round(shade * 3) / 3
    colored = np.clip(np.array(tint) * (1 + shade[..., None] * strength), 0, 255)
    return Image.fromarray(colored.astype('uint8')).resize((size, size), Image.Resampling.NEAREST)


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    qc = SOURCE / 'qc'
    qc.mkdir(exist_ok=True)
    raw_paths = {
        'materials_raw.png': GENERATED / 'exec-792c77fb-8236-4d85-81b9-0ce8a8ef080f.png',
        'darts_raw.png': GENERATED / 'exec-584daeda-3a4b-4010-81de-bbbcb59c9973.png',
    }
    for name, path in raw_paths.items():
        if not (SOURCE / name).exists():
            shutil.copy2(path, SOURCE / name)
    raw = Image.open(SOURCE / 'materials_raw.png').convert('RGB')
    cell = raw.width // 3
    tiles = [raw.crop(((i % 3) * cell, (i // 3) * cell,
                      (i % 3 + 1) * cell, (i // 3 + 1) * cell)) for i in range(6)]
    palette = [(161, 131, 83), (33, 28, 22), (112, 43, 29),
               (50, 69, 42), (79, 43, 22), (119, 102, 76)]
    surfaces = [np.asarray(material(tile, tint, 0.25 if i < 4 else 0.35, size=288))
                for i, (tile, tint) in enumerate(zip(tiles, palette))]
    yy, xx = np.mgrid[0:288, 0:288]
    dx, dy = xx - 144, yy - 144
    radius = np.hypot(dx, dy)
    theta = np.mod(np.arctan2(dy, dx) + math.pi / 2 + math.pi / 20, 2 * math.pi)
    sector = np.floor(theta / (math.pi / 10)).astype(int) % 20
    board = np.zeros((288, 288, 4), dtype=np.uint8)
    def fill(mask, which):
        board[mask, :3] = surfaces[which][mask]
        board[mask, 3] = 255
    # A textured outer band gives the number atlas its own dark, weathered
    # home outside the scoring surface instead of letting labels sit on wires.
    fill(radius <= 140, 4)
    fill(radius <= 138, 4)
    fill(radius <= 120, 1)
    fill(np.abs(radius - 140) <= 0.45, 5)
    fill(radius <= 122, 1)
    fill((radius <= 114) & (sector % 2 == 0), 0)
    fill((radius <= 114) & (sector % 2 == 1), 1)
    rings = (((radius >= 114 * 95 / 170) & (radius <= 114 * 111 / 170)) |
             ((radius >= 114 * 154 / 170) & (radius <= 114)))
    fill(rings & (sector % 2 == 0), 2)
    fill(rings & (sector % 2 == 1), 3)
    # Narrow exact wire masks use the generated patinated metal, not flat paint.
    near_boundary = np.minimum(np.mod(theta, math.pi / 10),
                               math.pi / 10 - np.mod(theta, math.pi / 10))
    wires = (np.sin(near_boundary) * radius <= 0.38) & (radius <= 114)
    for ratio in [95 / 170, 111 / 170, 154 / 170, 1]:
        wires |= np.abs(radius - 114 * ratio) <= 0.40
    fill(wires & (radius <= 114.5), 5)
    fill(radius <= 114 * 15.9 / 170, 3)
    fill(np.abs(radius - 114 * 15.9 / 170) <= 0.40, 5)
    fill(radius <= 114 * 6.35 / 170, 2)
    fill(np.abs(radius - 114 * 6.35 / 170) <= 0.35, 5)
    face = Image.fromarray(board).resize((576, 576), Image.Resampling.NEAREST)
    face.save(OUTPUT / 'board_face.png')

    atlas = Image.new('RGBA', (320, 256))
    font = ImageFont.truetype(str(ROOT / 'assets/fonts/Galmuri11-Bold.ttf'), 11)
    # Keep the existing number atlas byte-for-byte stable while the board face
    # grows a separate, textured label band.
    metal = np.asarray(material(tiles[5], (204, 178, 130), 0.15, size=256))
    for value in range(1, 21):
        mask = Image.new('L', (32, 32))
        draw = ImageDraw.Draw(mask)
        text = str(value)
        box = draw.textbbox((0, 0), text, font=font)
        pos = ((32 - (box[2] - box[0])) // 2 - box[0],
               (32 - (box[3] - box[1])) // 2 - box[1])
        draw.text(pos, text, fill=255, font=font, stroke_width=0)
        # Preserve crisp pixel font masks instead of anti-aliased lettering.
        mask = mask.point(lambda value: 255 if value >= 128 else 0)
        glyph = Image.new('RGBA', (32, 32))
        shadow = Image.new('RGBA', (32, 32), (20, 13, 7, 255))
        shadow.putalpha(mask)
        glyph.alpha_composite(shadow, (1, 1))
        ink = Image.fromarray(metal[:32, :32]).convert('RGBA')
        ink.putalpha(mask)
        glyph.alpha_composite(ink)
        glyph = glyph.resize((64, 64), Image.Resampling.NEAREST)
        atlas.alpha_composite(glyph, (((value - 1) % 5) * 64, ((value - 1) // 5) * 64))
    atlas.save(OUTPUT / 'board_numbers.png')

    dart_raw = Image.open(SOURCE / 'darts_raw.png').convert('RGBA')
    darts = Image.new('RGBA', (192, 128))
    dart_bounds = []
    for index in range(2):
        half = dart_raw.width // 2
        sprite = dart_raw.crop((index * half, 0, (index + 1) * half, dart_raw.height))
        crop = sprite.getchannel('A').getbbox()
        assert crop is not None
        sprite = sprite.crop(crop)
        sprite = sprite.resize((round(sprite.width * 104 / sprite.height), 104), Image.Resampling.NEAREST)
        sprite.putalpha(sprite.getchannel('A').point(lambda value: 255 if value > 128 else 0))
        alpha = np.asarray(sprite.getchannel('A'))
        nonempty_rows = np.where(alpha.max(axis=1) > 128)[0]
        tip_y = int(nonempty_rows[0])
        tip_columns = np.where(alpha[tip_y] > 128)[0]
        tip_x = int(tip_columns[len(tip_columns) // 2])
        cell_img = Image.new('RGBA', (96, 128))
        cell_img.alpha_composite(sprite, (48 - tip_x, 12 - tip_y))
        bounds = cell_img.getchannel('A').getbbox()
        assert bounds[0] > 0 and bounds[2] < 96 and bounds[1] == 12 and bounds[3] < 128
        assert cell_img.getpixel((48, 12))[3] > 128
        dart_bounds.append(bounds)
        darts.alpha_composite(cell_img, (index * 96, 0))
    darts.save(OUTPUT / 'dart_atlas.png')

    composite = face.copy()
    for index, value in enumerate(ORDER):
        angle = -math.pi / 2 + index * math.pi / 10
        gx = round(288 + math.cos(angle) * 260 - 32)
        gy = round(288 + math.sin(angle) * 260 - 32)
        src = ((value - 1) % 5 * 64, (value - 1) // 5 * 64)
        glyph = atlas.crop((src[0], src[1], src[0] + 64, src[1] + 64))
        composite.alpha_composite(glyph, (gx, gy))
    composite.save(qc / 'board-numbered.png')
    preview = Image.open(ROOT / 'assets/images/wind_darts/pub_interior.png').convert('RGBA')
    scale = max(360 / preview.width, 640 / preview.height)
    w, h = 360 / scale, 640 / scale
    crop = ((preview.width - w) / 2, (preview.height - h) / 2,
            (preview.width + w) / 2, (preview.height + h) / 2)
    preview = preview.crop(crop).resize((360, 640), Image.Resampling.NEAREST)
    preview.alpha_composite(Image.new('RGBA', preview.size, (20, 13, 7, 102)))
    rendered = composite.resize((319, 319), Image.Resampling.NEAREST)
    preview.alpha_composite(rendered, (21, 76))
    preview.save(qc / 'composition-360x640.png')
    metadata = {
        'source': 'Codex built-in ImageGen; exact prompts stored beside raw images',
        'master_reference': 'assets/images/wind_darts/pub_interior.png',
        'exception': 'user approved detailed dark antique western pixel art; no ugly-cute or hands',
        'board_face': {'size': [576, 576], 'base_grid': [288, 288], 'center': [288, 288],
                       'score_radius': 228, 'outer_radius': 280, 'number_radius': 260,
                       'sector_order': ORDER, 'first_sector_center_degrees': -90,
                       'runtime_visual_rotation_offset_degrees': 9,
                       'runtime_board_angle_degrees': -9,
                       'triple_radius': [95 / 170, 111 / 170],
                       'double_radius': [154 / 170, 1.0]},
        'board_numbers': {'size': [320, 256], 'cell': [64, 64], 'layout': [5, 4],
                          'values': list(range(1, 21)), 'center': [32, 32], 'font': 'Galmuri11-Bold'},
        'dart_atlas': {'size': [192, 128], 'cell': [96, 128], 'tip_anchor': [48, 12],
                       'order': ['flight', 'embedded'], 'visible_bounds': dart_bounds},
        'processing': 'Generated texture palette normalization, exact geometry masks, nearest-neighbor resize and alpha compositing. No synthetic creative texture.',
        'qc': {'alpha_padding': True, 'tip_anchors': True, 'score_radius': True,
               'static_composite_is_not_runtime_screenshot': True},
    }
    (SOURCE / 'processing-meta.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'outputs': ['board_face.png', 'board_numbers.png', 'dart_atlas.png'], 'dart_bounds': dart_bounds}))


if __name__ == '__main__':
    main()
