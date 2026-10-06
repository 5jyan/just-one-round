"""Reassemble generated artwork; no creative drawing or pixel-art upscaling.

Run generate2dsprite.py first to create each processed/raw-sheet-clean.png.
Reviewed source rectangles recover complete subjects where generated poses
crossed nominal grid lines (foil lids, ears and chopsticks).
"""
from pathlib import Path
import json
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
RUNTIME = ROOT / 'assets/images/ramen_timer'
CELL = 256
BOUNDS = {
    'idle': [(58, 6, 593, 609), (665, 6, 1211, 609),
             (58, 635, 595, 1237), (666, 634, 1206, 1237)],
    'poses': [(49, 9, 426, 434), (474, 11, 848, 436),
              (28, 449, 455, 862), (477, 449, 871, 862),
              (37, 877, 473, 1296), (477, 873, 867, 1297),
              (49, 1329, 415, 1749), (480, 1338, 836, 1748)],
    'cups': [(173, 20, 455, 326), (696, 13, 974, 326),
             (173, 347, 457, 667), (694, 331, 1006, 667),
             (130, 674, 499, 1015), (702, 646, 1022, 1013),
             (174, 1036, 458, 1341), (692, 1036, 973, 1341)],
    'fx': [(139, 72, 432, 475), (601, 102, 916, 494),
           (124, 539, 426, 951), (585, 589, 944, 931),
           (86, 1031, 439, 1376), (563, 1003, 930, 1440)],
}


def frames(name):
    source = Image.open(HERE / name / 'processed/raw-sheet-clean.png').convert('RGBA')
    cropped = [source.crop(box) for box in BOUNDS[name]]
    if name == 'cups':
        # The extended dry-noodle chopsticks cross the nominal row boundary.
        # Isolate this connected cup, excluding a sliver of the cup above it.
        for index, frame in enumerate(cropped):
            if index == 4:  # Keep the perfect cup's detached sparkle accents.
                continue
            mask = frame.getchannel('A').point(lambda a: 255 if a > 32 else 0)
            ImageDraw.floodfill(mask, (frame.width // 2, frame.height * 3 // 4), 128)
            mask = mask.point(lambda a: 255 if a == 128 else 0).filter(ImageFilter.MaxFilter(3))
            frame.putalpha(ImageChops.multiply(frame.getchannel('A'), mask))
    # One magnification per family: legitimate pose and cup changes remain.
    scale = 228 / max(max(frame.size) for frame in cropped)
    output = []
    for index, frame in enumerate(cropped):
        frame = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.LANCZOS)
        cell = Image.new('RGBA', (CELL, CELL))
        top = (CELL - frame.height) // 2 if name == 'fx' else 244 - frame.height
        cell.alpha_composite(frame, ((CELL - frame.width) // 2, top))
        cell.putalpha(cell.getchannel('A').point(lambda a: 0 if a < 8 else a))
        bounds = cell.getbbox()
        assert bounds and min(bounds[:2]) > 0 and max(bounds[2:]) < CELL
        folder = HERE / name / 'final_frames'
        folder.mkdir(exist_ok=True)
        cell.save(folder / f'{index}.png')
        output.append(cell)
    return output


def atlas(name, cells, columns):
    rows = (len(cells) + columns - 1) // columns
    image = Image.new('RGBA', (columns * CELL, rows * CELL))
    for index, frame in enumerate(cells):
        image.alpha_composite(frame, ((index % columns) * CELL, (index // columns) * CELL))
    image.save(RUNTIME / name)
    return {'size': list(image.size), 'layout': [columns, rows], 'cell_size': CELL}


def main():
    RUNTIME.mkdir(exist_ok=True, parents=True)
    # Uniform crop of the regenerated tall scene. Back edge of counter is
    # source y=1045 -> world y=432, with genuine cabinetry in lower overscan.
    crop = (53, 0, 788, 1633)
    background = Image.open(HERE / 'background/revised-raw.png').convert('RGB')
    background = background.crop(crop).resize((720, 1600), Image.Resampling.LANCZOS)
    background.save(RUNTIME / 'office_background.png')
    background.crop((0, 1024, 720, 1312)).save(RUNTIME / 'counter_front.png')
    idle, poses, cups, fx = (frames(name) for name in BOUNDS)
    # User-requested printed lid edit; preserve the reviewed frame geometry.
    lid_edit = HERE / 'lid_print'
    if (lid_edit / 'atlas.png').exists():
        cups[:4] = [Image.open(lid_edit / f'{i}.png').convert('RGBA') for i in range(4)]
    cooked_noodles = HERE / 'cooked_noodles/frame.png'
    if cooked_noodles.exists():
        cups[5] = Image.open(cooked_noodles).convert('RGBA')
    assets = {
        'office_background.png': {'size': [720, 1600], 'world_rect': [0, -80, 360, 800], 'reviewed_source_crop': crop},
        'counter_front.png': {'size': [720, 288], 'world_rect': [0, 432, 360, 144]},
        'raccoon_idle_sheet.png': atlas('raccoon_idle_sheet.png', idle, 4),
        'raccoon_pose_atlas.png': atlas('raccoon_pose_atlas.png', poses, 4),
        'ramen_cup_atlas.png': atlas('ramen_cup_atlas.png', cups[:4], 4),
        'ramen_fx_atlas.png': atlas('ramen_fx_atlas.png', fx, 3),
        'ramen_result_atlas.png': atlas('ramen_result_atlas.png', cups[4:7], 3),
    }
    manifest = {
        'version': 3,
        'source_contract': str(HERE.relative_to(ROOT)),
        'runtime_root': str(RUNTIME.relative_to(ROOT)),
        'style': 'clean_hd_2d_cartoon',
        'approved_exception': 'User approved replacing pixel art with crisp 2D cartoon on 2026-09-19.',
        'pixel_filter': 'medium',
        'assembly_resampling': 'LANCZOS',
        'source_rectangles': BOUNDS,
        'safe_core': [0, 0, 360, 640],
        'authored_overscan': [0, -80, 360, 800],
        'game_rules_version': 4,
        'lid_print_edit': {
            'source': 'cartoon_refresh_v3/lid_print/corrected-raw.png',
            'prompt': 'cartoon_refresh_v3/lid_print/corrected-prompt.txt',
            'text': '辛',
            'method': 'Built-in ImageGen; full-rim closed lid, silver peeled undersides; process.py uses shared .43 scale and bottom244.',
        },
        'assets': assets,
    }
    (HERE.parent / 'runtime_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    (HERE / 'pipeline-meta.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print('Assembled 7 HD assets with unchanged runtime atlas layouts.')


if __name__ == '__main__':
    main()
