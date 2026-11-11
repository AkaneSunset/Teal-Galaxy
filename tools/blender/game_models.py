"""Pictures of the models the game builds in code (game/models.gd and game/base_models.gd: the ships,
the Builder's base buildings) wearing their textures, rendered in Blender.

    python tools/blender/game_models.py OUT_DIR [ships] [base] [close]

Those models exist only as GDScript, so this reads the two scripts, turns their model functions
into Python (they use a small, regular part of the language: blocks, drums, balls, loops), builds
each in Blender with the same parts and materials, and dresses it with kit.texture_scene("models").
It is a look at the models, not an exporter: the game still builds them itself.
"""

import math
import os
import re
import sys

import bpy  # noqa: F401  (first: it makes bmesh importable outside Blender)
import bmesh
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402

GAME = os.path.join(kit.ROOT, "game")

# --- A little of Godot, in Python ------------------------------------------------------------------


class V:
    """Vector3."""

    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)

    def __add__(self, o):
        return V(self.x + o.x, self.y + o.y, self.z + o.z)

    def __sub__(self, o):
        return V(self.x - o.x, self.y - o.y, self.z - o.z)

    def __mul__(self, k):
        if isinstance(k, V):
            return V(self.x * k.x, self.y * k.y, self.z * k.z)
        return V(self.x * k, self.y * k, self.z * k)

    __rmul__ = __mul__

    def __truediv__(self, k):
        return V(self.x / k, self.y / k, self.z / k)

    def __neg__(self):
        return V(-self.x, -self.y, -self.z)

    def t(self):
        return (self.x, self.y, self.z)


V.ZERO = V()
V.ONE = V(1, 1, 1)


class Color:
    def __init__(self, r, g, b, a=1.0):
        if isinstance(r, Color):
            r, g, b, a = r.r, r.g, r.b, g
        self.r, self.g, self.b, self.a = r, g, b, a

    def lerp(self, o, t):
        return Color(self.r + (o.r - self.r) * t, self.g + (o.g - self.g) * t, self.b + (o.b - self.b) * t)

    def lightened(self, t):
        return Color(self.r + (1 - self.r) * t, self.g + (1 - self.g) * t, self.b + (1 - self.b) * t)

    def to_html(self, _alpha=False):
        return "".join(f"{round(c * 255):02x}" for c in (self.r, self.g, self.b))


class Node3D:
    def __init__(self):
        self.children = []
        self.position = V()
        self.rotation_degrees = V()
        self.scale = V(1, 1, 1)
        self.name = ""
        self.material_override = None

    @staticmethod
    def new():
        return Node3D()

    def add_child(self, c):
        self.children.append(c)


class Part(Node3D):
    def __init__(self, shape, kind, **dims):
        super().__init__()
        self.shape, self.kind, self.dims = shape, kind, dims


TEAL = Color(0.36, 0.78, 0.78)
TEAL_LIGHT = Color(0.5, 0.88, 0.88)
NAVY = Color(0.13, 0.2, 0.42)
AMBER = Color(1.0, 0.58, 0.1)
STEEL = Color(0.5, 0.53, 0.58)

# models.gd's material kinds: colour (sRGB), metallic, roughness, glow, alpha
KINDS = {
    "teal": (TEAL, 0.0, 0.5, 0, 1),
    "teal_light": (TEAL_LIGHT, 0.0, 0.5, 0, 1),
    "navy": (NAVY, 0.0, 0.5, 0, 1),
    "steel": (STEEL, 0.5, 0.35, 0, 1),
    "amber": (AMBER, 0.0, 0.5, 0.7, 1),
    "glass": (Color(0.35, 0.95, 1.0), 0.0, 0.1, 0.15, 0.55),
    "ice": (Color(0.62, 0.92, 1.0), 0.0, 0.15, 0.15, 0.85),
    "deck": (Color(0.26, 0.28, 0.32), 0.0, 0.8, 0, 1),
    "dark": (Color(0.05, 0.06, 0.08), 0.0, 0.9, 0, 1),
    "window": (Color(0.55, 0.9, 1.0), 0.0, 0.5, 1.4, 1),
    "green": (Color(0.35, 0.8, 0.4), 0.0, 0.8, 0, 1),
}


def paint(colour, light=False):
    c = colour.lerp(STEEL, 0.35)
    return "paint:" + (c.lightened(0.25) if light else c).to_html()


def block(n, size, kind, pos=V.ZERO, bevel=-1.0, rot=V.ZERO):
    if bevel < 0:
        bevel = min(size.x, size.y, size.z) * 0.22
    return _part(n, Part("box", kind, size=size, bevel=bevel), pos, rot)


def drum(n, radius, height, kind, pos=V.ZERO, rot=V.ZERO, sides=16, top=-1.0):
    return _part(n, Part("drum", kind, r=radius, h=height, sides=sides, top=radius if top < 0 else top), pos, rot)


