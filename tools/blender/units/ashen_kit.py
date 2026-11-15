"""What the Ashen Collective's units share: black faceted plate (black_plating), every surface a flat
facet, thin lines of the side's light along the seams, engines and visors lit in it, and the hexagon
emblem. These helpers build the shapes the newer Ashen units (aircraft, wheeled vehicles, walkers,
infantry) are made of; the older units each carry their own copies of the colours.
"""

import math

from mathutils import Vector

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT  # noqa: F401

PLATE = Color(0.19, 0.19, 0.21)  # the armour
RAISED = Color(0.28, 0.28, 0.3)  # plates laid over it
RECESS = Color(0.11, 0.11, 0.12)
TYRE = Color(0.07, 0.07, 0.075)
GLASS = Color(0.04, 0.05, 0.07)
ROOF = Color(0.1, 0.1, 0.1)  # painted in the side's colour
LIT = Color(1, 1, 1)  # the side's light

# A faceted cross-section: (across, up) as fractions of the half width and half height.
RIDGE = [(0, 1), (0.55, 0.72), (1, 0.08), (0.72, -0.6), (0, -0.85), (-0.72, -0.6), (-1, 0.08), (-0.55, 0.72)]
FLAT = [(0, 1), (0.8, 0.55), (1, 0.0), (0.8, -0.45), (0, -0.7), (-0.8, -0.45), (-1, 0.0), (-0.8, 0.55)]


def loft(P, sections, colour=PLATE, mask=PLAIN, shape=RIDGE, x=0.0):
    """A faceted body through cross-sections [(z, centre y, half width, half height), ...] from
    back to front; a section with no width is a point."""
    rings = []
    for z, cy, w, h in sections:
        rings.append([Vector((x + a * w, cy + b * h, z)) for a, b in shape])
    for (s0, r0), (s1, r1) in zip(zip(sections, rings), zip(sections[1:], rings[1:])):
        mid = Vector((x, (s0[1] + s1[1]) / 2, (s0[0] + s1[0]) / 2))
        n = len(shape)
        for k in range(n):
            j = (k + 1) % n
            if s0[2] < 1e-4:
                P.poly([r0[0], r1[j], r1[k]], colour, mask, mid)
            elif s1[2] < 1e-4:
                P.poly([r0[k], r0[j], r1[0]], colour, mask, mid)
            else:
                P.poly([r0[k], r0[j], r1[j], r1[k]], colour, mask, mid)
    if sections[0][2] > 1e-4:
        P.poly(rings[0], colour, mask, Vector((x, sections[0][1], sections[0][0] + 1)))
    if sections[-1][2] > 1e-4:
        P.poly(rings[-1], colour, mask, Vector((x, sections[-1][1], sections[-1][0] - 1)))


def plate(P, outline, y, thick, colour=PLATE, mask=PLAIN, bevel=0.0):
    """A flat plate (a wing, a tailplane) of the outline [(x, z), ...] at height y, `thick` deep;
    `bevel` lays a thinner, smaller plate on top for a facet."""
    P.prism([(px, y - thick / 2, pz) for px, pz in outline], (0, thick, 0), colour, mask)
    if bevel:
        cx = sum(p[0] for p in outline) / len(outline)
        cz = sum(p[1] for p in outline) / len(outline)
        inner = [(cx + (px - cx) * (1 - bevel), cz + (pz - cz) * (1 - bevel)) for px, pz in outline]
        P.prism([(px, y + thick / 2, pz) for px, pz in inner], (0, thick * 0.5, 0), colour, mask)


def fin(P, root, tip, chord_root, chord_tip, thick=0.18, colour=PLATE):
    """A fin from its root's leading edge `root` (x, y, z) to its tip's `tip`, swept back."""
    a, b = Vector(root), Vector(tip)
    pts = [a, b, b - Vector((0, 0, chord_tip)), a - Vector((0, 0, chord_root))]
    n = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
    P.prism([tuple(p - n * thick / 2) for p in pts], tuple(n * thick), colour)


def edge(P, a, b, wide=0.08, deep=0.06, face=(0, 1, 0)):
    """A thin line of the side's light from a to b."""
    P.beam(a, b, wide, deep, LIT, SIDE_GLOW, face=face)


