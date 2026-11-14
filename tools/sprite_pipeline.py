"""Stellar TD 2D sprite pipeline (docs/game/design/pivot-2d.md section 6.2).

Turns big Qwen-Image RGBA drawings into game sprites that all follow the same rules: one pixel density, one master
palette, a 1 px outline and a separate drop shadow made by this tool (not by the image model), so every sprite
matches every other one.

Commands (python -I tools/sprite_pipeline.py <cmd> ...):
  palette  IMG [IMG...] --colors 56 --out pal.png     master palette (one row of 1x1 swatches) from chosen art
  sprite   IN --size 64x80 --out OUT.png [--palette pal.png] [--no-outline] [--no-shadow]
                                                       trim, fit, downscale, quantise, outline, shadow
  texture  IN --size 64 --out OUT.png [--palette pal.png]
                                                       tileable ground texture at tile resolution (wraps)
  dualgrid A.png B.png --tile 32 --out OUT.png [--seed 1]
                                                       16-tile dual-grid transition set between two textures
  cliff    --palette pal.png --tile 32 --level-px 8 --out OUT.png [--base "#7a6a58"]
                                                       cliff face strip (strata bands) for one level drop
  lit      IN --out-dir DIR [--bevel 6] [--detail 1.0] [--strength 2.0]
                                                       normal map (+ emissive mask) for a sprite or tile, for
                                                       Godot CanvasTexture lighting (pivot-2d.md D11)
  sheet    IMG [IMG...] --out contact.png [--scale 4]  contact sheet for review (nearest upscale, labels)
  selftest                                             runs every command on generated input
"""
from __future__ import annotations

import argparse
import math
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ALPHA_CUT = 128          # alpha below this becomes fully transparent, above fully opaque (1-bit alpha)
OUTLINE_DARKEN = 0.35    # outline colour = neighbour colour x this, then snapped to the palette
SHADOW_OFFSET = (3, 3)   # px, bottom-right (light from top-left, art rules)
SHADOW_ALPHA = 90


# --- palette -------------------------------------------------------------------------------------------------

def load_palette(path: str | None) -> np.ndarray | None:
    if not path:
        return None
    img = Image.open(path).convert("RGBA")
    px = np.array(img).reshape(-1, 4)
    px = px[px[:, 3] > 0][:, :3]
    uniq = np.unique(px, axis=0)
    return uniq.astype(np.float32)


def _to_lab_like(rgb: np.ndarray) -> np.ndarray:
    # Cheap perceptual weighting (redmean-ish): good enough to pick the nearest palette entry.
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return np.stack([r * 0.30, g * 0.59, b * 0.11, (r - g) * 0.25, (g - b) * 0.25], axis=-1)


def snap(rgb: np.ndarray, pal: np.ndarray | None) -> np.ndarray:
    """Every pixel to its nearest palette colour (no dithering)."""
    if pal is None:
        return rgb
    flat = rgb.reshape(-1, 3).astype(np.float32)
    a = _to_lab_like(flat)[:, None, :]
    p = _to_lab_like(pal)[None, :, :]
    idx = np.argmin(((a - p) ** 2).sum(-1), axis=1)
    return pal[idx].reshape(rgb.shape).astype(np.uint8)


def cmd_palette(args) -> None:
    pixels = []
    for f in args.images:
        im = Image.open(f).convert("RGBA")
        im.thumbnail((512, 512))
        a = np.array(im).reshape(-1, 4)
        pixels.append(a[a[:, 3] > 128][:, :3])
    allpx = np.concatenate(pixels)
    side = int(math.ceil(math.sqrt(len(allpx))))
    pad = np.zeros((side * side - len(allpx), 3), np.uint8)
    img = Image.fromarray(np.concatenate([allpx, pad]).reshape(side, side, 3).astype(np.uint8), "RGB")
    q = img.quantize(colors=args.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    cols = np.array(q.getpalette()[: args.colors * 3], np.uint8).reshape(-1, 3)
    # sort by luminance so the strip reads dark -> light
    cols = cols[np.argsort(cols @ np.array([0.299, 0.587, 0.114]))]
    out = Image.fromarray(cols.reshape(1, -1, 3), "RGB")
    out.save(args.out)
    print(f"palette: {len(cols)} colours -> {args.out}")


# --- sprite --------------------------------------------------------------------------------------------------

def _trim(img: Image.Image) -> Image.Image:
    bbox = img.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0).getbbox()
    return img.crop(bbox) if bbox else img


