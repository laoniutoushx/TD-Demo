#!/usr/bin/env python3
"""
procedural_foundation_texture_generator.py

Generates AAA-quality PBR contact decal textures for turret foundations:
1. foundation_contact_albedo.png (RGBA: Base ground & crushed gravel with organic feathered alpha)
2. foundation_contact_normal.png (RGBA: Tangent-space normal with soil displacement and mound incline)
3. foundation_contact_orm.png    (RGB: R=Contact AO, G=Roughness, B=Metallic)

Pure NumPy + PIL implementation, self-contained and deterministic.
"""

import os
import math
import numpy as np
from PIL import Image

OUT_DIR = os.path.abspath("Asserts/textures/foundation")
os.makedirs(OUT_DIR, exist_ok=True)

SIZE = 1024
HALF = SIZE // 2

def generate_fbm_noise(size, octaves=4, persistence=0.5, lacunarity=2.0, seed=42):
    """Generates continuous 2D fBM noise using vectorized value noise + cubic Hermite interp."""
    rng = np.random.RandomState(seed)
    total = np.zeros((size, size), dtype=np.float32)
    freq = 1.0
    amp = 1.0
    max_amp = 0.0

    for _ in range(octaves):
        grid_w = max(4, int(size * freq / 32))
        grid_h = max(4, int(size * freq / 32))
        r = rng.rand(grid_h + 2, grid_w + 2).astype(np.float32)
        
        # Grid coordinates
        y = np.linspace(0, grid_h, size, endpoint=False)
        x = np.linspace(0, grid_w, size, endpoint=False)
        
        x0 = x.astype(np.int32)
        x1 = x0 + 1
        y0 = y.astype(np.int32)
        y1 = y0 + 1
        
        fx = (x - x0)[:, None] # (size, 1)
        fy = (y - y0)[None, :] # (1, size)
        
        # Smooth hermite s-curve: 3t^2 - 2t^3
        sx = fx * fx * (3.0 - 2.0 * fx)
        sy = fy * fy * (3.0 - 2.0 * fy)
        
        # Bilinear interpolation of random grid points
        v00 = r[y0[:, None], x0[None, :]]
        v10 = r[y0[:, None], x1[None, :]]
        v01 = r[y1[:, None], x0[None, :]]
        v11 = r[y1[:, None], x1[None, :]]
        
        top = v00 * (1.0 - sx.T) + v10 * sx.T
        bot = v01 * (1.0 - sx.T) + v11 * sx.T
        layer = top * (1.0 - sy) + bot * sy
        
        total += layer * amp
        max_amp += amp
        amp *= persistence
        freq *= lacunarity

    return total / max_amp

def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

