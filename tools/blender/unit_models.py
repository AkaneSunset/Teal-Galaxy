"""The sector battle units that have a model of their own: one faction's unit at one tier, modelled
here part by part, exported to game/battle/models/<faction>/<type>.glb and rendered.

    python tools/blender/unit_models.py OUT_DIR [export] [render] [ashen/artillery_t3 ...] [view=side ...] [samples=N]

A unit without one of these keeps the shared model of its type (battle_models.gd), drawn bigger
for its tier. One with a file here is drawn from it at its own size, wearing the textures listed
for "<faction>/<type>" under "battle" in game/textures/surfaces.json.

The models are built in the game's space (Y up, front +Z, metres, origin on the ground) from flat
faces, each with a colour and a paint mask, exactly as battle_models.gd builds the shared ones, so
the same shader draws both: PLAIN parts keep their colour and wear the frame set, PAINT parts take
the side's colour and wear the hull set, SIDE_GLOW parts glow in the side's colour, GLOW parts in
their own. The .glb holds a "body" mesh, a "top" mesh (the turret, its origin where it turns) and a
"muzzle" point under the top; colours and masks are in the vertex colours (alpha is the mask).
"""

import importlib
import math
import os
import sys

import bpy  # noqa: F401
import bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import battle_models as bm  # noqa: E402
import kit  # noqa: E402

PLAIN, GLOW, SIDE_GLOW, PAINT = bm.PLAIN, bm.GLOW, bm.SIDE_GLOW, bm.PAINT
Color = bm.Color
MODELS = os.path.join(kit.ROOT, "game", "battle", "models")

UNITS = ["ashen/artillery_t3", "ashen/tank_t3", "ashen/acu"]  # each is tools/blender/units/<faction>_<type>.py


# --- Shapes: lists of faces (corners, normal, colour, mask) in the game's space ---------------------