def engine(P, at, r, length, glow=True, sides=8, intake=False):
    """A podded jet engine from its intake at `at` (x, y, z) back `length`: faceted, its exhaust
    lit in the side's colour."""
    x, y, z = at
    P.lathe((x, y, z), (0, 0, -1), [(0, r * 0.92), (0.15, r), (length * 0.75, r), (length, r * 0.78)], PLATE, sides=sides, turn=math.pi / sides)
    P.lathe((x, y, z + 0.02), (0, 0, 1), [(0, r * 0.7), (0.04, r * 0.7)], RECESS, sides=sides, turn=math.pi / sides)
    if intake:  # a lit fan deep in the intake
        P.lathe((x, y, z + 0.06), (0, 0, 1), [(0, r * 0.4), (0.03, r * 0.4)], LIT, SIDE_GLOW, sides=sides)
    if glow:
        P.lathe((x, y, z - length - 0.02), (0, 0, -1), [(0, r * 0.62), (0.05, r * 0.62)], LIT, SIDE_GLOW, sides=sides, turn=math.pi / sides)
        P.lathe((x, y, z - length + 0.1), (0, 0, -1), [(0, r * 0.74), (0.14, r * 0.74)], RECESS, sides=sides, turn=math.pi / sides, caps=False)


def rotary(P, at, length, r=0.32, along=(0, 0, 1)):
    """A rotary cannon: a housing and six barrels round its axis, pointing along `along`."""
    a, d = Vector(at), Vector(along).normalized()
    P.lathe(tuple(a), tuple(d), [(0, r * 1.4), (length * 0.35, r * 1.4)], PLATE, sides=8)
    u = d.orthogonal().normalized()
    v = d.cross(u)
    for k in range(6):
        t = math.tau * k / 6
        o = a + (u * math.cos(t) + v * math.sin(t)) * r * 0.75
        P.lathe(tuple(o), tuple(d), [(length * 0.3, r * 0.26), (length, r * 0.26)], RECESS, sides=5)
    P.lathe(tuple(a + d * length * 0.88), tuple(d), [(0, r * 1.15), (length * 0.06, r * 1.15)], PLATE, sides=8)


def gun(P, at, length, r, along=(0, 0, 1), lit=True):
    """A plain faceted barrel with a boxed muzzle, its bore lit."""
    a, d = Vector(at), Vector(along).normalized()
    P.lathe(tuple(a), tuple(d), [(0, r), (length * 0.85, r), (length * 0.85, r * 1.5), (length, r * 1.5)], PLATE, sides=6, turn=math.pi / 6)
    if lit:
        P.lathe(tuple(a + d * (length + 0.01)), tuple(d), [(0, r * 0.6), (0.02, r * 0.6)], LIT, SIDE_GLOW, sides=6)


def missile(P, at, length, r, along=(0, 0, 1)):
    """An air-to-air missile on a short pylon: a faceted body, a pointed nose, small fins."""
    a, d = Vector(at), Vector(along).normalized()
    P.lathe(tuple(a), tuple(d), [(0, r), (length * 0.78, r), (length, 0.0)], RAISED, sides=6)
    for k in range(4):
        t = math.tau * k / 4 + math.pi / 4
        o = Vector((math.cos(t), math.sin(t), 0)) * r * 2.2
        P.beam(tuple(a + d * 0.05), tuple(a + d * 0.05 + o), 0.04, length * 0.12, PLATE, PLAIN, face=tuple(d))
    P.box((0.08, 0.3, length * 0.4), tuple(a + d * length * 0.45 + Vector((0, r + 0.12, 0))), PLATE)


def cells(P, at, n_across, n_up, size, facing=(0, 0, 1)):
    """A missile box: n_across by n_up lit cells in a block looking along `facing` (+Z or -Z)."""
    x, y, z = at
    s = 1 if facing[2] >= 0 else -1
    w, h = n_across * size + 0.1, n_up * size + 0.1
    P.box((w, h, size * 1.6), (x, y, z), PLATE)
    for i in range(n_across):
        for j in range(n_up):
            cx = x + (i - (n_across - 1) / 2) * size
            cy = y + (j - (n_up - 1) / 2) * size
            P.box((size * 0.8, size * 0.8, 0.04), (cx, cy, z + s * size * 0.8), RECESS)
            P.box((size * 0.42, size * 0.42, 0.04), (cx, cy, z + s * (size * 0.8 + 0.02)), LIT, SIDE_GLOW)


def wheel(P, x, y, z, r, w):
    """A big off-road wheel at (x, y, z), `w` across, its hub a faceted cap."""
    s = 1 if x >= 0 else -1
    P.lathe((x - s * w / 2, y, z), (s, 0, 0), [(0, r * 0.9), (w * 0.15, r), (w * 0.85, r), (w, r * 0.9)], TYRE, sides=10, turn=math.pi / 10)
    P.lathe((x + s * w / 2, y, z), (s, 0, 0), [(0, r * 0.55), (0.06, r * 0.45)], RAISED, sides=6)


