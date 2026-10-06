"""Normalize approved scene and align its floor to the unchanged 9x15 rules."""
from pathlib import Path
from PIL import Image

folder = Path(__file__).resolve().parent
project = folder.parents[4]
scene = Image.open(folder / 'clean-kitchen-master.png').convert('RGB')
scene = scene.resize((360, 764), Image.Resampling.NEAREST)
# Reuse the existing authored 9x15 floor so collision cells and visual cells
# share exactly the same boundaries; the approved outer frame is retained.
original = Image.open(project / 'assets/images/midnight_snake/apartment_background.png')
floor = original.crop((36, 112, 324, 592))
floor = floor.resize((264, 468), Image.Resampling.NEAREST)
scene.paste(floor, (48, 108))
scene.save(project / 'assets/images/midnight_snake/kitchen_playfield.png')
