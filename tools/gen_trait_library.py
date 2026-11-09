"""Write the material library (data/surfaces/library/*.tres) and the planet traits (data/traits/*.tres).

Kept as one script so the library is reviewable as a table and regenerable; hand-edit the .tres files afterwards if
a value needs tuning in the editor, then copy the change back here.
    python -I tools/gen_trait_library.py
"""
import os

LIB = "data/surfaces/library"
TRAITS = "data/traits"

# name: (texture, tint rgb, roughness_scale, metallic, specular, normal_strength, tile m)
MATERIALS = {
    "regolith_fine":   ("ground091",        (0.80, 0.80, 0.84), 1.45, 0.0, 0.40, 1.1, 2.5),
    "regolith_pebbly": ("gravel043",        (1.00, 1.00, 1.02), 1.35, 0.0, 0.40, 1.2, 2.0),
    "regolith_dark":   ("gravel024",        (1.00, 1.00, 1.00), 1.40, 0.0, 0.42, 1.2, 1.6),
    "gravel_grey":     ("gravel022",        (1.00, 1.00, 1.00), 1.30, 0.0, 0.42, 1.2, 1.8),
    "pebbles_light":   ("rocks006",         (1.00, 1.00, 1.00), 1.25, 0.0, 0.45, 1.2, 1.5),
    "cliff_grey":      ("rock058",          (1.00, 1.00, 1.00), 1.15, 0.0, 0.45, 1.3, 6.0),
    "rock_cracked":    ("rock062",          (1.00, 1.00, 1.00), 1.15, 0.0, 0.45, 1.3, 5.0),
    "rock_aged":       ("rock063",          (1.00, 1.00, 1.00), 1.15, 0.0, 0.45, 1.3, 6.0),
    "rock_rough":      ("rock028",          (1.00, 1.00, 1.00), 1.15, 0.0, 0.45, 1.3, 6.0),
    "rock_mountain":   ("rock051",          (1.00, 1.00, 1.00), 1.15, 0.0, 0.45, 1.3, 7.0),
    "rock_face":       ("rock_face_03",     (1.00, 1.00, 1.00), 1.10, 0.0, 0.45, 1.3, 6.0),
    "riverbed_rock":   ("dry_riverbed_rock", (1.00, 1.00, 1.00), 1.10, 0.0, 0.45, 1.2, 3.0),
    "basalt_dark":     ("rock035",          (1.00, 1.00, 1.00), 1.10, 0.0, 0.50, 1.3, 5.0),
    "basalt_black":    ("rock031",          (1.00, 1.00, 1.00), 1.05, 0.0, 0.50, 1.3, 5.0),
    "rock_dark_rough": ("rock048",          (1.00, 1.00, 1.00), 1.10, 0.0, 0.50, 1.3, 4.0),
    "obsidian":        ("rock041",          (1.00, 1.00, 1.00), 0.55, 0.0, 0.62, 1.0, 4.0),
    "lava_crust":      ("lava002",          (1.00, 1.00, 1.00), 0.90, 0.0, 0.50, 1.2, 4.0),
    "ice_clear":       ("ice002",           (0.95, 1.00, 1.05), 0.45, 0.0, 0.70, 1.0, 4.0),
    "frozen_ground":   ("snow014",          (1.00, 1.00, 1.00), 0.80, 0.0, 0.60, 1.1, 3.0),
    "snow_clean":      ("snow010a",         (1.00, 1.00, 1.00), 0.85, 0.0, 0.55, 1.0, 3.0),
    "snow_dunes":      ("snow008a",         (1.00, 1.00, 1.00), 0.85, 0.0, 0.55, 1.1, 6.0),
    "desert_ground":   ("ground096b",       (0.80, 0.80, 0.80), 1.30, 0.0, 0.40, 1.1, 3.0),
    "gravel_red":      ("gravel025",        (1.00, 1.00, 1.00), 1.30, 0.0, 0.40, 1.2, 2.0),
    "cracked_crust":   ("sandstone_cracks", (1.00, 1.00, 1.00), 1.20, 0.0, 0.42, 1.3, 4.0),
    "desert_cliff":    ("rock029",          (1.25, 1.25, 1.25), 1.15, 0.0, 0.45, 1.3, 7.0),
    "strata_beige":    ("rock052",          (1.00, 1.00, 1.00), 1.15, 0.0, 0.45, 1.3, 6.0),
    "strata_brown":    ("rock055",          (1.00, 1.00, 1.00), 1.15, 0.0, 0.45, 1.3, 6.0),
    # generated sets (Qwen) until scans exist for these minerals
    "crystal_crust":   ("crystal",          (0.70, 1.20, 1.10), 0.50, 0.0, 0.65, 1.2, 3.0),
    "sulfur_crust":    ("sulfur",           (1.10, 1.00, 0.70), 1.00, 0.0, 0.45, 1.0, 3.0),
}

