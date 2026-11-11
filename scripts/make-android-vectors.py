#!/usr/bin/env python3
"""Rafiq's silhouette in the Android vector drawables (status bar icon, widget previews)."""
import math, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib.util
spec = importlib.util.spec_from_file_location("icons", os.path.join(os.path.dirname(__file__), "make-icons.py"))
icons = importlib.util.module_from_spec(spec); spec.loader.exec_module(icons)
ROOT = icons.ROOT
D = os.path.join(ROOT, "android/app/src/main/res/drawable")

def poly_path(cx, cy, rx, ry, n=72):
    pts = icons.silhouette(rx, ry, n)
    return "M" + " L".join(f"{cx + x:.2f},{cy + y:.2f}" for x, y in pts) + " Z"

def crescent_path(cx, cy, r):
    ox, oy, rr = cx + r * 0.55, cy - r * 0.2, r * 0.82
    pts = []
    for i in range(48):
        a = 2 * math.pi * i / 48
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        if (x - ox) ** 2 + (y - oy) ** 2 > rr ** 2: pts.append((a, x, y))
    # outer arc (outside the cut), then back along the cut's edge inside the disc
    outer = [(x, y) for _, x, y in sorted(pts, key=lambda p: (p[0] - math.atan2(oy - cy, ox - cx)) % (2 * math.pi))]
    inner = []
    for i in range(48):
        a = 2 * math.pi * i / 48
        x, y = ox + rr * math.cos(a), oy + rr * math.sin(a)
        if (x - cx) ** 2 + (y - cy) ** 2 < r ** 2: inner.append((a, x, y))
    inner = [(x, y) for _, x, y in sorted(inner, key=lambda p: (p[0] - math.atan2(cy - oy, cx - ox) - math.pi) % (2 * math.pi))]
    # walk the cut's edge from the end of the outer arc back to its start
    if outer and inner:
        if math.dist(outer[-1], inner[0]) > math.dist(outer[-1], inner[-1]): inner.reverse()
    allp = outer + inner
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in allp) + " Z"

# Status bar icon: white silhouette, eyes cut out.
cx, cy, R = 12, 13.6, 8.3
rx, ry = R * 1.14, R * 0.88
eyes = ""
for ex in (cx - R * 0.37, cx + R * 0.37):
    w, h = R * 0.13, R * 0.17
    ey = cy - R * 0.03
    eyes += (f" M{ex - w:.2f},{ey - h + w:.2f} a{w:.2f},{w:.2f} 0 0 1 {2*w:.2f},0 v{2*(h - w):.2f}"
             f" a{w:.2f},{w:.2f} 0 0 1 {-2*w:.2f},0 Z")
open(os.path.join(D, "ic_stat_mochi.xml"), "w").write(f'''<?xml version="1.0" encoding="utf-8"?>
<!-- One-colour Rafiq for the status bar: the dome with two eyes cut out (scripts/make-android-vectors.py). -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd"
        android:pathData="{poly_path(cx, cy, rx, ry)}{eyes}" />
</vector>
''')

# Widget previews: the body path, colours, cheeks, ink; a golden crescent on top.
OLD_BODY = "M60,30.3 C89.5,30.3 101,39.2 101,62 C101,84.8 89.5,93.7 60,93.7 C30.5,93.7 19,84.8 19,62 C19,39.2 30.5,30.3 60,30.3 Z"
R = 41 / 1.14
body = poly_path(60, 62, 41, 31.7)
tip = 62 - 31.7 * icons.DOME_H
b = R * 0.065
finial = (f'    <path android:fillColor="#E8B64A" android:pathData="M{60 - b:.2f},{tip - R*0.05 - b:.2f} a{b:.2f},{b:.2f} 0 1 0 {2*b:.2f},0 a{b:.2f},{b:.2f} 0 1 0 {-2*b:.2f},0 Z" />\n'
          f'    <path android:fillColor="#E8B64A" android:pathData="{crescent_path(60, tip - R * 0.27, R * 0.12)}" />\n')
for name in ("idle", "working", "done", "waiting"):
    p = os.path.join(D, f"preview_face_{name}.xml")
    s = open(p).read()
    s = s.replace(OLD_BODY, body).replace("#EDEDEF", "#FBF6EC").replace("#C4C5CA", "#DECDB0")
    s = s.replace("#59FF7896", "#73E8B64A").replace("#1A1412", "#13213F")
    s = s.replace("pink cheeks", "golden cheeks").replace("Mochi's face", "Rafiq's face")
    if 'android:fillColor="#E8B64A"' not in s:
        s = s.replace("</vector>", finial + "</vector>")
    open(p, "w").write(s)
print("android vectors written")
