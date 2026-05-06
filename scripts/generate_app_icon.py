#!/usr/bin/env python3
"""Build AppIcon.icns and MenuBarTemplate.png from edgepad.png."""

from __future__ import annotations

import math
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

# macOS iconset required filenames → edge length in pixels
ICONSET_SIZES: list[tuple[str, int]] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def _border_mean_luma(rgb: Image.Image) -> float:
    a = rgb.load()
    w, h = rgb.size
    total = 0.0
    n = 0
    for x in range(w):
        total += sum(a[x, 0]) + sum(a[x, h - 1])
        n += 6
    for y in range(h):
        total += sum(a[0, y]) + sum(a[w - 1, y])
        n += 6
    return total / n


def light_bg_to_white_rgba(src: Image.Image, bg_cutoff: float = 248.0) -> Image.Image:
    """Assume dark glyph on near-white background; emit pure white with alpha."""
    rgb = src.convert("RGB")
    pix = rgb.load()
    w, h = rgb.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opix = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = pix[x, y]
            L = (r + g + b) / 3.0
            if L >= bg_cutoff:
                continue
            inv = max(0.0, (bg_cutoff - L) / bg_cutoff)
            alpha = int(min(255, round(255.0 * math.pow(inv, 0.85))))
            opix[x, y] = (255, 255, 255, alpha)
    return out


def dark_bg_to_white_rgba(src: Image.Image, fg_threshold: float = 200.0) -> Image.Image:
    """Light glyph on dark background (e.g. blue): bright pixels → white with alpha."""
    rgb = src.convert("RGB")
    pix = rgb.load()
    w, h = rgb.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    opix = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = pix[x, y]
            L = (r + g + b) / 3.0
            if L <= fg_threshold - 55:
                continue
            strength = min(1.0, max(0.0, (L - (fg_threshold - 55)) / (255.0 - (fg_threshold - 55))))
            alpha = int(round(255.0 * math.pow(strength, 0.9)))
            opix[x, y] = (255, 255, 255, alpha)
    return out


def rgba_to_white_on_transparent(src: Image.Image) -> Image.Image:
    border = _border_mean_luma(src.convert("RGB"))
    if border > 200.0:
        return light_bg_to_white_rgba(src)
    return dark_bg_to_white_rgba(src)


def crop_to_glyph(im: Image.Image, alpha_floor: int = 8) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return im
    # Shrink bbox to pixels with meaningful alpha
    a = im.split()[-1]
    bbox2 = a.point(lambda p: 255 if p > alpha_floor else 0).getbbox()
    if bbox2:
        return im.crop(bbox2)
    return im.crop(bbox)


def pad_square(im: Image.Image, pad_ratio: float = 0.12) -> Image.Image:
    w, h = im.size
    side = max(w, h)
    pad = int(round(side * pad_ratio))
    side += 2 * pad
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ox = (side - w) // 2
    oy = (side - h) // 2
    canvas.paste(im, (ox, oy), im)
    return canvas


def write_iconset(master: Image.Image, iconset_dir: Path) -> None:
    iconset_dir.mkdir(parents=True, exist_ok=True)
    for name, edge in ICONSET_SIZES:
        resized = master.resize((edge, edge), Image.Resampling.LANCZOS)
        resized.save(iconset_dir / name, format="PNG")


def white_rgba_to_template_black(rgba: Image.Image) -> Image.Image:
    """Menu bar / template images: solid black RGB, same alpha (HIG)."""
    alpha = rgba.split()[-1]
    black = Image.new("L", rgba.size, 0)
    return Image.merge("RGBA", (black, black, black, alpha))


def main() -> int:
    repo = Path(__file__).resolve().parents[1]
    src_png = repo / "Resources" / "edgepad.png"
    out_icns = repo / "Resources" / "AppIcon.icns"
    out_menubar = repo / "Resources" / "MenuBarTemplate.png"
    if not src_png.is_file():
        print(f"[generate_app_icon] missing source: {src_png}", file=sys.stderr)
        return 1

    raw = Image.open(src_png)
    rgba = rgba_to_white_on_transparent(raw)
    glyph = crop_to_glyph(rgba)

    # App icon: 12% padding looks right on the dock (lots of headroom there).
    app_square = pad_square(glyph, pad_ratio=0.12)
    master = app_square.resize((1024, 1024), Image.Resampling.LANCZOS)

    out_icns.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        write_iconset(master, iconset)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(out_icns)],
            check=True,
        )
    print(f"[generate_app_icon] wrote {out_icns}")

    # Menu bar template: 22pt tall, @2x = 44px. Light padding (8%) so the
    # glyph fills the bar height — Apple's HIG status icons sit close to the
    # full bar height with just enough breathing room to not touch the edges.
    mb_square = pad_square(glyph, pad_ratio=0.08)
    mb = mb_square.resize((44, 44), Image.Resampling.LANCZOS)
    white_rgba_to_template_black(mb).save(out_menubar, format="PNG")
    print(f"[generate_app_icon] wrote {out_menubar}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
