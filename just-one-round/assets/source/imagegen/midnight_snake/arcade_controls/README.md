# Approved integrated arcade controls

Source: user-provided full-screen mockup, retained as `reference-20260909.png`.
`process.py` crops only the lower board frame, kitchen cabinet, keycaps, and
floor, then uses nearest-neighbor resampling to a 360×195 runtime asset. The
runtime draws it full-width below the board; no original snake, board, or HUD
art is replaced.

Visual contract: dark teal kitchen cabinet frame continues below the board,
with a restrained brown lower trim and floor, plus four small cream pixel
keycaps with dark-brown arrows in keyboard inverted-T order (up above left,
down, right). The keycaps stay visually compact while their runtime touch
targets remain larger and invisible.

Pressed feedback reuses the same key source rectangle with an amber color
filter and 2-logical-pixel depression, preserving each arrow's direction and
lighting. Gameplay board remains 9×15; only the control presentation changes.
