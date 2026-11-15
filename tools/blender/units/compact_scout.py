"""The Terran Compact's tier 1 recon car: a small four-wheeled armoured car. A wedge of a bonnet,
a cabin whose sides lean in to the roof, a machine gun on a ring, a sensor head on a mast and a
spare wheel on the back. The side's colour is painted on in twin stripes and the Compact's mark.

About 3.6 m wide and 5.6 m long (the server's scout is 3 m in radius).
"""

import math

from units.compact_kit import *  # noqa: F401,F403

TOP_AT = (0.25, 2.3, -0.1)


def build(Part):
    body, right = Part(), Part()
    hull = [(-2.5, 0.75), (2.3, 0.75), (2.75, 1.1), (2.7, 1.45), (1.2, 1.75), (0.7, 2.3), (-1.9, 2.3), (-2.6, 1.9), (-2.7, 1.2)]
    wall = [(-2.4, 0.8), (2.2, 0.8), (2.6, 1.1), (2.55, 1.4), (1.1, 1.62), (0.6, 1.72), (-1.9, 1.72), (-2.5, 1.62), (-2.6, 1.2)]
    right.extrude(hull, 0.0, 0.9, STEEL)
    right.extrude(hull, 0.9, 1.35, STEEL, profile1=wall)
    right.prism([(0.12, 1.84, 1.14), (0.82, 1.84, 1.14), (0.82, 2.22, 0.8), (0.12, 2.22, 0.8)], (0, 0.03, 0.04), GLASS)  # windscreen
    right.prism([(0.98, 2.16, 0.3), (1.26, 1.82, 0.3), (1.26, 1.82, -0.6), (0.98, 2.16, -0.6)], (0.04, 0.03, 0), GLASS)  # a side window
    for z in (1.6, -1.6):
        tyre(right, 0.64, 1.3, 1.78, z)
        right.slab(1.3, (1.3, 1.82, z - 0.8, z + 0.8), 1.4, (1.3, 1.78, z - 0.6, z + 0.6), DARK)  # a guard over it
    emblem(right, 1.36, -0.15, 1.2, 0.26)
    stripes(right, 1.36, -0.85, 0.82, 1.62, wide=0.13, gap=0.1)
    top_stripes(right, 0.55, 2.31, -1.8, -0.9, wide=0.13, gap=0.1)
    right.box((0.3, 0.16, 0.08), (0.9, 1.28, 2.72), LAMP, GLOW)
    right.box((0.2, 0.1, 0.06), (1.0, 1.6, -2.68), TAIL, GLOW)
    body.lathe((0, 1.5, -2.72), (0, 0, -1), [(0, 0.52), (0.3, 0.52)], RUBBER, sides=12)  # the spare wheel
    body.lathe((0, 1.5, -3.02), (0, 0, -1), [(0, 0.28), (0.04, 0.28)], DARK, sides=8)
    # The sensor mast, and two aerials.
    body.box((0.16, 1.5, 0.16), (-0.6, 3.05, -1.3), DARK)
    body.box((0.5, 0.48, 0.5), (-0.6, 4.02, -1.3), LIGHT)
    body.box((0.3, 0.28, 0.05), (-0.6, 4.02, -1.04), GLASS)
    body.box((0.04, 1.9, 0.04), (0.9, 3.2, -1.7), DARK)
    body.box((0.04, 1.2, 0.04), (1.0, 2.6, -2.4), DARK)
    body.mirrored(right)

    top = Part()  # the machine gun on its ring
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 0.46), (0.1, 0.46)], DARK, sides=10)
    top.box((0.14, 0.34, 0.14), (0, 0.27, 0), DARK)
    top.box((0.18, 0.2, 0.9), (0, 0.5, 0.15), LIGHT)
    top.box((0.07, 0.07, 1.1), (0, 0.52, 1.1), DARK)
    top.box((0.22, 0.24, 0.3), (-0.2, 0.45, 0.2), OLIVE)
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, 0.52, 1.65), "view": 0.72}
