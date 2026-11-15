"""The Luminar Accord's tier 1 light artillery: a hover skimmer. A long hull with a slanted glazed
nose and slab sides riding on a line of light, the Accord's knot in brass on each flank, a small
domed chapel with arched windows at the stern, and in front of it twin fat mortars, brass at the
lip, thrown up to lob over the line. Its light is the side's colour.

About 3.8 m wide and 7.6 m long (the server's artillery is 3 m in radius).
"""

import math

from units.luminar_kit import *  # noqa: F401,F403

ELEVATION = 42.0
TOP_AT = (0.0, 2.2, -0.9)
# The hull from the side, nose to the right: (z, y) down its middle, and where it draws in to at its edge.
MIDDLE = [(3.9, 0.95), (3.75, 1.35), (2.2, 2.05), (0.6, 2.2), (-3.7, 2.2), (-3.9, 1.6), (-3.6, 0.7), (3.3, 0.7)]
EDGE = [(3.4, 0.98), (3.3, 1.3), (2.0, 1.85), (0.6, 2.0), (-3.5, 2.0), (-3.7, 1.55), (-3.4, 0.8), (3.0, 0.8)]


def build(Part):
    body, right = Part(), Part()
    right.extrude(MIDDLE, 0.0, 1.45, CERAMIC)
    right.extrude(MIDDLE, 1.45, 1.9, CERAMIC, profile1=EDGE)
    # The nose's glass, a brass line along the shoulder, light low along the flank and in the nose.
    right.prism([(0.08, 1.45, 3.56), (1.2, 1.45, 3.56), (1.2, 2.0, 2.34), (0.08, 2.0, 2.34)], (0, 0.04, 0.03), GLASS)
    right.line([(3.3, 1.32), (2.0, 1.87), (0.6, 2.02), (-3.5, 2.02)], 1.9, BRASS, PLAIN, wide=0.08, proud=0.06)
    right.line([(2.9, 0.9), (-0.6, 0.9), (-1.1, 1.25), (-3.4, 1.25)], 1.9, LIT, SIDE_GLOW, wide=0.09, proud=0.05)
    right.line([(2.9, 0.82), (-3.3, 0.82)], 1.9, BRASS, PLAIN, wide=0.07, proud=0.06)
    right.box((0.8, 0.12, 0.08), (1.0, 1.12, 3.72), LIT, SIDE_GLOW)
    # The Accord's knot on the flank: a ring, and three rings linked inside it.
    hoop(right, (1.93, 1.45, 0.6), (1, 0, 0), 0.42, 0.06, sides=14)
    for k in range(3):
        a = math.tau * k / 3 + math.pi / 2
        hoop(right, (1.93, 1.45 + math.sin(a) * 0.15, 0.6 + math.cos(a) * 0.15), (1, 0, 0), 0.2, 0.04, sides=10)
    # The works underneath, and the light it rides on.
    right.extrude([(3.1, 0.3), (3.4, 0.72), (-3.5, 0.72), (-3.2, 0.3)], 0.0, 1.5, WORKS)
    right.box((0.08, 0.1, 6.0), (1.52, 0.5, 0.0), LIT, SIDE_GLOW)
    right.box((0.9, 0.3, 1.2), (1.0, 0.3, -1.6), WORKS)  # a lift duct
    right.box((0.6, 0.06, 0.9), (1.0, 0.14, -1.6), LIT, SIDE_GLOW)
    # The chapel at the stern: a square of walls with an arched window in each, a low drum, a dome.
    body.box((2.4, 1.3, 2.0), (0, 2.85, -2.6), CERAMIC)
    body.box((2.5, 0.1, 2.1), (0, 3.5, -2.6), BRASS)
    body.box((2.5, 0.08, 2.1), (0, 2.24, -2.6), BRASS)
    for x in (-0.6, 0.6):
        body.box((0.4, 0.7, 0.06), (x, 2.85, -3.6), GLASS)
        body.lathe((x, 3.2, -3.6), (0, 0, -1), [(0, 0.2), (0.03, 0.2)], GLASS, sides=10)
    for z in (-3.1, -2.1):
        right.box((0.06, 0.7, 0.4), (1.2, 2.85, z), GLASS)
        right.lathe((1.2, 3.2, z), (1, 0, 0), [(0, 0.2), (0.03, 0.2)], GLASS, sides=10)
    body.lathe((0, 3.55, -2.6), (0, 1, 0), [(0, 0.85), (0.4, 0.85)], CERAMIC, sides=12)
    for k in range(6):
        a = math.tau * (k + 0.5) / 6
        body.box((0.22, 0.26, 0.06), (math.sin(a) * 0.85, 3.75, -2.6 + math.cos(a) * 0.85), GLASS, PLAIN, (0, math.degrees(a), 0))
    shell(body, (0, 3.95, -2.6), (0.95, 0.75, 0.95), SHADE, PLAIN, "y", 0.0, 1.0, sides=12, stacks=4)
    body.lathe((0, 3.93, -2.6), (0, 1, 0), [(0, 1.0), (0.06, 1.0)], BRASS, sides=12)
    body.lathe((0, 4.68, -2.6), (0, 1, 0), [(0, 0.1), (0.3, 0.03)], BRASS, sides=6)
    body.lathe((0, 2.2, -0.9), (0, 1, 0), [(0, 0.9), (0.08, 0.85)], BRASS, sides=12)  # the mortars' seat
    body.mirrored(right)

    # The mortars, from where they turn: a yoke, two fat barrels with brass lips.
    top = Part()
    e = math.radians(ELEVATION)
    d = (0.0, math.sin(e), math.cos(e))
    top.box((1.5, 0.5, 1.0), (0, 0.3, 0), WORKS)
    top.box((1.7, 0.6, 0.5), (0, 0.45, -0.1), BRASS, PLAIN, (-ELEVATION, 0, 0))
    for x in (-0.48, 0.48):
        at = (x, 0.45, -0.1)
        barrel(top, at, d, [(-0.3, 1.9, 0.4)], sides=12)
        barrel(top, at, d, [(-0.4, -0.3, 0.44), (0.5, 0.62, 0.44), (1.9, 2.2, 0.46)], BRASS, sides=12)
        top.lathe((x, 0.45 + d[1] * 2.2, -0.1 + d[2] * 2.2), d, [(0, 0.36), (0.02, 0.36)], WORKS, sides=12)
        top.lathe((x, 0.45 + d[1] * 2.1, -0.1 + d[2] * 2.1), d, [(0, 0.3), (0.02, 0.3)], LIT, SIDE_GLOW, sides=12)
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, 0.45 + d[1] * 2.2, -0.1 + d[2] * 2.2), "view": 0.9}
