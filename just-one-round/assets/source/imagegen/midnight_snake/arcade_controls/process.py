"""Deterministically extract the approved arcade control artwork (no repainting)."""
from pathlib import Path
from PIL import Image

folder = Path(__file__).resolve().parent
project = folder.parents[4]
raw = folder / 'reference-20260909.png'
image = Image.open(raw).convert('RGB')
# The supplied full-screen mockup is 861×1827. Keep only the lower cabinet,
# keycaps, trim, and floor, then fit it to the 360px logical game width.
panel = image.crop((0, 1350, 861, 1817)).resize((360, 195), Image.Resampling.NEAREST)
panel.save(project / 'assets/images/midnight_snake/arcade_controls.png')
