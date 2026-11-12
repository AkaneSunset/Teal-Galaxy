"""A holographic map terminal: a projector on a dais throwing a wireframe map of an orbital ring
station into the air, in a dark vaulted chamber with reflecting pools, rendered in Blender.

    python tools/blender/map_terminal.py OUT_DIR [samples=N] [glb]

The map is built from data, not drawn: STATION lists the station's sections (each a run of rooms
around the ring), the rooms are wireframe boxes, the corridors between them glowing lines, the
lift shaft through the middle a beam of light, and the markers small discs (red for "you are
here"). The chamber's floor and walls wear the game's own deck and trim textures
(kit.texture_scene("place")). With `glb`, the terminal and its hologram are also exported to
OUT_DIR/map_terminal.glb (projector, consoles and hologram as separate meshes, the hologram's
materials glowing), for a look in the game later.
"""

import math
import os
import random
import sys

import bpy  # noqa: F401  (first: it makes bmesh importable outside Blender)
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import kit  # noqa: E402

HOLO = (0.08, 0.8, 1.0)
AMBER = (1.0, 0.62, 0.18)
CENTRE = Vector((0.0, 0.0, 4.25))  # the hologram's middle
RING_R = 2.3
TILT = math.radians(14)  # the ring leans back a little, so its far side reads

# The station: (section, rooms in it, room size range in metres of hologram) around the ring.
STATION = [("docks", 3, (0.42, 0.62)), ("hab", 4, (0.32, 0.46)), ("lab", 2, (0.4, 0.55)),
           ("reactor", 3, (0.45, 0.62)), ("hangar", 2, (0.5, 0.66)), ("stores", 3, (0.32, 0.45))]
GAPS = {"lab", "hangar"}  # sections with a broken corridor after them, so the ring reads as rooms, not a tyre


def srgb(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def hexc(h):
    return srgb(tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)))


# --- Materials ----------------------------------------------------------------------------------


def _nodes(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    return m, nt, out


def glow(name, colour, strength, alpha=1.0):
    """Pure light: `alpha` below 1 lets the rest through (the hologram's room fills)."""
    m, nt, out = _nodes(name)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = colour + (1,)
    em.inputs["Strength"].default_value = strength
    if alpha >= 1.0:
        nt.links.new(em.outputs[0], out.inputs["Surface"])
    else:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.inputs["Fac"].default_value = alpha
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
    m.blend_method = "BLEND" if alpha < 1.0 else "OPAQUE"
    return m


def surface(name, colour, rough=0.5, metal=0.3):
    m = kit.mat(name, "#000000", metal=metal, rough=rough)
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = colour + (1,)
    return m


def water():
    m = surface("pool", hexc("#04070a"), rough=0.03, metal=0.0)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["IOR"].default_value = 1.33
    b.inputs["Specular IOR Level"].default_value = 0.9
    return m


def data_wall(name, a, b, scale, stretch, cut, strength):
    """Streams of lit data: noise stretched along the wall, cut down to sparse dashes of two colours."""
    m, nt, out = _nodes(name)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = stretch
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 1.0
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].position = cut
    ramp.color_ramp.elements[1].color = a + (1,)
    e = ramp.color_ramp.elements.new(cut + (1 - cut) * 0.55)
    e.color = b + (1,)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    base = nt.nodes.new("ShaderNodeBsdfPrincipled")
    base.inputs["Base Color"].default_value = hexc("#0b0f18") + (1,)
    base.inputs["Roughness"].default_value = 0.35
    nt.links.new(ramp.outputs["Color"], base.inputs["Emission Color"])
    base.inputs["Emission Strength"].default_value = strength
    nt.links.new(base.outputs[0], out.inputs["Surface"])
    return m