# saturation per material (1 = the scan's own colour). Lunar regolith from beige sand scans has to be near-grey; rock
# scans with lichen tints are muted; desert and mineral materials keep their colour.
SATURATION = {
    "regolith_fine": 0.12, "regolith_pebbly": 0.35, "regolith_dark": 0.5, "gravel_grey": 0.6, "pebbles_light": 0.6,
    "cliff_grey": 0.5, "rock_cracked": 0.6, "rock_aged": 0.3, "rock_rough": 0.6, "rock_mountain": 0.6,
    "rock_face": 0.7, "riverbed_rock": 0.8, "basalt_dark": 0.6, "basalt_black": 0.6, "rock_dark_rough": 0.6,
    "obsidian": 0.6, "ice_clear": 0.8, "frozen_ground": 0.6, "snow_clean": 0.5, "snow_dunes": 0.5,
    # desert rock keeps its warmth, but under the base-ground chroma budget so an accent can still read
    "desert_cliff": 0.8,
}

# id: dict
TRAITS_DEF = {
    "airless": dict(name="Airless", base=1.2, temp=(0.0, 0.85), tsoft=0.2, air=(0.0, 0.01), asoft=0.05,
                    spatial="global", mode="replace", hue=250, chroma=0.02, accent=False, emissive=False,
                    excludes=["desert", "life"], affinity={"crystalline": 1.3, "icy": 1.2},
                    mats={"surface": "regolith_fine", "surface_alt": "regolith_pebbly", "regional": "regolith_dark",
                          "cliff": "cliff_grey", "bedrock": "rock_mountain", "strata_a": "rock_aged",
                          "strata_b": "basalt_dark", "fresh_cut": "rock_cracked"},
                    lines=["boulder_fields", "ejecta_blocks", "crater_rims", "talus_aprons", "pebbles",
                           "regolith_clods", "dust_ponds", "dig_rubble"], landmarks=["central_peak", "fresh_crater"]),
    "rocky": dict(name="Barren rock", base=1.0, temp=(0.15, 0.8), tsoft=0.2, air=(0.0, 2.0), asoft=0.5,
                  spatial="global", mode="replace", hue=60, chroma=0.025, accent=False, emissive=False,
                  excludes=[], affinity={"desert": 1.3, "volcanic": 1.1},
                  mats={"surface": "gravel_grey", "surface_alt": "pebbles_light", "regional": "riverbed_rock",
                        "cliff": "rock_rough", "bedrock": "rock_mountain", "strata_a": "rock_face",
                        "strata_b": "rock_cracked", "fresh_cut": "rock_face"},
                  lines=["boulder_fields", "talus_aprons", "outcrops", "strata_ledges", "pebbles", "gravel_patches",
                         "cracks", "dig_rubble"], landmarks=["mesa", "outcrop_spire"]),
    "icy": dict(name="Icy", base=0.9, temp=(0.0, 0.28), tsoft=0.12, air=(0.0, 100.0), asoft=1.0,
                spatial="global", mode="replace", hue=230, chroma=0.03, accent=False, emissive=False,
                excludes=["desert", "life"], affinity={"crystalline": 1.4, "volcanic": 0.7},
                # an icy world's crust IS ice: bedrock is ice, rock only comes in as darker layers in it
                mats={"surface": "frozen_ground", "surface_alt": "snow_dunes", "regional": "snow_clean",
                      "cliff": "ice_clear", "bedrock": "ice_clear", "strata_a": "frozen_ground",
                      "strata_b": "rock_cracked", "fresh_cut": "ice_clear"},
                lines=["penitentes", "frost_overlay", "ice_cliffs", "cryo_geysers", "polygonal_ground", "pebbles"],
                landmarks=["cryo_geyser", "ice_arch"]),
    "volcanic": dict(name="Volcanic", base=0.75, temp=(0.3, 1.0), tsoft=0.2, air=(0.0, 100.0), asoft=1.0,
                     requires=["geologically_active"], spatial="regional", mode="replace", hue=30, chroma=0.03,
                     accent=False, emissive=True, excludes=["life"], affinity={"sulfur": 1.7, "crystalline": 1.1},
                     mats={"surface": "regolith_dark", "surface_alt": "rock_dark_rough", "regional": "regolith_dark",
                           "cliff": "basalt_black", "bedrock": "basalt_black", "strata_a": "basalt_dark",
                           "strata_b": "obsidian", "fresh_cut": "basalt_black"},
                     lines=["columnar_basalt", "vent_cones", "lava_tubes", "flow_fronts", "stain_rings", "pebbles"],
                     landmarks=["basalt_cliff", "caldera"]),
    "crystalline": dict(name="Crystalline", base=0.3, temp=(0.0, 0.9), tsoft=0.2, air=(0.0, 100.0), asoft=1.0,
                        spatial="crater_floor", mode="replace", hue=165, chroma=0.12, accent=True, emissive=True,
                        excludes=[], affinity={},
                        mats={"surface": "crystal_crust", "regional": "crystal_crust"},
                        lines=["crystal_clusters", "geodes", "crystal_shards"], landmarks=["crystal_arch"]),
    "desert": dict(name="Desert", base=0.9, temp=(0.45, 0.9), tsoft=0.15, air=(0.05, 5.0), asoft=0.1,
                   requires=["atmosphere"], spatial="global", mode="replace", hue=55, chroma=0.06, accent=False,
                   emissive=False, excludes=["airless", "icy"], affinity={"rocky": 1.2, "sulfur": 1.1},
                   mats={"surface": "desert_ground", "surface_alt": "gravel_red", "regional": "cracked_crust",
                         "cliff": "desert_cliff", "bedrock": "strata_beige", "strata_a": "strata_beige",
                         "strata_b": "strata_brown", "fresh_cut": "strata_beige"},
                   lines=["ventifacts", "yardangs", "hoodoos", "dust_drifts", "gravel_patches", "cracks", "pebbles"],
                   landmarks=["arch", "hoodoo_field"]),
    "sulfur": dict(name="Sulfurous", base=0.5, temp=(0.3, 0.95), tsoft=0.2, air=(0.0, 100.0), asoft=1.0,
                   requires=["geologically_active"], spatial="fault", mode="replace", hue=95, chroma=0.12,
                   accent=True, emissive=False, excludes=["life"], affinity={},
                   mats={"surface": "sulfur_crust", "regional": "sulfur_crust"},
                   lines=["fumaroles", "mineral_crusts", "stain_rings"], landmarks=["sulfur_spring"]),
    "life": dict(name="Living", base=0.6, temp=(0.3, 0.7), tsoft=0.12, air=(0.2, 5.0), asoft=0.2,
                 requires=["water"], spatial="lowland", mode="overlay", hue=130, chroma=0.1, accent=True,
                 emissive=False, excludes=["airless"], affinity={},
                 mats={}, lines=["lichen_crust", "microbial_mats", "low_cover", "shrubs", "alien_flora"],
                 landmarks=["great_tree"]),
}


