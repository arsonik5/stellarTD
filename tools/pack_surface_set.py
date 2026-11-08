"""Pack a photoscanned PBR set (tools/fetch_scans.py) into the terrain shader's two maps, at 2048:

    <name>_alb.png   RGB = albedo (sRGB),  A = roughness
    <name>_nrm.png   RG  = normal XY (OpenGL, as the scan ships and as Godot expects), B = AO, A = height
    <name>.json      far colour (mean linear albedo, for the distance ladder), height stats, source id

Unlike tools/bake_surface_textures.py, nothing is DERIVED here: the scan's own normal, roughness, AO and displacement
are used, which is the point of photoscans (a normal guessed from a photo's brightness can't tell a dark stone from a
hole). Height is percentile-stretched so every material uses the full range in the height blend.

    python -I tools/pack_surface_set.py Rock058 rock058          # scan id -> material texture name
    python -I tools/pack_surface_set.py --all                    # every scan in the cache, named lower-case
"""
import json, os, sys
import numpy as np
from PIL import Image

CACHE = os.path.join(os.path.expanduser("~"), ".stellar-assets", "scans")
OUT = "data/textures/surfaces/scan"          # git-ignored: rebuilt by tools/setup_surfaces.sh
SIZE = 2048
AO_FLOOR = 0.35            # an AO of 0 claims a crevice is sealed from the sky; scans bottom out in tiny pits


def load(path, mode, size):
    im = Image.open(path)
    if im.mode in ("I;16", "I;16B", "I"):
        a = np.asarray(im, dtype=np.float32)
        a = a / (65535.0 if a.max() > 255 else 255.0)
        im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8), "L")
    im = im.convert(mode)
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def find(d, stem):
    for ext in ("png", "jpg"):
        p = os.path.join(d, f"{stem}.{ext}")
        if os.path.exists(p):
            return p
    return None


def stretch(a, lo=1.0, hi=99.0):
    p0, p1 = np.percentile(a, [lo, hi])
    return np.clip((a - p0) / max(p1 - p0, 1e-4), 0.0, 1.0)


def pack(sid, name):
    d = os.path.join(CACHE, sid)
    col = find(d, "Color")
    nrm = find(d, "NormalGL")
    if col is None or nrm is None:
        print("skip", sid, "(no colour or normal)")
        return False
    albedo = load(col, "RGB", SIZE)
    normal = load(nrm, "RGB", SIZE)
    rp = find(d, "Roughness")
    rough = load(rp, "L", SIZE) if rp else np.full((SIZE, SIZE), 0.85, np.float32)
    ap = find(d, "AmbientOcclusion")
    ao = load(ap, "L", SIZE) if ap else np.ones((SIZE, SIZE), np.float32)
    ao = np.maximum(ao, AO_FLOOR)
    hp = find(d, "Displacement")
    height = stretch(load(hp, "L", SIZE)) if hp else np.full((SIZE, SIZE), 0.5, np.float32)
    if ap is None and hp is not None:
        # no AO map: a cavity term from the height (low points darker), gently
        k = 1.0 - np.clip(0.6 - height, 0.0, 0.6) * 0.8
        ao = np.maximum(k, AO_FLOOR)
    os.makedirs(OUT, exist_ok=True)
    alb = np.dstack([albedo, rough])
    Image.fromarray((alb * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"{name}_alb.png"))
    nm = np.dstack([normal[..., 0], normal[..., 1], ao, height])
    Image.fromarray((nm * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"{name}_nrm.png"))
    lin = np.where(albedo <= 0.04045, albedo / 12.92, ((albedo + 0.055) / 1.055) ** 2.4)
    far = lin.reshape(-1, 3).mean(0)
    info = {"source": sid, "far_colour_linear": [round(float(x), 4) for x in far],
            "albedo_mean_srgb": round(float(albedo.mean()), 4), "roughness_mean": round(float(rough.mean()), 3),
            "height_std": round(float(height.std()), 3), "ao_min": round(float(ao.min()), 3)}
    with open(os.path.join(OUT, f"{name}.json"), "w") as f:
        json.dump(info, f, indent=1)
    print(f"  {name:22s} <- {sid:18s} albedo {info['albedo_mean_srgb']:.3f} rough {info['roughness_mean']:.2f} "
          f"height std {info['height_std']:.3f}")
    return True


def main():
    if sys.argv[1:2] == ["--all"]:
        for sid in sorted(os.listdir(CACHE)):
            pack(sid, sid.lower())
    elif len(sys.argv) >= 3:
        pack(sys.argv[1], sys.argv[2])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
