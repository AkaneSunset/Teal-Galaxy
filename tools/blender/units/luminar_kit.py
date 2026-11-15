"""What the Luminar Accord's units share: smooth white ceramic shells banded in brass, dark works
underneath, and light in the side's colour along seams, under hover skirts and in eyes and muzzles."""

import math

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

CERAMIC = Color(0.86, 0.84, 0.8)  # the shell
SHADE = Color(0.66, 0.64, 0.61)  # panels set into it
BRASS = Color(0.66, 0.47, 0.2)
OLD = Color(0.42, 0.3, 0.14)  # brass in shadow: joints, ducts
WORKS = Color(0.09, 0.095, 0.1)  # the dark machinery underneath
GLASS = Color(0.04, 0.05, 0.06)
LIT = Color(1, 1, 1)  # glows in the side's colour

AXES = {"x": ((1, 0, 0), (0, 1, 0), (0, 0, 1)), "y": ((0, 1, 0), (0, 0, 1), (1, 0, 0)), "z": ((0, 0, 1), (1, 0, 0), (0, 1, 0))}


def shell(P, at, radii, colour, mask=PLAIN, axis="y", lo=-1.0, hi=1.0, sides=16, stacks=6, grow=0.0, arc=(0.0, 1.0)):
    """An ellipsoid (or a slice of one) centred on `at` with radii (rx, ry, rz): cut into `stacks`
    bands along `axis` between `lo` and `hi` (-1 to 1 along it), `sides` round. `grow` makes it that
    much bigger all over, for a band standing proud of a shell the same shape; `arc` keeps only
    part of the way round (fractions of a turn, from the first of the other two axes)."""
    w, u, v = AXES[axis]
    r = [x + grow for x in radii]

    def point(t, a):
        s = math.sqrt(max(0.0, 1.0 - t * t))
        d = [w[i] * t + (u[i] * math.cos(a) + v[i] * math.sin(a)) * s for i in range(3)]
        return (at[0] + d[0] * r[0], at[1] + d[1] * r[1], at[2] + d[2] * r[2])
    ts = [math.sin(math.asin(lo) + (math.asin(hi) - math.asin(lo)) * k / stacks) for k in range(stacks + 1)]
    n = max(1, round(sides * (arc[1] - arc[0])))
    angles = [math.tau * (arc[0] + (arc[1] - arc[0]) * k / n) for k in range(n + 1)]
    for t0, t1 in zip(ts, ts[1:]):
        for a0, a1 in zip(angles, angles[1:]):
            quad = [point(t0, a0), point(t0, a1), point(t1, a1), point(t1, a0)]
            if t0 <= -0.9999:
                quad = quad[1:]
            elif t1 >= 0.9999:
                quad = quad[:3]
            P.poly(quad, colour, mask, at)
    if arc == (0.0, 1.0):
        for t in (lo, hi):  # close a cut end
            if abs(t) < 0.9999:
                ring = [point(t, a) for a in angles[:-1]]
                mid = [at[i] + w[i] * r[i] * t for i in range(3)]
                P.poly(ring, colour, mask, [mid[i] - w[i] * (1 if t > 0 else -1) for i in range(3)])


def hoop(P, at, along, radius, thick, colour=None, mask=PLAIN, sides=14, deep=None):
    """A ring (open through the middle) round the direction `along`, like a duct's lip."""
    ax = max(range(3), key=lambda i: abs(along[i]))
    w, u, v = AXES["xyz"[ax]]
    pts = [tuple(at[i] + (u[i] * math.cos(math.tau * k / sides) + v[i] * math.sin(math.tau * k / sides)) * radius for i in range(3)) for k in range(sides + 1)]
    for a, b in zip(pts, pts[1:]):
        P.beam(a, b, deep or thick, thick, colour or BRASS, mask, face=w)


def hover(P, at, radii, glow=0.07):
    """The underside of a hover hull whose shell is `radii` round `at`: dark works below, and a
    line of light round it where the shell ends."""
    shell(P, (at[0], at[1] - radii[1] * 0.25, at[2]), (radii[0] * 0.86, radii[1] * 0.95, radii[2] * 0.88), WORKS, PLAIN, "y", -1.0, -0.2, stacks=3)
    shell(P, (at[0], at[1] - radii[1] * 0.3, at[2]), (radii[0] * 0.8, radii[1], radii[2] * 0.82), LIT, SIDE_GLOW, "y", -0.62, -0.5, stacks=1, grow=0.03)


def barrel(P, at, along, steps, colour=None, mask=PLAIN, sides=10):
    """A turned barrel: steps = [(from, to, radius), ...] along its line."""
    for a, b, r in steps:
        P.lathe(at, along, [(a, r), (b, r)], colour or CERAMIC, mask, sides=sides, turn=math.pi / sides)
