#!/usr/bin/env python
"""Offline planet heightmap baker: fBm base + real hydraulic erosion.

WHY THIS IS OFFLINE AND NOT IN THE GENERATOR
--------------------------------------------
Hydraulic erosion is iterative and non-local: a droplet's path depends on
every cell it has already crossed, and a drainage network only emerges after
tens of thousands of droplets have run over the whole map. That cannot be
evaluated per-block on demand, which is exactly why no amount of layered noise
reproduces river valleys, talus slopes or dendritic drainage. It has to be
baked once per seed.

This is also what Space Engineers 2 does - VRAGE3 is heightmap-first (base map
at 1 px / 8 voxels plus a detail map reaching 1 px / voxel) with 3D voxel
detail layered on top for overhangs. See main-design.md.

PROJECTION
----------
Equirectangular, because godot_voxel's `SdfSphereHeightmap` node takes a
single Image for the whole sphere (verified: params are image/radius/factor,
inputs x/y/z). Two consequences the code handles explicitly:
  - longitude WRAPS, so erosion must wrap at the x edges or a seam appears
  - latitude does NOT wrap, and cells near the poles cover far less ground,
    so horizontal steps are scaled by cos(latitude)

Usage:
  python tools/bake_planet_heightmap.py --seed 1 --width 2048 --out data/heightmaps/home.png
"""

import argparse
import os
import numpy as np

# --------------------------------------------------------------------------
# Value-noise fBm on the sphere
# --------------------------------------------------------------------------


def _hash3(ix, iy, iz, seed):
    """Integer bit-mixing hash. Deliberately not a float product of
    coordinates - that loses precision with distance from the origin and
    degenerates into structured banding (the same bug that hit the terrain
    shader; see main-design.md)."""
    h = (ix * np.uint64(374761393)) ^ (iy * np.uint64(668265263)) ^ \
        (iz * np.uint64(1274126177)) ^ (np.uint64(seed) * np.uint64(2654435761))
    h = (h ^ (h >> np.uint64(13))) * np.uint64(1274126177)
    return ((h ^ (h >> np.uint64(16))) & np.uint64(0xFFFFFF)).astype(np.float64) / float(0xFFFFFF)


def _value_noise_3d(x, y, z, seed):
    x0, y0, z0 = np.floor(x), np.floor(y), np.floor(z)
    fx, fy, fz = x - x0, y - y0, z - z0
    # Smoothstep so octaves blend without visible lattice creases.
    fx, fy, fz = (fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz))

    ix = (x0.astype(np.int64) + 4096).astype(np.uint64)
    iy = (y0.astype(np.int64) + 4096).astype(np.uint64)
    iz = (z0.astype(np.int64) + 4096).astype(np.uint64)
    one = np.uint64(1)

    def h(dx, dy, dz):
        return _hash3(ix + np.uint64(dx), iy + np.uint64(dy), iz + np.uint64(dz), seed)

    c00 = h(0, 0, 0) * (1 - fx) + h(1, 0, 0) * fx
    c10 = h(0, 1, 0) * (1 - fx) + h(1, 1, 0) * fx
    c01 = h(0, 0, 1) * (1 - fx) + h(1, 0, 1) * fx
    c11 = h(0, 1, 1) * (1 - fx) + h(1, 1, 1) * fx
    c0 = c00 * (1 - fy) + c10 * fy
    c1 = c01 * (1 - fy) + c11 * fy
    return c0 * (1 - fz) + c1 * fz


def max_useful_frequency(width, min_pixels_per_feature=4.0):
    """Highest noise frequency this map resolution can actually represent.

    Noise sampled on a unit direction has a feature every 1/freq units, and the
    equator is 2*pi units around, so there are 2*pi*freq features across
    `width` pixels. Going past ~1 feature per 4 px aliases, and on an
    equirectangular map that alias shows up as regular stipple that no amount
    of erosion tuning removes - it is in the base field, not the erosion.
    """
    return width / (2.0 * np.pi * min_pixels_per_feature)


def fbm_sphere(dirs, seed, octaves=7, frequency=1.6, lacunarity=2.0, gain=0.5,
               ridged=False, max_frequency=None):
    """fBm sampled on the unit-sphere DIRECTION rather than on 2D image
    coordinates. This is what makes the map seamless around the planet - a 2D
    noise field would tear at the +-180 degree meridian."""
    total = np.zeros(dirs.shape[:-1], dtype=np.float64)
    norm = 0.0
    amp, freq = 1.0, frequency
    for o in range(octaves):
        # Stop before the octave stops being representable at this resolution.
        if max_frequency is not None and freq > max_frequency:
            break
        n = _value_noise_3d(dirs[..., 0] * freq, dirs[..., 1] * freq, dirs[..., 2] * freq, seed + o * 977)
        n = n * 2.0 - 1.0
        if ridged:
            # Smooth absolute value. Plain `1 - abs(n)` is C0 but not C1 at
            # n == 0 - a derivative discontinuity sitting exactly along every
            # ridge line, which erosion then amplifies into crinkle. The eps
            # rounds the corner without changing the overall ridge shape.
            n = 1.0 - np.sqrt(n * n + 0.0025)
            n = n * np.abs(n)
        total += n * amp
        norm += amp
        amp *= gain
        freq *= lacunarity
    return total / max(norm, 1e-9)


