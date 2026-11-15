"""The Terran Compact's tier 1 mobile anti-air: a halftrack, wheels in front and tracks behind,
with a sloped bonnet, a small cab, and an open bed carrying twin autocannons on a turning mount
with a shield and ammunition stacked behind. The side's colour is painted on in twin stripes down
the bonnet and on the bed, and the Compact's mark on the cab door.

About 4 m wide and 7.4 m long (the server's AA is 3 m in radius).
"""

import math

from units.compact_kit import *  # noqa: F401,F403

ELEVATION = 40.0
TOP_AT = (0.0, 1.4, -1.5)


def build(Part):
    body, right = Part(), Part()
    body.extrude([(-3.8, 0.7), (3.4, 0.7), (3.4, 1.2), (-3.8, 1.2)], -1.3, 1.3, DARK)
    tyre(right, 0.62, 1.3, 1.76, 2.6)
    right.slab(1.3, (1.25, 1.8, 1.8, 3.4), 1.4, (1.25, 1.78, 2.0, 3.2), STEEL)
    gear(right, [(-3.2, 0.0), (-0.2, 0.0), (0.4, 0.5), (0.4, 0.8), (0.0, 1.1), (-3.4, 1.1), (-3.8, 0.8), (-3.8, 0.5)], 1.3, 2.0, (-2.9, -2.05, -1.2, -0.35), 0.36)
    bonnet = [(1.6, 1.2), (3.5, 1.2), (3.5, 1.7), (1.6, 2.1)]
    body.extrude(bonnet, -1.05, 1.05, STEEL)
    tilt = math.degrees(math.atan2(0.4, 1.9))
    top_stripes(body, -0.3, 1.92, 1.7, 3.45, wide=0.15, gap=0.12, tilt=tilt)
    for y in (1.3, 1.42, 1.54):  # the grille
        body.box((1.2, 0.07, 0.05), (0.45, y, 3.52), DARK)
    for dx in (-0.435, -0.165):
        body.box((0.15, 0.42, 0.04), (dx, 1.44, 3.52), STRIPE, PAINT)
    right.lathe((0.85, 1.85, 3.3), (0, 0, 1), [(0, 0.15), (0.14, 0.15)], LAMP, GLOW, sides=8)
    body.box((3.4, 0.3, 0.2), (0, 0.95, 3.55), STEEL)  # the bumper
    cab = [(0.2, 1.2), (1.6, 1.2), (1.6, 2.1), (1.2, 2.7), (0.2, 2.7)]
    body.extrude(cab, -1.3, 1.3, STEEL)
    for x in (-0.62, 0.62):
        body.prism([(x - 0.5, 2.2, 1.56), (x + 0.5, 2.2, 1.56), (x + 0.5, 2.6, 1.3), (x - 0.5, 2.6, 1.3)], (0, 0.03, 0.05), GLASS)
    right.extrude([(0.5, 2.1), (1.4, 2.1), (1.15, 2.55), (0.5, 2.55)], 1.29, 1.35, GLASS)
    emblem(right, 1.32, 0.9, 1.65, 0.25)
    # The bed: a floor, low walls, crates at the back.
    body.slab(1.2, (-1.5, 1.5, -3.8, 0.2), 1.4, (-1.5, 1.5, -3.8, 0.2), DARK)
    right.box((0.1, 0.7, 3.95), (1.45, 1.75, -1.8), STEEL)
    stripes(right, 1.51, -2.85, 1.4, 2.1, wide=0.13, gap=0.1)
    body.box((3.0, 0.7, 0.1), (0, 1.75, -3.75), STEEL)
    for x, h in ((-0.75, 0.55), (0.45, 0.7)):
        body.box((1.1, h, 0.8), (x, 1.4 + h / 2, -3.2), OLIVE)
    right.box((0.2, 0.1, 0.06), (1.2, 1.3, -3.82), TAIL, GLOW)
    body.mirrored(right)

    # The mount, from where it turns: a pedestal, a cradle, a shield on its right, a director on its left.
    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 0.62), (0.5, 0.5)], DARK, sides=10)
    top.box((1.1, 0.5, 0.9), (0, 0.75, -0.1), LIGHT)
    top.box((0.1, 1.3, 1.5), (0.95, 1.2, 0.3), STEEL, PLAIN, (-18, 0, 0))
    top.box((0.5, 0.5, 0.6), (-0.85, 1.15, -0.2), LIGHT)
    top.lathe((-0.85, 1.15, 0.1), (0, 0, 1), [(0, 0.18), (0.25, 0.18)], GLASS, sides=8)
    e = math.radians(ELEVATION)
    pivot = (0.0, 1.05, 0.0)
    d = (0.0, math.sin(e), math.cos(e))
    top.box((0.95, 0.55, 1.3), (0, pivot[1] + d[1] * 0.2, d[2] * 0.2), DARK, PLAIN, (-ELEVATION, 0, 0))
    for x in (-0.27, 0.27):
        at = (x, pivot[1], pivot[2])
        barrel(top, at, d, [(0.7, 1.3, 0.13), (1.3, 2.9, 0.08), (2.9, 3.2, 0.12)])
    top.mirrored(side)
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, pivot[1] + d[1] * 3.2, d[2] * 3.2), "view": 0.8}
