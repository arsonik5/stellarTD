"""Renders every building together as a small outpost (art_src/base_*.png).
blender -b -P art_src/base_scene.py -- <repo root (Windows path)>
Uses the exported .glb files, so it shows exactly what Godot will get."""
import sys, os, math
import bpy, bmesh
from mathutils import Vector

ROOT = sys.argv[sys.argv.index("--") + 1]
M = os.path.join(ROOT, "data", "models", "buildings")
OUT = os.path.join(ROOT, "art_src")
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def place(name, loc, yaw=0.0):
    """Import data/models/buildings/<name>/*.glb and move all its root objects."""
    folder = os.path.join(M, name)
    glb = [f for f in os.listdir(folder) if f.endswith(".glb")][0]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(folder, glb))
    new = [o for o in bpy.data.objects if o not in before]
    # like Godot: the model lives under one root node, so animated parts stay relative to the building
    root = bpy.data.objects.new(f"Root_{name}", None)
    sc.collection.objects.link(root)
    root.location = loc
    root.rotation_euler.z = math.radians(yaw)
    for o in new:
        if o.parent is None:
            o.parent = root
    return new


TOP = 0.25          # foundation top (foundation origin is its centre, 0.25 thick)
# foundation deck: 6 x 3 tiles
for ix in range(6):
    for iy in range(3):
        place("foundation", (-5 + 2 * ix, -2 + 2 * iy, 0.125))
# machines on the deck
place("smelter", (-4.0, 2.0, TOP))
place("crafter", (-1.0, 2.0, TOP))
place("constructor", (1.5, 2.0, TOP))
place("chest", (4.0, 2.0, TOP))
# pipe line in front of them along X (pipe model runs along Y, so turn it 90 degrees)
for k in range(9):
    x = -4.05 + 0.9 * k
    if k == 3:
        place("merger", (x, 0.2, TOP + 0.45), yaw=-90)
    elif k == 6:
        place("splitter", (x, 0.2, TOP + 0.45), yaw=-90)
    else:
        place("pipe", (x, 0.2, TOP + 0.45), yaw=-90)
# defence on the front corners
place("turret_gun", (-4.5, -2.2, TOP), yaw=160)
place("turret_cannon", (4.5, -2.2, TOP), yaw=200)
# ship garage beside the deck with a small ship on the pad (cockpit + core + thruster in a line)
GX, GY = 9.0, 0.5
place("ship_garage", (GX, GY, 0.0))
SZ = 0.28 + 1.0
place("ship_cockpit", (GX, GY + 1.6, 0.28 + 0.8))
place("ship_core", (GX, GY - 0.4, SZ))
place("ship_thruster", (GX, GY - 2.2, SZ))
for s in (-1, 1):
    place("ship_hull", (GX + s * 2.0, GY - 0.4, SZ))          # side armour blocks on the core
place("ship_gyroscope", (GX + 3.6, GY + 2.6, 0.8))

# ---------------------------------------------------------------- look: same lighting as the review renders
for eng in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
for attr, val in (("taa_render_samples", 96), ("use_raytracing", True), ("use_shadows", True)):
    try:
        setattr(sc.eevee, attr, val)
    except Exception:
        pass
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
sc.view_settings.view_transform = 'AgX'
try:
    sc.view_settings.look = 'AgX - Medium High Contrast'
