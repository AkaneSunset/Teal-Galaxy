"""What the Terran Compact's units share: welded grey steel, the side's colour painted on in twin
stripes and the Compact's mark (two rings round a square), tracks with road wheels, tyres."""

import math

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

STEEL = Color(0.36, 0.37, 0.39)  # the hull
DARK = Color(0.24, 0.25, 0.27)  # frames, guns, running gear
LIGHT = Color(0.46, 0.47, 0.49)  # boxes and fittings
TRACK = Color(0.1, 0.1, 0.11)
CLEAT = Color(0.17, 0.17, 0.18)
RUBBER = Color(0.08, 0.08, 0.085)
GLASS = Color(0.05, 0.07, 0.1)
OLIVE = Color(0.27, 0.3, 0.2)  # crates
STRIPE = Color(0.16, 0.16, 0.16)  # painted in the side's colour
LAMP = Color(1.0, 0.93, 0.8)
TAIL = Color(1.0, 0.2, 0.12)


def circle(z, y, r, n=14):
    return [(z + r * math.cos(math.tau * k / n), y + r * math.sin(math.tau * k / n)) for k in range(n + 1)]


def emblem(P, x, z, y, r):
    """The Compact's mark on a side wall at `x`."""
    P.line(circle(z, y, r), x, STRIPE, PAINT, wide=r * 0.16, proud=0.05)
    P.line(circle(z, y, r * 0.58, 10), x, STRIPE, PAINT, wide=r * 0.13, proud=0.05)
    P.box((0.05, r * 0.3, r * 0.3), (x, y, z), STRIPE, PAINT)


def stripes(P, x, z, y0, y1, wide=0.16, gap=0.14):
    """Twin stripes up a side wall at `x`."""
    for dz in (-(wide + gap) / 2, (wide + gap) / 2):
        P.line([(z + dz, y0 + wide * 0.3), (z + dz, y1 - wide * 0.3)], x, STRIPE, PAINT, wide=wide, proud=0.05)


def top_stripes(P, x, y, z0, z1, wide=0.18, gap=0.14, tilt=0.0):
    """Twin stripes along a roof or deck (or a slope tilted `tilt` degrees), for the camera overhead."""
    for dx in (-(wide + gap) / 2, (wide + gap) / 2):
        P.box((wide, 0.04, abs(z1 - z0)), (x + dx, y, (z0 + z1) / 2), STRIPE, PAINT, (tilt, 0, 0))


def gear(P, loop, x0, x1, wheels, r):
    """A track on the right with its road wheels showing: loop is [(z, y), ...] round it."""
    P.track(loop, x0, x1, TRACK, CLEAT, every=0.4)
    for z in wheels:
        P.wheel(r, x1 - 0.12, x1 + 0.08, z, r + 0.06, DARK, sides=10)
        P.wheel(r * 0.42, x1 + 0.08, x1 + 0.13, z, r + 0.06, LIGHT, sides=6)
    top = max(y for _, y in loop)
    for z in (max(z for z, _ in loop) - 0.55, min(z for z, _ in loop) + 0.55):  # sprocket and idler
        P.wheel(0.36, x1 - 0.12, x1 + 0.08, z, top - 0.5, DARK, sides=8)


def tyre(P, r, x0, x1, z):
    """A road wheel with a tyre, on the right."""
    P.wheel(r, x0, x1, z, r, RUBBER, sides=12)
    P.wheel(r * 0.55, x1, x1 + 0.05, z, r, DARK, sides=8)
    P.wheel(r * 0.2, x1 + 0.05, x1 + 0.09, z, r, LIGHT, sides=6)


def barrel(P, at, along, steps, colour=None, sides=8):
    """A gun barrel: steps = [(from, to, radius), ...] along its line."""
    for a, b, r in steps:
        P.lathe(at, along, [(a, r), (b, r)], colour or DARK, sides=sides, turn=math.pi / sides)
