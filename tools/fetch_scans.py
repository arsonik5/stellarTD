"""Download the CC0 photoscanned ground sets the material library is built from (ambientCG + Poly Haven, both CC0:
commercial use, no credit required). Sources land OUTSIDE the repo in ~/.stellar-assets/scans/<id>/ as the raw maps;
tools/pack_surface_set.py turns them into the game's packed 2048 maps.

    python -I tools/fetch_scans.py            # everything in SETS that isn't downloaded yet
    python -I tools/fetch_scans.py Rock058    # just these

Poly Haven is fetched through its public API, as its terms ask (no page scraping)."""
import io, json, os, sys, urllib.request, zipfile

CACHE = os.path.join(os.path.expanduser("~"), ".stellar-assets", "scans")
UA = {"User-Agent": "StellarTD-asset-fetch/1.0"}
# id -> source. Roles are decided in data/surfaces/library (SurfaceStyle .tres), not here.
SETS = {
    # airless / regolith
    "Ground091": "acg", "Gravel043": "acg", "Gravel024": "acg", "Gravel022": "acg", "Rocks006": "acg",
    # cliff / bedrock / cracked
    "Rock058": "acg", "Rock062": "acg", "Rock063": "acg", "Rock028": "acg", "Rock051": "acg",
    # dark basalt / volcanic
    "Rock035": "acg", "Rock031": "acg", "Rock048": "acg", "Rock041": "acg", "Lava002": "acg",
    # ice / snow
    "Ice002": "acg", "Snow014": "acg", "Snow010A": "acg", "Snow008A": "acg",
    # desert / strata
    "Ground096B": "acg", "Gravel025": "acg", "Rock029": "acg", "Rock052": "acg", "Rock055": "acg",
    # Poly Haven
    "rock_face_03": "ph", "sandstone_cracks": "ph", "dry_riverbed_rock": "ph",
}
# Poly Haven map names -> our names
PH_MAPS = {"Diffuse": "Color", "nor_gl": "NormalGL", "Rough": "Roughness", "AO": "AmbientOcclusion",
           "Displacement": "Displacement"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def fetch_acg(sid, out):
    data = get(f"https://ambientcg.com/get?file={sid}_2K-PNG.zip")
    z = zipfile.ZipFile(io.BytesIO(data))
    for n in z.namelist():
        low = n.lower()
        for key in ("color", "normalgl", "roughness", "ambientocclusion", "displacement"):
            if low.endswith(f"_{key}.png"):
                name = {"color": "Color", "normalgl": "NormalGL", "roughness": "Roughness",
                        "ambientocclusion": "AmbientOcclusion", "displacement": "Displacement"}[key]
                with open(os.path.join(out, name + ".png"), "wb") as f:
                    f.write(z.read(n))


def fetch_ph(sid, out):
    files = json.loads(get(f"https://api.polyhaven.com/files/{sid}"))
    for ph, name in PH_MAPS.items():
        entry = files.get(ph, {}).get("2k", {})
        fmt = entry.get("png") or entry.get("jpg")
        if fmt is None:
            continue
        ext = "png" if "png" in entry else "jpg"
        with open(os.path.join(out, f"{name}.{ext}"), "wb") as f:
            f.write(get(fmt["url"]))


def main():
    ids = sys.argv[1:] or list(SETS)
    os.makedirs(CACHE, exist_ok=True)
    for sid in ids:
        out = os.path.join(CACHE, sid)
        if os.path.isdir(out) and any(f.startswith("Color") for f in os.listdir(out)):
            print("have", sid)
            continue
        os.makedirs(out, exist_ok=True)
        try:
            (fetch_acg if SETS.get(sid, "acg") == "acg" else fetch_ph)(sid, out)
            print("got ", sid, sorted(os.listdir(out)))
        except Exception as e:
            print("FAIL", sid, e)


if __name__ == "__main__":
    main()
