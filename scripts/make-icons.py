#!/usr/bin/env python3
"""Rafiq's icons, drawn from scratch: the companion (RafiqLook.swift's dome) in a night sky.

    python3 scripts/make-icons.py            # writes every icon of the Mac, iPhone, Windows and Android apps
"""
import math, os, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IVORY, SAND = (251, 246, 236), (222, 205, 176)
INK, GOLD = (19, 33, 63), (232, 182, 74)
# Same silhouette as RafiqLook.swift.
DOME_H, TAPER, CURVE, BASE = 1.3, 2.0, 1.4, 3.2

def inside(x, y, rx, ry):
    if y >= 0:
        return abs(x / rx) ** BASE + abs(y / ry) ** BASE <= 1
    t = -y / (ry * DOME_H)
    return t < 1 and abs(x) <= rx * (1 - t ** TAPER) ** CURVE

def silhouette(rx, ry, n=240):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        ca, sa = math.cos(a), math.sin(a)
        lo, hi = 0.0, max(rx, ry * DOME_H) * 1.05
        for _ in range(26):
            m = (lo + hi) / 2
            if inside(ca * m, sa * m, rx, ry): lo = m
            else: hi = m
        pts.append((ca * lo, sa * lo))
    return pts

def vgrad(size, top, bottom):
    w, h = size
    k = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top)[None, None, :] * (1 - k) + np.array(bottom)[None, None, :] * k
    return Image.fromarray(np.repeat(arr, w, axis=1).astype(np.uint8), "RGB")

def draw_rafiq(img, cx, cy, R, glow=True, finial=True, flat=None, eyes=True):
    """The companion, centred on (cx, cy), unit R, like BotEngine (rx = 1.14 R, ry = 0.88 R)."""
    rx, ry = R * 1.14, R * 0.88
    pts = [(cx + x, cy + y) for x, y in silhouette(rx, ry)]
    W, H = img.size
    if glow:
        g = Image.new("RGBA", img.size, GOLD + (0,))
        ImageDraw.Draw(g).polygon(pts, fill=GOLD + (170,))
        g = g.filter(ImageFilter.GaussianBlur(R * 0.35))
        img.alpha_composite(g)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    if flat:
        body = Image.new("RGBA", img.size, flat + (255,))
    else:
        top = int(cy - ry * DOME_H)
        body = Image.new("RGBA", img.size, (0, 0, 0, 0))
        band = vgrad((W, int(ry * (1 + DOME_H)) + 2), IVORY, SAND).convert("RGBA")
        body.paste(band, (0, top))
        # soft highlight, upper right
        hl = Image.new("RGBA", img.size, (255, 255, 255, 0))
        ImageDraw.Draw(hl).ellipse([cx + rx * 0.12, cy - ry * 0.95, cx + rx * 0.62, cy - ry * 0.25], fill=(255, 255, 255, 150))
        body.alpha_composite(hl.filter(ImageFilter.GaussianBlur(R * 0.14)))
    img.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(img)
    if finial:
        tip = cy - ry * DOME_H
        b = R * 0.065
        d.ellipse([cx - b, tip - R * 0.05 - 2 * b, cx + b, tip - R * 0.05], fill=GOLD if not flat else flat)
        r = R * 0.12
        ccx, ccy = cx, tip - R * 0.27
        cres = Image.new("L", img.size, 0)
        cd = ImageDraw.Draw(cres)
        cd.ellipse([ccx - r, ccy - r, ccx + r, ccy + r], fill=255)
        ox, oy, rr = ccx + r * 0.55, ccy - r * 0.2, r * 0.82
        cd.ellipse([ox - rr, oy - rr, ox + rr, oy + rr], fill=0)
        img.paste(Image.new("RGBA", img.size, (GOLD if not flat else flat) + (255,)), (0, 0), cres)
    if eyes:
        for sd in (-1, 1):
            ex, ey = cx + sd * R * 0.37, cy - R * 0.04
            ew, eh = R * 0.125, R * 0.15
            d.rounded_rectangle([ex - ew, ey - eh, ex + ew, ey + eh], radius=ew, fill=INK if not flat else (0, 0, 0, 0))
            if not flat:
                d.ellipse([ex - R * 0.01, ey - R * 0.11, ex + R * 0.075, ey - R * 0.025], fill=(255, 255, 255))
        if not flat:
            for sd in (-1, 1):  # warm golden cheeks
                ch = Image.new("RGBA", img.size, GOLD + (0,))
                bx, by = cx + sd * rx * 0.58, cy + ry * 0.24
                ImageDraw.Draw(ch).ellipse([bx - R * 0.15, by - R * 0.08, bx + R * 0.15, by + R * 0.08], fill=GOLD + (90,))
                img.alpha_composite(ch.filter(ImageFilter.GaussianBlur(R * 0.03)))

