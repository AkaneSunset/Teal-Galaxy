"""The factions' city pieces, modelled in Blender and exported for Godot.

Each piece is built to its footprint in metres (one city cell is 10 m) with its origin on the ground
in the middle, and its front (doors, signs) toward Blender's +Y, which is -Z in Godot. Small parts
(lights, rails, grates) go in a separate "detail" object that the game stops drawing from far away.
Everything else is joined into one object, so a piece is one or two meshes for the city's batches.

Run with Blender:   blender -b -P tools/blender/city_models.py -- compact [--render DIR]
or with the bpy module (pip install bpy):   python tools/blender/city_models.py compact [--render DIR]

Writes game/city/<faction>/<piece>.glb (Godot imports them; game/city.gd loads them by name).
--render also writes a PNG of each piece to DIR, for checking the look without the game.
--sheet DIR writes one PNG per faction of all its zone housing side by side.

kit.py holds the shared parts and export; housing.py the zone housing (many looks per faction);
interiors.py the insides of buildings (inside_<piece>.glb), which --render pictures from the door.
"""

import glob
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import housing  # noqa: E402
import interiors  # noqa: E402
import kit  # noqa: E402
from kit import CELL, ball, box, compact_mats, cyl, finish, pilasters, render, reset, ring, saucer, slits, spike, text, tube, twin_turret  # noqa: E402

# --- The Terran Compact ----------------------------------------------------------------------------
# Dark navy naval-industrial armour, chamfered blocks, blue window slits, amber work lights, huge
# white stencils, yellow hazard stripes, twin-barrel turrets. See the "Faction building designs" doc.

def compact_hall(M):
    """The Government Hall: a fortress keep of stepped blocks, crowned with spire towers."""
    box((64, 64, 4), (0, 0, 0), M["steel"], bevel=0.8)
    for sx in (-1, 1):  # hazard stripes on the plinth edge
        box((0.6, 60, 0.25), (sx * 31.6, 0, 4.0), M["hazard"], detail=True)
        box((60, 0.6, 0.25), (0, sx * 31.6, 4.0), M["hazard"], detail=True)
    tiers = [(54, 18, "navy", 7), (42, 16, "slate", 9), (30, 14, "navy", 0)]
    z = 4.0
    for w, h, m, bare in tiers:
        box((w, w, h), (0, 0, z), M[m], bevel=1.6)
        pilasters(M, w, w, z, h)
        slits(M, w, w, z + 2, h - 3, every=4.5, skip_front=bare)
        box((w + 1.2, w + 1.2, 1.0), (0, 0, z + h - 0.5), M["steel"], bevel=0.3)  # ledge
        z += h
    # The keep's central tower and its stepped, slightly gothic crown and mast.
    box((12, 12, 26), (0, 0, z), M["slate"], bevel=1.0)
    slits(M, 12, 12, z + 2, 22, every=3.5)
    box((14, 14, 2.5), (0, 0, z + 26), M["steel"], bevel=0.5)
    box((9, 9, 8), (0, 0, z + 28.5), M["navy"], bevel=0.8)
    box((9.4, 9.4, 1.0), (0, 0, z + 34), M["blue"])
    cyl(3.2, 10, (0, 0, z + 36.5), M["slate"], verts=8, top=0.6)
    cyl(0.35, 18, (0, 0, z + 46.5), M["steel"], verts=6)
    cyl(0.6, 0.8, (0, 0, z + 64.5), M["blue"], verts=8, detail=True)
    # Four corner spires on the second tier.
    zc = 4 + 18 + 16
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 17.5, sy * 17.5
            box((6, 6, 20), (x, y, zc), M["navy"], bevel=0.6)
            box((6.4, 6.4, 0.8), (x, y, zc + 16), M["blue"])
            cyl(2.6, 9, (x, y, zc + 20), M["slate"], verts=4, top=0.2)
            cyl(0.25, 6, (x, y, zc + 29), M["steel"], verts=6, detail=True)
    # The front: a great armoured gate, a ramp up to it, work lights, and the stencil.
    box((16, 3, 10), (0, 26.6, 4), M["dark"])
    box((18, 2.6, 1.2), (0, 27.4, 14), M["steel"], bevel=0.3)
    box((16, 6, 4), (0, 31, 0), M["deck"])
    for sx in (-1, 1):
        box((0.6, 0.6, 0.6), (sx * 9.5, 28.6, 13.0), M["amber"], detail=True)
        box((0.6, 0.6, 0.6), (sx * 25, 27.6, 20.5), M["amber"], detail=True)
    text("TERRAN COMPACT", 3.6, (0, 27.25, 18.6), M["white"])
    # The eagle, on the second tier: two swept wings either side of a shield.
    for sx in (-1, 1):
        box((8, 0.4, 1.4), (sx * 6.0, 21.2, 33.4), M["white"], rot=(0, sx * math.radians(18), 0))
        box((6, 0.4, 1.0), (sx * 5.0, 21.2, 31.4), M["white"], rot=(0, sx * math.radians(18), 0))
    box((3.0, 0.5, 4.2), (0, 21.25, 29.6), M["blue"])
    # Twin turrets on the plinth corners.
    for sx in (-1, 1):
        for sy in (-1, 1):
            twin_turret(M, (sx * 29.5, sy * 29.5, 4.0), scale=0.75)


