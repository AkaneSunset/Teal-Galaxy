"""The Ashen Collective's gunship: a long dagger of black plate with a hull either side of it, each
carrying twin cannons slung underneath, swept wings out from those, two canted fins and three
engines astern. Its light is the side's colour: the engines, seams along the spine, the wings'
leading edges, the cannons' muzzles.

About 13.5 m long and 15 m across the wings at tier 1 (higher tiers are drawn bigger until they
have models of their own). Its origin is its middle: aircraft are placed at their flying height.
"""

import math

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

PLATE = Color(0.19, 0.19, 0.21)  # the armour
RAISED = Color(0.28, 0.28, 0.3)  # plates laid over it
RECESS = Color(0.11, 0.11, 0.12)
ROOF = Color(0.1, 0.1, 0.1)  # painted in the side's colour
LIT = Color(1, 1, 1)

# The middle hull from the side, nose to the right: (z, y) at its spine, and where it thins to at its edge.
SPINE = [(7.5, 0.0), (4.0, 0.7), (0.5, 1.25), (-3.0, 1.15), (-5.5, 0.7), (-6.0, 0.0), (-5.5, -0.6), (-1.0, -0.9), (3.0, -0.7), (7.5, -0.15)]
EDGE = [(3.2, 0.0), (2.0, 0.3), (0.3, 0.5), (-3.0, 0.45), (-5.0, 0.3), (-5.4, 0.0), (-5.0, -0.3), (-1.0, -0.4), (2.0, -0.3), (3.2, -0.08)]


def _grown(profile, s):
    return [(z * s, y * s) for z, y in profile]


