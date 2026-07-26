# Gravity Switch quiet base modules (v4)

This additive family keeps every v3 module intact and adds low-detail, dark
ground modules using the approved `basic_1x1_01` as the master reference.
Every other module has its own built-in ImageGen source under
`generated_family/raw`; no module interior is procedurally drawn.

- One cell is 48 × 48 px.
- Every output is a complete opaque collision-ground asset.
- No separate soil or fill image is assumed.
- Large modules must never be cropped at runtime.
- Runtime placement should try smaller modules when a larger footprint does
  not fit.
- Runtime placement should avoid placing the same asset ID edge-adjacent when
  another fitting asset is available.
- Deterministic postprocessing is limited to chroma removal, exact-size
  normalization, five-color quantization, and three-pixel connector cleanup.

Run:

```sh
python3 build_basic_family.py
python3 qc_basic_family.py
```