def equirect_directions(width, height):
    """Unit vectors for every pixel of an equirectangular map."""
    lon = (np.arange(width) + 0.5) / width * 2.0 * np.pi - np.pi
    lat = np.pi * 0.5 - (np.arange(height) + 0.5) / height * np.pi
    lon, lat = np.meshgrid(lon, lat)
    cl = np.cos(lat)
    return np.stack([cl * np.cos(lon), np.sin(lat), cl * np.sin(lon)], axis=-1), lat


# --------------------------------------------------------------------------
# Hydraulic erosion (droplet model)
# --------------------------------------------------------------------------


def erode(height, lat, droplets, seed,
          inertia=0.18, capacity=0.35, erosion=0.06, deposition=0.06,
          evaporation=0.015, gravity=1.5, min_slope=0.0008, max_steps=96,
          max_step_change=0.0015, brush_radius=2):
    """Droplet-based hydraulic erosion, vectorised over all droplets at once.

    Each droplet flows downhill carrying sediment; it erodes where it has
    spare capacity and deposits where it exceeds capacity or slows. Running
    them in lockstep as arrays is what makes this finish in seconds instead of
    hours - a per-droplet Python loop over 10^5 droplets is unusable.
    """
    h, w = height.shape
    rng = np.random.default_rng(seed)

    # Horizontal distance per pixel shrinks toward the poles on an equirect
    # map, so a droplet's step must shrink with it or polar regions erode as
    # though they were equatorial.
    lat_scale = np.clip(np.cos(lat), 0.35, 1.0)

    # Erosion strength tapers to zero across the polar caps. Without this the
    # 1/cos(lat) gradient amplification makes droplets carve violently in a
    # region that covers almost no actual ground, and it shows as horizontal
    # banding across the top and bottom of the map.
    pole_taper = np.clip((np.cos(lat) - 0.12) / 0.25, 0.0, 1.0)
    pole_taper = pole_taper * pole_taper * (3.0 - 2.0 * pole_taper)

    px = rng.uniform(0, w, droplets)
    # Spawn only outside the polar caps (~7% of rows at each end).
    cap = max(int(h * 0.07), 3)
    py = rng.uniform(cap, h - 1 - cap, droplets)
    dx = np.zeros(droplets)
    dy = np.zeros(droplets)
    speed = np.ones(droplets)
    water = np.ones(droplets)
    sediment = np.zeros(droplets)
    alive = np.ones(droplets, dtype=bool)

    def sample_bilinear(field, sx, sy):
        x0 = np.floor(sx).astype(np.int64)
        y0 = np.clip(np.floor(sy).astype(np.int64), 0, h - 2)
        fx, fy = sx - x0, sy - y0
        x0m, x1m = x0 % w, (x0 + 1) % w   # longitude wraps
        v00 = field[y0, x0m]
        v10 = field[y0, x1m]
        v01 = field[y0 + 1, x0m]
        v11 = field[y0 + 1, x1m]
        return (v00 * (1 - fx) * (1 - fy) + v10 * fx * (1 - fy) +
                v01 * (1 - fx) * fy + v11 * fx * fy)

    def gradient(sx, sy):
        e = 1.0
        gx = sample_bilinear(height, sx + e, sy) - sample_bilinear(height, sx - e, sy)
        gy = sample_bilinear(height, sx, np.clip(sy + e, 0, h - 1)) - \
             sample_bilinear(height, sx, np.clip(sy - e, 0, h - 1))
        return gx * 0.5, gy * 0.5

    # Erosion brush: a falloff disc, not a point. Removing material at a
    # single cell makes every droplet dig its own isolated pit, and the map
    # ends up covered in stipple instead of connected channels. Spreading each
    # erosion event over a small neighbourhood is what lets neighbouring
    # droplet paths merge into drainage.
    brush = []
    for by in range(-brush_radius, brush_radius + 1):
        for bx in range(-brush_radius, brush_radius + 1):
            d = np.sqrt(bx * bx + by * by)
            if d <= brush_radius:
                brush.append((bx, by, 1.0 - d / (brush_radius + 1.0)))
    bw = sum(b[2] for b in brush)
    brush = [(bx, by, wgt / bw) for bx, by, wgt in brush]

    def erode_brush(sx, sy, amount):
        x0 = np.floor(sx).astype(np.int64)
        y0 = np.floor(sy).astype(np.int64)
        for bx, by, wgt in brush:
            yy = np.clip(y0 + by, 0, h - 1)
            xx = (x0 + bx) % w
            np.add.at(height, (yy, xx), -amount * wgt)

    def deposit(sx, sy, amount):
        """Distribute bilinearly across the four surrounding cells.

        Depositing the whole amount onto one integer pixel is what produced
        visible stippling - every droplet left a single-pixel spike, so
        erosion added high-frequency speckle instead of carving valleys.
        """
        x0 = np.floor(sx).astype(np.int64)
        y0 = np.floor(sy).astype(np.int64)
        fx = sx - x0
        fy = sy - y0
        y0 = np.clip(y0, 0, h - 2)
        x0m, x1m = x0 % w, (x0 + 1) % w
        np.add.at(height, (y0, x0m), amount * (1.0 - fx) * (1.0 - fy))
        np.add.at(height, (y0, x1m), amount * fx * (1.0 - fy))
        np.add.at(height, (y0 + 1, x0m), amount * (1.0 - fx) * fy)
        np.add.at(height, (y0 + 1, x1m), amount * fx * fy)

    for _ in range(max_steps):
        if not alive.any():
            break
        gx, gy = gradient(px, py)
        s = sample_bilinear(lat_scale, px, py)
        # Latitude belongs on the GRADIENT, not on the step length. A pixel
        # spans less ground near the poles, so the same height difference is a
        # steeper real slope - but the droplet must still walk about one pixel
        # per step. Dividing the STEP by cos(lat) instead made droplets jump up
        # to ~7 px at high latitude, skipping cells and leaving the deposits as
        # visible stipple rather than continuous channels.
        gx = gx / np.maximum(s, 1e-3)

        dx = dx * inertia - gx * (1 - inertia)
        dy = dy * inertia - gy * (1 - inertia)
        length = np.sqrt(dx * dx + dy * dy)
        moving = length > 1e-8
        dx = np.where(moving, dx / np.maximum(length, 1e-8), 0.0)
        dy = np.where(moving, dy / np.maximum(length, 1e-8), 0.0)

        old_h = sample_bilinear(height, px, py)
        px = np.mod(px + dx, w)
        py = py + dy
        # Latitude does not wrap. Clamping droplets at the pole rows made them
        # accumulate there and streak; retire them instead.
        alive &= (py > 2.0) & (py < h - 3.0)
        py = np.clip(py, 1.0, h - 2.0)
        new_h = sample_bilinear(height, px, py)
        dh = new_h - old_h

        cap = np.maximum(-dh, min_slope) * speed * water * capacity

        # Uphill or over capacity -> drop sediment. Otherwise pick some up.
        over = (sediment > cap) | (dh > 0)
        drop = np.where(over,
                        np.where(dh > 0, np.minimum(dh, sediment), (sediment - cap) * deposition),
                        0.0)
        take = np.where(over, 0.0, np.minimum((cap - sediment) * erosion, -dh))

        # Hard cap on how much any single droplet-step may move. Without it a
        # few cells accumulate enormous values, and min/max normalisation then
        # collapses the entire rest of the map to flat grey.
        drop = np.clip(drop, 0.0, max_step_change)
        take = np.clip(take, 0.0, max_step_change)

        taper = sample_bilinear(pole_taper, px, py)
        drop = drop * taper
        take = take * taper

        deposit(px, py, np.where(alive, drop, 0.0))
        erode_brush(px, py, np.where(alive, take, 0.0))
        sediment = sediment - drop + take

        speed = np.sqrt(np.maximum(speed * speed + dh * -gravity, 0.0))
        water = water * (1 - evaporation)
        alive &= water > 0.01

    return height