def build(Part):
    body, right = Part(), Part()

    # The middle hull: a painted spine, the hull falling away from it to a thin edge either side,
    # so from above it is a dagger. A lit seam where the spine stands proud.
    shoulder = [(5.4, 0.0), (3.7, 0.7)] + SPINE[2:-2] + [(3.0, -0.7), (5.4, -0.12)]  # the spine's edge: its nose drawn back, so the tip is a point
    right.extrude(_grown(SPINE, 1.05), 0.0, 0.3, ROOF, PAINT, profile1=_grown(shoulder, 1.05))
    right.extrude(shoulder, 0.3, 1.7, PLATE, profile1=EDGE)
    for z in (2.4, 3.5, 4.6):  # teeth under the nose
        right.beam((0.45, -0.6, z), (0.55, -1.45, z + 0.6), 0.3, 0.5, RAISED, PLAIN, face=(1, 0, 0), wide1=0.05, deep1=0.08)
    right.beam((0.9, 0.62, 3.2), (1.25, 0.72, -1.5), 0.14, 0.06, LIT, SIDE_GLOW, face=(0.3, 1, 0))  # a slit along its shoulder

    # A side hull: a shorter blade alongside, the wing growing out of it.
    pod = [(4.4, -0.05), (2.5, 0.5), (-3.5, 0.6), (-5.2, 0.3), (-5.4, -0.3), (-3.0, -0.65), (2.5, -0.55), (4.4, -0.15)]
    thin = [(2.2, -0.05), (1.2, 0.3), (-3.2, 0.35), (-4.6, 0.2), (-4.8, -0.2), (-3.0, -0.35), (1.2, -0.3), (2.2, -0.12)]
    right.extrude(pod, 1.6, 2.6, RAISED)
    right.extrude(pod, 2.6, 3.4, RAISED, profile1=thin)
    right.box((0.5, 0.05, 2.6), (2.1, 0.61, -1.2), LIT, SIDE_GLOW)  # a lit grille on its back

    # The twin cannons under it: a housing, two barrels, their muzzles lit.
    right.box((1.25, 0.75, 3.2), (2.2, -0.95, 0.6), PLATE)
    right.box((1.35, 0.5, 1.2), (2.2, -0.95, -0.2), RAISED)
    right.box((0.06, 0.16, 1.6), (2.86, -0.95, 0.9), LIT, SIDE_GLOW)
    for x in (1.9, 2.5):
        right.lathe((x, -1.0, 2.2), (0, 0, 1), [(0, 0.27), (1.1, 0.27)], RAISED, turn=math.pi / 8)
        right.lathe((x, -1.0, 2.2), (0, 0, 1), [(1.1, 0.19), (3.3, 0.19)], RECESS, turn=math.pi / 8)
        right.lathe((x, -1.0, 2.2), (0, 0, 1), [(2.3, 0.25), (2.5, 0.25)], RAISED, turn=math.pi / 8)
        right.lathe((x, -1.0, 2.2), (0, 0, 1), [(3.3, 0.26), (3.8, 0.26)], RAISED, turn=math.pi / 8)
        right.lathe((x, -1.0, 2.2), (0, 0, 1), [(3.8, 0.16), (3.85, 0.16)], LIT, SIDE_GLOW, turn=math.pi / 8)

    # The wing: swept hard back, drooping a little to the tip, a plate laid on it, its leading
    # edge lit, a small fin turned down at the tip.
    def wing(x, z, lift=0.0):
        return (x, 0.15 - (x - 3.0) * 0.12 + lift, z)
    right.prism([wing(3.0, 1.6), wing(7.3, -2.9), wing(7.5, -4.7), wing(5.6, -4.1), wing(3.0, -3.7)], (0, -0.22, 0), PLATE)
    right.prism([wing(3.2, 0.6), wing(5.7, -2.2), wing(5.7, -3.6), wing(3.2, -3.1)], (0, 0.08, 0), RAISED)
    right.beam(wing(3.5, 1.0, 0.03), wing(7.1, -2.8, 0.03), 0.16, 0.06, LIT, SIDE_GLOW, face=(0, 1, 0))
    right.beam(wing(6.3, -3.2, 0.03), wing(6.3, -4.2, 0.03), 0.16, 0.06, LIT, SIDE_GLOW, face=(0, 1, 0))
    right.prism([(7.4, -0.4, -2.9), (7.4, -0.4, -4.7), (7.4, -1.4, -5.1), (7.4, -1.4, -4.3)], (0.14, 0, 0), RAISED)
    right.prism([wing(3.0, 3.3), wing(4.5, 1.7), wing(3.0, 2.0)], (0, -0.14, 0), RAISED)  # a barb ahead of the wing

    # A fin: tall, swept back, leaning outward.
    def fin(z, y):
        return (2.0 + (y - 0.5) * 0.35, y, z)
    right.prism([fin(-1.4, 0.5), fin(-4.9, 0.45), fin(-6.4, 3.0), (fin(-5.4, 3.0))], (0.18, 0, 0), PLATE)
    right.beam((fin(-3.0, 1.0)[0] + 0.2, 1.0, -3.0), (fin(-5.3, 2.6)[0] + 0.2, 2.6, -5.3), 0.14, 0.06, LIT, SIDE_GLOW, face=(1, 0, 0))
    right.prism([wing(3.4, -3.4), wing(4.6, -3.9), wing(3.8, -6.0)], (0, -0.16, 0), RAISED)  # a prong trailing from the wing root

    # Engines: one in the middle hull's stern, one in each side hull's.
    right.lathe((2.3, 0.0, -5.0), (0, 0, -1), [(0, 0.62), (0.8, 0.5)], RECESS, sides=8, turn=math.pi / 8)
    right.lathe((2.3, 0.0, -5.0), (0, 0, -1), [(0.8, 0.4), (0.86, 0.4)], LIT, SIDE_GLOW, sides=8, turn=math.pi / 8)
    body.lathe((0, 0.1, -5.6), (0, 0, -1), [(0, 0.8), (1.0, 0.65)], RECESS, sides=8, turn=math.pi / 8)
    body.lathe((0, 0.1, -5.6), (0, 0, -1), [(1.0, 0.52), (1.06, 0.52)], LIT, SIDE_GLOW, sides=8, turn=math.pi / 8)
    body.mirrored(right)

    fly = 6.0
    views = {
        "front": ((-14, -19, fly + 6.5), (0.5, -0.5, fly), 50, 0.0, (60, 0, 70)),
        "rear": ((13, 19, fly + 6.0), (0, 0, fly), 50, 0.0),
        "side": ((-34, 0, fly + 0.6), (0, 0, fly), 70, 0.0, (40, 0, -60)),
        "head_on": ((0, -34, fly + 0.8), (0, 0, fly), 70, 0.0),
        "top": ((0, -0.1, fly + 58), (0, 0, fly), 62, math.pi / 2, (30, 0, 200)),
        "below": ((-12, -16, fly - 5.0), (0, 0, fly), 50, 0.0, (60, 0, 70)),
    }
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -1.0, 6.05), "views": views, "fly": fly}