# landforms per trait: crater density (1 = airless, never resurfaced), ray strength, ledge strength (hard/soft layers
# on steep faces), contraction crack polygon size in m (0 = none), lava tubes
LANDFORMS = {
    "airless":     dict(craters=1.0, rays=1.0, ledges=0.3, cracks=0.0, tubes=0.0),
    "rocky":       dict(craters=0.35, rays=0.45, ledges=1.0, cracks=0.0, tubes=0.0),
    "icy":         dict(craters=0.5, rays=0.8, ledges=0.5, cracks=9.0, tubes=0.0),
    "volcanic":    dict(craters=0.12, rays=0.3, ledges=0.8, cracks=0.0, tubes=1.0),
    "crystalline": dict(craters=0.5, rays=0.5, ledges=0.0, cracks=0.0, tubes=0.0),
    "desert":      dict(craters=0.12, rays=0.1, ledges=1.4, cracks=0.7, tubes=0.0),
    "sulfur":      dict(craters=0.15, rays=0.2, ledges=0.0, cracks=0.35, tubes=0.0),
    "life":        dict(craters=0.05, rays=0.05, ledges=0.0, cracks=0.0, tubes=0.0),
}


def style_tres(name, m):
    tex, tint, rough, metal, spec, nrm, scale = m
    return f'''[gd_resource type="Resource" script_class="SurfaceStyle" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/world/surface_style.gd" id="1"]

[resource]
script = ExtResource("1")
display_name = "{name.replace('_', ' ').capitalize()}"
texture_name = "{tex}"
albedo_tint = Color({tint[0]}, {tint[1]}, {tint[2]}, 1)
roughness_scale = {rough}
metallic = {metal}
specular = {spec}
normal_strength = {nrm}
texture_scale_m = {scale}
saturation = {SATURATION.get(name, 1.0)}
'''


