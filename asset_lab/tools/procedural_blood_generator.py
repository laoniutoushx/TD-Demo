"""Procedural PBR Blood Decal Generator for Godot 4 Forward+
Generates 4 distinct PBR blood spatter variants:
1. heavy_pool (主聚稠血泊 - 重击/倒地/大体型)
2. radial_burst (强力径向爆射 - 暴击/大炮/爆炸)
3. directional_streak (动量定向拖尾 - 射击/击退/移动死亡)
4. droplet_scatter (轻型零星血滴 - 小型单位/流血轻伤)
Outputs: albedo (RGBA with mask), normal (tangent space RGB), orm (R=AO, G=Roughness, B=Metallic)
"""

import os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

def create_normal_map_from_height(height_map: np.ndarray, strength: float = 3.5) -> np.ndarray:
    """Computes tangent space normal map [0..255] from a float height map [0..1]."""
    # Sobel gradients
    gy, gx = np.gradient(height_map)
    gx = gx * strength
    gy = gy * strength
    gz = np.ones_like(height_map)

    # Normalize
    norm = np.sqrt(gx**2 + gy**2 + gz**2)
    norm = np.maximum(norm, 1e-6)
    nx = -gx / norm
    ny = -gy / norm
    nz = gz / norm

    # Map from [-1, 1] to [0, 255]
    r = ((nx * 0.5 + 0.5) * 255).astype(np.uint8)
    g = ((ny * 0.5 + 0.5) * 255).astype(np.uint8)
    b = ((nz * 0.5 + 0.5) * 255).astype(np.uint8)
    return np.stack([r, g, b], axis=-1)

def generate_heavy_pool(size=1024, seed=101):
    np.random.seed(seed)
    canvas = np.zeros((size, size), dtype=np.float32)
    cx, cy = size // 2, size // 2

    # 1. Main cohesive pool metaballs
    metas = [(cx, cy, 150)]
    for _ in range(12):
        ang = np.random.uniform(0, 2 * np.pi)
        dist = np.random.uniform(30, 110)
        r = np.random.uniform(60, 110)
        metas.append((cx + np.cos(ang) * dist, cy + np.sin(ang) * dist, r))

    # 2. Medium peripheral lobes
    for _ in range(25):
        ang = np.random.uniform(0, 2 * np.pi)
        dist = np.random.uniform(110, 220)
        r = np.random.uniform(20, 50)
        metas.append((cx + np.cos(ang) * dist, cy + np.sin(ang) * dist, r))

    # 3. Satellite droplets
    for _ in range(60):
        ang = np.random.uniform(0, 2 * np.pi)
        dist = np.random.uniform(180, 420)
        r = np.random.exponential(8) + 3
        metas.append((cx + np.cos(ang) * dist, cy + np.sin(ang) * dist, r))

    y, x = np.ogrid[:size, :size]
    for mx, my, mr in metas:
        d2 = (x - mx)**2 + (y - my)**2
        canvas += (mr**2) / (d2 + mr**2 * 0.4)

    # Thresholding for fluid meniscus
    density = gaussian_filter(canvas, sigma=1.5)
    mask = np.clip((density - 0.75) / 0.15, 0.0, 1.0)
    
    # Internal height for normal calculation
    height = gaussian_filter(mask * np.clip(density * 0.3, 0.0, 1.0), sigma=2.0)
    return mask, height, "heavy_pool"

