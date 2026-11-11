"""Teal Galaxy arena maps: greybox blockouts built in Blender from the research doc's map concepts
("Arena Shooter Game Modes", section 10.4, table 14).

Run with Blender's Python (the `bpy` module, or `blender -b -P`):

    python3.11 tools/blender/arena_maps.py --out art/arena_maps            # all maps
    python3.11 tools/blender/arena_maps.py --out art/arena_maps --only ring --no-render

For each map it writes <id>.blend (the editable source), <id>.glb (for Godot: geometry plus every
marker, with its game data in glTF extras), <id>.json (the markers alone) and PNG previews.

Units are metres, Blender's Z up: x east, y north. A player stands about 1.8 m tall; doors are 3 m
or wider, walls 4 to 8 m. Godot reads the .glb as Y up: Godot (x, y, z) = Blender (x, z, -y).

Markers are objects whose custom property `kind` says what they are:
  spawn       team ("A", "B", "C", "attack", "defend", "players"), set (which spawn list)
  zone        id; a capture zone (Sector Hold, Strongholds, Domination)
  hill        order; a Hardpoint / King of the Hill spot, in rotation order
  flag        team; CTF flag stand
  ball        Oddball spawn
  charge      id; a Core Breach charge point
  core        the One Flag data core / vault core
  checkpoint  order; Boarding Action checkpoint
  path        order; a node on the breach charge's route
  pickup      item; a power weapon or power-up
  resupply    ammo and health refill
  drop_zone   where Coma bots land in Firefight
  lift        bottom and top heights
  jump_pad    to (where it throws you)
  nest        an Oddball nest
  cart, robot, hoop, power_core, node, vehicle_pad, ai_spawn, heavy_drop: the objects of
              Payload, Push, Bombing Run, Onslaught / Warfare and Attrition
"""

import json
import math
import os
import sys

import bpy  # noqa: E402  (bpy first: it makes bmesh importable)
import bmesh
from mathutils import Vector

# --- Arguments ----------------------------------------------------------------------------------

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]


