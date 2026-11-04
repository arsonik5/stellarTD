"""Turn a generated surface photo into a tiling PBR material set.

An AI-generated rock image is NOT an albedo map. It has lighting baked into it,
it does not tile, and it carries no normal, roughness or occlusion data. Using
one directly as albedo double-lights the surface: the generator's sun is
multiplied by the engine's sun, and the result reads as a photo glued to
geometry rather than as a lit material. That is the single most common way
AI-sourced textures look wrong.

So this does four jobs, in order:

  1. SEAMLESS   - offset by half and cross-fade the seams, so the texture tiles.
  2. DE-LIGHT   - divide out the low-frequency luminance. Broad light and shade
                  is the generator's lighting; fine luminance detail is the
                  rock's own colour variation. Keeping the second and removing
                  the first is what turns a photo into an albedo.
  3. DERIVE     - height from the de-lit detail, normal from the height
                  gradient, occlusion from height cavity, roughness from local
                  detail density.
  4. PACK       - two RGBA textures instead of four RGB ones, because the
                  terrain shader samples these per material per plane and the
                  sample count is the frame budget.

Output, per material:
    <name>_alb.png   RGB = albedo (de-lit), A = roughness
    <name>_nrm.png   RG  = normal XY,       B = occlusion, A = height

Usage:
    python tools/bake_surface_textures.py --in raw/regolith.png --name regolith
    python tools/bake_surface_textures.py --in raw/ --all
"""

import argparse
import os
import sys

import numpy as np

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required:  python -m pip install pillow")


# ----------------------------------------------------------------- utilities

def _box_blur(a, radius):
    """Separable box blur via summed-area, wrapping at the edges.

    Wrapping matters: these maps tile, so a blur that clamps at the border
    would bake a brightness gradient into the seam it is supposed to hide.
    """
    if radius < 1:
        return a
    k = radius * 2 + 1
    pad = np.pad(a, ((radius, radius), (radius, radius)), mode="wrap")
    cum = np.cumsum(pad, axis=0)
    a = cum[k - 1:, :] - np.concatenate([np.zeros((1, pad.shape[1])), cum[:-k, :]], axis=0)
    cum = np.cumsum(a, axis=1)
    a = cum[:, k - 1:] - np.concatenate([np.zeros((a.shape[0], 1)), cum[:, :-k]], axis=1)
    return a / (k * k)


def _normalize(a, lo_pct=1.0, hi_pct=99.0):
    """Percentile stretch to 0..1, so a few outlier pixels cannot flatten
    everything else into the middle of the range."""
    lo = np.percentile(a, lo_pct)
    hi = np.percentile(a, hi_pct)
    if hi - lo < 1e-6:
        return np.zeros_like(a)
    return np.clip((a - lo) / (hi - lo), 0.0, 1.0)


def _luma(rgb):
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


# ------------------------------------------------------------------- 1. tile

def make_seamless(rgb, band_frac=0.14):
    """Cross-fade opposite edges into each other, then crop the spent band.

    The top band is blended with the BOTTOM band through a linear ramp and the
    bottom band is then discarded. The new bottom edge is therefore already
    continuous with the top one, and the same is done for left/right. The result
    tiles exactly, with no symmetry anywhere - only a soft blend zone.

    The first version of this rolled the image and then blended each seam strip
    against a FLIPPED COPY OF ITSELF, which is mirroring by another name. It
    produced exactly the bilateral symmetry this docstring used to claim it
    avoided: a visible mirrored cross straight through the middle of the tile.
    Writing the right intent in a comment does not make the code do it.
    """
    h, w = rgb.shape[:2]
    bh = max(4, int(h * band_frac))
    bw = max(4, int(w * band_frac))

    out = rgb.copy()
    ramp = np.linspace(0.0, 1.0, bh)[:, None, None]
    out[:bh] = out[:bh] * ramp + out[h - bh:] * (1.0 - ramp)
    out = out[:h - bh]

    h = out.shape[0]
    ramp = np.linspace(0.0, 1.0, bw)[None, :, None]
    out[:, :bw] = out[:, :bw] * ramp + out[:, w - bw:] * (1.0 - ramp)
    out = out[:, :w - bw]
    return np.clip(out, 0.0, 1.0)


# ---------------------------------------------------------------- 2. de-light

def delight(rgb, radius_frac=0.12):
    """Remove baked lighting by dividing out low-frequency luminance.

    Division, not subtraction: lighting is multiplicative. Subtracting a blur
    lifts shadows toward grey and leaves them looking washed, while dividing
    restores the underlying reflectance and keeps local contrast intact.
    """
    h, w = rgb.shape[:2]
    radius = max(2, int(min(h, w) * radius_frac))
    lum = _luma(rgb)
    low = _box_blur(lum, radius)
    low = np.maximum(low, 1e-3)
    # Normalise around the image's own mean so the result keeps its overall
    # brightness rather than drifting toward white.
    gain = (lum.mean() / low)[..., None]
    return np.clip(rgb * gain, 0.0, 1.0)


# ----------------------------------------------------------------- 3. derive

