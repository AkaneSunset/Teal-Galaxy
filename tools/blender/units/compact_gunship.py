"""The Terran Compact's tier 1 gunship, the patrol gunship: a helicopter. A slab-sided cabin with a
glazed nose, a four-bladed rotor over an engine housing, a thin tail boom with a fin and a tail
rotor, stub wings each carrying a rocket pod, a cannon under the chin, and skids. The side's
colour is painted on in twin stripes round the cabin, bands on the boom and the Compact's mark.

About 12 m from nose to tail and 10.5 m across the rotor. Its origin is its middle: aircraft are
placed at their flying height.
"""

import math

from units.compact_kit import *  # noqa: F401,F403

CABIN = [(4.7, -0.4), (4.1, -1.0), (-1.5, -1.0), (-2.6, -0.2), (-2.6, 0.75), (-1.7, 1.15), (0.9, 1.15), (2.5, 0.35), (4.5, 0.0)]


def _grown(profile, s, about=(0.6, 0.0)):
    return [(about[0] + (z - about[0]) * s, about[1] + (y - about[1]) * s) for z, y in profile]


def build(Part):
    body, right = Part(), Part()
    right.extrude(CABIN, 0.0, 0.7, STEEL)
    right.extrude(CABIN, 0.7, 1.05, STEEL, profile1=_grown(CABIN, 0.86))
    # The canopy: two panes up the nose's slope and a window in each side.
    right.prism([(0.06, 0.42, 2.42), (0.62, 0.42, 2.42), (0.62, 1.08, 1.08), (0.06, 1.08, 1.08)], (0, 0.035, 0.02), GLASS)
    right.prism([(0.06, 0.06, 4.3), (0.62, 0.06, 4.3), (0.62, 0.33, 2.62), (0.06, 0.33, 2.62)], (0, 0.03, 0.0), GLASS)
    right.box((0.06, 0.42, 1.2), (1.05, 0.45, 1.25), GLASS)
    right.box((0.06, 0.36, 0.7), (1.05, 0.45, 0.1), GLASS)
    emblem(right, 1.06, -0.75, -0.1, 0.3)
    stripes(right, 1.06, -1.55, -0.72, 0.8, wide=0.14, gap=0.12)
    # The engine housing and the rotor.
    body.extrude([(-2.2, 1.1), (0.8, 1.1), (0.4, 1.6), (-1.9, 1.6)], -0.6, 0.6, DARK)
    top_stripes(body, 0.0, 1.61, -1.85, -0.75, wide=0.16, gap=0.12)
    right.lathe((0.45, 1.35, -2.1), (0, 0, -1), [(0, 0.16), (0.35, 0.2)], LIGHT, sides=8)  # an exhaust
    body.lathe((0, 1.6, -0.3), (0, 1, 0), [(0, 0.2), (0.55, 0.14)], LIGHT, sides=8)
    body.lathe((0, 2.15, -0.3), (0, 1, 0), [(0, 0.36), (0.14, 0.36)], DARK, sides=8)
    for turn in (45, 135):
        body.box((0.44, 0.05, 10.6), (0, 2.24, -0.3), DARK, PLAIN, (0, turn, 0))
    # The tail: a boom, a stabiliser, a fin, a tail rotor on its left.
    body.beam((0, 0.3, -2.5), (0, 0.75, -7.0), 0.85, 0.7, STEEL, PLAIN, face=(1, 0, 0), wide1=0.36, deep1=0.26)
    for z, half in ((-4.0, 0.3), (-4.4, 0.28)):
        right.box((0.04, 0.5, 0.16), (half - 0.02, 0.47, z), STRIPE, PAINT)
    body.box((2.8, 0.08, 0.7), (0, 0.72, -6.1), STEEL)
    body.prism([(-0.07, 0.6, -6.1), (-0.07, 0.7, -7.2), (-0.07, 2.5, -7.9), (-0.07, 2.5, -7.2)], (0.14, 0, 0), STEEL)
    for x in (-0.09, 0.09):
        body.prism([(x, 1.5, -6.92), (x, 1.5, -7.42), (x, 2.3, -7.72), (x, 2.3, -7.2)], (0.02 if x > 0 else -0.02, 0, 0), STRIPE, PAINT)
    body.lathe((-0.07, 1.85, -7.3), (-1, 0, 0), [(0, 0.12), (0.2, 0.1)], LIGHT, sides=6)
    for turn in (25, 115):
        body.box((0.04, 2.1, 0.2), (-0.26, 1.85, -7.3), DARK, PLAIN, (turn, 0, 0))
    body.box((0.1, 0.1, 0.06), (0, 0.75, -7.02), TAIL, GLOW)
    # Stub wings, a rocket pod under each.
    right.box((1.5, 0.14, 1.1), (1.7, -0.2, -0.4), STEEL, PLAIN, (0, 0, -6))
    right.box((0.12, 0.3, 0.6), (2.1, -0.42, -0.4), DARK)
    right.lathe((2.1, -0.82, -1.4), (0, 0, 1), [(0, 0.2), (0.2, 0.3), (1.8, 0.3), (2.0, 0.24)], LIGHT, sides=8)
    right.lathe((2.1, -0.82, 0.6), (0, 0, 1), [(0, 0.2), (0.03, 0.2)], RUBBER, sides=8)
    right.box((0.05, 0.05, 0.05), (2.47, -0.12, 0.1), LAMP, GLOW)
    # Skids.
    right.box((0.1, 0.1, 4.6), (1.15, -1.8, 0.7), DARK)
    right.box((0.1, 0.1, 0.5), (1.15, -1.7, 3.15), DARK, PLAIN, (-25, 0, 0))
    for z in (2.2, -0.8):
        right.beam((0.8, -0.95, z), (1.15, -1.78, z), 0.1, 0.1, DARK, PLAIN, face=(0, 0, 1))
    # Under the chin: a sensor ball on the nose and the cannon.
    body.lathe((0, -0.55, 4.45), (0, -0.4, 1), [(0, 0.3), (0.25, 0.26)], LIGHT, sides=8)
    body.lathe((0, -0.65, 4.7), (0, -0.4, 1), [(0, 0.14), (0.03, 0.14)], GLASS, sides=8)
    body.box((0.5, 0.36, 0.7), (0, -1.16, 3.2), DARK)
    barrel(body, (0, -1.22, 3.5), (0, 0, 1), [(0.0, 1.3, 0.07), (1.3, 1.5, 0.1)])
    body.mirrored(right)
    fly = 6.0
    views = {
        "front": ((-13, -18, fly + 6.0), (0.3, 1.0, fly), 50, 0.0, (60, 0, 70)),
        "rear": ((12, 18, fly + 5.5), (0, 1.0, fly), 50, 0.0),
        "side": ((-32, 1.5, fly + 0.6), (0, 1.5, fly), 70, 0.0, (40, 0, -60)),
        "head_on": ((0, -32, fly + 0.8), (0, 0, fly), 70, 0.0),
        "top": ((0, 1.4, fly + 50), (0, 1.5, fly), 62, math.pi / 2, (30, 0, 200)),
    }
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -1.22, 5.0), "views": views, "fly": fly}
