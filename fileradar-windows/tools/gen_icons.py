#!/usr/bin/env python3
"""Generate FileRadar rich icon set — depth, gradients, specular highlights."""
from __future__ import annotations

import math
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = os.path.join(
    os.path.dirname(__file__),
    "..",
    "FileRadar",
    "Assets",
    "Icons",
)
SIZE = 128
os.makedirs(OUT, exist_ok=True)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def make_canvas():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def rounded_rect_mask(xy, r):
    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).rounded_rectangle(xy, radius=r, fill=255)
    return m


def gradient_fill(xy, c1, c2, vertical=True, r=18):
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    x0, y0, x1, y1 = xy
    w, h = x1 - x0, y1 - y0
    grad = Image.new("RGBA", (max(w, 1), max(h, 1)))
    gd = ImageDraw.Draw(grad)
    steps = h if vertical else w
    for i in range(max(steps, 1)):
        t = i / max(steps - 1, 1)
        col = lerp(c1, c2, t) + (255,)
        if vertical:
            gd.line([(0, i), (w, i)], fill=col)
        else:
            gd.line([(i, 0), (i, h)], fill=col)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    layer.paste(grad, (x0, y0), mask)
    return layer


def specular(xy, r=18, strength=70):
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    x0, y0, x1, y1 = xy
    od.rounded_rectangle(
        [x0 + 2, y0 + 2, x1 - 2, y0 + (y1 - y0) * 0.42],
        radius=max(r - 2, 2),
        fill=(255, 255, 255, strength),
    )
    overlay = overlay.filter(ImageFilter.GaussianBlur(3))
    mask = rounded_rect_mask(xy, r)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(overlay, mask=mask)
    return out


def rim(xy, color, r=18, width=2):
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(xy, radius=r, outline=color + (220,), width=width)
    return layer


def compose(parts):
    img = make_canvas()
    for p in parts:
        img = Image.alpha_composite(img, p)
    return img


def save(name, img):
    path = os.path.join(OUT, f"{name}.png")
    img.save(path, "PNG")
    print("wrote", name)


def icon_folder(name="folder", c1="#3B82F6", c2="#1D4ED8", tab="#60A5FA"):
    body = (18, 42, 110, 108)
    tabxy = (18, 28, 58, 48)
    body_m = rounded_rect_mask(body, 14)
    tab_m = rounded_rect_mask(tabxy, 10)
    sm = ImageChops.lighter(body_m, tab_m)
    sh = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 100), mask=sm)
    sh = sh.filter(ImageFilter.GaussianBlur(7))
    base = make_canvas()
    base.alpha_composite(sh, (0, 4))
    tab_fill = gradient_fill(tabxy, hex_rgb(tab), hex_rgb(c1), r=10)
    body_fill = gradient_fill(body, hex_rgb(c1), hex_rgb(c2), r=14)
    pocket = gradient_fill((26, 54, 102, 100), hex_rgb("#93C5FD"), hex_rgb(c1), r=10)
    a = pocket.split()[-1]
    pocket.putalpha(Image.eval(a, lambda v: int(v * 0.35)))
    hi = specular(body, r=14, strength=55)
    riml = rim(body, (255, 255, 255), r=14, width=1)
    save(name, compose([base, tab_fill, body_fill, pocket, hi, riml]))


def icon_doc(name, c1, c2, mark_color, mark_fn):
    xy = (30, 14, 98, 114)
    body_m = rounded_rect_mask(xy, 14)
    sh = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 95), mask=body_m)
    sh = sh.filter(ImageFilter.GaussianBlur(6))
    base = make_canvas()
    base.alpha_composite(sh, (1, 4))
    body = gradient_fill(xy, hex_rgb(c1), hex_rgb(c2), r=14)
    fold = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fold)
    fd.polygon([(72, 14), (98, 14), (98, 40)], fill=hex_rgb(c2) + (255,))
    fd.polygon(
        [(72, 14), (98, 40), (72, 40)],
        fill=lerp(hex_rgb(c1), (255, 255, 255), 0.35) + (255,),
    )
    hi = specular(xy, r=14, strength=50)
    mark = make_canvas()
    mark_fn(ImageDraw.Draw(mark), mark_color)
    riml = rim(xy, (255, 255, 255), r=14, width=1)
    save(name, compose([base, body, fold, hi, mark, riml]))


