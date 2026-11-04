"""Swap the placeholder meshes in the game scenes for the exported building models (one-off, re-runnable).
python art_src/wire_scenes.py   (from the repo root)
For each scene: removes the placeholder MeshInstance3D (and its mesh/material sub_resources) and the floating
name labels, instances the .glb as a "Model" child (pipes: as "Body", so span scaling still applies), resizes
the collision box to the model, and gives always-running machines the autoplay script."""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = os.path.join(ROOT, "scenes")
M = "res://data/models/buildings"
AUTOPLAY = "res://scripts/world/model_autoplay.gd"

# scene: (glb, remove_nodes, collision (size, centre_y) or None, autoplay, as_body)
LABELS = ["LabelPosZ", "LabelNegZ", "LabelPosX", "LabelNegX"]
CFG = {
    "smelter.tscn":       ("smelter/SM_Smelter.glb", ["MeshInstance3D"] + LABELS, ((2.0, 2.56, 2.0), 1.28), False, False),
    "processor.tscn":     ("crafter/SM_Crafter.glb", ["MeshInstance3D"] + LABELS, ((1.5, 1.7, 1.5), 0.85), False, False),
    "constructor.tscn":   ("constructor/SM_Constructor.glb", ["MeshInstance3D"] + LABELS, ((1.5, 2.1, 1.5), 1.05), False, False),
    "chest.tscn":         ("chest/SM_Chest.glb", ["MeshInstance3D"] + LABELS, ((1.5, 1.15, 1.5), 0.575), False, False),
    "turret_gun.tscn":    ("turret_gun/SM_TurretGun.glb", ["MeshInstance3D", "Barrel"] + LABELS, ((1.5, 1.16, 1.5), 0.58), False, False),
    "turret_cannon.tscn": ("turret_cannon/SM_TurretCannon.glb", ["MeshInstance3D", "Barrel"] + LABELS, ((1.5, 1.17, 1.5), 0.585), False, False),
    "foundation.tscn":    ("foundation/SM_Foundation.glb", ["MeshInstance3D"], None, False, False),
    "ship_core.tscn":     ("ship_core/SM_ShipCore.glb", ["MeshInstance3D"], None, True, False),
    "ship_cockpit.tscn":  ("ship_cockpit/SM_ShipCockpit.glb", ["MeshInstance3D"], None, False, False),
    "ship_hull.tscn":     ("ship_hull/SM_ShipHull.glb", ["MeshInstance3D"], None, False, False),
    "ship_gyroscope.tscn": ("ship_gyroscope/SM_ShipGyroscope.glb", ["MeshInstance3D"], None, True, False),
    "ship_thruster.tscn": ("ship_thruster/SM_ShipThruster.glb", ["MeshInstance3D"], None, False, False),
    "ship_garage.tscn":   ("ship_garage/SM_ShipGarage.glb", ["MeshInstance3D", "Label"], ((3.0, 0.28, 3.0), 0.14), True, False),
    "pipe_segment.tscn":  ("pipe/SM_VacuumPipe.glb", ["Body"], None, False, True),
    "pipe_merger.tscn":   ("merger/SM_Merger.glb", ["Body", "LabelTop"], None, False, True),
    "pipe_splitter.tscn": ("splitter/SM_Splitter.glb", ["Body", "LabelTop"], None, False, True),
}
HIDE_ON_PIPES = ["InputArrow", "OutputArrow"]


def blocks(text):
    """Split a .tscn into [header_line, body_lines] blocks."""
    out, cur = [], None
    for line in text.splitlines():
        if line.startswith("["):
            if cur:
                out.append(cur)
            cur = [line, []]
        elif cur is not None:
            cur[1].append(line)
    if cur:
        out.append(cur)
    return out


def node_name(header):
    m = re.match(r'\[node name="([^"]+)"', header)
    return m.group(1) if m else None


def node_parent(header):
    m = re.search(r'parent="([^"]+)"', header)
    return m.group(1) if m else None


def patch(fname, cfg):
    glb, remove, coll, autoplay, as_body = cfg
    path = os.path.join(S, fname)
    text = open(path, encoding="utf-8").read()
    if f'{M}/{glb}' in text:
        print("already wired:", fname)
        return
    bl = blocks(text)
    removed_res = set()
    keep = []
    body_pos = None
    for header, body in bl:
        n = node_name(header)
        if n in remove and node_parent(header) in (".", "Head"):
            for line in body:
                for rid in re.findall(r'SubResource\("([^"]+)"\)', line):
                    removed_res.add(rid)
                if n == "Body" and line.startswith("position"):
                    body_pos = line
            continue
        keep.append([header, body])
    # drop sub_resources only the removed nodes used
    used_elsewhere = set()
    for header, body in keep:
        for line in body:
            used_elsewhere.update(re.findall(r'SubResource\("([^"]+)"\)', line))
    final = []
    for header, body in keep:
        m = re.match(r'\[sub_resource type="[^"]+" id="([^"]+)"', header)
        if m and m.group(1) in removed_res and m.group(1) not in used_elsewhere:
            continue
        final.append([header, body])
    # ext_resources: model (+ autoplay script)
    ext = [f'[ext_resource type="PackedScene" path="{M}/{glb}" id="model"]']
    if autoplay:
        ext.append(f'[ext_resource type="Script" path="{AUTOPLAY}" id="autoplay"]')
    first_sub = next(i for i, (h, _) in enumerate(final) if not h.startswith("[gd_scene") and not h.startswith("[ext_resource"))
    for e in reversed(ext):
        final.insert(first_sub, [e, [""]])
    # collision resize
    if coll:
        (sx, sy, sz), cy = coll
        shape_id = None
        for header, body in final:
            if node_name(header) == "CollisionShape3D":
                for i, line in enumerate(body):
                    if line.startswith("transform"):
                        body[i] = f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {cy}, 0)"
                    m = re.search(r'SubResource\("([^"]+)"\)', line)
                    if line.startswith("shape") and m:
                        shape_id = m.group(1)
        for header, body in final:
            if shape_id and f'id="{shape_id}"' in header:
                for i, line in enumerate(body):
                    if line.startswith("size"):
                        body[i] = f"size = Vector3({sx}, {sy}, {sz})"
    # hide the debug arrows on pipes (code still moves them)
    if as_body:
        for header, body in final:
            if node_name(header) in HIDE_ON_PIPES and not any(l.startswith("visible") for l in body):
                body.insert(0, "visible = false")
    # the model node
    name = "Body" if as_body else "Model"
    node = [f'[node name="{name}" parent="." instance=ExtResource("model")]', []]
    if as_body:
        node[1].append(body_pos or "position = Vector3(0, 0.45, 0)")
    if autoplay:
        node[1].append('script = ExtResource("autoplay")')
    node[1].append("")
    final.append(node)
    # rebuild text, fix load_steps
    out = []
    for header, body in final:
        if out and out[-1] != "":
            out.append("")
        out.append(header)
        out.extend(l for l in body if l != "")
    txt = "\n".join(out).rstrip() + "\n"
    n_res = sum(1 for h, _ in final if h.startswith("[ext_resource") or h.startswith("[sub_resource"))
    txt = re.sub(r"load_steps=\d+", f"load_steps={n_res + 1}", txt, count=1)
    open(path, "w", encoding="utf-8", newline="\n").write(txt)
    print("wired:", fname)


for f, c in CFG.items():
    patch(f, c)
