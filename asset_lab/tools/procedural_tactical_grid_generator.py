#!/usr/bin/env python3
"""
procedural_tactical_grid_generator.py

Generates professional AAA-grade tactical building grid and cursor reticle textures:
1. tactical_grid_cell.png (512x512 RGBA: Seamless repeating 4m grid cell with inner corner accents and center tick)
2. tactical_reticle.png   (512x512 RGBA: Snapping reticle with corner brackets and outer pulse glow)

Self-contained pure NumPy + PIL implementation.
"""

import os
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = os.path.abspath("Asserts/textures/tactical_grid")
os.makedirs(OUT_DIR, exist_ok=True)
SIZE = 512

def generate_tactical_grid_cell():
    """Generates a repeating 4m grid unit texture with cyan magic / tech blueprint aesthetics."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1. Subtle translucent interior fill (shows buildable zone)
    draw.rectangle([0, 0, SIZE, SIZE], fill=(20, 60, 90, 16))

    # 2. Main border line (2px on each side, shared across adjacent cells)
    border_color = (65, 190, 245, 180)
    border_inner = (120, 225, 255, 240)
    
    # Outer frame
    draw.rectangle([0, 0, SIZE - 1, SIZE - 1], outline=border_color, width=2)
    # Highlight sub-frame
    draw.rectangle([2, 2, SIZE - 3, SIZE - 3], outline=(40, 120, 180, 50), width=1)

    # 3. Corner tick brackets inside each cell
    corner_len = 28
    corner_inset = 6
    # Top-Left
    draw.line([(corner_inset, corner_inset), (corner_inset + corner_len, corner_inset)], fill=border_inner, width=2)
    draw.line([(corner_inset, corner_inset), (corner_inset, corner_inset + corner_len)], fill=border_inner, width=2)
    # Top-Right
    draw.line([(SIZE - corner_inset - 1, corner_inset), (SIZE - corner_inset - 1 - corner_len, corner_inset)], fill=border_inner, width=2)
    draw.line([(SIZE - corner_inset - 1, corner_inset), (SIZE - corner_inset - 1, corner_inset + corner_len)], fill=border_inner, width=2)
    # Bottom-Left
    draw.line([(corner_inset, SIZE - corner_inset - 1), (corner_inset + corner_len, SIZE - corner_inset - 1)], fill=border_inner, width=2)
    draw.line([(corner_inset, SIZE - corner_inset - 1), (corner_inset, SIZE - corner_inset - 1 - corner_len)], fill=border_inner, width=2)
    # Bottom-Right
    draw.line([(SIZE - corner_inset - 1, SIZE - corner_inset - 1), (SIZE - corner_inset - 1 - corner_len, SIZE - corner_inset - 1)], fill=border_inner, width=2)
    draw.line([(SIZE - corner_inset - 1, SIZE - corner_inset - 1), (SIZE - corner_inset - 1, SIZE - corner_inset - 1 - corner_len)], fill=border_inner, width=2)

    # 4. Subtle center crosshair tick
    mid = SIZE // 2
    c_len = 8
    draw.line([(mid - c_len, mid), (mid + c_len, mid)], fill=(80, 200, 255, 130), width=1)
    draw.line([(mid, mid - c_len), (mid, mid + c_len)], fill=(80, 200, 255, 130), width=1)
    draw.point((mid, mid), fill=(200, 245, 255, 220))

    # Save
    out_path = os.path.join(OUT_DIR, "tactical_grid_cell.png")
    img.save(out_path, "PNG")
    print(f"Generated: {out_path}")

def generate_tactical_reticle():
    """Generates the targeted cell snapping reticle (white base for dynamic color tinting)."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 1. Subtle central energy tint
    draw.rectangle([12, 12, SIZE - 13, SIZE - 13], fill=(255, 255, 255, 22))

    # 2. Sleek outer boundary border
    draw.rectangle([4, 4, SIZE - 5, SIZE - 5], outline=(255, 255, 255, 100), width=2)

    # 3. Bold Corner L-Brackets
    bracket_len = 72
    bracket_w = 6
    offset = 4
    
    # Top-Left
    draw.line([(offset, offset), (offset + bracket_len, offset)], fill=(255, 255, 255, 255), width=bracket_w)
    draw.line([(offset, offset), (offset, offset + bracket_len)], fill=(255, 255, 255, 255), width=bracket_w)
    # Top-Right
    draw.line([(SIZE - offset - 1, offset), (SIZE - offset - 1 - bracket_len, offset)], fill=(255, 255, 255, 255), width=bracket_w)
    draw.line([(SIZE - offset - 1, offset), (SIZE - offset - 1, offset + bracket_len)], fill=(255, 255, 255, 255), width=bracket_w)
    # Bottom-Left
    draw.line([(offset, SIZE - offset - 1), (offset + bracket_len, SIZE - offset - 1)], fill=(255, 255, 255, 255), width=bracket_w)
    draw.line([(offset, SIZE - offset - 1), (offset, SIZE - offset - 1 - bracket_len)], fill=(255, 255, 255, 255), width=bracket_w)
    # Bottom-Right
    draw.line([(SIZE - offset - 1, SIZE - offset - 1), (SIZE - offset - 1 - bracket_len, SIZE - offset - 1)], fill=(255, 255, 255, 255), width=bracket_w)
    draw.line([(SIZE - offset - 1, SIZE - offset - 1), (SIZE - offset - 1, SIZE - offset - 1 - bracket_len)], fill=(255, 255, 255, 255), width=bracket_w)

    # 4. Mid-edge pointer markers
    mid = SIZE // 2
    # Top pointer
    draw.polygon([(mid - 6, offset + 1), (mid + 6, offset + 1), (mid, offset + 10)], fill=(255, 255, 255, 220))
    # Bottom pointer
    draw.polygon([(mid - 6, SIZE - offset - 2), (mid + 6, SIZE - offset - 2), (mid, SIZE - offset - 11)], fill=(255, 255, 255, 220))
    # Left pointer
    draw.polygon([(offset + 1, mid - 6), (offset + 1, mid + 6), (offset + 10, mid)], fill=(255, 255, 255, 220))
    # Right pointer
    draw.polygon([(SIZE - offset - 2, mid - 6), (SIZE - offset - 2, mid + 6), (SIZE - offset - 11, mid)], fill=(255, 255, 255, 220))

    # Save
    out_path = os.path.join(OUT_DIR, "tactical_reticle.png")
    img.save(out_path, "PNG")
    print(f"Generated: {out_path}")

def main():
    print("Generating AAA Tactical Grid textures...")
    generate_tactical_grid_cell()
    generate_tactical_reticle()
    print("Done!")

if __name__ == "__main__":
    main()
