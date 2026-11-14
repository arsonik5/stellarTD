"""Download CC0 photoscanned rock models from Poly Haven (through its public API, as its terms ask) into
data/models/rocks/<id>/ as glTF with textures. These are the scans the scatter asset lines are built from
(scripts/world/gen/asset_line.gd, data/asset_lines).

    python -I tools/fetch_rock_models.py                 # every model below that isn't there yet
    python -I tools/fetch_rock_models.py rock_07         # just these

Resolution per model: boulders and outcrops are scaled up to metres, so they get 2k textures; hand-sized stones 1k.
"""
import json, os, sys, urllib.request

DST = "data/models/rocks"
UA = {"User-Agent": "StellarTD-asset-fetch/1.0"}
MODELS = {
    # boulders (scaled to 0.8-4 m)
    "namaqualand_boulder_02": "2k", "namaqualand_boulder_03": "2k", "namaqualand_boulder_04": "2k",
    "namaqualand_boulder_05": "2k", "namaqualand_boulder_06": "2k", "namaqualand_boulders_01": "2k",
    "rock_07": "2k", "rock_09": "2k", "boulder_01": "2k",
    # rocks and stones (0.03-0.8 m)
    "namaqualand_rocks_01": "1k", "namaqualand_stones_01": "1k", "stone_01": "1k",
    # outcrops / cliff pieces (stage 4b)
    "namaqualand_cliff_01": "2k", "namaqualand_cliff_02": "2k", "rock_face_01": "2k", "rock_face_02": "2k",
}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def fetch(mid, res):
    files = json.loads(get(f"https://api.polyhaven.com/files/{mid}"))
    g = files.get("gltf", {}).get(res, {}).get("gltf")
    if g is None:
        print("FAIL", mid, "no gltf at", res)
        return
    out = os.path.join(DST, mid)
    os.makedirs(out, exist_ok=True)
    gltf_name = os.path.basename(g["url"])
    with open(os.path.join(out, gltf_name), "wb") as f:
        f.write(get(g["url"]))
    for rel, info in g.get("include", {}).items():
        p = os.path.join(out, rel)
        os.makedirs(os.path.dirname(p) or out, exist_ok=True)
        with open(p, "wb") as f:
            f.write(get(info["url"]))
    print("got ", mid, res, gltf_name, len(g.get("include", {})), "files")


def main():
    ids = sys.argv[1:] or list(MODELS)
    for mid in ids:
        if os.path.isdir(os.path.join(DST, mid)) and any(n.endswith(".gltf") for n in os.listdir(os.path.join(DST, mid))):
            print("have", mid)
            continue
        try:
            fetch(mid, MODELS.get(mid, "1k"))
        except Exception as e:
            print("FAIL", mid, e)


if __name__ == "__main__":
    main()