def schematic(name, colour, strength):
    """A console screen: a grid of lit cells and lines (Voronoi edges and bricks)."""
    m, nt, out = _nodes(name)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 2.5
    brick.inputs["Mortar Size"].default_value = 0.04
    brick.inputs["Color1"].default_value = (0.05, 0.12, 0.15, 1)
    brick.inputs["Color2"].default_value = (0.25, 0.6, 0.7, 1)
    brick.inputs["Mortar"].default_value = colour + (1,)
    nt.links.new(coord.outputs["Object"], brick.inputs["Vector"])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength
    nt.links.new(brick.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


# --- Shapes -------------------------------------------------------------------------------------


def _obj(name, bm, m, at=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = at
    bpy.context.scene.collection.objects.link(ob)
    return ob


def prism(name, r, z0, z1, m, sides=8, r1=None, turn=math.pi / 8, at=(0, 0), caps=True):
    """An upright prism (or frustum to `r1`), from z0 to z1, its corners turned by `turn`; open
    at both ends without `caps`."""
    bm = bmesh.new()
    r1 = r if r1 is None else r1
    lo = [bm.verts.new((at[0] + r * math.cos(turn + k * math.tau / sides), at[1] + r * math.sin(turn + k * math.tau / sides), z0)) for k in range(sides)]
    hi = [bm.verts.new((at[0] + r1 * math.cos(turn + k * math.tau / sides), at[1] + r1 * math.sin(turn + k * math.tau / sides), z1)) for k in range(sides)]
    for k in range(sides):
        bm.faces.new((lo[k], lo[(k + 1) % sides], hi[(k + 1) % sides], hi[k]))
    if caps:
        bm.faces.new(list(reversed(lo)))
        bm.faces.new(hi)
    return _obj(name, bm, m)


def block(name, size, at, m, turn=0.0, bevel=0.0):
    """A box `size`, its bottom centre at `at`, turned `turn` about Z."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0, 0, size[2] / 2), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect="EDGES")
    ob = _obj(name, bm, m, at)
    ob.rotation_euler.z = turn
    return ob


def tube(name, points, r, m, sides=6):
    """A thin tube through `points` (a glowing line)."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(points):
        d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        u = d.orthogonal().normalized()
        v = d.cross(u)
        rings.append([bm.verts.new(p + (u * math.cos(a) + v * math.sin(a)) * r) for a in (k * math.tau / sides for k in range(sides))])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    return _obj(name, bm, m)


# --- The hologram -------------------------------------------------------------------------------


def ring_point(a, r=RING_R, off=0.0):
    """A point on the tilted ring (it stands up, facing -Y, leaning back by TILT), `a` radians round."""
    p = Vector((math.cos(a) * r, off, math.sin(a) * r))
    return CENTRE + Matrix.Rotation(TILT, 3, "X") @ p


def hologram(rng, wire, fill, path, beam, marks):
    """The station map. Returns the objects, for the export."""
    obs = []
    count = sum(n for _, n, _ in STATION)
    gap = 0.22  # radians left empty after a section with a broken corridor
    span = (math.tau - gap * len(GAPS)) / count
    a = math.pi / 2 + 0.12
    ends = []  # (angle, section) for each room, in order
    for name, n, (lo, hi) in STATION:
        for i in range(n):
            s = rng.uniform(lo, hi) * 1.25
            size = Vector((s * rng.uniform(0.9, 1.35), s * rng.uniform(0.7, 1.1), s * rng.uniform(0.75, 1.0)))
            at = ring_point(a, RING_R + rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12))
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)  # the floor plan's walls
            bmesh.ops.scale(bm, vec=size, verts=bm.verts)
            xf = Matrix.Rotation(TILT, 4, "X") @ Matrix.Rotation(-a + rng.uniform(-0.35, 0.35), 4, "Y") @ Matrix.Rotation(rng.uniform(-0.75, 0.75), 4, "Z") @ Matrix.Rotation(rng.uniform(-0.55, 0.55), 4, "X")
            bmesh.ops.transform(bm, matrix=xf, verts=bm.verts)
            shell = bm.copy()
            ob = _obj(f"room_{name}_{i}", bm, wire, at)
            mod = ob.modifiers.new("wire", "WIREFRAME")
            mod.thickness = 0.016
            mod.use_even_offset = False
            obs.append(ob)
            obs.append(_obj(f"room_{name}_{i}_fill", shell, fill, at))
            ends.append((a, name, at))
            a -= span
        if name in GAPS:
            a -= gap
    # Corridors: along the ring between rooms, except across a gap; an amber route through some.
    for (a0, s0, p0), (a1, s1, p1) in zip(ends, ends[1:] + ends[:1]):
        if s0 != s1 and s0 in GAPS:
            continue
        sweep = (a0 - a1) % math.tau
        pts = [ring_point(a0 - sweep * t / 8, RING_R - 0.02) for t in range(9)]
        obs.append(tube("corridor", pts, 0.012, wire))
    route = [e for e in ends if e[1] in ("hab", "lab")] + [ends[-1]]
    for (a0, _, p0), (a1, _, p1) in zip(route, route[1:]):
        sweep = (a0 - a1) % math.tau
        if sweep > 1.5:
            continue
        pts = [ring_point(a0 - sweep * t / 10, RING_R + 0.05, -0.04) for t in range(11)]
        obs.append(tube("route", pts, 0.024, path))
    # The lift shaft: a beam from the top of the ring to the bottom, through the middle.
    top, bottom = ring_point(math.pi / 2, RING_R - 0.15), ring_point(-math.pi / 2, RING_R - 0.15)
    obs.append(tube("shaft", [top, bottom], 0.035, beam, sides=10))
    for t in (0.0, 1.0):
        obs.append(tube("shaft_cap", [top.lerp(bottom, t) + Vector((0, 0, 0.0)), top.lerp(bottom, t) + Vector((0, -0.01, 0))], 0.09, marks["red" if t == 0 else "teal"], sides=12))
    # Markers: small lit discs facing out of the map, off a few rooms. Red is "you are here".
    for k, (a0, name, p0) in enumerate(ends):
        if k % 3 != 1 and name != "hab":
            continue
        colour = "red" if (name == "hab" and k == 4) else ("green" if k % 2 else "teal")
        c = ring_point(a0, RING_R - 0.48 if k % 2 else RING_R + 0.45, -0.1)
        obs.append(disc(f"mark_{k}", c, 0.07, marks[colour]))
    return obs