def compact_tower(M, height, foot):
    """Tower Block and High-rise: stacked armoured blocks with blue slits and a spire crown."""
    w = foot * 0.9
    box((w, w, 3), (0, 0, 0), M["steel"], bevel=0.4)
    z = 3.0
    steps = [(0.92, 0.45), (0.8, 0.35), (0.66, 0.2)]
    body = height * 0.82 - 3
    for k, share in steps:
        h = body * share
        b = w * k
        box((b, b, h), (0, 0, z), M["navy"] if k != 0.8 else M["slate"], bevel=max(0.4, b * 0.06))
        pilasters(M, b, b, z, h)
        slits(M, b, b, z + 1.5, h - 2, every=3.2)
        box((b + 0.8, b + 0.8, 0.6), (0, 0, z + h - 0.3), M["steel"])
        for sx in (-1, 1):
            box((0.5, 0.5, 0.5), (sx * (b / 2 + 0.2), b / 2 + 0.2, z + h + 0.2), M["amber"], detail=True)
        z += h
    top = w * 0.5
    box((top, top, height * 0.06), (0, 0, z), M["slate"], bevel=0.3)
    box((top + 0.4, top + 0.4, 0.6), (0, 0, z + height * 0.06), M["blue"])
    cyl(top * 0.45, height * 0.1, (0, 0, z + height * 0.06 + 0.6), M["navy"], verts=4, top=0.2)
    cyl(0.18 * foot / 10, height * 0.12, (0, 0, z + height * 0.16), M["steel"], verts=6, detail=True)
    if height > 60:  # the high-rise's crown: four small spires round the top
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl(0.9, height * 0.07, (sx * top * 0.42, sy * top * 0.42, z + height * 0.06 + 0.6), M["slate"], verts=4, top=0.1)
    text("B-%02d" % (int(height) % 97), w * 0.16, (w * 0.22, w * 0.92 / 2 + 0.25, 5.0), M["white"])
    box((w * 0.3, 0.4, 2.6), (-w * 0.2, w / 2, 0), M["dark"])  # the door


def compact_road(M):
    box((10, 10, 0.3), (0, 0, 0), M["deck"])
    for sx in (-1, 1):
        box((0.35, 10, 0.06), (sx * 4.3, 0, 0.3), M["hazard"])
    for y in (-2.5, 2.5):
        box((1.2, 0.8, 0.05), (0, y, 0.3), M["dark"], detail=True)  # grates
    for x in (-3, 0, 3):  # the plate seams
        box((0.08, 10, 0.04), (x, 0, 0.3), M["dark"], detail=True)


def compact_plaza(M):
    box((19.8, 19.8, 0.35), (0, 0, 0), M["deck"])
    box((19.8, 0.5, 0.06), (0, 9.65, 0.35), M["hazard"])
    box((19.8, 0.5, 0.06), (0, -9.65, 0.35), M["hazard"])
    for x in (-6, -2, 2, 6):  # the bays
        box((0.25, 7, 0.05), (x, -4, 0.35), M["white"], detail=True)
    cyl(1.4, 0.8, (0, 4, 0.35), M["slate"], verts=8)
    cyl(0.15, 12, (0, 4, 1.15), M["steel"], verts=6)
    box((3.6, 0.08, 2.2), (1.85, 4, 10.5), M["navy"])  # the flag
    box((1.2, 0.1, 1.0), (1.85, 4, 11.1), M["white"], detail=True)
    for sx in (-1, 1):
        cyl(0.15, 5, (sx * 8.5, 8.5, 0.35), M["steel"], verts=6, detail=True)
        box((0.6, 0.6, 0.4), (sx * 8.5, 8.5, 5.35), M["amber"], detail=True)


def compact_wall(M):
    box((20, 4.0, 2), (0, 0, 0), M["steel"])
    box((20, 3.2, 7), (0, 0, 2), M["navy"], bevel=0.3)
    box((20, 0.6, 1.4), (0, 1.6, 9), M["slate"])  # the parapet
    box((20, 0.5, 0.2), (0, -1.3, 9), M["hazard"], detail=True)  # the walkway edge
    box((14, 0.25, 0.4), (0, 1.75, 6.0), M["blue"])
    for x in (-7, 7):
        box((0.5, 0.5, 0.5), (x, 2.0, 7.4), M["amber"], detail=True)


def compact_turret(M):
    box((9, 9, 1.0), (0, 0, 0), M["steel"], bevel=0.3)
    twin_turret(M, (0, -0.5, 1.0), scale=1.0)


COMPACT = {
    "hall": (compact_hall, (7, 7), 110),
    "tower": (lambda M: compact_tower(M, 40.0, 20.0), (2, 2), 40),
    "highrise": (lambda M: compact_tower(M, 90.0, 30.0), (3, 3), 90),
    "road": (compact_road, (1, 1), 2),
    "plaza": (compact_plaza, (2, 2), 12),
    "wall": (compact_wall, (2, 1), 10),
    "turret": (compact_turret, (1, 1), 8),
}

# --- The Coma Conglomerate ---------------------------------------------------------------------------
# Nothing of theirs looks built: gunmetal limbs coil up out of the ground and into one another, gold
# light runs along them, and discs and hoops hang off them. See the "Faction building designs" doc.

