"""Write the asset lines (data/asset_lines/*.tres): what lies on the ground, why, where and how. Regenerable table, like
tools/gen_trait_library.py. Traits list these ids in PlanetTrait.asset_lines.
    python -I tools/gen_asset_lines.py
"""
import os

OUT = "data/asset_lines"
BOULDERS = ["namaqualand_boulder_02", "namaqualand_boulder_03", "namaqualand_boulder_04", "namaqualand_boulder_05",
            "namaqualand_boulder_06"]
ROCKS = ["namaqualand_rocks_01", "namaqualand_boulders_01", "rock_07"]
STONES = ["namaqualand_stones_01", "stone_01", "rock_09"]
MOON = ["moon_rock_02", "moon_rock_03", "moon_rock_04", "moon_rock_05", "moon_rock_06", "moon_rock_07"]

LINES = {
    # debris that fell off slopes and came to rest below them: big, clustered, few
    "boulder_fields": dict(models=BOULDERS, size=(0.8, 3.2), skew="cubic", density=0.006, signal="talus",
                           sig=(0.12, 0.45), slope=(2, 38), ground=[], clump=(70, 0.4), rest=(300, 0.35),
                           burial=0.3, lod=1, shadows=True, collision=True, match=0.8, dust=0.3, view=1.0),
    # impact throw-out around young craters (the bake's "fresh" ejecta mask): blocks thick near the rim, thinning out
    "ejecta_blocks": dict(models=BOULDERS, size=(0.6, 2.4), skew="quintic", density=0.006, signal="fresh",
                          sig=(0.08, 0.5), slope=(0, 30), ground=[], clump=(120, 0.3), rest=(300, 0.35),
                          burial=0.2, lod=1, shadows=True, collision=True, match=0.8, dust=0.25, view=1.0),
    # the finer part of the debris apron: hand to knee sized rocks on scree and worked ground
    "talus_aprons": dict(models=ROCKS, size=(0.2, 0.9), skew="cubic", density=0.05, signal="talus",
                         sig=(0.06, 0.35), slope=(4, 42), ground=["scree", "worked", "secondary"], clump=(25, 0.55),
                         rest=(300, 0.35), burial=0.3, lod=0, shadows=True, collision=False, match=0.8, dust=0.35, view=0.7),
    # stones everywhere the fines have not covered them
    # (on the fine ground too, thinned: on a rocky world that is gravel; on an airless one, dust that buried most)
    "pebbles": dict(models=STONES + MOON, size=(0.04, 0.2), skew="cubic", density=2.5, near=True, signal="deposition",
                    sig=(0.3, 0.8), invert=True, slope=(0, 45), ground=["worked", "scree", "secondary", "fine"],
                    ground_density={"fine": 0.3},
                    clump=(6, 0.65), rest=(200, 0.25), burial=0.35, lod=0, shadows=True, collision=False,
                    match=0.35, dust=0.3, view=0.25, low=True),
    # impact-gardened clods half sunk in the fine regolith of airless worlds
    "regolith_clods": dict(models=MOON, size=(0.05, 0.25), skew="quadratic", density=1.0, near=True, signal="deposition",
                           sig=(0.2, 0.6), slope=(0, 30), ground=["fine"], clump=(10, 0.5), rest=(200, 0.3),
                           burial=0.45, lod=0, shadows=False, collision=False, match=0.8, dust=0.6, view=0.25, low=True),
    # coarse lag along drainage lines (rocky and desert worlds)
    "gravel_patches": dict(models=STONES, size=(0.03, 0.12), skew="cubic", density=3.0, near=True, signal="flow",
                           sig=(0.08, 0.35), slope=(0, 25), ground=["worked", "secondary"], clump=(12, 0.6),
                           rest=(200, 0.3), burial=0.4, lod=0, shadows=False, collision=False, match=0.4, dust=0.3, view=0.2, low=True),
}


def tres(lid, d):
    models = "Array[String]([" + ", ".join(f'"{m}"' for m in d["models"]) + "])"
    ground = "Array[String]([" + ", ".join(f'"{g}"' for g in d["ground"]) + "])"
    gdd = d.get("ground_density", {})
    gd = "{" + ", ".join(f'"{k}": {v}' for k, v in gdd.items()) + "}"
    return f'''[gd_resource type="Resource" script_class="AssetLine" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/world/gen/asset_line.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"{lid}"
display_name = "{lid.replace('_', ' ').capitalize()}"
models = {models}
size_min_m = {d['size'][0]}
size_max_m = {d['size'][1]}
size_skew = "{d['skew']}"
density = {d['density']}
signal_mask = "{d['signal']}"
signal_low = {d['sig'][0]}
signal_high = {d['sig'][1]}
signal_invert = {str(d.get('invert', False)).lower()}
slope_min_deg = {d['slope'][0]}
slope_max_deg = {d['slope'][1]}
on_ground = {ground}
clump_m = {d['clump'][0]}
clump_cover = {d['clump'][1]}
rest_m = {d['rest'][0]}
rest_share = {d['rest'][1]}
burial = {d['burial']}
lod = {d['lod']}
shadows = {str(d['shadows']).lower()}
collision = {str(d['collision']).lower()}
colour_match = {d['match']}
dust = {d['dust']}
view_ratio = {d.get('view', 1.0)}
low_poly = {str(d.get('low', False)).lower()}
near_field = {str(d.get('near', False)).lower()}
ground_density = {gd}
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    for lid, d in LINES.items():
        with open(f"{OUT}/{lid}.tres", "w", newline="\n") as f:
            f.write(tres(lid, d))
    print(len(LINES), "asset lines")


if __name__ == "__main__":
    main()