def ball(n, radius, kind, pos=V.ZERO, hemisphere=False):
    return _part(n, Part("ball", kind, r=radius, hemi=hemisphere), pos, V.ZERO)


def _part(n, p, pos, rot):
    p.position, p.rotation_degrees = pos, rot
    n.add_child(p)
    return p


def _b(n, size, kind, pos, bevel=-1.0, rot=V.ZERO):
    block(n, size, kind, pos, bevel, rot)


def _d(n, r, h, kind, pos, sides=16, top=-1.0, rot=V.ZERO):
    drum(n, r, h, kind, pos, rot, sides, top)


def _root(_name):
    return Node3D()


def _green():
    return "green"


HELPERS = {"material", "paint", "bevel_box", "_polygon", "part", "block", "drum", "ball", "_root", "make", "_b", "_d", "_green",
           "building", "_rock_mesh", "_surface_at", "ice_asteroid", "metal_asteroid", "boulder", "keycard"}


def transpile(path):
    """The model functions of a GDScript file, as Python source."""
    out = []
    keep = False
    for line in open(path).read().splitlines():
        m = re.match(r"static func (\w+)\((.*)\)( -> [\w\[\]]+)?:", line)
        if m:
            keep = m.group(1) not in HELPERS
            if keep:
                args = re.sub(r":\s*\w+\s*=", "=", m.group(2))
                args = re.sub(r":\s*=", "=", args)
                args = re.sub(r":\s*\w+", "", args)
                out.append(f"def {m.group(1)}({args}):")
            continue
        if not line.startswith("\t") and line.strip():
            keep = False
            continue
        if not keep:
            continue
        s = line.split(" #")[0].rstrip()
        if s.strip().startswith("#") or not s.strip():
            continue
        s = re.sub(r"\bvar (\w+)\s*(:\s*\w+\s*)?:?=", r"\1 =", s)
        s = re.sub(r"for (\w+) in (?!\[|range\()(.+):$", r"for \1 in range(int(\2)):", s)
        s = s.replace("Vector3(", "V(").replace("Vector3.", "V.").replace("Models.", "").replace("Node3D.new()", "Node3D()")
        s = s.replace("true", "True").replace("false", "False").replace("null", "None")
        s = re.sub(r"\(i / 3\)", "(i // 3)", s)
        s = s.replace(".to_pascal_case()", "")
        out.append(s.replace("\t", "    "))
    return "\n".join(out)


NS = {"V": V, "Color": Color, "Node3D": Node3D, "TAU": math.tau, "PI": math.pi, "cos": math.cos, "sin": math.sin,
      "maxi": max, "mini": min, "deg_to_rad": math.radians, "maxf": max, "minf": min, "clampf": lambda v, a, b: max(a, min(b, v)), "absf": abs,
      "SILVER": Color(0.86, 0.88, 0.92), "ROCK": Color(0.56, 0.63, 0.74), "TEAL": TEAL, "TEAL_LIGHT": TEAL_LIGHT, "NAVY": NAVY, "AMBER": AMBER, "STEEL": STEEL, "paint": paint,
      "block": block, "drum": drum, "ball": ball, "part": None, "_b": _b, "_d": _d, "_root": _root, "_green": _green}


def load_models():
    for f in ("models.gd", "base_models.gd"):
        src = transpile(os.path.join(GAME, f))
        for chunk in re.split(r"\n(?=def )", src):
            if not chunk.startswith("def "):
                continue
            try:
                exec(chunk, NS)
            except SyntaxError as err:  # a function using more of GDScript than this handles
                print("skipped", chunk.split("(")[0][4:], err.msg)
    return NS


# --- Building them in Blender ----------------------------------------------------------------------

GODOT_TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(kind):
    if kind in bpy.data.materials:
        return bpy.data.materials[kind]
    if kind.startswith("paint:"):
        h = kind[6:]
        col, metal, rough, glow, alpha = Color(*(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))), 0.25, 0.45, 0.22, 1
    else:
        col, metal, rough, glow, alpha = KINDS.get(kind, KINDS["teal"])
    m = bpy.data.materials.new(kind)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    rgb = tuple(_linear(c) for c in (col.r, col.g, col.b)) + (1.0,)
    b.inputs["Base Color"].default_value = rgb
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["Alpha"].default_value = alpha
    if glow:
        b.inputs["Emission Color"].default_value = rgb
        b.inputs["Emission Strength"].default_value = glow * 3
    return m


def _mesh(p):
    bm = bmesh.new()
    d = p.dims
    if p.shape == "box":
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=d["size"].t(), verts=bm.verts)
        if d["bevel"] > 0.001:
            bmesh.ops.bevel(bm, geom=bm.edges[:] + bm.verts[:], offset=min(d["bevel"], min(d["size"].t()) * 0.475), segments=1, affect="EDGES")
    elif p.shape == "drum":  # along Godot's Y, which is Blender's Z before the axis swap below
        bmesh.ops.create_cone(bm, cap_ends=True, segments=d["sides"], radius1=d["r"], radius2=d["top"], depth=d["h"])
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, "X"), verts=bm.verts)
    else:
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=d["r"])
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, "X"), verts=bm.verts)
        if d["hemi"]:
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0), plane_no=(0, 1, 0), clear_inner=True)
    me = bpy.data.meshes.new(p.shape)
    bm.to_mesh(me)
    bm.free()
    return me


