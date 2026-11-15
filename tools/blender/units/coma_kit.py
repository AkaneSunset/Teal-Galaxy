"""What the Coma Conglomerate's units share: dark graphite shells grown rather than built, all
curves, talons and horns, gold filigree let into them (the textures: gunmetal_traces with
hammered_gold on the frame), and amber light in their eyes, their halos and their beams.

Their light is their own amber (GLOW), not the side's colour: the side shows in a band of paint on
each shell (PAINT) and a thin line of the side's light (SIDE_GLOW).
"""

import math

from mathutils import Vector

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT  # noqa: F401
from units.luminar_kit import shell, hoop, tipped  # noqa: F401

GRAPHITE = Color(0.2, 0.19, 0.18)  # the shell
DEEP = Color(0.1, 0.095, 0.09)  # under it: joints, sockets, wells
GOLD = Color(0.7, 0.5, 0.22)  # rims and inlays
AMBER = Color(1.0, 0.62, 0.22)  # their light (GLOW)
LIT = Color(1, 1, 1)  # the side's light (SIDE_GLOW)


def _frames(V, closed=False):
    """Tangents and a twist-free frame (u, v) at each point of a path."""
    n = len(V)
    T = []
    for i in range(n):
        if closed:
            t = V[(i + 1) % n] - V[i - 1]
        else:
            t = V[min(i + 1, n - 1)] - V[max(i - 1, 0)]
        T.append(t.normalized())
    up = Vector((0, 1, 0)) if abs(T[0].y) < 0.9 else Vector((1, 0, 0))
    u = T[0].cross(up).normalized()
    U = []
    for t in T:
        u = (u - t * u.dot(t))
        u = u.normalized() if u.length > 1e-6 else t.orthogonal().normalized()
        U.append(u)
    return T, U, [t.cross(u) for t, u in zip(T, U)]


def tube(P, pts, radii, colour, mask=PLAIN, sides=8, squash=1.0, closed=False, caps=True):
    """A tube through the points, `radii` across at each (one number: the same all along; 0 at an
    end: a point). `squash` (one number, or one for each point) flattens or widens it across (along
    the frame's first axis)."""
    V = [Vector(p) for p in pts]
    R = radii if isinstance(radii, (list, tuple)) else [radii] * len(V)
    T, U, W = _frames(V, closed)
    Q = squash if isinstance(squash, (list, tuple)) else [squash] * len(V)
    rings = [[V[i] + (U[i] * math.cos(math.tau * k / sides) * Q[i] + W[i] * math.sin(math.tau * k / sides)) * R[i] for k in range(sides)] for i in range(len(V))]
    pairs = list(zip(range(len(V)), range(1, len(V))))
    if closed:
        pairs.append((len(V) - 1, 0))
    for a, b in pairs:
        mid = (V[a] + V[b]) / 2
        for k in range(sides):
            j = (k + 1) % sides
            if R[a] < 1e-4:
                P.poly([rings[a][0], rings[b][j], rings[b][k]], colour, mask, mid)
            elif R[b] < 1e-4:
                P.poly([rings[a][k], rings[a][j], rings[b][0]], colour, mask, mid)
            else:
                P.poly([rings[a][k], rings[a][j], rings[b][j], rings[b][k]], colour, mask, mid)
    if caps and not closed:
        if R[0] > 1e-4:
            P.poly(rings[0], colour, mask, V[0] + T[0])
        if R[-1] > 1e-4:
            P.poly(rings[-1], colour, mask, V[-1] - T[-1])


def bezier(a, b, c, d=None, n=8):
    """Points along a quadratic (a, b, c) or cubic (a, b, c, d) curve."""
    a, b, c = Vector(a), Vector(b), Vector(c)
    out = []
    for k in range(n + 1):
        t = k / n
        if d is None:
            p = a * (1 - t) ** 2 + b * 2 * t * (1 - t) + c * t * t
        else:
            p = a * (1 - t) ** 3 + b * 3 * t * (1 - t) ** 2 + c * 3 * t * t * (1 - t) + Vector(d) * t ** 3
        out.append(tuple(p))
    return out