def main():
    print(f"Generating foundation contact textures (size={SIZE}x{SIZE})...")

    # Coordinate grids
    y, x = np.ogrid[:SIZE, :SIZE]
    dx = (x - HALF).astype(np.float32) / HALF
    dy = (y - HALF).astype(np.float32) / HALF
    r = np.sqrt(dx * dx + dy * dy)
    angle = np.arctan2(dy, dx)

    # Multi-octave organic noise
    noise1 = generate_fbm_noise(SIZE, octaves=4, persistence=0.55, lacunarity=2.1, seed=101)
    noise2 = generate_fbm_noise(SIZE, octaves=3, persistence=0.5, lacunarity=2.0, seed=202)
    noise_cracks = generate_fbm_noise(SIZE, octaves=5, persistence=0.6, lacunarity=2.2, seed=303)

    # 1. Base Soil & Gravel Albedo Loading or Synthesis
    ground_color_path = "textures/Ground003_2K-JPG_Color.jpg"
    if not os.path.exists(ground_color_path):
        ground_color_path = "Asserts/materials/Ground003_2K-JPG/Ground003_2K-JPG_Color.jpg"

    if os.path.exists(ground_color_path):
        img_src = Image.open(ground_color_path).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        albedo_src = np.array(img_src, dtype=np.float32) / 255.0
    else:
        # Fallback procedural earthy dirt color
        albedo_src = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
        albedo_src[:, :, 0] = 0.38 + 0.08 * noise1
        albedo_src[:, :, 1] = 0.32 + 0.06 * noise1
        albedo_src[:, :, 2] = 0.25 + 0.04 * noise1

    # Base stone/slab texture for crushed edge plinth
    slab_color_path = "textures/slab_0_Color.jpg"
    if os.path.exists(slab_color_path):
        img_slab = Image.open(slab_color_path).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        slab_src = np.array(img_slab, dtype=np.float32) / 255.0
    else:
        slab_src = albedo_src * 0.85

    # Composite Albedo:
    # Inner region has darker damp compacted earth + gravel fragments
    gravel_mask = (noise_cracks > 0.62).astype(np.float32)
    inner_factor = 1.0 - smoothstep(0.15, 0.55, r)
    
    # Damp compacted earth tint (slightly darker & richer)
    soil_tint = np.array([0.72, 0.68, 0.62], dtype=np.float32)
    blended_albedo = albedo_src * (1.0 - inner_factor[:, :, None] * 0.25) * soil_tint
    
    # Sprinkle gravel fragments in inner-to-mid perimeter
    mid_ring = np.clip(1.0 - np.abs(r - 0.42) / 0.22, 0.0, 1.0)
    gravel_weight = gravel_mask * mid_ring * 0.7
    blended_albedo = blended_albedo * (1.0 - gravel_weight[:, :, None]) + slab_src * gravel_weight[:, :, None]

    # Calculate Organic Feathered Alpha:
    # Radius threshold modulated by noise creates organic fingers and splatter
    dist_perturbed = r + (noise1 - 0.5) * 0.22 + (noise2 - 0.5) * 0.10
    # Core (r < 0.45): alpha = 1.0
    # Transition (0.45 <= r <= 0.88): soft fade with noise erosion
    # Edge (r > 0.88): drops cleanly to 0.0
    alpha = 1.0 - smoothstep(0.40, 0.88, dist_perturbed)
    # Extra splatter dots around outer boundary
    splatter = (noise_cracks > 0.75).astype(np.float32) * (1.0 - smoothstep(0.70, 0.96, r)) * 0.45
    alpha = np.clip(alpha + splatter, 0.0, 1.0)
    # Force absolute boundary to 0 to prevent decal quad clipping
    border_fade = 1.0 - smoothstep(0.88, 0.98, r)
    alpha = alpha * border_fade

    albedo_out = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    albedo_out[:, :, 0:3] = np.clip(blended_albedo * 255.0, 0, 255).astype(np.uint8)
    albedo_out[:, :, 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)

    albedo_img = Image.fromarray(albedo_out, "RGBA")
    albedo_path = os.path.join(OUT_DIR, "foundation_contact_albedo.png")
    albedo_img.save(albedo_path, "PNG")
    print(f"Saved: {albedo_path}")

    # 2. PBR Tangent Space Normal Map
    # Load source normal if present
    ground_normal_path = "textures/Ground003_2K-JPG_NormalGL.jpg"
    if not os.path.exists(ground_normal_path):
        ground_normal_path = "Asserts/materials/Ground003_2K-JPG/Ground003_2K-JPG_NormalGL.jpg"

    if os.path.exists(ground_normal_path):
        img_norm = Image.open(ground_normal_path).convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS)
        norm_raw = np.array(img_norm, dtype=np.float32) / 255.0 * 2.0 - 1.0
    else:
        norm_raw = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
        norm_raw[:, :, 2] = 1.0

    # Soil displacement: outward mound inclination around r in [0.35, 0.65]
    # Height profile of mound: bell curve derivative gives slope
    mound_center = 0.48
    mound_width = 0.18
    mound_slope = -(r - mound_center) / (mound_width * mound_width) * np.exp(-((r - mound_center) ** 2) / (2 * mound_width * mound_width))
    mound_slope = np.clip(mound_slope * 0.35, -0.4, 0.4)

    # Convert radial slope to tangent space Nx, Ny
    slope_x = mound_slope * np.cos(angle)
    slope_y = mound_slope * np.sin(angle)

    # Gravel normal pop
    gravel_pop_x = (np.roll(gravel_mask, -1, axis=1) - np.roll(gravel_mask, 1, axis=1)) * 0.4
    gravel_pop_y = (np.roll(gravel_mask, -1, axis=0) - np.roll(gravel_mask, 1, axis=0)) * 0.4

    nx = norm_raw[:, :, 0] * 0.7 + slope_x + gravel_pop_x
    ny = norm_raw[:, :, 1] * 0.7 + slope_y + gravel_pop_y
    nz = np.sqrt(np.clip(1.0 - nx * nx - ny * ny, 0.05, 1.0))

    # Fade normal to neutral flat [0, 0, 1] as alpha fades
    fade_norm = smoothstep(0.0, 0.8, alpha)
    nx = nx * fade_norm
    ny = ny * fade_norm
    nz = nz * fade_norm + (1.0 - fade_norm)
    length = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    nx /= length
    ny /= length
    nz /= length

    normal_out = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    normal_out[:, :, 0] = np.clip((nx * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    normal_out[:, :, 1] = np.clip((ny * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    normal_out[:, :, 2] = np.clip((nz * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    normal_out[:, :, 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)

    normal_img = Image.fromarray(normal_out, "RGBA")
    normal_path = os.path.join(OUT_DIR, "foundation_contact_normal.png")
    normal_img.save(normal_path, "PNG")
    print(f"Saved: {normal_path}")

    # 3. PBR ORM Map (R = Contact AO, G = Roughness, B = Metallic)
    # Contact AO:
    # Deep ambient occlusion under turret core (r < 0.38: AO ~ 0.22)
    # Tight contact shadow ring right at turret base edge (r ~ 0.38: AO drops to 0.18)
    # Gradually opens up outwards (r > 0.40 -> AO ramps up smoothly to 1.0 at r ~ 0.80)
    contact_ring = np.exp(-((r - 0.38) ** 2) / 0.015)
    ao = 0.22 + 0.78 * smoothstep(0.32, 0.75, r)
    ao = np.clip(ao - contact_ring * 0.18, 0.12, 1.0)
    # Blend with micro crack occlusion
    ao = np.clip(ao - (1.0 - noise_cracks) * 0.15 * (1.0 - smoothstep(0.3, 0.7, r)), 0.08, 1.0)

    # Roughness:
    # Soil and crushed rock have high roughness 0.88 - 0.98
    roughness = 0.88 + 0.10 * noise1
    # Gravel pieces slightly sharper roughness 0.75
    roughness = roughness * (1.0 - gravel_weight * 0.2)

    # Metallic:
    # Dirt and rocks have 0.0 metallic
    metallic = np.zeros((SIZE, SIZE), dtype=np.float32)

    orm_out = np.zeros((SIZE, SIZE, 3), dtype=np.uint8)
    orm_out[:, :, 0] = np.clip(ao * 255.0, 0, 255).astype(np.uint8)
    orm_out[:, :, 1] = np.clip(roughness * 255.0, 0, 255).astype(np.uint8)
    orm_out[:, :, 2] = np.clip(metallic * 255.0, 0, 255).astype(np.uint8)

    orm_img = Image.fromarray(orm_out, "RGB")
    orm_path = os.path.join(OUT_DIR, "foundation_contact_orm.png")
    orm_img.save(orm_path, "PNG")
    print(f"Saved: {orm_path}")

    print("PBR Foundation Contact Textures generation COMPLETE!")

if __name__ == "__main__":
    main()
