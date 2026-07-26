from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT.parents[2] / "images" / "dung_dodge_v2"
RUNTIME.mkdir(parents=True, exist_ok=True)


def resize_background() -> None:
    source = Image.open(ROOT / "background" / "raw-background.png").convert("RGB")
    target_ratio = 360 / 640
    source_ratio = source.width / source.height
    if source_ratio > target_ratio:
        crop_width = round(source.height * target_ratio)
        left = (source.width - crop_width) // 2
        source = source.crop((left, 0, left + crop_width, source.height))
    else:
        crop_height = round(source.width / target_ratio)
        top = (source.height - crop_height) // 2
        source = source.crop((0, top, source.width, top + crop_height))
    output = source.resize((360, 640), Image.Resampling.NEAREST)
    output.save(ROOT / "background" / "processed" / "background-map.png")
    output.save(RUNTIME / "background_map.png")


def resize_ground() -> None:
    source = Image.open(
        ROOT / "ground" / "processed" / "ground-transparent.png"
    ).convert("RGBA")
    alpha_box = source.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError("Ground chroma key produced an empty image.")
    source = source.crop(alpha_box)
    target_ratio = 180 / 48
    source_ratio = source.width / source.height
    if source_ratio > target_ratio:
        crop_width = round(source.height * target_ratio)
        centered_left = (source.width - crop_width) // 2
        left = min(source.width - crop_width, centered_left + crop_width // 4)
        source = source.crop((left, 0, left + crop_width, source.height))
    elif source_ratio < target_ratio:
        crop_height = round(source.width / target_ratio)
        source = source.crop((0, 0, source.width, crop_height))
    output = source.resize((180, 48), Image.Resampling.NEAREST)
    output.save(ROOT / "ground" / "processed" / "ground-strip.png")
    output.save(RUNTIME / "ground_strip.png")


def copy_sprite_sheets() -> None:
    sheet_contract = {
        "player_idle": "player_idle_sheet.png",
        "player_run": "player_run_sheet.png",
        "poop": "poop_fall_sheet.png",
        "dust": "dust_sheet.png",
    }
    for source_name, runtime_name in sheet_contract.items():
        image = Image.open(
            ROOT / source_name / "processed" / "sheet-transparent.png"
        ).convert("RGBA")
        image.save(RUNTIME / runtime_name)


resize_background()
resize_ground()
copy_sprite_sheets()
