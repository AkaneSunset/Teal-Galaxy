"""The Terran Compact's tier 1 line tank: a slab-sided steel hull on wide open tracks, a boxy
turret with a cupola and a stowage bin behind, a long gun with a muzzle brake, a fuel drum on the
back. The side's colour is painted on: twin stripes up the glacis, along the turret roof and down
the flanks, and the Compact's mark on the turret.

About 6.6 m wide and 8.4 m long without the gun (the server's tier 1 tank is 4 m in radius).
"""

import math

from units.compact_kit import *  # noqa: F401,F403

TOP_AT = (0.0, 2.3, -0.3)


def build(Part):
    body, right = Part(), Part()
    body.extrude([(-4.0, 0.7), (3.4, 0.7), (4.2, 1.3), (4.1, 1.7), (2.6, 2.3), (-3.9, 2.3), (-4.1, 1.6)], -2.1, 2.1, STEEL)
    gear(right, [(-3.5, 0.0), (3.3, 0.0), (4.1, 0.75), (4.1, 1.1), (3.6, 1.5), (-3.7, 1.5), (-4.2, 1.1), (-4.2, 0.7)], 2.1, 3.2,
         (-2.95, -1.85, -0.75, 0.35, 1.45, 2.55), 0.5)
    right.slab(1.5, (2.1, 3.3, -4.3, 3.8), 1.62, (2.1, 3.3, -4.3, 3.8), DARK)  # the fender
    right.box((1.2, 0.1, 1.0), (2.7, 1.3, 4.15), DARK, PLAIN, (38, 0, 0))  # its mudguard
    right.box((0.95, 0.42, 1.7), (2.75, 1.84, -1.2), LIGHT)  # a stowage box on it
    right.box((0.95, 0.3, 1.0), (2.75, 1.78, 1.4), LIGHT)
    stripes(right, 2.11, -3.0, 1.62, 2.3)
    tilt = math.degrees(math.atan2(0.6, 1.5))
    top_stripes(body, -0.55, 2.03, 2.65, 4.05, tilt=tilt)  # up the glacis
    right.box((0.26, 0.26, 0.16), (1.55, 1.98, 3.72), LAMP, GLOW)
    body.slab(2.3, (-1.7, 1.7, -3.8, -2.5), 2.42, (-1.6, 1.6, -3.7, -2.6), DARK)  # the engine deck
    body.lathe((-1.1, 2.72, -3.5), (1, 0, 0), [(0, 0.4), (2.2, 0.4)], DARK, sides=10)  # the fuel drum
    right.box((0.4, 0.14, 0.06), (1.5, 1.7, -4.08), TAIL, GLOW)
    body.mirrored(right)

    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 1.6), (0.14, 1.6)], DARK, sides=12)
    top.slab(0.1, (-1.6, 1.6, -2.0, 1.4), 1.5, (-1.4, 1.4, -1.9, 1.0), STEEL)
    top.box((2.3, 0.85, 1.0), (0, 0.85, -2.45), LIGHT)  # the bin behind
    emblem(side, 1.52, 0.0, 0.82, 0.42)
    stripes(side, 1.5, -1.25, 0.2, 1.45, wide=0.18)
    top_stripes(top, -0.6, 1.52, -1.8, 0.9)
    top.lathe((0.55, 1.5, -0.9), (0, 1, 0), [(0, 0.5), (0.32, 0.46)], LIGHT, sides=10)  # the cupola
    top.box((0.5, 0.08, 0.5), (0.55, 1.86, -0.9), DARK)
    top.box((0.5, 0.3, 0.5), (-0.7, 1.65, 0.3), LIGHT)  # the sight
    top.box((1.35, 0.95, 0.5), (0, 0.8, 1.45), DARK)  # the mantlet
    barrel(top, (0, 0.8, 1.6), (0, 0, 1), [(0, 0.9, 0.3), (0.9, 4.5, 0.17), (4.5, 5.15, 0.28)])
    top.lathe((0, 0.8, 1.6), (0, 0, 1), [(5.15, 0.12), (5.17, 0.12)], TRACK, sides=8)
    barrel(top, (0.45, 0.85, 1.6), (0, 0, 1), [(0, 0.7, 0.06)])  # the coaxial gun
    top.mirrored(side)
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, 0.8, 6.75), "view": 0.85}
