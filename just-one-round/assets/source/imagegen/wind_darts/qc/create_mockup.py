"""Build a static composition check for wind_darts source art; not runtime artwork."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[5]
ART = ROOT / 'assets/images/wind_darts'
OUT = Path(__file__).with_name('composite_mockup.png')
W, H = 360, 640

bg = Image.open(ART / 'pub_interior.png').convert('RGBA')
scale = max(W / bg.width, H / bg.height)
bg = bg.resize((round(bg.width * scale), round(bg.height * scale)), Image.Resampling.NEAREST)
left, top = (bg.width - W) // 2, (bg.height - H) // 2
canvas = bg.crop((left, top, left + W, top + H))

machine = Image.open(ART / 'dart_machine.png').convert('RGBA').resize((310, 465), Image.Resampling.NEAREST)
machine_y = 65
canvas.alpha_composite(machine, ((W - machine.width) // 2, machine_y))

# Render one static, standard-number-order dartboard for visual placement QC.
draw = ImageDraw.Draw(canvas)
cx, cy, radius = W / 2, machine_y + 465 * 0.365, 64
ratios = lambda mm: radius * mm / 170
numbers = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
colors = ('#151513', '#ddd6c1')
draw.ellipse((cx-radius-5, cy-radius-5, cx+radius+5, cy+radius+5), fill='#70572d', outline='#e4c475', width=2)
for i, number in enumerate(numbers):
    start = -99 + i * 18
    end = start + 18
    draw.pieslice((cx-radius, cy-radius, cx+radius, cy+radius), start, end, fill=colors[i % 2])
    for inner, outer, color in (
        (ratios(99), ratios(107), '#b62820' if i % 2 == 0 else '#16804a'),
        (ratios(162), ratios(170), '#b62820' if i % 2 == 0 else '#16804a'),
    ):
        draw.pieslice((cx-outer, cy-outer, cx+outer, cy+outer), start, end, fill=color)
    a = math.radians(start)
    draw.line((cx, cy, cx + math.cos(a)*radius, cy + math.sin(a)*radius), fill='#8b8676', width=1)
    a = math.radians(start + 9)
    tx, ty = cx + math.cos(a)*(radius+8), cy + math.sin(a)*(radius+8)
    draw.text((round(tx-3), round(ty-4)), str(number), fill='#f0e7cf')
for ring in (ratios(99), ratios(107), ratios(162), ratios(170)):
    draw.ellipse((cx-ring, cy-ring, cx+ring, cy+ring), outline='#9b957f', width=1)
draw.ellipse((cx-ratios(15.9), cy-ratios(15.9), cx+ratios(15.9), cy+ratios(15.9)), fill='#16804a', outline='#d2c49a')
draw.ellipse((cx-ratios(6.35), cy-ratios(6.35), cx+ratios(6.35), cy+ratios(6.35)), fill='#c52c23', outline='#ebd6a2')

# Minimal illustrative HUD blocks; labels are examples, not baked game assets.
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 13)
draw.rounded_rectangle((12, 10, 143, 54), radius=6, fill='#17120ee8', outline='#b78745', width=1)
draw.text((20, 14), 'WIND  1.4 m/s', font=font, fill='#f0d39a')
draw.text((20, 33), 'THROW  1 / 5', font=font, fill='#f5eee0')
draw.rounded_rectangle((220, 10, 348, 54), radius=6, fill='#17120ee8', outline='#b78745', width=1)
draw.text((229, 14), 'OPPONENT', font=font, fill='#c9a36d')
draw.text((229, 33), 'SHOT 1  ·  24', font=font, fill='#f5eee0')
draw.rounded_rectangle((12, 574, 142, 615), radius=6, fill='#17120ee8', outline='#b78745', width=1)
draw.text((19, 579), 'POWER', font=font, fill='#f0d39a')
draw.rounded_rectangle((20, 598, 134, 606), radius=4, fill='#393126')
draw.rounded_rectangle((20, 598, 87, 606), radius=4, fill='#d69739')

hand = Image.open(ART / 'throwing_hand.png').convert('RGBA').resize((328, 300), Image.Resampling.NEAREST)
hand = hand.rotate(-40, resample=Image.Resampling.NEAREST, expand=True)
canvas.alpha_composite(hand, (-14, 300))
canvas.convert('RGB').save(OUT)
print(OUT)