def icon_image():
    def mark(d, col):
        d.rounded_rectangle([42, 48, 86, 88], radius=8, fill=col + (230,))
        d.ellipse([48, 54, 62, 68], fill=(255, 255, 255, 220))
        d.polygon([(46, 86), (62, 66), (74, 78), (86, 58), (86, 86)], fill=(255, 255, 255, 200))

    icon_doc("image", "#38BDF8", "#0284C7", (255, 255, 255), mark)


def icon_video():
    def mark(d, col):
        d.rounded_rectangle([44, 48, 84, 86], radius=10, fill=col + (235,))
        d.polygon([(56, 56), (56, 78), (76, 67)], fill=(255, 255, 255, 240))

    icon_doc("video", "#A78BFA", "#6D28D9", (255, 255, 255), mark)


def icon_music():
    def mark(d, col):
        d.ellipse([48, 70, 72, 94], fill=col + (240,))
        d.rectangle([68, 36, 76, 78], fill=col + (240,))
        d.polygon([(76, 36), (96, 44), (96, 54), (76, 48)], fill=col + (240,))

    icon_doc("music", "#34D399", "#059669", (255, 255, 255), mark)


def icon_document():
    def mark(d, col):
        for y in (52, 64, 76, 88):
            d.rounded_rectangle([42, y, 86, y + 6], radius=3, fill=col + (200,))

    icon_doc("document", "#F8FAFC", "#CBD5E1", (71, 85, 105), mark)


def icon_archive():
    def mark(d, col):
        d.rounded_rectangle([40, 40, 88, 96], radius=8, fill=col + (230,))
        d.rectangle([40, 56, 88, 64], fill=(255, 255, 255, 180))
        d.rounded_rectangle([56, 58, 72, 74], radius=3, fill=(255, 255, 255, 230))

    icon_doc("archive", "#FBBF24", "#D97706", (120, 53, 15), mark)


def icon_app():
    def mark(d, col):
        for i, xy in enumerate([(44, 48, 60, 64), (68, 48, 84, 64), (44, 72, 60, 88), (68, 72, 84, 88)]):
            d.rounded_rectangle(xy, radius=5, fill=(255, 255, 255, 210 if i % 2 == 0 else 160))

    icon_doc("app", "#818CF8", "#4F46E5", (255, 255, 255), mark)


def icon_file():
    def mark(d, col):
        d.rounded_rectangle([42, 58, 86, 66], radius=3, fill=col + (180,))
        d.rounded_rectangle([42, 74, 74, 82], radius=3, fill=col + (140,))

    icon_doc("file", "#E2E8F0", "#94A3B8", (71, 85, 105), mark)


def icon_pdf():
    def mark(d, col):
        d.rounded_rectangle([44, 56, 84, 86], radius=8, fill=(239, 68, 68, 240))
        d.rounded_rectangle([52, 66, 60, 78], radius=2, fill=(255, 255, 255, 240))
        d.rounded_rectangle([64, 66, 76, 72], radius=2, fill=(255, 255, 255, 240))
        d.rounded_rectangle([64, 74, 72, 78], radius=2, fill=(255, 255, 255, 200))

    icon_doc("pdf", "#FECACA", "#EF4444", (255, 255, 255), mark)


def icon_code():
    def mark(d, col):
        d.polygon([(54, 52), (42, 70), (54, 88), (62, 82), (54, 70), (62, 58)], fill=col + (230,))
        d.polygon([(74, 52), (86, 70), (74, 88), (66, 82), (74, 70), (66, 58)], fill=col + (230,))

    icon_doc("code", "#67E8F9", "#0891B2", (255, 255, 255), mark)


def badge(name, c1, c2, draw_fn, r=28):
    xy = (16, 16, 112, 112)
    m = rounded_rect_mask(xy, r)
    sh = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 110), mask=m)
    sh = sh.filter(ImageFilter.GaussianBlur(8))
    base = make_canvas()
    base.alpha_composite(sh, (0, 4))
    body = gradient_fill(xy, hex_rgb(c1), hex_rgb(c2), r=r)
    hi = specular(xy, r=r, strength=60)
    glyph = make_canvas()
    draw_fn(ImageDraw.Draw(glyph))
    riml = rim(xy, (255, 255, 255), r=r, width=1)
    save(name, compose([base, body, hi, glyph, riml]))


def draw_home(d):
    d.polygon([(64, 34), (96, 62), (88, 62), (88, 94), (40, 94), (40, 62), (32, 62)], fill=(255, 255, 255, 245))
    d.rectangle([54, 72, 74, 94], fill=(255, 255, 255, 200))


