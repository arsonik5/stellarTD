"""Review renders for any building .blend (Eevee, dark sky, regolith ground, player stand-in for scale).
blender -b <file.blend> -P render_building.py -- <outdir> <prefix> [views...]
views: hero back left right high close scale painted idle   (default: hero back high scale painted)
Meshes whose origin sits below the ground (ship parts, foundation) are lifted so they rest on it.
"""
import sys, math, os
import bpy, bmesh
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT, PREFIX = ARGS[0], ARGS[1]
VIEWS = ARGS[2:] or ["hero", "back", "high", "scale", "painted"]
sc = bpy.context.scene
meshes = [o for o in bpy.data.objects if o.type == 'MESH']

for eng in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
for attr, val in (("taa_render_samples", 64), ("use_raytracing", True), ("use_shadows", True)):
    try:
        setattr(sc.eevee, attr, val)
    except Exception:
        pass
sc.render.resolution_x, sc.render.resolution_y = 1280, 960
sc.view_settings.view_transform = 'AgX'
try:
    sc.view_settings.look = 'AgX - Medium High Contrast'
except Exception:
    pass

# lift onto ground
minz = min((o.matrix_world @ Vector(c)).z for o in meshes for c in o.bound_box)
if minz < -0.001:
    for o in meshes:
        if o.parent is None:          # children (nested moving parts) follow their parent
            o.location.z -= minz
bpy.context.view_layer.update()
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
ctr = (lo + hi) / 2
size = max(hi - lo)

# world: studio HDRI lights the scene, camera sees a dark space sky
w = bpy.data.worlds.new("W"); sc.world = w
w.use_nodes = True
nt = w.node_tree
bg = nt.nodes["Background"]
hdr = os.path.join(bpy.utils.system_resource('DATAFILES', path="studiolights/world"), "sunset.exr")
env = nt.nodes.new("ShaderNodeTexEnvironment"); env.image = bpy.data.images.load(hdr)
nt.links.new(env.outputs["Color"], bg.inputs["Color"]); bg.inputs["Strength"].default_value = 0.55
sky = nt.nodes.new("ShaderNodeBackground")
geo = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.0; ramp.color_ramp.elements[0].color = (0.05, 0.035, 0.03, 1)
ramp.color_ramp.elements[1].position = 0.12; ramp.color_ramp.elements[1].color = (0.004, 0.006, 0.015, 1)
nt.links.new(geo.outputs["Generated"], sep.inputs[0]); nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], sky.inputs["Color"])
lp = nt.nodes.new("ShaderNodeLightPath"); mix = nt.nodes.new("ShaderNodeMixShader")
nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
nt.links.new(bg.outputs["Background"], mix.inputs[1]); nt.links.new(sky.outputs["Background"], mix.inputs[2])
nt.links.new(mix.outputs[0], nt.nodes["World Output"].inputs["Surface"])

sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 3.2; sun.angle = math.radians(3); sun.color = (1.0, 0.95, 0.88)
so = bpy.data.objects.new("Sun", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(35))
rim = bpy.data.lights.new("Rim", 'SUN'); rim.energy = 1.4; rim.color = (0.6, 0.75, 1.0)
ro = bpy.data.objects.new("Rim", rim); sc.collection.objects.link(ro); ro.rotation_euler = (math.radians(65), 0, math.radians(200))

g = bpy.data.meshes.new("Ground")
bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40); bm.to_mesh(g); bm.free()
go = bpy.data.objects.new("Ground", g); sc.collection.objects.link(go); go.location.z = -0.001
gm = bpy.data.materials.new("Regolith"); gm.use_nodes = True
pb = gm.node_tree.nodes["Principled BSDF"]
noise = gm.node_tree.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 0.6; noise.inputs["Detail"].default_value = 8.0
gr = gm.node_tree.nodes.new("ShaderNodeValToRGB")
gr.color_ramp.elements[0].color = (0.05, 0.043, 0.038, 1); gr.color_ramp.elements[1].color = (0.12, 0.10, 0.085, 1)
gm.node_tree.links.new(noise.outputs["Fac"], gr.inputs["Fac"]); gm.node_tree.links.new(gr.outputs["Color"], pb.inputs["Base Color"])
pb.inputs["Roughness"].default_value = 0.95
g.materials.append(gm)

cam_d = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
tgt = bpy.data.objects.new("Tgt", None); sc.collection.objects.link(tgt)
tc = cam.constraints.new('TRACK_TO'); tc.target = tgt; tc.track_axis = 'TRACK_NEGATIVE_Z'; tc.up_axis = 'UP_Y'

mats = {m.name: m for m in bpy.data.materials}
def bsdf(n):
    return mats[n].node_tree.nodes["Principled BSDF"]
