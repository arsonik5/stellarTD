"""Stellar TD building kit - shared parts, materials and export for every building generator.

Conventions (match the approved Smelter, art_src/smelter/smelter.py):
- 1 unit = 1 m. Blender Z up. glTF export turns Blender -Y into Godot +Z, so Godot's forward (-Z) is Blender +Y.
- Material slots: Paint_Primary / Paint_Secondary are the paint-tool slots (grey by default). The rest are fixed.
- Every part is built as its own closed mesh, beveled by weight (2 segments, harden normals), then joined per group.
Usage inside a generator: `import kit; kit.begin(out_dir)`, build parts, then `kit.finish("SM_Name", groups)`.
"""
import sys, os, math
import bpy, bmesh
from mathutils import Vector, Matrix

OUT = None
MATS = []
PRI, SEC, BARE, RUB, HAZ, HEAT, STAT, GLASS, WELD = range(9)
parts = []
_group = ["main"]
SPEC = {}                                   # prefix -> dict(job, on, joint, joins); see part() and audit.py
BLOCKOUT = os.environ.get("BLOCKOUT") == "1"  # blockout stage: big parts only, no fasteners/welds, no bake/export


def part(prefix, job, on=None, joint=None, joins=()):
    """Declare a part: what it does, what it is mounted on (a part prefix or 'ground') and how (audit.JOINTS).
    Every object whose name starts with `prefix` is covered (the longest declared prefix wins); a sub-part that
    leaves out on/joint inherits them from the nearest shorter declared prefix. No declaration, no part."""
    SPEC[prefix] = dict(job=job, on=on, joint=joint, joins=tuple(joins))


# ------------------------------------------------------------------ setup / materials
def begin(out_dir):
    global OUT, MATS
    OUT = out_dir
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = 'METRIC'
    parts.clear()
    SPEC.clear()
    MATS = [
        principled("M_Paint_Primary",   (0.16, 0.165, 0.17), 0.4, 0.42),
        principled("M_Paint_Secondary", (0.045, 0.047, 0.05), 0.5, 0.5),
        principled("M_Metal_Bare",      (0.62, 0.62, 0.62), 1.0, 0.32),
        principled("M_Rubber_Dark",     (0.018, 0.018, 0.02), 0.0, 0.85),
        hazard_material(),
        principled("M_Emissive_Heat",   (0.9, 0.28, 0.02), 0.0, 0.4, (1.0, 0.2, 0.01), 1.6),
        principled("M_Emissive_Status", (0.05, 0.25, 0.1), 0.0, 0.3, (0.2, 0.9, 0.35), 1.2),
        glass_material(),
        principled("M_Paint_Secondary_Weld", (0.05, 0.052, 0.055), 0.45, 0.72),   # 8 weld beads: painted over, never chipped
    ]