def _hoop(R, r, at, m, rot=(0, 0, 0), squash=1.0, segs=28, minor=6, detail=False):
    """A hoop of radius R (its band r thick, `squash` flattening the band) centred on `at`, turned
    by `rot`: lying flat until turned."""
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=segs, minor_segments=minor, location=at, rotation=rot)
    ob = bpy.context.object
    ob.scale = (1.0, 1.0, squash)  # along its own axis; joining the piece bakes it in
    return kit._keep(ob, m, detail)


def coma_port(M, at, r, turn=0.0):
    """A round port standing out of a limb's flank: a socket, its heavy rim, the dark inside and a
    hoop of light. `at` is the middle of its mouth; it looks toward +Y, turned `turn` radians
    about Z."""
    x, y, z = at
    out = (-math.sin(turn), math.cos(turn))
    stand = (math.pi / 2, 0, turn)
    cyl(r * 1.04, 3.2, (x - out[0] * 1.6, y - out[1] * 1.6, z), M["hide"], verts=20, rot=stand)
    _hoop(r, r * 0.25, (x, y, z), M["hide"], rot=stand, segs=20)
    cyl(r * 0.98, 0.1, (x + out[0] * 0.06, y + out[1] * 0.06, z), M["void"], verts=20, rot=stand)
    _hoop(r * 0.56, 0.16, (x + out[0] * 0.16, y + out[1] * 0.16, z), M["aur"], rot=stand, segs=20, minor=4, detail=True)
    _hoop(r * 0.24, 0.1, (x + out[0] * 0.16, y + out[1] * 0.16, z), M["aur"], rot=stand, segs=12, minor=4, detail=True)


def coma_hall(M):
    """The Data Spire: limbs of gunmetal coiling up out of the ground into two horns, round ports
    in their flanks, a great hoop hung off the taller horn and a landing disc held out in front."""
    def limb(pts, radii, lines=3, sides=10, twist=0.45, phase=0.5):
        tube(pts, radii, M["hide"], sides=sides, steps=4, lines=[phase + k * math.tau / lines for k in range(lines)], line_m=M["aur"],
             line_r=0.16, twist=twist)

    ball(21, (0, 0, 0), M["hide"], sx=1.35, sy=1.0, sz=0.42, segs=18, rings=8, dome=True)  # the mound they rise from
    # The two horns (seen from the front the taller stands in the middle, curling to the right).
    limb([(3, -4, 0), (4, -5, 16), (6, -5, 32), (4, -4, 48), (-2, -2, 62), (-9, 0, 71), (-15, 2, 73), (-19, 3, 68)], [12, 11.5, 8.5, 6, 4.2, 2.6, 1.4, 0.4], lines=5)
    limb([(-15, -6, 0), (-17, -7, 14), (-16, -6, 30), (-13, -5, 44), (-14, -3, 55), (-18, -1, 61), (-22, 0, 58)], [8.5, 8.5, 6.2, 4.2, 2.6, 1.4, 0.4], lines=4, phase=1.3)
    # The lobes at their feet, and the limbs that climb and cross them.
    limb([(20, 2, 0), (22, 3, 10), (20, 3, 20), (13, 0, 27), (7, -3, 30)], [9, 10.5, 9, 6, 4], lines=4)
    limb([(-27, 2, 0), (-28, 3, 10), (-26, 2, 21), (-20, -2, 29), (-15, -5, 33)], [7, 9, 7.5, 5, 3.5], lines=4, phase=2.0)
    limb([(-4, 8, 0), (-4, 10, 8), (-3, 7, 16), (0, 2, 22)], [8, 9, 6.5, 4], lines=3, phase=1.0)
    limb([(8, -14, 0), (9, -15, 12), (7, -12, 26), (5, -8, 36)], [9, 8, 6, 4], lines=3, phase=3.0)
    limb([(25, 9, 0), (27, 7, 14), (19, 3, 30), (9, 0, 41), (4, -2, 51)], [4.6, 4.2, 3.3, 2.5, 1.6], lines=2, sides=8, phase=0.9)
    limb([(-20, 13, 0), (-22, 11, 10), (-14, 7, 22), (-4, 3, 31), (3, 0, 39)], [4.4, 3.9, 3.1, 2.3, 1.5], lines=2, sides=8, phase=2.2)
    limb([(3, -3, 51), (-4, -4, 46.5), (-10, -4, 47), (-14, -4, 52)], [2.3, 1.6, 1.6, 2.1], lines=2, sides=8)  # a brace between the horns
    coma_port(M, (21.5, 14.3, 11), 4.2, turn=-0.12)
    coma_port(M, (-4, 19.6, 8.5), 3.3)
    coma_port(M, (-27.5, 12.7, 12), 3.9, turn=0.12)
    coma_port(M, (6.2, 4.6, 31), 2.9, turn=-0.05)
    for k in range(9):  # roots, running out to the edge of the plot and curling
        a = math.radians(30 + k * 40)
        curl = 0.3 if k % 2 else -0.3
        pts = [(math.cos(a + c) * r, math.sin(a + c) * r * 0.92, z) for r, z, c in ((11, 9.5, 0), (19, 7.5, curl * 0.3), (26.5, 3.2, curl * 0.7), (32.5, 0.2, curl))]
        limb(pts, [3.4, 2.5, 1.7, 0.7], lines=2, sides=8, phase=1.6)
    for a0, lean in ((70, 1), (110, -1)):  # and two that make the gate, over the way in
        a = math.radians(a0)
        pts = [(math.cos(a) * 9, 9 + math.sin(a) * 8, 12), (lean * 5.6, 24, 9.5), (lean * 4.6, 31, 5.5), (lean * 3.4, 34, 0)]
        limb(pts, [2.6, 1.9, 1.3, 0.8], lines=2, sides=8, phase=0.2)
    tube([(-3.4, 34, 0.5), (-3.8, 33.6, 4.6), (0, 33.2, 7.2), (3.8, 33.6, 4.6), (3.4, 34, 0.5)], 0.16, M["aur"], sides=4, steps=4, detail=True)
    box((5.2, 17, 0.3), (0, 26, 0), M["black"])
    for s in (-1, 1):
        box((0.14, 17, 0.06), (s * 2.3, 26, 0.3), M["aur"], detail=True)
    # The great hoop, hung off the taller horn, its front edge lifted.
    tilt = (math.radians(10), math.radians(9), 0)
    _hoop(15, 1.9, (20, -4, 43.5), M["hide"], rot=tilt, squash=0.42, segs=36)
    for R in (16.95, 13.1):
        _hoop(R, 0.14, (20, -4, 43.6), M["aur"], rot=tilt, segs=36, minor=4, detail=True)
    for x, y, z0, z1 in ((31.5, 5.6, 43.5, 26), (23.9, 10.5, 45.5, 20), (16.1, 10.5, 46.5, 30), (34.1, 1.1, 42, 24)):  # strands hanging from it
        tube([(x, y, z0), (x + 0.5, y + 0.6, (z0 + z1) / 2), (x - 0.4, y - 0.3, z1)], [0.22, 0.16, 0.06], M["hide"], sides=4, steps=2, detail=True)
    # The landing disc, held out in front.
    limb([(-5, 5, 13), (-8, 11, 16.5), (-9.5, 15.5, 18.3)], [3.6, 2.6, 2.0], lines=2, sides=8)
    saucer(11.5, (-9.5, 18, 20), M["gun"], rim=1.0, under=3.2, foot=0.3, verts=28)
    cyl(7.6, 0.6, (-9.5, 18, 20), M["gun"], verts=28)
    cyl(4.4, 0.5, (-9.5, 18, 20.6), M["black"], verts=24)
    for R, z in ((11.3, 20.02), (7.5, 20.62), (4.2, 21.12), (9.4, 20.02)):
        ring(R, 0.12, (-9.5, 18, z), M["aur"], detail=True, segs=36)
    ring(11.55, 0.1, (-9.5, 18, 19.5), M["aur"], detail=True, segs=36)
    cyl(0.9, 0.25, (-9.5, 18, 21.1), M["light"], verts=12, detail=True)
    for x, y, z0, drop in ((-20, 2, 58, 30), (-17, -1, 60, 24)):  # strands off the lesser horn
        tube([(x, y, z0), (x - 2.5, y + 2, z0 - drop * 0.5), (x - 2.0, y + 3, z0 - drop)], [0.2, 0.15, 0.05], M["hide"], sides=4, steps=3, detail=True)