def sn(a):
    return "Array[StringName]([" + ", ".join(f'&"{x}"' for x in a) + "])"


def trait_tres(tid, d):
    mats = d["mats"]
    ext = ['[ext_resource type="Script" path="res://scripts/world/gen/planet_trait.gd" id="1"]']
    ids = {}
    for i, (role, mname) in enumerate(sorted(mats.items())):
        if mname not in ids:
            ids[mname] = f"m{len(ids) + 2}"
            ext.append(f'[ext_resource type="Resource" path="res://{LIB}/{mname}.tres" id="{ids[mname]}"]')
    mat_dict = "{\n" + ",\n".join(f'"{r}": ExtResource("{ids[m]}")' for r, m in sorted(mats.items())) + "\n}" if mats else "{}"
    aff = "{\n" + ",\n".join(f'"{k}": {v}' for k, v in d["affinity"].items()) + "\n}" if d["affinity"] else "{}"
    return f'''[gd_resource type="Resource" script_class="PlanetTrait" load_steps={len(ext) + 1} format=3]

{chr(10).join(ext)}

[resource]
script = ExtResource("1")
id = &"{tid}"
display_name = "{d['name']}"
base_weight = {d['base']}
temperature_range = Vector2({d['temp'][0]}, {d['temp'][1]})
temperature_soft = {d['tsoft']}
air_range = Vector2({d['air'][0]}, {d['air'][1]})
air_soft = {d['asoft']}
requires_facts = {sn(d.get('requires', []))}
excludes = {sn(d['excludes'])}
affinity = {aff}
spatial = "{d['spatial']}"
material_mode = "{d['mode']}"
materials = {mat_dict}
hue = {d['hue']}
chroma_max = {d['chroma']}
accent = {str(d['accent']).lower()}
emissive = {str(d['emissive']).lower()}
crater_density = {LANDFORMS[tid]['craters']}
ray_strength = {LANDFORMS[tid]['rays']}
ledge_strength = {LANDFORMS[tid]['ledges']}
crack_cell_m = {LANDFORMS[tid]['cracks']}
lava_tubes = {LANDFORMS[tid]['tubes']}
asset_lines = {sn(d['lines'])}
landmarks = {sn(d['landmarks'])}
'''


def main():
    os.makedirs(LIB, exist_ok=True)
    os.makedirs(TRAITS, exist_ok=True)
    for name, m in MATERIALS.items():
        with open(f"{LIB}/{name}.tres", "w", newline="\n") as f:
            f.write(style_tres(name, m))
    for tid, d in TRAITS_DEF.items():
        with open(f"{TRAITS}/{tid}.tres", "w", newline="\n") as f:
            f.write(trait_tres(tid, d))
    print(len(MATERIALS), "materials,", len(TRAITS_DEF), "traits")


if __name__ == "__main__":
    main()