def disc(name, at, r, m):
    bm = bmesh.new()
    ring = bmesh.ops.create_circle(bm, cap_ends=True, segments=16, radius=r)
    inner = bmesh.ops.create_circle(bm, cap_ends=False, segments=16, radius=r * 1.6)
    edges = [e for e in bm.edges if all(v in inner["verts"] for v in e.verts)]
    bmesh.ops.extrude_edge_only(bm, edges=edges)
    bmesh.ops.scale(bm, vec=(1.12, 1.12, 1), verts=[v for v in bm.verts if v not in ring["verts"] and v not in inner["verts"]])
    bmesh.ops.transform(bm, matrix=Matrix.Rotation(TILT, 4, "X") @ Matrix.Rotation(math.pi / 2, 4, "X"), verts=bm.verts)
    return _obj(name, bm, m, at)


# --- The terminal and the chamber ----------------------------------------------------------------


def terminal(M):
    obs = []
    obs.append(prism("dais_step", 4.4, -1.6, 0.22, M["floor"]))
    obs.append(prism("dais", 3.7, 0.22, 0.5, M["floor"]))
    edge = [Vector((3.74 * math.cos(math.pi / 8 + k * math.tau / 8), 3.74 * math.sin(math.pi / 8 + k * math.tau / 8), 0.47)) for k in range(9)]
    obs.append(tube("dais_trim", edge, 0.03, M["holo_dim"]))
    obs.append(prism("projector_base", 1.15, 0.5, 1.05, M["wall"], r1=0.95))
    obs.append(prism("projector_neck", 0.62, 1.05, 1.55, M["metal"], r1=0.48))
    obs.append(prism("projector_head", 0.48, 1.55, 1.75, M["metal"], r1=0.82))
    obs.append(prism("projector_lens", 0.66, 1.75, 1.79, M["lens"], sides=24))
    obs.append(prism("projector_lip", 0.86, 1.70, 1.80, M["metal"], sides=8, r1=0.86))
    for k in range(8):  # vanes holding the lens, lit at their tips
        a = math.pi / 8 + k * math.tau / 8
        obs.append(block("vane", (0.12, 0.42, 0.3), (math.cos(a) * 0.86, math.sin(a) * 0.86, 1.5), M["wall"], turn=a + math.pi / 2))
        obs.append(block("vane_light", (0.06, 0.06, 0.06), (math.cos(a) * 0.98, math.sin(a) * 0.98, 1.82), M["holo"]))
    for side in (-1, 1):  # two lecterns either side, angled toward the projector
        x, y, turn = side * 2.35, -1.25, side * math.radians(-35)
        obs.append(block("console", (1.1, 0.7, 1.0), (x, y, 0.5), M["wall"], turn=turn, bevel=0.04))
        top = block("console_top", (1.2, 0.85, 0.08), (x, y, 1.48), M["metal"], turn=turn)
        top.rotation_euler.x = math.radians(-24) if side else 0
        top.rotation_mode = "ZXY"
        top.rotation_euler = (math.radians(24), 0, turn)
        obs.append(top)
        screen = block("console_screen", (1.0, 0.62, 0.02), (x, y, 1.56), M["screen"], turn=turn)
        screen.rotation_mode = "ZXY"
        screen.rotation_euler = (math.radians(24), 0, turn)
        obs.append(screen)
    return obs


