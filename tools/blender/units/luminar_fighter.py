"""The Luminar Accord's fighter (Rev 2), all three marks: a crewed faceted needle dart. A hex-
section fuselage drawn out to a point, a faceted glass canopy in a brass frame, straight-edged
swept wings with a cannon pod under each, twin canted fins, flat tailplanes and one hex nozzle.
Mk II adds canards, moves the cannons to the wingtips, hangs ventral fins and sets a faceted dome
fairing behind the canopy. Mk III goes to twin hex nozzles fed by box intake sponsons, carries
three cannons under each wing, a two-tier dome fairing and a brass nose cone.
Its light is the side's colour.

The wings are swept back, as drawn; the order asked for forward sweep (an open item in Rev 2).
About 12, 13 and 15 m long. The origin is its middle: aircraft are placed at their flying height.
"""

from units.accord_kit import *  # noqa: F401,F403

NEEDLE = [(0, 1), (0.62, 0.55), (1, 0), (0.6, -0.6), (-0.6, -0.6), (-1, 0), (-0.62, 0.55)]
BODY = [(-5.6, 0.05, 0.62, 0.45), (-4.6, 0.08, 0.85, 0.55), (-1.0, 0.1, 0.95, 0.62), (2.0, 0.04, 0.62, 0.48), (4.4, -0.05, 0.26, 0.22), (6.2, -0.1, 0.0, 0.0)]
GLAZE = [(0.8, 0.52, 0.42, 0.32), (2.5, 0.42, 0.34, 0.24), (3.4, 0.28, 0.14, 0.04)]
WING = [(0.9, 1.4), (4.6, -1.7), (4.6, -2.7), (0.9, -2.9)]
TAIL = [(0.75, -3.9), (2.6, -5.3), (2.6, -5.9), (0.75, -5.75)]
CANARD = [(0.6, 2.6), (1.8, 1.8), (1.8, 1.4), (0.6, 1.7)]


def make(Part, tier):
    body, right = Part(), Part()
    loft(body, BODY, CERAMIC, PLAIN, NEEDLE)
    if tier >= 3:  # a brass nose cone
        loft(body, [(4.4, -0.05, 0.27, 0.23), (6.25, -0.1, 0.0, 0.0)], BRASS, PLAIN, NEEDLE)
    for k in (1, 2, 6):
        seam(body, BODY, NEEDLE, k, 0.035, z1=4.3)
    for z in (-4.0, -1.6):
        band(body, BODY, z, 0.1, NEEDLE, grow=0.025)
    seam(right, BODY, NEEDLE, 2, 0.04, LIT, SIDE_GLOW, t=0.5, z0=-0.6, z1=2.2)
    loft(body, GLAZE, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, GLAZE, CANOPY, k, 0.025)
    wing(right, WING, 0.0, 0.13)
    right.beam((2.0, 0.08, -0.6), (3.6, 0.08, -1.9), 0.08, 0.04, LIT, SIDE_GLOW, face=(0, 1, 0))
    wing(right, TAIL, 0.05, 0.1)
    fin(right, (0.6, 0.5, -3.4), (1.25, 2.0, -4.7), 1.7, 0.65)
    right.box((0.36, 0.42, 1.0), (0.9, -0.05, 0.4), CERAMIC)  # the intake
    right.box((0.28, 0.32, 0.04), (0.9, -0.05, 0.92), WORKS)
    if tier == 1:  # a cannon pod under each wing
        right.box((0.28, 0.28, 1.4), (2.9, -0.2, -0.5), GUN)
        muzzle = hexgun(right, (2.9, -0.2, 0.2), (0, 0, 1), 0.8, 0.1)
    else:
        wing(right, CANARD, 0.12, 0.08)
        fin(right, (0.5, -0.45, -3.3), (0.95, -1.25, -4.1), 1.2, 0.5, 0.1)  # ventral fins
        if tier == 2:  # cannons at the wingtips
            right.box((0.26, 0.26, 2.0), (4.65, 0.0, -1.7), CERAMIC)
            muzzle = hexgun(right, (4.65, 0.0, -0.7), (0, 0, 1), 0.9, 0.09)
        else:  # three under each wing, a box intake sponson down each flank
            for x in (2.2, 2.75, 3.3):
                right.box((0.22, 0.22, 1.2), (x, -0.22, -1.2), GUN)
                muzzle = hexgun(right, (x, -0.22, -0.6), (0, 0, 1), 0.7, 0.08)
            right.slab(-0.45, (0.7, 1.35, -4.6, 1.2), 0.45, (0.75, 1.3, -4.5, 1.0), CERAMIC)
            right.box((0.62, 0.06, 5.6), (1.03, 0.47, -1.7), BRASS)
            right.box((0.48, 0.66, 0.04), (1.03, 0.0, 1.21), WORKS)
            right.box((0.66, 0.8, 0.06), (1.03, 0.0, 1.17), BRASS)
        drum(body, (0, 0.6, -0.5), 0.36, 0.18, BRASS)  # the dome fairing
        if tier >= 3:
            drum(body, (0, 0.78, -0.5), 0.3, 0.14, CERAMIC, r1=0.24)
            pyramid(body, (0, 0.92, -0.5), 0.24, 0.12, BRASS, ribs=False)
        else:
            pyramid(body, (0, 0.78, -0.5), 0.36, 0.2, BRASS, ribs=False)
    if tier >= 3:  # twin nozzles
        nozzle(right, (0.5, 0.05, -5.3), (0, 0, -1), 0.4, 0.75)
    else:
        nozzle(body, (0, 0.05, -5.5), (0, 0, -1), 0.5, 0.7)
    body.mirrored(right)
    k = {1: 1.0, 2: 1.1, 3: 1.25}[tier]
    fly = 9.0
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": tuple(c * k for c in muzzle), "views": air_views(fly, 0.95 * k), "fly": fly}


def build(Part):
    return make(Part, 1)