DEFAULT_PAINT = tuple(tuple(mats[n]["default_rgb"]) if "default_rgb" in mats[n] else tuple(bsdf(n).inputs["Base Color"].default_value[:3])
                      for n in ("M_Paint_Primary", "M_Paint_Secondary") if n in mats)

def set_paint(primary, secondary):
    """Same maths the Godot paint shader will use: albedo = D * mix(1, paint / default_grey, RM.r)."""
    for n, c in (("M_Paint_Primary", primary), ("M_Paint_Secondary", secondary)):
        if n not in mats:
            continue
        m = mats[n]
        nt = m.node_tree
        b = bsdf(n)
        if "default_rgb" not in m:                       # unbaked model: plain colour
            b.inputs["Base Color"].default_value = (*c, 1)
            continue
        if "PAINT_MIX" not in nt.nodes:
            texs = [x for x in nt.nodes if x.type == 'TEX_IMAGE']
            d = next(x for x in texs if x.image.name.endswith("_D"))
            sepn = next(x for x in nt.nodes if x.type == 'SEPARATE_COLOR')
            tint = nt.nodes.new("ShaderNodeMix"); tint.data_type = 'RGBA'; tint.name = "PAINT_MIX"
            tint.inputs["A"].default_value = (1, 1, 1, 1)
            nt.links.new(sepn.outputs["Red"], tint.inputs["Factor"])
            mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = 'RGBA'; mul.blend_type = 'MULTIPLY'
            mul.inputs["Factor"].default_value = 1.0
            nt.links.new(d.outputs["Color"], mul.inputs["A"])
            nt.links.new(tint.outputs["Result"], mul.inputs["B"])
            nt.links.new(mul.outputs["Result"], b.inputs["Base Color"])
        dflt = list(m["default_rgb"])
        ratio = tuple(min(c[i] / max(dflt[i], 1e-3), 8.0) for i in range(3))
        nt.nodes["PAINT_MIX"].inputs["B"].default_value = (*ratio, 1)

def set_emission(on):
    for n in ("M_Emissive_Heat", "M_Emissive_Status"):
        if n in mats:
            bsdf(n).inputs["Emission Strength"].default_value = (1.6 if n.endswith("Heat") else 1.2) if on else 0.0

def shot(name, direction, elev, dist_k=1.0, look_z=None, lens=40):
    d = max(size, 1.2) * 2.15 * dist_k
    dv = Vector(direction).normalized()
    cam.location = Vector((ctr.x + dv.x * d, ctr.y + dv.y * d, max(elev, 0.3)))
    tgt.location = Vector((ctr.x, ctr.y, look_z if look_z is not None else ctr.z))
    cam_d.lens = lens
    sc.render.filepath = f"{OUT}/{PREFIX}_{name}.png"
    bpy.ops.render.render(write_still=True)

def add_player(pos):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=1.5, location=(pos[0], pos[1], 0.75), vertices=24)
    a = bpy.context.active_object
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.13, location=(pos[0], pos[1], 1.67))
    b = bpy.context.active_object
    pm = bpy.data.materials.new("Player"); pm.use_nodes = True
    pm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.45, 0.6, 1)
    for o in (a, b):
        o.data.materials.append(pm)
        bpy.ops.object.shade_smooth()
    return (a, b)

eye = 1.7 if size > 1.0 else 1.2
for v in VIEWS:
    if v == "hero":
        shot("hero", (0.62, -0.78, 0), max(eye, hi.z * 0.75))
    elif v == "back":
        shot("back", (-0.6, 0.8, 0), max(eye, hi.z * 0.8))
    elif v == "left":
        shot("left", (-0.97, -0.24, 0), max(eye * 0.9, hi.z * 0.6))
    elif v == "right":
        shot("right", (0.97, 0.24, 0), max(eye * 0.9, hi.z * 0.6))
    elif v == "high":
        shot("high", (0.6, -0.8, 0), ctr.z + size * 1.7)
    elif v == "close":
        shot("close", (0.5, -0.86, 0), max(1.2, hi.z * 0.6), dist_k=0.55)
    elif v == "scale":
        pl = add_player((lo.x - 0.6, lo.y - 0.2))
        shot("scale", (0.35, -0.94, 0), 1.6, dist_k=1.25, look_z=max(1.0, ctr.z))
        for o in pl:
            o.hide_render = True
    elif v == "painted":
        set_paint((0.78, 0.33, 0.05), (0.07, 0.075, 0.08))
        shot("painted", (0.62, -0.78, 0), max(eye, hi.z * 0.75))
        if DEFAULT_PAINT:
            set_paint(*DEFAULT_PAINT)
    elif v == "idle":
        set_emission(False)
        shot("idle", (0.62, -0.78, 0), max(eye, hi.z * 0.75))
        set_emission(True)
print("RENDERS DONE")