def taper(n, r0, r1=0.0, power=1.0):
    """Radii from r0 down to r1 over n + 1 points."""
    return [r0 + (r1 - r0) * (k / n) ** power for k in range(n + 1)]


def ring(P, at, normal, radius, thick, colour=AMBER, mask=GLOW, sides=28, squash=1.0):
    """A thin ring (a halo) round `at`, facing along `normal`."""
    n = Vector(normal).normalized()
    u = n.orthogonal().normalized()
    v = n.cross(u)
    c = Vector(at)
    pts = [tuple(c + (u * math.cos(math.tau * k / sides) * squash + v * math.sin(math.tau * k / sides)) * radius) for k in range(sides)]
    tube(P, pts, thick, colour, mask, sides=5, closed=True)


def ball(P, at, r, colour=GRAPHITE, mask=PLAIN, sides=8, stacks=4):
    shell(P, at, (r, r, r), colour, mask, "y", sides=sides, stacks=stacks)


def eye(P, at, facing, r, glow=AMBER):
    """An amber eye: a dark socket, a lit iris, a gold rim round it, looking along `facing`."""
    f = Vector(facing).normalized()
    a = Vector(at)
    P.lathe(tuple(a - f * r * 0.4), tuple(f), [(0, r * 1.1), (r * 0.42, r * 1.1)], DEEP, sides=12)
    P.lathe(tuple(a - f * r * 0.05), tuple(f), [(0, r * 0.75), (r * 0.12, r * 0.75)], glow, GLOW, sides=12)
    P.lathe(tuple(a + f * r * 0.06), tuple(f), [(0, r * 0.3), (r * 0.1, r * 0.3)], Color(1.0, 0.9, 0.7), GLOW, sides=10)
    tube(P, [tuple(a + f * r * 0.02 + (f.orthogonal().normalized() * math.cos(math.tau * k / 14) + f.cross(f.orthogonal().normalized()) * math.sin(math.tau * k / 14)) * r * 1.1) for k in range(14)], r * 0.12, GOLD, PLAIN, sides=4, closed=True)


def pods(P, at, across, up, n_across, n_up, r, colour=GRAPHITE):
    """A cluster of round missile pods: a grid n_across by n_up of balls, spaced by their size."""
    a, u, w = Vector(at), Vector(across).normalized(), Vector(up).normalized()
    for i in range(n_across):
        for j in range(n_up):
            p = a + u * (i - (n_across - 1) / 2) * r * 2.05 + w * (j - (n_up - 1) / 2) * r * 2.0
            ball(P, tuple(p), r, colour, sides=8, stacks=4)
            P.lathe(tuple(p + u.cross(w) * r * 0.75), tuple(u.cross(w)), [(0, r * 0.35), (r * 0.3, r * 0.35)], AMBER, GLOW, sides=6)


def talon(P, root, bend, tip, r0, sides=8, glow=True, flat=1.0):
    """A talon: a tapering curved arm from `root` through `bend` to a point at `tip`, an amber light
    near its end if `glow`."""
    pts = bezier(root, bend, tip, n=10)
    tube(P, pts, taper(10, r0, 0.0, 1.6), GRAPHITE, PLAIN, sides=sides, squash=flat)
    if glow:
        p = Vector(pts[7])
        d = (Vector(pts[8]) - Vector(pts[6])).normalized()
        out = Vector((p.x, 0, p.z))
        out = out.normalized() if out.length > 1e-3 else Vector((0, 0, 1))
        out = (out - d * out.dot(d)).normalized()
        r = r0 * 0.42
        P.lathe(tuple(p + out * r * 1.2), tuple(out), [(0, r * 0.75), (r * 0.2, r * 0.75)], AMBER, GLOW, sides=8)


