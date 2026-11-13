"""Pictures of the sector battle's units and structures (game/battle/battle_models.gd) wearing each
faction's textures, rendered in Blender.

    python tools/blender/battle_models.py OUT_DIR [compact ashen luminar coma militia] [army] [base] [tanks] [before] [clash] [samples=N]

Those models exist only as GDScript, so this reads the script's `match type:` block, turns each
case into Python (boxes, cylinders, cones and tracks, with the same sizes and paint masks), and
builds it in Blender. The textures go on the way the game's shader lays them: each flat face from
the axis it faces most, the set listed for the faction under "battle" in
game/textures/surfaces.json on the painted hull and its "_frame" set on the plain parts, with no
normal map (the game's shader has none either). A look at the models, not an exporter.
"""

import json
import math
import os
import re
import sys

import bpy  # noqa: F401  (first: it makes bmesh importable outside Blender)
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402

SCRIPT = os.path.join(kit.ROOT, "game", "battle", "battle_models.gd")
TEXTURES = os.path.join(kit.ROOT, "game", "textures")

# The factions' colours as the server gives them, and the militia's (battle_view.gd).
SIDES = {"compact": "#58b7ff", "ashen": "#e0453c", "luminar": "#4fd992", "coma": "#f0b545", "militia": "#db9947"}

PLAIN, GLOW, SIDE_GLOW, PAINT = 0.0, 0.5, 0.75, 1.0

# --- A little of Godot, in Python ------------------------------------------------------------------


class V:
    """Vector3."""

    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)

    def __add__(self, o):
        return V(self.x + o.x, self.y + o.y, self.z + o.z)

    def __mul__(self, k):
        return V(self.x * k, self.y * k, self.z * k)

    def m(self):
        return Vector((self.x, self.y, self.z))


V.ZERO, V.RIGHT, V.UP, V.BACK = V(), V(1, 0, 0), V(0, 1, 0), V(0, 0, 1)


class B:
    """Basis: nothing, or a turn about an axis."""

    def __init__(self, axis=None, angle=0.0):
        self.mat = Matrix.Rotation(angle, 3, axis.m()) if axis else Matrix.Identity(3)

    def __mul__(self, v):
        return V(*(self.mat @ v.m()))


class Color:
    def __init__(self, r, g, b):
        self.r, self.g, self.b = r, g, b

    def key(self):
        return "%02x%02x%02x" % tuple(round(c * 255) for c in (self.r, self.g, self.b))


Color.WHITE = Color(1, 1, 1)


def _from_euler(rot):
    """Basis.from_euler: about Z, then X, then Y."""
    return Matrix.Rotation(rot.y, 3, "Y") @ Matrix.Rotation(rot.x, 3, "X") @ Matrix.Rotation(rot.z, 3, "Z")


def _begin():
    return []  # faces: (corners, normal, colour, mask), in Godot's space


def _quad(st, a, b, c, d, colour, mask):
    st.append(([a, b, c, d], (b - a).cross(c - a).normalized(), colour, mask))


def _box(st, size, pos, colour, mask, rot=V.ZERO):
    b = _from_euler(rot)
    h = Vector((size.x * 0.5, size.y * 0.5, size.z * 0.5))

    def p(x, y, z):
        return pos.m() + b @ Vector((x * h.x, y * h.y, z * h.z))

    _quad(st, p(-1, 1, -1), p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1), colour, mask)
    _quad(st, p(-1, -1, 1), p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), colour, mask)
    _quad(st, p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1), colour, mask)
    _quad(st, p(1, -1, -1), p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1), colour, mask)
    _quad(st, p(1, -1, 1), p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), colour, mask)
    _quad(st, p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), colour, mask)


def _cyl(st, radius, height, pos, colour, mask, sides=12, basis=None):
    _cone(st, radius, radius, height, pos, colour, mask, sides, basis)


def _cone(st, r0, r1, height, pos, colour, mask, sides=12, basis=None):
    b = (basis or B()).mat
    at = pos.m()
    y0, y1 = -height * 0.5, height * 0.5
    for k in range(sides):
        a0, a1 = math.tau * k / sides, math.tau * (k + 1) / sides
        b0 = at + b @ Vector((math.cos(a0) * r0, y0, math.sin(a0) * r0))
        b1 = at + b @ Vector((math.cos(a1) * r0, y0, math.sin(a1) * r0))
        t0 = at + b @ Vector((math.cos(a0) * r1, y1, math.sin(a0) * r1))
        t1 = at + b @ Vector((math.cos(a1) * r1, y1, math.sin(a1) * r1))
        if r1 > 0.0:
            _quad(st, b0, t0, t1, b1, colour, mask)
            st.append(([at + b @ Vector((0, y1, 0)), t1, t0], b @ Vector((0, 1, 0)), colour, mask))
        else:
            st.append(([b0, t0, b1], (t0 - b0).cross(b1 - b0).normalized(), colour, mask))
        st.append(([at + b @ Vector((0, y0, 0)), b0, b1], b @ Vector((0, -1, 0)), colour, mask))