def draw_star(d):
    pts = []
    for i in range(5):
        a = math.radians(-90 + i * 72)
        b = math.radians(-90 + i * 72 + 36)
        pts.append((64 + 28 * math.cos(a), 64 + 28 * math.sin(a)))
        pts.append((64 + 12 * math.cos(b), 64 + 12 * math.sin(b)))
    d.polygon(pts, fill=(255, 255, 255, 245))


def draw_download(d):
    d.rectangle([58, 30, 70, 70], fill=(255, 255, 255, 240))
    d.polygon([(44, 66), (64, 90), (84, 66)], fill=(255, 255, 255, 240))
    d.rounded_rectangle([36, 96, 92, 106], radius=4, fill=(255, 255, 255, 220))


def draw_desktop(d):
    d.rounded_rectangle([30, 36, 98, 82], radius=8, fill=(255, 255, 255, 240))
    d.rectangle([34, 40, 94, 72], fill=(147, 197, 253, 220))
    d.rounded_rectangle([50, 86, 78, 94], radius=3, fill=(255, 255, 255, 220))
    d.rectangle([44, 94, 84, 100], fill=(255, 255, 255, 200))


def draw_docs(d):
    d.rounded_rectangle([40, 30, 78, 96], radius=8, fill=(255, 255, 255, 200))
    d.rounded_rectangle([50, 38, 92, 104], radius=8, fill=(255, 255, 255, 245))
    for y in (54, 66, 78):
        d.rounded_rectangle([60, y, 84, y + 6], radius=2, fill=(59, 130, 246, 200))


def draw_pictures(d):
    d.rounded_rectangle([34, 40, 94, 96], radius=10, fill=(255, 255, 255, 235))
    d.ellipse([44, 50, 62, 68], fill=(253, 224, 71, 230))
    d.polygon([(40, 94), (58, 70), (72, 84), (86, 60), (94, 94)], fill=(34, 197, 94, 210))


def draw_music_place(d):
    d.ellipse([40, 64, 72, 96], fill=(255, 255, 255, 240))
    d.rectangle([66, 34, 76, 78], fill=(255, 255, 255, 240))
    d.polygon([(76, 34), (100, 42), (100, 54), (76, 48)], fill=(255, 255, 255, 240))


def draw_videos_place(d):
    d.rounded_rectangle([34, 42, 94, 90], radius=12, fill=(255, 255, 255, 240))
    d.polygon([(54, 52), (54, 80), (80, 66)], fill=(124, 58, 237, 230))


def draw_recycle(d):
    d.polygon([(48, 40), (80, 40), (92, 100), (36, 100)], fill=(255, 255, 255, 230))
    d.rounded_rectangle([44, 30, 84, 42], radius=4, fill=(255, 255, 255, 245))
    d.rectangle([60, 24, 68, 34], fill=(255, 255, 255, 245))


def draw_search(d):
    d.ellipse([34, 34, 82, 82], outline=(255, 255, 255, 245), width=8)
    d.line([(78, 78), (100, 100)], fill=(255, 255, 255, 245), width=9)


def draw_sync(d):
    d.arc([34, 34, 94, 94], 40, 220, fill=(255, 255, 255, 245), width=8)
    d.polygon([(86, 28), (102, 48), (78, 52)], fill=(255, 255, 255, 245))
    d.arc([34, 34, 94, 94], 220, 400, fill=(255, 255, 255, 200), width=8)
    d.polygon([(42, 100), (26, 80), (50, 76)], fill=(255, 255, 255, 200))


def draw_transfers(d):
    d.polygon([(64, 28), (88, 52), (76, 52), (76, 76), (52, 76), (52, 52), (40, 52)], fill=(255, 255, 255, 245))
    d.polygon([(64, 100), (40, 76), (52, 76), (52, 52), (76, 52), (76, 76), (88, 76)], fill=(255, 255, 255, 200))


def draw_inspector(d):
    d.rounded_rectangle([36, 30, 92, 98], radius=10, fill=(255, 255, 255, 230))
    d.rounded_rectangle([44, 38, 84, 62], radius=6, fill=(59, 130, 246, 200))
    d.rounded_rectangle([44, 70, 84, 78], radius=3, fill=(148, 163, 184, 220))
    d.rounded_rectangle([44, 84, 70, 90], radius=3, fill=(148, 163, 184, 180))