def chamber(M):
    R = 15.0  # the octagon's walls this far out (apothem)
    H = 17.0
    for k in range(8):
        a = k * math.tau / 8 - math.pi / 2  # wall 0 behind the camera
        w = 2 * R * math.tan(math.pi / 8) + 0.6
        c = Vector((math.cos(a) * (R + 0.4), math.sin(a) * (R + 0.4), -1.2))
        block("wall", (w, 0.8, H + 1.2), c, M["wall"], turn=a + math.pi / 2)
        if k in (0,):
            continue
        # Data panels: tall lit screens set into the wall, either side of a dark seam.
        for s in (-1, 1):
            p = Vector((math.cos(a) * (R - 0.05), math.sin(a) * (R - 0.05), 2.4)) + Vector((-math.sin(a), math.cos(a), 0)) * s * 2.7
            block("data", (4.6, 0.12, 11.5), p, M["data"], turn=a + math.pi / 2)
        for s in (-1, 1):
            p = Vector((math.cos(a) * (R - 0.25), math.sin(a) * (R - 0.25), 0.0)) + Vector((-math.sin(a), math.cos(a), 0)) * s * 5.6
            block("rib", (0.9, 0.7, H), p, M["wall"], turn=a + math.pi / 2, bevel=0.06)
            block("rib_light", (0.08, 0.1, 10.0), p + Vector((0, 0, 3.0)) - Vector((math.cos(a), math.sin(a), 0)) * 0.36, M["strip"], turn=a + math.pi / 2)
    # A doorway lit from the room beyond, back left, and a wall screen with the station's decks, right.
    a = math.radians(135)
    door = Vector((math.cos(a) * (R - 0.3), math.sin(a) * (R - 0.3), 0))
    block("door_frame", (3.4, 1.0, 4.6), door, M["metal"], turn=a + math.pi / 2)
    block("door_light", (2.6, 1.1, 3.8), door, M["doorway"], turn=a + math.pi / 2)
    a = math.radians(30)
    scr = Vector((math.cos(a) * (R - 0.35), math.sin(a) * (R - 0.35), 1.6))
    block("wall_screen_frame", (4.2, 0.4, 2.8), scr - Vector((0, 0, 0.2)), M["metal"], turn=a + math.pi / 2)
    block("wall_screen", (3.8, 0.45, 2.4), scr, M["screen"], turn=a + math.pi / 2)
    # Floor: a cross of walkways over dark pools, the dais in the middle.
    block("pool_bed", (2 * R + 2, 2 * R + 2, 0.2), (0, 0, -1.6), M["pool_bed"])
    pool = block("pool", (2 * R, 2 * R, 0.01), (0, 0, -0.45), M["pool"])
    pool.data.materials[0] = M["pool"]
    for w, d, at in ((3.4, 2 * R, (0, 0)), (2 * R, 3.0, (0, 0))):
        block("floor", (w, d, 1.6), (at[0], at[1], -1.6), M["floor"])
        for s in (-1, 1):  # lit edges along the walkway
            if w < d:
                block("edge", (0.05, d - 9, 0.04), (s * (w / 2 + 0.01), -(d / 4) - 2.2, -0.03), M["holo_dim"])
    # The roof: a dark vault with a ring of light round an opening.
    prism("roof", R + 1, H, H + 0.6, M["wall"], sides=8)
    prism("oculus", 3.0, H - 0.05, H, M["strip"], sides=32)
    prism("oculus_dark", 2.6, H - 0.06, H, M["wall"], sides=32)
    # Four buttresses lean in from the back corners and frame the terminal.
    for s in (-1, 1):
        for ox, oy, h in ((5.6, 7.5, 13.0),):
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=(1.5, 1.3, h), verts=bm.verts)
            bmesh.ops.translate(bm, vec=(0, 0, h / 2), verts=bm.verts)
            bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.2, segments=1, affect="EDGES")
            ob = _obj("buttress", bm, M["wall"], (s * ox, oy, -0.4))
            ob.rotation_euler = (math.radians(-6), s * math.radians(-9), 0)
            block("buttress_foot", (2.2, 2.0, 2.4), (s * ox, oy, -0.4), M["wall"], bevel=0.12)
            block("buttress_light", (0.06, 0.06, 7.0), (s * ox - s * 0.0, oy - 0.68, 2.5), M["strip"])


