"""Extract the two generated action poses into the existing runtime cells."""

from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[1] / "raw/v4/student_jump_slide_raw.png"
RUNTIME = HERE.parents[5] / "images/homebound_run"

sheet = Image.open(SOURCE).convert("RGBA")
half = sheet.width // 2
for index, (name, height) in enumerate((("jump", 202), ("slide", 125))):
    source = sheet.crop((index * half, 0, (index + 1) * half, sheet.height))
    alpha = source.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise ValueError(f"{name} pose is empty")
    source.putalpha(alpha)
    cropped = source.crop(bounds)
    width = round(cropped.width * height / cropped.height)
    if width > 180:
        width = 180
        height = round(cropped.height * width / cropped.width)
    pose = cropped.resize((width, height), Image.Resampling.NEAREST)
    cell = Image.new("RGBA", (192, 288))
    cell.alpha_composite(pose, ((192 - width) // 2, 272 - height))
    cell.save(HERE / f"student_{name}.png")
    cell.save(RUNTIME / f"student_{name}.png")