def generate_radial_burst(size=1024, seed=202):
    np.random.seed(seed)
    canvas = np.zeros((size, size), dtype=np.float32)
    cx, cy = size // 2, size // 2

    # Compact center
    metas = [(cx, cy, 65)]
    for _ in range(8):
        ang = np.random.uniform(0, 2 * np.pi)
        dist = np.random.uniform(20, 60)
        metas.append((cx + np.cos(ang) * dist, cy + np.sin(ang) * dist, np.random.uniform(25, 45)))

    # Radiating arms / tendrils
    num_arms = 14
    for i in range(num_arms):
        base_ang = (i / num_arms) * 2 * np.pi + np.random.uniform(-0.15, 0.15)
        length = np.random.uniform(220, 440)
        steps = int(length / 15)
        for s in range(steps):
            d = s * 15
            drift = np.random.uniform(-8, 8)
            cur_ang = base_ang + drift * 0.01
            px = cx + np.cos(cur_ang) * d
            py = cy + np.sin(cur_ang) * d
            radius = max(2.5, (1.0 - d / length)**1.2 * 22.0 + np.random.uniform(-2, 2))
            metas.append((px, py, radius))

    # Fine high-velocity droplets
    for _ in range(160):
        ang = np.random.uniform(0, 2 * np.pi)
        dist = np.random.uniform(100, 480)
        r = np.random.exponential(4.5) + 2.0
        metas.append((cx + np.cos(ang) * dist, cy + np.sin(ang) * dist, r))

    y, x = np.ogrid[:size, :size]
    for mx, my, mr in metas:
        d2 = (x - mx)**2 + (y - my)**2
        canvas += (mr**2) / (d2 + mr**2 * 0.35)

    density = gaussian_filter(canvas, sigma=1.2)
    mask = np.clip((density - 0.70) / 0.18, 0.0, 1.0)
    height = gaussian_filter(mask * np.clip(density * 0.4, 0.0, 1.0), sigma=1.5)
    return mask, height, "radial_burst"

def generate_directional_streak(size=1024, seed=303):
    np.random.seed(seed)
    canvas = np.zeros((size, size), dtype=np.float32)
    cx, cy = size // 2, size // 3 # Impact head placed at upper-middle

    # 1. Impact head
    metas = [(cx, cy, 75)]
    for _ in range(6):
        metas.append((cx + np.random.uniform(-40, 40), cy + np.random.uniform(-30, 30), np.random.uniform(30, 55)))

    # 2. Main forward thrust streaks along +Y (downward in image space)
    num_streaks = 10
    for _ in range(num_streaks):
        spread_x = np.random.normal(0, 35)
        streak_len = np.random.uniform(250, 550)
        for d in np.linspace(20, streak_len, 25):
            px = cx + spread_x * (1.0 + (d / streak_len) * 0.8) + np.random.uniform(-8, 8)
            py = cy + d
            r = max(2.5, (1.0 - d / streak_len)**0.9 * 28.0 + np.random.uniform(-2, 2))
            metas.append((px, py, r))

    # 3. Elongated spray droplets
    for _ in range(120):
        spread_x = np.random.normal(0, 80)
        d_y = np.random.uniform(50, 600)
        r = np.random.exponential(5) + 2.0
        metas.append((cx + spread_x, cy + d_y, r))

    y, x = np.ogrid[:size, :size]
    for mx, my, mr in metas:
        # Slightly stretch along Y axis
        d2 = (x - mx)**2 + ((y - my) / 1.3)**2
        canvas += (mr**2) / (d2 + mr**2 * 0.38)

    density = gaussian_filter(canvas, sigma=1.3)
    mask = np.clip((density - 0.72) / 0.16, 0.0, 1.0)
    height = gaussian_filter(mask * np.clip(density * 0.35, 0.0, 1.0), sigma=1.8)
    return mask, height, "directional_streak"