def _tracks(st, x, length, height):
    for sx in (-x, x):
        _box(st, V(1.1, height, length), V(sx, height * 0.5 + 0.05, 0), NS["DARK"], PLAIN)
        _box(st, V(1.15, 0.25, length * 0.86), V(sx, height * 0.62, 0), NS["GREY"], PLAIN)


NS = {"V": V, "B": B, "Color": Color, "PI": math.pi, "TAU": math.tau, "cos": math.cos, "sin": math.sin,
      "deg_to_rad": math.radians, "PLAIN": PLAIN, "GLOW": GLOW, "SIDE_GLOW": SIDE_GLOW, "PAINT": PAINT,
      "_begin": _begin, "_box": _box, "_cyl": _cyl, "_cone": _cone, "_tracks": _tracks}


def load_models():
    """{type: function(body) -> (top faces or None, top_at)} from the script's match block, and its colours."""
    src = open(SCRIPT).read()
    for name, r, g, b in re.findall(r"^const (\w+) := Color\(([\d.]+), ([\d.]+), ([\d.]+)\)", src, re.M):
        NS[name] = Color(float(r), float(g), float(b))
    block = src[src.index("\tmatch type:"):src.index("\tvar out :=")]
    out, lines = {}, None
    for line in block.splitlines()[1:]:
        case = re.match(r'\t\t("(\w+)"|_):$', line)
        if case:
            lines = out.setdefault(case.group(2), []) if case.group(2) else []
            continue
        s = line[3:].split(" #")[0].rstrip()
        if not s.strip() or s.strip().startswith("#"):
            continue
        s = re.sub(r"\bvar (\w+) :=", r"\1 =", s)
        s = re.sub(r"for (\w+) in (\d+):", r"for \1 in range(\2):", s)
        s = s.replace("Vector3(", "V(").replace("Vector3.", "V.").replace("Basis(", "B(")
        lines.append(s.replace("\t", "    "))
    models = {}
    for name, body in out.items():
        code = f"def unit(body):\n    top = None\n    top_at = V()\n    muzzle = 2.0\n" + "".join(f"    {s}\n" for s in body) + "    return top, top_at\n"
        scope = {}
        exec(code, NS, scope)
        models[name] = scope["unit"]
    return models


# --- Building them in Blender ----------------------------------------------------------------------


def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgb(hex_colour):
    return tuple(_linear(int(hex_colour[i:i + 2], 16) / 255) for i in (1, 3, 5))


_table = None


def _maps(name):
    """What the shader would be given for `name` under "battle": (folder, tile), or None."""
    global _table
    if _table is None:
        with open(os.path.join(TEXTURES, "surfaces.json")) as f:
            _table = json.load(f)
    e = _table.get("battle", {}).get(name)
    if e is None:
        return None
    e = {"set": e} if isinstance(e, str) else e
    return os.path.join(TEXTURES, e["set"]), e.get("tile", _table["sets"].get(e["set"], 4.0))