def stars(img, box, seed=3, n=18, color=(255, 240, 210)):
    rnd = np.random.default_rng(seed)
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    for _ in range(n):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y0 + (y1 - y0) * 0.55)
        r = rnd.uniform(0.6, 1.8) * img.size[0] / 512
        a = int(rnd.uniform(90, 220))
        d.ellipse([x - r, y - r, x + r, y + r], fill=color + (a,))

THEMES = {
    "Night":    ((11, 22, 48), (27, 77, 92)),
    "Blue":     ((12, 42, 92), (40, 120, 200)),
    "Graphite": ((24, 26, 30), (70, 74, 82)),
    "Green":    ((8, 48, 40), (24, 130, 100)),
    "Pink":     ((70, 20, 52), (200, 80, 130)),
    "Purple":   ((34, 18, 72), (120, 80, 210)),
    "Orange":   ((80, 30, 10), (226, 120, 40)),
}

def square(size, theme="Night", dark=False):
    """Full-bleed square (iPhone, Android): background, stars, the companion."""
    S = 1024
    top, bottom = ((6, 8, 14), (16, 22, 34)) if dark else THEMES[theme]
    img = vgrad((S, S), top, bottom).convert("RGBA")
    stars(img, (0, 0, S, S))
    draw_rafiq(img, S / 2, S * 0.60, S * 0.25)
    return img.resize((size, size), Image.LANCZOS)

def mac_icon(size):
    """macOS shape: a rounded square inset in the canvas, with a soft shadow."""
    S = 1024
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inset, rad = 100, 185
    box = [inset, inset, S - inset, S - inset]
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([box[0], box[1] + 12, box[2], box[3] + 12], radius=rad, fill=(0, 0, 0, 110))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)))
    tile = vgrad((S, S), *THEMES["Night"]).convert("RGBA")
    stars(tile, box)
    draw_rafiq(tile, S / 2, S * 0.585, S * 0.205)
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=rad, fill=255)
    canvas.paste(tile, (0, 0), m)
    return canvas.resize((size, size), Image.LANCZOS)

def menubar(h):
    """Template image: the black silhouette with the eyes cut out, crescent on top."""
    S = 8
    W, H = int(h * 4 / 3) * S, h * S
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    R = H * 0.47
    draw_rafiq(img, W / 2, H * 0.56, R, glow=False, finial=False, flat=(0, 0, 0))
    return img.resize((W // S, H // S), Image.LANCZOS)

def save(img, *path, rgb=False):
    p = os.path.join(ROOT, *path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    (img.convert("RGB") if rgb else img).save(p)

def main():
    mac = "NotchBuddy/Assets.xcassets/AppIcon.appiconset"
    for s in (16, 32, 128, 256, 512):
        save(mac_icon(s), mac, f"icon_{s}x{s}.png")
        save(mac_icon(s * 2), mac, f"icon_{s}x{s}@2x.png")
    mb = "NotchBuddy/Assets.xcassets/MenuBarIcon.imageset"
    save(menubar(18), mb, "menubar.png"); save(menubar(36), mb, "menubar@2x.png"); save(menubar(54), mb, "menubar@3x.png")
    ph = "NotchBuddy/PhoneAssets.xcassets"
    save(square(1024), ph, "AppIcon.appiconset", "icon-1024.png", rgb=True)
    save(square(1024, dark=True), ph, "AppIcon.appiconset", "icon-1024-dark.png", rgb=True)
    save(square(1024).convert("L").convert("RGB"), ph, "AppIcon.appiconset", "icon-1024-tinted.png", rgb=True)
    for theme in ("Blue", "Graphite", "Green", "Pink", "Purple"):
        save(square(1024, theme), ph, f"AppIcon-{theme}.appiconset", "icon-1024.png", rgb=True)
    for theme in ("Blue", "Graphite", "Green", "Pink", "Purple", "Orange"):
        save(square(180, theme), ph, f"IconPreview-{theme}.imageset", "preview.png", rgb=True)
    win = "windows/src-tauri/icons"
    save(mac_icon(32), win, "32x32.png"); save(mac_icon(128), win, "128x128.png")
    save(mac_icon(256), win, "128x128@2x.png"); save(mac_icon(512), win, "icon.png")
    mac_icon(256).save(os.path.join(ROOT, win, "icon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    # Android: a full-bleed tile, rounded like the launcher's mask.
    a = square(512)
    m = Image.new("L", a.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, 511, 511], radius=112, fill=255)
    out = Image.new("RGBA", a.size, (0, 0, 0, 0)); out.paste(a, (0, 0), m)
    save(out, "android/app/src/main/res/mipmap-xxxhdpi", "ic_launcher.png")
    # The README's and the site's icon.
    save(mac_icon(256), "docs", "media", "icon.png")
    print("icons written")

if __name__ == "__main__":
    main()