def disc(P, at, r, thick, colour=GRAPHITE, glow=True, sides=20):
    """A hover disc: a flat drum with an amber line round its edge."""
    x, y, z = at
    P.lathe((x, y, z), (0, 1, 0), [(0, r * 0.8), (thick * 0.25, r), (thick * 0.75, r), (thick, r * 0.85)], colour, sides=sides)
    if glow:
        P.lathe((x, y + thick * 0.42, z), (0, 1, 0), [(0, r * 1.015), (thick * 0.16, r * 1.015)], AMBER, GLOW, sides=sides, caps=False)
        P.lathe((x, y - 0.02, z), (0, 1, 0), [(0, r * 0.5), (0.02, r * 0.5)], AMBER, GLOW, sides=sides)


def blade(P, outline, thick, colour=GRAPHITE, mask=PLAIN):
    """A flat curved plate (a wing, a crest): the outline [(x, y, z)] pulled `thick` along its
    facing, centred on it."""
    pts = [Vector(p) for p in outline]
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    n.normalize()
    P.prism([tuple(p - n * thick / 2) for p in pts], tuple(n * thick), colour, mask)


def air_views(fly, k=1.0, lift=0.0):
    """The render cameras for an aircraft at `fly` metres, `k` times further back for a bigger one."""
    return {
        "front": ((-15 * k, -20 * k, fly + 8.0 * k), (0.3, 0.0, fly + lift), 50, 0.0, (60, 0, 70)),
        "rear": ((14 * k, 20 * k, fly + 7.5 * k), (0, 0, fly + lift), 50, 0.0),
        "side": ((-34 * k, 0, fly + 0.6 * k), (0, 0, fly + lift), 70, 0.0, (40, 0, -60)),
        "head_on": ((0, -34 * k, fly + 0.8 * k), (0, 0, fly + lift), 70, 0.0),
        "top": ((0, -0.1, fly + 52 * k), (0, 0, fly), 62, math.pi / 2, (30, 0, 200)),
        "below": ((-12 * k, -16 * k, fly - 5.0 * k), (0, 0, fly + lift), 50, 0.0, (60, 0, 70)),
    }


def scaled(P, k):
    """P made `k` times bigger about its origin."""
    out = type(P)()
    for corners, n, colour, mask in P:
        out.append(([c * k for c in corners], n, colour, mask))
    return out


def around(r, a, y):
    """The point `r` out from the middle at `a` degrees round from the front (+Z), `y` up."""
    t = math.radians(a)
    return (r * math.sin(t), y, r * math.cos(t))


def prong(P, pts, r0, r_tip=0.0, glow_tip=True, sides=8, flat=1.0):
    """A talon along the points `pts` (from its root to its point), tapering from r0, its last
    stretch an amber point if `glow_tip`."""
    n = len(pts) - 1
    R = taper(n, r0, r_tip, 1.3)
    cut = n - 1 if glow_tip else n
    tube(P, pts[:cut + 1], R[:cut + 1], GRAPHITE, PLAIN, sides=sides, squash=flat)
    if glow_tip:
        tube(P, pts[cut - 0:], [R[cut] * 1.05, 0.0], AMBER, GLOW, sides=sides, squash=flat)


def missile(P, at, along, length, r, tip=GOLD):
    """A missile pod: a round-nosed tube along `along`, a gold nose cone at its front."""
    P.lathe(at, along, [(0, r * 0.6), (r * 0.6, r), (length * 0.78, r), (length * 0.8, r * 0.82)], GRAPHITE, sides=10)
    a, d = Vector(at), Vector(along).normalized()
    P.lathe(tuple(a + d * length * 0.8), tuple(d), [(0, r * 0.82), (length * 0.2, 0.0)], tip, GLOW if tip == AMBER else PLAIN, sides=10)
    P.lathe(tuple(a + d * length * 0.5), tuple(d), [(0, r * 1.06), (r * 0.25, r * 1.06)], GOLD, sides=10)