def derive_height(rgb, detail_frac=0.03):
    """Height from high-passed luminance.

    Only the HIGH frequencies: broad luminance is material colour (a dark rock
    unit next to a pale one is not a hole), while fine luminance detail
    genuinely tracks surface relief, because pits self-shadow and edges catch
    light.
    """
    h, w = rgb.shape[:2]
    radius = max(2, int(min(h, w) * detail_frac))
    lum = _luma(rgb)
    return _normalize(lum - _box_blur(lum, radius))


def derive_normal(height, strength=2.0):
    """Tangent-space normal from the height gradient.

    `np.roll` rather than an edge-clamped difference, so the normal map tiles
    with the texture it came from.
    """
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    nz = np.ones_like(height)
    inv = 1.0 / np.sqrt(dx * dx + dy * dy + nz * nz)
    # Green channel is flipped to OpenGL convention, which is what Godot expects.
    return np.stack([-dx * inv * 0.5 + 0.5, dy * inv * 0.5 + 0.5], axis=-1)


def derive_occlusion(height, radius_frac=0.02, strength=1.0, floor=0.45):
    """Cavity occlusion: how far below its neighbourhood a point sits.

    Floored well above zero. Ambient occlusion is a fraction of the sky a point
    can see, and a millimetre-deep pit in regolith can still see most of it -
    an AO map that reaches 0 is claiming the crevice is sealed. Unfloored, every
    map baked here bottomed out at 0.000 and crushed all cavity detail to pure
    black the moment the surface was not in direct sun.
    """
    h = height.shape[0]
    radius = max(2, int(h * radius_frac))
    cavity = np.clip(_box_blur(height, radius) - height, 0.0, 1.0)
    return np.clip(1.0 - cavity * 2.0 * strength, floor, 1.0)


def derive_roughness(height, base=0.90, spread=0.14, radius_frac=0.02):
    """Rougher where there is more fine detail, smoother on flat faces.

    Natural rock lives in a narrow band near the top of the range - the spread
    is small on purpose. Wide roughness variation reads as wet patches.
    """
    h = height.shape[0]
    radius = max(2, int(h * radius_frac))
    local_mean = _box_blur(height, radius)
    variance = _box_blur((height - local_mean) ** 2, radius)
    return np.clip(base + (_normalize(variance) - 0.5) * 2.0 * spread, 0.0, 1.0)


# ------------------------------------------------------------------- 4. pack

def bake(src_path, name, out_dir, size=1024, normal_strength=2.0,
         roughness_base=0.90):
    img = Image.open(src_path).convert("RGB")
    if img.size != (size, size):
        img = img.resize((size, size), Image.LANCZOS)
    rgb = np.asarray(img, dtype=np.float32) / 255.0

    # Cropping the blend bands leaves a non-power-of-two image; resize back so
    # the GPU gets a clean mip chain. Done BEFORE deriving maps, so the normal
    # and height are computed at the resolution they will actually be sampled at
    # rather than being resampled afterwards, which would soften them.
    rgb = make_seamless(rgb)
    rgb = np.asarray(
        Image.fromarray((rgb * 255).astype(np.uint8), "RGB").resize(
            (size, size), Image.LANCZOS), dtype=np.float32) / 255.0
    albedo = delight(rgb)
    height = derive_height(albedo)
    normal = derive_normal(height, normal_strength)
    occl = derive_occlusion(height)
    rough = derive_roughness(height, roughness_base)

    os.makedirs(out_dir, exist_ok=True)

    alb = np.concatenate([albedo, rough[..., None]], axis=-1)
    Image.fromarray((alb * 255).astype(np.uint8), "RGBA").save(
        os.path.join(out_dir, f"{name}_alb.png"))

    nrm = np.stack([normal[..., 0], normal[..., 1], occl, height], axis=-1)
    Image.fromarray((nrm * 255).astype(np.uint8), "RGBA").save(
        os.path.join(out_dir, f"{name}_nrm.png"))

    print(f"  {name}: albedo mean {albedo.mean():.3f}  "
          f"height contrast {height.std():.3f}  "
          f"roughness {rough.mean():.3f}+-{rough.std():.3f}  "
          f"occlusion min {occl.min():.3f}")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True,
                    help="source image, or a directory when --all is given")
    ap.add_argument("--name", help="material name (single-file mode)")
    ap.add_argument("--all", action="store_true",
                    help="bake every image in the source directory, named after each file")
    ap.add_argument("--out", default="data/textures/surfaces")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--normal-strength", type=float, default=2.0)
    ap.add_argument("--roughness-base", type=float, default=0.90)
    args = ap.parse_args()

    print(f"baking to {args.out} at {args.size}px")
    if args.all:
        names = [f for f in sorted(os.listdir(args.src))
                 if f.lower().endswith((".png", ".jpg", ".jpeg", ".webp"))]
        if not names:
            sys.exit(f"no images found in {args.src}")
        for f in names:
            bake(os.path.join(args.src, f), os.path.splitext(f)[0],
                 args.out, args.size, args.normal_strength, args.roughness_base)
    else:
        if not args.name:
            sys.exit("--name is required unless --all is given")
        bake(args.src, args.name, args.out, args.size,
             args.normal_strength, args.roughness_base)


if __name__ == "__main__":
    main()
