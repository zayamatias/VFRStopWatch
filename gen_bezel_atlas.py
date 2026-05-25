#!/usr/bin/env python3
"""
Generate a compact bezel font atlas for the fenix7pro Connect IQ app.

Parameters chosen to stay within the fenix7pro graphics memory pool:
- CELL_SIZE: 36×36 pixels per glyph cell
- ANGLE_STEP: 15 degrees  →  24 angles per character
- COLS: 16 columns in the sprite sheet
- CHARS: 40 characters (0-9, A-Z, : - / space)

Total cells:  40 × 24 = 960
Grid rows:    ceil(960 / 16) = 60
Image size:   576 × 2160 pixels (grayscale)
Uncompressed: ~1.2 MB  (vs 16.2 MB for old atlas)
"""

import math, os, json
from PIL import Image, ImageDraw, ImageFont

# ── Parameters ──────────────────────────────────────────────────────────────
CELL_SIZE  = 24     # pixels per atlas cell — rendered at native size (no transform)
ANGLE_STEP = 15     # degrees between pre-rendered angles
NUM_ANGLES = 360 // ANGLE_STEP   # 24
COLS       = 16

CHARS = (
    "0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    ":-/ "
)
assert len(CHARS) == 40, f"Expected 40 chars, got {len(CHARS)}"

FONT_SIZE = 18      # pt — matches the ~20pt bezel slot font used by the vector fallback

# ── Find a usable monospace/sans font ───────────────────────────────────────
FONT_PATHS = [
    # macOS system fonts
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/SFNSText.ttf",
    "/System/Library/Fonts/SFNS.ttf",
]

font = None
for fp in FONT_PATHS:
    if os.path.exists(fp):
        try:
            font = ImageFont.truetype(fp, FONT_SIZE)
            print(f"Using font: {fp}")
            break
        except Exception:
            pass

if font is None:
    print("WARNING: no TrueType font found, falling back to PIL default bitmap font")
    font = ImageFont.load_default()

# ── Atlas dimensions ─────────────────────────────────────────────────────────
NUM_CHARS = len(CHARS)
total_cells = NUM_CHARS * NUM_ANGLES
rows = math.ceil(total_cells / COLS)
img_w = COLS * CELL_SIZE
img_h = rows * CELL_SIZE

print(f"Atlas: {NUM_CHARS} chars × {NUM_ANGLES} angles = {total_cells} cells")
print(f"Grid:  {COLS} cols × {rows} rows = {img_w}×{img_h} pixels")
print(f"Uncompressed: ~{img_w * img_h // 1024} KB (grayscale, black glyph on white bg)")

atlas = Image.new("L", (img_w, img_h), 255)  # white background (transparent with :tintColor)

for ci, ch in enumerate(CHARS):
    for ai in range(NUM_ANGLES):
        angle_deg = ai * ANGLE_STEP

        # Render glyph as BLACK-on-WHITE grayscale
        # :tintColor in Connect IQ tints dark (black) pixels and treats light (white) pixels
        # as transparent — so the glyph must be DARK and the background LIGHT.
        cell = Image.new("L", (CELL_SIZE, CELL_SIZE), 255)  # white background
        draw = ImageDraw.Draw(cell)

        try:
            bbox = draw.textbbox((0, 0), ch, font=font)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            tx = (CELL_SIZE - tw) // 2 - bbox[0]
            ty = (CELL_SIZE - th) // 2 - bbox[1]
        except AttributeError:
            tw, th = draw.textsize(ch, font=font)
            tx = (CELL_SIZE - tw) // 2
            ty = (CELL_SIZE - th) // 2

        draw.text((tx, ty), ch, fill=0, font=font)  # black glyph

        # Rotate (PIL rotates CCW; positive angle_deg = CW tilt)
        cell = cell.rotate(-angle_deg, expand=False, resample=Image.BICUBIC, fillcolor=255)

        # Paste into atlas
        atlas_index = ci * NUM_ANGLES + ai
        col = atlas_index % COLS
        row = atlas_index // COLS
        atlas.paste(cell, (col * CELL_SIZE, row * CELL_SIZE))

out_path = os.path.join(
    os.path.dirname(__file__),
    "resources", "fonts", "bezel_font.png"
)
atlas.save(out_path, optimize=True)
print(f"Saved: {out_path}")

# Also save metadata so the MC code knows the constants
meta = {
    "cell_size":   CELL_SIZE,
    "angle_step":  ANGLE_STEP,
    "num_angles":  NUM_ANGLES,
    "cols":        COLS,
    "num_chars":   NUM_CHARS,
    "chars":       CHARS,
    "img_w":       img_w,
    "img_h":       img_h,
}
meta_path = os.path.join(
    os.path.dirname(__file__),
    "resources", "fonts", "bezel_font_meta.json"
)
with open(meta_path, "w") as mf:
    json.dump(meta, mf, indent=2)
print(f"Saved meta: {meta_path}")
