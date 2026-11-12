"""The modelling kit the city scripts share: materials, parts, joining and export, and renders.

Every part is added with its bottom centre (or, where it says so, its middle) at a point in metres,
+Y the piece's front, +Z up. Parts marked detail=True are joined into the "detail" mesh, which the
game stops drawing from far away; the rest are joined into one mesh named after the piece.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Quaternion, Vector

CELL = 10.0
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# --- Scene and parts -------------------------------------------------------------------------------

_mats = {}
_parts = []  # (object, is_detail) for the piece being built
_marks = []  # named points in it (an inside's way out, its lamps)
_screens = []  # the displays in it: meshes of their own, which the game puts pictures on
POSTERS = []  # pictures to show on them in a render (the game chooses its own)
FACTION = ""  # whose piece was built last: renders dress it in that faction's textures


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    _parts.clear()
    _marks.clear()
    _screens.clear()


def mat(name, rgb, emit=0.0, metal=0.55, rough=0.5):
    """A material: a hex colour, optionally glowing (emit = strength)."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    c = tuple(int(rgb[i:i + 2], 16) / 255.0 for i in (1, 3, 5)) + (1.0,)
    b.inputs["Base Color"].default_value = c
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit > 0:
        b.inputs["Emission Color"].default_value = c
        b.inputs["Emission Strength"].default_value = emit
    _mats[name] = m
    return m


def _keep(ob, m, detail, bevel=0.0):
    ob.data.materials.append(m)
    if bevel > 0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=mod.name)
    _parts.append((ob, detail))
    return ob