# --------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--width", type=int, default=2048, help="equirect width; height is width/2")
    ap.add_argument("--droplets", type=int, default=250000)
    ap.add_argument("--continent-freq", type=float, default=1.3)
    ap.add_argument("--mountain-freq", type=float, default=3.1)
    ap.add_argument("--out", default="data/heightmaps/home.png")
    ap.add_argument("--preview", default="", help="also write a shaded relief preview here")
    args = ap.parse_args()

    w = args.width
    h = w // 2
    print(f"baking {w}x{h} equirect heightmap, seed {args.seed}")

    dirs, lat = equirect_directions(w, h)
    fmax = max_useful_frequency(w)
    print(f"  max representable noise frequency at this width: {fmax:.1f}")

    # Continents: very low frequency, pushed through a curve so coast->inland
    # is a real transition rather than a linear ramp.
    cont = fbm_sphere(dirs, args.seed, octaves=4, frequency=args.continent_freq, max_frequency=fmax)
    cont = np.sign(cont) * np.abs(cont) ** 0.8

    # Mountains: ridged, and MULTIPLIED by continent height so ranges sit
    # inland instead of rising straight out of the ocean.
    ridge = fbm_sphere(dirs, args.seed + 101, octaves=6, frequency=args.mountain_freq,
                       ridged=True, max_frequency=fmax)
    inland = np.clip(cont * 1.5 + 0.3, 0.0, 1.0)
    height = cont * 0.6 + ridge * inland * 0.55

    # Fine detail, kept small so erosion has clean landforms to work on.
    height += fbm_sphere(dirs, args.seed + 202, octaves=5, frequency=6.0, max_frequency=fmax) * 0.05

    height = (height - height.min()) / max(np.ptp(height), 1e-9)
    pre = height.copy()

    print(f"eroding with {args.droplets} droplets...")
    height = erode(height, lat, args.droplets, args.seed)
    # Percentile clip, not min/max: erosion inevitably leaves a handful of
    # extreme cells, and normalising against them flattens everything else.
    lo, hi = np.percentile(height, 0.05), np.percentile(height, 99.95)
    height = np.clip(height, lo, hi)
    height = (height - lo) / max(hi - lo, 1e-9)

    changed = float(np.abs(height - pre).mean())
    print(f"  mean change from erosion: {changed:.5f}")

    # High-frequency energy: RMS difference from a 3x3 box blur. Stipple is
    # per-pixel noise, so it shows up here as a large jump over the base.
    def hf_energy(f):
        k = (f + np.roll(f, 1, 0) + np.roll(f, -1, 0) +
             np.roll(f, 1, 1) + np.roll(f, -1, 1)) / 5.0
        return float(np.sqrt(np.mean((f - k) ** 2)))
    hb, he = hf_energy(pre), hf_energy(height)
    print(f"  high-freq energy: base {hb:.6f} -> eroded {he:.6f}  (ratio {he/max(hb,1e-9):.2f}x)")
    print("  ratio near 1.0 = erosion carved without adding pixel noise;"
          " >2 = stippling")

    # Pole banding shows up as row-to-row jitter concentrated in the caps, so
    # compare vertical high-frequency energy there against the equatorial band.
    def row_jitter(f, y0, y1):
        band = f[y0:y1]
        return float(np.sqrt(np.mean((band[1:] - band[:-1]) ** 2)))
    hh = height.shape[0]
    capn = max(int(hh * 0.07), 3)
    polar = 0.5 * (row_jitter(height, 0, capn * 2) + row_jitter(height, hh - capn * 2, hh))
    equat = row_jitter(height, hh // 2 - capn, hh // 2 + capn)
    print(f"  pole banding: polar row-jitter {polar:.6f} vs equatorial {equat:.6f}"
          f"  (ratio {polar/max(equat,1e-9):.2f}x, want < ~1.5)")

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    _write_png16(args.out, height)
    print(f"wrote {args.out}")

    if args.preview:
        _write_preview(args.preview, height)
        print(f"wrote {args.preview}")
        base_path = args.preview.replace(".png", "_base.png")
        _write_preview(base_path, pre)
        print(f"wrote {base_path} (pre-erosion, for comparison)")


def _write_png16(path, field01):
    """16-bit greyscale PNG. 8-bit would quantise a planet's full height range
    into 256 steps, which reads as visible terracing on gentle slopes."""
    import zlib, struct
    h, w = field01.shape
    data = (np.clip(field01, 0, 1) * 65535).astype(">u2")
    raw = b"".join(b"\x00" + data[y].tobytes() for y in range(h))

    def chunk(tag, payload):
        c = struct.pack(">I", len(payload)) + tag + payload
        return c + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def _write_preview(path, field01):
    """Hillshade, so drainage networks are actually visible to a human -
    a raw heightmap looks like grey mush and hides whether erosion worked."""
    import zlib, struct
    gy, gx = np.gradient(field01 * 220.0)
    nx, ny, nz = -gx, -gy, np.ones_like(gx)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    lx, ly, lz = -0.5, -0.6, 0.62
    shade = np.clip((nx * lx + ny * ly + nz * lz) / n, 0, 1)
    img = np.clip(shade * 0.75 + field01 * 0.35, 0, 1)
    h, w = img.shape
    data = (img * 255).astype(np.uint8)
    raw = b"".join(b"\x00" + data[y].tobytes() for y in range(h))

    def chunk(tag, payload):
        c = struct.pack(">I", len(payload)) + tag + payload
        return c + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    main()