def hexagon(P, at, r, normal, colour=LIT, mask=SIDE_GLOW):
    """The Ashen hexagon: a lit outline facing along `normal`."""
    n = Vector(normal).normalized()
    u = n.orthogonal().normalized()
    v = n.cross(u)
    c = Vector(at)
    pts = [c + (u * math.cos(math.tau * k / 6 + math.pi / 6) + v * math.sin(math.tau * k / 6 + math.pi / 6)) * r for k in range(7)]
    for a, b in zip(pts, pts[1:]):
        P.beam(tuple(a), tuple(b), r * 0.18, 0.03, colour, mask, face=tuple(n))


def scaled(P, k):
    """P made `k` times bigger about its origin."""
    out = type(P)()
    for corners, n, colour, mask in P:
        out.append(([c * k for c in corners], n, colour, mask))
    return out


def air_views(fly, k=1.0):
    """The render cameras for an aircraft at `fly` metres, `k` times further back for a bigger one."""
    return {
        "front": ((-15 * k, -20 * k, fly + 8.0 * k), (0.3, 0.0, fly), 50, 0.0, (60, 0, 70)),
        "rear": ((14 * k, 20 * k, fly + 7.5 * k), (0, 0, fly), 50, 0.0),
        "side": ((-34 * k, 0, fly + 0.6 * k), (0, 0, fly), 70, 0.0, (40, 0, -60)),
        "head_on": ((0, -34 * k, fly + 0.8 * k), (0, 0, fly), 70, 0.0),
        "top": ((0, -0.1, fly + 52 * k), (0, 0, fly), 62, math.pi / 2, (30, 0, 200)),
        "below": ((-12 * k, -16 * k, fly - 5.0 * k), (0, 0, fly), 50, 0.0, (60, 0, 70)),
    }


def hull(P, L, W, H, nose=1.6, belly=0.8, roof=0.5):
    """A wheeled vehicle's hull: a long faceted box from belly to H, its nose sloped back over
    `nose` metres, the roof's edges chamfered in by `roof`. Front +Z, the middle at z = 0."""
    f, b = L / 2, -L / 2
    P.extrude([(b, belly), (f - 0.5, belly), (f, belly + 0.6), (f - nose * 0.25, H - 0.35), (b + 0.3, H - 0.35), (b, H - 0.8)], -W / 2, W / 2, PLATE)
    P.slab(H - 0.35, (-W / 2, W / 2, b + 0.3, f - nose * 0.25), H + roof * 0.6, (-W / 2 + roof, W / 2 - roof, b + 0.6, f - nose), PLATE)
    for sx in (-1, 1):  # lit lines along the sides, lights at the nose
        P.beam((sx * (W / 2 + 0.01), belly + 0.5, b + 0.6), (sx * (W / 2 + 0.01), belly + 0.5, f - 0.9), 0.06, 0.04, LIT, SIDE_GLOW, face=(sx, 0, 0))
        P.box((W * 0.22, 0.1, 0.05), (sx * W * 0.3, belly + 0.62, f + 0.02), LIT, SIDE_GLOW)


def axles(P, L, W, zs, r=0.78, w=0.62):
    """Wheels each side at the given z positions."""
    for z in zs:
        for sx in (-1, 1):
            wheel(P, sx * (W / 2 - 0.05 + w / 2 - 0.2), r, z, r, w)


def windscreen(P, W, y0, y1, z0, z1):
    """Dark glass across the front of a cab, sloped from (y0, z0) back to (y1, z1)."""
    P.hexa([(-W / 2, y0, z0), (W / 2, y0, z0), (W / 2, y1, z1), (-W / 2, y1, z1)], [(-W / 2, y0 + 0.07, z0), (W / 2, y0 + 0.07, z0), (W / 2, y1 + 0.07, z1), (-W / 2, y1 + 0.07, z1)], GLASS)


def cab_glass(P, L, W, H, nose, roof=0.5):
    """Dark glass on the sloped front of a hull() roof."""
    f = L / 2
    windscreen(P, W - 2 * roof - 0.3, H - 0.33, H + roof * 0.6 - 0.04, f - nose * 0.25 - 0.15, f - nose + 0.12)


def radar(P, at, w, h, tilt=-15):
    """A phased-array radar panel on a post, its face lit with the hexagon."""
    x, y, z = at
    P.box((0.25, 0.8, 0.25), (x, y - 0.4, z), PLATE)
    P.box((w, h, 0.18), (x, y + h / 2, z), PLATE, PLAIN, (tilt, 0, 0))
    hexagon(P, (x, y + h / 2, z + 0.11), min(w, h) * 0.18, (0, 0.25, 1))