def generate_droplet_scatter(size=1024, seed=404):
    np.random.seed(seed)
    canvas = np.zeros((size, size), dtype=np.float32)
    cx, cy = size // 2, size // 2

    # 4 distinct micro-clusters
    sub_centers = [
        (cx - 100, cy - 80),
        (cx + 120, cy - 60),
        (cx - 40, cy + 120),
        (cx + 80, cy + 90),
        (cx, cy)
    ]
    metas = []
    for scx, scy in sub_centers:
        for _ in range(25):
            ang = np.random.uniform(0, 2 * np.pi)
            dist = np.random.exponential(45)
            r = np.random.exponential(7.0) + 2.5
            metas.append((scx + np.cos(ang) * dist, scy + np.sin(ang) * dist, r))

    # Random background spatter
    for _ in range(90):
        ang = np.random.uniform(0, 2 * np.pi)
        dist = np.random.uniform(40, 420)
        r = np.random.exponential(4.0) + 1.8
        metas.append((cx + np.cos(ang) * dist, cy + np.sin(ang) * dist, r))

    y, x = np.ogrid[:size, :size]
    for mx, my, mr in metas:
        d2 = (x - mx)**2 + (y - my)**2
        canvas += (mr**2) / (d2 + mr**2 * 0.4)

    density = gaussian_filter(canvas, sigma=1.0)
    mask = np.clip((density - 0.75) / 0.18, 0.0, 1.0)
    height = gaussian_filter(mask * np.clip(density * 0.4, 0.0, 1.0), sigma=1.2)
    return mask, height, "droplet_scatter"

def build_pbr_set(mask: np.ndarray, height: np.ndarray, variant_name: str, out_dir: str):
    os.makedirs(out_dir, exist_ok=True)
    size = mask.shape[0]

    # 1. Albedo (RGBA)
    # Color tuning: Realistic deep dark venous blood (#680504 to #8A0C0B)
    base_color_core = np.array([105, 7, 6], dtype=np.float32)
    base_color_edge = np.array([145, 14, 12], dtype=np.float32)
    
    # Meniscus edge interpolation based on height/density
    rgb = np.zeros((size, size, 3), dtype=np.uint8)
    for c in range(3):
        col = base_color_core[c] * height + base_color_edge[c] * (1.0 - height)
        rgb[..., c] = np.clip(col, 0, 255).astype(np.uint8)

    alpha = (mask * 255).astype(np.uint8)
    albedo_img = Image.fromarray(np.dstack([rgb, alpha]), mode='RGBA')
    albedo_path = os.path.join(out_dir, f"{variant_name}_albedo.png")
    albedo_img.save(albedo_path, format="PNG")

    # 2. Normal (RGB Tangent space)
    normal_map = create_normal_map_from_height(height, strength=4.5)
    # Flat normal (128, 128, 255) outside mask
    outside = mask < 0.01
    normal_map[outside] = [128, 128, 255]
    normal_img = Image.fromarray(normal_map, mode='RGB')
    normal_path = os.path.join(out_dir, f"{variant_name}_normal.png")
    normal_img.save(normal_path, format="PNG")

    # 3. ORM (R=AO, G=Roughness, B=Metallic)
    # Liquid blood is glossy in center (roughness ~0.12 = 30), edges slightly drier (roughness ~0.35 = 90)
    ao = np.clip(255 - (1.0 - height) * 35, 180, 255).astype(np.uint8)
    roughness = (32 + (1.0 - height) * 58).astype(np.uint8)
    metallic = np.zeros((size, size), dtype=np.uint8)
    orm_map = np.stack([ao, roughness, metallic], axis=-1)
    orm_img = Image.fromarray(orm_map, mode='RGB')
    orm_path = os.path.join(out_dir, f"{variant_name}_orm.png")
    orm_img.save(orm_path, format="PNG")

    print(f"[{variant_name}] Generated PBR set in {out_dir}")
    print(f"  - Albedo: {albedo_path} (coverage: {np.mean(mask > 0.05)*100:.1f}%)")
    print(f"  - Normal: {normal_path}")
    print(f"  - ORM:    {orm_path}")

def main():
    base_dir = "Asserts/materials/blood_variants"
    generators = [
        generate_heavy_pool,
        generate_radial_burst,
        generate_directional_streak,
        generate_droplet_scatter
    ]
    for gen in generators:
        mask, height, name = gen(size=1024)
        out_path = os.path.join(base_dir, name)
        build_pbr_set(mask, height, name, out_path)

if __name__ == "__main__":
    main()
