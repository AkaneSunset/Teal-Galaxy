"""The Terran Compact's tier 1 heavy artillery: a tracked tractor towing a field howitzer. The
tractor has a tall cab in front and a bed of ammunition crates behind; the gun rides on two big
wheels with its trails spread out the back and a flat shield, and turns on its carriage to aim.
The side's colour is painted on in twin stripes and the Compact's mark on the cab.

About 5 m wide and 10.6 m long, tractor and gun together (the server's tier 1 artillery is 3 m in
radius: this one is long).
"""

import math

from units.compact_kit import *  # noqa: F401,F403

ELEVATION = 24.0
TOP_AT = (0.0, 1.35, -2.4)


def build(Part):
    body, right = Part(), Part()
    # The tractor.
    body.extrude([(0.3, 0.6), (5.0, 0.6), (5.4, 1.0), (5.4, 1.5), (0.3, 1.5)], -1.5, 1.5, STEEL)
    gear(right, [(0.9, 0.0), (4.5, 0.0), (5.2, 0.6), (5.2, 0.95), (4.7, 1.3), (0.6, 1.3), (0.2, 0.95), (0.2, 0.6)], 1.5, 2.4, (1.25, 2.25, 3.25, 4.25), 0.44)
    right.slab(1.3, (1.5, 2.5, 0.2, 5.3), 1.42, (1.5, 2.5, 0.2, 5.3), DARK)
    cab = [(3.0, 1.5), (5.4, 1.5), (5.3, 2.3), (4.7, 3.2), (3.0, 3.2)]
    body.extrude(cab, -1.45, 1.45, STEEL)
    for x in (-0.7, 0.7):  # two panes of glass in the windscreen
        body.prism([(x - 0.55, 2.42, 5.25), (x + 0.55, 2.42, 5.25), (x + 0.55, 3.08, 4.81), (x - 0.55, 3.08, 4.81)], (0, 0.04, 0.05), GLASS)
    right.extrude([(3.4, 2.4), (4.6, 2.4), (4.3, 3.0), (3.4, 3.0)], 1.44, 1.5, GLASS)
    emblem(right, 1.47, 3.8, 1.95, 0.33)
    top_stripes(body, -0.4, 3.22, 3.1, 4.6)
    for dx in (-0.56, -0.24):  # and on down the cab's front
        body.box((0.18, 0.75, 0.04), (dx, 1.9, 5.37), STRIPE, PAINT, (-7, 0, 0))
    right.box((0.24, 0.2, 0.1), (1.1, 1.35, 5.42), LAMP, GLOW)
    body.lathe((0.0, 3.2, 3.6), (0, 1, 0), [(0, 0.3), (0.14, 0.3)], DARK, sides=8)
    body.slab(1.5, (-1.5, 1.5, 0.3, 3.0), 1.72, (-1.5, 1.5, 0.3, 3.0), DARK)  # the bed
    right.box((0.1, 0.62, 2.7), (1.45, 2.03, 1.65), STEEL)
    stripes(right, 1.51, 1.0, 1.72, 2.34, wide=0.14)
    body.box((2.7, 0.62, 0.1), (0, 2.03, 0.35), STEEL)
    for x, z, h in ((-0.75, 2.3, 0.8), (0.6, 2.2, 1.0), (-0.5, 1.1, 0.7), (0.75, 1.0, 0.55)):
        body.box((1.1, h, 1.0), (x, 1.72 + h / 2, z), OLIVE)
    # The tow bar, and the gun's carriage: an axle on two big wheels, its trails spread behind.
    body.box((0.18, 0.18, 1.9), (0, 0.9, -0.6), DARK)
    body.box((1.9, 0.5, 1.1), (0, 1.0, -2.4), DARK)
    right.wheel(0.86, 1.15, 1.5, -2.4, 0.86, RUBBER, sides=12)
    right.wheel(0.56, 1.5, 1.55, -2.4, 0.86, DARK, sides=8)
    right.wheel(0.16, 1.55, 1.6, -2.4, 0.86, LIGHT, sides=6)
    right.beam((0.4, 0.85, -2.9), (1.45, 0.16, -5.5), 0.24, 0.28, DARK, PLAIN, face=(0, 1, 0))
    right.box((0.5, 0.4, 0.12), (1.45, 0.2, -5.55), LIGHT)
    body.mirrored(right)

    # The gun, from where it turns on its carriage.
    top, side = Part(), Part()
    top.box((2.7, 1.5, 0.1), (0, 0.75, 0.45), STEEL, PLAIN, (-12, 0, 0))  # the shield
    top.box((0.6, 0.5, 0.2), (0, 0.6, 0.45), DARK, PLAIN, (-12, 0, 0))
    e = math.radians(ELEVATION)
    pivot = (0.0, 0.55, 0.0)
    d = (0.0, math.sin(e), math.cos(e))
    n = (0.0, math.cos(e), -math.sin(e))

    def along(dist, up=0.0, x=0.0):
        return (x, pivot[1] + d[1] * dist + n[1] * up, pivot[2] + d[2] * dist + n[2] * up)
    top.box((0.62, 0.62, 1.4), along(-0.4), LIGHT, PLAIN, (-ELEVATION, 0, 0))  # the breech
    barrel(top, pivot, d, [(0.3, 1.7, 0.3), (1.7, 4.6, 0.19), (4.6, 5.15, 0.28)])
    barrel(top, along(0, 0.42), d, [(0.0, 1.9, 0.12)], LIGHT)  # the recoil cylinders
    barrel(top, along(0, -0.4), d, [(0.0, 1.5, 0.12)], LIGHT)
    side.box((0.3, 0.5, 0.5), (0.5, 0.45, -0.1), DARK)
    top.mirrored(side)
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": along(5.15), "view": 1.3}
