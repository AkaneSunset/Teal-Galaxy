"""Zone housing: what stands on a lot when a housing zone is laid in the city builder.

Every faction has VARIANTS looks for a low-density lot (2 x 2 cells, 20 m: houses, huts, pods) and
as many for a high-density lot (3 x 3 cells, 30 m: towers, hives, spires). The game picks one per
lot, so a zoned street is a mix. Each density has three kinds of building per faction, and each
kind is built twice from different numbers (`alt` flips its layout), which gives the six looks.

Exported as game/city/<faction>/zone_low_<n>.glb and zone_high_<n>.glb.
"""

import math
import random

from kit import (ashen_mats, ball, box, coma_mats, compact_mats, cone, cyl, halfpipe, luminar_mats, pilasters, prism,
                 ring, slits, spike, twin_turret)

LOW = 20.0
HIGH = 30.0
VARIANTS = 6
TAU = math.tau


def around(n, r, z=0.0, start=0.0, at=(0.0, 0.0)):
    """n points on a circle of radius r."""
    return [(at[0] + r * math.cos(start + TAU * i / n), at[1] + r * math.sin(start + TAU * i / n), z) for i in range(n)]


def cone_pt(r0, r1, h, verts, k, z, turn=0.0, mid=False, out=1.03, at=(0.0, 0.0, 0.0)):
    """A point on a cone's side at height z: on its k-th edge, or (mid) the middle of its k-th
    face. For lights and ribs that run up a spire."""
    a = TAU * (k + (0.5 if mid else 0.0)) / verts
    r = (r0 + (r1 - r0) * z / h) * (math.cos(math.pi / verts) if mid else 1.0) * out
    x, y = r * math.sin(a), r * math.cos(a)  # Blender's cones start at +Y and go round clockwise
    c, s = math.cos(turn), math.sin(turn)
    return (at[0] + x * c - y * s, at[1] + x * s + y * c, at[2] + z)


# --- Terran Compact: armoured navy blocks, blue slits, amber lamps, hazard stripes -----------------

def compact_low(M, rng, kind, alt):
    box((19.6, 19.6, 0.2), (0, 0, 0), M["deck"])
    box((19.6, 0.4, 0.06), (0, 9.5, 0.2), M["hazard"], detail=True)
    if kind == 0:  # barracks rows with numbered doors
        n = 3 if alt else 2
        bw = 16.0 / n - 1.2
        for i in range(n):
            x = -8 + (i + 0.5) * 16.0 / n
            h = rng.uniform(4.2, 5.8)
            box((bw, 13, h), (x, -1.5, 0.2), M["navy"] if i % 2 == 0 else M["slate"], bevel=0.5)
            box((bw + 0.5, 13.5, 0.4), (x, -1.5, h + 0.2), M["steel"])
            box((1.6, 0.3, 2.4), (x, 5.0, 0.2), M["dark"])
            box((bw * 0.6, 0.25, 0.5), (x, 5.05, 3.3), M["blue"])
            box((0.9, 0.2, 0.6), (x + bw * 0.3, 5.05, 2.2), M["white"], detail=True)  # the number plate
            box((0.4, 0.4, 0.4), (x, 5.25, 2.8), M["amber"], detail=True)
            for y in (-5.5, 1.0):
                box((1.4, 1.4, 0.9), (x, y, h + 0.6), M["steel"], detail=True)
        cyl(0.14, 6.0, (-8 + 0.5 * 16.0 / n, -6.5, 5.0), M["steel"], verts=6, detail=True)
    elif kind == 1:  # a bunker house behind a yard wall
        s = -1 if alt else 1
        h = rng.uniform(4.6, 5.6)
        box((12, 10, h), (-s * 2.5, -3, 0.2), M["navy"], bevel=1.3)
        box((12.5, 10.5, 0.4), (-s * 2.5, -3, h + 0.2), M["steel"])
        up = rng.uniform(3.2, 4.6)
        box((6, 6, up), (-s * 4.5, -4, h + 0.6), M["slate"], bevel=0.8)
        box((4.2, 0.25, 0.5), (-s * 4.5, -0.95, h + up * 0.6), M["blue"])
        box((7.0, 0.25, 0.5), (-s * 2.5, 2.05, h * 0.65), M["blue"])
        box((1.8, 0.3, 2.5), (-s * 5.5, 2.0, 0.2), M["dark"])
        box((0.4, 0.4, 0.4), (-s * 5.5, 2.25, 3.0), M["amber"], detail=True)
        cyl(0.15, 6.5, (-s * 4.5, -4, h + up + 0.6), M["steel"], verts=6, detail=True)
        box((19.2, 0.6, 1.7), (0, -9.3, 0.2), M["steel"])
        box((0.6, 13, 1.7), (s * 9.3, -3.0, 0.2), M["steel"])
        cyl(2.0, rng.uniform(3.0, 4.4), (s * 6.0, 4.5, 0.2), M["slate"], verts=10)
        cyl(2.15, 0.3, (s * 6.0, 4.5, 2.4), M["hazard"], verts=10, detail=True)
    else:  # prefab huts: half-pipes of plate
        n = 3 if alt else 2
        r = 16.0 / n / 2 - 0.35
        for i in range(n):
            x = -8 + (i + 0.5) * 16.0 / n
            ln = rng.uniform(11.0, 14.0)
            y = 5.0 - ln / 2
            halfpipe(r, ln, (x, y, 0.2), M["navy"] if i % 2 == alt else M["slate"], verts=10)
            box((0.7, ln * 0.9, 0.25), (x, y, r + 0.15), M["steel"])
            box((1.5, 0.3, 2.2), (x, 5.0, 0.2), M["dark"])
            box((r * 0.9, 0.25, 0.4), (x, 5.05, r * 0.72), M["blue"])
            box((0.35, 0.35, 0.35), (x + 1.2, 5.2, 2.0), M["amber"], detail=True)
        box((16.5, 1.2, 0.5), (0, -8.5, 0.2), M["steel"])  # the pipe run behind
        cyl(1.3, 3.4, (7.5 if alt else -7.5, 7.5, 0.2), M["slate"], verts=8)