def _godot_xf(n):
    r = n.rotation_degrees
    rot = Euler((math.radians(r.x), math.radians(r.y), math.radians(r.z)), "YXZ").to_matrix().to_4x4()
    s = Matrix.Diagonal((n.scale.x, n.scale.y, n.scale.z, 1.0))
    return Matrix.Translation(n.position.t()) @ rot @ s


def build(node, at=(0, 0, 0), turn=0.0, parent_xf=None):
    """Puts a model into the scene, `at` a point in Blender space, turned `turn` radians about Z."""
    if parent_xf is None:
        parent_xf = Matrix.Translation(at) @ Matrix.Rotation(turn, 4, "Z") @ GODOT_TO_BLENDER
    xf = parent_xf @ _godot_xf(node)
    if isinstance(node, Part):
        ob = bpy.data.objects.new(node.shape, _mesh(node))
        kind = node.material_override or node.kind
        ob.data.materials.append(material(kind))
        ob.matrix_world = xf
        bpy.context.scene.collection.objects.link(ob)
    for c in node.children:
        build(c, parent_xf=xf)


# --- Scenes ----------------------------------------------------------------------------------------


def stage(cam, target, lens, size=(1600, 900), sun=(50, 0, 35), ground=True):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.render.resolution_x, scene.render.resolution_y = size
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.4, 0.52, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    bpy.ops.object.light_add(type="SUN", rotation=tuple(math.radians(a) for a in sun))
    bpy.context.object.data.energy = 3.2
    if ground:
        bpy.ops.mesh.primitive_plane_add(size=2000, location=(0, 0, -0.02))
        bpy.context.object.data.materials.append(kit.mat("ground", "#3a3f44", metal=0, rough=0.9))
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


def shoot(path, plain):
    """Renders the scene, textured, to `path`; with `plain`, also as it was, beside it."""
    scene = bpy.context.scene
    if plain:
        scene.render.filepath = path.replace(".png", "_plain.png")
        bpy.ops.render.render(write_still=True)
    kit.texture_scene("models")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(path)


def ships(out, M, plain):
    kit.reset()
    build(M["starter_ship"](), at=(0, 0, 2.85))
    stage((13, 15, 7), (0, 0.5, 2.4), 40)
    shoot(os.path.join(out, "starter_ship.png"), plain)
    kit.reset()
    build(M["fleet_carrier"](), at=(0, 0, 30))
    stage((250, 250, 130), (0, 0, 25), 38, ground=False)
    shoot(os.path.join(out, "fleet_carrier.png"), plain)
    kit.reset()  # the carrier's flight deck and island, close
    build(M["fleet_carrier"](), at=(0, 0, 30))
    stage((-35, 45, 78), (20, -12, 62), 30, ground=False)
    shoot(os.path.join(out, "fleet_carrier_island.png"), plain)


BASE = [("command_center_at", (5,)), ("warehouse", ()), ("power_plant", ()), ("carrier_dock", ()), ("ice_extractor", ()),
        ("spaceport", ()), ("hydroponics", ()), ("refinery", ()), ("research_outpost", ()), ("data_spire", ()),
        ("ship_foundry", ()), ("habitat_dome", ())]


def base(out, M, plain):
    kit.reset()
    cols = 4
    for i, (name, args) in enumerate(BASE):
        x, y = (i % cols - (cols - 1) / 2) * 24, (i // cols - 1) * 24
        build(M["node_plate"](20.0), at=(x, y, 0))
        build(M[name](*args), at=(x, y, 1.0), turn=math.pi)
    stage((70, -120, 70), (0, 4, 2), 36)
    shoot(os.path.join(out, "base_buildings.png"), plain)


def close(out, M, plain):
    kit.reset()
    build(M["command_center_at"](5), at=(0, 0, 0), turn=math.pi)
    build(M["warehouse"](), at=(20, 4, 0), turn=math.pi)
    build(M["wall"](30.0), at=(5, 22, 0))
    build(M["wall_tower"](), at=(-14, 22, 0))
    stage((24, -26, 13), (4, 4, 6), 32)
    shoot(os.path.join(out, "base_close.png"), plain)


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    out = args[0]
    what = args[1:] or ["ships", "base", "close"]
    plain = "plain" in what
    os.makedirs(out, exist_ok=True)
    M = load_models()
    for w in what:
        if w in ("ships", "base", "close"):
            globals()[w](out, M, plain)


if __name__ == "__main__":
    main(sys.argv)
