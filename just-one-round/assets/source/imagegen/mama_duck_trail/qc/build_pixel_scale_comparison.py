from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[5]
RUNTIME = ROOT / "assets/images/mama_duck_trail"
CALIBRATION = ROOT / "assets/images/dung_dodge_v2/player_run_sheet.png"
OUTPUT = Path(__file__).with_name("pixel_scale_comparison.png")

canvas = Image.new("RGBA", (256, 112), (35, 42, 48, 255))
calibration_sheet = Image.open(CALIBRATION).convert("RGBA")
calibration_frame = calibration_sheet.crop((0, 0, 32, 32))
duckling = Image.open(RUNTIME / "duckling_idle.png").convert("RGBA")
mother = Image.open(RUNTIME / "mother_duck_idle.png").convert("RGBA")

canvas.alpha_composite(
    calibration_frame.resize((64, 64), Image.Resampling.NEAREST),
    (20, 24),
)
canvas.alpha_composite(
    duckling.resize((64, 64), Image.Resampling.NEAREST),
    (96, 24),
)
canvas.alpha_composite(
    mother.resize((64, 64), Image.Resampling.NEAREST),
    (172, 24),
)
canvas.save(OUTPUT)
