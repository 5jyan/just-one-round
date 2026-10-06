"""Deterministic export of generated, processor-cleaned atmosphere sprites."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT.parents[3]
reports = {}
GENERATED = Path('/Users/saulpark/.codex/generated_images/01a0e7e9-6965-7fd1-a6b0-3339f3ecf0fe')
RAW_NAMES = {'wind': 'exec-243d4e35-c9cb-4cf9-83c2-50198729ffd7.png',
             'leaf': 'exec-0fe25179-8551-40ae-9817-55826f40bdf9.png'}
for name, width, height in [('wind', 128, 32), ('leaf', 16, 16)]:
    source = ROOT / name / 'processed'
    output = ASSETS / 'images' / 'western_duel' / 'fx' / f'standoff_{name}'
    output.mkdir(parents=True, exist_ok=True)
    atlas = Image.new('RGBA', (width * 2, height * 2))
    frames = []
    for index in range(4):
        image = Image.open(source / f'idle-{index + 1}.png').convert('RGBA')
        box = image.getbbox()
        top = (image.height - height) // 2
        assert box and box[1] >= top and box[3] <= top + height, (name, box)
        image = image.crop((0, top, width, top + height))
        box = image.getbbox()
        assert box and box[0] > 0 and box[1] > 0 and box[2] < width and box[3] < height
        image.save(output / f'frame_{index + 1:02d}.png')
        atlas.paste(image, ((index % 2) * width, (index // 2) * height))
        frames.append({'frame': index + 1, 'bounds': box})
    atlas.save(output / 'sheet-transparent.png')
    raw = source / 'raw-sheet.png'
    reports[name] = {'cell': [width, height], 'grid': [2, 2], 'frames': frames,
                     'raw_sha256': hashlib.sha256(raw.read_bytes()).hexdigest(),
                     'source': str(raw), 'method': 'Built-in ImageGen + generate2dsprite processor; nearest export',
                     'generated_original': str(GENERATED / RAW_NAMES[name]),
                     'prompt': str(ROOT / name / 'prompt-used.txt'),
                     'runtime': str(output / 'sheet-transparent.png'),
                     'display_size': [width * 2, height * 2], 'scale': 2,
                     'calibration': 'western_duel/background/saloon_day_180x480.png',
                     'non_colliding': True, 'phase': 'standoff only'}
(ROOT / 'provenance.json').write_text(json.dumps(reports, indent=2) + '\n')
print(json.dumps(reports, indent=2))