def coma_power(M):
    """The Power Plant: a swollen dome between two long lobes, round ports in their faces, gold seams
    running over them, hoops held up on arms of light, and a ring of glowing pillars round the front."""
    ball(11.5, (0, -2, 0), M["hide"], sx=1.0, sy=1.0, sz=1.45, segs=28, rings=14, dome=True)
    ball(8.5, (0, -10, 0), M["hide"], sx=1.5, sy=0.9, sz=0.85, segs=24, rings=12, dome=True)  # the hump behind
    for s in (-1, 1):
        ball(7.0, (s * 10.5, 2, 0), M["hide"], sx=1.4, sy=1.05, sz=0.72, segs=24, rings=12, dome=True)
        coma_port(M, (s * 10.5, 8.0, 2.8), 2.1)
        coma_port(M, (s * 5.2, 7.0, 8.2), 1.3, turn=-s * 0.4)
    ball(5.0, (0, 9, 0), M["hide"], sx=1.0, sy=0.9, sz=1.05, segs=20, rings=10, dome=True)  # the snout round the way in
    coma_port(M, (0, 12.75, 2.75), 2.75)
    for k, a in enumerate((-2.2, -1.5, -0.9, 0.3, 1.0, 1.95, 2.6, 3.4, 4.1)):  # gold seams over the dome, pole to ground
        pts = [(11.5 * 1.03 * math.sin(t) * math.cos(a + 0.25 * t), -2 + 11.5 * 1.03 * math.sin(t) * math.sin(a + 0.25 * t), 16.7 * 1.03 * math.cos(t))
               for t in (0.22, 0.5, 0.8, 1.1, 1.38, 1.55)]
        tube(pts, 0.13, M["aur"], sides=4, steps=3, detail=True)
    for s in (-1, 1):  # and along the lobes
        for dz, sweep in ((0.55, 0.0), (0.82, 0.5)):
            pts = [(s * (10.5 + 9.8 * 1.03 * math.cos(u) * math.sqrt(1 - dz * dz)), 2 + 7.35 * 1.03 * math.sin(u) * math.sqrt(1 - dz * dz), 5.04 * 1.03 * dz)
                   for u in [sweep + i * 0.42 for i in range(7)]]
            tube(pts, 0.12, M["aur"], sides=4, steps=3, detail=True)
    for R, r, c, rot, arm in ((6.5, 0.85, (7.5, -6, 24.5), (math.radians(68), 0, math.radians(28)), [(5.0, -3.5, 14.0), (6.8, -4.6, 18.5), (7.6, -5.2, 21.0)]),
                              (4.3, 0.6, (-7.8, -1.5, 21.5), (math.radians(35), math.radians(28), 0), [(-5.2, -1.5, 13.6), (-6.8, -1.5, 17.5), (-7.4, -1.5, 20.0)]),
                              (3.3, 0.5, (-14.5, 3.0, 12.5), (math.radians(58), 0, math.radians(-35)), [(-8.8, 0.5, 9.0), (-11.8, 1.8, 10.6), (-13.3, 2.6, 11.4)]),
                              (2.6, 0.45, (15.0, 3.5, 11.0), (math.radians(60), 0, math.radians(40)), [(9.0, 1.5, 8.6), (12.0, 2.6, 9.8), (13.6, 3.2, 10.4)])):
        _hoop(R, r, c, M["hide"], rot=rot, squash=0.5, segs=32)
        for rr in (R + r + 0.03, R - r - 0.03):
            _hoop(rr, 0.12, c, M["aur"], rot=rot, segs=32, minor=4, detail=True)
        tube(arm, [0.34, 0.26, 0.2], M["aur"], sides=5, steps=3, detail=True)
        cyl(0.7, 0.4, arm[0], M["hide"], verts=10)
    for k in range(13):  # the ring of pillars round the front
        a = math.radians(-8 + k * 16)
        x, y = 18.0 * math.cos(a), 2 + 15.5 * math.sin(a)
        if abs(x) < 3.5:
            continue
        cyl(0.95, 0.45, (x, y, 0), M["plate"], verts=10)
        ring(0.92, 0.05, (x, y, 0.46), M["aur"], detail=True, segs=16)
        cyl(0.42, 3.4 + 0.5 * (k % 3), (x, y, 0.45), M["beam"], verts=12, detail=True)
        cyl(0.5, 0.15, (x, y, 3.85 + 0.5 * (k % 3)), M["hide"], verts=10, detail=True)
    box((5.2, 8.5, 0.3), (0, 16.6, 0), M["black"])
    for s in (-1, 1):
        box((0.14, 8.5, 0.06), (s * 2.3, 16.6, 0.3), M["aur"], detail=True)


