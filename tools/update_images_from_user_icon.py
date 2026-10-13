#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Update all project and installer images based on the user's hand-crafted installer/assets/app_icon.png.
Updates:
  - assets/acorn.png (512x512)
  - assets/acorn_colored.png (512x512)
  - assets/nutnotes_toolbar.png (90x30 3-state)
  - assets/nutnotes_icon_30.png (30x30)
  - installer/assets/app_icon.ico (Windows multi-res: 256, 128, 64, 48, 32, 16)
  - installer/assets/wizard_small.bmp (55x55 24-bit BMP)
  - installer/assets/wizard_large.bmp (164x314 24-bit BMP)
  - installer/assets/nutnotes_toolbar.png (90x30 3-state)
  - installer/assets/nutnotes_icon_30.png (30x30)
  - build/ and release/ assets mirrors
"""

import os
import shutil
from PIL import Image, ImageDraw, ImageFont

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_APP_ICON = os.path.join(PROJECT_DIR, "installer", "assets", "app_icon.png")

def main():
    if not os.path.exists(SRC_APP_ICON):
        raise FileNotFoundError(f"Source icon not found: {SRC_APP_ICON}")

    print(f"Loading user icon from: {SRC_APP_ICON}")
    user_icon = Image.open(SRC_APP_ICON).convert("RGBA")
    print(f"User icon size: {user_icon.size}, mode: {user_icon.mode}")

    # 1. assets/acorn_colored.png (512x512 colored) and assets/acorn.png (512x512 contour outline)
    icon_512 = user_icon.resize((512, 512), Image.Resampling.LANCZOS)
    
    os.makedirs(os.path.join(PROJECT_DIR, "assets"), exist_ok=True)
    p_acorn_col = os.path.join(PROJECT_DIR, "assets", "acorn_colored.png")
    icon_512.save(p_acorn_col, "PNG")
    print(f"Updated: {p_acorn_col} (512x512 colored)")

    # 2. In-App Contour Acorn (for watermark in main window & overlay)
    contour_src = os.path.join(PROJECT_DIR, "installer", "assets", "acorn.png")
    if not os.path.exists(contour_src):
        contour_src = os.path.join(PROJECT_DIR, "examples", "acorn_3364582.png")
    c_img = Image.open(contour_src).convert("RGBA")
    alpha_c = c_img.split()[3]
    white_contour = Image.merge("RGBA", (
        Image.new("L", c_img.size, 255),
        Image.new("L", c_img.size, 255),
        Image.new("L", c_img.size, 255),
        alpha_c
    ))
    p_acorn = os.path.join(PROJECT_DIR, "assets", "acorn.png")
    white_contour.save(p_acorn, "PNG")
    white_contour.save(os.path.join(PROJECT_DIR, "installer", "assets", "acorn.png"), "PNG")
    print(f"Updated: {p_acorn} (512x512 contour outline for watermark)")

    # 3. installer/assets/app_icon.ico (multi-resolution Windows icon) - COLORED for installer
    ico_dest = os.path.join(PROJECT_DIR, "installer", "assets", "app_icon.ico")
    ico_sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    ico_imgs = [user_icon.resize(s, Image.Resampling.LANCZOS) for s in ico_sizes]
    ico_imgs[0].save(
        ico_dest,
        format="ICO",
        sizes=[(im.width, im.height) for im in ico_imgs],
        append_images=ico_imgs[1:]
    )
    print(f"Updated: {ico_dest} (multi-res ICO 16..256 colored)")

    # 4. installer/assets/wizard_small.bmp (55x55 24-bit BMP) - COLORED for installer header
    small_bmp = Image.new("RGB", (55, 55), color=(255, 255, 255))
    icon_45 = user_icon.resize((45, 45), Image.Resampling.LANCZOS)
    small_bmp.paste(icon_45, (5, 5), mask=icon_45.split()[3])
    small_dest = os.path.join(PROJECT_DIR, "installer", "assets", "wizard_small.bmp")
    small_bmp.save(small_dest, "BMP")
    print(f"Updated: {small_dest} (55x55 BMP colored)")

    # 5. installer/assets/wizard_large.bmp (164x314 24-bit BMP) - COLORED for installer banner
    banner_w, banner_h = 164, 314
    banner = Image.new("RGB", (banner_w, banner_h), color=(255, 255, 255))
    draw_b = ImageDraw.Draw(banner)

    # Soft subtle warm neutral gradient
    for y in range(banner_h):
        t = y / float(banner_h)
        r = int(250 * (1 - t) + 238 * t)
        g = int(247 * (1 - t) + 233 * t)
        b = int(244 * (1 - t) + 226 * t)
        draw_b.line([(0, y), (banner_w, y)], fill=(r, g, b))

    # Right edge subtle separator line
    draw_b.line([(banner_w - 1, 0), (banner_w - 1, banner_h)], fill=(225, 218, 210))

    # Paste centered icon (116x116)
    icon_banner = user_icon.resize((116, 116), Image.Resampling.LANCZOS)
    bx = (banner_w - 116) // 2
    by = 56
    banner.paste(icon_banner, (bx, by), mask=icon_banner.split()[3])

    # Text branding below logo
    try:
        font_title = ImageFont.truetype("arialbd.ttf", 16)
        font_sub = ImageFont.truetype("segoeui.ttf", 11)
    except Exception:
        font_title = ImageFont.load_default()
        font_sub = ImageFont.load_default()

    title_text = "NutNotes"
    bbox_t = draw_b.textbbox((0, 0), title_text, font=font_title)
    tw = bbox_t[2] - bbox_t[0]
    draw_b.text(((banner_w - tw) // 2, by + 128), title_text, fill=(35, 20, 10), font=font_title)

    sub_text = "REAPER Assistant"
    bbox_s = draw_b.textbbox((0, 0), sub_text, font=font_sub)
    sw = bbox_s[2] - bbox_s[0]
    draw_b.text(((banner_w - sw) // 2, by + 150), sub_text, fill=(110, 90, 80), font=font_sub)

    large_dest = os.path.join(PROJECT_DIR, "installer", "assets", "wizard_large.bmp")
    banner.save(large_dest, "BMP")
    print(f"Updated: {large_dest} (164x314 BMP colored)")

    # 6. REAPER Toolbar icons - CONTOUR outline
    from PIL import ImageFilter
    alpha_thick = alpha_c.filter(ImageFilter.MaxFilter(3))
    alpha_24 = alpha_thick.resize((24, 24), Image.Resampling.LANCZOS)

    # Soft dark shadow for contrast across any theme
    shadow_alpha = alpha_24.filter(ImageFilter.MaxFilter(3))
    import numpy as np
    arr_sh = (np.array(shadow_alpha).astype(float) * 0.45).astype(np.uint8)
    sh_img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    sh_img.putalpha(Image.fromarray(arr_sh))

    fg_normal = Image.new("RGBA", (24, 24), (235, 235, 235, 0))
    fg_normal.putalpha(alpha_24)
    icon_normal = Image.alpha_composite(sh_img, fg_normal)

    fg_hover = Image.new("RGBA", (24, 24), (255, 255, 255, 0))
    fg_hover.putalpha(alpha_24)
    icon_hover = Image.alpha_composite(sh_img, fg_hover)

    icon_pressed = icon_normal

    # A) 90x30 3-state icon (Normal, Hover, Pressed)
    tb_90 = Image.new("RGBA", (90, 30), (0, 0, 0, 0))
    tb_90.paste(icon_normal, (3, 3), icon_normal)
    tb_90.paste(icon_hover, (33, 3), icon_hover)
    tb_90.paste(icon_pressed, (64, 4), icon_pressed)

    for folder in [os.path.join(PROJECT_DIR, "installer", "assets"), os.path.join(PROJECT_DIR, "assets")]:
        dst = os.path.join(folder, "nutnotes_toolbar.png")
        tb_90.save(dst, "PNG")
        print(f"Updated: {dst} (90x30 contour 3-state)")

    # B) 30x30 single icon
    single_30 = Image.new("RGBA", (30, 30), (0, 0, 0, 0))
    single_30.paste(icon_normal, (3, 3), icon_normal)
        dst = os.path.join(folder, "nutnotes_icon_30.png")
        single_30.save(dst, "PNG")
        print(f"Updated: {dst} (30x30 contour single)")

    # 6. Mirror to build/ and release/ if they exist
    for mirror_base in [os.path.join(PROJECT_DIR, "build", "NutNotes_v0.2_BETA", "assets"),
                        os.path.join(PROJECT_DIR, "release", "assets")]:
        if os.path.exists(mirror_base):
            shutil.copy2(p_acorn, os.path.join(mirror_base, "acorn.png"))
            shutil.copy2(os.path.join(PROJECT_DIR, "assets", "nutnotes_toolbar.png"),
                         os.path.join(mirror_base, "nutnotes_toolbar.png"))
            shutil.copy2(os.path.join(PROJECT_DIR, "assets", "nutnotes_icon_30.png"),
                         os.path.join(mirror_base, "nutnotes_icon_30.png"))
            print(f"Mirrored updated assets to: {mirror_base}")

    print("\nAll project and installer images successfully updated from app_icon.png!")

if __name__ == "__main__":
    main()