def lights():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("dark")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.004, 0.006, 0.012, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world

    def light(kind, at, energy, colour, size=1.0, rot=(0, 0, 0)):
        d = bpy.data.lights.new(kind, kind)
        d.energy = energy
        d.color = colour
        if kind == "AREA":
            d.size = size
        else:
            d.shadow_soft_size = size
        ob = bpy.data.objects.new(kind, d)
        ob.location = at
        ob.rotation_euler = rot
        scene.collection.objects.link(ob)

    light("POINT", CENTRE, 220, HOLO, 1.6)  # the hologram's own light
    light("POINT", (0, 0, 2.3), 18, HOLO, 0.4)  # off the lens
    light("AREA", (0, 0, 16.5), 900, (0.55, 0.65, 1.0), 6.0)  # the oculus
    light("AREA", (0, -9, 9), 160, (0.5, 0.6, 0.9), 8.0, (math.radians(30), 0, 0))  # fill on the walkway
    for s in (-1, 1):
        light("AREA", (s * 10, 4, 7), 260, (0.45, 0.35, 1.0), 6.0, (0, s * math.radians(-70), 0))  # the data walls' spill


def camera(at, look, lens):
    scene = bpy.context.scene
    d = bpy.data.cameras.new("eye")
    d.lens = lens
    d.clip_end = 300
    ob = bpy.data.objects.new("eye", d)
    ob.location = at
    v = Vector(look) - Vector(at)
    ob.rotation_euler = v.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(ob)
    scene.camera = ob


def bloom(path):
    """The glow the game's renderer would add: bright parts bled out at two sizes."""
    import numpy as np
    from PIL import Image, ImageFilter
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, dtype=np.float32) / 255
    bright = np.clip((a - 0.55) / 0.45, 0, 1) * a
    glow_ = np.zeros_like(a)
    src = Image.fromarray((bright * 255).astype(np.uint8))
    for radius, k in ((6, 0.55), (22, 0.45), (60, 0.35)):
        glow_ += np.asarray(src.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255 * k
    out = 1 - (1 - a) * (1 - np.clip(glow_, 0, 1))  # screen
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(path)


def build(samples):
    kit.reset()
    rng = random.Random("teal-galaxy/map-terminal")
    M = {
        "floor": surface("floor", hexc("#5c6a74"), rough=0.55, metal=0.2),
        "wall": surface("wall", hexc("#27313a"), rough=0.6, metal=0.3),
        "metal": surface("metal", hexc("#3a444d"), rough=0.35, metal=0.7),
        "pool_bed": surface("pool_bed", hexc("#05080a"), rough=0.9, metal=0.0),
        "pool": water(),
        "holo": glow("holo", HOLO, 4.0),
        "holo_dim": glow("holo_dim", HOLO, 1.5),
        "fill": glow("holo_fill", HOLO, 0.6, alpha=0.06),
        "path": glow("route", AMBER, 5.0),
        "beam": glow("shaft", (0.55, 0.65, 1.0), 14.0),
        "lens": glow("lens", HOLO, 6.0),
        "strip": glow("strip", (0.22, 0.35, 1.0), 4.0),
        "doorway": glow("doorway", (0.3, 0.45, 0.7), 0.35),
        "data": data_wall("data", (0.2, 0.1, 0.9), (0.35, 0.55, 1.0), 5.0, (1.0, 1.0, 16.0), 0.7, 1.6),
        "screen": schematic("screen", HOLO, 0.7),
    }
    marks = {c: glow("mark_" + c, v, 4.0) for c, v in (("red", (1.0, 0.18, 0.2)), ("green", (0.3, 1.0, 0.5)), ("teal", HOLO))}
    chamber(M)
    parts = terminal(M)
    holo = hologram(rng, M["holo"], M["fill"], M["path"], M["beam"], marks)
    kit.texture_scene("place")  # deck plate on the floor, trim plates on the walls, as the game's rooms
    lights()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.cycles.transparent_max_bounces = 24
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    return parts, holo


def shoot(path, size, at, look, lens):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    camera(at, look, lens)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bloom(path)
    print(path)


def export(out, parts, holo):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts + holo:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "map_terminal.glb"), use_selection=True, export_apply=True)


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    out = args[0]
    samples = next((int(a[8:]) for a in args if a.startswith("samples=")), 96)
    os.makedirs(out, exist_ok=True)
    parts, holo = build(samples)
    shoot(os.path.join(out, "map_terminal_chamber.png"), (1600, 1200), (0, -12.5, 1.75), (0, 0, 3.6), 22)
    shoot(os.path.join(out, "map_terminal_close.png"), (1600, 1200), (-5.8, -7.2, 2.6), (0, 0, 3.7), 26)
    if "glb" in args:
        export(out, parts, holo)


if __name__ == "__main__":
    main(sys.argv)