# --- Ashen Collective -------------------------------------------------------------------------------

def _path(points, width, m, z=0.0, thick=0.18, kerb=None, detail=False):
    """A winding paved path through `points` ((x, y) on the ground), `width` across, laid flat at
    `z`; with `kerb` a material, a low kerb runs along both its edges."""
    import bmesh
    from mathutils import Vector
    pts = [p for _, p in kit._spline([(x, y, 0.0) for x, y in points], 6)]
    bm = bmesh.new()
    rows = []
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        d = (b - a).normalized()
        side = Vector((-d.y, d.x, 0.0))
        row = []
        for s in (-1, 1):
            for h in (z, z + thick):
                row.append(bm.verts.new(p + side * s * width / 2 + Vector((0, 0, h))))
        rows.append(row)
    for r0, r1 in zip(rows, rows[1:]):  # top, bottom and both sides of each stretch
        for i, j in ((1, 3), (2, 0), (0, 1), (3, 2)):
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    for row, flip in ((rows[0], False), (rows[-1], True)):
        f = (row[0], row[1], row[3], row[2])
        bm.faces.new(f[::-1] if flip else f)
    kit._solid("path", bm, m, detail)
    if kerb is not None:
        for s in (-1, 1):
            edge = []
            for i, p in enumerate(pts[::2]):
                k = min(i * 2, len(pts) - 1)
                a, b = pts[max(k - 1, 0)], pts[min(k + 1, len(pts) - 1)]
                d = (b - a).normalized()
                q = p + Vector((-d.y, d.x, 0.0)) * s * (width / 2 + 0.15)
                edge.append((q.x, q.y, z + thick + 0.08))
            tube(edge, 0.16, kerb, sides=4, steps=2, flat=0.7, detail=True)