def material(side, colour, mask, plain=False, look=None):
    """One part's material, as the game's shader paints it (SHADER in battle_models.gd). `look` is
    whose textures it wears, if not the side's own: a unit with a set of its own ("ashen/artillery_t3")."""
    look = look or side
    kind = "hull" if mask > 0.85 else "side" if mask > 0.6 else "glow" if mask > 0.35 else "frame"
    name = f"{side}:{look}:{kind}:{colour.key()}" + (":plain" if plain else "")
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tint = _rgb(SIDES[side])
    base = tuple(_linear(c) for c in (colour.r, colour.g, colour.b))
    col = tuple(t * (0.75 + base[1] * 1.6) for t in tint) if kind == "hull" else tint if kind == "side" else base
    emit = tuple(t * 2.4 for t in tint) if kind == "side" else tuple(c * 2.6 for c in base) if kind == "glow" else (0, 0, 0)
    bsdf.inputs["Base Color"].default_value = col + (1,)
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Metallic"].default_value = 0.1
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Emission Color"].default_value = tuple(e + c * 0.12 for e, c in zip(emit, col)) + (1,)
    maps = None if plain or kind in ("side", "glow") else _maps(look if kind == "hull" else look + "_frame")
    if maps is None:
        return m
    folder, tile = maps
    uv = nt.nodes.new("ShaderNodeUVMap")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / tile, 1 / tile, 1)
    nt.links.new(uv.outputs["UV"], mapping.inputs["Vector"])

    def tex(map_name, colour_data):
        path = os.path.join(folder, map_name + ".png")
        if not os.path.exists(path):
            return None
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(path, check_existing=True)
        t.image.colorspace_settings.name = "sRGB" if colour_data else "Non-Color"
        nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
        return t.outputs["Color"]

    def mix(kind_, a, b):
        n = nt.nodes.new("ShaderNodeMix")
        n.data_type, n.blend_type = "RGBA", kind_
        n.inputs["Factor"].default_value = 1.0
        for socket, v in ((n.inputs[6], a), (n.inputs[7], b)):
            if isinstance(v, tuple):
                socket.default_value = v + (1,) * (4 - len(v))
            else:
                nt.links.new(v, socket)
        return n.outputs[2]

    def times(socket, k):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = "MULTIPLY"
        n.use_clamp = True
        nt.links.new(socket, n.inputs[0])
        n.inputs[1].default_value = k
        return n.outputs[0]

    albedo, orm, glow = tex("albedo", True), tex("orm", False), tex("glow", False)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(orm, sep.inputs["Color"])
    lit = mix("MULTIPLY", mix("MULTIPLY", tuple(c * 1.3 for c in col), albedo), sep.outputs["Red"])  # lift 1.3
    nt.links.new(lit, bsdf.inputs["Base Color"])
    nt.links.new(times(sep.outputs["Green"], 0.69), bsdf.inputs["Roughness"])
    nt.links.new(times(sep.outputs["Blue"], 0.1), bsdf.inputs["Metallic"])
    own = mix("MULTIPLY", lit, (0.12, 0.12, 0.12))
    if glow and kind == "hull":
        own = mix("ADD", own, mix("MULTIPLY", tuple(t * 1.6 for t in tint), glow))  # lines 1.6
    nt.links.new(own, bsdf.inputs["Emission Color"])
    return m


TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot's Y up, front +Z -> Blender's Z up, front -Y


def _object(name, faces, side, plain, look=None):
    """A mesh from faces in Godot's space, with the face-projected UVs the shader works out."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("face")
    slots, mats = {}, []
    for corners, normal, colour, mask in faces:
        try:
            f = bm.faces.new([bm.verts.new(TO_BLENDER @ c) for c in corners])
        except ValueError:
            continue
        f.normal_update()
        if f.normal.dot(TO_BLENDER @ normal) < 0:
            f.normal_flip()
        mat = material(side, colour, mask, plain, look)
        if mat.name not in slots:
            slots[mat.name] = len(mats)
            mats.append(mat)
        f.material_index = slots[mat.name]
        n = Vector((abs(normal.x), abs(normal.y), abs(normal.z)))
        for loop in f.loops:
            g = TO_BLENDER.inverted() @ loop.vert.co
            loop[uv].uv = (g.x, g.z) if n.y >= n.x and n.y >= n.z else (g.x, g.y) if n.z > n.x else (g.z, g.y)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for mat in mats:
        me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build(models, name, side, at=(0, 0, 0), turn=0.0, aim=0.0, scale=1.0, plain=False):
    """Puts a unit into the scene: `at` in Blender's space, turned `turn` radians (0 faces -Y, the
    camera's side in these scenes), its turret `aim` radians further."""
    body = _begin()
    top, top_at = models[name](body)
    xf = Matrix.Translation(at) @ Matrix.Rotation(turn, 4, "Z") @ Matrix.Scale(scale, 4)
    _object(name, body, side, plain).matrix_world = xf
    if top:
        ob = _object(name + "_top", top, side, plain)
        ob.matrix_world = xf @ Matrix.Translation(TO_BLENDER @ top_at.m()) @ Matrix.Rotation(aim, 4, "Z")


# --- Scenes ----------------------------------------------------------------------------------------


def stage(cam, target, lens, size=(1600, 900), sun=(52, 0, 28)):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.view_settings.view_transform = "Filmic"  # the battle view's tone mapping
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.36, 0.44, 0.55, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    bpy.ops.object.light_add(type="SUN", rotation=tuple(math.radians(a) for a in sun))
    bpy.context.object.data.energy = 3.2
    bpy.ops.mesh.primitive_plane_add(size=4000, location=(0, 0, -0.02))
    bpy.context.object.data.materials.append(kit.mat("ground", "#3d4039", metal=0, rough=0.95))
    bpy.ops.object.camera_add(location=cam)
    c = bpy.context.object
    t = bpy.data.objects.new("target", None)
    t.location = target
    scene.collection.objects.link(t)
    k = c.constraints.new("TRACK_TO")
    k.target = t
    k.track_axis = "TRACK_NEGATIVE_Z"
    k.up_axis = "UP_Y"
    c.data.lens = lens
    c.data.clip_end = 5000
    scene.camera = c


