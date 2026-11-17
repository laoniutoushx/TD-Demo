from pathlib import Path
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(r"H:\Godot\Projects\TD-Demo")
BRAIN = Path(r"C:\Users\SuzumiyaHaruhi\.gemini\antigravity-cli\brain\e8f67f83-3da5-4e70-8e83-3a87e553aba5")
KIT1_PATH = BRAIN / "ui_concept_a_panel_kit_1794756801603.jpg"
KIT2_PATH = BRAIN / "ui_concept_a_header_slot_kit_1794756801523.jpg"
OUT_DIR = ROOT / "UI" / "theme" / "textures"


def dewhite_flood(
    rgb: np.ndarray,
    extra_seeds: list[tuple[int, int]] | None = None,
    white_min: int = 224,
    sat_max: int = 24,
) -> Image.Image:
    """Remove solid white background via edge+seed flood-fill with AA de-fringing."""
    h, w, _ = rgb.shape
    mn = rgb.min(axis=2)
    mx = rgb.max(axis=2)
    is_bg_cand = (mn >= white_min) & ((mx - mn) <= sat_max)

    visited = np.zeros((h, w), dtype=bool)
    q = deque()

    for x in range(w):
        if is_bg_cand[0, x]:
            visited[0, x] = True
            q.append((0, x))
        if is_bg_cand[h - 1, x] and not visited[h - 1, x]:
            visited[h - 1, x] = True
            q.append((h - 1, x))
    for y in range(1, h - 1):
        if is_bg_cand[y, 0] and not visited[y, 0]:
            visited[y, 0] = True
            q.append((y, 0))
        if is_bg_cand[y, w - 1] and not visited[y, w - 1]:
            visited[y, w - 1] = True
            q.append((y, w - 1))

    if extra_seeds:
        for sx, sy in extra_seeds:
            if 0 <= sx < w and 0 <= sy < h and is_bg_cand[sy, sx] and not visited[sy, sx]:
                visited[sy, sx] = True
                q.append((sy, sx))

    while q:
        cy, cx = q.popleft()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and is_bg_cand[ny, nx]:
                visited[ny, nx] = True
                q.append((ny, nx))

    alpha = (~visited).astype(np.float32)

    # Anti-alias 1.5px transition ring & un-premultiply white matte
    dist_to_bg = ndimage.distance_transform_edt(~visited)
    ring = (~visited) & (dist_to_bg <= 1.8)
    lum = rgb.mean(axis=2) / 255.0
    sat = (mx - mn) / 255.0

    # Near-white low-sat edge pixels smoothly fade alpha and un-matte color against #FFFFFF
    fade = np.clip((0.96 - lum) / 0.20 + sat * 2.5, 0.0, 1.0)
    alpha[ring] = np.minimum(alpha[ring], np.clip(fade[ring] * (dist_to_bg[ring] / 1.4), 0.0, 1.0))

    a3 = np.clip(alpha[..., None], 0.0, 1.0)
    rgb_f = rgb.astype(np.float32)
    denom = np.maximum(a3, 0.08)
    unmatted = np.where(
        (a3 > 0.0) & (a3 < 0.999) & (lum[..., None] > 0.65),
        np.clip((rgb_f - (1.0 - a3) * 255.0) / denom, 0.0, 255.0),
        rgb_f,
    )
    rgba = np.dstack([np.clip(unmatted, 0, 255).astype(np.uint8), (alpha * 255.0 + 0.5).astype(np.uint8)])
    return Image.fromarray(rgba, mode="RGBA")