def _tree(M, at, h, spread, seed):
    """A swamp tree: a crooked trunk that forks, and dark leaves in clumps on each branch."""
    import random
    r = random.Random(seed)
    x, y, z = at
    lean = (r.uniform(-1, 1), r.uniform(-1, 1))
    top = (x + lean[0] * 0.8, y + lean[1] * 0.8, z + h * 0.55)
    tube([(x, y, z), (x + lean[0] * 0.3, y + lean[1] * 0.3, z + h * 0.3), top], [0.42, 0.3, 0.22], M["bark"], sides=6, steps=3)
    for k in range(3):  # roots
        a = r.uniform(0, math.tau)
        tube([(x, y, z + 0.6), (x + math.cos(a) * 1.0, y + math.sin(a) * 1.0, z + 0.1)], [0.2, 0.08], M["bark"], sides=4, steps=1, detail=True)
    for k in range(r.choice((2, 3))):  # branches, each ending in a clump of leaves
        a = r.uniform(0, math.tau)
        end = (top[0] + math.cos(a) * spread * 0.6, top[1] + math.sin(a) * spread * 0.6, z + h * r.uniform(0.7, 0.85))
        tube([top, end], [0.2, 0.09], M["bark"], sides=5, steps=1)
        for j in range(3):
            c = (end[0] + r.uniform(-1.2, 1.2), end[1] + r.uniform(-1.2, 1.2), end[2] + r.uniform(-0.2, 1.4))
            ball(spread * r.uniform(0.32, 0.45), c, M["leaf"], sz=0.7, segs=7, rings=5)
    ball(spread * 0.5, (top[0], top[1], z + h * 0.9), M["leaf"], sz=0.65, segs=8, rings=5)


def _shrub(M, at, size, seed):
    import random
    r = random.Random(seed)
    for k in range(3):
        ball(size * r.uniform(0.5, 0.8), (at[0] + r.uniform(-size, size) * 0.6, at[1] + r.uniform(-size, size) * 0.6, at[2] + size * 0.25),
             M["leaf"], sz=0.6, segs=6, rings=4, detail=True)