def compact_high(M, rng, kind, alt):
    box((27.5, 27.5, 3.0), (0, 0, 0), M["steel"], bevel=0.5)
    for s in (-1, 1):
        box((26, 0.5, 0.2), (0, s * 13.4, 3.0), M["hazard"], detail=True)
    if kind == 0:  # a stepped tower under a spire crown
        height = rng.uniform(78, 92) if alt else rng.uniform(52, 64)
        steps = [(24.0, 0.5), (20.0, 0.3), (15.0, 0.2)] if alt else [(25.0, 0.38), (19.0, 0.38), (13.0, 0.24)]
        z = 3.0
        for i, (b, share) in enumerate(steps):
            h = (height * 0.8) * share
            box((b, b, h), (0, 0, z), M["slate"] if i == 1 else M["navy"], bevel=1.0)
            pilasters(M, b, b, z, h)
            slits(M, b, b, z + 1.5, h - 2, every=3.4)
            box((b + 0.8, b + 0.8, 0.6), (0, 0, z + h - 0.3), M["steel"])
            z += h
        box((9, 9, 5), (0, 0, z), M["slate"], bevel=0.5)
        box((9.4, 9.4, 0.7), (0, 0, z + 5), M["blue"])
        cone(5.2, height * 0.1, (0, 0, z + 5.7), M["navy"], verts=4, top=0.25, turn=math.pi / 4)
        cyl(0.22, height * 0.1, (0, 0, z + 5.7 + height * 0.1), M["steel"], verts=6, detail=True)
        box((5, 0.5, 3.2), (0, 12.6, 3.0), M["dark"])
    elif kind == 1:  # twin slabs tied together by gantries
        h1, h2 = rng.uniform(58, 72), rng.uniform(40, 52)
        size = (20.0, 9.0) if alt else (9.0, 20.0)
        for s, h in ((-1, h1), (1, h2)):
            at = (0, s * 7.5, 3.0) if alt else (s * 7.5, 0, 3.0)
            box((size[0], size[1], h), at, M["navy"] if s < 0 else M["slate"], bevel=0.8)
            pilasters(M, size[0], size[1], 3.0, h, at=at)
            box((size[0] + 0.8, size[1] + 0.8, 0.7), (at[0], at[1], 3.0 + h), M["steel"])
            for row in range(int((h - 4) // 3.6)):
                zz = 5.5 + row * 3.6
                for side in (-1, 1):
                    if alt:
                        box((size[0] * 0.78, 0.3, 0.55), (at[0], at[1] + side * (size[1] / 2 + 0.05), zz), M["blue"])
                    else:
                        box((0.3, size[1] * 0.78, 0.55), (at[0] + side * (size[0] / 2 + 0.05), at[1], zz), M["blue"])
        for zz in (h2 * 0.45, h2 * 0.85):  # the gantries
            box((3.0, 7.0, 2.2) if alt else (7.0, 3.0, 2.2), (rng.uniform(-5, 5) if alt else 0, 0 if alt else rng.uniform(-5, 5), 3.0 + zz), M["steel"], bevel=0.2)
        tall = (0, -7.5) if alt else (-7.5, 0)
        short = (0, 7.5) if alt else (7.5, 0)
        cyl(0.25, 12, (tall[0], tall[1], 3.7 + h1), M["steel"], verts=6, detail=True)
        box((4, 4, 2.5), (tall[0], tall[1], 3.7 + h1), M["slate"], bevel=0.4)
        twin_turret(M, (short[0], short[1], 3.7 + h2), scale=0.7)
    else:  # wings round a court, under a crowned keep
        h = rng.uniform(34, 46)
        s = -1 if alt else 1
        box((26, 8, h), (0, -9, 3.0), M["navy"], bevel=0.8)
        slits(M, 26, 8, 4.5, h - 2, every=3.6, at=(0, -9))
        box((26.8, 8.8, 0.7), (0, -9, 3.0 + h), M["steel"])
        wing = h * rng.uniform(0.55, 0.75)
        for side in ((-1, 1) if not alt else (s,)):
            box((8, 17, wing), (side * 9, 4, 3.0), M["slate"], bevel=0.8)
            slits(M, 8, 17, 4.5, wing - 2, every=3.6, at=(side * 9, 4))
            box((8.8, 17.8, 0.7), (side * 9, 4, 3.0 + wing), M["steel"])
        kx = -s * 9 if alt else 0.0
        ky = 6.0 if alt else -9.0
        base = 3.0 if alt else 3.7 + h
        kh = h * 1.5 if alt else h * 0.45
        box((7, 7, kh), (kx, ky, base), M["navy"], bevel=0.6)  # the keep
        pilasters(M, 7, 7, base, kh, at=(kx, ky))
        slits(M, 7, 7, base + 1.5, kh - 2, every=3.4, at=(kx, ky))
        box((7.6, 7.6, 0.8), (kx, ky, base + kh), M["blue"])
        cone(4.4, 9, (kx, ky, base + kh + 0.8), M["slate"], verts=4, top=0.2, turn=math.pi / 4)
        cyl(0.2, 7, (kx, ky, base + kh + 9.8), M["steel"], verts=6, detail=True)
        for side in (-1, 1):
            box((0.5, 0.5, 0.5), (side * 4.5, 12.5, 3.2), M["amber"], detail=True)


# --- Ashen Collective: black spiked hives and needles lit red, standing on roots and legs ----------

def ashen_low(M, rng, kind, alt):
    box((19.6, 19.6, 0.2), (0, 0, 0), M["moss"])
    box((19.6, 0.3, 0.08), (0, 9.6, 0.2), M["red"], detail=True)
    if kind == 0:  # a cluster of A-frame hives
        spots = [(-4.5, -3.5), (4.5, -4.0), (0.5, 3.5)] if not alt else [(-5, -5), (5, -5), (-5, 4), (5, 3.5)]
        for i, (x, y) in enumerate(spots):
            r = rng.uniform(4.2, 5.4) if not alt else rng.uniform(3.6, 4.4)
            h = rng.uniform(8.0, 12.5)
            turn = math.pi / 4
            cone(r, h, (x, y, 0.2), M["black"], verts=4, top=0.25, turn=turn)
            cone(r * 1.08, h * 0.3, (x, y, 0.2), M["char"], verts=4, top=r * 0.8, turn=turn)  # the lower plates
            spike(0.28, (x, y, h - 0.3), (x + rng.uniform(-0.6, 0.6), y, h + 3.0), M["char"])
            a = cone_pt(r, 0.25, h, 4, 0, 0.6, turn, mid=True, at=(x, y, 0.2))
            b = cone_pt(r, 0.25, h, 4, 0, h * 0.45, turn, mid=True, at=(x, y, 0.2))
            spike(0.32, a, b, M["red"], tip=0.1)  # the red door slit, up the front
            if i == 0:
                for k in (1, 3):
                    spike(0.2, cone_pt(r, 0.25, h, 4, k, h * 0.5, turn, at=(x, y, 0.2)), cone_pt(r * 1.7, r, h, 4, k, h * 0.85, turn, at=(x, y, 0.2)), M["char"], detail=True)
    elif kind == 1:  # pods on spider legs
        pods = [(0.0, -1.0, 1.0)] if not alt else [(-4.5, -3.0, 0.72), (4.0, 2.5, 0.62)]
        for x, y, k in pods:
            z = rng.uniform(5.0, 6.5) * k + 1.5
            ball(1.0, (x, y, z), M["black"], sx=5.0 * k, sy=6.0 * k, sz=3.0 * k, segs=8, rings=5)
            ball(1.0, (x, y, z + 0.2 * k), M["char"], sx=5.3 * k, sy=6.3 * k, sz=1.1 * k, segs=8, rings=4)  # a plate round its middle
            n = 6 if not alt else 4
            for i, foot in enumerate(around(n, 8.6 * k, 0.2, start=TAU / n / 2, at=(x, y))):
                knee = (x + (foot[0] - x) * 0.72, y + (foot[1] - y) * 0.72, z + 2.2 * k)
                spike(0.42 * k, (x + (foot[0] - x) * 0.4, y + (foot[1] - y) * 0.4, z), knee, M["char"], tip=0.3 * k)
                spike(0.34 * k, knee, foot, M["black"], tip=0.1)
            box((2.6 * k, 0.3, 0.5 * k), (x, y + 5.8 * k, z - 0.1), M["red"])
            for sx in (-1, 1):
                box((0.3, 3.0 * k, 0.4 * k), (x + sx * 4.9 * k, y, z - 0.1), M["red"], detail=True)
            spike(0.22, (x, y - 2 * k, z + 2.6 * k), (x, y - 3.4 * k, z + 6.0 * k), M["char"], detail=True)
            spike(0.22, (x, y + 1 * k, z + 2.8 * k), (x, y + 1.6 * k, z + 5.2 * k), M["char"], detail=True)
    else:  # a thorn longhouse
        ln = 13.0 if alt else 16.0
        h = rng.uniform(8.0, 10.5)
        w = 8.5 if alt else 9.5
        x0 = -3.5 if alt else 0.0
        prism(w, h, ln, (x0, 0, 0.2), M["black"])
        prism(w * 1.12, h * 0.28, ln * 0.94, (x0, 0, 0.2), M["char"])
        box((0.25, ln * 0.9, 0.25), (x0, 0, h + 0.1), M["red"])  # the ridge line
        n = 4 if alt else 5
        for i in range(n):  # crossed thorn ribs over the ridge
            y = -ln / 2 + (i + 0.5) * ln / n
            for s in (-1, 1):
                spike(0.26, (x0 + s * w * 0.3, y, h * 0.42), (x0 - s * 1.6, y, h + 2.6), M["char"])
        spike(0.45, (x0, ln / 2 + 0.05, 0.6), (x0, ln / 2 + 0.05, h * 0.55), M["red"], tip=0.08)
        if alt:  # a hive beside it
            r, hh = 4.6, rng.uniform(9, 12)
            cone(r, hh, (5.5, -2.0, 0.2), M["black"], verts=4, top=0.2, turn=math.pi / 4)
            spike(0.3, cone_pt(r, 0.2, hh, 4, 0, 0.6, math.pi / 4, mid=True, at=(5.5, -2.0, 0.2)), cone_pt(r, 0.2, hh, 4, 0, hh * 0.5, math.pi / 4, mid=True, at=(5.5, -2.0, 0.2)), M["red"], tip=0.1)
            spike(0.25, (5.5, -2.0, hh - 0.2), (5.9, -2.0, hh + 2.8), M["char"])


def _ashen_spire(M, rng, at, r, h, verts=6, roots=5, crown=4):
    """A needle spire: red light up every edge, a spiked crown, splayed roots."""
    x, y, z = at
    turn = rng.uniform(0, TAU)
    cone(r, h, at, M["black"], verts=verts, top=r * 0.14, turn=turn)
    cone(r * 1.12, h * 0.16, at, M["char"], verts=verts, top=r * 0.92, turn=turn)
    for k in range(verts):
        spike(0.2 + r * 0.02, cone_pt(r, r * 0.14, h, verts, k, h * 0.14, turn, at=at), cone_pt(r, r * 0.14, h, verts, k, h * 0.93, turn, at=at), M["red"], tip=0.08)
    for foot in (around(roots, r * 2.0, z, start=turn, at=(x, y)) if roots else []):
        spike(r * 0.2, foot, (x + (foot[0] - x) * 0.3, y + (foot[1] - y) * 0.3, z + h * 0.2), M["char"], tip=r * 0.1)
    for i, p in enumerate(around(crown, r * 0.75, z + h + h * 0.07, start=turn, at=(x, y))):
        spike(0.3, (x + (p[0] - x) * 0.2, y + (p[1] - y) * 0.2, z + h * 0.9), p, M["char"])
    spike(0.28, (x, y, z + h - 0.5), (x, y, z + h + h * 0.1), M["char"])


def ashen_high(M, rng, kind, alt):
    cyl(14.6, 1.6, (0, 0, 0), M["char"], verts=8, turn=math.pi / 8)
    cyl(14.8, 0.25, (0, 0, 1.6), M["red"], verts=8, turn=math.pi / 8)
    cyl(14.2, 0.3, (0, 0, 1.75), M["black"], verts=8, turn=math.pi / 8)
    if kind == 0 and not alt:  # one great needle on its roots
        h = rng.uniform(64, 76)
        _ashen_spire(M, rng, (0, 0, 1.8), 7.4, h, verts=6, roots=5, crown=5)
        cyl(3.0, 0.6, (0, 9.5, 5.5), M["core"], verts=8, rot=(math.pi / 2, 0, 0))  # the furnace hatch
        cyl(3.6, 0.5, (0, 9.2, 5.5), M["char"], verts=8, rot=(math.pi / 2, 0, 0))
    elif kind == 0:  # a needle carried on giant legs
        h = rng.uniform(58, 70)
        z = rng.uniform(19, 24)
        ball(1.0, (0, 0, z), M["black"], sx=8.0, sy=8.0, sz=5.0, segs=8, rings=5)
        ball(1.0, (0, 0, z + 0.4), M["char"], sx=8.5, sy=8.5, sz=1.6, segs=8, rings=4)
        cyl(2.8, 1.2, (0, 0, z - 5.6), M["core"], verts=8)  # the furnace under its belly
        for foot in around(6, 13.6, 1.8, start=TAU / 12):
            knee = (foot[0] * 0.78, foot[1] * 0.78, z + 9.0)
            spike(1.1, (foot[0] * 0.4, foot[1] * 0.4, z), knee, M["char"], tip=0.8)
            spike(0.9, knee, foot, M["black"], tip=0.2)
        _ashen_spire(M, rng, (0, 0, z + 3.5), 4.6, h, verts=6, roots=0, crown=5)
        for sx in (-1, 1):
            box((0.4, 5.0, 0.6), (sx * 7.9, 0, z), M["red"])
        box((5.0, 0.4, 0.6), (0, 7.9, z), M["red"])
    elif kind == 1 and not alt:  # a knot of spires, bridged
        spots = [(-6.0, -5.0), (6.5, -3.0), (0.0, 7.0)]
        top = rng.uniform(70, 88)
        hs = [top, top * rng.uniform(0.7, 0.8), top * rng.uniform(0.5, 0.6)]
        for (x, y), h in zip(spots, hs):
            _ashen_spire(M, rng, (x, y, 1.8), 4.6, h, verts=5, roots=4, crown=3)
        for i in range(len(spots)):  # the bridges
            a, b = spots[i], spots[(i + 1) % len(spots)]
            zz = 1.8 + hs[-1] * (0.35 + 0.22 * i)
            spike(0.9, (a[0], a[1], zz), (b[0], b[1], zz + 3.0), M["char"], tip=0.9)
            spike(0.25, (a[0], a[1], zz + 1.0), (b[0], b[1], zz + 4.0), M["red"], tip=0.25, detail=True)
    elif kind == 1:  # hives stacked into a tower, thorns at every eave
        tiers = rng.choice((4, 5))
        z = 1.8
        r = 13.0
        turn = math.pi / 4
        for i in range(tiers):
            th = rng.uniform(13, 17) * (1 - i * 0.06)
            top = r * 0.52
            cone(r, th, (0, 0, z), M["black"] if i % 2 == 0 else M["char"], verts=4, top=top, turn=turn)
            cyl(r * 1.02, 0.35, (0, 0, z), M["red"], verts=4, turn=turn)
            for k in range(4):
                c = cone_pt(r, top, th, 4, k, 0.3, turn, out=1.0, at=(0, 0, z))
                spike(0.5, c, (c[0] * 1.22, c[1] * 1.22, z + th * 0.42), M["char"])
                a = cone_pt(r, top, th, 4, k, th * 0.2, turn, mid=True, at=(0, 0, z))
                b = cone_pt(r, top, th, 4, k, th * 0.85, turn, mid=True, at=(0, 0, z))
                spike(0.3, a, b, M["red"], tip=0.1)
            z += th * 0.86
            r = top * 1.5
        spike(1.4, (0, 0, z), (0, 0, z + 20.0), M["black"], verts=5)
    else:  # the great hive
        h = rng.uniform(56, 68) if alt else rng.uniform(44, 52)
        r = 16.5 if not alt else 14.5
        turn = math.pi / 4
        at = (0, 0, 1.8)
        cone(r, h, at, M["black"], verts=4, top=1.6, turn=turn)
        cone(r * 1.06, h * 0.22, at, M["char"], verts=4, top=r * 0.86, turn=turn)
        for k in range(4):  # chitin ribs up the corners, red light up each face
            spike(1.0, cone_pt(r, 1.6, h, 4, k, 0.5, turn, at=at), cone_pt(r, 1.6, h, 4, k, h * 1.04, turn, out=1.25, at=at), M["char"], tip=0.25)
            for off in ((0.0,) if not alt else (-0.18, 0.18)):
                a = cone_pt(r, 1.6, h, 4, k + off, h * 0.3, turn, mid=True, at=at)
                b = cone_pt(r, 1.6, h, 4, k + off * 0.3, h * 0.92, turn, mid=True, at=at)
                spike(0.34, a, b, M["red"], tip=0.1)
        front = cone_pt(r, 1.6, h, 4, 0, h * 0.14, turn, mid=True, out=1.0, at=at)
        cyl(3.4, 1.2, (front[0], front[1] + 0.3, front[2]), M["core"], verts=8, rot=(math.pi / 2, 0, 0))
        cyl(4.1, 0.9, (front[0], front[1] + 0.1, front[2]), M["char"], verts=8, rot=(math.pi / 2, 0, 0))
        for p in around(6, 4.5, 1.8 + h + 7.0):
            spike(0.4, (p[0] * 0.3, p[1] * 0.3, 1.8 + h - 2.0), p, M["char"])
        spike(0.5, (0, 0, 1.8 + h - 1.0), (0, 0, 1.8 + h + 11.0), M["char"])


# --- Luminar Accord: pale faceted spires braced by leaning blades, green light in the seams --------

def _luminar_spire(M, at, r, h, verts=6, blades=3, reach=1.9, turn=0.0, drum=0.22):
    """A needle on a faceted drum, a green light bar up its front, blades leaning in to brace it."""
    x, y, z = at
    dh = h * drum
    cyl(r, dh, at, M["grey"], verts=verts, turn=turn)
    cone(r * 0.96, h - dh, (x, y, z + dh), M["pale"], verts=verts, top=r * 0.06, turn=turn)
    cyl(r * 1.04, 0.3, (x, y, z + dh), M["green"], verts=verts, turn=turn)
    a = cone_pt(r * 0.96, r * 0.06, h - dh, verts, 0, 0.6, turn, mid=True, out=1.04, at=(x, y, z + dh))
    b = cone_pt(r * 0.96, r * 0.06, h - dh, verts, 0, (h - dh) * 0.7, turn, mid=True, out=1.06, at=(x, y, z + dh))
    spike(max(0.16, r * 0.07), a, b, M["crystal"], tip=0.06)
    for foot in around(blades, r * reach, z, start=turn + math.pi / 2 + TAU / max(blades, 1) / 2, at=(x, y)):
        spike(r * 0.5, foot, (x + (foot[0] - x) * 0.18, y + (foot[1] - y) * 0.18, z + h * 0.6), M["pale"], tip=r * 0.08, flat=0.22)


def luminar_low(M, rng, kind, alt):
    box((19.6, 19.6, 0.25), (0, 0, 0), M["deck"])
    for s in (-1, 1):
        box((0.25, 19.0, 0.06), (s * 9.3, 0, 0.25), M["green"], detail=True)
    box((19.0, 0.25, 0.06), (0, 9.3, 0.25), M["green"], detail=True)
    if kind == 0:  # short spires on a plated base
        box((15, 15, 1.0), (0, -1, 0.25), M["pale"], bevel=0.4)
        spots = [(-3.8, -3.5), (3.8, -2.5), (0.0, 3.0)] if not alt else [(-4.2, -4.5), (4.2, -4.5), (-4.2, 2.5), (4.2, 2.5)]
        for i, (x, y) in enumerate(spots):
            h = rng.uniform(9.5, 14.0) if not alt else rng.uniform(7.5, 11.5)
            _luminar_spire(M, (x, y, 1.25), 2.5 if not alt else 2.1, h, verts=6, blades=2 if alt else 3, reach=1.7)
    elif kind == 1:  # a chapel house under a steep roof
        s = -1 if alt else 1
        w, ln = (7.5, 13.0) if not alt else (9.0, 11.0)
        h = rng.uniform(4.6, 5.6)
        rh = rng.uniform(6.0, 8.0)
        x0 = -s * 2.0
        box((w, ln, h), (x0, -1.5, 0.25), M["pale"], bevel=0.4)
        prism(w + 0.8, rh, ln + 0.6, (x0, -1.5, h + 0.25), M["grey"])
        box((1.8, 0.3, h + rh * 0.55), (x0, ln / 2 - 1.35, 0.25), M["crystal"])  # the crystal front
        box((w * 0.9, 0.25, 0.3), (x0, ln / 2 - 1.4, h + 0.1), M["green"], detail=True)
        for i in range(3):  # blades down both sides
            y = -1.5 - ln / 2 + (i + 0.5) * ln / 3
            for side in (-1, 1):
                spike(1.5, (x0 + side * (w / 2 + 2.6), y, 0.25), (x0 + side * (w / 2 - 0.3), y, h + rh * 0.35), M["pale"], tip=0.15, flat=0.2)
        cone(0.55, 5.5, (x0, ln / 2 - 2.2, h + rh), M["pale"], verts=4)
        cone(1.0, rng.uniform(5.0, 7.0), (s * 6.5, 5.5, 0.9), M["crystal"], verts=4)  # an obelisk in the yard
        cyl(1.5, 0.65, (s * 6.5, 5.5, 0.25), M["grey"], verts=6)
    else:  # plated terraces stepping up
        s = -1 if alt else 1
        steps = [(16.0, 12.0, 0.0, -2.0), (11.0, 9.0, s * 2.0, -3.0), (6.0, 6.0, s * 4.0, -4.0)]
        z = 0.25
        for i, (w, d, x, y) in enumerate(steps):
            h = rng.uniform(2.8, 3.6) if not alt else rng.uniform(3.4, 4.4)
            box((w, d, h), (x, y, z), M["pale"] if i != 1 else M["grey"], bevel=0.5)
            box((w * 0.86, 0.25, 0.35), (x, y + d / 2 + 0.05, z + h - 0.9), M["green"])
            box((w + 0.5, d + 0.5, 0.3), (x, y, z + h), M["grey"])
            z += h + 0.3
        _luminar_spire(M, (s * 4.0, -4.0, z), 1.5, rng.uniform(7.0, 10.0), verts=6, blades=3, reach=1.6)
        cone(0.9, 4.5, (-s * 6.5, 6.5, 0.85), M["crystal"], verts=4)
        cyl(1.3, 0.6, (-s * 6.5, 6.5, 0.25), M["grey"], verts=6)


def luminar_high(M, rng, kind, alt):
    box((27.5, 27.5, 1.5), (0, 0, 0), M["grey"], bevel=0.5)
    for s in (-1, 1):
        box((26.5, 0.3, 0.08), (0, s * 13.2, 1.5), M["green"], detail=True)
        box((0.3, 26.5, 0.08), (s * 13.2, 0, 1.5), M["green"], detail=True)
    if kind == 0:  # one cathedral needle
        h = rng.uniform(88, 100) if alt else rng.uniform(66, 78)
        _luminar_spire(M, (0, 0, 1.5), 7.0 if alt else 8.2, h, verts=8 if not alt else 6, blades=6 if not alt else 4, reach=1.75, drum=0.16)
        for p in around(4 if alt else 3, 9.5, 1.5, start=0.6):  # lesser needles at its feet
            _luminar_spire(M, p, 1.7, h * rng.uniform(0.2, 0.3), verts=6, blades=0)
    elif kind == 1:  # a pyramid of blades about a core, spires on top
        h = rng.uniform(58, 70) if not alt else rng.uniform(74, 86)
        n = 8 if not alt else 6
        core = 4.6
        cyl(core, h * 0.52, (0, 0, 1.5), M["grey"], verts=n)
        for k in range(n):  # a light bar on every face of the core
            a = cone_pt(core, core, 1, n, k, 0, 0, mid=True, out=1.03)
            box((0.5, 0.5, h * 0.44), (a[0], a[1], 1.5 + h * 0.05), M["green"])
        for foot in around(n, 13.2, 1.5, start=TAU / n / 2):
            spike(3.4, foot, (foot[0] * 0.2, foot[1] * 0.2, 1.5 + h * 0.56), M["pale"], tip=0.5, flat=0.2)
        cyl(core + 1.2, 1.2, (0, 0, 1.5 + h * 0.52), M["pale"], verts=n)
        cone(3.8, h * 0.48, (0, 0, 2.7 + h * 0.52), M["pale"], verts=6, top=0.2)
        for p in around(3 if not alt else 4, 3.6, 2.7 + h * 0.52, start=0.5):
            cone(1.5, h * rng.uniform(0.2, 0.3), p, M["pale"], verts=6, top=0.1)
        box((0.6, 0.6, h * 0.3), (0, 3.4, 2.7 + h * 0.52), M["crystal"])
    else:  # twin spires joined by decks
        h1 = rng.uniform(74, 90)
        h2 = h1 * rng.uniform(0.7, 0.85)
        gap = 6.8
        spots = [(-gap, 0.0), (gap, 0.0)] if not alt else [(0.0, -gap), (0.0, gap)]
        for (x, y), h in zip(spots, (h1, h2)):
            _luminar_spire(M, (x, y, 1.5), 5.6, h, verts=6, blades=0, drum=0.2)
        for zz in (h2 * 0.25, h2 * 0.45):  # the decks between them
            box((gap * 2, 4.5, 1.1) if not alt else (4.5, gap * 2, 1.1), (0, 0, 1.5 + zz), M["pale"], bevel=0.3)
            box((gap * 1.6, 4.7, 0.25) if not alt else (4.7, gap * 1.6, 0.25), (0, 0, 1.5 + zz - 0.25), M["green"])
        for (x, y), h in zip(spots, (h1, h2)):  # blades on the outer sides only
            for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
                out = (x + dx * 6.5, y + dy * 6.5) if not alt else (x + dx * 6.5, y + dy * 6.5)
                if abs(out[0]) > 13.4 or abs(out[1]) > 13.4 or (not alt and dx * x < 0) or (alt and dy * y < 0):
                    continue
                spike(2.2, (out[0], out[1], 1.5), (x + dx * 1.0, y + dy * 1.0, 1.5 + h * 0.5), M["pale"], tip=0.3, flat=0.2)


# --- Coma Conglomerate: flowing gunmetal traced with gold, discs afloat on columns of light --------

def coma_low(M, rng, kind, alt):
    cyl(9.8, 0.25, (0, 0, 0), M["black"], verts=20)
    ring(8.8, 0.12, (0, 0, 0.3), M["gold"], detail=True)
    if kind == 0:  # shells like poured metal
        shells = [(0.0, -1.0, 7.0, 5.6, 4.8)] if not alt else [(-2.5, -2.0, 5.2, 4.6, 4.4), (3.2, 1.5, 4.0, 3.6, 3.0)]
        for x, y, a, b, c in shells:
            c *= rng.uniform(0.9, 1.2)
            ball(1.0, (x, y, 0.25), M["gun"], sx=a, sy=b, sz=c, segs=14, rings=8, dome=True)
            ring(1.0, 0.04, (x, y, 0.45), M["gold"], sx=a * 1.01, sy=b * 1.01)
            ring(1.0, 0.03, (x, y, 0.25 + c * 0.6), M["gold"], sx=a * 0.81, sy=b * 0.81, detail=True)
            ring(1.5, 0.16, (x, y + b * 0.93, 1.9), M["gold"], upright=True)  # the gold-lined opening
            cyl(1.4, 0.3, (x, y + b * 0.9, 1.9), M["black"], verts=12, rot=(math.pi / 2, 0, 0))
            spike(1.6, (x - a * 0.55, y - b * 0.4, 0.25 + c * 0.55), (x - a * 1.25, y - b * 1.1, 0.25), M["gun"], tip=0.1, flat=0.35)  # a swept tail
    elif kind == 1:  # a home afloat on a column of light
        z = rng.uniform(4.5, 6.5) if not alt else rng.uniform(7.0, 9.0)
        cyl(3.2, 0.5, (0, 0, 0.25), M["gun"], verts=16)
        ring(3.0, 0.1, (0, 0, 0.8), M["gold"], detail=True)
        cyl(0.9, z, (0, 0, 0.5), M["light"], verts=10)
        tiers = [(7.0, 1.3), (5.2, 1.3), (3.2, 1.6)] if not alt else [(5.0, 1.0), (6.6, 1.2), (4.4, 1.2), (2.4, 1.6)]
        zz = z + 0.4
        for r, h in tiers:
            cyl(r, h, (0, 0, zz), M["gun"], verts=18)
            ring(r, 0.11, (0, 0, zz + 0.1), M["gold"])
            zz += h
        cone(0.8, 4.5, (0, 0, zz), M["goldm"], verts=6)
        ball(0.5, (0, 0, zz + 4.9), M["light"], segs=8, rings=4, detail=True)
    else:  # a cluster of ringed domes
        spots = [(-4.0, -3.0, 4.4), (4.2, -1.0, 3.4), (-0.5, 4.6, 2.8)] if not alt else [(-4.6, 3.0, 3.2), (4.6, 3.0, 3.2), (0.0, -3.5, 4.8), (0.0, 5.6, 2.0)]
        for i, (x, y, r) in enumerate(spots):
            base = rng.uniform(0.9, 2.4)
            cyl(r, base, (x, y, 0.25), M["black"], verts=16)
            ball(r * 0.97, (x, y, 0.25 + base), M["gun"], segs=14, rings=8, dome=True)
            ring(r, 0.1, (x, y, 0.3 + base), M["gold"])
            if i == 0 or (alt and i == 2):
                cone(0.35, r * 1.7, (x, y, base + r * 0.9), M["goldm"], verts=5)
                spike(0.12, (x, y, base + r * 1.8), (x + 0.9, y, base + r * 2.25), M["goldm"], detail=True)
                spike(0.12, (x, y, base + r * 1.55), (x - 0.8, y, base + r * 1.95), M["goldm"], detail=True)


def _thorn_spire(M, rng, at, r, h, verts=5):
    """A thin spire with thorns breaking from its side."""
    x, y, z = at
    cone(r, h, at, M["gun"], verts=verts, top=0.08)
    for f in (0.45, 0.62, 0.78):
        a = rng.uniform(0, TAU)
        rr = r * (1 - f)
        spike(0.22 + r * 0.06, (x, y, z + h * f), (x + math.cos(a) * (rr + 1.6), y + math.sin(a) * (rr + 1.6), z + h * f + 3.2), M["gun"], detail=r < 1.4)
    cyl(r * 1.05, 0.25, (x, y, z + h * 0.2), M["gold"], verts=verts, detail=r < 1.4)


def coma_high(M, rng, kind, alt):
    cyl(14.4, 1.4, (0, 0, 0), M["black"], verts=24)
    cyl(12.6, 1.4, (0, 0, 1.4), M["gun"], verts=24)
    ring(13.4, 0.14, (0, 0, 1.5), M["gold"], segs=28)
    if kind == 0:  # a twisting needle
        h = rng.uniform(80, 96) if alt else rng.uniform(60, 72)
        n = 16 if alt else 12
        verts = 4 if alt else 5
        twist = (0.2 if alt else 0.16) * rng.choice((-1, 1))
        z = 2.8
        for i in range(n):
            f0, f1 = i / n, (i + 1) / n
            r0, r1 = 8.6 * (1 - f0) ** 1.25 + 1.0, 8.6 * (1 - f1) ** 1.25 + 1.0
            cyl(r0, h / n, (0, 0, z), M["gun"], verts=verts, top=r1, turn=twist * i)
            if i % 3 == 0:
                cyl(r0 * 1.03, 0.3, (0, 0, z), M["gold"], verts=verts, turn=twist * i)
            z += h / n
        cone(1.0, h * 0.12, (0, 0, z), M["goldm"], verts=verts)
        ring(3.2, 0.2, (0, 9.6, 6.5), M["gold"], upright=True)
    elif kind == 1:  # discs stacked on a column of light
        h = rng.uniform(58, 72) if not alt else rng.uniform(76, 90)
        cyl(1.3, h, (0, 0, 2.8), M["light"], verts=10)
        n = 4 if not alt else 6
        for i in range(n):
            f = i / (n - 1)
            zz = 2.8 + h * (0.14 + 0.72 * f)
            r = 12.5 - 7.0 * f if not alt else 6.0 + 6.0 * math.sin(math.pi * (0.15 + 0.7 * f))
            cyl(r, 2.4, (0, 0, zz), M["gun"], verts=22)
            cyl(r * 0.78, 1.3, (0, 0, zz + 2.4), M["black"], verts=22)
            ring(r, 0.16, (0, 0, zz + 0.15), M["gold"], segs=26)
            ring(r * 0.6, 0.1, (0, 0, zz + 3.75), M["gold"], detail=True)
        cone(2.2, h * 0.2, (0, 0, 2.8 + h), M["gun"], verts=6)
        ball(0.9, (0, 0, 2.8 + h * 1.2 + 0.8), M["light"], segs=8, rings=4)
    else:  # a keep of drums ringed by thorned spires
        h = rng.uniform(62, 74) if not alt else rng.uniform(78, 92)
        z = 2.8
        for r, share in ((11.0, 0.32), (8.6, 0.22), (6.2, 0.16)):
            cyl(r, h * share, (0, 0, z), M["gun"], verts=14)
            ring(r, 0.15, (0, 0, z + h * share - 0.4), M["gold"])
            z += h * share
        cone(4.4, h * 0.42, (0, 0, z), M["gun"], verts=6, top=0.1)
        n = 5 if not alt else 7
        for p in around(n, 11.6, 2.8, start=math.pi / 2 + TAU / n / 2):
            _thorn_spire(M, rng, p, 1.9, h * rng.uniform(0.55, 0.85))
        ring(3.2, 0.24, (0, 11.1, 2.8 + h * 0.17), M["gold"], upright=True)  # the sigil
        box((0.4, 0.3, 7.5), (0, 11.1, 2.8 + h * 0.17 - 3.75), M["gold"])
        box((4.4, 0.3, 0.4), (0, 11.1, 2.8 + h * 0.17 - 0.2), M["gold"])


BUILDERS = {
    "compact": (compact_mats, compact_low, compact_high),
    "ashen": (ashen_mats, ashen_low, ashen_high),
    "luminar": (luminar_mats, luminar_low, luminar_high),
    "coma": (coma_mats, coma_low, coma_high),
}


def pieces(faction):
    """{piece name: (build(M), cells, height)} for the faction's zone housing."""
    _, low, high = BUILDERS[faction]
    out = {}
    for v in range(1, VARIANTS + 1):
        for name, build, cells, height in (("zone_low", low, (2, 2), 14), ("zone_high", high, (3, 3), 95)):
            def make(M, build=build, name=name, v=v):
                build(M, random.Random(f"{faction}/{name}/{v}"), (v - 1) % 3, v > 3)
            out[f"{name}_{v}"] = (make, cells, height)
    return out
