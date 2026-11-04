"""Part audit: the build fails unless every part of a model makes mechanical sense on paper and in the geometry.

Every part must be declared (kit.part): what it does (job), what it is mounted on (on) and how (joint). Fasteners
and weld beads are recognised by name and need no declaration. The audit then checks the real meshes:

  UNDOCUMENTED  a part with no declaration, or a declaration with no job
  NO MOUNT      a part whose mount is missing or names nothing that exists
  FLOATING      a part that does not touch what it says it is mounted on
  CUTS INTO     two parts that sink into each other without a joint that allows it (the "merges into each other"
                look); through / inset / pivot joints may sink in, everything else only touches (<= 2.5 mm)
  NO HARDWARE   a bolted part with no bolt on it, a welded part with no weld bead between it and its mount
  LOOSE BOLT    a fastener that touches nothing; BURIED BOLT one sunk deep into more than the part it fastens
  LOOSE WELD    a weld bead that does not touch two parts

Joints: ground, seated, bolted, welded, clamped, hinged, pivot, through, inset.
"""
import math
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

JOINTS = ("ground", "seated", "bolted", "welded", "clamped", "hinged", "pivot", "through", "inset")
EMBED_OK = ("through", "inset", "pivot")
TOUCH = 0.0015          # closer than this counts as touching
SINK_OK = 0.0025        # how far a plain joint may sink in (bevels, seating)
WASHER_SINK = 0.004     # a fastener may seat this far into anything it sits on
WELD_SINK = 0.025


class Part:
    def __init__(self, ob):
        self.ob = ob
        self.name = ob.name
        self.kind = ob.get("kind", "part")
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.transform(ob.matrix_world)
        bm.normal_update()
        self.verts = [v.co.copy() for v in bm.verts]
        self.edges = [(e.verts[0].co.copy(), e.verts[1].co.copy()) for e in bm.edges]
        # contact can happen mid-face (a flat foot on a curved wall touches at its centre, where there is no vertex)
        self.samples = self.verts + [f.calc_center_median() for f in bm.faces]
        self.bvh = BVHTree.FromBMesh(bm)
        bm.free()
        xs, ys, zs = zip(*self.verts)
        self.lo = Vector((min(xs), min(ys), min(zs)))
        self.hi = Vector((max(xs), max(ys), max(zs)))

    def near(self, other, m=TOUCH):
        return all(self.lo[i] - m <= other.hi[i] and other.lo[i] - m <= self.hi[i] for i in range(3))


def _inside(bvh, p):
    """Ray parity: odd hits = inside a closed mesh."""
    d = Vector((0.5773, 0.5774, 0.5775))
    hits, o = 0, p.copy()
    for _ in range(64):
        loc, nrm, idx, dist = bvh.ray_cast(o, d)
        if loc is None:
            break
        hits += 1
        o = loc + d * 1e-5
    return hits % 2 == 1


def depth(a, b):
    """How far a's vertices sink below b's surface (0 if none do)."""
    best = 0.0
    for v in a.verts:
        if not (b.lo.x - 1e-4 <= v.x <= b.hi.x + 1e-4 and b.lo.y - 1e-4 <= v.y <= b.hi.y + 1e-4
                and b.lo.z - 1e-4 <= v.z <= b.hi.z + 1e-4):
            continue
        loc, nrm, idx, dist = b.bvh.find_nearest(v)
        if loc is None or dist <= best or dist <= SINK_OK * 0.5:
            continue
        if (v - loc).dot(nrm) < 0 and _inside(b.bvh, v):
            best = dist
    return best


def crosses(a, b):
    """True if an edge of a passes through b's surface between two points outside b (thin parts crossing)."""
    for e0, e1 in a.edges:
        d = e1 - e0
        L = d.length
        if L < 0.006:
            continue
        d.normalize()
        loc, nrm, idx, dist = b.bvh.ray_cast(e0, d, L)
        if loc is None or dist < 0.002 or L - dist < 0.002 or abs(nrm.dot(d)) < 0.3:
            continue
        if not _inside(b.bvh, e0) and not _inside(b.bvh, e1):
            loc2, nrm2, idx2, dist2 = b.bvh.ray_cast(loc + d * 1e-5, d, L - dist)
            if loc2 is None or dist2 < 0.002:
                continue
            # in and out again, and the stretch between is well inside b (not grazing along one of its faces)
            m = (loc + loc2) / 2
            mloc, mn, mi, md = b.bvh.find_nearest(m)
            if md is not None and md > SINK_OK and _inside(b.bvh, m):
                return True
    return False