def _barrier(M, a, b, z=0.0, h=1.1):
    """A low Ashen barrier from `a` to `b` (on the ground): six-sided armoured blocks, each with a
    red-lit window in its face, the kind that edges the planting beds."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    turn = math.atan2(dy, dx)
    n = max(1, round(length / 2.4))
    seg = length / n
    for i in range(n):
        t = (i + 0.5) / n
        c = (a[0] + dx * t, a[1] + dy * t, z)
        box((seg - 0.18, 0.7, h), c, M["plate"], bevel=0.3, rot=(0, 0, turn))
        box((seg - 0.18, 0.9, 0.18), c, M["frame"], rot=(0, 0, turn))  # the foot
        for s in (-1, 1):  # the lit window in each face
            o = (-math.sin(turn) * s * 0.36, math.cos(turn) * s * 0.36)
            box((seg * 0.6, 0.06, 0.16), (c[0] + o[0], c[1] + o[1], z + h * 0.42), M["strip"], rot=(0, 0, turn), detail=True)


def _monolith(M, at, h):
    """The park's monument: a stepped black spire of angled plates, slit with red light, on a
    raised plinth with an ember well at its foot."""
    x, y, z = at
    cyl(5.4, 0.7, (x, y, z), M["frame"], verts=8, turn=math.pi / 8)
    cyl(5.5, 0.08, (x, y, z + 0.7), M["strip"], verts=8, turn=math.pi / 8)
    cyl(4.6, 0.5, (x, y, z + 0.78), M["floor"], verts=8, turn=math.pi / 8)
    z += 1.28
    tiers = [(5.6, 4.6, 0.30), (4.6, 3.8, 0.26), (3.6, 3.0, 0.22), (2.6, 2.2, 0.16), (1.6, 1.4, 0.06)]
    zz = z
    for i, (w, d, f) in enumerate(tiers):
        hh = h * f
        box((w, d, hh), (x, y, zz), M["plate"], bevel=0.35)
        for sx in (-1, 1):  # angled plates leaning on its flanks
            box((0.6, d * 0.7, hh * 0.8), (x + sx * (w / 2 + 0.1), y, zz), M["frame"], bevel=0.15, rot=(0, sx * 0.12, 0))
        for k, ox in enumerate((-0.28, 0.0, 0.28)[: 3 - i // 2]):  # red slits up the front and back
            for sy in (-1, 1):
                box((0.16, 0.08, hh * (0.75 if k != 1 else 0.55)), (x + ox * w, y + sy * (d / 2 + 0.02), zz + hh * 0.12), M["strip"])
        box((w + 0.3, d + 0.3, 0.12), (x, y, zz + hh - 0.06), M["strip"], detail=True)  # a lit seam where the tiers meet
        zz += hh
    spike(0.7, (x, y, zz), (x, y, zz + h * 0.14), M["plate"], verts=4)
    for a in range(4):  # buttress blades at the corners
        ang = math.pi / 4 + a * math.pi / 2
        foot = (x + math.cos(ang) * 4.6, y + math.sin(ang) * 4.0, z - 0.5)
        spike(0.55, foot, (x + math.cos(ang) * 2.0, y + math.sin(ang) * 1.7, z + h * 0.35), M["frame"], flat=0.45, tip=0.15)
    box((2.2, 0.6, 1.8), (x, y + 2.55, z - 0.1), M["frame"], bevel=0.12)  # the ember well at its foot
    box((1.6, 0.1, 1.2), (x, y + 2.9, z + 0.1), M["grate"])
    box((1.4, 0.06, 1.0), (x, y + 2.84, z + 0.2), M["ember"])


def _pavilion(M, at, turn=0.0):
    """A shelter: an angular black roof hung on four raked legs, red light under its eaves."""
    x, y, z = at
    c, s = math.cos(turn), math.sin(turn)

    def p(u, v, w=0.0):
        return (x + u * c - v * s, y + u * s + v * c, z + w)

    box((8.4, 6.4, 0.25), p(0, 0), M["floor"], rot=(0, 0, turn))
    for u in (-3.2, 3.2):
        for v in (-2.2, 2.2):
            spike(0.32, p(u * 1.08, v * 1.1), p(u * 0.86, v * 0.82, 3.6), M["frame"], tip=0.22)
    box((9.8, 7.8, 0.6), p(0, 0, 3.6), M["plate"], bevel=0.28, rot=(0, 0, turn))
    box((7.0, 5.0, 0.7), p(0, 0, 4.2), M["plate"], bevel=0.3, rot=(0, 0, turn))  # its raised crown
    for u, v, w, d in ((0, -3.92, 9.9, 0.12), (0, 3.92, 9.9, 0.12), (-4.92, 0, 0.12, 7.9), (4.92, 0, 0.12, 7.9)):
        box((w, d, 0.12), p(u, v, 3.62), M["strip"], rot=(0, 0, turn))  # the lit edge of the eave
    box((5.0, 0.6, 0.5), p(0, -1.0, 0.25), M["frame"], rot=(0, 0, turn), detail=True)  # benches
    box((5.0, 0.6, 0.5), p(0, 1.0, 0.25), M["frame"], rot=(0, 0, turn), detail=True)


def _solid_marker(at, size):
    """Marks a box `size` (x, y, z) with its bottom centre at `at` as solid: the park is a flat
    piece you walk over, and the game walls in only what its "solid..." markers cover."""
    mk = kit.marker(f"solid{len([m for m in kit._marks if m.name.startswith('solid')]) + 1}", (at[0], at[1], at[2] + size[2] / 2))
    mk.scale = (size[0] / 2, size[1] / 2, size[2] / 2)


def ashen_park(M):
    """An Ashen park, 3 x 3 cells: dark paving and swamp beds under trees, a winding path between
    planters edged with red-lit barriers, a black spire monument slit with red light on a raised
    plinth, and a shelter with a lit eave. Front toward +Y."""
    M = dict(M)
    M["leaf"] = kit.mat("leaf", "#26331f", metal=0.0, rough=0.8)
    M["bark"] = kit.mat("bark", "#29231f", metal=0.0, rough=0.85)
    M["stone"] = kit.mat("stone", "#45474c", metal=0.1, rough=0.8)
    box((29.6, 29.6, 0.2), (0, 0, 0), M["floor"])  # the paving everywhere
    for x0, y0, w, d in ((-9.5, -8.0, 9.5, 12.0), (8.5, 9.0, 11.0, 9.0), (-10.0, 9.5, 8.0, 8.0), (10.0, -9.5, 7.5, 7.5)):
        box((w, d, 0.45), (x0, y0, 0.2), M["moss"], bevel=0.12)  # swamp beds, raised a little
    # The paths: one winding in from the front to the monument, one crossing toward the shelter.
    _path([(1.0, 15.0), (2.5, 9.0), (-1.0, 3.0), (1.5, -2.5), (5.5, -5.0)], 3.2, M["stone"], z=0.2, kerb=M["frame"])
    _path([(-15.0, 2.5), (-9.0, 1.5), (-3.0, 0.5), (0.5, -1.0)], 2.4, M["stone"], z=0.2, kerb=M["frame"])
    _path([(2.5, -2.0), (6.0, 1.0), (10.5, 2.5), (15.0, 2.0)], 2.4, M["stone"], z=0.2, kerb=M["frame"])
    _monolith(M, (8.5, -8.5, 0.2), 22.0)
    _pavilion(M, (-9.5, 9.5, 0.65), turn=0.0)
    # Barriers round the beds and along the front edge, broken where the paths come in.
    for a, b in (((-14.4, 14.6), (-2.0, 14.6)), ((4.5, 14.6), (14.4, 14.6)), ((-14.6, -14.4), (-14.6, -1.0)),
                 ((-14.6, 5.0), (-14.6, 14.0)), ((-14.2, -14.6), (2.0, -14.6)), ((14.6, -3.0), (14.6, 0.5)),
                 ((14.6, 4.5), (14.6, 13.0)), ((-4.8, -2.2), (-4.8, -13.5))):
        _barrier(M, a, b, z=0.2)
        _solid_marker(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.2), (abs(b[0] - a[0]) + 0.9, abs(b[1] - a[1]) + 0.9, 1.1))
    _solid_marker((8.5, -8.5, 0.0), (9.0, 8.4, 24.0))  # the monument on its plinth
    for i, (x, y, h, sp) in enumerate(((-10.5, -5.0, 9.5, 3.4), (-7.0, -11.5, 7.5, 2.8), (-12.0, -12.0, 6.5, 2.4), (10.5, 9.5, 10.0, 3.6),
                                       (6.0, 11.0, 7.0, 2.6), (12.5, 6.5, 6.0, 2.2), (-3.5, 6.5, 8.0, 3.0), (3.0, -12.5, 6.5, 2.4))):
        _tree(M, (x, y, 0.6), h, sp, seed=31 + i)
        _solid_marker((x, y, 0.6), (0.9, 0.9, h * 0.6))
    for i, (x, y, sz) in enumerate(((-6.0, -6.0, 1.3), (-12.5, -2.5, 1.1), (-8.5, -2.0, 0.9), (7.0, 6.5, 1.2), (12.0, 12.0, 1.0),
                                    (-2.0, 9.0, 1.1), (-12.5, 6.0, 1.0), (4.5, 4.5, 0.9), (13.0, -4.5, 1.1), (-1.5, -12.0, 1.0))):
        _shrub(M, (x, y, 0.6), sz, seed=60 + i)
    for i, (x, y) in enumerate(((-2.0, 12.0), (5.0, 7.5), (-3.5, -3.5), (-11.5, 3.6), (8.0, 4.4), (13.0, 4.2))):  # path lamps
        cyl(0.18, 1.4, (x, y, 0.2), M["frame"], verts=6, detail=True)
        box((0.34, 0.34, 0.34), (x, y, 1.6), M["strip"], detail=True)
    for i, (x, y, r) in enumerate(((-5.5, 12.5, 0.9), (12.8, -0.8, 0.7), (-13.0, -8.0, 0.8))):  # boulders in the beds
        ball(r, (x, y, 0.5), M["char"], sx=1.3, sz=0.7, segs=6, rings=4, detail=True)


ASHEN = {
    "park": (ashen_park, (3, 3), 26),
}

COMA = {
    "hall": (coma_hall, (7, 7), 76),
    "power": (coma_power, (4, 4), 30),
}

FACTIONS = {
    "compact": (compact_mats, COMPACT),
    "ashen": (kit.ashen_mats, ASHEN),
    "luminar": (kit.luminar_mats, {}),
    "coma": (kit.coma_mats, COMA),
}
for _faction, (_mats, _pieces) in FACTIONS.items():
    _pieces.update(housing.pieces(_faction))
    for _name, _build in interiors.INSIDES.get(_faction, {}).items():
        _pieces[_name] = (_build, (1, 1), 6)


def sheet(path, faction, columns):
    """One picture of the faction's zone housing, loaded back from the exported files: each column
    is a (low-density piece, high-density piece) pair, the low lots in front, the high ones behind."""
    reset()
    folder = os.path.join(kit.ROOT, "game", "city", faction)
    mid = (len(columns) - 1) / 2
    for col, pair in enumerate(columns):
        for name, pitch, y in zip(pair, (26.0, 36.0), (34.0, -14.0)):
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(folder, f"{name}.glb"))
            for ob in set(bpy.data.objects) - before:
                if ob.parent is None:
                    ob.location.x -= (col - mid) * pitch  # the camera looks back along Y: the first column on the left
                    ob.location.y += y
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.resolution_x, scene.render.resolution_y = 1800, 900
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.4, 0.52, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scene.world = world
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(52), 0, math.radians(150)))
    bpy.context.object.data.energy = 3.0
    bpy.ops.mesh.primitive_plane_add(size=900, location=(0, 0, -0.05))
    bpy.context.object.data.materials.append(kit.mat("ground", "#3a3f44", metal=0, rough=0.9))
    kit.texture_scene(faction)
    bpy.ops.object.camera_add(location=(60, 235, 105))
    cam = bpy.context.object
    target = bpy.data.objects.new("target", None)
    target.location = (0, 0, 30)
    scene.collection.objects.link(target)
    c = cam.constraints.new("TRACK_TO")
    c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"
    cam.data.lens = 34
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    dirs = {}
    for flag in ("--render", "--sheet"):
        if flag in args:
            i = args.index(flag)
            dirs[flag] = args[i + 1]
            del args[i:i + 2]
            os.makedirs(dirs[flag], exist_ok=True)
    only = args[1:]  # piece names, or a family: "zone" or "zone_low" builds every one of them
    for faction in args[:1] or list(FACTIONS):
        make_mats, pieces = FACTIONS[faction]
        for piece, (build, cells, height) in pieces.items():
            if only and not any(piece == o or piece.startswith(o + "_") for o in only):
                continue
            reset()
            build(make_mats())
            finish(faction, piece)
            if "--render" in dirs:
                if piece.startswith("inside_"):
                    kit.POSTERS = sorted(glob.glob(os.path.join(kit.ROOT, "game", "city", faction, "propaganda", "poster_*.png")))
                    views = interiors.VIEWS.get(faction, {}).get(piece, ())
                    kit.render_inside(os.path.join(dirs["--render"], f"{faction}_{piece}.png"), views=views)
                    continue
                render(os.path.join(dirs["--render"], f"{faction}_{piece}.png"), (cells[0] * CELL, cells[1] * CELL), height)
        if "--sheet" in dirs:  # every look at the top tier, then three looks growing through the tiers
            top = housing.TIERS
            sheet(os.path.join(dirs["--sheet"], f"{faction}_housing.png"), faction,
                  [(f"zone_low_{v}_t{top}", f"zone_high_{v}_t{top}") for v in range(1, housing.VARIANTS + 1)])
            for v in (1, 2, 3):
                sheet(os.path.join(dirs["--sheet"], f"{faction}_tiers_{v}.png"), faction,
                      [(f"zone_low_{v}_t{t}", f"zone_high_{v}_t{t}") for t in range(1, top + 1)])


if __name__ == "__main__":
    main(sys.argv)