def box(size, at, m, bevel=0.0, rot=(0, 0, 0), detail=False):
    """A box `size` (x, y, z) standing with its bottom centre at `at`."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(at[0], at[1], at[2] + size[2] / 2), rotation=rot)
    ob = bpy.context.object
    ob.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _keep(ob, m, detail, min(bevel, min(size) * 0.45))


def cyl(r, h, at, m, verts=16, top=None, rot=(0, 0, 0), detail=False, bevel=0.0, turn=0.0):
    """A drum (or a cone when `top` is a radius) of height `h`, its bottom centre at `at`
    (unless laid over with `rot`: then `at` is its middle). `turn` spins an upright one about Z."""
    loc = (at[0], at[1], at[2] + (h / 2 if rot == (0, 0, 0) else 0))
    if rot == (0, 0, 0):
        rot = (0, 0, turn)
    if top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=top, depth=h, location=loc, rotation=rot)
    return _keep(bpy.context.object, m, detail, bevel)


def text(body, size, at, m, depth=0.15, detail=False):
    """Stencilled lettering standing upright on a +Y face, its centre at `at`."""
    bpy.ops.object.text_add(location=at, rotation=(math.pi / 2, 0, math.pi))
    ob = bpy.context.object
    ob.data.body = body
    ob.data.size = size
    ob.data.extrude = depth / 2
    ob.data.align_x = "CENTER"
    ob.data.align_y = "CENTER"
    bpy.ops.object.convert(target="MESH")
    return _keep(bpy.context.object, m, detail)


def finish(faction, piece):
    """Joins the parts into "<piece>" and "detail" and exports the glb."""
    out = []
    for detail in (False, True):
        obs = [o for o, d in _parts if d == detail]
        if not obs:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in obs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        ob = bpy.context.object
        ob.name = "detail" if detail else piece
        ob.data.name = ob.name
        out.append(ob)
    bpy.ops.object.select_all(action="DESELECT")
    for o in out + _marks + _screens:
        o.select_set(True)
    global FACTION
    FACTION = faction
    path = os.path.join(ROOT, "game", "city", faction, piece + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    tris = sum(len(o.data.polygons) for o in out)
    print(f"{faction}/{piece}.glb  {tris} faces")
    return out


def render(path, foot, height):
    """A daylight three-quarter view of the piece just built."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.resolution_x, scene.render.resolution_y = 900, 640
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.4, 0.52, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scene.world = world
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(35)))
    bpy.context.object.data.energy = 3.0
    bpy.ops.mesh.primitive_plane_add(size=max(foot) * 4, location=(0, 0, -0.05))
    bpy.context.object.data.materials.append(mat("ground", "#3a3f44", metal=0, rough=0.9))
    texture_scene(FACTION)
    span = max(max(foot), height)
    d = span * 1.75
    bpy.ops.object.camera_add(location=(d * 0.62, d * 0.85, height * 0.5 + span * 0.45))
    cam = bpy.context.object
    target = bpy.data.objects.new("target", None)
    target.location = (0, 0, height * 0.45)
    scene.collection.objects.link(target)
    c = cam.constraints.new("TRACK_TO")
    c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"
    cam.data.lens = 40
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def texture_scene(group):
    """Dresses every material in the scene with its textures from game/textures, the way the game
    does (game/surfaces.gd): the set listed for the material's name in surfaces.json under `group`
    (a faction, or "models"), projected from the three axes in the object's own space. For renders
    only: the exported models stay plain and the game adds the textures itself."""
    import json
    import re
    tex_dir = os.path.join(ROOT, "game", "textures")
    with open(os.path.join(tex_dir, "surfaces.json")) as f:
        table = json.load(f)
    entries = table.get(group, {})
    for m in bpy.data.materials:
        name = re.sub(r"\.\d+$", "", m.name).split(":")[0]
        e = entries.get(name)
        if e is None or not m.use_nodes or m.get("textured"):
            continue
        e = {"set": e} if isinstance(e, str) else e
        folder = os.path.join(tex_dir, e["set"])
        if not os.path.exists(os.path.join(folder, "albedo.png")):
            continue
        m["textured"] = True
        tile = e.get("tile", table["sets"].get(e["set"], 4.0))
        nt = m.node_tree
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        coord = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (1 / tile,) * 3
        nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])

        def tex(map_name, colour):
            path = os.path.join(folder, map_name + ".png")
            if not os.path.exists(path):
                return None
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = bpy.data.images.load(path, check_existing=True)
            t.image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
            t.projection = "BOX"
            t.projection_blend = 0.25
            nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
            return t

        def multiply(a, b_socket_or_value):
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            if isinstance(a, tuple):
                mix.inputs[6].default_value = a
            else:
                nt.links.new(a, mix.inputs[6])
            nt.links.new(b_socket_or_value, mix.inputs[7])
            return mix.outputs[2]

        def scale(socket, value):
            mm = nt.nodes.new("ShaderNodeMath")
            mm.operation = "MULTIPLY"
            nt.links.new(socket, mm.inputs[0])
            mm.inputs[1].default_value = value
            return mm.outputs[0]

        albedo, orm, glow = tex("albedo", True), tex("orm", False), tex("glow", False)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(orm.outputs["Color"], sep.inputs["Color"])
        base = tuple(b.inputs["Base Color"].default_value)
        nt.links.new(multiply(multiply(base, albedo.outputs["Color"]), sep.outputs["Red"]), b.inputs["Base Color"])
        rough = min(1.0, b.inputs["Roughness"].default_value * 1.25)
        nt.links.new(scale(sep.outputs["Green"], rough), b.inputs["Roughness"])
        nt.links.new(scale(sep.outputs["Blue"], b.inputs["Metallic"].default_value), b.inputs["Metallic"])
        # The game reads the normal map; with no UVs to give it a tangent here, bump from the albedo.
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.35
        bump.inputs["Distance"].default_value = 0.02
        nt.links.new(albedo.outputs["Color"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
        if glow:
            strength = b.inputs["Emission Strength"].default_value
            if strength > 0:
                colour = tuple(b.inputs["Emission Color"].default_value)
            elif "glow" in e:
                h = e["glow"]
                colour = tuple(int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)) + (1.0,)
                b.inputs["Emission Strength"].default_value = 2.0
            else:
                continue
            nt.links.new(multiply(colour, glow.outputs["Color"]), b.inputs["Emission Color"])


def marker(name, at):
    """A named point exported with the piece: the game reads "exit" (the way out of an inside) and
    "light..." (where it hangs a lamp)."""
    ob = bpy.data.objects.new(name, None)
    ob.location = at
    bpy.context.scene.collection.objects.link(ob)
    _marks.append(ob)
    return ob


def display(M, at, facing, w=0.9, h=1.35, frame="dark", lamp="amber"):
    """A display hung on a wall: `at` is the bottom centre of its screen, on the wall's face, and
    `facing` the way it looks ("+x", "-x", "+y" or "-y"). The frame is detail. The screen is a mesh
    of its own, "screen1", "screen2"..., mapped so a picture fills it upright: the game shows the
    faction's propaganda on every mesh so named."""
    n = {"+x": (1, 0), "-x": (-1, 0), "+y": (0, 1), "-y": (0, -1)}[facing]
    r = (-n[1], n[0])  # to the right of someone looking at it
    x, y, z = at
    size = (w + 0.14, 0.08, h + 0.14) if n[0] == 0 else (0.08, w + 0.14, h + 0.14)
    box(size, (x + n[0] * 0.04, y + n[1] * 0.04, z - 0.07), M[frame], detail=True)
    box((0.22, 0.05, 0.05) if n[0] == 0 else (0.05, 0.22, 0.05), (x + n[0] * 0.05, y + n[1] * 0.05, z - 0.17), M[lamp], detail=True)
    c = (x + n[0] * 0.085, y + n[1] * 0.085)
    name = f"screen{len(_screens) + 1}"
    me = bpy.data.meshes.new(name)
    me.from_pydata([(c[0] - r[0] * w / 2, c[1] - r[1] * w / 2, z), (c[0] + r[0] * w / 2, c[1] + r[1] * w / 2, z),
                    (c[0] + r[0] * w / 2, c[1] + r[1] * w / 2, z + h), (c[0] - r[0] * w / 2, c[1] - r[1] * w / 2, z + h)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    for i, at_uv in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
        uv.data[i].uv = at_uv
    me.materials.append(mat("screen", "#16304f", emit=1.0, metal=0.0))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    _screens.append(ob)
    return ob


def wall(a, b, z, h, m, gaps=(), t=0.4):
    """A wall from `a` to `b` ((x, y) points, along X or along Y), z up to z + h, with doorways:
    each gap is (how far along from `a` its middle is, its width, its height)."""
    along_x = a[1] == b[1]
    length = abs(b[0] - a[0]) + abs(b[1] - a[1])
    sgn = 1 if (b[0] - a[0] if along_x else b[1] - a[1]) > 0 else -1

    def seg(d0, d1, z0, hh):
        if d1 - d0 < 0.01 or hh < 0.01:
            return
        mid = (d0 + d1) / 2
        at = (a[0] + sgn * mid, a[1], z0) if along_x else (a[0], a[1] + sgn * mid, z0)
        box((d1 - d0, t, hh) if along_x else (t, d1 - d0, hh), at, m)

    pos = 0.0
    for c, w, gh in sorted(gaps):
        seg(pos, c - w / 2, z, h)
        seg(c - w / 2, c + w / 2, z + gh, h - gh)  # over the doorway
        pos = c + w / 2
    seg(pos, length, z, h)


def render_inside(path, eye=(0.0, -0.5, 1.7), look=(0.0, -20.0, 2.5), lens=17):
    """A view from where you come in, lit by the piece's own lamps."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.resolution_x, scene.render.resolution_y = 1200, 700
    world = bpy.data.worlds.new("dark")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.025, 0.035, 1)
    scene.world = world
    for i, ob in enumerate(_screens if POSTERS else []):  # a poster on every display
        m = bpy.data.materials.new("poster")
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(POSTERS[i % len(POSTERS)])
        m.node_tree.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        m.node_tree.links.new(tex.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.0
        ob.data.materials.clear()
        ob.data.materials.append(m)
    texture_scene(FACTION)
    for mk in _marks:
        if mk.name.startswith("light"):
            bpy.ops.object.light_add(type="POINT", location=mk.location)
            bpy.context.object.data.energy = 2500 if mk.location.z > 8 else 500
            bpy.context.object.data.color = (0.85, 0.92, 1.0)
            bpy.context.object.data.shadow_soft_size = 0.5
    bpy.ops.object.camera_add(location=eye)
    cam = bpy.context.object
    target = bpy.data.objects.new("target", None)
    target.location = look
    scene.collection.objects.link(target)
    c = cam.constraints.new("TRACK_TO")
    c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"
    cam.data.lens = lens
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def cone(r, h, at, m, verts=4, top=0.0, sx=1.0, sy=1.0, turn=0.0, detail=False):
    """A cone or pyramid standing at `at`, stretched (sx, sy) and turned `turn` radians about Z.
    With 4 sides and turn = pi / 4 its base is a square of side r * 1.41, edges along X and Y."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=top, depth=h, location=(at[0], at[1], at[2] + h / 2), rotation=(0, 0, turn))
    ob = bpy.context.object
    if sx != 1.0 or sy != 1.0:
        ob.scale = (sx, sy, 1.0)
        bpy.ops.object.transform_apply(scale=True)
    return _keep(ob, m, detail)


def spike(r, base, tip_at, m, verts=4, tip=0.0, flat=1.0, detail=False):
    """A tapering beam from `base` to `tip_at` (any direction): a thorn, a leg, a buttress blade.
    `tip` is its radius at the far end. `flat` under 1 squeezes it into a blade standing on edge
    (thin sideways, so a leaning buttress keeps its full depth toward what it leans on)."""
    a, b = Vector(base), Vector(tip_at)
    d = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=tip, depth=d.length, location=(a + b) / 2)
    ob = bpy.context.object
    if flat != 1.0:
        ob.scale = (1.0, flat, 1.0)
        bpy.ops.object.transform_apply(scale=True)
    side = Vector((0, 0, 1)).cross(d)  # the level direction across the lean
    spin = math.atan2(-side.x, side.y) if side.length > 1e-6 else 0.0
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized()) @ Quaternion((0, 0, 1), spin)
    return _keep(ob, m, detail)


def ball(r, at, m, sx=1.0, sy=1.0, sz=1.0, segs=12, rings=6, dome=False, detail=False):
    """A sphere centred on `at`, stretched; dome=True keeps only its upper half."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=r, location=at)
    ob = bpy.context.object
    ob.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(scale=True)
    if dome:
        _cut_below(ob)
    return _keep(ob, m, detail)


def _cut_below(ob):
    """Removes everything under the object's own middle."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
    bm.to_mesh(ob.data)
    bm.free()


def halfpipe(r, length, at, m, verts=12, detail=False):
    """A half-cylinder hut lying along Y, its flat side on the ground at `at`."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=length, location=at, rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.object
    bpy.ops.object.transform_apply(rotation=True)
    _cut_below(ob)
    return _keep(ob, m, detail)


def prism(w, h, length, at, m, detail=False):
    """A triangular prism (an A-frame, a steep roof): w wide, h high, its ridge along Y, standing
    with its base centre at `at`."""
    x, y, z = at
    a, l = w / 2, length / 2
    verts = [(x - a, y - l, z), (x + a, y - l, z), (x, y - l, z + h), (x - a, y + l, z), (x + a, y + l, z), (x, y + l, z + h)]
    faces = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    mesh = bpy.data.meshes.new("prism")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new("prism", mesh)
    bpy.context.scene.collection.objects.link(ob)
    return _keep(ob, m, detail)


def ring(R, r, at, m, upright=False, sx=1.0, sy=1.0, detail=False, segs=20):
    """A thin hoop of radius R centred on `at`: flat, or upright facing +Y."""
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=segs, minor_segments=4, location=at, rotation=(math.pi / 2 if upright else 0, 0, 0))
    ob = bpy.context.object
    if sx != 1.0 or sy != 1.0:
        ob.scale = (sx, sy, 1.0)
        bpy.ops.object.transform_apply(scale=True)
    return _keep(ob, m, detail)


# --- Faction materials and motifs ------------------------------------------------------------------
# The looks are set out in the "Faction building designs" doc.

def compact_mats():
    return {
        "navy": mat("navy", "#1f2b3e", metal=0.6, rough=0.45),
        "slate": mat("slate", "#33435a", metal=0.6, rough=0.5),
        "steel": mat("steel", "#3b4049", metal=0.75, rough=0.4),
        "deck": mat("deck", "#2a2e33", metal=0.5, rough=0.7),
        "blue": mat("blue", "#4f8fe0", emit=2.4),
        "amber": mat("amber", "#ffa733", emit=3.0),
        "white": mat("white", "#d9dee5", metal=0.1, rough=0.6),
        "hazard": mat("hazard", "#e0b020", metal=0.2, rough=0.6),
        "dark": mat("dark", "#111418", metal=0.3, rough=0.8),
    }


def slits(M, w, d, z0, h, every=4.0, skip_front=0.0, at=(0.0, 0.0)):
    """Rows of blue window slits round a block w x d standing at `at`, from z0 up h metres: short
    slits in pairs, with armour between them. `skip_front`: leave that many metres at the front's
    top bare (for a sign)."""
    n = max(1, int(h // every))
    for i in range(n):
        z = z0 + every * (i + 0.5) - 0.3
        for face, span in ((0, w), (1, d)):
            k = max(1, int(span // 7))
            seg = span * 0.8 / k
            for j in range(k):
                c = -span * 0.4 + seg * (j + 0.5)
                for side in (-1, 1):
                    if face == 0 and side == 1 and z > z0 + h - skip_front:
                        continue
                    half = (d if face == 0 else w) / 2 + 0.05
                    if face == 0:
                        box((seg * 0.7, 0.3, 0.55), (at[0] + c, at[1] + side * half, z), M["blue"])
                    else:
                        box((0.3, seg * 0.7, 0.55), (at[0] + side * half, at[1] + c, z), M["blue"])


def pilasters(M, w, d, z0, h, at=(0.0, 0.0)):
    """Steel ribs up the corners of a block standing at `at`."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((1.0, 1.0, h), (at[0] + sx * (w / 2 - 0.2), at[1] + sy * (d / 2 - 0.2), z0), M["steel"], bevel=0.15)


def twin_turret(M, at, scale=1.0):
    """The Compact's signature gun: two barrels on a round armoured base."""
    s = scale
    x, y, z = at
    cyl(3.6 * s, 2.4 * s, (x, y, z), M["slate"], verts=16, bevel=0.2 * s)
    cyl(3.9 * s, 0.4 * s, (x, y, z + 2.4 * s), M["hazard"], verts=16)
    box((4.6 * s, 5.0 * s, 2.4 * s), (x, y - 0.4 * s, z + 2.8 * s), M["navy"], bevel=0.5 * s)
    box((3.4 * s, 0.3 * s, 0.4 * s), (x, y + 2.15 * s, z + 4.1 * s), M["blue"], detail=s < 1.5)
    for side in (-1, 1):
        cyl(0.38 * s, 6.5 * s, (x + side * 0.9 * s, y + 4.5 * s, z + 3.9 * s), M["steel"], verts=10, rot=(math.pi / 2, 0, 0))
        cyl(0.5 * s, 1.0 * s, (x + side * 0.9 * s, y + 2.4 * s, z + 3.9 * s), M["dark"], verts=10, rot=(math.pi / 2, 0, 0))
    cyl(0.3 * s, 0.4 * s, (x, y - 2.2 * s, z + 5.2 * s), M["amber"], verts=8, detail=True)


def ashen_mats():
    """Black chitin plate lit blood red, over swamp and ash."""
    return {
        "black": mat("black", "#0d0e11", metal=0.35, rough=0.35),
        "char": mat("char", "#1d1e23", metal=0.35, rough=0.45),
        "red": mat("red", "#e0453c", emit=2.4),
        "core": mat("core", "#ff3a22", emit=4.0),
        "moss": mat("moss", "#1b231c", metal=0.0, rough=0.6),
    }


def luminar_mats():
    """Pale grey plating in long tapering plates, green light in every seam."""
    return {
        "pale": mat("pale", "#d3d8db", metal=0.35, rough=0.4),
        "grey": mat("grey", "#8f999f", metal=0.45, rough=0.45),
        "deck": mat("deck", "#343a40", metal=0.5, rough=0.6),
        "green": mat("green", "#4fd992", emit=2.2),
        "crystal": mat("crystal", "#6ff0ac", emit=3.0),
    }


def coma_mats():
    """Dark gunmetal traced with gold; discs floating on columns of light."""
    return {
        "gun": mat("gun", "#2c2e35", metal=0.85, rough=0.25),
        "black": mat("black", "#15161a", metal=0.8, rough=0.3),
        "gold": mat("gold", "#f0b545", emit=2.2),
        "goldm": mat("goldm", "#c9a04a", metal=1.0, rough=0.3),
        "light": mat("light", "#ffe9a8", emit=4.5),
    }
