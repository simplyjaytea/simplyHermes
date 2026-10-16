#!/usr/bin/env python3
"""Build every AppIcon PNG from one square artwork file.

Usage: python3 tools/app-icon/make_app_icon.py ARTWORK.png
Needs numpy, scipy and Pillow. Writes into App/HermesApp/Assets.xcassets/AppIcon.appiconset.

The artwork is a white winged bubble holding a navy portrait on a vertical blue gradient.
- Light: the artwork at 1024 px, full bleed, no alpha.
- Dark: the bubble lifted off the blue gradient and put on a near-black gradient.
- Tinted: the bubble's luminance on a transparent background.
- Sizes up to 87 px (notifications, Settings, Spotlight) use a simplified mark: the white
  hair highlights and eye whites are filled and the eyes and lip mark are thickened, so the
  face still reads when it is a few pixels wide.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

OUT = Path(__file__).resolve().parents[2] / "App/HermesApp/Assets.xcassets/AppIcon.appiconset"
SIZE = 1024
NAVY = np.array([3, 48, 122], np.float32)
WHITE = np.full(3, 255, np.float32)
DARK_TOP, DARK_BOTTOM = np.array([24, 29, 40], np.float32), np.array([6, 8, 12], np.float32)
SIMPLIFY_MAX_PX = 87
# Features to thicken in the simplified mark, as (y0, y1, x0, x1) boxes in 1024 px coordinates:
# the eyes and the lip mark. The nose is left alone; thickened, it reads as a bruise.
FEATURE_BOXES = [(430, 495, 260, 420), (550, 580, 285, 320)]
# iOS "All Sizes" slots: (points, scales).
SLOTS = [("20", (2, 3)), ("29", (2, 3)), ("38", (2, 3)), ("40", (2, 3)), ("60", (2, 3)),
         ("64", (2, 3)), ("68", (2,)), ("76", (2,)), ("83.5", (2,))]
APPEARANCES = [("", None), ("-Dark", "dark"), ("-Tinted", "tinted")]


def luminance(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def variants(light):
    """Return the light, dark and tinted 1024 px arrays, plus the bubble's alpha."""
    p = light.astype(np.float32)
    # The background is a vertical gradient: sample both edge columns on each row.
    bg = ((p[:, :4].mean(1) + p[:, -4:].mean(1)) / 2)[:, None, :].repeat(SIZE, 1)
    d = WHITE - bg
    a = np.clip(((p - bg) * d).sum(2) / (d * d).sum(2), 0, 1)
    # Flood the background from a corner over low-alpha pixels; everything else is the bubble.
    lab, _ = ndi.label(a < 0.5)
    outside = lab == lab[0, 0]
    band = ndi.binary_dilation(outside, iterations=3)
    alpha = np.where(band, a, 1.0)
    alpha[outside & (a < 0.06)] = 0  # drops the artwork's faint background texture
    fg = np.clip((p - bg * (1 - alpha[..., None])) / np.maximum(alpha, 1e-3)[..., None], 0, 255)
    t = np.linspace(0, 1, SIZE)[:, None, None]
    dark_bg = (DARK_TOP * (1 - t) + DARK_BOTTOM * t).repeat(SIZE, 1)
    dark = fg * alpha[..., None] + dark_bg * (1 - alpha[..., None])
    lum = luminance(fg)
    tinted = np.dstack([lum, lum, lum, alpha * 255])
    return p, dark, tinted, alpha


def simplify(images, light, alpha):
    """Fill small white islands and thicken the eyes and lips inside the bubble."""
    inside = ndi.binary_erosion(alpha > 0.98, iterations=6)
    dv = WHITE - NAVY
    n = np.clip(((WHITE - light) * dv).sum(2) / (dv * dv).sum(), 0, 1) * inside
    ink = n > 0.5
    lab, k = ndi.label(~ink & inside)
    sizes = ndi.sum(np.ones_like(lab), lab, range(1, k + 1))
    white_islands = np.isin(lab, 1 + np.nonzero(sizes < 4000)[0])
    lab, k = ndi.label(ink)
    sizes = ndi.sum(np.ones_like(lab), lab, range(1, k + 1))
    centres = ndi.center_of_mass(ink, lab, range(1, k + 1))
    keep = [i + 1 for i, (c, s) in enumerate(zip(centres, sizes))
            if 10 <= s < 4000 and any(y0 <= c[0] < y1 and x0 <= c[1] < x1 for y0, y1, x0, x1 in FEATURE_BOXES)]
    yy, xx = np.mgrid[-9:10, -9:10]
    features = ndi.binary_dilation(np.isin(lab, keep), structure=xx * xx + yy * yy <= 81) & inside
    target = np.maximum(n, (white_islands | features).astype(np.float32))
    target = ndi.gaussian_filter(target, 1.0) * inside + n * ~inside
    mix = (np.clip(target - n, 0, 1) / np.maximum(1 - n, 1e-3))[..., None]
    out = []
    for img, ink_rgb in zip(images, (NAVY, NAVY, np.full(3, luminance(NAVY)))):
        img = img.copy()
        img[..., :3] = img[..., :3] * (1 - mix) + ink_rgb * mix
        out.append(img)
    return out


def save(arr, path, px):
    mode = "RGBA" if arr.shape[2] == 4 else "RGB"
    img = Image.fromarray(np.clip(arr, 0, 255).round().astype(np.uint8), mode)
    if px != SIZE:
        img = img.resize((px, px), Image.LANCZOS)
    img.save(path, optimize=True)


def main():
    art = Image.open(sys.argv[1]).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    light, dark, tinted, alpha = variants(np.asarray(art))
    full = [light, dark, tinted]
    small = simplify(full, light, alpha)
    for old in OUT.glob("AppIcon*.png"):
        old.unlink()
    images = []
    for (suffix, appearance), big, little in zip(APPEARANCES, full, small):
        save(big, OUT / f"AppIcon{suffix}.png", SIZE)
        entry = {"filename": f"AppIcon{suffix}.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        images.append(entry)
        for points, scales in SLOTS:
            for scale in scales:
                px = round(float(points) * scale)
                name = f"AppIcon{suffix}-{px}.png"
                if not (OUT / name).exists():
                    save(little if px <= SIMPLIFY_MAX_PX else big, OUT / name, px)
                slot = {"filename": name, "idiom": "universal", "platform": "ios",
                        "scale": f"{scale}x", "size": f"{points}x{points}"}
                if appearance:
                    slot = {"appearances": [{"appearance": "luminosity", "value": appearance}], **slot}
                images.append(slot)
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (OUT / "Contents.json").write_text(json.dumps(contents, indent=2, separators=(",", " : ")) + "\n")


if __name__ == "__main__":
    main()
