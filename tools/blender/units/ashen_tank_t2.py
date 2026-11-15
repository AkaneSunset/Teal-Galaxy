"""The Ashen Collective's main battle tank, Mk II: heavier layered faceted armour over seven road
wheels a side, skirts over the top of the tracks, blunt lit prows at the nose, and a long flat
turret with a 70 mm rail cannon and a sensor block on its roof. Its light is the side's colour.

About 7.8 m long (without the gun) and 4 m wide.
"""

from units.ashen_kit import *  # noqa: F401,F403

TRACK = Color(0.07, 0.07, 0.075)
CLEAT = Color(0.14, 0.14, 0.15)


def build(Part):
    body, top, right = Part(), Part(), Part()
    # The tracks, road wheels showing under the skirts.
    loop = [(-3.9, 0.9), (-3.4, 0.1), (3.3, 0.1), (4.0, 0.9), (3.6, 1.25), (-3.6, 1.25)]
    right.track(loop, 1.35, 2.05, TRACK, CLEAT)
    for k in range(7):
        right.wheel(0.42, 1.25, 2.1, -2.85 + k * 0.95, 0.5, RECESS, sides=8)
    # Skirts with lit seams; the prows over each track.
    right.extrude([(-3.95, 0.75), (3.9, 0.75), (4.25, 1.25), (4.1, 1.75), (-3.95, 1.75)], 1.95, 2.15, PLATE)
    right.beam((2.16, 1.25, -3.6), (2.16, 1.25, 1.2), 0.05, 0.04, LIT, SIDE_GLOW, face=(1, 0, 0))
    right.beam((2.16, 1.25, 1.2), (2.16, 1.6, 2.4), 0.05, 0.04, LIT, SIDE_GLOW, face=(1, 0, 0))
    right.slab(1.0, (1.05, 2.05, 3.6, 4.4), 1.9, (1.15, 1.95, 3.4, 4.15), RAISED)
    right.box((0.6, 0.12, 0.05), (1.55, 1.45, 4.42), LIT, SIDE_GLOW)
    # The hull, layered plates over it.
    body.extrude([(-3.9, 0.7), (3.4, 0.7), (4.2, 1.2), (3.8, 1.9), (1.6, 2.35), (-3.7, 2.35), (-4.0, 1.9)], -1.95, 1.95, PLATE)
    for z0, z1 in ((-3.4, -1.4), (-1.2, 0.8), (1.0, 2.6)):
        body.slab(2.35, (-1.75, 1.75, z0, z1), 2.5, (-1.6, 1.6, z0 + 0.1, z1 - 0.1), RAISED)
    # The turret: long and flat, faceted cheeks lit, the rail cannon, a sensor block on its roof.
    top.slab(0.0, (-1.55, 1.55, -2.4, 1.4), 0.9, (-1.2, 1.2, -2.2, 0.9), PLATE)
    top.slab(0.9, (-1.0, 1.0, -2.0, 0.6), 1.05, (-0.85, 0.85, -1.9, 0.4), RAISED)
    for sx in (-1, 1):
        top.beam((sx * 1.45, 0.45, 1.3), (sx * 1.1, 0.75, -0.2), 0.06, 0.04, LIT, SIDE_GLOW, face=(sx, 0, 0))
    hexagon(top, (1.38, 0.5, -1.0), 0.28, (1, 0, 0))
    top.box((0.6, 0.6, 1.0), (0, 0.45, 1.5), RAISED)
    gun(top, (0.0, 0.45, 1.9), 3.6, 0.14)
    top.box((0.7, 0.4, 0.7), (0.45, 1.35, -0.8), PLATE)
    top.box((0.5, 0.18, 0.04), (0.45, 1.38, -0.44), LIT, SIDE_GLOW)
    body.mirrored(right)
    return {"body": body, "top": top, "top_at": (0.0, 2.5, -0.5), "muzzle": (0.0, 0.45, 5.5), "view": 1.0}
