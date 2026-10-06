# v7 processor notes

- `processed_native_540_fit90/` is the accepted processor result. It passes
  strict grounded-body QC with the reviewed source-edge override; every output
  frame has zero paste clamping and no output-edge contact.
- `delivery_270x540/` is assembled from the accepted 540px frames by the
  transparent-only centered crop `[135, 0, 405, 540]`. The assembly script
  rejects any opaque pixel loss; the fire frame's extended revolver remains
  inside the delivery cell.
- `processed_native_540/` is retained as a superseded fit-scale experiment
  (the subject was about 54% of the square frame and too small for runtime).
- `processed_native_540_fit95/` is retained as a rejected experiment because
  the larger scale caused strict paste-clamp failures on the bottom row.
