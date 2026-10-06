"""Clean generated alpha and assemble fixed-scale cups; no creative drawing."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops

HERE = Path(__file__).resolve().parent
raw = Image.open(HERE / 'corrected-raw.png').convert('RGBA')
atlas = Image.new('RGBA', (1024, 256))
for i in range(4):
    frame = raw.crop((round(i * raw.width / 4), 0,
                      round((i + 1) * raw.width / 4), raw.height))
    alpha = frame.getchannel('A')
    mask = alpha.point(lambda a: 255 if a > 100 else 0)
    ImageDraw.floodfill(mask, (270, 450), 128)
    mask = mask.point(lambda a: 255 if a == 128 else 0).filter(ImageFilter.MaxFilter(3))
    frame.putalpha(ImageChops.multiply(alpha, mask))
    frame = frame.crop(frame.getbbox())
    frame = frame.resize((round(frame.width * .43), round(frame.height * .43)), Image.Resampling.LANCZOS)
    cell = Image.new('RGBA', (256, 256))
    cell.alpha_composite(frame, ((256 - frame.width) // 2, 244 - frame.height))
    cell.putalpha(cell.getchannel('A').point(lambda a: 0 if a < 8 else a))
    cell.save(HERE / f'{i}.png')
    atlas.alpha_composite(cell, (i * 256, 0))
atlas.save(HERE / 'atlas.png')
atlas.save(HERE.parents[5] / 'assets/images/ramen_timer/ramen_cup_atlas.png')
