"""The Terran Compact's tier 1 troop transport, the conscript carrier: a six-wheeled armoured
truck. A flat-faced cab over the front axle, a tall box of a troop body behind it with a ramp
across the back, and a machine gun on a ring on the roof. The side's colour is painted on in twin
stripes up the body's sides and along its roof, and the Compact's mark.

About 3.6 m wide and 7.6 m long.
"""

import math

from units.compact_kit import *  # noqa: F401,F403

TOP_AT = (0.0, 3.45, 0.9)


def build(Part):
    body, right = Part(), Part()
    body.extrude([(-3.7, 0.7), (3.6, 0.7), (3.6, 1.15), (-3.7, 1.15)], -1.2, 1.2, DARK)  # the chassis
    for z in (2.6, -1.3, -2.75):
        tyre(right, 0.64, 1.2, 1.72, z)
    right.slab(1.32, (1.2, 1.76, -3.5, -0.55), 1.42, (1.2, 1.74, -3.4, -0.65), DARK)  # a guard over the back wheels
    # The cab: a flat face leaning back to the windscreen.
    cab = [(1.9, 1.15), (3.8, 1.15), (3.8, 2.1), (3.5, 3.05), (1.9, 3.05)]
    body.extrude(cab, -1.6, 1.6, STEEL)
    for x in (-0.76, 0.76):
        body.prism([(x - 0.66, 2.2, 3.79), (x + 0.66, 2.2, 3.79), (x + 0.66, 2.9, 3.57), (x - 0.66, 2.9, 3.57)], (0, 0.015, 0.05), GLASS)
    right.box((0.06, 0.6, 0.9), (1.6, 2.5, 2.85), GLASS)
    right.box((0.07, 0.9, 0.05), (1.6, 1.7, 2.3), DARK)
    right.box((0.3, 0.4, 0.08), (1.85, 2.5, 3.5), DARK)  # a mirror
    for y in (1.3, 1.45, 1.6, 1.75):  # the grille
        body.box((1.5, 0.08, 0.05), (0, y, 3.82), DARK)
    for dx in (-0.14, 0.14):
        body.box((0.14, 0.62, 0.04), (dx, 1.52, 3.84), STRIPE, PAINT)
    right.box((0.36, 0.22, 0.08), (1.2, 1.5, 3.82), LAMP, GLOW)
    body.box((3.3, 0.36, 0.25), (0, 0.95, 3.85), DARK)  # the bumper
    # The troop body.
    box = [(-3.8, 1.15), (1.75, 1.15), (1.75, 3.4), (-3.8, 3.4)]
    body.extrude(box, -1.7, 1.7, STEEL)
    body.slab(3.4, (-1.5, 1.5, -3.6, 1.55), 3.48, (-1.4, 1.4, -3.5, 1.45), LIGHT)  # a raised roof plate
    emblem(right, 1.71, -0.2, 2.3, 0.4)
    stripes(right, 1.71, -1.5, 1.2, 3.35, wide=0.17, gap=0.14)
    top_stripes(body, 0.0, 3.49, -3.3, -0.6, wide=0.22, gap=0.18)
    for z in (-2.6, 0.9):  # ribs up the wall, firing ports between
        right.box((0.07, 2.2, 0.1), (1.71, 2.27, z), DARK)
    for z in (-3.1, -2.2, 0.5, 1.3):
        right.box((0.05, 0.14, 0.34), (1.71, 2.75, z), GLASS)
    # The ramp across the back, shut, on its hinges with a ram either side.
    body.box((2.7, 2.0, 0.1), (0, 2.25, -3.84), LIGHT)
    body.box((2.9, 0.12, 0.14), (0, 1.2, -3.86), DARK)
    for y in (1.7, 2.25, 2.8):
        body.box((2.4, 0.06, 0.04), (0, y, -3.9), DARK)
    right.box((0.12, 2.0, 0.12), (1.48, 2.25, -3.86), DARK)
    right.box((0.22, 0.14, 0.06), (1.45, 3.2, -3.83), TAIL, GLOW)
    body.mirrored(right)

    top = Part()  # the roof machine gun on its ring, a small shield in front of the gunner
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 0.55), (0.14, 0.55)], DARK, sides=10)
    top.box((0.16, 0.4, 0.16), (0, 0.34, 0.1), DARK)
    top.box((0.9, 0.5, 0.06), (0, 0.55, 0.35), STEEL, PLAIN, (-12, 0, 0))
    top.box((0.2, 0.22, 0.9), (0, 0.62, 0.3), LIGHT)
    top.box((0.08, 0.08, 1.2), (0, 0.64, 1.3), DARK)
    top.box((0.24, 0.26, 0.32), (-0.24, 0.52, 0.2), OLIVE)
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, 0.64, 1.9), "view": 0.95}