class Part(list):
    """The faces of a body or a turret."""

    def poly(self, corners, colour, mask=PLAIN, out=None):
        """A flat face. `out` is a point it faces away from (its solid's middle)."""
        corners = [Vector(c) for c in corners]
        n = Vector((0, 0, 0))
        for i in range(len(corners)):  # Newell: right for any flat polygon, convex or not
            a, b = corners[i], corners[(i + 1) % len(corners)]
            n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
        if n.length < 1e-9:
            return
        n.normalize()
        if out is not None:
            mid = sum(corners, Vector()) / len(corners)
            if n.dot(mid - Vector(out)) < 0:
                n = -n
                corners.reverse()
        self.append((corners, n, colour, mask))

    def hexa(self, lo, hi, colour, mask=PLAIN):
        """A solid between two four-cornered faces (lo[i] under hi[i])."""
        lo, hi = [Vector(p) for p in lo], [Vector(p) for p in hi]
        mid = sum(lo + hi, Vector()) / 8
        self.poly(lo, colour, mask, mid)
        self.poly(hi, colour, mask, mid)
        for i in range(4):
            j = (i + 1) % 4
            self.poly([lo[i], lo[j], hi[j], hi[i]], colour, mask, mid)

    def slab(self, y0, r0, y1, r1, colour, mask=PLAIN):
        """A block from the rectangle r0 = (x0, x1, z0, z1) at height y0 to r1 at y1: sloped sides
        where the two differ."""
        def ring(y, r):
            return [(r[0], y, r[2]), (r[1], y, r[2]), (r[1], y, r[3]), (r[0], y, r[3])]
        self.hexa(ring(y0, r0), ring(y1, r1), colour, mask)

    def box(self, size, at, colour, mask=PLAIN, rot=(0, 0, 0)):
        """A box of `size` centred on `at`, turned `rot` (degrees about X, then Y, then Z)."""
        m = Matrix.Rotation(math.radians(rot[2]), 3, "Z") @ Matrix.Rotation(math.radians(rot[1]), 3, "Y") @ Matrix.Rotation(math.radians(rot[0]), 3, "X")
        h = Vector(size) * 0.5
        at = Vector(at)

        def p(x, y, z):
            return at + m @ Vector((x * h.x, y * h.y, z * h.z))
        self.hexa([p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1)], [p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1)], colour, mask)

    def extrude(self, profile, x0, x1, colour, mask=PLAIN, profile1=None, caps=True):
        """A side profile [(z, y), ...] pulled across from x0 to x1 (to `profile1` at x1, if given)."""
        a = [Vector((x0, y, z)) for z, y in profile]
        b = [Vector((x1, y, z)) for z, y in (profile1 or profile)]
        mid = (sum(a, Vector()) + sum(b, Vector())) / (len(a) * 2)
        area = sum(profile[i][0] * profile[(i + 1) % len(profile)][1] - profile[(i + 1) % len(profile)][0] * profile[i][1] for i in range(len(profile)))
        for i in range(len(a)):
            j = (i + 1) % len(a)
            quad = [a[i], a[j], b[j], b[i]]
            if (area > 0) == (x1 > x0):
                quad.reverse()
            if profile1:  # the two ends differ, so the side isn't flat: two triangles, each with its own facing
                self.poly(quad[:3], colour, mask)
                self.poly([quad[0], quad[2], quad[3]], colour, mask)
            else:
                self.poly(quad, colour, mask)
        if caps:
            self.poly(a, colour, mask, mid)
            self.poly(b, colour, mask, mid)

    def lathe(self, at, along, steps, colour, mask=PLAIN, sides=8, turn=0.0, caps=True, squash=1.0):
        """A turned shape along the direction `along` from `at`: steps = [(distance, radius), ...]."""
        at, w = Vector(at), Vector(along).normalized()
        u = w.cross(Vector((1, 0, 0)))
        u = (u if u.length > 1e-6 else w.cross(Vector((0, 1, 0)))).normalized()
        v = w.cross(u)

        def ring(d, r):
            return [at + w * d + (u * math.cos(turn + math.tau * k / sides) * squash + v * math.sin(turn + math.tau * k / sides)) * r for k in range(sides)]
        rings = [ring(d, r) for d, r in steps]
        for r0, r1, s0, s1 in zip(rings, rings[1:], steps, steps[1:]):
            mid = at + w * (s0[0] + s1[0]) / 2
            for k in range(sides):
                j = (k + 1) % sides
                self.poly([r0[k], r0[j], r1[j], r1[k]], colour, mask, mid)
        if caps:
            self.poly(rings[0], colour, mask, at + w * (steps[0][0] + 1))
            self.poly(rings[-1], colour, mask, at + w * (steps[-1][0] - 1))

    def wheel(self, r, x0, x1, z, y, colour, mask=PLAIN, sides=10):
        """A wheel on an axle across the hull."""
        self.lathe((x0, y, z), (1, 0, 0), [(0, r), (x1 - x0, r)], colour, mask, sides)

    def track(self, loop, x0, x1, band, cleat, every=0.42):
        """A track: the side profile `loop` [(z, y), ...] pulled across from x0 to x1, cleats all
        the way round it."""
        self.extrude(loop, x0, x1, band)
        zc = sum(p[0] for p in loop) / len(loop)
        yc = sum(p[1] for p in loop) / len(loop)
        for i in range(len(loop)):
            (z0, y0), (z1, y1) = loop[i], loop[(i + 1) % len(loop)]
            run = math.hypot(z1 - z0, y1 - y0)
            tilt = math.degrees(math.atan2(-(y1 - y0), z1 - z0))
            out = ((y0 - y1) / run, (z1 - z0) / run)  # (z, y) away from the loop's inside
            if out[0] * ((z0 + z1) / 2 - zc) + out[1] * ((y0 + y1) / 2 - yc) < 0:
                out = (-out[0], -out[1])
            n = max(1, round(run / every))
            for k in range(n):
                t = (k + 0.5) / n
                self.box((x1 - x0 + 0.06, 0.1, every * 0.48), ((x0 + x1) / 2, y0 + (y1 - y0) * t + out[1] * 0.03, z0 + (z1 - z0) * t + out[0] * 0.03), cleat, PLAIN, (tilt, 0, 0))

    def line(self, points, x, colour, mask=SIDE_GLOW, wide=0.1, proud=0.06):
        """A lit line on a side wall at `x`, through the points [(z, y), ...]."""
        for (z0, y0), (z1, y1) in zip(points, points[1:]):
            run = math.hypot(z1 - z0, y1 - y0)
            tilt = math.degrees(math.atan2(-(y1 - y0), z1 - z0))
            self.box((proud, wide, run + wide * 0.6), (x, (y0 + y1) / 2, (z0 + z1) / 2), colour, mask, (tilt, 0, 0))

    def prism(self, points, offset, colour, mask=PLAIN):
        """A flat plate of any outline: the polygon `points` (in one plane) pulled by `offset`."""
        pts = [Vector(p) for p in points]
        off = Vector(offset)
        n = Vector((0, 0, 0))
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
        n.normalize()
        mid = sum(pts, Vector()) / len(pts) + off / 2
        self.poly(pts, colour, mask, mid)
        self.poly([p + off for p in pts], colour, mask, mid)
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            self.poly([a, b, b + off, a + off], colour, mask, (a + b) / 2 + off / 2 - (b - a).cross(n))

    def beam(self, a, b, wide, deep, colour, mask=SIDE_GLOW, face=(0, 0, 1)):
        """A bar from a to b, `wide` across and `deep` along `face` (the way its lit side looks)."""
        a, b = Vector(a), Vector(b)
        w = (b - a).normalized()
        u = w.cross(Vector(face)).normalized() * wide / 2
        v = u.cross(w).normalized() * deep / 2
        self.hexa([a - u - v, a + u - v, a + u + v, a - u + v], [b - u - v, b + u - v, b + u + v, b - u + v], colour, mask)

    def mirrored(self, other):
        """Adds `other` and its mirror image across the hull's middle."""
        self.extend(other)
        for corners, n, colour, mask in other:
            self.append(([Vector((-c.x, c.y, c.z)) for c in reversed(corners)], Vector((-n.x, n.y, n.z)), colour, mask))