def draw_chrome(d):
    d.rounded_rectangle([30, 36, 60, 66], radius=8, fill=(255, 255, 255, 240))
    d.rounded_rectangle([68, 36, 98, 66], radius=8, fill=(255, 255, 255, 180))
    d.rounded_rectangle([30, 74, 60, 104], radius=8, fill=(255, 255, 255, 180))
    d.rounded_rectangle([68, 74, 98, 104], radius=8, fill=(255, 255, 255, 240))


def draw_dualpane(d):
    d.rounded_rectangle([28, 34, 60, 94], radius=8, fill=(255, 255, 255, 240))
    d.rounded_rectangle([68, 34, 100, 94], radius=8, fill=(255, 255, 255, 200))


def draw_grid(d):
    for x, y in [(34, 34), (64, 34), (34, 64), (64, 64)]:
        d.rounded_rectangle([x, y, x + 28, y + 28], radius=6, fill=(255, 255, 255, 230))


def draw_more(d):
    for x in (40, 64, 88):
        d.ellipse([x - 8, 56, x + 8, 72], fill=(255, 255, 255, 240))


def draw_sun(d):
    d.ellipse([48, 48, 80, 80], fill=(255, 255, 255, 245))
    for i in range(8):
        a = math.radians(i * 45)
        x0 = 64 + 22 * math.cos(a)
        y0 = 64 + 22 * math.sin(a)
        x1 = 64 + 34 * math.cos(a)
        y1 = 64 + 34 * math.sin(a)
        d.line([(x0, y0), (x1, y1)], fill=(255, 255, 255, 230), width=5)


def draw_dropstack(d):
    d.rounded_rectangle([34, 58, 94, 100], radius=10, fill=(255, 255, 255, 230))
    d.polygon([(64, 28), (92, 58), (36, 58)], fill=(255, 255, 255, 245))
    d.rectangle([58, 40, 70, 70], fill=(255, 255, 255, 245))


def draw_queue(d):
    for i, y in enumerate([36, 56, 76]):
        alpha = 245 - i * 40
        d.rounded_rectangle([34, y, 94, y + 14], radius=6, fill=(255, 255, 255, alpha))


def draw_shelves(d):
    for y in (36, 58, 80):
        d.rounded_rectangle([30, y, 98, y + 16], radius=5, fill=(255, 255, 255, 230 if y != 58 else 200))


def draw_cleanup(d):
    d.ellipse([36, 36, 92, 92], outline=(255, 255, 255, 245), width=7)
    d.line([(50, 50), (78, 78)], fill=(255, 255, 255, 245), width=7)
    d.line([(78, 50), (50, 78)], fill=(255, 255, 255, 245), width=7)


def draw_duplicates(d):
    d.rounded_rectangle([34, 40, 78, 92], radius=8, fill=(255, 255, 255, 180))
    d.rounded_rectangle([50, 34, 94, 86], radius=8, fill=(255, 255, 255, 245))


def draw_timeline(d):
    d.ellipse([54, 30, 74, 50], fill=(255, 255, 255, 245))
    d.rectangle([60, 50, 68, 86], fill=(255, 255, 255, 230))
    d.ellipse([40, 82, 56, 98], fill=(255, 255, 255, 200))
    d.ellipse([72, 82, 88, 98], fill=(255, 255, 255, 200))
    d.line([(48, 90), (80, 90)], fill=(255, 255, 255, 180), width=4)


def draw_workspaces(d):
    d.rounded_rectangle([28, 40, 58, 88], radius=8, fill=(255, 255, 255, 200))
    d.rounded_rectangle([50, 34, 80, 94], radius=8, fill=(255, 255, 255, 230))
    d.rounded_rectangle([72, 40, 102, 88], radius=8, fill=(255, 255, 255, 200))


def draw_brand(d):
    for rad in (18, 30, 42):
        d.ellipse([64 - rad, 64 - rad, 64 + rad, 64 + rad], outline=(255, 255, 255, 200), width=4)
    d.ellipse([58, 58, 70, 70], fill=(255, 255, 255, 245))
    d.pieslice([22, 22, 106, 106], -20, 25, fill=(255, 255, 255, 70))


def draw_gear(d):
    d.ellipse([50, 50, 78, 78], outline=(255, 255, 255, 245), width=7)
    for i in range(8):
        a = math.radians(i * 45)
        x0 = 64 + 16 * math.cos(a)
        y0 = 64 + 16 * math.sin(a)
        x1 = 64 + 30 * math.cos(a)
        y1 = 64 + 30 * math.sin(a)
        d.line([(x0, y0), (x1, y1)], fill=(255, 255, 255, 245), width=8)
    d.ellipse([56, 56, 72, 72], fill=(255, 255, 255, 245))


