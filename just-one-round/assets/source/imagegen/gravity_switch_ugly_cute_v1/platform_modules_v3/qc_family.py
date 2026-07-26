from hashlib import sha256
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
PROCESSED = ROOT / "processed"
MASTER = PROCESSED / "scrap_module_1x1_01.png"

SPECS = {
    "scrap_module_1x1_01.png": (48, 48),
    "scrap_module_1x1_02.png": (48, 48),
    "scrap_module_1x1_03.png": (48, 48),
    "scrap_module_1x1_04.png": (48, 48),
    "scrap_module_2x1_01.png": (96, 48),
    "scrap_module_2x1_02.png": (96, 48),
    "scrap_module_3x1_01.png": (144, 48),
    "scrap_module_3x1_02.png": (144, 48),
    "scrap_module_1x2_01.png": (48, 96),
    "scrap_module_1x2_02.png": (48, 96),
    "scrap_module_1x3_01.png": (48, 144),
    "scrap_module_1x3_02.png": (48, 144),
    "scrap_module_2x2_01.png": (96, 96),
    "scrap_module_2x2_02.png": (96, 96),
    "scrap_module_3x2_01.png": (144, 96),
    "scrap_module_2x3_01.png": (96, 144),
}

PALETTE = {
    (48, 27, 52, 255),
    (67, 39, 69, 255),
    (96, 61, 91, 255),
    (135, 88, 117, 255),
    (78, 96, 39, 255),
    (112, 132, 48, 255),
    (171, 195, 54, 255),
    (232, 218, 133, 255),
    (226, 76, 38, 255),
}

master = Image.open(MASTER).convert("RGBA")
master_top = master.crop((0, 0, 48, 3))
master_bottom = master.crop((0, 45, 48, 48))
master_left = master.crop((0, 0, 3, 48))
master_right = master.crop((45, 0, 48, 48))
hashes = {}

for filename, expected_size in SPECS.items():
    path = PROCESSED / filename
    image = Image.open(path).convert("RGBA")
    assert image.size == expected_size, (filename, image.size, expected_size)
    assert image.getchannel("A").getextrema() == (255, 255), filename
    assert set(image.getdata()).issubset(PALETTE), filename
    assert (255, 0, 255, 255) not in set(image.getdata()), filename

    units_wide = image.width // 48
    units_high = image.height // 48
    for column in range(units_wide):
        x = column * 48
        assert image.crop((x, 0, x + 48, 3)).tobytes() == master_top.tobytes()
        assert (
            image.crop((x, image.height - 3, x + 48, image.height)).tobytes()
            == master_bottom.tobytes()
        )
    for row in range(units_high):
        y = row * 48
        assert image.crop((0, y, 3, y + 48)).tobytes() == master_left.tobytes()
        assert (
            image.crop((image.width - 3, y, image.width, y + 48)).tobytes()
            == master_right.tobytes()
        )

    digest = sha256(image.tobytes()).hexdigest()
    assert digest not in hashes, f"{filename} duplicates {hashes.get(digest)}"
    hashes[digest] = filename

assert len(list(PROCESSED.glob("scrap_module_*.png"))) == len(SPECS)
assert Image.open(ROOT / "previews" / "mixed_join_test.png").size == (384, 288)

print(
    "PASS: 16 unique modules; exact dimensions; opaque; fixed 9-color palette; "
    "no magenta; every 48px perimeter segment matches the approved connector."
)