def gap(a, b):
    """Smallest vertex-to-surface distance between two parts (0 if they overlap)."""
    if a.bvh.overlap(b.bvh):
        return 0.0
    g = 1e9
    for x, y in ((a, b), (b, a)):
        for v in x.samples:
            loc, nrm, idx, dist = y.bvh.find_nearest(v, g)
            if loc is not None and dist < g:
                g = dist
    return g


def run(objs, spec, blockout=False):
    """objs: the built parts; spec: {prefix: dict(job, on, joint, joins)}. Returns (errors, sheet rows)."""
    parts = [Part(o) for o in objs]
    errors = []
    prefixes = sorted(spec, key=len, reverse=True)

    def entry(name):
        for p in prefixes:
            if name.startswith(p):
                return p
        return None

    def resolved(p):
        """on/joint, inherited from the nearest shorter declared prefix when a sub-part leaves them out."""
        on, joint = spec[p].get("on"), spec[p].get("joint")
        q = p
        while (on is None or joint is None) and q:
            q = q[:-1]
            if q in spec:
                on = on if on is not None else spec[q].get("on")
                joint = joint if joint is not None else spec[q].get("joint")
        return on, joint

    for p in parts:
        p.entry = entry(p.name) if p.kind == "part" else None
    by_entry = {}
    for p in parts:
        if p.entry:
            by_entry.setdefault(p.entry, []).append(p)

    def matches(q, on):
        """q is (part of) `on`: the part declared under exactly that prefix, or, when `on` names a group that has
        no declaration of its own (e.g. 'Skid' for SkidBeam/SkidDeck/...), anything whose name starts with it."""
        if q.kind != "part":
            return False
        if on in spec and on in by_entry:
            return q.entry == on
        return q.name.startswith(on)       # a group, or an assembly whose sub-parts carry the declarations

    def targets(on, me):
        return [q for q in parts if q is not me and matches(q, on)]

    def family(p):
        """the part and its declared sub-parts (HousingPanel-X1 -> its hinges, latch, slots)"""
        return [q for q in parts if q.entry and q.entry.startswith(p.entry)]

    def related(a, b):
        """the joint between two parts, if one is declared mounted on / joining the other (most permissive wins)"""
        found = []
        for x, y in ((a, b), (b, a)):
            if not x.entry:
                continue
            on, joint = resolved(x.entry)
            if on and on != "ground" and matches(y, on):
                found.append(joint)
            if any(matches(y, n) for n in spec[x.entry].get("joins", ())):
                found.append(joint if joint in EMBED_OK else "inset")
        if not found:
            return None
        return next((j for j in found if j in EMBED_OK), found[0])

    # declarations
    for p in parts:
        if p.kind != "part":
            continue
        if p.entry is None:
            errors.append(f"UNDOCUMENTED  {p.name}: no kit.part() says what it does")
            continue
        if not spec[p.entry].get("job"):
            errors.append(f"UNDOCUMENTED  {p.name}: declared as '{p.entry}' without a job")
        on, joint = resolved(p.entry)
        if joint not in JOINTS:
            errors.append(f"NO MOUNT      {p.name}: joint '{joint}' is not one of {', '.join(JOINTS)}")
        if on is None:
            errors.append(f"NO MOUNT      {p.name}: nothing says what it is mounted on")
        elif on != "ground":
            ts = targets(on, p)
            if not ts:
                errors.append(f"NO MOUNT      {p.name}: mounted on '{on}', which does not exist")
            else:
                g = min(gap(p, t) for t in ts if p.near(t, 0.05)) if any(p.near(t, 0.05) for t in ts) else 1e9
                if g > TOUCH:
                    errors.append(f"FLOATING      {p.name}: {'%.1f mm' % (g * 1000) if g < 1e8 else 'far'} "
                                  f"away from '{on}', which it is mounted on")

    # sinking into each other
    fast_deep = {}
    for i, a in enumerate(parts):
        for b in parts[i + 1:]:
            if not a.near(b):
                continue
            if a.kind == "weld" and b.kind == "weld":
                continue
            if not a.bvh.overlap(b.bvh):
                continue
            d = max(depth(a, b), depth(b, a))
            if d <= SINK_OK and (crosses(a, b) or crosses(b, a)):
                d = 0.01            # passes clean through (no vertex inside, e.g. two crossed bars): count as 10 mm
            if d <= SINK_OK:
                continue
            if "weld" in (a.kind, b.kind):
                if d > WELD_SINK:
                    w, o = (a, b) if a.kind == "weld" else (b, a)
                    errors.append(f"CUTS INTO     weld {w.name} is buried {d * 1000:.0f} mm in {o.name}")
                continue
            if "fitting" in (a.kind, b.kind):
                f, o = (a, b) if a.kind == "fitting" else (b, a)
                fast_deep.setdefault(f.name, [("fitting",)]).append((d, o.name))
                continue
            if "fastener" in (a.kind, b.kind):
                f, o = (a, b) if a.kind == "fastener" else (b, a)
                if o.kind == "fastener":
                    errors.append(f"CUTS INTO     bolts {a.name} and {b.name} overlap ({d * 1000:.0f} mm)")
                elif d > WASHER_SINK:
                    fast_deep.setdefault(f.name, []).append((d, o.name))
                    inside = sum(1 for v in f.verts if o.bvh.find_nearest(v)[0] is not None
                                 and o.bvh.find_nearest(v)[3] > 0.001 and _inside(o.bvh, v))
                    if inside > 0.5 * len(f.verts):  # the head itself is inside something: hidden, fastens nothing
                        errors.append(f"BURIED BOLT   {f.name} is hidden inside {o.name}")
                continue
            for x, y in ((a, b), (b, a)):           # a part buried completely inside another does nothing
                if len(x.verts) >= 4 and all(y.lo[i] <= x.lo[i] and x.hi[i] <= y.hi[i] for i in range(3)):
                    inside = sum(1 for v in x.verts if (y.bvh.find_nearest(v)[3] or 0) > 0.0005 and _inside(y.bvh, v))
                    if inside >= 0.95 * len(x.verts):
                        errors.append(f"HIDDEN        {x.name} is completely inside {y.name}: nobody sees it, it does nothing")
            joint = related(a, b)
            if joint in EMBED_OK:
                continue
            why = f"joint '{joint}' only allows touching" if joint else "no joint between them"
            errors.append(f"CUTS INTO     {a.name} and {b.name} sink {d * 1000:.0f} mm into each other ({why})")
    for f, lst in fast_deep.items():
        allowed = 1
        if lst and lst[0] == ("fitting",):       # a union nut: the pipe runs through it and it sits on the part
            lst, allowed = lst[1:], 2
        if len(lst) > allowed:
            lst.sort(reverse=True)
            for d, o in lst[allowed:]:
                errors.append(f"BURIED BOLT   {f} sinks {d * 1000:.0f} mm into {o} (it can only fasten one part)")

    # hardware on every joint
    if not blockout:
        fasteners = [p for p in parts if p.kind in ("fastener", "fitting")]
        welds = [p for p in parts if p.kind == "weld"]
        for f in fasteners:
            if not any(f.near(q) and gap(f, q) <= TOUCH for q in parts if q.kind not in ("fastener", "fitting")):
                errors.append(f"LOOSE BOLT    {f.name} touches nothing")
        for w in welds:
            n = sum(1 for q in parts if q.kind == "part" and w.near(q) and gap(w, q) <= TOUCH)
            if n < 2:
                errors.append(f"LOOSE WELD    {w.name} touches {n} part(s); a weld joins two")
        for p in parts:
            if p.kind != "part" or not p.entry:
                continue
            on, joint = resolved(p.entry)
            if joint == "bolted":
                if not any(q.near(f) and gap(q, f) <= TOUCH for q in family(p) for f in fasteners):
                    errors.append(f"NO HARDWARE   {p.name} is 'bolted' to '{on}' but has no bolt on it")
            elif joint == "welded" and on not in (None, "ground"):
                ts = targets(on, p)
                if not any(p.near(w) and gap(p, w) <= TOUCH and any(w.near(t) and gap(w, t) <= TOUCH for t in ts)
                           for w in welds):
                    errors.append(f"NO HARDWARE   {p.name} is 'welded' to '{on}' but no weld bead joins them")

    rows = []
    for pfx in sorted(spec):
        on, joint = resolved(pfx)
        n = len(by_entry.get(pfx, []))
        rows.append((pfx, spec[pfx].get("job", ""), on or "", joint or "", n))
    return errors, rows