def strip_enclosed_white(rgba_img: Image.Image, white_min: int = 205, sat_max: int = 28, seed_y_min: int = 0) -> Image.Image:
    """Clear enclosed near-white neutral holes (such as gaps inside tangled green vine loops)."""
    arr = np.array(rgba_img, dtype=np.float32)
    rgb = arr[..., :3]
    mn = rgb.min(axis=2)
    mx = rgb.max(axis=2)
    yy, _ = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    holes = (yy >= seed_y_min) & (mn >= white_min) & ((mx - mn) <= sat_max) & (arr[..., 3] > 0)
    # Feather 1px neighbor ring around removed white holes to strip bright fringes
    dil = ndimage.binary_dilation(holes, iterations=1)
    edge = dil & (~holes)
    arr[holes, 3] = 0.0
    lum = rgb.mean(axis=2)
    arr[edge & (lum > 180), 3] *= 0.35
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def crop_kit1(kit1: np.ndarray) -> None:
    # 1. stone_panel_9slice.png (512x512) from Top-Left weathered limestone slab
    slab_rgb = kit1[30:482, 30:482]
    slab_rgba = dewhite_flood(slab_rgb, white_min=228, sat_max=22)
    # Trim to opaque bbox then fit cleanly into 512x512
    bbox = slab_rgba.getbbox()
    slab_cropped = slab_rgba.crop(bbox).resize((512, 512), Image.Resampling.LANCZOS)
    # Keep corner moss neatly within the 56px 9-slice margin so horizontal/vertical stretch zone is pure limestone+bronze
    arr = np.array(slab_cropped, dtype=np.float32)
    yy, xx = np.mgrid[0:512, 0:512]
    in_stretch_band = ((xx >= 54) & (xx <= 457)) | ((yy >= 54) & (yy <= 457))
    in_edge_trim = in_stretch_band & (~((xx >= 54) & (xx <= 457) & (yy >= 54) & (yy <= 457)))
    # Replace greenish moss outliers inside the 9-slice stretch strips with median adjacent stone edge slice
    is_green = (arr[..., 1] > arr[..., 0] + 10) & (arr[..., 1] > arr[..., 2] + 10)
    replace_mask = in_edge_trim & is_green
    if replace_mask.any():
        clean_row_col = arr[256, :, :3]
        for y_idx in range(512):
            m = replace_mask[y_idx]
            if m.any():
                # Interpolate along edge strip from nearest stone pixel at x=256 or y=256
                if 54 <= y_idx <= 457:
                    arr[y_idx, m, :3] = arr[256, m, :3]
                else:
                    arr[y_idx, m, :3] = arr[y_idx, 256, :3]
    # Slightly darken center interior (~14%) so ivory & gold text pops crisply (WCAG >= 4.5:1)
    inner = (np.minimum(np.minimum(xx, 511 - xx), np.minimum(yy, 511 - yy)) / 48.0).clip(0.0, 1.0)
    arr[..., :3] *= (1.0 - 0.14 * inner[..., None])
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(OUT_DIR / "stone_panel_9slice.png")

    # 2. stone_recessed_9slice.png & stone_recessed_moss_9slice.png (256x256, margin=20)
    # Use painted weathered limestone center texture from slab inside a crisp slim bronze rim
    tex_src = np.array(slab_cropped, dtype=np.float32)[80:432, 80:432, :3]
    tex_256 = np.array(Image.fromarray(tex_src.astype(np.uint8)).resize((256, 256), Image.Resampling.BILINEAR), dtype=np.float32)
    # Deep charcoal limestone well + thin chamfered bronze outer rim matching Concept Board A sub-panels
    def make_recessed(moss_rim: bool) -> Image.Image:
        out = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        y, x = np.mgrid[0:256, 0:256]
        chamfer = 10.0
        dx = np.maximum(0.0 - x, x - 255.0)
        dy = np.maximum(0.0 - y, y - 255.0)
        edge_dist = np.minimum(np.minimum(x, 255.0 - x), np.minimum(y, 255.0 - y))
        diag_dist = np.minimum(
            np.minimum(x + y - chamfer, (255 - x) + y - chamfer),
            np.minimum(x + (255 - y) - chamfer, (255 - x) + (255 - y) - chamfer),
        ) * 0.7071
        sdf = np.minimum(edge_dist, diag_dist)  # >0 inside, 0 at perimeter

        a = np.clip((sdf + 0.8) / 1.4, 0.0, 1.0)
        # Interior dark slate stone
        well = tex_256 * 0.44 + np.array([6.0, 8.0, 7.0])
        # Subtle inner ambient occlusion vignette along perimeter
        ao = np.clip((sdf - 5.0) / 16.0, 0.45, 1.0)
        well *= ao[..., None]

        # Slim bronze frame around sdf [1.2 .. 5.2]
        is_outer_dark = sdf <= 1.2
        is_bronze = (sdf > 1.2) & (sdf <= 4.2)
        is_inner_glow = (sdf > 4.2) & (sdf <= 6.2)

        col = well.copy()
        # Directional bronze bevel shading (warm top/left highlight, darker bottom/right)
        bevel_shade = np.clip(1.05 - ((x + y) / 510.0) * 0.38, 0.65, 1.12)
        bronze_rgb = np.array([138.0, 114.0, 72.0])[None, None, :] * bevel_shade[..., None]
        if moss_rim:
            bronze_rgb = bronze_rgb * 0.65 + np.array([92.0, 168.0, 52.0])[None, None, :] * 0.35

        col = np.where(is_outer_dark[..., None], np.array([18.0, 19.0, 17.0]), col)
        col = np.where(is_bronze[..., None], bronze_rgb, col)
        if moss_rim:
            glow_w = np.clip(1.0 - np.abs(sdf - 4.8) / 1.8, 0.0, 1.0)
            col = np.where(is_inner_glow[..., None], col * (1.0 - 0.5 * glow_w[..., None]) + np.array([104.0, 192.0, 56.0]) * (0.5 * glow_w[..., None]), col)
        else:
            col = np.where(is_inner_glow[..., None], col * 0.72, col)

        rgba = np.dstack([np.clip(col, 0, 255).astype(np.uint8), (a * 255.0 + 0.5).astype(np.uint8)])
        return Image.fromarray(rgba, "RGBA")

    make_recessed(False).save(OUT_DIR / "stone_recessed_9slice.png")
    make_recessed(True).save(OUT_DIR / "stone_recessed_moss_9slice.png")

    # 3. Four Bronze Corner Brackets (96x96 RGBA) from Kit 1 Bottom-Left
    brackets = {
        "bronze_corner_tl.png": kit1[524:754, 14:244],
        "bronze_corner_tr.png": kit1[524:754, 270:500],
        "bronze_corner_bl.png": kit1[782:1012, 14:244],
        "bronze_corner_br.png": kit1[782:1012, 270:500],
    }
    for fname, sub in brackets.items():
        im = dewhite_flood(sub, white_min=226, sat_max=22)
        im = im.crop(im.getbbox()).resize((96, 96), Image.Resampling.LANCZOS)
        im.save(OUT_DIR / fname)

    # 4. Corner Moss Tufts (96x96 RGBA) from Kit 1 Bottom-Right
    moss_tr = dewhite_flood(kit1[520:730, 804:1015], white_min=224, sat_max=24)
    moss_tr = moss_tr.crop(moss_tr.getbbox()).resize((96, 96), Image.Resampling.LANCZOS)
    moss_bl = dewhite_flood(kit1[804:1016, 520:732], white_min=224, sat_max=24)
    moss_bl = moss_bl.crop(moss_bl.getbbox()).resize((96, 96), Image.Resampling.LANCZOS)
    moss_br = dewhite_flood(kit1[804:1016, 804:1015], white_min=224, sat_max=24)
    moss_br = moss_br.crop(moss_br.getbbox()).resize((96, 96), Image.Resampling.LANCZOS)
    moss_tl = moss_tr.transpose(Image.Transpose.FLIP_LEFT_RIGHT)

    moss_tl.save(OUT_DIR / "moss_corner.png")
    moss_tl.save(OUT_DIR / "moss_corner_tl.png")
    moss_tr.save(OUT_DIR / "moss_corner_tr.png")
    moss_bl.save(OUT_DIR / "moss_corner_bl.png")
    moss_br.save(OUT_DIR / "moss_corner_br.png")

    # 5. Circular Hero Medallion Frame (256x256 RGBA, hollow center centered at exact (128,128))
    med_rgb = kit1[524:820, 508:866]
    mh, mw, _ = med_rgb.shape
    # Detect hollow white interior region near center
    mn = med_rgb.min(axis=2)
    mx = med_rgb.max(axis=2)
    bg_mask = (mn >= 224) & ((mx - mn) <= 22)
    lbl, _ = ndimage.label(bg_mask)
    hole_lbl = lbl[mh // 2, mw // 2]
    hy, hx = np.where(lbl == hole_lbl)
    hcx = float(hx.mean())
    hcy = float(hy.mean())
    r_in = float(np.sqrt(((hx - hcx) ** 2 + (hy - hcy) ** 2).max()))
    med_rgba = dewhite_flood(med_rgb, extra_seeds=[(int(hcx), int(hcy))], white_min=224, sat_max=22)
    # Keep only the single largest connected opaque island (strips stray corner leaf fragments from neighbor sprites)
    med_arr = np.array(med_rgba)
    comp_lbl, num_c = ndimage.label(med_arr[..., 3] > 20)
    if num_c > 1:
        sizes = ndimage.sum(med_arr[..., 3] > 20, comp_lbl, range(1, num_c + 1))
        keep_id = int(np.argmax(sizes)) + 1
        med_arr[comp_lbl != keep_id, 3] = 0
        med_rgba = Image.fromarray(med_arr, "RGBA")

    # Rescale so inner white hole has radius ~80px (diameter 160 / 256 = 62.5%) centered at (128, 128)
    target_r_in = 80.0
    scale = target_r_in / r_in
    new_w = max(1, int(round(mw * scale)))
    new_h = max(1, int(round(mh * scale)))
    med_scaled = med_rgba.resize((new_w, new_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    paste_x = int(round(128.0 - hcx * scale))
    paste_y = int(round(128.0 - hcy * scale))
    canvas.paste(med_scaled, (paste_x, paste_y), med_scaled)
    canvas.save(OUT_DIR / "hero_medallion_frame.png")
    print(f"HERO_MEDALLION_INNER_RATIO={target_r_in * 2 / 256.0:.3f} hole_px={r_in:.1f}")


def crop_kit2(kit2: np.ndarray) -> None:
    # 1. Wave plaque (512x112 RGBA) — clean out Resource plaque top leaf pixels
    wave_src = kit2[44:270, 22:1002].copy()
    # Mask out Resource plaque top-right leaf tip around y>=252-44=208, x in [850..910]
    wave_src[208:, 840:920] = 255
    # Also gently fade wave's far-left bottommost hanging tendril tip below y=209 so bbox stays tight
    wave_src[209:, 50:80] = 255
    wave_rgba = dewhite_flood(wave_src, white_min=224, sat_max=22)
    wave_rgba = strip_enclosed_white(wave_rgba, white_min=198, sat_max=30)
    wave_rgba = wave_rgba.crop(wave_rgba.getbbox())
    # Fit proportionally inside 512x112 centered
    w_im = wave_rgba.resize((512, 112), Image.Resampling.LANCZOS)
    w_im.save(OUT_DIR / "stone_wave_plaque.png")

    # 2. Resource plaque (460x96 RGBA) — clean out Wave plaque left vine tip
    res_src = kit2[252:416, 70:954].copy()
    # Remove Wave vine tip at top-left x < 28 (orig x < 98), y < 18 (orig y < 270)
    res_src[:20, :32] = 255
    res_rgba = dewhite_flood(res_src, white_min=224, sat_max=22)
    res_rgba = res_rgba.crop(res_rgba.getbbox())
    r_im = res_rgba.resize((460, 96), Image.Resampling.LANCZOS)
    r_im.save(OUT_DIR / "stone_resource_plaque.png")

    # 3. Seamless tileable Top Vine Trim (1024x88 RGBA, natural leaf aspect ratio)
    vine_src = kit2[780:958, 28:996].copy()
    vine_rgba = dewhite_flood(vine_src, white_min=222, sat_max=22)
    vine_rgba = strip_enclosed_white(vine_rgba, white_min=192, sat_max=34)
    vine_rgba = vine_rgba.crop(vine_rgba.getbbox())
    # Resize preserving natural ~968x160 -> ~1024x92 proportions without flat squashing
    target_w = 1024
    target_h = 88
    vine_scaled = np.array(vine_rgba.resize((target_w + 64, target_h), Image.Resampling.LANCZOS), dtype=np.float32)
    # Cross-fade 64px overlap between left end and right end for zero visible seam when tiled
    blend_w = 64
    t = np.linspace(0.0, 1.0, blend_w, dtype=np.float32)[None, :, None]
    left_seam = vine_scaled[:, :blend_w, :]
    right_seam = vine_scaled[:, -blend_w:, :]
    seam = right_seam * (1.0 - t) + left_seam * t
    tile_arr = vine_scaled[:, :target_w, :].copy()
    tile_arr[:, :blend_w, :] = seam
    Image.fromarray(np.clip(tile_arr, 0, 255).astype(np.uint8), "RGBA").save(OUT_DIR / "top_vine_trim.png")

    # 4. Three Identical-Silhouette Slots (128x128 RGBA) + Aperture Mask (128x128 RGBA)
    norm_raw = dewhite_flood(kit2[470:733, 72:338], white_min=224, sat_max=22)
    norm_crop = norm_raw.crop(norm_raw.getbbox()).resize((128, 128), Image.Resampling.LANCZOS)
    nb = norm_raw.getbbox()  # Measure exact width/height of clean slot

    # Build 4-way symmetric outer octagonal silhouette alpha from norm_crop
    na = np.array(norm_crop, dtype=np.float32)[..., 3]
    sym_alpha = (na + na[:, ::-1] + na[::-1, :] + na[::-1, ::-1]) * 0.25
    # Sharpen slightly to remove any soft outer fluff while preserving smooth 1px AA
    sym_alpha = np.clip((sym_alpha - 24.0) * (255.0 / 215.0), 0.0, 255.0).astype(np.uint8)

    # Align active slot strictly to bronze rim bounding box (ignoring protruding green glow!)
    act_sub = kit2[475:728, 384:640]
    act_im = Image.fromarray(act_sub, "RGB").resize((128, 128), Image.Resampling.LANCZOS)
    act_rgb = np.array(act_im, dtype=np.float32)

    # Middle-Right empty item slot (boost moss-green inner hairline subtly for Concept A parity)
    emp_raw = dewhite_flood(kit2[470:733, 686:952], white_min=224, sat_max=22)
    emp_crop = emp_raw.crop(emp_raw.getbbox()).resize((128, 128), Image.Resampling.LANCZOS)
    emp_f = np.array(emp_crop, dtype=np.float32)[..., :3]
    is_moss_line = (emp_f[..., 1] > emp_f[..., 0] + 6.0) & (emp_f[..., 1] > emp_f[..., 2] + 6.0)
    emp_f[is_moss_line, 1] = np.clip(emp_f[is_moss_line, 1] + 24.0, 0, 255)
    emp_f[is_moss_line, 0] = np.clip(emp_f[is_moss_line, 0] + 8.0, 0, 255)
    emp_rgb = emp_f.astype(np.uint8)
    norm_rgb = np.array(norm_crop, dtype=np.uint8)[..., :3]

    # Blend outer 3.5px of slot_active back to norm_rgb so exterior bronze rim stays crisp & free of outer green spill
    outer_dist = ndimage.distance_transform_edt(sym_alpha > 128)
    rim_mix = np.clip((outer_dist - 1.5) / 3.0, 0.0, 1.0)[..., None]
    act_clean_rgb = np.clip(norm_rgb.astype(np.float32) * (1.0 - rim_mix) + act_rgb * rim_mix, 0, 255).astype(np.uint8)

    # Enforce IDENTICAL alpha across all 3 slots (alpha_diff == 0)
    Image.fromarray(np.dstack([norm_rgb, sym_alpha]), "RGBA").save(OUT_DIR / "slot_normal.png")
    Image.fromarray(np.dstack([act_clean_rgb, sym_alpha]), "RGBA").save(OUT_DIR / "slot_active.png")
    Image.fromarray(np.dstack([emp_rgb, sym_alpha]), "RGBA").save(OUT_DIR / "slot_empty_item.png")

    # Verify zero alpha difference
    an = np.array(Image.open(OUT_DIR / "slot_normal.png"))[..., 3]
    aa = np.array(Image.open(OUT_DIR / "slot_active.png"))[..., 3]
    ae = np.array(Image.open(OUT_DIR / "slot_empty_item.png"))[..., 3]
    assert int(np.abs(an.astype(int) - aa.astype(int)).max()) == 0, "slot_normal vs slot_active alpha mismatch!"
    assert int(np.abs(an.astype(int) - ae.astype(int)).max()) == 0, "slot_normal vs slot_empty_item alpha mismatch!"

    # Build matching slot_aperture_mask.png (128x128 RGBA) seated 1px inside bronze inner bezel
    # In 128x128, bronze rim is ~7.5px thick; chamfered corner cuts at ~13px from corners.
    y, x = np.mgrid[0:128, 0:128]
    inset = 7.5
    corner_cut = 13.0
    dx = np.minimum(x - inset, 127.0 - inset - x)
    dy = np.minimum(y - inset, 127.0 - inset - y)
    diag = np.minimum(
        np.minimum((x + y) - (inset * 2.0 + corner_cut), (127.0 - x + y) - (inset * 2.0 + corner_cut)),
        np.minimum((x + 127.0 - y) - (inset * 2.0 + corner_cut), (127.0 - x + 127.0 - y) - (inset * 2.0 + corner_cut)),
    ) * 0.7071
    sdf_in = np.minimum(np.minimum(dx, dy), diag)
    mask_a = np.clip((sdf_in + 0.6) / 1.2, 0.0, 1.0)
    mask_rgba = np.zeros((128, 128, 4), dtype=np.uint8)
    mask_rgba[..., :3] = 255
    mask_rgba[..., 3] = (mask_a * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(mask_rgba, "RGBA").save(OUT_DIR / "slot_aperture_mask.png")
    print(f"SLOTS_VERIFIED alpha_diff=0 norm_bbox={nb}")


def clean_currency_icons() -> None:
    # Clean coin white halo fringes & resize wood cleanly into UI/theme/textures/
    coin_path = ROOT / "Asserts" / "resources" / "demo_ui" / "UI" / "2_爱给网_aigei_com.png"
    wood_path = ROOT / "Asserts" / "resources" / "demo_ui" / "UI" / "木支柱4(wood_prop4)_爱给网_aigei_com.png"

    coin = Image.open(coin_path).convert("RGBA")
    arr = np.array(coin, dtype=np.float32)
    # Remove outer partial white/sparkle halo where alpha < 180 & near white
    lum = arr[..., :3].mean(axis=2)
    sat = arr[..., :3].max(axis=2) - arr[..., :3].min(axis=2)
    fringe = (arr[..., 3] < 210) & (lum > 180) & (sat < 45)
    arr[fringe, 3] = 0.0
    # Slight erode 1px alpha silhouette to strip crisp white edge pixel ring
    alpha_mask = arr[..., 3] > 25
    eroded = ndimage.binary_erosion(alpha_mask, iterations=1)
    edge = alpha_mask & (~eroded)
    white_edge = edge & (lum > 170)
    arr[white_edge, 3] *= 0.25
    clean_coin = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    cb = clean_coin.getbbox()
    clean_coin.crop(cb).resize((64, 64), Image.Resampling.LANCZOS).save(OUT_DIR / "icon_coin.png")

    wood = Image.open(wood_path).convert("RGBA")
    wb = wood.getbbox()
    wood.crop(wb).resize((64, 64), Image.Resampling.LANCZOS).save(OUT_DIR / "icon_wood.png")
    print("CURRENCY_ICONS_CLEANED")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    kit1 = np.array(Image.open(KIT1_PATH).convert("RGB"))
    kit2 = np.array(Image.open(KIT2_PATH).convert("RGB"))
    crop_kit1(kit1)
    crop_kit2(kit2)
    clean_currency_icons()
    print("BUILD_CONCEPT_A_ASSETS_OK")


if __name__ == "__main__":
    main()
