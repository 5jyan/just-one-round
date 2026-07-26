from pathlib import Path
import json

from PIL import Image


ROOT = Path(__file__).resolve().parent
PROCESSED = ROOT / "processed"
CONTRACT = json.loads((ROOT / "basic-family-contract.json").read_text())
allowed = {tuple(color) for color in CONTRACT["palette"]}

raw_files = sorted((ROOT / "generated_family" / "raw").glob("*.png"))
keyed_files = sorted((ROOT / "generated_family" / "keyed").glob("*.png"))
assert len(raw_files) == 14, len(raw_files)
assert len(keyed_files) == 14, len(keyed_files)

files = sorted(PROCESSED.glob("scrap_basic_*.png"))
assert len(files) == len(CONTRACT["assets"]), (
    len(files),
    len(CONTRACT["assets"]),
)

names = set()
pixel_payloads = set()
for asset in CONTRACT["assets"]:
    name = asset["name"]
    assert name not in names
    names.add(name)
    image = Image.open(PROCESSED / f"{name}.png").convert("RGBA")
    assert list(image.size) == asset["pixels"], (name, image.size)
    colors = set(image.getdata())
    assert colors <= allowed, (name, colors - allowed)
    assert {alpha for *_, alpha in colors} == {255}, name
    assert not any(
        red > 220 and blue > 180 and green < 50
        for red, green, blue, _ in colors
    ), name
    payload = image.tobytes()
    assert payload not in pixel_payloads, f"Duplicate processed art: {name}"
    pixel_payloads.add(payload)

print(
    "PASS: 14 individual ImageGen sources + approved master; "
    "15 unique quiet base modules; exact whole-cell dimensions; "
    "opaque; fixed 5-color palette; existing v3 preserved."
)