def shoot(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(path)


def army(out, M, side):
    """The mobile units: the ground line in front, the commander behind it, the aircraft over the back."""
    kit.reset()
    row = [("scout", -17.5, 0.5), ("engineer", -11.5, 0.45), ("striker", -5.5, 0.4), ("tank", 2.5, 0.4), ("artillery", 11.5, 0.35), ("aa", 19.0, 0.3)]
    for name, x, turn in row:
        build(M, name, side, at=(x, 0, 0), turn=turn, aim=-0.25 if name == "tank" else 0.0)
    build(M, "acu", side, at=(-1.0, 12, 0), turn=0.35)
    build(M, "fighter", side, at=(-16, 15, 6.5), turn=0.5)
    build(M, "gunship", side, at=(13, 15, 6.0), turn=0.3)
    build(M, "bomber", side, at=(28, 24, 9.0), turn=0.4)
    stage((-8, -45, 16), (1.5, 5, 3.0), 38)
    shoot(os.path.join(out, f"battle_{side}_army.png"))


def base(out, M, side):
    """The structures, small ones in front."""
    kit.reset()
    for name, x, y in [("factory", -34, 22), ("node", 0, 30), ("airfactory", 36, 22), ("outpost", -42, -6),
                       ("turret", -24, -10), ("aaturret", -11, -12), ("shield", 0, -10), ("extractor", 13, -10),
                       ("generator", 27, -10), ("massstorage", 40, -12), ("energystorage", 51, -8), ("pod", -32, -22)]:
        build(M, name, side, at=(x, y, 0), turn=0.35 if name in ("turret", "aaturret") else 0.0, aim=-0.3)
    stage((-36, -98, 46), (2, 4, 6.5), 33)
    shoot(os.path.join(out, f"battle_{side}_base.png"))


def tanks(out, M, sides):
    """The same tank in every side's textures."""
    kit.reset()
    for i, side in enumerate(sides):
        build(M, "tank", side, at=((i - (len(sides) - 1) / 2) * 9.0, 0, 0), turn=0.55, aim=-0.2)
    stage((-5, -42, 11), (0.4, 0, 1.4), 40, size=(2000, 760))
    shoot(os.path.join(out, "battle_tanks.png"))


def before(out, M, side):
    """One side's tank as it was, plain paint, beside the same tank textured."""
    kit.reset()
    build(M, "tank", side, at=(-5.2, 0, 0), turn=0.55, aim=-0.2, plain=True)
    build(M, "tank", side, at=(5.2, 0, 0), turn=0.55, aim=-0.2)
    stage((-5, -28, 9.5), (0.6, 0, 1.5), 46)
    shoot(os.path.join(out, f"battle_{side}_before.png"))


def clash(out, M, a, d):
    """Two sides' lines meeting: `a` from the left, `d` from the right."""
    kit.reset()
    for side, sx in ((a, -1), (d, 1)):
        for name, x, y, z in [("tank", 8, -4, 0), ("tank", 11.5, 6, 0), ("striker", 6.5, 1.5, 0), ("aa", 19, -7, 0),
                              ("artillery", 22, 4, 0), ("gunship", 15, 14, 8), ("fighter", 8, 22, 11)]:
            build(M, name, side, at=(sx * x, y + sx * 1.5, z), turn=-sx * (math.pi / 2 - 0.1), aim=-sx * 0.1)
    stage((-14, -52, 20), (0, 3, 2.5), 36)
    shoot(os.path.join(out, f"battle_clash_{a}_{d}.png"))


SAMPLES = 40
SCENES = ["army", "base", "tanks", "before", "clash"]


def main(argv):
    global SAMPLES
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    out = args[0]
    words = args[1:]
    for w in words:
        if w.startswith("samples="):
            SAMPLES = int(w[8:])
    sides = [w for w in words if w in SIDES] or ["compact", "ashen", "luminar", "coma"]
    what = [w for w in words if w in SCENES] or SCENES
    os.makedirs(out, exist_ok=True)
    M = load_models()
    for w in what:
        if w == "tanks":
            tanks(out, M, sides)
        elif w == "clash":
            for i in range(0, len(sides) - 1, 2):
                clash(out, M, sides[i], sides[i + 1])
        elif w == "before":
            before(out, M, sides[0])
        else:
            for side in sides:
                globals()[w](out, M, side)


if __name__ == "__main__":
    main(sys.argv)