def arg(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


OUT = os.path.abspath(arg("--out", "art/arena_maps"))
ONLY = arg("--only")
RENDER = "--no-render" not in argv
SAMPLES = int(arg("--samples", "24"))

# --- Scene helpers ------------------------------------------------------------------------------

MATS = {}
COLOURS = {
    "floor": ((0.16, 0.17, 0.19), 0),
    "floor2": ((0.22, 0.23, 0.25), 0),
    "wall": ((0.62, 0.64, 0.67), 0),
    "hull": ((0.42, 0.45, 0.50), 0),
    "cover": ((0.24, 0.47, 0.50), 0),
    "crate": ((0.55, 0.42, 0.24), 0),
    "ramp": ((0.36, 0.38, 0.42), 0),
    "glass": ((0.35, 0.75, 0.85), 1.5),
    "core": ((0.10, 0.85, 0.80), 6),
    "A": ((0.15, 0.40, 1.00), 1.5),
    "B": ((1.00, 0.20, 0.18), 1.5),
    "C": ((0.20, 0.85, 0.30), 1.5),
    "attack": ((0.15, 0.40, 1.00), 1.5),
    "defend": ((1.00, 0.20, 0.18), 1.5),
    "players": ((0.15, 0.40, 1.00), 1.5),
    "ffa": ((0.95, 0.95, 0.95), 1.5),
    "zone": ((1.00, 0.80, 0.10), 0.6),
    "hill": ((1.00, 0.45, 0.05), 0.6),
    "objective": ((1.00, 0.45, 0.05), 5),
    "pickup": ((0.75, 0.30, 1.00), 5),
    "resupply": ((0.30, 1.00, 0.45), 4),
    "coma": ((0.65, 0.10, 0.90), 3),
    "label": ((1.0, 1.0, 0.92), 2),
    "path": ((1.00, 0.65, 0.10), 3),
    "lift": ((0.95, 0.85, 0.20), 1.5),
}


def mat(key):
    if key in MATS:
        return MATS[key]
    colour, glow = COLOURS[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    bsdf.inputs["Roughness"].default_value = 0.7
    if glow:
        bsdf.inputs["Emission Color"].default_value = (*colour, 1)
        bsdf.inputs["Emission Strength"].default_value = glow
    m.diffuse_color = (*colour, 1)
    MATS[key] = m
    return m


class Map:
    def __init__(self, mid, name, modes, notes):
        self.id, self.name, self.modes, self.notes = mid, name, modes, notes
        self.colls = {}
        self.markers = []
        self.cutaways = []  # (suffix, [collections hidden], caption)

    def coll(self, name):
        if name not in self.colls:
            c = bpy.data.collections.new(name)
            bpy.context.scene.collection.children.link(c)
            self.colls[name] = c
        return self.colls[name]

    # Geometry --------------------------------------------------------------------------------

    def mesh(self, name, verts, faces, key, coll="Geometry", props=None):
        me = bpy.data.meshes.new(name)
        me.from_pydata(verts, [], faces)
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat(key))
        ob = bpy.data.objects.new(name, me)
        self.coll(coll).objects.link(ob)
        for k, v in (props or {}).items():
            ob[k] = v
        return ob

    def box(self, name, cx, cy, z0, sx, sy, h, key="wall", coll="Geometry", rot=0.0, props=None):
        """A box centred on (cx, cy), its base at z0, `rot` radians about Z."""
        hx, hy = sx / 2, sy / 2
        c, s = math.cos(rot), math.sin(rot)
        pts = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]]
        verts = [(x, y, z0) for x, y in pts] + [(x, y, z0 + h) for x, y in pts]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self.mesh(name, verts, faces, key, coll, props)

    def rect(self, name, x0, x1, y0, y1, z0, z1, key="wall", coll="Geometry", props=None):
        return self.box(name, (x0 + x1) / 2, (y0 + y1) / 2, z0, x1 - x0, y1 - y0, z1 - z0, key, coll, props=props)

    def seg(self, name, x1, y1, x2, y2, h, z0=0.0, t=0.5, key="wall", coll="Geometry"):
        """A wall from (x1, y1) to (x2, y2)."""
        L = math.hypot(x2 - x1, y2 - y1)
        return self.box(name, (x1 + x2) / 2, (y1 + y2) / 2, z0, L + t, t, h, key, coll, math.atan2(y2 - y1, x2 - x1))

    def ramp(self, name, x0, y0, x1, y1, width, z_low, z_high, z_base=None, key="ramp", coll="Geometry"):
        """A solid ramp from (x0, y0) at z_low up to (x1, y1) at z_high, its underside at z_base."""
        zb = min(z_low, z_high) if z_base is None else z_base
        d = Vector((x1 - x0, y1 - y0, 0)).normalized()
        n = Vector((-d.y, d.x, 0)) * (width / 2)
        a, b = Vector((x0, y0, 0)), Vector((x1, y1, 0))
        p = [a - n, a + n, b + n, b - n]
        verts = [(v.x, v.y, zb) for v in p] + [(p[0].x, p[0].y, z_low), (p[1].x, p[1].y, z_low),
                                              (p[2].x, p[2].y, z_high), (p[3].x, p[3].y, z_high)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self.mesh(name, verts, faces, key, coll)

    def arc(self, name, r_in, r_out, z0, h, a0, a1, key="wall", coll="Geometry", step=6.0):
        """A solid ring piece between radii, from angle a0 to a1 (degrees, anticlockwise from east)."""
        n = max(1, int(math.ceil((a1 - a0) / step)))
        verts, faces = [], []
        for i in range(n + 1):
            t = math.radians(a0 + (a1 - a0) * i / n)
            c, s = math.cos(t), math.sin(t)
            verts += [(r_in * c, r_in * s, z0), (r_out * c, r_out * s, z0),
                      (r_out * c, r_out * s, z0 + h), (r_in * c, r_in * s, z0 + h)]
        for i in range(n):
            q, w = 4 * i, 4 * (i + 1)
            faces += [(q + 0, q + 1, w + 1, w + 0), (q + 1, q + 2, w + 2, w + 1),
                      (q + 2, q + 3, w + 3, w + 2), (q + 3, q + 0, w + 0, w + 3)]
        faces += [(0, 1, 2, 3), (4 * n + 3, 4 * n + 2, 4 * n + 1, 4 * n)]
        return self.mesh(name, verts, faces, key, coll)

    def ring_wall(self, name, r_in, r_out, z0, h, gaps=(), key="wall", coll="Geometry"):
        """A full ring with openings: gaps are (angle in degrees, width in metres at r_out)."""
        cuts = sorted((a - math.degrees(w / 2 / r_in), a + math.degrees(w / 2 / r_in)) for a, w in gaps)
        if not cuts:
            return [self.arc(name, r_in, r_out, z0, h, 0, 360, key, coll)]
        pieces = []
        for i, (lo, hi) in enumerate(cuts):
            nxt = cuts[(i + 1) % len(cuts)][0] + (360 if i + 1 == len(cuts) else 0)
            if nxt > hi:
                pieces.append(self.arc(f"{name}.{i}", r_in, r_out, z0, h, hi, nxt, key, coll))
        return pieces

    def cyl(self, name, x, y, z0, r, h, key, coll="Geometry", n=32, props=None):
        verts = []
        for i in range(n):
            t = 2 * math.pi * i / n
            verts += [(x + r * math.cos(t), y + r * math.sin(t), z0), (x + r * math.cos(t), y + r * math.sin(t), z0 + h)]
        faces = [tuple(2 * i for i in range(n))[::-1], tuple(2 * i + 1 for i in range(n))]
        faces += [(2 * i, 2 * ((i + 1) % n), 2 * ((i + 1) % n) + 1, 2 * i + 1) for i in range(n)]
        return self.mesh(name, verts, faces, key, coll, props)

    def plate(self, name, x0, x1, y0, y1, z0, z1, holes=(), key="floor", coll="Geometry"):
        """A floor plate with rectangular holes (x0, x1, y0, y1), split into strips round them."""
        xs = sorted({x0, x1, *[h[0] for h in holes], *[h[1] for h in holes]})
        ys = sorted({y0, y1, *[h[2] for h in holes], *[h[3] for h in holes]})
        xs = [x for x in xs if x0 <= x <= x1]
        ys = [y for y in ys if y0 <= y <= y1]

        def solid(xa, xb, ya, yb):
            cx, cy = (xa + xb) / 2, (ya + yb) / 2
            return not any(h[0] <= cx <= h[1] and h[2] <= cy <= h[3] for h in holes)

        k = 0
        for j in range(len(ys) - 1):
            run = None
            for i in range(len(xs) - 1):
                if solid(xs[i], xs[i + 1], ys[j], ys[j + 1]):
                    run = xs[i] if run is None else run
                    end = xs[i + 1]
                if run is not None and (i == len(xs) - 2 or not solid(xs[i + 1], xs[i + 2], ys[j], ys[j + 1])):
                    self.rect(f"{name}.{k}", run, end, ys[j], ys[j + 1], z0, z1, key, coll)
                    k += 1
                    run = None

    def room(self, name, x0, x1, y0, y1, h, doors=(), z0=0.0, t=0.5, key="wall", coll="Geometry"):
        """Four walls round a rectangle. doors: (side 'N'/'S'/'E'/'W', centre along the side, width)."""
        sides = {"S": (x0, y0, x1, y0), "N": (x0, y1, x1, y1), "W": (x0, y0, x0, y1), "E": (x1, y0, x1, y1)}
        for side, (ax, ay, bx, by) in sides.items():
            horiz = ay == by
            lo, hi = (ax, bx) if horiz else (ay, by)
            gaps = sorted((c - w / 2, c + w / 2) for s, c, w in doors if s == side)
            cur, i = lo, 0
            for g0, g1 in gaps + [(hi, hi)]:
                if g0 > cur:
                    if horiz:
                        self.seg(f"{name}.{side}{i}", cur, ay, g0, ay, h, z0, t, key, coll)
                    else:
                        self.seg(f"{name}.{side}{i}", ax, cur, ax, g0, h, z0, t, key, coll)
                    i += 1
                cur = g1

    # Markers ---------------------------------------------------------------------------------

    def marker(self, ob, kind, **data):
        ob["kind"] = kind
        for k, v in data.items():
            ob[k] = v
        loc = [round(v, 2) for v in ob.get("pos", (0, 0, 0))]
        self.markers.append({"name": ob.name, "kind": kind, "pos": loc, **data})
        return ob

    def spawn(self, team, i, x, y, z=0.0, face=0.0, set_="main"):
        name = f"spawn_{team}_{set_}_{i:02d}"
        ob = self.cyl(name, x, y, z + 0.02, 0.6, 0.12, team, "Markers", n=12)
        self.box(name + "_dir", x + 0.55 * math.cos(math.radians(face)), y + 0.55 * math.sin(math.radians(face)), z + 0.02,
                 0.8, 0.25, 0.14, team, "Markers", math.radians(face))
        ob["pos"] = (x, y, z)
        return self.marker(ob, "spawn", team=team, set=set_, facing=face)

    def spawn_row(self, team, x, y, z=0.0, face=0.0, n=6, spread=2.5, set_="main", across=None):
        """n spawns in a row centred on (x, y), across the facing direction (or `across` degrees)."""
        a = math.radians(face + 90 if across is None else across)
        for i in range(n):
            o = (i - (n - 1) / 2) * spread
            self.spawn(team, i + 1, x + o * math.cos(a), y + o * math.sin(a), z, face, set_)

    def disc_marker(self, kind, name, x, y, z, r, key, label=None, label_side=-1, **data):
        ob = self.cyl(name, x, y, z + 0.03, r, 0.06, key, "Markers", n=40)
        ob["pos"] = (x, y, z)
        ob["radius"] = r
        self.marker(ob, kind, radius=r, **data)
        if label:
            # beside the disc (below it on the plan; hills above), so zone and hill labels never overlap
            self.label(label, x, y + label_side * (r + 1.1), z + 0.2, 1.3)
        return ob

    def zone(self, zid, x, y, z=0.0, r=4.0):
        return self.disc_marker("zone", f"zone_{zid}", x, y, z, r, "zone", f"Zone {zid}", id=zid)

    def hill(self, order, x, y, z=0.0, r=3.5, note=""):
        ob = self.disc_marker("hill", f"hill_{order}", x, y, z, r, "hill", f"Hill {order}", 1, order=order, note=note)
        return ob

    def beacon(self, kind, name, x, y, z, key="objective", h=2.5, r=0.5, label=None, **data):
        ob = self.cyl(name, x, y, z, r, h, key, "Markers", n=16)
        ob["pos"] = (x, y, z)
        self.marker(ob, kind, **data)
        if label:
            self.label(label, x, y, z + h + 0.3, 1.5, key)
        return ob

    def pickup(self, item, x, y, z=0.0):
        self.box(f"pedestal_{item}", x, y, z, 1.2, 1.2, 0.8, "floor2", "Markers")
        ob = self.box(f"pickup_{item}", x, y, z + 0.9, 0.6, 0.6, 0.6, "pickup", "Markers", rot=math.radians(45))
        ob["pos"] = (x, y, z)
        self.label(item.replace("_", " ").title(), x, y - 1.6, z + 1.6, 1.0, "pickup")
        return self.marker(ob, "pickup", item=item)

    def resupply(self, i, x, y, z=0.0):
        ob = self.box(f"resupply_{i}", x, y, z, 1.6, 1.0, 1.1, "resupply", "Markers")
        ob["pos"] = (x, y, z)
        return self.marker(ob, "resupply")

    def label(self, text, x, y, z, size=2.0, key="label"):
        cu = bpy.data.curves.new(f"label_{text}", "FONT")
        cu.body = text
        cu.size = size
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        ob = bpy.data.objects.new(f"label_{text}", cu)
        ob.location = (x, y, z)
        ob.data.materials.append(mat("label" if key == "label" else key))
        self.coll("Labels").objects.link(ob)
        return ob

    def callout(self, text, x, y, z=0.0, size=1.7):
        return self.label(text, x, y, z + 0.15, size)


# --- The maps -----------------------------------------------------------------------------------
# Every layout is a proposal built from the doc's notes, sized for 6v6 (5v5 for Core Breach).


def high_port_ring():
    m = Map("high_port_ring", "High Port Ring", ["Sector Hold", "Hardpoint", "Slayer", "Oddball"],
            "Ring corridor round a core atrium; three zones 120 degrees apart so it plays as 2 or 3 teams; "
            "atrium balconies give height.")
    ZONES = {"A": 90, "B": 210, "C": 330}  # zones on the ring, and the spokes into the atrium
    SPAWNS = {"A": 150, "B": 30, "C": 270}  # team spawns between the zones (2 teams: A and B)
    R_RING = 30.5
    pol = lambda r, a: (r * math.cos(math.radians(a)), r * math.sin(math.radians(a)))

    m.cyl("deck", 0, 0, -0.5, 36, 0.5, "floor", n=96)
    m.arc("ring_floor_band", 27, 34, 0, 0.02, 0, 360, "floor2")
    m.ring_wall("hull", 34, 35, 0, 7, (), "hull")
    m.ring_wall("ring_inner_wall", 26.5, 27, 0, 6, [(a, 6.5) for a in ZONES.values()])
    m.ring_wall("atrium_wall", 14.5, 15, 0, 9, [(a, 6.5) for a in ZONES.values()])
    # The core: the station's reactor column, glowing, and a ring of glass round it.
    m.cyl("reactor_core", 0, 0, 0, 3.5, 14, "core", n=48)
    m.ring_wall("core_glass", 4.5, 4.8, 0, 1.1, [(0, 2), (120, 2), (240, 2)], "glass")
    # Balcony at 4 m round the atrium, with a low rail.
    m.arc("balcony", 10, 14.5, 3.6, 0.4, 0, 360, "floor2")
    m.ring_wall("balcony_rail", 10, 10.3, 4, 1.1, [], "glass")
    for name, a in ZONES.items():
        # Spokes: a 6.5 m corridor, half of it a ramp up to the balcony, half at floor level.
        for side in (-1, 1):
            off = side * 3.25
            ax, ay = pol(15, a)
            bx, by = pol(26.5, a)
            px, py = -math.sin(math.radians(a)) * off, math.cos(math.radians(a)) * off
            m.seg(f"spoke_{name}_wall{side}", ax + px, ay + py, bx + px, by + py, 6)
        rx, ry = -math.sin(math.radians(a)) * 1.6, math.cos(math.radians(a)) * 1.6
        x0, y0 = pol(26, a)
        x1, y1 = pol(14.5, a)
        m.ramp(f"spoke_{name}_ramp", x0 + rx, y0 + ry, x1 + rx, y1 + ry, 3.0, 0.0, 4.0)
        m.seg(f"spoke_{name}_divider", *pol(15, a), *pol(25, a), 1.1, 0, 0.3, "glass")
        zx, zy = pol(R_RING, a)
        m.zone(name, zx, zy, 0, 3.5)
        # Low cover inside each zone and a bulkhead either side with a door.
        for da in (-9, 9):
            cx, cy = pol(R_RING, a + da)
            m.box(f"zone_{name}_cover{da}", cx, cy, 0, 2.6, 0.8, 1.2, "cover", rot=math.radians(a + da))
    for name, a in SPAWNS.items():
        sx, sy = pol(R_RING, a)
        m.spawn_row(name, sx, sy, 0, (a + 180) % 360, n=6, spread=1.0, across=a, set_="main")
        # A shield wall in front of each spawn so nobody fires into it from the next zone.
        for da in (-11, 11):
            cx, cy = pol(29.5, a + da)
            m.box(f"spawn_{name}_shield{da}", cx, cy, 0, 0.6, 4.5, 3, "wall", rot=math.radians(a + da))
    # Bulkheads with doors half way between each spawn and the zones beside it.
    for a in (0, 60, 120, 180, 240, 300):
        for r0, r1 in ((27, 29.2), (31.8, 34)):
            m.seg(f"bulkhead_{a}_{r0}", *pol(r0, a), *pol(r1, a), 6, 0, 0.6)
    # Hardpoint rotation (60 s each).
    for i, (r, a, z, note) in enumerate([(8, 270, 0, "atrium floor"), (R_RING, 90, 0, "ring, zone A"), (12, 210, 4, "balcony"),
                                         (R_RING, 330, 0, "ring, zone C"), (12, 30, 4, "balcony")], 1):
        x, y = pol(r, a)
        m.hill(i, x, y, z, 3.0, note)
    bx, by = pol(7, 90)
    m.beacon("ball", "oddball_spawn", bx, by, 0, "objective", 1.0, 0.4, "Ball")
    px, py = pol(12, 270)
    m.pickup("power_weapon", px, py, 4)
    for txt, r, a in [("Core Atrium", 7, 300), ("Balcony", 12.3, 150), ("North Ring", 30.5, 70), ("West Ring", 30.5, 190),
                      ("East Ring", 30.5, 350)]:
        m.callout(txt, *pol(r, a), 4.5 if txt == "Balcony" else 0)
    return m


def carrier_dock_pads():
    m = Map("carrier_dock_pads", "Carrier Dock Pads", ["Slayer", "CTF", "Hardpoint"],
            "Two landed carriers face each other across a Builder's Carrier Dock; ramps and cargo make three "
            "lanes; each carrier's hold is a base.")
    m.rect("dock", -72, 72, -34, 34, -0.6, 0, "floor")
    for lane_y in (-22, 22):
        m.rect(f"dock_paint{lane_y}", -30, 30, lane_y - 0.15, lane_y + 0.15, 0, 0.02, "zone")
    m.rect("dock_edge_n", -72, 72, 33.5, 34, 0, 1.1, "cover")
    m.rect("dock_edge_s", -72, 72, -34, -33.5, 0, 1.1, "cover")
    for s, team in ((-1, "A"), (1, "B")):
        X = lambda x: s * x  # mirror: team A west, team B east
        x_front, x_back = 36, 68
        lo, hi = sorted((X(x_front), X(x_back)))
        # The hold floor 2 m up on the carrier's struts, the hull round it and its roof.
        m.rect(f"hold_floor_{team}", lo, hi, -12, 12, 0, 2, "floor2")
        m.rect(f"hull_back_{team}", min(X(68), X(68.8)), max(X(68), X(68.8)), -12.5, 12.5, 0, 13, "hull")
        for side in (-1, 1):
            y = side * 12.25
            # side walls with a crew door (walk-out) at x = 46
            a0, a1 = sorted((X(36), X(44.5)))
            b0, b1 = sorted((X(47.5), X(68)))
            m.rect(f"hull_side_{team}{side}a", a0, a1, y - 0.25, y + 0.25, 0, 13, "hull")
            m.rect(f"hull_side_{team}{side}b", b0, b1, y - 0.25, y + 0.25, 0, 13, "hull")
            d0, d1 = sorted((X(44.5), X(47.5)))
            m.rect(f"hull_side_{team}{side}lintel", d0, d1, y - 0.25, y + 0.25, 5.5, 13, "hull")
            m.rect(f"hull_side_{team}{side}sill", d0, d1, y - 0.25, y + 0.25, 0, 2, "hull")
            # crew stairs down from the side door toward the middle
            m.ramp(f"crew_stairs_{team}{side}", X(46), side * 15.5, X(38), side * 15.5, 3, 2, 0, 0)
            m.rect(f"crew_landing_{team}{side}", *sorted((X(44.5), X(47.5))), *sorted((side * 12.5, side * 17)), 0, 2, "floor2")
            # front bulkhead beside the big ramp
            f0, f1 = sorted((X(36), X(36.6)))
            m.rect(f"hull_front_{team}{side}", f0, f1, *sorted((side * 5, side * 12.5)), 0, 13, "hull")
        f0, f1 = sorted((X(36), X(36.6)))
        m.rect(f"hull_front_lintel_{team}", f0, f1, -5, 5, 8, 13, "hull")
        m.rect(f"roof_{team}", lo - 0.5, hi + 0.5, -12.5, 12.5, 13, 13.6, "hull", "Roofs")
        # Nose and engines outside the hold, for the silhouette.
        m.rect(f"engine_{team}_n", *sorted((X(60), X(72))), 9, 14, 4, 10, "hull", "Roofs")
        m.rect(f"engine_{team}_s", *sorted((X(60), X(72))), -14, -9, 4, 10, "hull", "Roofs")
        # The loading ramp down to the dock.
        m.ramp(f"hold_ramp_{team}", X(36), 0, X(27), 0, 10, 2, 0, 0)
        # Inside the hold: a defensive mezzanine along the back wall, with a ramp up to it.
        m.rect(f"mezzanine_{team}", *sorted((X(61), X(68))), -12, 12, 6, 6.5, "floor2")
        m.rect(f"mezzanine_rail_{team}", *sorted((X(60.6), X(61))), -12, 12, 6.5, 7.6, "glass")
        m.ramp(f"mezzanine_ramp_{team}", X(46), -10, X(61), -10, 3, 2, 6.5, 2)
        m.box(f"hold_crates_{team}1", X(52), 5, 2, 2.4, 2.4, 1.4, "crate")
        m.box(f"hold_crates_{team}2", X(44), -4, 2, 3.0, 1.2, 1.2, "cover")
        m.box(f"hold_crates_{team}3", X(55), -3, 2, 1.2, 3.0, 1.2, "cover")
        m.beacon("flag", f"flag_{team}", X(62), 4, 2, team, 2.6, 0.35, f"Flag {team}", team=team)
        m.spawn_row(team, X(57), -6, 2, 0 if s < 0 else 180, n=6, spread=2.2, across=90, set_="main")
        m.callout(f"{'West' if s < 0 else 'East'} Hold", X(50), 0, 2)
    # Lanes: container rows split the dock into a middle lane and two side lanes.
    for side in (-1, 1):
        y = side * 12
        for x, stack in ((-21, 1), (-15, 1), (-5.5, 2), (5.5, 2), (15, 1), (21, 1)):
            for k in range(stack):
                m.box(f"container_{side}_{x}_{k}", x, y, 2.6 * k, 6, 2.5, 2.6, "crate" if k == 0 else "cover")
        # side lanes: a crane base and low cover
        m.box(f"crane_{side}", 0, side * 25, 0, 4, 4, 9, "hull")
        m.box(f"crane_arm_{side}", 0, side * 20, 9, 2, 14, 1.2, "hull")
        for x in (-14, 14):
            m.box(f"lane_cover_{side}_{x}", x, side * 24, 0, 3, 1, 1.2, "cover")
        for x in (-28, 28):
            m.box(f"ramp_cover_{side}_{x}", x, side * 7, 0, 1, 3.5, 1.2, "cover")
    # The middle: a raised cargo pad with the power weapon, ramps up from each team's side.
    m.rect("mid_pad", -4, 4, -4, 4, 0, 1.5, "floor2")
    m.ramp("mid_ramp_w", -9, 0, -4, 0, 4, 0, 1.5, 0)
    m.ramp("mid_ramp_e", 9, 0, 4, 0, 4, 0, 1.5, 0)
    m.pickup("power_weapon", 0, 0, 1.5)
    for i, (x, y, z, note) in enumerate([(0, 0, 1.5, "mid pad"), (0, 24, 0, "north lane"), (-24, -18, 0, "west ramp foot"),
                                         (0, -24, 0, "south lane"), (24, 18, 0, "east ramp foot")], 1):
        m.hill(i, x, y, z, 3.0, note)
    m.callout("Mid Pad", 0, -6.5)
    m.callout("North Lane", 0, 29)
    m.callout("South Lane", 0, -29)
    m.cutaways.append(("plan", ["Roofs"], "roofs hidden"))
    return m


def hangar_flight_deck():
    m = Map("hangar_flight_deck", "Hangar and Flight Deck", ["Hardpoint", "Slayer"],
            "A carrier's hangar (close quarters) under its flight deck (long sightlines); the hill rotates "
            "round the hangar floor, a lift, the deck catapult and the observation tower.")
    DECK = 9.0
    # Holes in the deck: two ramps up from the hangar (south side) and two lifts (north side).
    ramp_holes = [(-16, -8, -15, -11), (8, 16, -15, -11)]
    lift_holes = [(-26, -18, 2, 10), (18, 26, 2, 10)]
    m.rect("hangar_floor", -42, 42, -17, 17, -0.6, 0, "floor")
    m.plate("flight_deck", -52, 52, -19, 19, DECK - 1, DECK, ramp_holes + lift_holes, "floor2", "Deck")
    m.room("hangar_walls", -40, 40, -16, 16, DECK - 1, [("W", 0, 6), ("E", 0, 6)], 0, 0.8, "hull")
    # Deck edge rails, and the catapult track down the middle.
    for y in (-19, 19):
        m.rect(f"deck_rail{y}", -52, 52, y - 0.2 if y > 0 else y, y if y > 0 else y + 0.2, DECK, DECK + 1.1, "glass", "Deck")
    m.rect("catapult_track", -46, 46, -4.4, -3.6, DECK, DECK + 0.15, "zone", "Deck")
    m.box("catapult_shuttle", 0, -4, DECK, 3, 1.6, 0.6, "hull", "Deck")
    for x in (-40, 40):
        m.box(f"blast_deflector{x}", x, -4, DECK, 1.0, 9, 2.6, "hull", "Deck")
    for x, y in ((-30, 12), (30, 12), (-12, -12), (12, -12), (-32, -14), (32, -14)):
        m.box(f"deck_cover_{x}_{y}", x, y, DECK, 3, 1, 1.2, "cover", "Deck")
    # Parked fighters on the deck, for cover and silhouette.
    for x in (-24, 24):
        m.box(f"deck_fighter_{x}", x, -12, DECK, 7, 2, 2, "hull", "Deck")
        m.box(f"deck_fighter_{x}_wing", x + (1 if x < 0 else -1), -12, DECK + 0.8, 3, 8, 0.4, "hull", "Deck")
    # Observation tower (the island) on the north edge, ramps up from both sides.
    TOP = DECK + 6
    m.rect("tower_base", -6, 6, 12, 18, DECK, TOP, "hull", "Deck")
    for x, y in ((-5.7, 12.3), (5.7, 12.3), (-5.7, 17.7), (5.7, 17.7)):
        m.box(f"tower_post_{x}_{y}", x, y, TOP, 0.5, 0.5, 4, "hull", "Deck")
    m.rect("tower_roof", -6.5, 6.5, 11.5, 18.5, TOP + 4, TOP + 4.5, "hull", "Tower Roof")
    m.rect("tower_glass", -6, 6, 17.6, 18, TOP, TOP + 1.1, "glass", "Deck")
    m.ramp("tower_ramp_w", -22, 13.5, -6, 13.5, 3, DECK, TOP, DECK)
    m.ramp("tower_ramp_e", 22, 13.5, 6, 13.5, 3, DECK, TOP, DECK)
    # Hangar ramps up to the deck through the holes.
    m.ramp("hangar_ramp_w", -28, -13, -8, -13, 4, 0, DECK, 0)
    m.ramp("hangar_ramp_e", 28, -13, 8, -13, 4, 0, DECK, 0)
    # Lifts: platforms at the bottom of their shafts (they ride to the deck in game).
    for name, (x0, x1, y0, y1) in (("w", lift_holes[0]), ("e", lift_holes[1])):
        ob = m.rect(f"lift_{name}", x0 + 0.2, x1 - 0.2, y0 + 0.2, y1 - 0.2, 0, 0.3, "lift", "Markers")
        ob["pos"] = ((x0 + x1) / 2, (y0 + y1) / 2, 0)
        m.marker(ob, "lift", bottom=0.0, top=DECK, seconds=4)
        for cx, cy in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            m.box(f"lift_{name}_post_{cx}_{cy}", cx, cy, 0, 0.5, 0.5, DECK, "lift")
    # In the hangar: parked fighters, a maintenance gantry and crates.
    for x, y in ((-30, 6), (30, 6), (-8, 8), (8, 8)):
        m.box(f"hangar_fighter_{x}_{y}", x, y, 0, 7, 2, 2.2, "hull")
        m.box(f"hangar_fighter_{x}_{y}_wing", x, y, 0.8, 3, 7, 0.4, "hull")
    m.rect("gantry_w", -3, -2.4, -6, 4, 0, 5, "hull")
    m.rect("gantry_e", 2.4, 3, -6, 4, 0, 5, "hull")
    m.rect("gantry_top", -3, 3, -6, 4, 5, 5.5, "hull")
    for x, y in ((-20, -4), (20, -4), (-34, -6), (34, -6), (0, -9), (-14, 2), (14, 2)):
        m.box(f"hangar_crate_{x}_{y}", x, y, 0, 2.2, 2.2, 1.4 if abs(x) != 34 else 2.4, "crate")
    for i, (x, y, z, note) in enumerate([(0, 0, 0, "hangar floor"), (-22, 6, DECK, "west lift top"), (0, -4, DECK, "catapult"),
                                         (0, 15, TOP, "observation tower"), (22, 6, DECK, "east lift top")], 1):
        m.hill(i, x, y, z, 3.0, note)
    for team, s in (("A", -1), ("B", 1)):
        m.spawn_row(team, s * 37, 0, 0, 0 if s < 0 else 180, n=6, spread=2.0, across=90, set_="hangar")
        m.spawn_row(team, s * 47, 6, DECK, 0 if s < 0 else 180, n=6, spread=2.0, across=90, set_="deck")
    m.pickup("power_weapon", 0, -9, 0)
    m.pickup("overshield", 0, 15, TOP)
    for txt, x, y, z in [("Hangar Floor", 0, -2, 0), ("Gantry", 0, 6, 0), ("Catapult", 0, -7.5, DECK), ("Tower", 0, 10, TOP),
                         ("West Lift", -22, 0, DECK), ("East Lift", 22, 0, DECK)]:
        m.callout(txt, x, y, z)
    m.cutaways.append(("hangar", ["Deck", "Tower Roof", "Labels"], "flight deck hidden: the hangar below"))
    m.cutaways.append(("deck", ["Tower Roof"], "flight deck"))
    return m


def outpost_vault():
    m = Map("outpost_vault", "Outpost Vault", ["Core Breach", "One Flag (Data Core)"],
            "Attackers come in over an outpost's 12x12 surface grid and down three shafts; two charge "
            "points on the level below; the defenders start by the vault.")
    LOW = -9.0  # the level below ground
    T = 6.0  # surface grid tile
    shafts = [(-30, -24, -30, -12), (-6, 6, -30, -12), (24, 30, -30, -12)]
    # Surface: 12x12 tiles, minus the shafts.
    for i in range(12):
        for j in range(12):
            x0, y0 = -36 + i * T, -36 + j * T
            if any(s[0] <= x0 + 3 <= s[1] and s[2] <= y0 + 3 <= s[3] for s in shafts):
                continue
            m.rect(f"tile_{i}_{j}", x0 + 0.06, x0 + T - 0.06, y0 + 0.06, y0 + T - 0.06, -1, 0, "floor2" if (i + j) % 2 else "floor", "Surface")
    for k, (x0, x1, y0, y1) in enumerate(shafts):
        for side in ("W", "E"):
            x = x0 if side == "W" else x1
            m.rect(f"shaft_{k}_rail{side}", x - 0.2, x + 0.2, y0, y1, 0, 1.1, "glass", "Surface")
    # Surface buildings on the grid: cover for the approach, none over the shafts.
    for name, x0, x1, y0, y1, h in [("command", -12, 12, 18, 30, 8), ("extractor_w", -30, -18, 6, 18, 5), ("extractor_e", 18, 30, 6, 18, 5),
                                    ("depot_w", -24, -12, -6, 0, 3.5), ("depot_e", 12, 24, -6, 0, 3.5), ("pylon_w", -36, -30, -6, 0, 9),
                                    ("pylon_e", 30, 36, -6, 0, 9), ("silo_w", -18, -12, 24, 30, 6), ("silo_e", 12, 18, 24, 30, 6)]:
        m.rect(f"bldg_{name}", x0 + 0.5, x1 - 0.5, y0 + 0.5, y1 - 0.5, 0, h, "hull", "Surface")
    for x in (-15, 15, -21, 21):
        m.box(f"surface_cover_{x}", x, -20, 0, 3, 1, 1.2, "cover", "Surface")
    m.spawn_row("attack", 0, -34, 0, 90, n=5, spread=3.0, set_="round_start")
    m.callout("Surface Grid", 0, -26, 1.2)
    # The level below.
    m.rect("lower_floor", -36, 36, -36, 36, LOW - 0.6, LOW, "floor")
    H = 8.0
    m.room("lower_outer", -36, 36, -36, 36, H, [], LOW, 0.8, "hull")
    for k, (x0, x1, y0, y1) in enumerate(shafts):
        if k == 1:
            # middle shaft: a ramp on the west half, a straight drop on the east half
            m.ramp(f"shaft_ramp_{k}", -3, -30, -3, -12, 6, 0, LOW, LOW)
        else:
            m.ramp(f"shaft_ramp_{k}", (x0 + x1) / 2, -30, (x0 + x1) / 2, -12, 6, 0, LOW, LOW)
    m.room("landing_wall", -36, 36, -36, -8, H, [("N", -27, 4), ("N", 0, 6), ("N", 27, 4)], LOW, 0.6)
    for side, sx in (("A", -1), ("B", 1)):
        X = lambda x: sx * x
        x0, x1 = sorted((X(34), X(14)))
        e_side = "E" if sx < 0 else "W"
        m.room(f"site_{side}", x0, x1, -2, 14, H, [("S", X(27), 4), (e_side, 6, 3), ("N", X(20), 3)], LOW, 0.6)
        m.beacon("charge", f"charge_{side}", X(24), 7, LOW, "objective", 1.6, 0.8, f"Charge {side}", id=side)
        for cx, cy, w, d in ((X(29), 10, 2.4, 2.4), (X(18), 2, 3, 1), (X(24), 1, 1, 3)):
            m.box(f"site_{side}_cover_{cx}_{cy}", cx, cy, LOW, w, d, 1.3, "crate" if w == d else "cover")
        m.callout(f"Site {side}", X(24), 11.5, LOW)
        # flank corridor from the landing up to the site, with a pillar
        m.box(f"flank_pillar_{side}", X(27), -5, LOW, 1.2, 1.2, H, "hull")
    m.room("mid_hall", -8, 8, -6, 12, H, [("S", 0, 6), ("W", 6, 3), ("E", 6, 3), ("N", 0, 3)], LOW, 0.6)
    for x in (-3.5, 3.5):
        m.box(f"mid_pillar_{x}", x, 3, LOW, 1.2, 1.2, H, "hull")
    m.callout("Mid Hall", 0, -2, LOW)
    m.callout("Defender Hall", 0, 17, LOW)
    m.room("vault", -12, 12, 20, 34, H, [("S", -6, 3), ("S", 6, 3)], LOW, 0.8, "hull")
    m.rect("vault_core_plinth", -2, 2, 27, 31, LOW, LOW + 1, "floor2")
    m.beacon("core", "data_core", 0, 29, LOW + 1, "core", 1.4, 0.7, "Data Core")
    m.spawn_row("defend", 0, 32.5, LOW, 270, n=5, spread=3.0, set_="round_start")
    m.callout("Vault", 0, 24, LOW)
    for x, y in ((-24, 17), (24, 17), (0, 17)):
        m.box(f"defender_cover_{x}", x, y, LOW, 3, 1, 1.2, "cover")
    m.cutaways.append(("lower", ["Surface"], "surface hidden: the level below"))
    m.cutaways.append(("surface", [], "surface"))
    return m


def carrier_boarding():
    m = Map("carrier_boarding", "Carrier Boarding", ["Boarding Action"],
            "Hybrid: take the hangar, escort a breach charge through the power room, then the bridge; "
            "forward spawns at each checkpoint.")
    H = 7.0
    hull = [(-60, -25), (40, -25), (70, 0), (40, 25), (-60, 25)]
    m.rect("boarding_pad", -76, -60, -24, -2, -0.6, 0, "floor2")
    m.mesh("deck_floor", [(x, y, -0.6) for x, y in hull] + [(x, y, 0) for x, y in hull],
           [(4, 3, 2, 1, 0), (5, 6, 7, 8, 9)] + [(i, (i + 1) % 5, (i + 1) % 5 + 5, i + 5) for i in range(5)], "floor")
    for i in range(4):
        (x1, y1), (x2, y2) = hull[i], hull[i + 1]
        m.seg(f"hull_{i}", x1, y1, x2, y2, H, 0, 0.8, "hull")
    # Section 1: the hangar (south-west, ground level) and the flight deck (north-west, 6 m up).
    m.rect("flight_deck", -60, -25, 0, 25, 0, 6, "floor2")
    m.rect("flight_deck_rail", -60, -60.3, 0, 25, 6, 7.1, "glass")
    m.ramp("flight_deck_ramp", -25, 12, -12, 12, 6, 6, 0, 0)
    m.seg("hangar_divider", -60, 0, -25, 0, 1.2, 6, 0.4, "glass")
    for x, y in ((-48, -12), (-36, -18), (-36, -6)):
        m.box(f"hangar_shuttle_{x}_{y}", x, y, 0, 6, 2.5, 2.2, "hull")
    for x, y in ((-54, -6), (-30, -12), (-44, -20)):
        m.box(f"hangar_crate_{x}_{y}", x, y, 0, 2, 2, 1.4, "crate")
    for x, y in ((-50, 12), (-40, 18), (-34, 8)):
        m.box(f"deck_cover_{x}_{y}", x, y, 6, 3, 1, 1.2, "cover")
    # Wall between section 1 and the power room: the charge door and the flight deck's way down.
    m.room("s1_wall", -25, -25.01, -25, 25, H, [("W", -10, 6), ("W", 12, 7)], 0, 0.8)
    # Section 2: the power room, reactor in the middle, a catwalk round it.
    m.cyl("reactor", 0, 0, 0, 5, 12, "core", n=40)
    m.arc("catwalk", 8, 11, 4.6, 0.4, 0, 360, "floor2")
    m.ring_wall("catwalk_rail", 10.7, 11, 5, 1.1, [], "glass")
    m.ramp("catwalk_ramp_s", -16, -14, -6, -10.5, 3, 0, 5, 0)
    m.ramp("catwalk_ramp_n", -16, 14, -6, 10.5, 3, 0, 5, 0)
    for x, y in ((-12, -4), (12, 4), (6, -16), (-6, 17), (14, -10)):
        m.box(f"power_cover_{x}_{y}", x, y, 0, 3, 1, 1.2, "cover")
    m.room("s2_wall", 20, 20.01, -25, 25, H, [("W", 0, 6), ("W", 15, 3), ("W", -15, 3)], 0, 0.8)
    # Middle passage to the bridge, with flank rooms either side.
    m.seg("corridor_n", 20, 5, 35, 5, H, 0, 0.6)
    m.seg("corridor_s", 20, -5, 35, -5, H, 0, 0.6)
    m.room("s3_wall", 35, 35.01, -25, 25, H, [("W", 0, 6), ("W", 15, 3), ("W", -15, 3)], 0, 0.8)
    for y in (-15, 15):
        m.box(f"flank_cover_{y}", 27.5, y, 0, 1, 3, 1.2, "cover")
    # Section 3: the bridge, a raised command platform and its stations.
    m.mesh("command_platform", [(50, -10, 0), (62, -6, 0), (62, 6, 0), (50, 10, 0), (50, -10, 1.5), (62, -6, 1.5), (62, 6, 1.5), (50, 10, 1.5)],
           [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], "floor2")
    m.ramp("command_steps", 44, 0, 50, 0, 6, 0, 1.5, 0)
    for x, y in ((42, -14), (42, 14), (52, -16), (52, 16), (58, 0)):
        m.box(f"bridge_station_{x}_{y}", x, y, 0 if abs(y) > 10 else 1.5, 2.6, 1.0, 1.1, "glass")
    m.beacon("objective", "bridge_controls", 60, 0, 1.5, "objective", 1.8, 0.8, "Bridge")
    # Checkpoints, the charge's route and the forward spawns.
    for i, (x, y, z, r, txt) in enumerate([(-40, -10, 0, 6, "Take the Hangar"), (24, 0, 0, 4, "Power Room Door"), (60, 0, 1.5, 4, "Bridge")], 1):
        m.disc_marker("checkpoint", f"checkpoint_{i}", x, y, z, r, "zone", f"Checkpoint {i}: {txt}", order=i)
    path = [(-40, -10), (-25, -10), (-14, -14), (0, -15), (14, -12), (20, 0), (35, 0), (44, 0)]
    for i, (x, y) in enumerate(path, 1):
        m.beacon("path", f"charge_path_{i:02d}", x, y, 0, "path", 0.3, 0.35, None, order=i)
    for i in range(len(path) - 1):
        m.seg(f"charge_path_line_{i}", *path[i], *path[i + 1], 0.06, 0.02, 0.25, "path", "Markers")
    m.beacon("objective", "breach_charge", -40, -10, 0, "pickup", 1.0, 0.6, "Breach Charge")
    m.spawn_row("attack", -70, -13, 0, 0, n=6, spread=2.5, across=90, set_="section_1")
    m.spawn_row("attack", -50, 14, 6, 0, n=6, spread=2.5, across=90, set_="section_2")
    m.spawn_row("attack", -10, 20, 0, 0, n=6, spread=2.0, set_="section_3")
    m.spawn_row("defend", 12, 20, 0, 180, n=6, spread=2.0, set_="section_1")
    m.spawn_row("defend", 30, 18, 0, 270, n=6, spread=1.6, across=0, set_="section_2")
    m.spawn_row("defend", 64, 0, 0, 180, n=6, spread=1.4, across=90, set_="section_3")
    for txt, x, y, z in [("Hangar", -44, -3, 0), ("Flight Deck", -44, 22, 6), ("Power Room", 0, -21, 0), ("Corridor", 27.5, 0, 0),
                         ("Bridge", 47, -20, 0)]:
        m.callout(txt, x, y, z)
    return m


def besieged_outpost():
    m = Map("besieged_outpost", "Besieged Outpost", ["Coma Firefight"],
            "Hold the outpost core while Coma phase-shifting bots drop in at the edges; resupply at the "
            "turrets, away from cover.")
    m.rect("ground", -75, 75, -75, 75, -0.6, 0, "floor")
    m.rect("compound_floor", -40, 40, -40, 40, 0, 0.02, "floor2")
    R = 40.0  # wall apothem
    rc = R / math.cos(math.radians(22.5))
    verts = [(rc * math.cos(math.radians(-22.5 + 45 * k)), rc * math.sin(math.radians(-22.5 + 45 * k))) for k in range(9)]
    for k in range(8):
        (x1, y1), (x2, y2) = verts[k], verts[k + 1]
        mid_angle = 45 * k  # this edge's middle faces this angle
        if mid_angle % 90 == 0:  # a gate in the middle of the N, E, S and W walls
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            ux, uy = (x2 - x1), (y2 - y1)
            L = math.hypot(ux, uy)
            ux, uy = ux / L * 4.5, uy / L * 4.5
            m.seg(f"wall_{k}a", x1, y1, mx - ux, my - uy, 4, 0, 1.0, "hull")
            m.seg(f"wall_{k}b", mx + ux, my + uy, x2, y2, 4, 0, 1.0, "hull")
        else:
            m.seg(f"wall_{k}", x1, y1, x2, y2, 4, 0, 1.0, "hull")
    # Turrets on the diagonal walls, on raised platforms with a ramp; resupply crates beside them, in the open.
    for i, a in enumerate((45, 135, 225, 315), 1):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        x, y = 34 * c, 34 * s
        m.cyl(f"turret_platform_{i}", x, y, 0, 3.5, 3, "floor2", n=24)
        m.cyl(f"turret_{i}", x, y, 3, 1.2, 1.6, "hull", n=16)
        m.box(f"turret_{i}_barrel", x + 1.6 * c, y + 1.6 * s, 3.9, 3.2, 0.5, 0.5, "hull", rot=math.radians(a))
        m.ramp(f"turret_ramp_{i}", 25 * c - 3 * s, 25 * s + 3 * c, 31 * c - 3 * s, 31 * s + 3 * c, 2.4, 0, 3, 0)
        m.resupply(i, 26 * c + 3 * s, 26 * s - 3 * c, 0)
        m.callout(f"Turret {i}", 30 * c + 5 * s, 30 * s - 5 * c)
    # The hub: the outpost core building, four doors, the core inside.
    m.room("core_building", -9, 9, -9, 9, 7, [("N", 0, 4), ("S", 0, 4), ("E", 0, 4), ("W", 0, 4)], 0, 1.0, "hull")
    m.rect("core_roof", -9.5, 9.5, -9.5, 9.5, 7, 7.6, "hull", "Roofs")
    m.cyl("outpost_core", 0, 0, 0, 2.5, 6, "core", n=32)
    m.disc_marker("objective", "hub", 0, 0, 0, 9, "zone", None, id="hub")
    m.spawn_row("players", 0, -5.5, 0, 270, n=4, spread=2.5, set_="hub")
    for i, (x, y) in enumerate(((6, 6), (-6, 6), (6, -6), (-6, -6))):
        m.box(f"core_console_{i}", x, y, 0, 1.6, 0.8, 1.1, "glass")
    # Buildings and cover between the core and the walls.
    for name, x, y, sx, sy, h in [("barracks", -22, 18, 12, 6, 4), ("depot", 22, -18, 12, 6, 4), ("hydroponics", 20, 20, 6, 10, 3.5),
                                  ("generator", -20, -20, 6, 10, 3.5)]:
        m.box(f"bldg_{name}", x, y, 0, sx, sy, h, "hull")
    for x, y, r in ((0, 20, 0), (0, -20, 0), (20, 0, 90), (-20, 0, 90), (13, 30, 0), (-13, -30, 0), (30, -12, 90), (-30, 12, 90)):
        m.box(f"sandbags_{x}_{y}", x, y, 0, 4, 1, 1.2, "cover", rot=math.radians(r))
    # Coma drop zones outside the walls.
    for i, a in enumerate(range(0, 360, 60), 1):
        x, y = 58 * math.cos(math.radians(a + 30)), 58 * math.sin(math.radians(a + 30))
        m.disc_marker("drop_zone", f"coma_drop_{i}", x, y, 0, 6, "coma", f"Drop {i}", id=i)
    for txt, x, y in [("Core", 0, -12), ("North Gate", 0, 44), ("South Gate", 0, -44), ("East Gate", 45, 0), ("West Gate", -45, 0)]:
        m.callout(txt, x, y)
    m.cutaways.append(("plan", ["Roofs"], "roof hidden"))
    return m



# --- The archetype and per-mode maps ------------------------------------------------------------
# Sections 4 to 9 of the report: the four map archetypes (figures 7, 8, 10 and 12) and the map
# types table 9 and the mode sections ask for. Original Teal Galaxy layouts that follow those rules.


def arena_floor(m, x0, x1, y0, y1, h=6.0, key="hull", doors=()):
    m.rect("floor", x0, x1, y0, y1, -0.6, 0, "floor")
    m.room("perimeter", x0, x1, y0, y1, h, doors, 0, 0.8, key)


def jump_pad(m, i, x, y, z, to, note=""):
    ob = m.cyl(f"jump_pad_{i}", x, y, z + 0.02, 1.2, 0.2, "lift", "Markers", n=20)
    ob["pos"] = (x, y, z)
    m.marker(ob, "jump_pad", to=list(to), note=note)
    m.label("Jump", x, y - 2, z + 0.3, 1.0)


def twin_bastions():
    m = Map("twin_bastions", "Twin Bastions", ["CTF", "Slayer", "One Flag", "Neutral Bomb"],
            "Archetype 1 (figure 7): two mirrored bases, each with its flag, spawn, three entrances and a high "
            "perch; a long-sightline top lane with mirrored weapon pickups, a short contested middle with the "
            "power-up, and a covered bottom flank. Flag to flag is about 116 m, 25 to 40 s on foot.")
    arena_floor(m, -66, 66, -32, 32, 7)
    for s, team in ((-1, "A"), (1, "B")):
        X = lambda x: s * x
        lo, hi = sorted((X(50), X(65.2)))
        front = "E" if s < 0 else "W"
        m.room(f"base_{team}", lo, hi, -10, 10, 6, [(front, 0, 4), ("N", X(57), 4), ("S", X(57), 4)], 0, 0.6, "hull")
        m.rect(f"base_{team}_roof", lo, hi, -10, 10, 6, 6.5, "hull", "Roofs")
        # the high defensive perch at the back, with a ramp up
        m.rect(f"perch_{team}", *sorted((X(61), X(65))), -9.5, 9.5, 3.2, 3.6, "floor2")
        m.ramp(f"perch_ramp_{team}", X(52), -7.5, X(61), -7.5, 2.5, 0, 3.6, 0)
        m.rect(f"perch_rail_{team}", *sorted((X(60.8), X(61))), -6, 9.5, 3.6, 4.7, "glass")
        m.beacon("flag", f"flag_{team}", X(58), 3, 0, team, 2.6, 0.35, f"Flag {team}", team=team)
        m.spawn_row(team, X(63), 0, 3.6, 0 if s < 0 else 180, n=6, spread=2.6, across=90)
        # Neutral Bomb plants in each base; One Flag defends base A's flag.
        m.disc_marker("charge", f"bomb_plant_{team}", X(56), -4, 0, 1.6, "objective", None, id=f"plant_{team}", mode="Neutral Bomb")
        m.callout(f"{'Red' if s < 0 else 'Blue'} Base", X(57), -2, 3.6)
        # base mouths open onto each lane: angled walls make the corner routes of the figure
        m.seg(f"mouth_n_{team}", X(50), 10, X(42), 16, 4)
        m.seg(f"mouth_s_{team}", X(50), -10, X(42), -16, 4)
    # Lane dividers, with crossings near the middle.
    for y in (-11, 11):
        for x0, x1 in ((-40, -15), (-9, 9), (15, 40)):
            m.seg(f"divider_{y}_{x0}", x0, y, x1, y, 4)
    # Top lane: long sightlines, a little low cover, mirrored weapon pickups.
    for x in (-30, 30):
        m.pickup(f"weapon_W_{'west' if x < 0 else 'east'}", x * 0.6, 22)
    for x in (-36, -8, 8, 36):
        m.box(f"top_cover_{x}", x, 22 + (2 if x in (-8, 36) else -2), 0, 3, 0.8, 1.2, "cover")
    m.callout("Top Lane: long sightlines", 0, 27)
    # Middle: short route, the contested power-up on a low plinth.
    m.rect("mid_plinth", -3, 3, -3, 3, 0, 0.8, "floor2")
    m.pickup("power_up_P", 0, 0, 0.8)
    m.beacon("ball", "neutral_bomb_spawn", 0, 5, 0, "objective", 0.8, 0.4, "Bomb", mode="Neutral Bomb")
    for x in (-22, 22):
        m.box(f"mid_cover_{x}", x, 0, 0, 1, 4, 1.4, "cover")
    m.callout("Mid: short route", 0, -6)
    # Bottom lane: cover and a roofed stretch, the flag-run route.
    m.rect("tunnel_roof", -24, 24, -31, -13, 4.2, 4.7, "hull", "Roofs")
    for x in (-24, 24):
        m.rect(f"tunnel_mouth_{x}", x - 0.4, x + 0.4, -31.2, -26, 0, 4.2, "hull")
    for i, (x, y) in enumerate(((-34, -18), (-16, -25), (-6, -18), (6, -26), (16, -18), (34, -25), (0, -22))):
        m.box(f"flank_crate_{i}", x, y, 0, 2.2, 2.2, 1.6, "crate")
    m.callout("Bottom Lane: covered flank", 0, -29)
    m.cutaways.append(("plan", ["Roofs"], "roofs hidden"))
    return m


def spindle_yard():
    m = Map("spindle_yard", "Spindle Yard", ["Hardpoint", "King of the Hill"],
            "Archetype 2, rotating hill (figure 8): H1 in the middle, H2 to H5 at the corners, on a fixed 60 s "
            "rotation. Each hill has two or three ways in and a perch over it; spawns flip as the hill moves.")
    arena_floor(m, -40, 40, -36, 36, 6)
    HILLS = [(0, 0), (-22, 20), (22, 20), (22, -20), (-22, -20)]
    m.rect("plaza", -8, 8, -8, 8, 0, 0.02, "floor2")
    for x, y in ((-6, -6), (6, -6), (-6, 6), (6, 6)):
        m.box(f"plaza_pillar_{x}_{y}", x, y, 0, 1.2, 1.2, 5, "hull")
    for i, (x, y) in enumerate(HILLS[1:], 2):
        sx, sy = (1 if x > 0 else -1), (1 if y > 0 else -1)
        # a courtyard: two walls of an L round the hill, leaving three ways in
        m.seg(f"court_{i}_a", x - 7 * sx, y + 7 * sy, x + 3 * sx, y + 7 * sy, 4)
        m.seg(f"court_{i}_b", x + 7 * sx, y + 7 * sy, x + 7 * sx, y - 3 * sy, 4)
        m.box(f"court_{i}_cover", x - 3 * sx, y - 3 * sy, 0, 3, 1, 1.2, "cover", rot=math.radians(45))
        # the perch: a platform on the outer corner, a ramp up from inside the courtyard
        m.rect(f"perch_{i}", *sorted((x + 7 * sx, x + 11 * sx)), *sorted((y + 2 * sy, y + 11 * sy)), 0, 3.5, "floor2")
        m.ramp(f"perch_{i}_ramp", x + 9 * sx, y - 7 * sy, x + 9 * sx, y + 2 * sy, 3, 0, 3.5, 0)
    for i, (x, y) in enumerate(HILLS, 1):
        m.hill(i, x, y, 0, 3.5, "fixed rotation, 60 s")
    # the links between hills in the figure (H2-H3, H3-H4, H4-H5, H5-H1, H1-H2): low walls guide them
    for x0, y0, x1, y1 in ((-10, 28, 10, 28), (30, 8, 30, -8), (-10, -28, 10, -28)):
        m.seg(f"link_wall_{x0}_{y0}", x0, y0, x1, y1, 1.2, 0, 0.6, "cover")
    m.spawn_row("A", -35, 0, 0, 0, n=6, spread=2.4, across=90, set_="main")
    m.spawn_row("B", 35, 0, 0, 180, n=6, spread=2.4, across=90, set_="main")
    # flipped spawn sets used while the hill is near a team's main spawn
    m.spawn_row("A", 0, 33, 0, 270, n=4, spread=2.4, across=0, set_="flip")
    m.spawn_row("B", 0, -33, 0, 90, n=4, spread=2.4, across=0, set_="flip")
    m.pickup("power_weapon", -30, 0)
    m.pickup("power_weapon_2", 30, 0)
    return m


def three_pylons():
    m = Map("three_pylons", "Three Pylons", ["Domination", "Strongholds", "Total Control"],
            "Archetype 2, static three zones (figure 8): A near one team's spawn, C near the other's, B in "
            "the middle as the main fight. Holding two of three outscores the enemy; taking their home point "
            "flips their spawns.")
    arena_floor(m, -48, 48, -32, 32, 6)
    m.spawn_row("A", -40, 24, 0, 270, n=6, spread=2.2, across=0, set_="home")
    m.spawn_row("B", 40, 24, 0, 270, n=6, spread=2.2, across=0, set_="home")
    m.spawn_row("A", -40, -25, 0, 90, n=6, spread=2.2, across=0, set_="flipped")
    m.spawn_row("B", 40, -25, 0, 90, n=6, spread=2.2, across=0, set_="flipped")
    # B: a central pylon house with three ways in.
    m.room("pylon_house_B", -8, 8, -8, 8, 5, [("W", 0, 4), ("E", 0, 4), ("S", 0, 4)], 0, 0.6, "hull")
    m.cyl("pylon_B", 0, 4, 0, 1, 9, "core", n=16)
    m.zone("B", 0, 0, 0, 4)
    # A and C: semi-open bunkers, each a U of walls opening toward the middle and toward home.
    for zid, s in (("A", -1), ("C", 1)):
        x = s * 28
        m.seg(f"bunker_{zid}_back", x + s * 7, -6, x + s * 7, 6, 3.5)
        m.seg(f"bunker_{zid}_s", x - s * 2, -7, x + s * 7, -7, 3.5)
        m.cyl(f"pylon_{zid}", x + s * 4, 3, 0, 0.8, 7, "core", n=16)
        m.zone(zid, x, 0, 0, 4)
        m.box(f"bunker_{zid}_cover", x - s * 6, 4, 0, 1, 3.5, 1.2, "cover")
    # mid power-up near B, the routes between with cover
    m.pickup("power_up", 0, -16)
    for x, y in ((-16, 10), (16, 10), (-16, -12), (16, -12), (-34, 10), (34, 10), (0, 20)):
        m.box(f"route_cover_{x}_{y}", x, y, 0, 3, 1, 1.4, "crate")
    m.rect("north_walk", -20, 20, 16, 17, 0, 3.5, "hull")
    return m


def supply_line():
    m = Map("supply_line", "Supply Line", ["Payload", "Escort", "Hybrid", "Rush", "Breakthrough"],
            "Archetype 3 (figure 10): one winding route in three sections, each with a choke the defenders "
            "can hold. Checkpoints add time and move both sides' spawns forward. Played once per side.")
    m.rect("ground", -100, 100, -40, 40, -0.6, 0, "floor")
    path = [(x, 16 * math.sin(x / 100 * math.pi * 1.5)) for x in range(-92, 96, 8)]
    for i in range(len(path) - 1):
        m.seg(f"track_{i}", *path[i], *path[i + 1], 0.08, 0.01, 2.0, "path", "Markers")
    for i, (x, y) in enumerate(path[::2], 1):
        m.beacon("path", f"route_{i:02d}", x, y, 0, "path", 0.3, 0.35, None, order=i)
    cart = m.box("cart", path[0][0], path[0][1], 0, 2.4, 1.6, 1.4, "objective", "Markers")
    cart["pos"] = (path[0][0], path[0][1], 0)
    m.marker(cart, "cart", note="Payload cart / Escort payload: speeds up with up to 3 pushers")
    m.label("Cart", path[0][0], path[0][1] - 2.5, 1.8, 1.4)
    yat = lambda x: 16 * math.sin(x / 100 * math.pi * 1.5)
    # Chokes: two buildings either side of the route before each checkpoint.
    for k, cx in enumerate((-40, 22, 76), 1):
        y = yat(cx)
        m.box(f"choke_{k}_n", cx, y + 9, 0, 10, 8, 7, "hull")
        m.box(f"choke_{k}_s", cx, y - 9, 0, 10, 8, 7, "hull")
        m.box(f"choke_{k}_bridge", cx, y, 6, 4, 10, 1, "hull")
    for k, (cx, txt) in enumerate(((-30, "CP1"), (32, "CP2"), (90, "Final")), 1):
        m.disc_marker("checkpoint", f"checkpoint_{k}", cx, yat(cx), 0, 4, "zone", f"{txt}: +time, spawns move", order=k)
    # Hybrid's first capture point at the start of the route.
    m.zone("hybrid", -78, yat(-78) + 8, 0, 4)
    # Rush: two charge stations per section.
    for k, cx in enumerate((-50, 10, 66), 1):
        for j, dy in enumerate((12, -12)):
            m.beacon("charge", f"rush_charge_{k}{'ab'[j]}", cx, yat(cx) + dy, 0, "objective", 1.4, 0.6, f"Charge {k}{'AB'[j]}", id=f"{k}{'ab'[j]}", mode="Rush")
    # Health packs along the route.
    for i, x in enumerate((-60, -10, 45)):
        m.resupply(f"health_{i}", x, yat(x) - 6)
    # Cover along the route, and side buildings for each section's terrain.
    for x in range(-84, 96, 12):
        m.box(f"route_cover_{x}", x, yat(x) + (6 if (x // 12) % 2 else -6), 0, 3, 1, 1.3, "cover", rot=math.radians(20))
    for x, y in ((-70, -30), (-55, 30), (-5, -30), (5, 32), (55, -32), (60, 30)):
        m.box(f"bldg_{x}_{y}", x, y, 0, 14, 10, 6, "hull")
    m.spawn_row("attack", -96, 0, 0, 0, n=6, spread=2.4, across=90, set_="section_1")
    m.spawn_row("attack", -36, -26, 0, 90, n=6, spread=2.0, across=0, set_="section_2")
    m.spawn_row("attack", 26, -26, 0, 90, n=6, spread=2.0, across=0, set_="section_3")
    for k, x in enumerate((-30, 32, 88), 1):
        m.spawn_row("defend", x, -34, 0, 90, n=6, spread=2.0, across=0, set_=f"section_{k}")
    return m


def lattice():
    m = Map("lattice", "Lattice", ["Onslaught", "Warfare", "Conquest"],
            "Archetype 4 (figure 12): a power core per team and power nodes between them in a chain. A node "
            "can be built or attacked only if it links to your core or a node you hold; the enemy core is open "
            "only while you hold a node linked to it. The closest model to Teal Galaxy's lattice. Vehicles.")
    m.rect("ground", -135, 135, -75, 75, -0.6, 0, "floor")
    NODES = {"red_core": (-115, 0), "n1": (-60, 40), "n2": (-60, -40), "n3": (0, 0), "n4": (60, 40), "n5": (60, -40), "blue_core": (115, 0)}
    LINKS = [("red_core", "n1"), ("red_core", "n2"), ("n1", "n3"), ("n2", "n3"), ("n3", "n4"), ("n3", "n5"), ("n4", "blue_core"), ("n5", "blue_core")]
    for a, b in LINKS:
        m.seg(f"link_{a}_{b}", *NODES[a], *NODES[b], 0.06, 0.01, 0.6, "path", "Markers")
    for team, key in (("A", "red_core"), ("B", "blue_core")):
        x, y = NODES[key]
        m.cyl(f"{key}_base", x, y, 0, 9, 1.2, "floor2", n=40)
        ob = m.cyl(key, x, y, 1.2, 3, 10, team, "Markers", n=24)
        ob["pos"] = (x, y, 1.2)
        m.marker(ob, "power_core", team=team, hp=5000, links=[l[1] if l[0] == key else l[0] for l in LINKS if key in l])
        m.label("Red Core" if team == "A" else "Blue Core", x, y - 12, 1.5, 2.5)
        s = -1 if team == "A" else 1
        m.spawn_row(team, x + s * 14, 0, 0, 0 if s < 0 else 180, n=8, spread=2.5, across=90)
        for j, dy in enumerate((-16, 16)):
            ob = m.rect(f"vehicle_pad_{team}_{j}", x - 4, x + 4, y + dy - 3, y + dy + 3, 0, 0.15, "lift", "Markers")
            ob["pos"] = (x, y + dy, 0)
            m.marker(ob, "vehicle_pad", team=team)
        m.beacon("pickup", f"orb_{team}", x + s * 8, 12, 0, "pickup", 1.0, 0.5, "Orb", item="orb", note="Warfare: captures a node at once")
    for key in ("n1", "n2", "n3", "n4", "n5"):
        x, y = NODES[key]
        m.cyl(f"{key}_pad", x, y, 0, 6, 0.8, "floor2", n=32)
        ob = m.cyl(key, x, y, 0.8, 1.5, 5, "zone", "Markers", n=16)
        ob["pos"] = (x, y, 0.8)
        m.marker(ob, "node", hp=2000, links=[l[1] if l[0] == key else l[0] for l in LINKS if key in l])
        m.label(f"Node {key[1]}", x, y - 8, 1.0, 2.2)
    for key, x, y, note in (("side_vehicle", 0, 58, "vehicle node"), ("side_countdown", 0, -58, "countdown node")):
        m.cyl(f"{key}_pad", x, y, 0, 5, 0.8, "floor2", n=32)
        ob = m.cyl(key, x, y, 0.8, 1.2, 4, "pickup", "Markers", n=16)
        ob["pos"] = (x, y, 0.8)
        m.marker(ob, "node", hp=2000, side_node=note, links=[])
        m.label(f"Side node: {note}", x, y - 7, 1.0, 1.8)
    # Terrain for vehicles: ridges and rock outcrops, out of the link lines.
    for i, (x, y, sx, sy, h, r) in enumerate([(-88, 30, 18, 8, 5, 30), (-88, -30, 18, 8, 5, -30), (88, 30, 18, 8, 5, -30), (88, -30, 18, 8, 5, 30),
                                              (-30, 0, 10, 24, 7, 0), (30, 0, 10, 24, 7, 0), (-30, 60, 30, 10, 9, 0), (30, -60, 30, 10, 9, 0),
                                              (-100, 55, 20, 14, 10, 0), (100, -55, 20, 14, 10, 0)]):
        m.box(f"rock_{i}", x, y, 0, sx, sy, h, "hull", rot=math.radians(r))
    return m


def foundry_spire():
    m = Map("foundry_spire", "Foundry Spire", ["Deathmatch", "FFA", "Duel", "Clan Arena", "Freeze Tag", "Invasion"],
            "A kill-count arena in the Quake tradition: many loops, no single choke, high verticality on three "
            "levels with jump routes, and item timing (armour, mega health, the power-up) as the objective.")
    arena_floor(m, -26, 26, -26, 26, 15)
    L1, L2 = 5.0, 10.0
    # level 1: four corner platforms joined by edge walkways
    for sx in (-1, 1):
        for sy in (-1, 1):
            m.rect(f"l1_corner_{sx}_{sy}", *sorted((sx * 25.6, sx * 13)), *sorted((sy * 25.6, sy * 13)), L1 - 0.5, L1, "floor2")
    for sy in (-1, 1):
        m.rect(f"l1_walk_{sy}", -13, 13, *sorted((sy * 25.6, sy * 22)), L1 - 0.5, L1, "floor2")
    # level 2: a bridge over the middle, north to south, on the west side; a platform east
    m.rect("l2_bridge", -10, -6, -25.6, 25.6, L2 - 0.5, L2, "floor2")
    m.rect("l2_east", 14, 25.6, -6, 6, L2 - 0.5, L2, "floor2")
    for x0, x1 in ((-10.2, -10), (-6, -5.8)):
        m.rect(f"l2_rail_{x0}", x0, x1, -13, 13, L2, L2 + 1.1, "glass")
    # ramps: floor to level 1 in two corners, level 1 to level 2 at the bridge ends
    m.ramp("ramp_f1_sw", -4, -18, -13, -18, 3, 0, L1, 0)
    m.ramp("ramp_f1_ne", 4, 18, 13, 18, 3, 0, L1, 0)
    m.ramp("ramp_12_s", -17, -16, -17, -24, 3, L1, L2, L1 - 0.5)
    m.ramp("ramp_12_e", 19, 13, 19, 6, 3, L1, L2, L1 - 0.5)
    # the pit: a sunken middle loop with pillars
    for x, y in ((6, 6), (6, -6), (-2, 0)):
        m.box(f"pillar_{x}_{y}", x, y, 0, 2, 2, L2 + 3, "hull")
    for x, y in ((14, -16), (-18, 8), (16, 10)):
        m.box(f"floor_cover_{x}_{y}", x, y, 0, 3, 1, 1.3, "cover", rot=math.radians(30))
    jump_pad(m, 1, 2, -12, 0, (-8, -12, L2), "floor to the bridge")
    jump_pad(m, 2, 10, 0, 0, (20, 0, L2), "floor to the east platform")
    jump_pad(m, 3, -20, 0, 0, (-20, 18, L1), "floor to level 1")
    m.pickup("heavy_armour", 20, 0, L2)
    m.pickup("mega_health", 0, 0, 0)
    m.pickup("power_up", -8, 0, L2)
    m.pickup("light_armour", -20, -20, L1)
    for i, (x, y, z) in enumerate([(-22, 22, L1), (22, -22, L1), (22, 22, L1), (-22, -22, L1), (0, 24, L1), (0, -24, L1),
                                   (-22, 0, 0), (22, -10, 0), (12, 22, 0), (-12, -22, 0), (-8, 20, L2), (20, 4, L2)], 1):
        m.spawn("ffa", i, x, y, z, math.degrees(math.atan2(-y, -x)), "ffa")
    return m


def longwatch():
    m = Map("longwatch", "Longwatch", ["Instagib"],
            "Instagib map: every hit kills, so long sightlines and verticality, with tracking and dodging the "
            "skill. Towers at each end and in the middle, catwalks on the walls, little cover.")
    arena_floor(m, -60, 60, -20, 20, 16)
    for x in (-48, 0, 48):
        h = 12 if x == 0 else 8
        m.rect(f"tower_{x}", x - 4, x + 4, -4, 4, 0, h, "hull")
        # ramps run inward from each end tower; the middle tower has one from each side
        for d, y in ([(1, 9)] if x < 0 else [(-1, -9)] if x > 0 else [(1, 9), (-1, -9)]):
            m.ramp(f"tower_{x}_ramp_{d}", x + d * 20, y, x + d * 4, y, 3, 0, h, 0)
            m.rect(f"tower_{x}_link_{d}", *sorted((x, x + d * 4)), *((4, y + 1.5) if y > 0 else (y - 1.5, -4)), h - 0.5, h, "floor2")
    for y in (-18, 18):
        m.rect(f"catwalk_{y}", -56, 56, *sorted((y, y - 3 if y > 0 else y + 3)), 5.5, 6, "floor2")
    m.rect("bridge_mid", -1.5, 1.5, -18, 18, 7.5, 8, "glass")
    for i, x in enumerate((-30, -14, 14, 30)):
        jump_pad(m, i + 1, x, 12 if i % 2 else -12, 0, (x, 16.5 if i % 2 else -16.5, 6), "floor to the catwalk")
    for x, y in ((-24, 0), (24, 0), (-36, -10), (36, 10)):
        m.box(f"cover_{x}_{y}", x, y, 0, 1, 4, 1.4, "cover")
    for i, (x, y, z) in enumerate([(-56, 0, 0), (56, 0, 0), (-48, 0, 8), (48, 0, 8), (-30, 18, 6), (30, -18, 6), (0, 0, 12), (-10, -14, 0),
                                   (10, 14, 0), (-40, -16, 6), (40, 16, 6), (0, 18, 6)], 1):
        m.spawn("ffa", i, x, y, z, 0 if x < 0 else 180, "ffa")
    return m


def crossfire_box():
    m = Map("crossfire_box", "Crossfire Box", ["Gun Game"],
            "Gun Game map: small and symmetrical so nobody has an edge. Four-way symmetry round a central block.")
    arena_floor(m, -18, 18, -18, 18, 5)
    m.box("centre_block", 0, 0, 0, 5, 5, 3.5, "hull")
    for a in range(0, 360, 90):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        m.box(f"corner_box_{a}", 11 * (c - s), 11 * (s + c), 0, 3, 3, 2.6, "crate")
        m.box(f"low_cover_{a}", 9 * c, 9 * s, 0, 1, 4, 1.2, "cover", rot=math.radians(a))
        m.box(f"edge_wall_{a}", 15 * c - 6 * s, 15 * s + 6 * c, 0, 1, 5, 2.4, "hull", rot=math.radians(a))
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        m.spawn("ffa", i + 1, 15 * math.cos(a), 15 * math.sin(a), 0, math.degrees(a) + 180, "ffa")
    return m


def nest_loop():
    m = Map("nest_loop", "Nest Loop", ["Oddball", "King of the Hill", "Strongholds"],
            "Oddball map: a compact loop, the ball spawns in the middle, and several nests where a carrier can "
            "be shielded by teammates. Each nest can be broken from at least two directions.")
    arena_floor(m, -32, 32, -30, 30, 7)
    m.beacon("ball", "ball_spawn", 0, 0, 0, "objective", 1.0, 0.45, "Ball")
    m.ring_wall("loop_inner", 8, 8.6, 0, 3.5, [(0, 4), (90, 4), (180, 4), (270, 4)])
    # four nests, each with two ways in
    nests = [("Upper Room", 20, 18, 3.5), ("Bunker", -20, -18, 0), ("Balcony", -20, 18, 3.5), ("Pit", 20, -18, -0.0)]
    for i, (name, x, y, z) in enumerate(nests, 1):
        sx, sy = (1 if x > 0 else -1), (1 if y > 0 else -1)
        if z > 0:
            m.rect(f"nest_{i}_floor", x - 6, x + 6, y - 5, y + 5, 0, z, "floor2")
            m.ramp(f"nest_{i}_ramp_a", x - sx * 14, y - sy * 2, x - sx * 6, y - sy * 2, 3, 0, z, 0)
            m.ramp(f"nest_{i}_ramp_b", x + sx * 2, y - sy * 13, x + sx * 2, y - sy * 5, 3, 0, z, 0)
            m.rect(f"nest_{i}_rail", *sorted((x - sx * 6, x + sx * 1)), *sorted((y - sy * 5, y - sy * 5.3)), z, z + 1.1, "glass")
        else:
            m.room(f"nest_{i}_walls", x - 6, x + 6, y - 5, y + 5, 3.5, [("N" if sy < 0 else "S", x, 3), ("E" if sx < 0 else "W", y, 3)], 0, 0.5)
        ob = m.disc_marker("nest", f"nest_{i}", x, y, z, 2.5, "hill", name)
    m.spawn_row("A", -29, 0, 0, 0, n=6, spread=2.4, across=90)
    m.spawn_row("B", 29, 0, 0, 180, n=6, spread=2.4, across=90)
    for zid, (x, y) in zip("ABC", ((-12, 2), (0, 16), (12, -2))):
        m.zone(zid, x, y, 0, 3)
    for i, (x, y, z) in enumerate(((0, -16, 0), (20, 18, 3.5), (-20, -18, 0)), 1):
        m.hill(i, x, y, z, 2.5, "KotH")
    return m


def relay_sites():
    m = Map("relay_sites", "Relay Sites", ["Search and Destroy", "Bomb defusal"],
            "Bomb map: asymmetric by role, fair over a match. Attackers start on one side with two or more "
            "routes to each of two sites; defenders start nearer the sites and must split. Sides swap at half.")
    arena_floor(m, -50, 50, -50, 50, 7)
    for side, x in (("A", -26), ("B", 26)):
        m.disc_marker("charge", f"site_{side}", x, 26, 0, 5, "objective", f"Site {side}", id=side)
        m.box(f"site_{side}_crate1", x - 3, 28, 0, 2.4, 2.4, 1.6, "crate")
        m.box(f"site_{side}_crate2", x + 4, 23, 0, 3, 1, 1.3, "cover")
        m.box(f"site_{side}_stack", x + 1, 31, 0, 2.4, 2.4, 3.2, "crate")
    m.spawn_row("attack", 0, -46, 0, 90, n=5, spread=3.0, set_="round_start")
    m.spawn_row("defend", 0, 44, 0, 270, n=5, spread=3.0, set_="round_start")
    # Buildings that make the routes: A long (west), A short via mid, mid, B short, B long (east).
    for name, x0, x1, y0, y1 in [("west_block", -38, -14, -20, 8), ("mid_west", -10, -4, -30, 14), ("mid_east", 4, 10, -30, 14),
                                 ("east_block", 14, 38, -20, 8), ("north_mid", -12, 12, 22, 34)]:
        m.rect(f"bldg_{name}", x0, x1, y0, y1, 0, 6, "hull")
    m.room("a_short_room", -14, -4, 8, 18, 4, [("S", -9, 3), ("W", 13, 3)], 0, 0.5)
    m.room("b_short_room", 4, 14, 8, 18, 4, [("S", 9, 3), ("E", 13, 3)], 0, 0.5)
    for x, y in ((-44, -10), (44, -10), (0, -10), (0, 10), (-20, -32), (20, -32)):
        m.box(f"route_cover_{x}_{y}", x, y, 0, 3, 1, 1.4, "cover")
    for txt, x, y in [("A Long", -44, 0), ("A Short", -9, 6), ("Mid", 0, -2), ("B Short", 9, 6), ("B Long", 44, 0)]:
        m.callout(txt, x, y)
    return m


def tug_line():
    m = Map("tug_line", "Tug Line", ["Push"],
            "Push map: long and mirrored with one central track. A robot in the middle pushes a barricade "
            "toward whichever team's spawn it moves; forward spawns open after each checkpoint.")
    arena_floor(m, -80, 80, -26, 26, 7)
    m.rect("track", -72, 72, -1, 1, 0, 0.1, "path", "Markers")
    ob = m.box("robot", 0, 0, 0.1, 2.4, 2.4, 2.6, "objective", "Markers")
    ob["pos"] = (0, 0, 0)
    m.marker(ob, "robot", note="about 1.22 m/s while pushed")
    m.label("Robot", 0, -3.5, 3, 1.5)
    for x in (-60, -30, 30, 60):
        ob = m.box(f"barricade_cp_{x}", x, 0, 0, 0.6, 6, 2, "zone", "Markers")
        ob["pos"] = (x, 0, 0)
        m.marker(ob, "checkpoint", order=abs(x) // 30, toward="A" if x < 0 else "B")
    for s, team in ((-1, "A"), (1, "B")):
        m.spawn_row(team, s * 76, 0, 0, 0 if s < 0 else 180, n=6, spread=3, across=90, set_="main")
        m.spawn_row(team, s * 45, 18, 0, 0 if s < 0 else 180, n=4, spread=2.5, across=0, set_="forward")
    # Flank routes parallel to the track, separated by buildings with crossings.
    for s in (-1, 1):
        for x0, x1 in ((-66, -44), (-22, -8), (8, 22), (44, 66)):
            m.rect(f"bldg_{s}_{x0}", x0, x1, *sorted((s * 7, s * 13)), 0, 6, "hull")
    for x in (-52, -15, 15, 52):
        m.box(f"track_cover_{x}", x, 4, 0, 3, 1, 1.3, "cover")
        m.box(f"track_cover_s_{x}", -x, -4, 0, 3, 1, 1.3, "cover")
    return m


def goal_field():
    m = Map("goal_field", "Goal Field", ["Bombing Run"],
            "Bombing Run map: a long symmetric field like a CTF map, but with one ball in the centre and a "
            "hoop at each end. Carry it through for 7, throw it through for 3: the area by each hoop matters most.")
    arena_floor(m, -64, 64, -28, 28, 6)
    m.beacon("ball", "ball_spawn", 0, 0, 0, "objective", 1.0, 0.45, "Ball")
    for s, team in ((-1, "A"), (1, "B")):
        x = s * 56
        # the hoop: a frame standing in the goal mouth, 4 m up
        for y in (-3, 3):
            m.box(f"hoop_{team}_post{y}", x, y, 0, 0.6, 0.6, 7, "hull")
        m.rect(f"hoop_{team}_top", x - 0.3, x + 0.3, -3, 3, 7, 7.5, team)
        m.rect(f"hoop_{team}_bottom", x - 0.3, x + 0.3, -3, 3, 3, 3.4, team)
        ob = m.rect(f"hoop_{team}", x - 0.1, x + 0.1, -2.7, 2.7, 3.4, 7, "glass", "Markers")
        ob["pos"] = (x, 0, 3.4)
        m.marker(ob, "hoop", team=team, carry=7, throw=3)
        # galleries either side for the long throw, and cover round the hoop
        m.rect(f"gallery_{team}_n", *sorted((s * 40, s * 50)), 14, 22, 0, 3.5, "floor2")
        m.rect(f"gallery_{team}_s", *sorted((s * 40, s * 50)), -22, -14, 0, 3.5, "floor2")
        m.ramp(f"gallery_{team}_ramp_n", s * 30, 18, s * 40, 18, 3, 0, 3.5, 0)
        m.ramp(f"gallery_{team}_ramp_s", s * 30, -18, s * 40, -18, 3, 0, 3.5, 0)
        for y in (-8, 8):
            m.box(f"hoop_cover_{team}_{y}", s * 48, y, 0, 1, 4, 1.4, "cover")
        m.spawn_row(team, s * 61, 0, 0, 0 if s < 0 else 180, n=6, spread=3.5, across=90)
    for x, y in ((-20, 10), (20, -10), (-20, -10), (20, 10), (0, 16), (0, -16)):
        m.box(f"field_cover_{x}_{y}", x, y, 0, 4, 1, 1.4, "crate")
    return m


def attrition_front():
    m = Map("attrition_front", "Attrition Front", ["Attrition"],
            "Attrition map: larger, with AI soldiers in the middle so even weaker players have targets that "
            "score. Pilot kills are worth more than AI; team spawns at the ends, AI squads in the contested belt.")
    m.rect("ground", -85, 85, -55, 55, -0.6, 0, "floor")
    m.rect("belt", -40, 40, -55, 55, 0, 0.02, "floor2")
    for s, team in ((-1, "A"), (1, "B")):
        m.spawn_row(team, s * 78, 0, 0, 0 if s < 0 else 180, n=8, spread=3, across=90)
        for j, y in enumerate((-30, 30)):
            ob = m.rect(f"heavy_drop_{team}_{j}", s * 64 - 5, s * 64 + 5, y - 5, y + 5, 0, 0.12, "lift", "Markers")
            ob["pos"] = (s * 64, y, 0)
            m.marker(ob, "heavy_drop", team=team, note="drop zone for a heavy unit, worth more points")
    # AI squads in the middle belt, two per side per lane.
    for s, team in ((-1, "A"), (1, "B")):
        for j, y in enumerate((-36, -12, 12, 36)):
            ob = m.cyl(f"ai_squad_{team}_{j}", s * 22, y, 0.02, 3, 0.1, team, "Markers", n=16)
            ob["pos"] = (s * 22, y, 0)
            m.marker(ob, "ai_spawn", team=team, size=4)
            m.label("AI squad", s * 22, y - 4, 0.3, 1.1)
    # Buildings for the pilots, open ground for the heavies.
    for i, (x, y, sx, sy, h) in enumerate([(0, 0, 14, 10, 8), (-30, 40, 12, 10, 6), (30, -40, 12, 10, 6), (-30, -22, 8, 8, 10),
                                           (30, 22, 8, 8, 10), (-55, 10, 10, 18, 5), (55, -10, 10, 18, 5), (0, 40, 10, 6, 4), (0, -40, 10, 6, 4)]):
        m.box(f"bldg_{i}", x, y, 0, sx, sy, h, "hull")
        if h >= 8:
            m.ramp(f"bldg_{i}_ramp", x - sx / 2 - 10, y, x - sx / 2, y, 3, 0, h, 0)
    for x in range(-36, 40, 12):
        m.box(f"belt_cover_{x}", x, (x * 7) % 30 - 15, 0, 3, 1, 1.3, "cover", rot=math.radians(x * 3))
    return m


MAPS = {
    "ring": high_port_ring,
    "dock": carrier_dock_pads,
    "hangar": hangar_flight_deck,
    "vault": outpost_vault,
    "boarding": carrier_boarding,
    "outpost": besieged_outpost,
    "bastions": twin_bastions,
    "spindle": spindle_yard,
    "pylons": three_pylons,
    "supply": supply_line,
    "lattice": lattice,
    "spire": foundry_spire,
    "longwatch": longwatch,
    "crossfire": crossfire_box,
    "nest": nest_loop,
    "sites": relay_sites,
    "tug": tug_line,
    "goal": goal_field,
    "attrition": attrition_front,
}

# --- Planet terrain -----------------------------------------------------------------------------
# The outdoor maps stand on a planet, built the way the game's own surface is (game/terrain.gd and
# game/battle/battle_terrain.gd): faceted ground in the world's palette, gentle relief where the
# fight is, flattened under every building, spawn and objective, then rising past the edge of play
# into a rim, rolling high ground, ridged peaks, mesas and a cliff or a ledge on one side, with
# boulders (and ice on frost worlds) scattered over it. Seeded by the map id, so it's the same
# every build.

from mathutils import noise as _noise  # noqa: E402

# The game's world palettes (battle_terrain.gd): low ground, high ground, rock, peaks, sky, sun.
WORLDS = {
    "frost": {"low": (0.42, 0.47, 0.53), "high": (0.62, 0.67, 0.75), "rock": (0.25, 0.27, 0.32), "peak": (0.86, 0.9, 0.96),
              "sky": (0.55, 0.66, 0.8), "sun": (1.0, 0.95, 0.88)},
    "dust": {"low": (0.56, 0.42, 0.27), "high": (0.68, 0.55, 0.37), "rock": (0.36, 0.25, 0.18), "peak": (0.78, 0.66, 0.5),
             "sky": (0.62, 0.52, 0.42), "sun": (1.0, 0.86, 0.7)},
    "moss": {"low": (0.27, 0.36, 0.2), "high": (0.4, 0.45, 0.27), "rock": (0.32, 0.3, 0.27), "peak": (0.66, 0.66, 0.62),
             "sky": (0.42, 0.58, 0.78), "sun": (1.0, 0.96, 0.86)},
    "ash": {"low": (0.27, 0.26, 0.26), "high": (0.38, 0.36, 0.35), "rock": (0.16, 0.15, 0.15), "peak": (0.52, 0.47, 0.44),
            "sky": (0.36, 0.28, 0.27), "sun": (1.0, 0.8, 0.62)},
}

# Which maps are outdoors, on what kind of world. Station and carrier interiors, and the enclosed
# arenas, stay as they are.
#   relief: metres of rolling ground inside the play area (0 = flat, like a built pad)
#   strip: objects that stand in for ground or for the arena's boundary walls, replaced by terrain
#   rim: a steep bank just past the edge of play, where the walls were
OUTDOOR = {
    "carrier_dock_pads": {"world": "frost", "relief": 0.0, "strip": [], "rim": 0},
    "outpost_vault": {"world": "frost", "relief": 0.0, "strip": [], "rim": 0},
    "besieged_outpost": {"world": "ash", "relief": 0.8, "strip": ["ground"], "rim": 0},
    "twin_bastions": {"world": "moss", "relief": 0.6, "strip": ["floor", "perimeter"], "rim": 9},
    "supply_line": {"world": "dust", "relief": 1.6, "strip": ["ground"], "rim": 10},
    "lattice": {"world": "moss", "relief": 3.5, "strip": ["ground"], "rim": 0},
    "relay_sites": {"world": "dust", "relief": 0.4, "strip": ["floor", "perimeter"], "rim": 9},
    "attrition_front": {"world": "ash", "relief": 1.8, "strip": ["ground", "belt"], "rim": 8},
}


def _smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def _mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def add_terrain(m, cfg, lo, hi):
    import numpy as np

    world = WORLDS[cfg["world"]]
    seed = sum(ord(c) * (i + 7) for i, c in enumerate(m.id))
    off = Vector(((seed % 997) * 13.1, (seed % 389) * 7.7, 0))
    rng = __import__("random").Random(seed)

    # Footprints of everything that stands on the ground: the terrain flattens round them.
    for name in cfg["strip"]:
        for ob in [o for o in bpy.data.objects if o.name == name or o.name.startswith(name + ".")]:
            bpy.data.objects.remove(ob)
    boxes = []
    for ob in bpy.data.objects:
        if ob.type != "MESH" or ob.users_collection[0].name not in ("Geometry", "Markers", "Surface", "Roofs", "Deck"):
            continue
        xs = [(ob.matrix_world @ Vector(c)) for c in ob.bound_box]
        boxes.append((min(v.x for v in xs), max(v.x for v in xs), min(v.y for v in xs), max(v.y for v in xs)))
    B = np.array(boxes) if boxes else np.zeros((0, 4))

    play = (lo.x, hi.x, lo.y, hi.y)
    span = max(hi.x - lo.x, hi.y - lo.y)
    skirt = max(90.0, span * 0.55)
    cell = max(2.0, (span + 2 * skirt) / 170)
    nx = int((hi.x - lo.x + 2 * skirt) / cell) + 1
    ny = int((hi.y - lo.y + 2 * skirt) / cell) + 1
    X = np.linspace(lo.x - skirt, hi.x + skirt, nx)
    Y = np.linspace(lo.y - skirt, hi.y + skirt, ny)
    GX, GY = np.meshgrid(X, Y)
    px, py = GX.ravel(), GY.ravel()
    # distance to the nearest footprint, and how far outside the play area
    if len(B):
        dx = np.maximum(np.maximum(B[:, 0][None] - px[:, None], px[:, None] - B[:, 1][None]), 0)
        dy = np.maximum(np.maximum(B[:, 2][None] - py[:, None], py[:, None] - B[:, 3][None]), 0)
        near = np.sqrt(dx * dx + dy * dy).min(axis=1)
    else:
        near = np.full(px.shape, 1e9)
    ox = np.maximum(np.maximum(play[0] - px, px - play[1]), 0)
    oy = np.maximum(np.maximum(play[2] - py, py - play[3]), 0)
    out = np.sqrt(ox * ox + oy * oy)

    # One side gets a cliff (or a ledge), as on the game's bases; the peaks crowd some sides.
    cliff_ang = rng.uniform(0, 2 * math.pi)
    cliff_dir = (math.cos(cliff_ang), math.sin(cliff_ang))
    cliff_h = rng.uniform(22, 40) * (-0.6 if rng.random() < 0.3 else 1)
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    half = Vector(((hi.x - lo.x) / 2, (hi.y - lo.y) / 2, 0))

    H = np.zeros(px.shape)
    for i in range(len(px)):
        x, y, d = px[i], py[i], out[i]
        p = Vector((x * 0.012, y * 0.012, 0)) + off
        roll = _noise.fractal(p, 1.0, 2.0, 3, noise_basis="PERLIN_NEW")
        detail = _noise.noise(Vector((x * 0.09, y * 0.09, 3.0)) + off)
        # inside: gentle relief, flat under and round anything built or marked
        flat = _smooth(2.0, 14.0, near[i])
        h_in = (roll * cfg["relief"] + detail * 0.15 * cfg["relief"]) * flat
        if d <= 0:
            H[i] = max(h_in, -0.4 * cfg["relief"]) - 0.05
            continue
        o = _smooth(0.0, 30.0, d)
        far = _smooth(15.0, skirt * 0.8, d)
        ang = math.atan2(y - cy, x - cx)
        side = _noise.noise(Vector((math.cos(ang) * 1.3, math.sin(ang) * 1.3, 9.0)) + off) * 0.5 + 0.5
        far *= _smooth(0.2, 0.7, side) * 0.8 + 0.2
        ridge = _noise.ridged_multi_fractal(Vector((x * 0.008, y * 0.008, 1.0)) + off, 1.0, 2.0, 4, 1.0, 2.0, noise_basis="PERLIN_NEW")
        h = roll * 6.0 + detail * 1.2 + max(0.0, ridge - 0.6) ** 1.6 * (10.0 + 70.0 * far)
        mesa = _noise.noise(Vector((x * 0.015, y * 0.015, 5.0)) + off)
        if mesa > 0.3:
            h = max(h, (12.0 + 10.0 * far) * _smooth(0.3, 0.38, mesa) + detail * 0.6)
        s = (x - cx) * cliff_dir[0] + (y - cy) * cliff_dir[1] - (abs(half.x * cliff_dir[0]) + abs(half.y * cliff_dir[1])) - 25
        h += _smooth(0.0, 6.0, s - _noise.noise(Vector((x * 0.03, y * 0.03, 7.0)) + off) * 12) * cliff_h
        H[i] = h_in * (1 - o) + h * o - 0.05
        # the rim: a steep bank where an arena wall stood, so the play area keeps its edge
        if cfg["rim"]:
            H[i] = max(H[i], cfg["rim"] * _smooth(0.0, 5.0, d) + detail * 1.0)

    # Faceted mesh with vertex colours by height and slope.
    Z = H.reshape(ny, nx)
    verts = [(float(X[i]), float(Y[j]), float(Z[j, i])) for j in range(ny) for i in range(nx)]
    faces = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces += [(a, a + 1, a + nx + 1), (a, a + nx + 1, a + nx)]
    me = bpy.data.meshes.new("terrain")
    me.from_pydata(verts, [], faces)
    me.update()
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    zmax = max(10.0, float(H.max()))
    for poly in me.polygons:
        vz = [verts[v][2] for v in poly.vertices]
        n = poly.normal
        steep = 1.0 - abs(n.z)
        hz = sum(vz) / 3
        c = _mix(world["low"], world["high"], _smooth(-2.0, 14.0, hz))
        c = _mix(c, world["rock"], _smooth(0.25, 0.5, steep))
        c = _mix(c, world["peak"], _smooth(zmax * 0.55, zmax * 0.85, hz) * (1 - _smooth(0.35, 0.6, steep)))
        jit = 0.9 + 0.2 * ((poly.index * 2654435761) % 1000) / 1000
        for li in poly.loop_indices:
            col.data[li].color = (c[0] * jit, c[1] * jit, c[2] * jit, 1)
    mat_t = bpy.data.materials.new("terrain")
    mat_t.use_nodes = True
    nt = mat_t.node_tree
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.95
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat_t)
    ob = bpy.data.objects.new("terrain", me)
    m.coll("Terrain").objects.link(ob)
    ob["kind"] = "terrain"
    ob["world"] = cfg["world"]

    # Boulders over the high ground and the edges of play, and ice on frost worlds.
    def height(x, y):
        i = min(nx - 1, max(0, int(round((x - X[0]) / (X[1] - X[0])))))
        j = min(ny - 1, max(0, int(round((y - Y[0]) / (Y[1] - Y[0])))))
        return float(Z[j, i]), float(near[j * nx + i]), float(out[j * nx + i])

    placed = 0
    for k in range(900):
        x = rng.uniform(X[0], X[-1])
        y = rng.uniform(Y[0], Y[-1])
        z, nr, d = height(x, y)
        if nr < 6 or d < 6:  # nothing loose inside the play area
            continue
        r = rng.uniform(1.5, 6.0)
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
        for v in bm.verts:
            v.co *= 1.0 + rng.uniform(-0.3, 0.3)
            v.co.z *= 0.65
            v.co += Vector((x, y, z + r * 0.25))
        rme = bpy.data.meshes.new(f"boulder_{k}")
        bm.to_mesh(rme)
        bm.free()
        rme.materials.append(mat("rock_" + cfg["world"]) if ("rock_" + cfg["world"]) in COLOURS else mat("hull"))
        rob = bpy.data.objects.new(f"boulder_{k}", rme)
        m.coll("Terrain").objects.link(rob)
        placed += 1
        if cfg["world"] == "frost" and d > 0 and rng.random() < 0.35:
            m.box(f"ice_{k}", x + r, y, z, 0.8, 0.8, rng.uniform(3, 7), "ice", "Terrain", rot=rng.uniform(0, 3))
        if placed > 260:
            break
    return world


for _w, _p in WORLDS.items():
    COLOURS["rock_" + _w] = (_p["rock"], 0)
COLOURS["ice"] = ((0.55, 0.8, 0.95), 0.4)


# --- Output -------------------------------------------------------------------------------------


def bounds():
    lo, hi = Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    for ob in bpy.context.scene.objects:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            v = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, v))
            hi = Vector(map(max, hi, v))
    return lo, hi


def setup_render():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.045, 0.07, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.8
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(38), math.radians(12), math.radians(35))
    sc.collection.objects.link(sun)
    try:
        sc.view_settings.view_transform = "AgX"
    except TypeError:
        pass


def camera(name, ortho=None):
    cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    bpy.context.scene.collection.objects.link(cam)
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    cam.data.clip_end = 2000
    return cam


def render(m, path, cam, res, hidden):
    sc = bpy.context.scene
    for c in m.colls.values():
        c.hide_render = c.name in hidden
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    for c in m.colls.values():
        c.hide_render = False


def build(key):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    m = MAPS[key]()
    sc = bpy.context.scene
    sc["arena_map"] = json.dumps({"id": m.id, "name": m.name, "modes": m.modes, "notes": m.notes})
    lo, hi = bounds()
    centre = (lo + hi) / 2
    size = max(hi.x - lo.x, hi.y - lo.y)
    os.makedirs(OUT, exist_ok=True)
    base = os.path.join(OUT, m.id)

    setup_render()
    outdoor = OUTDOOR.get(m.id)
    if outdoor:
        world = add_terrain(m, outdoor, lo, hi)
        sky = world["sky"]
        sc.world.node_tree.nodes["Background"].inputs[0].default_value = (sky[0] * 0.35, sky[1] * 0.35, sky[2] * 0.35, 1)
        sun = bpy.data.objects["Sun"]
        sun.data.color = world["sun"]
        size *= 1.3  # show the land round the play area
    top = camera("Camera_Top", size * 1.06)
    top.location = (centre.x, centre.y, hi.z + 300)
    persp = camera("Camera_Perspective")
    persp.data.lens = 32
    d = Vector((0.55, -1.0, 0.85)).normalized() * size * 1.05
    persp.location = centre + d
    persp.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()

    with open(base + ".json", "w") as f:
        json.dump({"id": m.id, "name": m.name, "modes": m.modes, "notes": m.notes,
                   "units": "metres; Blender Z up (x east, y north); Godot (x, y, z) = (x, z, -y)",
                   "bounds": {"min": [round(v, 2) for v in lo], "max": [round(v, 2) for v in hi]},
                   "markers": m.markers}, f, indent=1)

    bpy.ops.wm.save_as_mainfile(filepath=base + ".blend", compress=True)

    if RENDER:
        render(m, base + "_perspective.png", persp, (1600, 1000), [])
        views = m.cutaways or [("plan", [], "plan")]
        for suffix, hidden, _ in views:
            render(m, f"{base}_{suffix}.png", top, (1400, 1400), hidden)

    # The .glb: geometry and markers, no labels, lights or cameras.
    for ob in list(m.coll("Labels").objects):
        bpy.data.objects.remove(ob)
    bpy.ops.export_scene.gltf(filepath=base + ".glb", export_format="GLB", export_extras=True,
                              export_cameras=False, export_lights=False, export_apply=True)
    print(f"built {m.id}: {len(m.markers)} markers")
    return m


if __name__ == "__main__":
    keys = [ONLY] if ONLY else list(MAPS)
    for k in keys:
        build(k)