except Exception:
    pass
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
nt = w.node_tree
bg = nt.nodes["Background"]
env = nt.nodes.new("ShaderNodeTexEnvironment")
env.image = bpy.data.images.load(os.path.join(bpy.utils.system_resource('DATAFILES', path="studiolights/world"), "sunset.exr"))
nt.links.new(env.outputs["Color"], bg.inputs["Color"]); bg.inputs["Strength"].default_value = 0.5
sky = nt.nodes.new("ShaderNodeBackground")
geo = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.0; ramp.color_ramp.elements[0].color = (0.06, 0.04, 0.035, 1)
ramp.color_ramp.elements[1].position = 0.15; ramp.color_ramp.elements[1].color = (0.003, 0.005, 0.014, 1)
nt.links.new(geo.outputs["Generated"], sep.inputs[0]); nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], sky.inputs["Color"])
lp = nt.nodes.new("ShaderNodeLightPath"); mix = nt.nodes.new("ShaderNodeMixShader")
nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
nt.links.new(bg.outputs["Background"], mix.inputs[1]); nt.links.new(sky.outputs["Background"], mix.inputs[2])
nt.links.new(mix.outputs[0], nt.nodes["World Output"].inputs["Surface"])
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 3.4; sun.angle = math.radians(2); sun.color = (1.0, 0.94, 0.86)
so = bpy.data.objects.new("Sun", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(55), 0, math.radians(30))
rim = bpy.data.lights.new("Rim", 'SUN'); rim.energy = 1.5; rim.color = (0.6, 0.75, 1.0)
ro = bpy.data.objects.new("Rim", rim); sc.collection.objects.link(ro); ro.rotation_euler = (math.radians(70), 0, math.radians(210))

g = bpy.data.meshes.new("Ground")
bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=80); bm.to_mesh(g); bm.free()
go = bpy.data.objects.new("Ground", g); sc.collection.objects.link(go); go.location.z = -0.002
gm = bpy.data.materials.new("Regolith"); gm.use_nodes = True
pb = gm.node_tree.nodes["Principled BSDF"]
nz = gm.node_tree.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 0.35; nz.inputs["Detail"].default_value = 10.0
gr = gm.node_tree.nodes.new("ShaderNodeValToRGB")
gr.color_ramp.elements[0].color = (0.045, 0.038, 0.033, 1); gr.color_ramp.elements[1].color = (0.13, 0.105, 0.085, 1)
gm.node_tree.links.new(nz.outputs["Fac"], gr.inputs["Fac"]); gm.node_tree.links.new(gr.outputs["Color"], pb.inputs["Base Color"])
pb.inputs["Roughness"].default_value = 0.95
g.materials.append(gm)

cam_d = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
tgt = bpy.data.objects.new("Tgt", None); sc.collection.objects.link(tgt)
tc = cam.constraints.new('TRACK_TO'); tc.target = tgt; tc.track_axis = 'TRACK_NEGATIVE_Z'; tc.up_axis = 'UP_Y'


def shot(name, loc, look, lens=32):
    cam.location = loc; tgt.location = look; cam_d.lens = lens
    sc.render.filepath = os.path.join(OUT, f"base_{name}.png")
    bpy.ops.render.render(write_still=True)


if "--anim" in sys.argv:
    # every imported animation plays and repeats (spinners loop seamlessly); render 6 s of the ground view
    import math as _m
    for o in bpy.data.objects:
        ad = o.animation_data
        if not ad:
            continue
        if ad.action:
            tr = ad.nla_tracks.new()
            tr.strips.new(ad.action.name, 0, ad.action)
            ad.action = None
        for tr in ad.nla_tracks:
            tr.mute = False
            for st in tr.strips:
                length = max(1.0, st.action_frame_end - st.action_frame_start)
                st.repeat = _m.ceil(150 / length)
    sc.render.fps = 24
    sc.frame_start, sc.frame_end = 0, 143
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.eevee.taa_render_samples = 32
    cam.location = (-2.5, -8.5, 2.6); tgt.location = (0.0, 1.5, 1.0); cam_d.lens = 30
    os.makedirs(os.path.join(OUT, "anim"), exist_ok=True)
    sc.render.filepath = os.path.join(OUT, "anim", "f_")
    sc.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(animation=True)
    print("BASE DONE")
    sys.exit(0)

shot("overview", (-7.5, -14.0, 7.5), (2.0, 0.5, 0.6), lens=30)
shot("ground", (-1.5, -7.0, 1.7), (0.5, 1.5, 1.1), lens=28)
shot("ship", (15.5, -7.5, 4.2), (9.0, 0.3, 1.3), lens=35)
shot("joint", (-1.0, -1.6, 1.15), (-1.35, 0.2, 0.7), lens=45)   # pipe -> merger -> pipe, up close
print("BASE DONE")