# --- Into Blender ---------------------------------------------------------------------------------


def load(unit):
    """{"body": Part, "top": Part or None, "top_at": (x, y, z), "muzzle": (x, y, z) from the top's pivot}."""
    mod = importlib.import_module("units." + unit.replace("/", "_"))
    return mod.build(Part)


def _mesh(name, faces):
    """One mesh for the game: flat faces, colours and masks in the corner colours."""
    b = bmesh.new()
    col = b.loops.layers.float_color.new("Col")
    for corners, normal, colour, mask in faces:
        try:
            f = b.faces.new([b.verts.new(bm.TO_BLENDER @ c) for c in corners])
        except ValueError:
            continue
        f.normal_update()
        if f.normal.dot(bm.TO_BLENDER @ normal) < 0:
            f.normal_flip()
        rgba = tuple(bm._linear(c) for c in (colour.r, colour.g, colour.b)) + (mask,)
        for loop in f.loops:
            loop[col] = rgba
    bmesh.ops.triangulate(b, faces=b.faces[:])
    me = bpy.data.meshes.new(name)
    b.to_mesh(me)
    b.free()
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = 0
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def export(unit):
    kit.reset()
    m = load(unit)
    body = _mesh("body", m["body"])
    tris = len(body.data.polygons)
    if m.get("top"):
        top = _mesh("top", m["top"])
        tris += len(top.data.polygons)
        top.parent = body
        top.location = bm.TO_BLENDER @ Vector(m["top_at"])
        muzzle = bpy.data.objects.new("muzzle", None)
        bpy.context.scene.collection.objects.link(muzzle)
        muzzle.parent = top
        muzzle.location = bm.TO_BLENDER @ Vector(m["muzzle"])
    path = os.path.join(MODELS, unit + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=False,
                              export_materials="NONE", export_vertex_color="ACTIVE", export_all_vertex_colors=True,
                              export_active_vertex_color_when_no_material=True, export_normals=True,
                              export_texcoords=False, export_animations=False)
    print(f"{path}: {tris} triangles")


