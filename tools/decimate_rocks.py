"""Blender (headless): photoscanned rock models -> game-ready scatter meshes.

Scans arrive at 10k-110k triangles a rock; a scatter line puts hundreds of them in view, so each rock is decimated to a
role budget (the scan's own normal map keeps the surface detail), rock SETS (several rocks in one file) are split into
one mesh per rock, and each is exported as its own .glb with its textures:
    data/models/rocks/<model>/game/<mesh>.glb

    blender -b -P tools/decimate_rocks.py            (run from the repo root; tools/setup_surfaces.sh does it)

Budgets (triangles): boulder 6000, rock 2500, stone 1200, cliff piece 12000. Already-light meshes are left alone.
"""
import os, sys
import bpy

ROOT = os.path.abspath("data/models/rocks")
BUDGET = {"boulder": 6000, "rock": 2500, "stone": 1200, "cliff": 12000}
ROLE = {
    "namaqualand_boulder_02": "boulder", "namaqualand_boulder_03": "boulder", "namaqualand_boulder_04": "boulder",
    "namaqualand_boulder_05": "boulder", "namaqualand_boulder_06": "boulder",
    "namaqualand_boulders_01": "rock", "namaqualand_rocks_01": "rock", "rock_07": "rock",
    "namaqualand_stones_01": "stone", "rock_09": "stone", "stone_01": "stone",
    "namaqualand_cliff_01": "cliff", "namaqualand_cliff_02": "cliff", "rock_face_01": "cliff", "rock_face_02": "cliff",
    "moon_rock_02": "stone", "moon_rock_03": "stone", "moon_rock_04": "stone", "moon_rock_05": "stone",
    "moon_rock_06": "stone", "moon_rock_07": "stone",
}


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def process(model, role):
    d = os.path.join(ROOT, model)
    gltf = next((f for f in os.listdir(d) if f.endswith(".gltf")), None)
    if gltf is None:
        return
    out_dir = os.path.join(d, "game")
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(d, gltf))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and "LOD" not in o.name.upper().replace("LOD0", "")]
    for ob in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        # bake the import transform into the mesh, origin to the bottom-centre (so burial offsets are predictable)
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        tris = tri_count(ob)
        budget = BUDGET[role]
        if tris > budget * 1.15:
            mod = ob.modifiers.new("dec", "DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = budget / tris
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier="dec")
        bb = [ob.matrix_world @ v.co for v in ob.data.vertices]
        cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
        cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
        cz = min(v.z for v in bb)
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            v.co = (w.x - cx, w.y - cy, w.z - cz)
        ob.matrix_world.identity()
        name = ob.name.replace(".", "_")
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, name + ".glb"), use_selection=True,
                                  export_format="GLB", export_image_format="AUTO")
        lod0 = tri_count(ob)
        # LOD1 at 30% for distance (VoxelInstanceLibraryMultiMeshItem.mesh_lod1)
        mod = ob.modifiers.new("dec1", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = 0.3
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="dec1")
        bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, name + "_lod1.glb"), use_selection=True,
                                  export_format="GLB", export_image_format="AUTO")
        print(f"ROCKDEC {model:24s} {name:30s} {tris:7d} -> {lod0:6d} / {tri_count(ob):5d} tris")


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for model, role in ROLE.items():
        if only and model not in only:
            continue
        if os.path.isdir(os.path.join(ROOT, model)):
            process(model, role)


main()