def badge_moon():
    xy = (16, 16, 112, 112)
    r = 28
    m = rounded_rect_mask(xy, r)
    sh = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh.paste((0, 0, 0, 110), mask=m)
    sh = sh.filter(ImageFilter.GaussianBlur(8))
    base = make_canvas()
    base.alpha_composite(sh, (0, 4))
    body = gradient_fill(xy, hex_rgb("#6366F1"), hex_rgb("#312E81"), r=r)
    hi = specular(xy, r=r, strength=50)
    glyph = make_canvas()
    gd = ImageDraw.Draw(glyph)
    gd.ellipse([40, 36, 96, 92], fill=(255, 255, 255, 245))
    punch = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(punch).ellipse([58, 30, 112, 84], fill=255)
    rr, gg, bb, aa = glyph.split()
    aa = ImageChops.multiply(aa, Image.eval(punch, lambda p: 255 - p))
    glyph = Image.merge("RGBA", (rr, gg, bb, aa))
    riml = rim(xy, (255, 255, 255), r=r, width=1)
    save("moon", compose([base, body, hi, glyph, riml]))


def main():
    icon_folder("folder")
    icon_folder("folder-teal", "#14B8A6", "#0F766E", "#5EEAD4")
    icon_folder("folder-amber", "#F59E0B", "#B45309", "#FCD34D")
    icon_image()
    icon_video()
    icon_music()
    icon_document()
    icon_archive()
    icon_app()
    icon_file()
    icon_pdf()
    icon_code()

    badge("home", "#3B82F6", "#1D4ED8", draw_home)
    badge("star", "#F59E0B", "#B45309", draw_star)
    badge("downloads", "#06B6D4", "#0E7490", draw_download)
    badge("desktop", "#64748B", "#334155", draw_desktop)
    badge("documents", "#3B82F6", "#1E40AF", draw_docs)
    badge("pictures", "#EC4899", "#BE185D", draw_pictures)
    badge("music-place", "#10B981", "#047857", draw_music_place)
    badge("videos-place", "#8B5CF6", "#5B21B6", draw_videos_place)
    badge("recycle", "#94A3B8", "#475569", draw_recycle)
    badge("search", "#6366F1", "#4338CA", draw_search)
    badge("sync", "#14B8A6", "#0F766E", draw_sync)
    badge("transfers", "#3B82F6", "#1D4ED8", draw_transfers)
    badge("inspector", "#0EA5E9", "#0369A1", draw_inspector)
    badge("chrome", "#8B5CF6", "#6D28D9", draw_chrome)
    badge("dualpane", "#3B82F6", "#1E3A8A", draw_dualpane)
    badge("grid", "#64748B", "#334155", draw_grid)
    badge("more", "#64748B", "#1E293B", draw_more)
    badge("sun", "#F59E0B", "#D97706", draw_sun)
    badge("dropstack", "#F97316", "#C2410C", draw_dropstack)
    badge("queue", "#F59E0B", "#B45309", draw_queue)
    badge("shelves", "#A78BFA", "#6D28D9", draw_shelves)
    badge("cleanup", "#F43F5E", "#BE123C", draw_cleanup)
    badge("duplicates", "#38BDF8", "#0284C7", draw_duplicates)
    badge("timeline", "#34D399", "#059669", draw_timeline)
    badge("workspaces", "#FBBF24", "#D97706", draw_workspaces)
    badge("brand", "#007AFF", "#0051D5", draw_brand)
    badge("xfer-pill", "#14B8A6", "#0F766E", draw_transfers)
    badge("rail-home", "#14B8A6", "#0F766E", draw_home)
    badge("rail-search", "#14B8A6", "#0F766E", draw_search)
    badge("rail-sync", "#14B8A6", "#0F766E", draw_sync)
    badge("rail-xfer", "#14B8A6", "#0F766E", draw_transfers)
    badge("rail-prefs", "#14B8A6", "#0F766E", draw_gear)
    badge("prefs", "#64748B", "#334155", draw_gear)
    badge("chrome-radar", "#007AFF", "#003D99", draw_brand)
    badge("chrome-preview", "#0EA5E9", "#075985", draw_inspector)
    badge("chrome-rail", "#14B8A6", "#115E59", draw_dualpane)
    badge("chrome-tabs", "#F59E0B", "#92400E", draw_workspaces)
    badge_moon()
    print("TOTAL", len([f for f in os.listdir(OUT) if f.endswith(".png")]))


if __name__ == "__main__":
    main()