def principled(name, rgb, metal=0.0, rough=0.5, emit=None, emit_str=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_str
    m.diffuse_color = (*rgb, 1)
    return m


def glass_material():
    m = principled("M_Glass", (0.35, 0.45, 0.5), 0.0, 0.08)
    m.node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.22
    try:
        m.surface_render_method = 'BLENDED'
    except Exception:
        m.blend_method = 'BLEND'
    m.diffuse_color = (0.35, 0.45, 0.5, 0.22)
    return m


def hazard_material():
    n = 128
    img = bpy.data.images.new("T_Hazard_D", n, n)
    px = []
    for y in range(n):
        for x in range(n):
            c = (0.85, 0.58, 0.04) if ((x + y) // 16) % 2 == 0 else (0.025, 0.025, 0.025)
            px += [c[0], c[1], c[2], 1.0]
    img.pixels = px
    img.filepath_raw = f"{OUT}/T_Hazard_D.png"
    img.file_format = 'PNG'
    img.save()
    m = principled("M_Hazard", (0.5, 0.4, 0.05), 0.2, 0.6)
    nt = m.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return m


class group:
    """`with kit.group("Head"):` - parts built inside go into a separately exported mesh."""
    def __init__(self, name):
        self.name = name
    def __enter__(self):
        self.prev = _group[0]
        _group[0] = self.name
    def __exit__(self, *a):
        _group[0] = self.prev


# ------------------------------------------------------------------ mesh helpers
def fix_ngons(bm):
    ng = [f for f in bm.faces if len(f.verts) > 4]
    if ng:
        res = bmesh.ops.triangulate(bm, faces=ng, quad_method='BEAUTY', ngon_method='BEAUTY')
        bmesh.ops.join_triangles(bm, faces=res["faces"], angle_face_threshold=math.radians(5),
                                 angle_shape_threshold=math.radians(180))


def box_uv(bm, scale=2.5):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            co = l.vert.co
            l[uv].uv = ((co.y, co.z), (co.x, co.z), (co.x, co.y))[ax]
            l[uv].uv = (l[uv].uv[0] * scale, l[uv].uv[1] * scale)


def make_obj(name, bm, bevel, smooth=True):
    fix_ngons(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    bw = bm.edges.layers.float.get("bevel_weight_edge") or bm.edges.layers.float.new("bevel_weight_edge")
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(25):
            e[bw] = 1.0
    for f in bm.faces:
        f.smooth = smooth and bevel > 0
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in MATS:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob["bevel"] = bevel
    ob["group"] = _group[0]
    bpy.context.scene.collection.objects.link(ob)
    parts.append(ob)
    return ob


def set_mat(bm, mat, faces=None):
    for f in (faces if faces is not None else bm.faces):
        f.material_index = mat


def transform(bm, mtx):
    bmesh.ops.transform(bm, matrix=mtx, verts=bm.verts)


def rotz(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Z')


def box(name, size, center, mat, bevel=0.012, rot=None, taper=1.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        s = taper if v.co.z > 0 else 1.0
        v.co = Vector((v.co.x * size[0] * s, v.co.y * size[1] * s, v.co.z * size[2]))
    if rot:
        transform(bm, rot)
    transform(bm, Matrix.Translation(center))
    set_mat(bm, mat)
    return make_obj(name, bm, bevel)


FASTENER_WORDS = ("Bolt", "Screw", "Nut")


def _fastener(bm, r, h):
    """Real fastener head along +Z, seated at z=-h/2: round washer on the surface, hex head, chamfered top."""
    hw, hh, hc = 0.24 * h, 0.56 * h, 0.2 * h
    z = -h / 2
    for (r1, r2, d, seg) in ((r * 1.45, r * 1.45, hw, 16), (r, r, hh, 6), (r, r * 0.78, hc, 6)):
        geom = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=d)
        vs = [v for v in geom["verts"]]
        bmesh.ops.translate(bm, verts=vs, vec=(0, 0, z + d / 2))
        z += d


def cyl(name, r, h, center, mat, seg=24, axis='Z', r2=None, bevel=0.008, smooth=True, rot=None):
    """Cylinder along `axis` ('X','Y','Z', optionally signed: '-Y' points the top the other way).
    A 6-sided cylinder named *Bolt*/*Screw*/*Nut* is built as a real fastener (washer, hex head, chamfer) whose
    washer sits on the surface at the -axis end."""
    bm = bmesh.new()
    kind = "part"
    if seg == 6 and any(k in name for k in FASTENER_WORDS):
        if BLOCKOUT:
            bm.free()
            return None
        _fastener(bm, r, h)
        bevel, smooth, kind = 0.0, False, "fastener"
    else:
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=r, radius2=(r if r2 is None else r2), depth=h)
    ax = axis.lstrip('+')
    if ax == 'X':
        transform(bm, Matrix.Rotation(math.pi / 2, 4, 'Y'))
    elif ax == '-X':
        transform(bm, Matrix.Rotation(-math.pi / 2, 4, 'Y'))
    elif ax == 'Y':
        transform(bm, Matrix.Rotation(-math.pi / 2, 4, 'X'))
    elif ax == '-Y':
        transform(bm, Matrix.Rotation(math.pi / 2, 4, 'X'))
    elif ax == '-Z':
        transform(bm, Matrix.Rotation(math.pi, 4, 'X'))
    if rot:
        transform(bm, rot)
    transform(bm, Matrix.Translation(center))
    set_mat(bm, mat)
    ob = make_obj(name, bm, bevel, smooth)
    ob["kind"] = kind
    return ob


def tube(name, r_out, r_in, h, center, mat, seg=24, axis='Z', bevel=0.004):
    """Closed thick-walled ring (manifold), e.g. collars and glass tubes."""
    bm = bmesh.new()
    vs = []
    for z in (-h / 2, h / 2):
        for r in (r_out, r_in):
            vs.append([bm.verts.new((math.cos(2 * math.pi * i / seg) * r, math.sin(2 * math.pi * i / seg) * r, z))
                       for i in range(seg)])
    bo, bi, to, ti = vs
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((bo[i], bo[j], to[j], to[i]))
        bm.faces.new((ti[i], ti[j], bi[j], bi[i]))
        bm.faces.new((to[i], to[j], ti[j], ti[i]))
        bm.faces.new((bi[i], bi[j], bo[j], bo[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if axis == 'X':
        transform(bm, Matrix.Rotation(math.pi / 2, 4, 'Y'))
    elif axis == 'Y':
        transform(bm, Matrix.Rotation(-math.pi / 2, 4, 'X'))
    transform(bm, Matrix.Translation(center))
    set_mat(bm, mat)
    return make_obj(name, bm, bevel)


def octo(name, w, d, chamfer, z0, z1, mat, bevel=0.012, inset=None, taper=1.0):
    """Chamfered-corner prism. inset=(thickness, depth) recesses a panel into every side face."""
    hw, hd, c = w / 2, d / 2, chamfer
    pts = [(-hw + c, -hd), (hw - c, -hd), (hw, -hd + c), (hw, hd - c),
           (hw - c, hd), (-hw + c, hd), (-hw, hd - c), (-hw, -hd + c)]
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in pts]
    top = [bm.verts.new((x * taper, y * taper, z1)) for x, y in pts]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    sides = [bm.faces.new((bot[i], bot[(i + 1) % 8], top[(i + 1) % 8], top[i])) for i in range(8)]
    bm.normal_update()
    set_mat(bm, mat)
    if inset:
        bmesh.ops.inset_individual(bm, faces=sides, thickness=inset[0], depth=0.0)
        bmesh.ops.inset_individual(bm, faces=sides, thickness=0.004, depth=-inset[1])
    return make_obj(name, bm, bevel)


def basis(normal, up=(0, 0, 1)):
    """4x4 rotation mapping local X->right, Y->up, Z->normal for a face with outward `normal`."""
    n = Vector(normal).normalized()
    u = Vector(up)
    u = u - n * u.dot(n)
    if u.length < 1e-6:                      # up parallel to the normal: any perpendicular will do
        u = Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))
        u = u - n * u.dot(n)
    u.normalize()
    r = u.cross(n)
    return Matrix((r, u, n)).transposed().to_4x4()


def plate(name, center, normal, w, h, t=0.022, clip=0.05, mat=PRI, up=(0, 0, 1), bolt_inset=0.035, bolts_on=True,
          bevel=0.005, slots=0):
    """Armour plate standing proud of a face: clipped corners, bevelled rim, hex bolts in the corners.
    center lies on the face; the plate grows outward along `normal` by t. slots: dark vent slots across the plate."""
    hw, hh, c = w / 2, h / 2, min(clip, w / 3, h / 3)
    pts = [(-hw + c, -hh), (hw - c, -hh), (hw, -hh + c), (hw, hh - c), (hw - c, hh), (-hw + c, hh), (-hw, hh - c), (-hw, -hh + c)]
    bm = bmesh.new()
    back = [bm.verts.new((x, y, 0.0)) for x, y in pts]
    front = [bm.verts.new((x, y, t)) for x, y in pts]
    bm.faces.new(list(reversed(back)))
    bm.faces.new(front)
    for i in range(8):
        bm.faces.new((back[i], back[(i + 1) % 8], front[(i + 1) % 8], front[i]))
    M = Matrix.Translation(center) @ basis(normal, up)
    transform(bm, M)
    set_mat(bm, mat)
    make_obj(name, bm, bevel)
    if slots:
        part(name + "S", "vent slot cut in the plate", name, "inset")
    bolt_inset = max(bolt_inset, c * 0.5 + 0.026)       # fully on the plate, clear of the clipped corner
    if bolts_on and min(w, h) > 0.12:
        for sx in (-1, 1):
            for sy in (-1, 1):
                p = M @ Vector((sx * (hw - bolt_inset), sy * (hh - bolt_inset), t + 0.007))
                cyl(f"{name}Bolt{sx}{sy}", 0.011, 0.014, (0, 0, 0), BARE, seg=6, bevel=0.0, rot=Matrix.Translation(p) @ basis(normal, up))
    for k in range(slots):
        v = -hh * 0.45 + (hh * 0.9) * (k + 0.5) / slots
        p = M @ Vector((0, v, t + 0.002))
        box(f"{name}S{k}", (w * 0.55, 0.018, 0.006), (0, 0, 0), RUB, bevel=0.0,
            rot=Matrix.Translation(p) @ basis(normal, up))


def recess_box(name, size, center, frame_mat, ring_mat, hole_mat, face_axis='-Y', frame=0.07, depth=0.12, bevel=0.008):
    """Box whose face on `face_axis` has a flat frame ring (ring_mat) around a recessed opening (hole_mat)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    transform(bm, Matrix.Diagonal((*size, 1)))
    transform(bm, Matrix.Translation(center))
    set_mat(bm, frame_mat)
    bm.normal_update()
    ax = {'X': 0, 'Y': 1, 'Z': 2}[face_axis[-1]]
    sgn = -1 if face_axis[0] == '-' else 1
    face = [f for f in bm.faces if f.normal[ax] * sgn > 0.9]
    before = set(bm.faces)
    bmesh.ops.inset_individual(bm, faces=face, thickness=frame, depth=0.0)
    set_mat(bm, ring_mat, [f for f in bm.faces if f not in before])
    before = set(bm.faces)
    bmesh.ops.inset_individual(bm, faces=face, thickness=0.003, depth=-depth)
    set_mat(bm, hole_mat, face + [f for f in bm.faces if f not in before])
    return make_obj(name, bm, bevel)


def pipe(name, pts, r, mat, fillet=0.12, seg=12, bevel=0.004):
    """Poly-line pipe with rounded elbows (curve sweep -> mesh)."""
    P = [Vector(p) for p in pts]
    out = [P[0]]
    for i in range(1, len(P) - 1):
        a, b, c = P[i - 1], P[i], P[i + 1]
        d1, d2 = (b - a).normalized(), (c - b).normalized()
        f = min(fillet, (b - a).length / 2, (c - b).length / 2)
        p0, p2 = b - d1 * f, b + d2 * f
        for k in range(7):
            t = k / 6
            out.append((1 - t) ** 2 * p0 + 2 * (1 - t) * t * b + t * t * p2)
    out.append(P[-1])
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = r
    cu.bevel_resolution = max(1, seg // 4 - 1)
    cu.use_fill_caps = True
    sp = cu.splines.new('POLY')
    sp.points.add(len(out) - 1)
    for i, p in enumerate(out):
        sp.points[i].co = (p.x, p.y, p.z, 1)
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target='MESH')
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bpy.data.objects.remove(ob)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    set_mat(bm, mat)
    return make_obj(name, bm, bevel)


def torus(name, R, r, center, mat, rot=None, major=14, minor=6, bevel=0.0):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=major, minor_segments=minor)
    t = bpy.context.active_object
    bm = bmesh.new()
    bm.from_mesh(t.data)
    bpy.data.objects.remove(t)
    if rot:
        transform(bm, rot)
    transform(bm, Matrix.Translation(center))
    set_mat(bm, mat)
    return make_obj(name, bm, bevel, smooth=True)


def lathe(name, profile, center, mat, seg=24, axis='Z', bevel=0.0, mats=None):
    """Revolve a CLOSED profile [(r, h), ...] around the axis -> manifold solid (bells, nozzles, domes).
    mats: optional per-profile-edge material list (edge i goes from point i to i+1)."""
    bm = bmesh.new()
    n = len(profile)
    rings = []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), h)) for r, h in profile])
    open_axis = profile[0][0] == 0 and profile[-1][0] == 0   # both ends on the axis: no closing edge
    for k in range(seg):
        A, B = rings[k], rings[(k + 1) % seg]
        for i in range(n):
            if open_axis and i == n - 1:
                continue
            j = (i + 1) % n
            q = [A[i], A[j], B[j], B[i]]
            q = [v for idx, v in enumerate(q) if v not in q[:idx]]
            if len(q) < 3:
                continue
            f = bm.faces.new(q)
            f.material_index = mats[i] if mats else mat
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if axis == 'Y':
        transform(bm, Matrix.Rotation(-math.pi / 2, 4, 'X'))
    elif axis == '-Y':
        transform(bm, Matrix.Rotation(math.pi / 2, 4, 'X'))
    elif axis == 'X':
        transform(bm, Matrix.Rotation(math.pi / 2, 4, 'Y'))
    transform(bm, Matrix.Translation(center))
    return make_obj(name, bm, bevel)


def bolts(prefix, center, normal_axis, radius, count, r=0.014, h=0.016, start=0.0):
    sgn = 1 if normal_axis[0] == '+' else -1
    ax = normal_axis[1]
    for i in range(count):
        a = start + 2 * math.pi * i / count
        u, v = math.cos(a) * radius, math.sin(a) * radius
        c = list(center)
        if ax == 'Y':
            c[0] += u; c[2] += v; c[1] += sgn * h / 2
        elif ax == 'X':
            c[1] += u; c[2] += v; c[0] += sgn * h / 2
        else:
            c[0] += u; c[1] += v; c[2] += sgn * h / 2
        cyl(f"{prefix}{i}", r, h, tuple(c), BARE, seg=6, axis=normal_axis, bevel=0.0)


# ------------------------------------------------------------------ shared assemblies (the visual kit)
def skid(w, z1=0.12, casting=0.16, name="Skid"):
    """Welded transport frame, built the way a container base is: four channel-steel side beams (flanges facing out)
    and a deck plate between them; at each corner an ISO-style corner casting is the node the two beams are welded
    into: same height as the beams, oval twist-lock apertures on the outer faces and on top (crane / lock points)."""
    h, fl, tf, tw = z1, 0.085, 0.016, 0.016
    cw = casting
    L = w - 2 * cw
    for sy in (-1, 1):            # beams along X (profile in the YZ plane)
        yo, yi = sy * w / 2, sy * (w / 2 - fl)
        pts = [(yi, 0), (yo, 0), (yo, tf), (yi + sy * tw, tf), (yi + sy * tw, h - tf), (yo, h - tf), (yo, h), (yi, h)]
        profile(f"{name}BeamX{sy}", pts, (0, 0, 0), (1, 0, 0), L, SEC, up=(0, 0, 1), bevel=0.004)
    for sx in (-1, 1):            # beams along Y (profile local u runs along -X)
        xo, xi = sx * w / 2, sx * (w / 2 - fl)
        pts = [(-xi, 0), (-xo, 0), (-xo, tf), (-(xi + sx * tw), tf), (-(xi + sx * tw), h - tf), (-xo, h - tf), (-xo, h), (-xi, h)]
        profile(f"{name}BeamY{sx}", pts, (0, 0, 0), (0, 1, 0), L, SEC, up=(0, 0, 1), bevel=0.004)
    # deck plate: fills between the beams, notched round the corner castings (it butts against them, never into)
    a, b = w / 2 - fl + 0.001, w / 2 - cw
    deck = [(-b, -a), (b, -a), (b, -b), (a, -b), (a, b), (b, b), (b, a), (-b, a), (-b, b), (-a, b), (-a, -b), (-b, -b)]
    profile(f"{name}Deck", deck, (0, 0, h - tf / 2), (0, 0, 1), tf, SEC, up=(0, 1, 0), bevel=0.002)
    ap = squircle(cw * 0.3, cw * 0.15, 2.6, seg=24)
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = Vector((sx * (w / 2 - cw / 2), sy * (w / 2 - cw / 2), h / 2))
            box(f"{name}Casting_{sx}_{sy}", (cw, cw, h), tuple(c), SEC, bevel=0.004)
            for nrm, up in (((sx, 0, 0), (0, 0, 1)), ((0, sy, 0), (0, 0, 1)), ((0, 0, 1), (1, 0, 0))):
                n = Vector(nrm)
                half = cw / 2 if n.z == 0 else h / 2
                profile(f"{name}CastHole{nrm}_{sx}_{sy}", ap, tuple(c + n * (half - 0.0028)), nrm, 0.006, RUB, up=up, bevel=0.0)
            # beams welded into the casting in the inside corner, down the inner web (the top is a flush butt joint)
            jx = sx * (w / 2 - cw)                       # where the Y-running beam... (X-beam end plane)
            jy = sy * (w / 2 - cw)
            weld(f"{name}JWx_w_{sx}_{sy}", [(jx - sx * WELD_R, sy * (w / 2 - fl) - sy * WELD_R * 0.3, 0.01), (jx - sx * WELD_R, sy * (w / 2 - fl) - sy * WELD_R * 0.3, h)])
            weld(f"{name}JWy_w_{sx}_{sy}", [(sx * (w / 2 - fl) - sx * WELD_R * 0.3, jy - sy * WELD_R, 0.01), (sx * (w / 2 - fl) - sx * WELD_R * 0.3, jy - sy * WELD_R, h)])
    part(name + "Casting", "corner casting: crane and twist-lock point, the node the beams weld into", "ground", "ground")
    part(name + "Beam", "channel-steel side beam: carries the machine between the corner castings", name + "Casting", "welded")
    part(name + "Deck", "deck plate between the beams: the machine stands on it", name + "Beam", "inset")
    part(name + "CastHole", "twist-lock aperture in the casting", name + "Casting", "inset")


# ------------------------------------------------------------------ custom-shape tools (no more boxes)
def squircle(a, b, n=4.0, seg=48):
    """Superellipse outline |x/a|^n + |y/b|^n = 1 (a, b = half sizes). n=2 ellipse, n~4 rounded square."""
    pts = []
    for i in range(seg):
        t = 2 * math.pi * (i + 0.5) / seg
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2 / n), c), b * math.copysign(abs(s) ** (2 / n), s)))
    return pts


def loft(name, rings, mat, bevel=0.01, caps=True):
    """Skin a solid through cross-section rings (lists of 3D points, equal counts, same winding).
    Use for tapering hulls, square-to-round cowls, bulging bodies."""
    bm = bmesh.new()
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(rings[0])
    for k in range(len(vr) - 1):
        A, B = vr[k], vr[k + 1]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((A[i], A[j], B[j], B[i]))
    if caps:
        bm.faces.new(list(reversed(vr[0])))
        bm.faces.new(vr[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    set_mat(bm, mat)
    return make_obj(name, bm, bevel)


def zring(pts2d, z, sx=1.0, sy=1.0, ox=0.0, oy=0.0):
    return [(x * sx + ox, y * sy + oy, z) for x, y in pts2d]


def yring(pts2d, y, cz=0.0, cx=0.0):
    """Cross-section in the XZ plane at depth y (for hulls that run along +Y, e.g. turret heads)."""
    return [(x + cx, y, z + cz) for x, z in pts2d]


def match_ring(pts2d, seg):
    """Resample any closed 2D outline to `seg` points by angle around the origin (for square-to-round lofts)."""
    out = []
    for i in range(seg):
        t = 2 * math.pi * (i + 0.5) / seg
        d = Vector((math.cos(t), math.sin(t)))
        best = None
        for k in range(len(pts2d)):
            p, q = Vector(pts2d[k]), Vector(pts2d[(k + 1) % len(pts2d)])
            # ray from origin along d against segment p-q
            e = q - p
            den = d.x * e.y - d.y * e.x
            if abs(den) < 1e-9:
                continue
            u = (p.x * e.y - p.y * e.x) / den
            v = (p.x * d.y - p.y * d.x) / den
            if u > 0 and -1e-6 <= v <= 1 + 1e-6 and (best is None or u < best):
                best = u
        out.append((d.x * best, d.y * best))
    return out


def profile(name, pts2d, center, normal, depth, mat, up=(0, 0, 1), bevel=0.008):
    """Extrude any 2D silhouette (u right, v up, in the plane facing `normal`) by `depth`, centred on that plane."""
    bm = bmesh.new()
    back = [bm.verts.new((u, v, -depth / 2)) for u, v in pts2d]
    front = [bm.verts.new((u, v, depth / 2)) for u, v in pts2d]
    bm.faces.new(list(reversed(back)))
    bm.faces.new(front)
    n = len(pts2d)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((back[i], back[j], front[j], front[i]))
    transform(bm, Matrix.Translation(center) @ basis(normal, up))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    set_mat(bm, mat)
    return make_obj(name, bm, bevel)


# ------------------------------------------------------------------ fastening: every joint shows how it is held
WELD_R = 0.007


def weld(name, pts, r=WELD_R, mat=None, closed=False):
    """Fillet weld bead along a polyline (welded seams between two parts). Painted over, so it reads as a seam."""
    if BLOCKOUT:
        return None
    P = list(pts) + ([pts[0]] if closed else [])
    ob = pipe(name, P, r, WELD if mat is None else mat, fillet=0.0, seg=8, bevel=0.0)
    ob["kind"] = "weld"
    return ob


def weld_ring(name, center, R, axis='Z', r=WELD_R, mat=None):
    """Circular weld where a tube/round part meets a flat face (axis = the tube's axis)."""
    if BLOCKOUT:
        return None
    rot = {'Z': None, 'X': Matrix.Rotation(math.pi / 2, 4, 'Y'), 'Y': Matrix.Rotation(math.pi / 2, 4, 'X')}[axis[-1]]
    ob = torus(name, R, r, center, WELD if mat is None else mat, rot, major=max(12, int(R * 120)), minor=5)
    ob["kind"] = "weld"
    return ob


def saddle_weld(name, axis, R_neck, R_drum, mat=None, n=32, z0=0.0):
    """Weld where a horizontal neck (along +/-X or +/-Y, at height z0) leaves a vertical drum of radius R_drum
    standing on the Z axis."""
    if BLOCKOUT:
        return None
    a, sgn = axis[1], (1 if axis[0] == '+' else -1)
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        lat, z = math.cos(t) * R_neck, math.sin(t) * R_neck + z0
        along = math.sqrt(max(R_drum ** 2 - lat ** 2, 0.0)) + 0.002
        pts.append(Vector((sgn * along, lat, z) if a == 'X' else (lat, sgn * along, z)))
    # swept as one closed tube (a polyline weld leaves an open seam where its ends meet)
    m, r = 8, WELD_R
    bm = bmesh.new()
    rings = []
    for i in range(n):
        tng = (pts[(i + 1) % n] - pts[i - 1]).normalized()
        side = tng.cross(Vector((1, 0, 0) if a == 'X' else (0, 1, 0)))
        if side.length < 1e-6:
            side = tng.orthogonal()
        side.normalize()
        up = tng.cross(side).normalized()
        rings.append([bm.verts.new(pts[i] + (side * math.cos(2 * math.pi * k / m) + up * math.sin(2 * math.pi * k / m)) * r)
                      for k in range(m)])
    for i in range(n):
        A, B = rings[i], rings[(i + 1) % n]
        for k in range(m):
            bm.faces.new((A[k], A[(k + 1) % m], B[(k + 1) % m], B[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    set_mat(bm, WELD if mat is None else mat)
    ob = make_obj(name, bm, 0.0)
    ob["kind"] = "weld"
    return ob


def _bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return Vector([min(v[i] for v in vs) for i in range(3)]), Vector([max(v[i] for v in vs) for i in range(3)])


def box_weld(name, a, b, tol=0.002):
    """Fillet welds where two square-sided parts meet face to face (posts on plates, rails into posts...): a bead
    along every edge of the contact patch that has a face on the other part to weld onto. a, b: the objects."""
    if BLOCKOUT:
        return
    (alo, ahi), (blo, bhi) = _bounds(a), _bounds(b)
    for k in range(3):
        for lo_, hi_, sgn in ((ahi, blo, 1), (bhi, alo, -1)):
            if abs(lo_[k] - hi_[k]) > tol:
                continue
            o = [i for i in range(3) if i != k]
            r0 = [max(alo[i], blo[i]) for i in o]
            r1 = [min(ahi[i], bhi[i]) for i in o]
            if r1[0] - r0[0] < 0.005 or r1[1] - r0[1] < 0.005:
                continue
            plane = (lo_[k] + hi_[k]) / 2
            # the smaller face is the part being welded on; beads sit in the corner on the bigger part's face
            area_a = (ahi[o[0]] - alo[o[0]]) * (ahi[o[1]] - alo[o[1]])
            area_b = (bhi[o[0]] - blo[o[0]]) * (bhi[o[1]] - blo[o[1]])
            small_is_a = area_a <= area_b
            blo_, bhi_ = (blo, bhi) if small_is_a else (alo, ahi)       # the big part's bounds
            toward_small = -sgn if small_is_a else sgn                  # along k, from the plane into the small part
            off_k = plane + toward_small * WELD_R * 0.6
            n = 0
            for j, (axis_i, val, out) in enumerate(((o[0], r0[0], -1), (o[0], r1[0], 1), (o[1], r0[1], -1), (o[1], r1[1], 1))):
                beyond = (blo_[axis_i] < val - WELD_R * 1.5) if out < 0 else (bhi_[axis_i] > val + WELD_R * 1.5)
                if not beyond:
                    continue                                            # flush edge: nothing to weld onto
                other = o[1] if axis_i == o[0] else o[0]
                lo_o, hi_o = (r0[0], r1[0]) if other == o[0] else (r0[1], r1[1])
                p0, p1 = [0.0] * 3, [0.0] * 3
                for p, t in ((p0, lo_o), (p1, hi_o)):
                    p[k] = off_k
                    p[axis_i] = val + out * WELD_R * 0.6
                    p[other] = t
                weld(f"{name}{n}", [tuple(p0), tuple(p1)])
                n += 1
            return


def ship_frame(H=1.0, B=0.16, name="Frame"):
    """Ship block frame: 12 edge beams welded between 8 corner nodes, every outer face exactly on +/-H so blocks butt
    together on their frames. The corner nodes carry the coupling sockets blocks lock together with."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                recess_box(f"{name}Node{sx}{sy}{sz}", (B, B, B), (sx * (H - B / 2), sy * (H - B / 2), sz * (H - B / 2)),
                           BARE, BARE, RUB, ('+Z' if sz > 0 else '-Z'), frame=0.04, depth=0.02, bevel=0.008)
    part(name + "Node", "corner node: the beams weld into it, its socket couples the next block", "ground", "ground")
    for a in range(3):
        for s1 in (-1, 1):
            for s2 in (-1, 1):
                c = [0.0, 0.0, 0.0]
                o = [i for i in range(3) if i != a]
                c[o[0]] = s1 * (H - B / 2)
                c[o[1]] = s2 * (H - B / 2)
                size = [B - 0.04] * 3                            # beams slimmer than the nodes: the weld shows
                size[a] = 2 * H - 2 * B
                bm_ = box(f"{name}Beam{a}{s1}{s2}", tuple(size), tuple(c), SEC, bevel=0.01)
                for s in (-1, 1):
                    k = [0, 0, 0]; k[a] = s
                    node = [0, 0, 0]
                    node[a] = s; node[o[0]] = s1; node[o[1]] = s2
                    box_weld(f"{name}Weld{a}{s1}{s2}{s}_", bm_, bpy.data.objects[f"{name}Node{node[0]}{node[1]}{node[2]}"])
    part(name + "Beam", "edge beam: the block's structure", name + "Node", "welded")


def deck_plate(name, w, d, z_top, t=0.03, cells=2, tread=True):
    """Walkable deck: w x d plate, top at z_top, split into cells x cells panels by recessed seams, with a raised
    diamond tread (anti-slip) set into it. Centred on the origin. The caller declares the deck's mount."""
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=cells, y_segments=cells, size=0.5)
    for v in bm.verts:
        v.co.x *= w
        v.co.y *= d
    res = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for v in [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z -= t
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    transform(bm, Matrix.Translation((0, 0, z_top)))
    set_mat(bm, PRI)
    bm.normal_update()
    tops = [f for f in bm.faces if f.normal.z > 0.9]
    bmesh.ops.inset_individual(bm, faces=tops, thickness=0.025, depth=-0.006)
    make_obj(name, bm, 0.004)
    if tread:
        n = max(2, int(w / 0.22))
        for i in range(-n // 2, n // 2 + 1):
            for j in range(-n // 2, n // 2 + 1):
                x, y = i * 0.22 + 0.11 * (j % 2), j * 0.22
                if (i + j) % 2 == 0 and abs(x) < w / 2 - 0.12 and abs(y) < d / 2 - 0.12:
                    box(f"{name}Tread_{i}_{j}", (0.09, 0.02, 0.008), (x, y, z_top - 0.006 + 0.004), SEC, bevel=0.0, rot=rotz(45))
        part(name + "Tread", "anti-slip tread, set into the deck", name, "inset")


def foundation_block(h, name="F"):
    """2 x 2 m foundation of height h, origin at its CENTRE, every outer face exactly on +/-1.0 and +/-h/2 so blocks
    tile edge to edge. Low blocks (h <= 0.3): four perimeter beams carry the deck. Taller blocks: corner posts,
    top and bottom ring beams welded between them, cladding panels set into each side, the deck on top."""
    HW, z0, z1 = 1.0, -h / 2, h / 2
    B = 0.16
    L = 2.0 - 2 * B
    if h <= 0.3:
        for s in (-1, 1):
            recess_box(f"{name}BeamX{s}", (2.0, B, h), (0, s * (HW - B / 2), 0), SEC, SEC, RUB, ('+Y' if s > 0 else '-Y'),
                       frame=0.05, depth=0.02, bevel=0.006)
        for s in (-1, 1):
            by = recess_box(f"{name}BeamY{s}", (B, L, h), (s * (HW - B / 2), 0, 0), SEC, SEC, RUB, ('+X' if s > 0 else '-X'),
                            frame=0.05, depth=0.02, bevel=0.006)
            for sy in (-1, 1):
                box_weld(f"{name}BeamWeld{s}{sy}_", by, bpy.data.objects[f"{name}BeamX{sy}"])
        part(name + "BeamX", "perimeter beam: carries the deck, butts the next foundation", "ground", "ground")
        part(name + "BeamY", "perimeter beam: carries the deck", name + "BeamX", "welded")
        deck_plate(name + "Deck", L, L, z1)
        part(name + "Deck", "deck plate: what you walk and build on", name + "Beam", "inset")
        return
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"{name}Post_{sx}_{sy}", (B, B, h), (sx * (HW - B / 2), sy * (HW - B / 2), 0), SEC, bevel=0.008)
    part(name + "Post", "corner post: carries the deck down to the ground", "ground", "ground")
    for k, zc in enumerate((z0 + B / 2, z1 - B / 2)):
        for s in (-1, 1):
            bx = box(f"{name}Ring{k}X{s}", (L, B, B), (0, s * (HW - B / 2), zc), SEC, bevel=0.008)
            by = box(f"{name}Ring{k}Y{s}", (B, L, B), (s * (HW - B / 2), 0, zc), SEC, bevel=0.008)
            for t in (-1, 1):
                box_weld(f"{name}RingWeld{k}X{s}{t}_", bx, bpy.data.objects[f"{name}Post_{t}_{s}"])
                box_weld(f"{name}RingWeld{k}Y{s}{t}_", by, bpy.data.objects[f"{name}Post_{s}_{t}"])
    part(name + "Ring", "ring beam: ties the posts together, carries the deck and the cladding", name + "Post", "welded")
    ph = h - 2 * B
    for s in (-1, 1):                                      # cladding set into each side, 2 cm back from the face
        box(f"{name}CladX{s}", (L, 0.03, ph), (0, s * (HW - 0.02 - 0.015), 0), PRI, bevel=0.004)
        box(f"{name}CladY{s}", (0.03, L, ph), (s * (HW - 0.02 - 0.015), 0, 0), PRI, bevel=0.004)
        n_rib = max(2, int(L / 0.42))
        for i in range(n_rib):                             # stiffening ribs pressed into the cladding's face
            t = -L / 2 + L * (i + 0.5) / n_rib
            box(f"{name}CladRibX{s}{i}", (0.05, 0.012, ph - 0.06), (t, s * (HW - 0.013), 0), PRI, bevel=0.0)
            box(f"{name}CladRibY{s}{i}", (0.012, 0.05, ph - 0.06), (s * (HW - 0.013), t, 0), PRI, bevel=0.0)
    part(name + "Clad", "cladding panel: closes the side", name + "Ring", "inset", joins=(name + "Post",))
    part(name + "CladRib", "stiffening rib pressed into the cladding", name + "Clad", "inset")
    deck_plate(name + "Deck", L, L, z1)
    part(name + "Deck", "deck plate: what you walk and build on", name + "Ring1", "inset", joins=(name + "Post",))


def weld_loop(name, pts, r=WELD_R, mat=None):
    """Closed fillet weld round any outline (a lofted body welded onto a plate): one closed tube, no open seam."""
    if BLOCKOUT:
        return None
    P = [Vector(p) for p in pts]
    n = len(P)
    c = sum(P, Vector()) / n
    pn = Vector()
    for i in range(n):
        pn += (P[i] - c).cross(P[(i + 1) % n] - c)
    pn.normalize()
    m = 8
    bm = bmesh.new()
    rings = []
    for i in range(n):
        tng = (P[(i + 1) % n] - P[i - 1]).normalized()
        side = tng.cross(pn).normalized()
        rings.append([bm.verts.new(P[i] + (side * math.cos(2 * math.pi * k / m) + pn * math.sin(2 * math.pi * k / m)) * r)
                      for k in range(m)])
    for i in range(n):
        A, B = rings[i], rings[(i + 1) % n]
        for k in range(m):
            bm.faces.new((A[k], A[(k + 1) % m], B[(k + 1) % m], B[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    set_mat(bm, WELD if mat is None else mat)
    ob = make_obj(name, bm, 0.0)
    ob["kind"] = "weld"
    return ob


def bolt_ring(prefix, center, normal, radius, count, r=0.011, h=0.013, start=0.0, up=(0, 0, 1)):
    """Bolt circle on a face with any normal (bolts() only does axis-aligned faces)."""
    n = Vector(normal).normalized()
    M = basis(n, up if abs(Vector(up).normalized().dot(n)) < 0.99 else (1, 0, 0))
    for i in range(count):
        a = start + 2 * math.pi * i / count
        p = Vector(center) + (M @ Vector((math.cos(a) * radius, math.sin(a) * radius, 0, 0))).xyz + n * (h / 2)
        cyl(f"{prefix}{i}", r, h, (0, 0, 0), BARE, seg=6, bevel=0.0, rot=Matrix.Translation(p) @ M)


def wall_bracket(name, wall_p, wall_n, reach, r=0.02, foot=0.14, up=(0, 0, 1)):
    """Stand-off bracket: a foot plate bolted to a wall (at wall_p, normal wall_n) and a round arm welded to it,
    reaching `reach` out from the wall surface to carry something. Returns the arm's outer end point."""
    n = Vector(wall_n).normalized()
    p = Vector(wall_p)
    plate(name + "Foot", tuple(p), tuple(n), foot, foot, t=0.012, clip=0.015, mat=SEC, up=up, bolt_inset=0.016)
    L = reach - 0.012
    cyl(name + "Arm", r, L, (0, 0, 0), SEC, seg=16, bevel=0.003, rot=Matrix.Translation(p + n * (0.012 + L / 2)) @ basis(n, up))
    w = weld_ring(name + "Weld", (0, 0, 0), r + WELD_R * 0.4)
    if w is not None:
        w.data.transform(Matrix.Translation(p + n * (0.012 + WELD_R * 0.5)) @ basis(n, up))
    w2 = weld_ring(name + "WeldEnd", (0, 0, 0), r + WELD_R * 0.4)  # and welded to what it carries
    if w2 is not None:
        w2.data.transform(Matrix.Translation(p + n * (reach - WELD_R * 0.5)) @ basis(n, up))
    part(name + "Foot", "bracket foot: bolted to the wall", None, "bolted")
    part(name + "Arm", "bracket arm: holds the part off the wall", name + "Foot", "welded")
    return p + n * reach


def bolt_line(prefix, p0, p1, n, normal, r=0.012, h=0.014, inset=0.0):
    """n bolts evenly along p0->p1 (inset from the ends), heads facing `normal`."""
    a, b = Vector(p0), Vector(p1)
    for i in range(n):
        t = (i + 0.5) / n if inset == 0.0 else inset + (1 - 2 * inset) * i / max(1, n - 1)
        p = a.lerp(b, t) + Vector(normal).normalized() * (h / 2)
        cyl(f"{prefix}{i}", r, h, (0, 0, 0), BARE, seg=6, bevel=0.0, rot=Matrix.Translation(p) @ basis(normal))


def fitting(name, pos, direction, r_pipe):
    """Hex union nut where a pipe or hose meets a part (the pipe runs through it, it sits on the part)."""
    ob = cyl(name + "Nut", r_pipe * 1.7, r_pipe * 1.8, (0, 0, 0), BARE, seg=6, bevel=0.003,
             rot=Matrix.Translation(pos) @ basis(direction))
    if ob is not None:
        ob["kind"] = "fitting"
    return ob


def clamp(name, pos, direction, r_pipe, foot_dir, foot_len=0.05):
    """Pipe clamp: band around the pipe plus a tab running to the surface it is bolted to."""
    d = Vector(direction).normalized()
    f = Vector(foot_dir).normalized()
    M = Matrix.Translation(pos) @ basis(d)
    tube(name + "Band", r_pipe + 0.012, r_pipe + 0.002, 0.03, (0, 0, 0), SEC, seg=16, bevel=0.002)
    parts[-1].matrix_world = M
    tab_c = Vector(pos) + f * (r_pipe + (foot_len - 0.01) / 2)
    box(name + "Tab", (0.03, 0.03, foot_len - 0.01), (0, 0, 0), SEC, bevel=0.003, rot=Matrix.Translation(tab_c) @ basis(f, d))
    fb = Vector(pos) + f * (r_pipe + foot_len - 0.005)          # the foot sits on the surface, not in it
    box(name + "Foot", (0.08, 0.04, 0.01), (0, 0, 0), SEC, bevel=0.002, rot=Matrix.Translation(fb) @ basis(-f, d))
    side = d.cross(f).normalized()
    for s in (-1, 1):
        p = fb + side * (0.028 * s) - f * 0.0105
        cyl(f"{name}Bolt{s}", 0.008, 0.008, (0, 0, 0), BARE, seg=6, bevel=0.0, rot=Matrix.Translation(p) @ basis(-f))
    # declare part(name, job, on=<surface>, joint='bolted') in the generator: that is the foot
    part(name + "Band", "band that grips the pipe", name + "Tab", "inset")
    part(name + "Tab", "arm from the band to the foot (one pressed piece)", name + "Foot", "inset")


def pipe_support(name, pos, r_in, ground_z, axis='Y', width=0.08):
    """Pipe stand: a cradle shaped to the pipe (the pipe rests in it), a strap over the top bolted to the cradle
    ears, a round post welded under the cradle and onto a bolted base plate. pos = pipe centre; axis = pipe direction."""
    n = (0, 1, 0) if axis[-1] == 'Y' else (1, 0, 0)
    ear = r_in + 0.065
    zb = -(r_in + 0.06)
    lower = [(math.cos(t) * r_in, math.sin(t) * r_in) for t in [math.pi + math.pi * k / 20 for k in range(21)]]
    cradle = [(-ear, 0.0)] + lower + [(ear, 0.0), (ear, -0.025), (r_in * 0.6, zb), (-r_in * 0.6, zb), (-ear, -0.025)]
    profile(name + "Cradle", cradle, pos, n, width, SEC, up=(0, 0, 1), bevel=0.004)
    ro = r_in + 0.012
    strap = [(math.cos(t) * ro, math.sin(t) * ro) for t in [math.pi * k / 20 for k in range(21)]] + \
            [(math.cos(t) * r_in, math.sin(t) * r_in) for t in [math.pi * (20 - k) / 20 for k in range(21)]]
    profile(name + "Strap", strap, pos, n, width * 0.6, BARE, up=(0, 0, 1), bevel=0.0)
    lat = Vector((1, 0, 0)) if axis[-1] == 'Y' else Vector((0, 1, 0))
    along = Vector(n)
    for s in (-1, 1):                                     # strap feet bolted down onto the cradle ears
        c = Vector(pos) + lat * (s * (r_in + 0.03)) + Vector((0, 0, 0.006))
        sz = (0.05, width * 0.6, 0.012) if axis[-1] == 'Y' else (width * 0.6, 0.05, 0.012)
        box(f"{name}StrapFoot{s}", sz, tuple(c), BARE, bevel=0.0)
        cyl(f"{name}StrapBolt{s}", 0.009, 0.012, tuple(c + Vector((0, 0, 0.012))), BARE, seg=6, bevel=0.0)
    post_top = pos[2] + zb
    post_len = post_top - (ground_z + 0.018)
    cyl(name + "Post", 0.035, post_len, (pos[0], pos[1], ground_z + 0.018 + post_len / 2), SEC, seg=16, bevel=0.004)
    weld_ring(name + "PostWeldTop", (pos[0], pos[1], post_top - WELD_R * 0.5), 0.035 + WELD_R * 0.4)
    weld_ring(name + "PostWeldBase", (pos[0], pos[1], ground_z + 0.018 + WELD_R * 0.5), 0.035 + WELD_R * 0.4)
    base_plate(name + "Base", (pos[0], pos[1], ground_z), 0.2, 0.14, t=0.018, bolt_inset=0.025)
    # declare part(name, job, on=<what it stands on>, joint='bolted') in the generator: that is the base plate
    part(name + "Cradle", "cradle the pipe rests in", name + "Post", "welded")
    part(name + "StrapFoot", "strap ends, bolted down onto the cradle ears", name + "Cradle", "bolted")
    part(name + "Strap", "strap over the pipe: holds it in the cradle", name + "StrapFoot", "inset")
    part(name + "Post", "post carrying the cradle", name + "Base", "welded")


def base_plate(name, center, w, d, t=0.02, mat=None, bolt_inset=0.03):
    """Bolted foot plate on the surface below (columns, posts, pylons stand on these)."""
    plate(name, center, (0, 0, 1), w, d, t=t, clip=min(w, d) * 0.18, mat=SEC if mat is None else mat,
          up=(0, 1, 0), bolt_inset=bolt_inset)


def gusset(name, foot, out_dir, length, height, t=0.035, mat=None, notch=0.25, hanging=False):
    """Triangular brace: stands at `foot` against a wall, reaches `length` outward along out_dir (x, y) and `height`
    up the wall. Clipped tip, so it reads as a machined part, not a wedge."""
    d = Vector((out_dir[0], out_dir[1], 0)).normalized()
    up = Vector((0, 0, -1 if hanging else 1))           # hanging: a bracket under a load, flat edge on top
    side = Vector((-d.y, d.x, 0))
    f = Vector(foot)
    c = notch
    pts = [(0, 0), (length, 0), (length, height * c * 0.35), (length * c, height), (0, height)]
    bm = bmesh.new()
    rings = []
    for sgn in (-1, 1):
        rings.append([bm.verts.new(f + d * u + up * v + side * (sgn * t / 2)) for u, v in pts])
    bm.faces.new(rings[0]); bm.faces.new(list(reversed(rings[1])))
    for i in range(len(pts)):
        k = (i + 1) % len(pts)
        bm.faces.new((rings[0][i], rings[1][i], rings[1][k], rings[0][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    set_mat(bm, SEC if mat is None else mat)
    ob = make_obj(name, bm, 0.006)
    # fillet welds on both sides: along the floor and up the wall
    for sgn in (-1, 1):
        o = side * (sgn * (t / 2 + WELD_R * 0.6))
        weld(f"{name}WeldFloor{sgn}", [f + o + up * WELD_R, f + d * length + o + up * WELD_R])
        weld(f"{name}WeldWall{sgn}", [f + o + d * WELD_R, f + up * height + o + d * WELD_R])
    return ob


class HousingShape:
    """The housing's outer surface, so parts can sit exactly on it (panels follow the curve, ports know the wall)."""
    def __init__(self, w, z0, z1, n, bulge, taper):
        self.h, self.z0, self.z1, self.n = w / 2, z0, z1, n
        H0 = z1 - z0
        self.keys = [(z0, 1.0), (z0 + H0 * 0.18, bulge), (z0 + H0 * 0.7, (1 + bulge) / 2), (z1, taper)]

    def hw(self, z):
        """half width of the surface at height z"""
        for (za, sa), (zb, sb) in zip(self.keys, self.keys[1:]):
            if za <= z <= zb:
                return self.h * (sa + (sb - sa) * (z - za) / (zb - za))
        return self.h * (self.keys[0][1] if z < self.z0 else self.keys[-1][1])

    def point(self, face, u, z):
        a, n = self.hw(z), self.n
        s = max(-0.999, min(0.999, u / a))
        d = a * (1 - abs(s) ** n) ** (1 / n)                       # depth of the squircle at that lateral offset
        return rotz({'-Y': 0, '+X': 90, '+Y': 180, '-X': 270}[face]) @ Vector((u, -d, z))

    def at(self, face, u, z):
        """(point, outward normal) on `face` ('-Y','+X','+Y','-X') at lateral offset u and height z. The normal
        includes the wall's slope (the housing swells and tapers), so flat parts sit on it without sinking in."""
        e = 1e-4
        p = self.point(face, u, z)
        du = self.point(face, u + e, z) - self.point(face, u - e, z)
        dz = self.point(face, u, z + e) - self.point(face, u, z - e)
        nrm = du.cross(dz).normalized()
        if nrm.dot(Vector((p.x, p.y, 0))) < 0:
            nrm = -nrm
        return p, nrm

    def wall(self, face, z=None):
        """distance from the centre to the wall at the middle of a face (where a port goes through)"""
        return self.hw(0.45 if z is None else z)


def housing_panel(name, shape, face, z_lo, z_hi, w, kind, job, t=0.022, clip=0.06, on="Housing"):
    """A panel that follows the curved housing wall exactly (no gap behind it, nothing sunk in), with a job.
    kind 'cover': removable cover, corner bolts.  'vent': cover with louvre slots over something that needs air.
    'door': hinged service door, two hinges on the left edge, a latch handle on the right, no bolts."""
    hw_, hh = w / 2, (z_hi - z_lo) / 2
    zc = (z_lo + z_hi) / 2
    c = min(clip, w / 3, hh / 1.5)
    outline = [(-hw_ + c, -hh), (hw_ - c, -hh), (hw_, -hh + c), (hw_, hh - c), (hw_ - c, hh), (-hw_ + c, hh), (-hw_, hh - c), (-hw_, -hh + c)]
    # built flat in (u, v, offset) space, cut into a 4 cm grid, then every vertex is mapped onto the wall: the whole
    # panel bends with the housing (no gap behind it, nothing sunk in)
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((u, v, 0.0)) for u, v in outline])
    step = 0.04
    for axis_v, lo, hi in ((Vector((1, 0, 0)), -hw_, hw_), (Vector((0, 1, 0)), -hh, hh)):
        k = 1
        while lo + k * step < hi - 0.005:
            co = axis_v * (lo + k * step)
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=co, plane_no=axis_v)
            k += 1
    for kz, _ in shape.keys:                 # cut exactly on the wall's creases too, so the panel bends where it does
        if z_lo + 0.005 < kz < z_hi - 0.005:
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                                   plane_co=(0, kz - zc, 0), plane_no=(0, 1, 0))
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for v in [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]:
        v.co.z = t
    for v in bm.verts:
        p, nrm = shape.at(face, v.co.x, zc + v.co.y)
        v.co = p + nrm * v.co.z
    set_mat(bm, PRI)
    make_obj(name, bm, 0.004)
    part(name, job, on, {"door": "hinged"}.get(kind, "bolted"))

    def frame(u, v, off):
        p, nrm = shape.at(face, u, zc + v)
        return p + nrm * off, nrm
    up = Vector((0, 0, 1))
    if kind in ("cover", "vent"):
        bi = max(c * 0.5 + 0.026, 0.035)
        for sx in (-1, 1):
            for sy in (-1, 1):
                p, nrm = frame(sx * (hw_ - bi), sy * (hh - bi), t + 0.007)
                cyl(f"{name}Bolt{sx}{sy}", 0.011, 0.014, (0, 0, 0), BARE, seg=6, bevel=0.0, rot=Matrix.Translation(p) @ basis(nrm, up))
    if kind == "vent":
        k_n = max(2, int((2 * hh - 0.1) / 0.05))
        for k in range(k_n):                                         # louvres: two columns of slots in the face
            v = -hh + 0.06 + (2 * hh - 0.12) * (k + 0.5) / k_n
            for j, uu in enumerate((-w * 0.14, w * 0.14)):
                p, nrm = frame(uu, v, t - 0.002)
                box(f"{name}Slot{k}_{j}", (w * 0.22, 0.016, 0.006), (0, 0, 0), RUB, bevel=0.0,
                    rot=Matrix.Translation(p) @ basis(nrm, up))
        part(name + "Slot", "louvre slot: lets air through to what the vent cools", name, "inset")
    if kind == "door":
        for sy in (-1, 1):                                           # hinge: leaf screwed to the wall, knuckle, pin
            v = sy * (hh - 0.07)
            pl, nl = frame(-hw_ - 0.022, v, 0.004)
            box(f"{name}HingeLeaf{sy}", (0.03, 0.06, 0.008), (0, 0, 0), SEC, bevel=0.0, rot=Matrix.Translation(pl) @ basis(nl, up))
            cyl(f"{name}HingeScrew{sy}", 0.006, 0.006, (0, 0, 0), BARE, seg=6, bevel=0.0,
                rot=Matrix.Translation(pl + nl * 0.007) @ basis(nl, up))
            pk, nk = frame(-hw_ - 0.004, v, t * 0.5 + 0.004)
            tz = (frame(-hw_ - 0.004, v + 0.01, 0)[0] - frame(-hw_ - 0.004, v - 0.01, 0)[0]).normalized()
            cyl(f"{name}Knuckle{sy}", 0.012, 0.05, (0, 0, 0), BARE, seg=12, bevel=0.0,
                rot=Matrix.Translation(pk) @ basis(tz, nk))          # the pin runs up the (sloping) wall
        part(name + "HingeLeaf", "hinge leaf: carries the door on the wall", on, "bolted")
        part(name + "Knuckle", "hinge knuckle: the door turns on its pin", name + "HingeLeaf", "pivot", joins=(name,))
        ph, nh = frame(hw_ - 0.05, 0.0, t)                           # latch: handle on a base, keeper on the wall
        box(f"{name}Latch", (0.03, 0.09, 0.012), (0, 0, 0), SEC, bevel=0.002, rot=Matrix.Translation(ph + nh * 0.006) @ basis(nh, up))
        box(f"{name}LatchGrip", (0.022, 0.07, 0.018), (0, 0, 0), BARE, bevel=0.003, rot=Matrix.Translation(ph + nh * 0.021) @ basis(nh, up))
        part(name + "Latch", "latch base: turns to lock the door shut", name, "pivot")
        part(name + "LatchGrip", "latch handle: what you pull to open the door", name + "Latch", "inset")


def housing(w, z0, z1, chamfer=0.2, belt=None, posts=True, name="Housing", taper=0.97, panels=None,
            n=4.2, bulge=1.025, on="Skid"):
    """Lofted rounded-square housing (it swells slightly above the base and tapers to the top), lofted trims,
    optional belt, base flange bolted to the skid. Returns the HousingShape (for ports and other parts on the wall).
    panels: {'-Y0': ('cover'|'vent'|'door', 'job'), ...} - face + band (0 = lower, 1 = above the belt). Only panels
    with a job: no armour for the sake of armour."""
    h = w / 2
    sec = squircle(h, h, n, seg=96)
    H0 = z1 - z0
    shape = HousingShape(w, z0, z1, n, bulge, taper)
    loft(name, [zring(sec, z0), zring(sec, z0 + H0 * 0.18, bulge, bulge), zring(sec, z0 + H0 * 0.7, (1 + bulge) / 2, (1 + bulge) / 2),
                zring(sec, z1, taper, taper)], SEC, bevel=0.012)
    part(name, "machine housing: encloses the drive and the process", on, "bolted")
    bands = [(z0 + 0.12, belt - 0.03), (belt + 0.08, z1 - 0.08)] if belt else [(z0 + 0.12, z1 - 0.08)]
    for key, (kind, job) in (panels or {}).items():
        face, k = key[:2], int(key[2:])
        a, b = bands[k]
        housing_panel(f"{name}Panel{key}", shape, face, a, b, w * 0.6, kind, job, on=name)
    loft(name + "TrimLow", [zring(sec, z0, 1.075, 1.075), zring(sec, z0 + 0.035, 1.075, 1.075), zring(sec, z0 + 0.035, 1.0, 1.0)], SEC, bevel=0.004)
    part(name + "TrimLow", "base flange: what the hold-down bolts clamp to the skid", name, "inset")
    loft(name + "TrimHigh", [zring(sec, z1 - 0.05, taper + 0.02, taper + 0.02), zring(sec, z1 + 0.02, taper + 0.05, taper + 0.05),
                             zring(sec, z1 + 0.05, taper + 0.03, taper + 0.03)], SEC, bevel=0.006)
    part(name + "TrimHigh", "top rim: stiffens the shell where the top deck sits", name, "inset")
    if belt:
        s = 1.0 + (bulge - 1.0) * 0.9 + 0.02
        loft(name + "Belt", [zring(sec, belt, s, s), zring(sec, belt + 0.05, s, s)], SEC, bevel=0.005)
        part(name + "Belt", "stiffening band round the shell", name, "inset")
    if posts:
        # the base flange is what holds the housing down: bolts around it into the skid (no decorative wedges)
        for k, (x, y) in enumerate(squircle(h * 1.04, h * 1.04, n, seg=16)):
            cyl(f"{name}BaseBolt{k}", 0.013, 0.016, (x, y, z0 + 0.035 + 0.008), BARE, seg=6, bevel=0.0)
    return shape


PIPE_R_OUT, PIPE_R_IN, COLLAR_W = 0.3, 0.232, 0.07   # the one pipe-end profile every connector shares


def pipe_collar(name, axis, end, light=False, c=(0.0, 0.0, 0.0)):
    """Pipe-end collar whose mating face sits exactly at `end` along `axis` ('+Y','-X',...): the same part on pipes,
    mergers, splitters and machine ports, so two ends meet flush. Bolts sit on the back face, a thin steel seal on
    the mating face. c offsets the pipe centreline (machines: (0, 0, 0.45))."""
    a, sgn = axis[1], (1 if axis[0] == '+' else -1)
    inward = ('-' if sgn > 0 else '+') + a
    def at(off):
        p = list(c); p['XYZ'.index(a)] += sgn * off
        return tuple(p)
    tube(name + "Collar", PIPE_R_OUT, PIPE_R_IN, COLLAR_W, at(end - COLLAR_W / 2), SEC, seg=32, axis=a, bevel=0.006)
    tube(name + "Seal", PIPE_R_OUT - 0.012, PIPE_R_IN + 0.012, 0.006, at(end - 0.004), BARE, seg=32, axis=a, bevel=0.0)
    part(name + "Seal", "steel seal ring in the mating face", name + "Collar", "inset")
    bolts(name + "Bolt", at(end - COLLAR_W), inward, 0.268, 8, r=0.012, h=0.014, start=math.pi / 8)
    if light:
        # lit band set into the collar's rim (not a ring stuck behind it): marks an output
        tube(name + "Light", PIPE_R_OUT + 0.002, PIPE_R_OUT - 0.006, 0.016, at(end - COLLAR_W * 0.55), STAT, seg=32, axis=a, bevel=0.0)
        part(name + "Light", "lit band in the collar rim: marks this end as an output", name + "Collar", "inset")


PORT_FLANGE_R = 0.33


def pipe_port(name, axis, face, end=0.45, flange=True, light=False, neck_from=None, drum_r=None, c=(0.0, 0.0, 0.0),
              wall=False):
    """Connector from a body to where the pipe starts: round bolted flange on the body face (flat bodies), hollow
    neck, the shared pipe collar ending at `end`, and a dark throat so the opening reads as a tunnel. Every pipe
    connection in the game (junctions, machine inputs and outputs) is this one round part.
    neck_from: start the neck inside the body (round bodies) instead of using a flange. c: pipe centreline offset.
    wall: the neck goes through a flat housing wall at `face` and is welded all round there (machine ports)."""
    a, sgn = axis[1], (1 if axis[0] == '+' else -1)
    def at(off):
        p = list(c); p['XYZ'.index(a)] += sgn * off
        return tuple(p)
    start = face
    if flange:
        cyl(name + "Flange", PORT_FLANGE_R, 0.024, at(face + 0.012), SEC, seg=40, axis=a, bevel=0.005)
        # flange bolts sit between the collar bolts (start 0 vs pi/8), so short necks never stack two bolts
        bolts(name + "FlangeBolt", at(face + 0.024), axis, 0.3, 8, start=0.0)
        start = face + 0.024
    if neck_from is not None:
        start = neck_from
    neck_len = (end - COLLAR_W) - start
    tube(name + "Neck", PIPE_R_IN + 0.02, PIPE_R_IN, neck_len, at(start + neck_len / 2), BARE, seg=32, axis=a, bevel=0.004)
    cyl(name + "Throat", PIPE_R_IN - 0.0003, 0.012, at(max(start, face) + 0.004), RUB, seg=32, axis=a, bevel=0.0)
    if name + "Throat" not in SPEC:
        part(name + "Throat", "dark bore: the opening reads as a tunnel into the body", name + "Neck", "inset")
    part(name + "Collar", "pipe-end collar: the next pipe's collar bolts to it", name + "Neck", "welded")
    if flange:
        part(name + "Flange", "port flange: bolts the port to the body", name + "Neck", "welded")
    pipe_collar(name, axis, end, light=light, c=c)
    # neck welded to the collar, and to the flange (flat hub) or into the drum wall (round hub)
    weld_ring(name + "WeldCollar", at(end - COLLAR_W - WELD_R * 0.5), PIPE_R_IN + 0.02 + WELD_R * 0.4, a)
    if flange:
        weld_ring(name + "WeldFlange", at(face + 0.024 + WELD_R * 0.5), PIPE_R_IN + 0.02 + WELD_R * 0.4, a)
    elif drum_r:
        saddle_weld(name + "WeldDrum", axis, PIPE_R_IN + 0.02 + WELD_R * 0.4, drum_r)
    elif wall:
        weld_ring(name + "WeldWall", at(face + WELD_R * 0.5), PIPE_R_IN + 0.02 + WELD_R * 0.4, a)


def machine_port(name, axis, face, end, light=False, job=None, body="Housing"):
    """A machine's item input or output: the round pipe port at pipe height (0.45 m), neck welded through the
    housing wall at `face`, collar mating face on the footprint edge `end`. Same profile as every pipe end."""
    pipe_port(name, axis, face, end=end, flange=False, neck_from=face - 0.04, light=light, c=(0.0, 0.0, 0.45), wall=True)
    part(name, job or ("item output" if light else "item input"), body, "through")
    part(name + "Throat", "dark bore: the opening reads as a tunnel into the body", name + "Neck", "inset", joins=(body,))


def lugs(half, z, name="Lug"):
    for sx in (-1, 1):
        for sy in (-1, 1):
            rot = rotz(45 * sx * sy) @ Matrix.Rotation(math.pi / 2, 4, 'X')
            box(f"{name}Base_{sx}_{sy}", (0.1, 0.1, 0.03), (sx * half, sy * half, z + 0.015), SEC, bevel=0.004)
            torus(f"{name}_{sx}_{sy}", 0.042, 0.012, (sx * half, sy * half, z + 0.07), BARE, rot)


def dock(name, pos, axis, r=0.2, stub=0.12):
    """Pipe dock: bolted flange, steel stub, dark mouth. axis is the outward direction: '+Y','-Y','+X','-X'."""
    sgn = 1 if axis[0] == '+' else -1
    ax = axis[1]
    def at(off):
        p = list(pos)
        p['XYZ'.index(ax)] += sgn * off
        return tuple(p)
    cyl(name + "Flange", r + 0.05, 0.05, at(0.025), SEC, seg=24, axis=ax)
    cyl(name + "Stub", r - 0.03, stub, at(0.05 + stub / 2), BARE, seg=24, axis=ax)
    cyl(name + "Mouth", r, 0.03, at(0.05 + stub - 0.015), SEC, seg=24, axis=ax)
    cyl(name + "Hole", r - 0.07, 0.01, at(0.05 + stub - 0.002), RUB, seg=24, axis=ax, bevel=0.0)
    bolts(name + "Bolt", at(0.05), axis, r + 0.015, 8, start=math.pi / 8)
    weld_ring(name + "WeldStub", at(0.05 + WELD_R * 0.5), r - 0.03 + WELD_R * 0.4, ax)
    weld_ring(name + "WeldMouth", at(0.05 + stub - 0.03 - WELD_R * 0.5), r - 0.03 + WELD_R * 0.4, ax)


def radiator(name, x_side, y_half, z0, z1, fins=7, depth=0.15):
    """Fin bank on the +/-X side. x_side = signed x of the housing face."""
    sx = 1 if x_side > 0 else -1
    zc, h = (z0 + z1) / 2, z1 - z0
    for sy in (-1, 1):
        box(f"{name}Post_{sy}", (0.06, 0.05, h + 0.1), (x_side + sx * 0.03, sy * (y_half + 0.03), zc), SEC, bevel=0.005)
    for z in (z0 - 0.025, z1 + 0.025):
        box(f"{name}Rail_{z:.2f}", (0.06, 2 * y_half + 0.1, 0.045), (x_side + sx * 0.03, 0, z), SEC, bevel=0.005)
    box(f"{name}Back", (0.025, 2 * y_half, h), (x_side + sx * 0.012, 0, zc), RUB, bevel=0.0)
    for i in range(fins):
        y = -y_half + 2 * y_half * (i + 0.5) / fins
        box(f"{name}Fin{i}", (depth, 0.02, h - 0.02), (x_side + sx * depth / 2, y, zc), BARE, bevel=0.004)


def status_strip(name, y_face, z, w=0.36, facing='-Y', on="Housing"):
    """The one status light every building gets: a thin strip in a bezel screwed to the front, centred.
    y_face: where the front surface is (the bezel's back sits exactly on it)."""
    sgn = -1 if facing[0] == '-' else 1
    box(name + "Bezel", (w + 0.04, 0.02, 0.05), (0, y_face + sgn * 0.01, z), SEC, bevel=0.004)
    box(name, (w, 0.012, 0.022), (0, y_face + sgn * 0.02, z), STAT, bevel=0.0)
    for s in (-1, 1):
        cyl(f"{name}Screw{s}", 0.008, 0.008, (s * (w / 2 + 0.012), y_face + sgn * 0.024, z), BARE, seg=6, axis=facing, bevel=0.0)
    part(name, "status light: green = running, red = fault", name + "Bezel", "inset")
    part(name + "Bezel", "frame of the status light, screwed to the front", on, "bolted")


def beacon(name, pos):
    x, y, z = pos
    cyl(name + "Base", 0.05, 0.04, (x, y, z + 0.02), SEC, seg=12)
    cyl(name + "Lamp", 0.032, 0.065, (x, y, z + 0.072), STAT, seg=12, bevel=0.0)
    cyl(name + "Cap", 0.04, 0.015, (x, y, z + 0.112), SEC, seg=12, bevel=0.0)


def console(name, pos, yaw_deg, w=0.3, h=0.26):
    rot = rotz(yaw_deg)
    n = rot @ Vector((0, -1, 0))
    p = Vector(pos)
    box(name, (w, 0.09, h), tuple(p), SEC, bevel=0.007, rot=rot)
    box(name + "Screen", (w * 0.76, 0.012, h * 0.55), tuple(p + n * 0.047 + Vector((0, 0, h * 0.12))), STAT, bevel=0.0, rot=rot)
    side = rot @ Vector((1, 0, 0))
    for i, m in enumerate((RUB, HAZ, BARE)):
        c = p + n * 0.05 + side * (-0.07 + 0.07 * i) + Vector((0, 0, -h * 0.3))
        cyl(f"{name}Btn{i}", 0.016, 0.02, tuple(c), m, seg=8, axis='Y', bevel=0.0, rot=rot)


def chevron(name, center, direction='+Y', size=0.16, mat=None, h=0.012):
    """Flat arrow plate pointing along `direction` (flow marker), lying on the XY plane."""
    yaw = {'+Y': 0, '-Y': 180, '+X': -90, '-X': 90}[direction]
    rot = rotz(yaw)
    for s in (-1, 1):
        box(f"{name}_{s}", (size * 0.22, size * 0.62, h), (0, 0, 0), mat if mat is not None else HAZ,
            bevel=0.0, rot=rot @ rotz(s * 40) @ Matrix.Translation((0, -size * 0.18, 0)))
        parts[-1].location = Vector(center) + (rot @ Vector((s * size * 0.2, 0, 0)))


# ------------------------------------------------------------------ surface bake: AO + worn edges + grime
BEVEL_SCALE = 2.0          # chamfers are twice the value given per part: soft, readable edges, not 1 cm slivers
PAINT_PREFIX = "M_Paint_"
NO_BAKE = ("M_Emissive", "M_Glass")


def _cycles_setup():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 64
    sc.cycles.device = 'CPU'
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if any(d.type == kind for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = True
                    sc.cycles.device = 'GPU'
                    break
            except TypeError:
                pass
    except Exception:
        pass


PAINTED_LIGHT = False             # was True for the per-vertex PS2 look; off since per-pixel lighting (2026-11-08): real light + painted light = double lighting, dark undersides
DUST_AMT = 1.0                    # ship parts set this lower: they fly, they don't sit in regolith
WEAR_SCALE = 1.0                  # size of wear features (edge bevel, cavity reach, dust height, noise): 1 = building
                                  # scale. Hand tools are ~10x smaller: at 1.0 every face of a 4 cm tool counted as a
                                  # worn edge and its dark paint baked out light grey (2026-11-08). Tools use ~0.12.
BARE_COL = (0.58, 0.58, 0.6)      # steel under the paint
DUST_COL = (0.33, 0.29, 0.24)
RUST_COL = (0.22, 0.09, 0.035)


def bake_detail(objs, base_name, res=2048):
    """Substance-style wear baked into two textures on a fresh, non-overlapping UV0:
      T_<name>_D  : final albedo (default grey paint) with paint chipped to bare steel on worn edges,
                    grime and AO in cavities, dust low on the body, rust spots in sheltered areas.
      T_<name>_RM : R = paint mask (1 = intact paint), G = roughness, B = metallic (glTF metallicRoughness layout;
                    glTF ignores R, so the paint shader can read it).
    Paint tool in Godot: albedo = D * mix(1, paint_colour / default_grey, RM.r). Emissive and glass are not baked."""
    sc = bpy.context.scene
    _cycles_setup()
    box_uv_name = objs[0].data.uv_layers[0].name if objs[0].data.uv_layers else "UVMap"
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
        uv = o.data.uv_layers.new(name="UVBake")
        o.data.uv_layers.active = uv
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003, area_weight=0.0, scale_to_bounds=False)
    try:
        bpy.ops.uv.pack_islands(margin=0.003, rotate=True)
    except Exception:
        pass
    bpy.ops.object.mode_set(mode='OBJECT')

    d_img = bpy.data.images.new(f"T_{base_name}_D", res, res, alpha=False)
    rm_img = bpy.data.images.new(f"T_{base_name}_RM", res, res, alpha=False, is_data=True)
    rm_img.colorspace_settings.name = 'Non-Color'

    mats = {m for o in objs for m in o.data.materials if m}
    info, outs = {}, {}
    base_z = min((o.matrix_world @ Vector(c)).z for o in objs for c in o.bound_box)
    for m in mats:
        nt = m.node_tree
        b = nt.nodes["Principled BSDF"]
        link = b.inputs["Base Color"].links
        info[m.name] = dict(col=tuple(b.inputs["Base Color"].default_value)[:3], src=link[0].from_node if link else None,
                            rough=b.inputs["Roughness"].default_value, metal=b.inputs["Metallic"].default_value)
        tgt = nt.nodes.new("ShaderNodeTexImage"); tgt.name = "BAKE_TARGET"; tgt.image = d_img
        if m.name.startswith(NO_BAKE):
            nt.nodes.active = tgt
            continue
        N = nt.nodes.new
        L = nt.links.new

        def mnode(op, a=None, b_=None, clamp=False):
            n = N("ShaderNodeMath"); n.operation = op; n.use_clamp = clamp
            for k, v in enumerate((a, b_)):
                if v is None:
                    continue
                if isinstance(v, (int, float)):
                    n.inputs[k].default_value = v
                else:
                    L(v, n.inputs[k])
            return n.outputs[0]

        def mrange(v, f0, f1, t0, t1):
            n = N("ShaderNodeMapRange"); n.clamp = True
            n.inputs["From Min"].default_value = f0; n.inputs["From Max"].default_value = f1
            n.inputs["To Min"].default_value = t0; n.inputs["To Max"].default_value = t1
            L(v, n.inputs["Value"])
            return n.outputs["Result"]

        def mixc(fac, a, b_):
            n = N("ShaderNodeMix"); n.data_type = 'RGBA'
            for sock, v in (("A", a), ("B", b_)):
                if isinstance(v, tuple):
                    n.inputs[sock].default_value = (*v[:3], 1)
                else:
                    L(v, n.inputs[sock])
            if isinstance(fac, (int, float)):
                n.inputs["Factor"].default_value = fac
            else:
                L(fac, n.inputs["Factor"])
            return n.outputs["Result"]

        def noise(scale, detail, rough=0.55):
            n = N("ShaderNodeTexNoise")
            n.inputs["Scale"].default_value = scale / WEAR_SCALE; n.inputs["Detail"].default_value = detail
            n.inputs["Roughness"].default_value = rough
            L(tc.outputs["Object"], n.inputs["Vector"])
            return n.outputs["Fac"]

        tc = N("ShaderNodeTexCoord")
        geo = N("ShaderNodeNewGeometry")
        ao = N("ShaderNodeAmbientOcclusion"); ao.samples = 24; ao.inputs["Distance"].default_value = 0.18 * WEAR_SCALE
        cav = mrange(ao.outputs["AO"], 0.2, 1.0, 0.0, 1.0)               # 0 deep in gaps, 1 open
        bev = N("ShaderNodeBevel"); bev.samples = 12; bev.inputs["Radius"].default_value = 0.06 * WEAR_SCALE
        dot = N("ShaderNodeVectorMath"); dot.operation = 'DOT_PRODUCT'
        L(bev.outputs["Normal"], dot.inputs[0]); L(geo.outputs["True Normal"], dot.inputs[1])
        edge = mrange(dot.outputs["Value"], 0.5, 0.995, 1.0, 0.0)         # 1 on convex edges
        n1, n2 = noise(12.0, 8.0, 0.72), noise(3.0, 6.0)
        chip_raw = mnode('ADD', mnode('MULTIPLY', edge, 1.15), mnode('MULTIPLY', mnode('SUBTRACT', n1, 0.5), 1.4))
        chip_raw = mnode('ADD', chip_raw, mnode('MULTIPLY', mnode('SUBTRACT', n2, 0.5), 0.6))
        chip = mrange(chip_raw, 0.42, 0.5, 0.0, 1.0)
        spots = mrange(noise(48.0, 4.0, 0.6), 0.7, 0.74, 0.0, 0.9)          # small chips on flat panels
        chip = mnode('MAXIMUM', chip, mnode('MULTIPLY', spots, mrange(noise(4.0, 3.0), 0.5, 0.65, 0.0, 1.0)))
        sep = N("ShaderNodeSeparateXYZ"); L(geo.outputs["Position"], sep.inputs[0])     # world height
        low = mrange(sep.outputs["Z"], base_z, base_z + 0.45 * WEAR_SCALE, 1.0, 0.0)
        dust = mnode('MULTIPLY', low, mrange(n2, 0.35, 0.65, 0.35 * DUST_AMT, 0.8 * DUST_AMT), clamp=True)
        grime = mnode('ADD', mnode('MULTIPLY', mnode('SUBTRACT', 1.0, cav), 0.75),
                      mrange(noise(1.6, 10.0), 0.45, 0.75, 0.0, 0.3), clamp=True)
        rust = mrange(mnode('ADD', mnode('MULTIPLY', grime, 0.6), mnode('MULTIPLY', noise(9.0, 12.0), 0.8)), 0.78, 0.92, 0.0, 0.7)

        nm = m.name
        paint = nm.startswith(PAINT_PREFIX)
        rubber = "Rubber" in nm
        is_weld = nm.endswith("_Weld")
        if is_weld:
            chip = mnode('MULTIPLY', chip, 0.0)
        if rubber:
            dust = mnode('MULTIPLY', dust, 0.15)
        if info[nm]["src"] is not None:                                   # hazard decal: stripes via the box UV
            uvn = N("ShaderNodeUVMap"); uvn.uv_map = box_uv_name
            L(uvn.outputs["UV"], info[nm]["src"].inputs["Vector"])
            col = info[nm]["src"].outputs["Color"]
            paintlike = True
        else:
            col = info[nm]["col"]
            paintlike = paint
        if paintlike and not is_weld:
            col = mixc(mnode('MULTIPLY', edge, 0.3), col, (0.9, 0.9, 0.9))   # paint rubbed thin on edges
            col = mixc(chip, col, BARE_COL)
        elif not rubber:
            col = mixc(mnode('MULTIPLY', edge, 0.6), col, (0.85, 0.85, 0.88))
        else:
            col = mixc(mnode('MULTIPLY', edge, 0.15), col, (0.06, 0.06, 0.06))
        if not rubber:
            col = mixc(rust, col, RUST_COL)
        col = mixc(dust, col, DUST_COL)
        shade = N("ShaderNodeMix"); shade.data_type = 'RGBA'; shade.blend_type = 'MULTIPLY'
        L(mrange(grime, 0.0, 1.0, 0.0, 0.65), shade.inputs["Factor"]); L(col, shade.inputs["A"])
        shade.inputs["B"].default_value = (0.25, 0.23, 0.21, 1)
        albedo = shade.outputs["Result"]
        if PAINTED_LIGHT:
            # PS2 look: light painted into the texture - lit from above, shaded underneath, deeper in the gaps
            nz = N("ShaderNodeSeparateXYZ"); L(geo.outputs["True Normal"], nz.inputs[0])
            k = mnode('MULTIPLY', mnode('ADD', 0.8, mnode('MULTIPLY', nz.outputs["Z"], 0.28)), mrange(cav, 0.0, 1.0, 0.55, 1.0))
            comb = N("ShaderNodeCombineColor")
            for i in range(3):
                L(k, comb.inputs[i])
            lit = N("ShaderNodeMix"); lit.data_type = 'RGBA'; lit.blend_type = 'MULTIPLY'
            lit.inputs["Factor"].default_value = 1.0
            L(albedo, lit.inputs["A"]); L(comb.outputs[0], lit.inputs["B"])
            albedo = lit.outputs["Result"]

        r0, m0 = info[nm]["rough"], info[nm]["metal"]
        rough = mnode('ADD', r0, mnode('MULTIPLY', grime, 0.35))
        rough = mnode('ADD', rough, mnode('MULTIPLY', dust, 0.4))
        rough = mnode('ADD', rough, mnode('MULTIPLY', rust, 0.5), clamp=True)
        metal = mnode('MULTIPLY', m0, mnode('SUBTRACT', 1.0, mnode('ADD', dust, rust)), clamp=True)
        if paintlike:
            rough = mnode('ADD', mnode('MULTIPLY', rough, mnode('SUBTRACT', 1.0, chip)), mnode('MULTIPLY', chip, 0.3), clamp=True)
            metal = mnode('ADD', mnode('MULTIPLY', metal, mnode('SUBTRACT', 1.0, chip)), mnode('MULTIPLY', chip, 0.95), clamp=True)
        comb = N("ShaderNodeCombineColor")
        if paint:
            L(mnode('SUBTRACT', 1.0, mnode('ADD', chip, rust, clamp=True)), comb.inputs["Red"])
        else:
            comb.inputs["Red"].default_value = 0.0
        L(rough, comb.inputs["Green"]); L(metal, comb.inputs["Blue"])
        out = N("ShaderNodeOutputMaterial"); out.target = 'CYCLES'
        emit = N("ShaderNodeEmission")
        L(emit.outputs["Emission"], out.inputs["Surface"])
        out.is_active_output = True
        outs[nm] = (nt, emit, albedo, comb.outputs["Color"])
        for n in nt.nodes:
            n.select = False
        tgt.select = True
        nt.nodes.active = tgt

    def run(img, which):
        for nm, (nt, emit, albedo, rmc) in outs.items():
            for l in list(emit.inputs["Color"].links):
                nt.links.remove(l)
            nt.links.new(albedo if which == 0 else rmc, emit.inputs["Color"])
        for m in mats:
            m.node_tree.nodes["BAKE_TARGET"].image = img
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.bake(type='EMIT', margin=8, use_clear=True)
        img.filepath_raw = f"{OUT}/{img.name}.png"
        img.file_format = 'PNG'
        img.save()
        img.pack()
    run(d_img, 0)
    run(rm_img, 1)

    for m in mats:
        nt = m.node_tree
        if m.name.startswith(NO_BAKE):
            nt.nodes.remove(nt.nodes["BAKE_TARGET"])
            continue
        for n in list(nt.nodes):
            if not (n.type == 'BSDF_PRINCIPLED' or (n.type == 'OUTPUT_MATERIAL' and n.target != 'CYCLES')):
                nt.nodes.remove(n)
        for n in nt.nodes:
            if n.type == 'OUTPUT_MATERIAL':
                n.is_active_output = True
        b = nt.nodes["Principled BSDF"]
        for sock in ("Base Color", "Roughness", "Metallic"):
            for l in list(b.inputs[sock].links):
                nt.links.remove(l)
        t1 = nt.nodes.new("ShaderNodeTexImage"); t1.image = d_img
        nt.links.new(t1.outputs["Color"], b.inputs["Base Color"])
        t2 = nt.nodes.new("ShaderNodeTexImage"); t2.image = rm_img
        sp = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(t2.outputs["Color"], sp.inputs["Color"])
        nt.links.new(sp.outputs["Green"], b.inputs["Roughness"])
        nt.links.new(sp.outputs["Blue"], b.inputs["Metallic"])
        b.inputs["Base Color"].default_value = (1, 1, 1, 1)
        m["default_rgb"] = list(info[m.name]["col"])
    for o in objs:
        for uv in list(o.data.uv_layers):
            if uv.name != "UVBake":
                o.data.uv_layers.remove(uv)
    try:
        sc.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        pass
    print("REPORT baked", d_img.name, rm_img.name, res)


# ------------------------------------------------------------------ finish: bevel, UV, join per group, validate, export
FPS = 24


def assign(group, *prefixes):
    """Move already-built parts whose names start with any prefix into a moving group."""
    for ob in parts:
        if any(ob.name.startswith(p) for p in prefixes):
            ob["group"] = group


def spin(group, axis, seconds=4.0, turns=1.0, track="Working-loop"):
    """Continuous rotation about the group's pivot (local axis 0/1/2). Linear keys, loops seamlessly."""
    return dict(track=track, group=group, path="rotation_euler", axis=axis, interp='LINEAR', spin=True,
                keys=[(0.0, 0.0), (seconds, 2 * math.pi * turns)])


def swing(group, axis, keys, path="rotation_euler", track="Working-loop", interp='BEZIER'):
    """Keyframed offsets: keys = [(seconds, value), ...]; value is added to the rest pose (radians or metres)."""
    return dict(track=track, group=group, path=path, axis=axis, interp=interp, keys=keys)


def finish(base_name, pivots=None, extra_report="", bake_res=512, parents=None, anims=None):
    """Joins parts per group into `<base_name>_<group>` meshes ('main' -> base_name), validates and exports one GLB.
    pivots: {group: (x,y,z)} origin for moving parts (e.g. turret head). Rotation/scale are always applied.
    parents: {child_group: parent_group} so moving parts nest (barrel under head).
    anims: list from spin()/swing(); every track becomes one glTF animation (name ending -loop = loops in Godot)."""
    pivots = pivots or {}
    parents = parents or {}
    anims = anims or []
    if not _audit(base_name):
        return []
    for ob in parts:
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bm = bmesh.new(); bm.from_mesh(ob.data); box_uv(bm); bm.to_mesh(ob.data); bm.free()
        if ob["bevel"] <= 0:
            continue
        bv = ob.modifiers.new("Bevel", 'BEVEL')
        bv.limit_method = 'WEIGHT'
        bv.width = ob["bevel"] * BEVEL_SCALE
        bv.segments = 3
        bv.harden_normals = True
        bv.use_clamp_overlap = True
        bv.miter_outer = 'MITER_ARC'
        bpy.ops.object.modifier_apply(modifier="Bevel")

    groups = {}
    for ob in parts:
        groups.setdefault(ob["group"], []).append(ob)
    finals = []
    for g, obs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for ob in obs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        obj = bpy.context.active_object
        obj.name = obj.data.name = base_name if g == "main" else f"{base_name}_{g}"
        tri = obj.modifiers.new("NgonFix", 'TRIANGULATE')
        tri.min_vertices = 5
        tri.keep_custom_normals = True
        bpy.ops.object.modifier_apply(modifier="NgonFix")
        # unused slots stay; the glTF exporter only writes materials that faces use
        if g in pivots:
            bpy.context.scene.cursor.location = pivots[g]
            bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        finals.append(obj)

    for obj in finals:
        bm = bmesh.new(); bm.from_mesh(obj.data)
        ngons = sum(1 for f in bm.faces if len(f.verts) > 4)
        nme = sum(1 for e in bm.edges if not e.is_manifold)
        tris = sum(len(f.verts) - 2 for f in bm.faces)
        bm.free()
        bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        print("REPORT %-28s tris=%-6d ngons=%d nonmanifold=%d scale=%s rot=%s slots=%d" % (
            obj.name, tris, ngons, nme, tuple(round(s, 3) for s in obj.scale),
            tuple(round(r, 3) for r in obj.rotation_euler), len(obj.material_slots)))
        print("REPORT %-28s x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f] origin=%s" % (
            obj.name, min(v.x for v in bb), max(v.x for v in bb), min(v.y for v in bb), max(v.y for v in bb),
            min(v.z for v in bb), max(v.z for v in bb), tuple(round(c, 3) for c in obj.location)))
    if extra_report:
        print("REPORT", extra_report)

    if bake_res and not BLOCKOUT:                 # blockouts export flat materials, no bake
        bake_detail(finals, base_name, bake_res)

    by_group = {}
    for g, obs in groups.items():
        by_group[g] = bpy.data.objects[base_name if g == "main" else f"{base_name}_{g}"]
    for child, par in parents.items():
        c, p = by_group[child], by_group[par]
        mw = c.matrix_world.copy()
        c.parent = p
        c.matrix_world = mw
    # animations: one action per object per track, pushed into an NLA track of that name (exported merged by name)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start = 0
    # every spinner fills its whole track with whole turns, so mixed-speed parts loop together
    track_len = {}
    for a in anims:
        track_len[a["track"]] = max(track_len.get(a["track"], 0.0), max(t for t, _ in a["keys"]))
    for a in anims:
        if a.get("spin"):
            sec, ang = a["keys"][-1]
            L = track_len[a["track"]]
            n = max(1, round(L / sec))
            a["keys"] = [(0.0, 0.0), (L, ang * n)]
    tracks = {}
    for a in anims:
        tracks.setdefault((a["track"], a["group"]), []).append(a)
    for (track, g), lst in tracks.items():
        ob = by_group[g]
        ob.animation_data_create()
        act = bpy.data.actions.new(f"{track}_{ob.name}")
        ob.animation_data.action = act
        rest = {"rotation_euler": tuple(ob.rotation_euler), "location": tuple(ob.location)}
        end = 0
        for a in lst:
            bpy.context.preferences.edit.keyframe_new_interpolation_type = a["interp"]
            for t, v in a["keys"]:
                f = round(t * FPS)
                end = max(end, f)
                vec = list(rest[a["path"]])
                vec[a["axis"]] += v
                setattr(ob, a["path"], vec)
                ob.keyframe_insert(a["path"], index=a["axis"], frame=f)
            setattr(ob, a["path"], rest[a["path"]])
        nt = ob.animation_data.nla_tracks.new()
        nt.name = track
        nt.strips.new(track, 0, act)
        ob.animation_data.action = None
        print("REPORT anim", track, ob.name, "frames", end)
    bpy.ops.wm.save_as_mainfile(filepath=f"{OUT}/{base_name}.blend")
    bpy.ops.object.select_all(action='DESELECT')
    for obj in finals:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=f"{OUT}/{base_name}.glb", export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True,
                              export_animations=bool(anims), export_animation_mode='NLA_TRACKS',
                              export_force_sampling=True, export_frame_step=1)
    print("DONE", base_name)
    return finals


def _audit(base_name):
    """Run audit.py on the separate parts, write the part sheet (parts.md). Returns False when the build must stop:
    in blockout mode always (blockout renders instead of exporting), otherwise when the audit found errors
    (AUDIT=warn lets it through, for work in progress)."""
    import audit
    bpy.context.view_layer.update()          # parts placed through matrix_world (clamp bands) need this to read back
    errs, rows = audit.run(parts, SPEC, blockout=BLOCKOUT)
    with open(f"{OUT}/parts.md", "w", encoding="utf-8") as fh:
        fh.write(f"# {base_name}: parts\n\nGenerated by kit.finish from the kit.part() declarations. "
                 "Every part: what it does, what it is mounted on, how.\n\n")
        fh.write("| Part | Job | Mounted on | Joint | Objects |\n|---|---|---|---|---|\n")
        for pfx, job, on, joint, cnt in rows:
            fh.write(f"| {pfx} | {job} | {on} | {joint} | {cnt} |\n")
        fh.write(f"\n## Audit: {len(errs)} problem(s)\n\n" + "".join(f"- {e}\n" for e in errs))
    for e in errs:
        print("AUDIT", e)
    print(f"AUDIT {base_name}: {len(errs)} problem(s), {len(parts)} objects, {len(SPEC)} declared parts")
    if BLOCKOUT:
        _blockout_render(base_name)
        return not errs and os.environ.get("AUDIT_ONLY") != "1"   # a clean blockout exports (no bake) so it can be played
    if errs and os.environ.get("AUDIT") != "warn":
        bpy.ops.wm.save_as_mainfile(filepath=f"{OUT}/{base_name}_audit.blend")
        print("AUDIT FAIL: fix these before the model is exported (parts left in", f"{base_name}_audit.blend)")
        return False
    return os.environ.get("AUDIT_ONLY") != "1"


def _blockout_render(base_name):
    """Blockout stage: every declared part in its own flat colour, two Workbench views, next to the part sheet."""
    import random
    rnd = random.Random(7)
    cols = {}
    prefixes = sorted(SPEC, key=len, reverse=True)
    for ob in parts:
        pfx = next((p for p in prefixes if ob.name.startswith(p)), None)
        if pfx not in cols:
            cols[pfx] = (rnd.random() * 0.8 + 0.2, rnd.random() * 0.8 + 0.2, rnd.random() * 0.8 + 0.2, 1) if pfx else (1, 0, 1, 1)
        ob.color = cols[pfx]
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.color_type = 'OBJECT'
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 1100, 900
    lo = Vector((min(min((o.matrix_world @ Vector(c))[i] for c in o.bound_box) for o in parts) for i in range(3)))
    hi = Vector((max(max((o.matrix_world @ Vector(c))[i] for c in o.bound_box) for o in parts) for i in range(3)))
    ctr, size = (lo + hi) / 2, (hi - lo).length
    cam = bpy.data.objects.new("BlockCam", bpy.data.cameras.new("BlockCam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    os.makedirs(f"{OUT}/renders", exist_ok=True)
    for tag, d in (("front", Vector((0.9, 1.3, 0.7))), ("back", Vector((-0.9, -1.3, 0.7)))):   # +Y is forward
        cam.location = ctr + d.normalized() * size * 1.5
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = f"{OUT}/renders/blockout_{tag}.png"
        bpy.ops.render.render(write_still=True)
    print("BLOCKOUT rendered", f"{OUT}/renders/blockout_front.png", "and parts.md")


def out_dir():
    return sys.argv[sys.argv.index("--") + 1]
