#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate Colored NutNotes Logo & Installer Artwork
- Colors the acorn logo according to specifications:
  - Outline/Contour: Deep Chestnut Brown (#5A341C / RGB: 90, 52, 28)
  - Cap & Stem interior: Same Brown (#5A341C / RGB: 90, 52, 28)
  - Nut interior: Warm Golden Caramel (#D48E4E / RGB: 212, 142, 78)
  - Handles the gaps in the stroke boundary so caramel fill does not leak
- Generates:
  - assets/acorn.png (512x512 RGBA)
  - assets/acorn_colored.png (512x512 RGBA)
  - Setup/assets/app_icon.ico (Windows multi-resolution icon)
  - Setup/assets/wizard_small.bmp (55x55 24-bit BMP for Inno Setup header)
  - Setup/assets/wizard_large.bmp (164x314 24-bit BMP for Inno Setup welcome/finish page)
  - Setup/assets/nutnotes_toolbar.png (REAPER toolbar button icon)
"""

import os
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

def generate_colored_acorn():
    src_path = 'examples/acorn_3364582.png'
    if not os.path.exists(src_path):
        raise FileNotFoundError(f"Source file not found: {src_path}")

    orig = Image.open(src_path).convert('RGBA')
    arr = np.array(orig)
    orig_alpha = arr[:, :, 3].astype(float) / 255.0

    # 1. Build boundary mask with closed gaps for flood-fill segmentation
    bridge_img = Image.fromarray((arr[:, :, 3] > 40).astype(np.uint8) * 255)
    draw = ImageDraw.Draw(bridge_img)
    # Gap 1: Cap right side
    draw.line([(442, 82), (474, 87)], fill=255, width=14)
    # Gap 2: Nut right side
    draw.line([(448, 338), (428, 359)], fill=255, width=18)
    # Gap 3: Nut bottom-left side
    draw.line([(114, 452), (140, 464)], fill=255, width=18)
    # Gap 4: Left cap / body division bridge across the left acorn
    draw.line([(35, 275), (222, 275)], fill=255, width=10)

    bridged_stroke = np.array(bridge_img) > 128
    h, w = bridged_stroke.shape

    # 2. Flood-fill from borders to identify outside background
    outside = np.zeros_like(bridged_stroke)
    q = deque()
    for x in range(w):
        if not bridged_stroke[0, x]: q.append((0, x)); outside[0, x] = True
        if not bridged_stroke[h-1, x]: q.append((h-1, x)); outside[h-1, x] = True
    for y in range(h):
        if not bridged_stroke[y, 0]: q.append((y, 0)); outside[y, 0] = True
        if not bridged_stroke[y, w-1]: q.append((y, w-1)); outside[y, w-1] = True

    while q:
        cy, cx = q.popleft()
        for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w:
                if not bridged_stroke[ny, nx] and not outside[ny, nx]:
                    outside[ny, nx] = True
                    q.append((ny, nx))

    enclosed = (~bridged_stroke) & (~outside)

    # 3. Label enclosed connected components
    comp_map = np.zeros((h, w), dtype=int)
    cid = 0
    for y in range(h):
        for x in range(w):
            if enclosed[y, x] and comp_map[y, x] == 0:
                cid += 1
                cq = deque([(y, x)])
                comp_map[y, x] = cid
                while cq:
                    cy, cx = cq.popleft()
                    for dy, dx in [(-1,0),(1,0),(0,-1),(0,1)]:
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w:
                            if enclosed[ny, nx] and comp_map[ny, nx] == 0:
                                comp_map[ny, nx] = cid
                                cq.append((ny, nx))

    # Definition of regions:
    # 1. Stems: Comp 1 (main right stem) AND Comp 4 (left stem loop)
    stems_mask = (comp_map == 1) | (comp_map == 4)

    # 2. Caps: Comp 2 (main right cap) AND left acorn cap (upper part of Comp 3, y <= 280, x < 235)
    c3 = (comp_map == 3)
    y_grid, x_grid = np.indices((h, w))
    left_cap_mask = c3 & (y_grid <= 280) & (x_grid < 235)
    caps_mask = (comp_map == 2) | left_cap_mask

    # 3. Nuts: Comp 6 (left nut body), main right nut in c3, Comp 5 (right nut highlight)
    main_nut_mask = c3 & (~left_cap_mask)
    nuts_mask = (comp_map == 6) | main_nut_mask | (comp_map == 5)

    def expand_mask(m, radius=4):
        img_m = Image.fromarray(m.astype(np.uint8) * 255)
        img_m = img_m.filter(ImageFilter.MaxFilter(radius))
        return np.array(img_m) > 128

    # Dilation under strokes to prevent hairline anti-aliasing gaps
    stems_expanded = expand_mask(stems_mask, 5)
    caps_expanded = expand_mask(caps_mask, 5)
    nuts_expanded = expand_mask(nuts_mask, 5)

    # 4. Color Palette
    # Contour: even darker, almost black (deep warm espresso)
    CONTOUR_COLOR = np.array([28, 16, 8], dtype=float)
    # Stems (both right and left acorn stems): in contour color (almost black)
    STEM_COLOR = CONTOUR_COLOR
    # Caps (both right and left acorn caps): preserved rich chestnut brown
    CAP_COLOR = np.array([90, 52, 28], dtype=float)
    # Nuts interior (both right and left acorn bodies): warm golden caramel
    CARAMEL_COLOR = np.array([212, 142, 78], dtype=float)

    out_rgba = np.zeros((h, w, 4), dtype=float)

    # 1. Fill nuts interior (caramel)
    for c in range(3):
        out_rgba[nuts_expanded, c] = CARAMEL_COLOR[c]
    out_rgba[nuts_expanded, 3] = 255.0

    # 2. Fill caps interior (both right and left caps in cap brown)
    for c in range(3):
        out_rgba[caps_expanded, c] = CAP_COLOR[c]
    out_rgba[caps_expanded, 3] = 255.0

    # 3. Fill stems interior (both right and left stems in contour color)
    for c in range(3):
        out_rgba[stems_expanded, c] = STEM_COLOR[c]
    out_rgba[stems_expanded, 3] = 255.0

    # 4. Composite stroke on top with original anti-aliasing (in CONTOUR_COLOR)
    for y in range(h):
        for x in range(w):
            a = orig_alpha[y, x]
            if a > 0:
                bg_a = out_rgba[y, x, 3] / 255.0
                final_a = a + bg_a * (1.0 - a)
                if final_a > 0:
                    for c in range(3):
                        out_rgba[y, x, c] = (CONTOUR_COLOR[c] * a + out_rgba[y, x, c] * bg_a * (1.0 - a)) / final_a
                    out_rgba[y, x, 3] = final_a * 255.0

    colored_img = Image.fromarray(np.clip(out_rgba, 0, 255).astype(np.uint8), mode='RGBA')
    return colored_img

def main():
    user_icon_path = os.path.join('Setup', 'assets', 'app_icon.png')
    if os.path.exists(user_icon_path):
        print(f"Loading custom user icon from: {user_icon_path}")
        logo = Image.open(user_icon_path).convert('RGBA')
    else:
        print("Generating colored acorn logo...")
        logo = generate_colored_acorn()

    os.makedirs('assets', exist_ok=True)
    os.makedirs('Setup/assets', exist_ok=True)

    # 1. Colored artwork for Installer & branding
    logo_512 = logo.resize((512, 512), Image.Resampling.LANCZOS)
    logo_512.save('assets/acorn_colored.png', 'PNG')
    print("Saved assets/acorn_colored.png (512x512 colored)")

    # 2. In-App Contour Acorn (for watermark in main window & overlay)
    contour_src = 'Setup/assets/acorn.png'
    if not os.path.exists(contour_src):
        contour_src = 'examples/acorn_3364582.png'
    c_img = Image.open(contour_src).convert('RGBA')
    alpha_c = c_img.split()[3]
    # Pure white RGB with original contour alpha so ReaImGui can tint it with col_acorn
    white_contour = Image.merge('RGBA', (
        Image.new('L', c_img.size, 255),
        Image.new('L', c_img.size, 255),
        Image.new('L', c_img.size, 255),
        alpha_c
    ))
    white_contour.save('assets/acorn.png', 'PNG')
    white_contour.save('Setup/assets/acorn.png', 'PNG')
    print("Saved assets/acorn.png (512x512 contour outline for watermark)")

    # 3. Save Windows multi-resolution icon (.ico) - COLORED for installer
    ico_sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    ico_imgs = []
    for s in ico_sizes:
        ico_imgs.append(logo.resize(s, Image.Resampling.LANCZOS))
    ico_imgs[0].save(
        'Setup/assets/app_icon.ico',
        format='ICO',
        sizes=[(im.width, im.height) for im in ico_imgs],
        append_images=ico_imgs[1:]
    )
    print("Saved Setup/assets/app_icon.ico (colored)")

    # 4. Save WizardSmallImageFile (55x55 24-bit BMP) - COLORED for installer header
    small_bmp = Image.new('RGB', (55, 55), color=(255, 255, 255))
    logo_small = logo.resize((45, 45), Image.Resampling.LANCZOS)
    small_bmp.paste(logo_small, (5, 5), mask=logo_small.split()[3])
    small_bmp.save('Setup/assets/wizard_small.bmp', 'BMP')
    print("Saved Setup/assets/wizard_small.bmp (55x55 colored)")

    # 5. Save WizardImageFile (164x314 24-bit BMP) - COLORED for installer banner
    banner_w, banner_h = 164, 314
    banner = Image.new('RGB', (banner_w, banner_h), color=(255, 255, 255))
    draw_b = ImageDraw.Draw(banner)

    # Soft subtle vertical gradient from warm cream #FAF7F4 to #EFE9E2
    for y in range(banner_h):
        t = y / float(banner_h)
        r = int(250 * (1 - t) + 238 * t)
        g = int(247 * (1 - t) + 233 * t)
        b = int(244 * (1 - t) + 226 * t)
        draw_b.line([(0, y), (banner_w, y)], fill=(r, g, b))

    # Decorative subtle accent line on right edge to separate from wizard text
    draw_b.line([(banner_w - 1, 0), (banner_w - 1, banner_h)], fill=(225, 218, 210))

    # Place colored acorn logo centered in upper portion (116x116)
    logo_banner = logo.resize((116, 116), Image.Resampling.LANCZOS)
    bx = (banner_w - 116) // 2
    by = 56
    banner.paste(logo_banner, (bx, by), mask=logo_banner.split()[3])

    # Text branding below logo
    try:
        font_title = ImageFont.truetype("arialbd.ttf", 16)
        font_sub = ImageFont.truetype("segoeui.ttf", 11)
    except Exception:
        font_title = ImageFont.load_default()
        font_sub = ImageFont.load_default()

    # Draw "NutNotes"
    title_text = "NutNotes"
    bbox_t = draw_b.textbbox((0, 0), title_text, font=font_title)
    tw = bbox_t[2] - bbox_t[0]
    draw_b.text(((banner_w - tw) // 2, by + 128), title_text, fill=(35, 20, 10), font=font_title)

    # Draw "REAPER Assistant"
    sub_text = "REAPER Assistant"
    bbox_s = draw_b.textbbox((0, 0), sub_text, font=font_sub)
    sw = bbox_s[2] - bbox_s[0]
    draw_b.text(((banner_w - sw) // 2, by + 150), sub_text, fill=(110, 90, 80), font=font_sub)

    banner.save('Setup/assets/wizard_large.bmp', 'BMP')
    print("Saved Setup/assets/wizard_large.bmp (164x314 colored)")

    # 6. Save Toolbar Icons - CONTOUR for REAPER toolbar
    # Multi-resolution outline icon:
    alpha_thick = alpha_c.filter(ImageFilter.MaxFilter(3))
    alpha_24 = alpha_thick.resize((24, 24), Image.Resampling.LANCZOS)

    # Create soft dark shadow (45% opacity) to guarantee crisp contrast on both light and dark themes
    shadow_alpha = alpha_24.filter(ImageFilter.MaxFilter(3))
    arr_sh = (np.array(shadow_alpha).astype(float) * 0.45).astype(np.uint8)
    sh_img = Image.new('RGBA', (24, 24), (0, 0, 0, 0))
    sh_img.putalpha(Image.fromarray(arr_sh))

    # Frame 1: Normal (Crisp off-white contour #EAEAEA)
    fg_normal = Image.new('RGBA', (24, 24), (235, 235, 235, 0))
    fg_normal.putalpha(alpha_24)
    icon_normal = Image.alpha_composite(sh_img, fg_normal)

    # Frame 2: Hover (Pure bright white contour #FFFFFF)
    fg_hover = Image.new('RGBA', (24, 24), (255, 255, 255, 0))
    fg_hover.putalpha(alpha_24)
    icon_hover = Image.alpha_composite(sh_img, fg_hover)

    # Frame 3: Pressed (Shifted 1px down-right)
    icon_pressed = icon_normal

    # Standard REAPER 3-state toolbar icon: 90x30
    tb_90 = Image.new("RGBA", (90, 30), (0, 0, 0, 0))
    tb_90.paste(icon_normal, (3, 3), icon_normal)
    tb_90.paste(icon_hover, (33, 3), icon_hover)
    tb_90.paste(icon_pressed, (64, 4), icon_pressed)

    for p in ['assets/nutnotes_toolbar.png', 'Setup/assets/nutnotes_toolbar.png']:
        tb_90.save(p, 'PNG')
    print("Saved assets/nutnotes_toolbar.png and Setup/assets/nutnotes_toolbar.png (90x30 contour 3-state)")

    # Single 30x30 icon
    single_30 = Image.new("RGBA", (30, 30), (0, 0, 0, 0))
    single_30.paste(icon_normal, (3, 3), icon_normal)
    for p in ['assets/nutnotes_icon_30.png', 'Setup/assets/nutnotes_icon_30.png']:
        single_30.save(p, 'PNG')
    print("Saved assets/nutnotes_icon_30.png and Setup/assets/nutnotes_icon_30.png (30x30 contour single)")

    print("\nAll assets generated successfully!")

if __name__ == '__main__':
    main()