def _fit(img: Image.Image, w: int, h: int) -> Image.Image:
    """Downscale to fit inside w x h keeping aspect (box filter: averages, no ringing), bottom-centred."""
    s = min(w / img.width, h / img.height)
    nw, nh = max(1, round(img.width * s)), max(1, round(img.height * s))
    # premultiply so transparent pixels don't bleed their colour into the edge
    a = np.array(img).astype(np.float32)
    a[..., :3] *= a[..., 3:4] / 255.0
    small = Image.fromarray(a.astype(np.uint8), "RGBA").resize((nw, nh), Image.Resampling.BOX)
    b = np.array(small).astype(np.float32)
    al = np.maximum(b[..., 3:4], 1.0)
    b[..., :3] = np.clip(b[..., :3] * 255.0 / al, 0, 255)
    small = Image.fromarray(b.astype(np.uint8), "RGBA")
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.paste(small, ((w - nw) // 2, h - nh))
    return canvas


def _outline(rgba: np.ndarray, pal: np.ndarray | None) -> np.ndarray:
    solid = rgba[..., 3] > 0
    h, w = solid.shape
    out = rgba.copy()
    grown = np.zeros_like(solid)
    src_col = np.zeros((h, w, 3), np.float32)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        sh = np.zeros_like(solid)
        ys, yd = (slice(max(dy, 0), h + min(dy, 0)), slice(max(-dy, 0), h + min(-dy, 0)))
        xs, xd = (slice(max(dx, 0), w + min(dx, 0)), slice(max(-dx, 0), w + min(-dx, 0)))
        sh[yd, xd] = solid[ys, xs]
        newly = sh & ~solid & ~grown
        c = np.zeros((h, w, 3), np.float32)
        c[yd, xd] = rgba[ys, xs, :3]
        src_col[newly] = c[newly]
        grown |= newly
    col = (src_col * OUTLINE_DARKEN).astype(np.uint8)
    if pal is not None:
        col = snap(col, pal)
    out[grown, :3] = col[grown]
    out[grown, 3] = 255
    return out


def _shadow(rgba: np.ndarray) -> np.ndarray:
    h, w = rgba.shape[:2]
    ox, oy = SHADOW_OFFSET
    sh = np.zeros((h + oy, w + ox, 4), np.uint8)
    sh[oy:, ox:, 3] = np.where(rgba[..., 3] > 0, SHADOW_ALPHA, 0)
    return sh


def make_sprite(src: Image.Image, w: int, h: int, pal: np.ndarray | None, outline: bool = True) -> np.ndarray:
    img = _fit(_trim(src.convert("RGBA")), w - 2 if outline else w, h - 2 if outline else h)
    if outline:
        pad = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        pad.paste(img, (1, 1))
        img = pad
    a = np.array(img)
    a[..., 3] = np.where(a[..., 3] >= ALPHA_CUT, 255, 0)
    a[..., :3] = snap(a[..., :3], pal)
    a[a[..., 3] == 0, :3] = 0
    if outline:
        a = _outline(a, pal)
    return a


def cmd_sprite(args) -> None:
    w, h = (int(v) for v in args.size.lower().split("x"))
    pal = load_palette(args.palette)
    a = make_sprite(Image.open(args.input), w, h, pal, not args.no_outline)
    Image.fromarray(a, "RGBA").save(args.out)
    msg = f"sprite: {args.out} {w}x{h}"
    if not args.no_shadow:
        sp = Path(args.out).with_name(Path(args.out).stem + "_shadow.png")
        Image.fromarray(_shadow(a), "RGBA").save(sp)
        msg += f" (+ {sp.name})"
    print(msg)


# --- textures and tiles --------------------------------------------------------------------------------------

def make_texture(src: Image.Image, size: int, pal: np.ndarray | None) -> np.ndarray:
    im = src.convert("RGB")
    s = min(im.width, im.height)
    im = im.crop(((im.width - s) // 2, (im.height - s) // 2, (im.width + s) // 2, (im.height + s) // 2))
    # make it wrap: blend with a half-shifted copy across a soft cross (classic offset-blend seam fix)
    a = np.array(im).astype(np.float32)
    shifted = np.roll(np.roll(a, s // 2, 0), s // 2, 1)
    yy, xx = np.mgrid[0:s, 0:s]
    d = np.minimum(np.minimum(xx, s - 1 - xx), np.minimum(yy, s - 1 - yy)) / (s * 0.25)
    wgt = np.clip(d, 0, 1)[..., None]
    mixed = a * wgt + shifted * (1 - wgt)
    small = Image.fromarray(mixed.astype(np.uint8)).resize((size, size), Image.Resampling.BOX)
    return snap(np.array(small), pal)


def cmd_texture(args) -> None:
    t = make_texture(Image.open(args.input), args.size, load_palette(args.palette))
    Image.fromarray(t, "RGB").save(args.out)
    print(f"texture: {args.out} {args.size}x{args.size} (wraps)")


def _value_noise(w: int, h: int, cell: int, rng: random.Random) -> np.ndarray:
    gw, gh = w // cell + 2, h // cell + 2
    g = np.array([[rng.random() for _ in range(gw)] for _ in range(gh)], np.float32)
    yy, xx = np.mgrid[0:h, 0:w] / cell
    x0, y0 = xx.astype(int), yy.astype(int)
    fx, fy = xx - x0, yy - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = g[y0, x0] * (1 - fx) + g[y0, x0 + 1] * fx
    b = g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def cmd_dualgrid(args) -> None:
    """16 tiles; tile index = TL*8 + TR*4 + BL*2 + BR (1 = texture B at that corner). Dual-grid: display tiles
    sit half a tile off the data grid, so 16 tiles cover every corner combination (no 47-tile blob needed)."""
    t = args.tile
    ta = np.array(Image.open(args.a).convert("RGB").resize((t, t), Image.Resampling.NEAREST))
    tb = np.array(Image.open(args.b).convert("RGB").resize((t, t), Image.Resampling.NEAREST))
    rng = random.Random(args.seed)
    sheet = np.zeros((t * 4, t * 4, 3), np.uint8)
    yy, xx = np.mgrid[0:t, 0:t] / (t - 1)
    for idx in range(16):
        tl, tr, bl, br = (idx >> 3) & 1, (idx >> 2) & 1, (idx >> 1) & 1, idx & 1
        # bilinear corner weight for B, roughened with noise so the border is not a straight line
        wb = (tl * (1 - xx) * (1 - yy) + tr * xx * (1 - yy) + bl * (1 - xx) * yy + br * xx * yy)
        n = _value_noise(t, t, max(4, t // 4), rng) - 0.5
        mask = (wb + n * 0.35) > 0.5
        tile = np.where(mask[..., None], tb, ta)
        r, c = divmod(idx, 4)
        sheet[r * t:(r + 1) * t, c * t:(c + 1) * t] = tile
    Image.fromarray(sheet, "RGB").save(args.out)
    print(f"dualgrid: {args.out} 16 tiles of {t}px (index = TL*8+TR*4+BL*2+BR)")


def cmd_cliff(args) -> None:
    """A cliff face strip: tile wide, level_px tall per level drop, horizontal strata bands from the palette."""
    pal = load_palette(args.palette)
    base = np.array([int(args.base[i:i + 2], 16) for i in (1, 3, 5)], np.float32)
    t, hpx = args.tile, args.level_px
    rng = random.Random(7)
    rows = []
    for y in range(hpx):
        shade = 0.55 + 0.35 * (1 - y / max(hpx - 1, 1))          # lit lip at the top, dark at the foot
        band = 0.9 + 0.2 * math.sin(y * 2.1 + 0.5)                   # strata
        row = np.tile(base * shade * band, (t * 4, 1))
        for x in range(t * 4):
            row[x] *= 0.92 + 0.16 * rng.random()
        rows.append(row)
    a = np.clip(np.array(rows), 0, 255).astype(np.uint8)
    a[0, :] = np.clip(base * 1.15, 0, 255)                            # edge highlight
    a = snap(a, pal)
    Image.fromarray(a, "RGB").save(args.out)
    print(f"cliff: {args.out} {t * 4}x{hpx} (4 tile widths, tile seamlessly)")


# --- lighting maps (normal + emissive) -----------------------------------------------------------------------

def _distance_inside(solid: np.ndarray, cap: int) -> np.ndarray:
    """Steps from each solid pixel to the nearest edge (4-neighbour erosion), capped. Cheap and good enough for a
    bevel on sprites a few hundred px wide."""
    d = np.zeros(solid.shape, np.float32)
    cur = solid.copy()
    for k in range(1, cap + 1):
        er = cur.copy()
        er[1:, :] &= cur[:-1, :]
        er[:-1, :] &= cur[1:, :]
        er[:, 1:] &= cur[:, :-1]
        er[:, :-1] &= cur[:, 1:]
        er[0, :] = er[-1, :] = False
        er[:, 0] = er[:, -1] = False
        d[cur] = k
        cur = er
        if not cur.any():
            break
    d[cur] = cap
    return d


def make_normal(rgba: np.ndarray, bevel: int, detail: float, strength: float, wrap: bool = False) -> np.ndarray:
    """Tangent-space normal map. Height = rounded bevel from the silhouette (so panels and modules read as raised
    forms under a moving light) + fine relief from albedo luminance (seams, bolts, grime). Godot 2D normal maps use
    green = up (+Y) in texture space, which is what this writes."""
    a = rgba[..., 3] > 0 if rgba.shape[-1] == 4 else np.ones(rgba.shape[:2], bool)
    lum = (rgba[..., :3].astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)) / 255.0
    if wrap or a.all():
        h_shape = np.zeros(a.shape, np.float32)
    else:
        d = _distance_inside(a, bevel)
        h_shape = np.sin(np.clip(d / max(bevel, 1), 0, 1) * (math.pi / 2))      # rounded edge profile
    # luminance detail, high-passed so big colour areas don't tilt whole panels
    blur = lum.copy()
    for _ in range(3):
        blur = (np.roll(blur, 1, 0) + np.roll(blur, -1, 0) + np.roll(blur, 1, 1) + np.roll(blur, -1, 1) + blur) / 5
    h = h_shape + (lum - blur) * detail
    if wrap:
        gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    else:
        hp = np.pad(h, 1, mode="edge")
        gx = (hp[1:-1, 2:] - hp[1:-1, :-2]) * 0.5
        gy = (hp[2:, 1:-1] - hp[:-2, 1:-1]) * 0.5
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)    # image y grows down; +green = up
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], -1)
    out = np.zeros((*h.shape, 4), np.uint8)
    out[..., :3] = ((n * 0.5 + 0.5) * 255).astype(np.uint8)
    out[..., 3] = 255 if wrap else np.where(a, 255, 0)
    return out


def make_emissive(rgba: np.ndarray, min_value: float = 0.85, min_sat: float = 0.45) -> np.ndarray:
    """Glow mask: bright, saturated pixels (windows, furnace mouths, status lights). White on black."""
    rgb = rgba[..., :3].astype(np.float32) / 255.0
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    m = (mx >= min_value) & (sat >= min_sat)
    if rgba.shape[-1] == 4:
        m &= rgba[..., 3] > 0
    out = np.zeros((*m.shape, 4), np.uint8)
    out[..., :3][m] = rgba[..., :3][m]
    out[..., 3][m] = 255
    return out


def cmd_lit(args) -> None:
    src = np.array(Image.open(args.input).convert("RGBA"))
    stem = Path(args.input).stem
    od = Path(args.out_dir)
    od.mkdir(parents=True, exist_ok=True)
    wrap = bool(args.wrap)
    Image.fromarray(make_normal(src, args.bevel, args.detail, args.strength, wrap), "RGBA").save(od / f"{stem}_n.png")
    em = make_emissive(src)
    msg = f"lit: {od / (stem + '_n.png')}"
    if em[..., 3].any():
        Image.fromarray(em, "RGBA").save(od / f"{stem}_e.png")
        msg += f" + {stem}_e.png ({int((em[..., 3] > 0).sum())} glowing px)"
    print(msg)


# --- review --------------------------------------------------------------------------------------------------

def cmd_sheet(args) -> None:
    ims = [(Path(f).stem, Image.open(f).convert("RGBA")) for f in args.images]
    cell = max(max(i.width, i.height) for _, i in ims) * args.scale + 16
    cols = max(1, min(len(ims), args.cols))
    rows = math.ceil(len(ims) / cols)
    out = Image.new("RGBA", (cols * cell, rows * (cell + 14)), (40, 40, 46, 255))
    d = ImageDraw.Draw(out)
    for k, (name, im) in enumerate(ims):
        big = im.resize((im.width * args.scale, im.height * args.scale), Image.Resampling.NEAREST)
        r, c = divmod(k, cols)
        x, y = c * cell + 8, r * (cell + 14) + 8
        out.alpha_composite(big, (x, y))
        d.text((x, y + big.height + 2), name[:40], fill=(220, 220, 220, 255))
    out.save(args.out)
    print(f"sheet: {args.out} ({len(ims)} images)")


# --- selftest ------------------------------------------------------------------------------------------------

def cmd_selftest(_args) -> None:
    import tempfile
    tmp = Path(tempfile.mkdtemp(prefix="sprite_pipe_"))
    big = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.rectangle((300, 200, 724, 900), fill=(180, 90, 40, 255))
    d.ellipse((380, 260, 640, 520), fill=(240, 200, 60, 255))
    big.save(tmp / "src.png")
    tex = Image.fromarray((np.random.default_rng(1).random((512, 512, 3)) * 255).astype(np.uint8))
    tex.save(tmp / "tex.png")
    Image.new("RGB", (512, 512), (90, 140, 70)).save(tmp / "tex_b.png")
    fails = 0

    def check(ok: bool, what: str) -> None:
        nonlocal fails
        print(("PASS " if ok else "FAIL ") + what)
        fails += 0 if ok else 1

    run = lambda argv: main(argv)  # noqa: E731
    run(["palette", str(tmp / "src.png"), str(tmp / "tex.png"), "--colors", "16", "--out", str(tmp / "pal.png")])
    pal = load_palette(str(tmp / "pal.png"))
    check(pal is not None and 2 <= len(pal) <= 16, f"palette has 2..16 colours ({0 if pal is None else len(pal)})")
    run(["sprite", str(tmp / "src.png"), "--size", "64x80", "--out", str(tmp / "spr.png"), "--palette", str(tmp / "pal.png")])
    s = np.array(Image.open(tmp / "spr.png"))
    check(s.shape[:2] == (80, 64), "sprite is 64x80")
    check(set(np.unique(s[..., 3])) <= {0, 255}, "sprite alpha is 1-bit")
    opaque = s[s[..., 3] == 255][:, :3]
    pal_set = {tuple(c) for c in pal.astype(np.uint8)}
    check(all(tuple(c) in pal_set for c in opaque), "every opaque pixel is a palette colour")
    check(s[0, :, 3].max() == 0 or s[:, 0, 3].max() == 0, "outline stays inside the canvas")
    check((tmp / "spr_shadow.png").exists(), "shadow written")
    run(["texture", str(tmp / "tex.png"), "--size", "64", "--out", str(tmp / "t.png"), "--palette", str(tmp / "pal.png")])
    t = np.array(Image.open(tmp / "t.png")).astype(int)
    seam = np.abs(t[:, 0] - t[:, -1]).mean()
    inner = np.abs(t[:, 31] - t[:, 32]).mean()
    check(seam <= inner * 1.6 + 8, f"texture wraps (edge diff {seam:.0f} vs inner {inner:.0f})")
    run(["dualgrid", str(tmp / "tex.png"), str(tmp / "tex_b.png"), "--tile", "32", "--out", str(tmp / "dg.png")])
    dg = np.array(Image.open(tmp / "dg.png"))
    check(dg.shape[:2] == (128, 128), "dual-grid sheet 4x4 of 32 px")
    check((dg[0:32, 0:32] != [90, 140, 70]).any() and (dg[96:128, 96:128] == [90, 140, 70]).all(),
          "tile 0 is all A, tile 15 all B")
    run(["cliff", "--palette", str(tmp / "pal.png"), "--tile", "32", "--level-px", "8", "--out", str(tmp / "c.png")])
    check(Image.open(tmp / "c.png").size == (128, 8), "cliff strip 128x8")
    run(["lit", str(tmp / "spr.png"), "--out-dir", str(tmp)])
    nm = np.array(Image.open(tmp / "spr_n.png")).astype(int)
    solid = s[..., 3] > 0
    check(nm.shape[:2] == s.shape[:2], "normal map same size as sprite")
    flat_ok = abs(nm[solid][:, 2].mean() - 255) < 80
    check(flat_ok, f"normals mostly face the viewer (mean blue {nm[solid][:, 2].mean():.0f})")
    left_edge = nm[40, np.argmax(solid[40])][0]
    right_edge = nm[40, len(solid[40]) - 1 - np.argmax(solid[40][::-1])][0]
    check(left_edge < 128 < right_edge, f"bevel tilts edges outward (left R {left_edge}, right R {right_edge})")
    glow = Image.new("RGBA", (32, 32), (60, 60, 60, 255)); ImageDraw.Draw(glow).rectangle((10, 10, 20, 20), fill=(255, 170, 40, 255)); glow.save(tmp / "glow.png")
    run(["lit", str(tmp / "glow.png"), "--out-dir", str(tmp)])
    check((tmp / "glow_e.png").exists() and np.array(Image.open(tmp / "glow_e.png"))[15, 15, 3] == 255, "emissive mask catches the glowing window")
    run(["sheet", str(tmp / "spr.png"), str(tmp / "dg.png"), "--out", str(tmp / "sheet.png")])
    check((tmp / "sheet.png").exists(), "contact sheet written")
    print(f"SELFTEST DONE fails={fails}  ({tmp})")
    sys.exit(1 if fails else 0)


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("palette"); p.add_argument("images", nargs="+"); p.add_argument("--colors", type=int, default=56); p.add_argument("--out", required=True); p.set_defaults(fn=cmd_palette)
    p = sub.add_parser("sprite"); p.add_argument("input"); p.add_argument("--size", required=True); p.add_argument("--out", required=True); p.add_argument("--palette"); p.add_argument("--no-outline", action="store_true"); p.add_argument("--no-shadow", action="store_true"); p.set_defaults(fn=cmd_sprite)
    p = sub.add_parser("texture"); p.add_argument("input"); p.add_argument("--size", type=int, default=64); p.add_argument("--out", required=True); p.add_argument("--palette"); p.set_defaults(fn=cmd_texture)
    p = sub.add_parser("dualgrid"); p.add_argument("a"); p.add_argument("b"); p.add_argument("--tile", type=int, default=32); p.add_argument("--out", required=True); p.add_argument("--seed", type=int, default=1); p.set_defaults(fn=cmd_dualgrid)
    p = sub.add_parser("cliff"); p.add_argument("--palette"); p.add_argument("--tile", type=int, default=32); p.add_argument("--level-px", type=int, default=8); p.add_argument("--base", default="#7a6a58"); p.add_argument("--out", required=True); p.set_defaults(fn=cmd_cliff)
    p = sub.add_parser("lit"); p.add_argument("input"); p.add_argument("--out-dir", required=True); p.add_argument("--bevel", type=int, default=6); p.add_argument("--detail", type=float, default=1.0); p.add_argument("--strength", type=float, default=2.0); p.add_argument("--wrap", action="store_true", help="tileable texture: wrap edges, no silhouette bevel"); p.set_defaults(fn=cmd_lit)
    p = sub.add_parser("sheet"); p.add_argument("images", nargs="+"); p.add_argument("--out", required=True); p.add_argument("--scale", type=int, default=4); p.add_argument("--cols", type=int, default=6); p.set_defaults(fn=cmd_sheet)
    p = sub.add_parser("selftest"); p.set_defaults(fn=cmd_selftest)
    a = ap.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