def place(unit, side, at=(0, 0, 0), turn=0.0, aim=0.0, look=None):
    """Puts a unit into a render's scene, textured as the game's shader would (see battle_models.build)."""
    m = load(unit)
    look = look or unit
    xf = Matrix.Translation(at) @ Matrix.Rotation(turn, 4, "Z")
    bm._object(unit, m["body"], side, False, look).matrix_world = xf
    if m.get("top"):
        ob = bm._object(unit + "_top", m["top"], side, False, look)
        ob.matrix_world = xf @ Matrix.Translation(bm.TO_BLENDER @ Vector(m["top_at"])) @ Matrix.Rotation(aim, 4, "Z")


def render(out, unit, shared):
    """A sheet's worth of pictures of one unit: three quarters front and rear, side, front, top, as
    the battle's camera sees it, and beside the shared model it replaces."""
    side = unit.split("/")[0]
    name = unit.replace("/", "_")
    views = {
        "front": ((-13, -17, 8.5), (0.8, -1, 2.4), 50, 0.0),
        "rear": ((12, 17, 8.0), (0, 0, 2.2), 50, 0.0),
        "side": ((-30, -2, 3.2), (0, -2, 2.6), 70, 0.0, (40, 0, -60)),
        "head_on": ((0, -32, 3.5), (0, 0, 2.8), 75, 0.0),
        "top": ((0, -1.6, 44), (0, -1.5, 0), 62, math.pi / 2, (30, 0, 200)),
    }
    k = load(unit).get("view", 1.0)  # how much further back to stand for a bigger unit
    views.update(load(unit).get("views", {}))  # a tall unit's own cameras
    only = [w[5:] for w in sys.argv if w.startswith("view=")]
    for view, (cam, target, lens, turn, *sun) in views.items():
        if only and view not in only:
            continue
        cam, target = tuple(c * k for c in cam), tuple(c * k for c in target)
        kit.reset()
        place(unit, side, turn=turn)
        bm.stage(cam, target, lens, sun=sun[0] if sun else (52, 0, 28))  # a sun that doesn't glint off a facet into this camera
        bm.shoot(os.path.join(out, f"{name}_{view}.png"))
    if only and "in_battle" not in only:
        return
    # In a battle: from the battle camera's height, among the shared models it fights beside.
    kit.reset()
    base, _, tier = unit.split("/")[1].partition("_t")
    scale = 1.25 ** (int(tier or 1) - 1)
    place(unit, side, at=(-7, 0, 0), turn=0.5, aim=-0.2)
    bm.build(shared, base, side, at=(7, 0, 0), turn=0.5, aim=-0.2, scale=scale)
    bm.build(shared, "tank", side, at=(19, 4, 0), turn=0.5, aim=-0.2)
    bm.build(shared, "striker", side, at=(-19, 5, 0), turn=0.5)
    bm.stage((-10, -52, 44), (0, 0, 1.5), 60)
    bm.shoot(os.path.join(out, f"{name}_in_battle.png"))


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    out = args[0]
    words = args[1:]
    for w in words:
        if w.startswith("samples="):
            bm.SAMPLES = int(w[8:])
    units = [w for w in words if w in UNITS] or UNITS
    what = [w for w in words if w in ("export", "render")] or ["export", "render"]
    os.makedirs(out, exist_ok=True)
    for unit in units:
        if "export" in what:
            export(unit)
        if "render" in what:
            render(out, unit, bm.load_models())


if __name__ == "__main__":
    main(sys.argv)
