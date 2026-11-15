"""The Luminar Accord's tier 1 scout aircraft: a light gull-winged plane. A slim body with a long
glass canopy in a brass frame, wings that rise from the body and then droop out to upturned tips,
a single ring-duct engine round the tail (a brass hoop bound round a cone), and a lit sensor dome
underneath. Unarmed. Its light is the side's colour.

About 12 m across the wings and 8.5 m long. Its origin is its middle: aircraft are placed at their
flying height.
"""

import math

from units.luminar_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    shell(body, (0, 0.1, 0.4), (0.85, 0.6, 4.0), CERAMIC, PLAIN, "z", -0.75, 1.0, sides=12, stacks=8)
    shell(body, (0, 0.42, 1.2), (0.55, 0.5, 1.7), GLASS, PLAIN, "z", sides=10, stacks=5)
    shell(body, (0, 0.38, 1.2), (0.62, 0.42, 1.82), BRASS, PLAIN, "y", -0.3, 0.12, sides=14, stacks=1)
    # A wing: up from the body to the gull's bend, then out and a little down, the tip turned up.
    root0, root1 = (0.5, 0.15, 1.9), (0.5, 0.15, -1.6)
    bend0, bend1 = (2.2, 0.75, 0.5), (2.2, 0.75, -1.5)
    tip0, tip1 = (5.6, 0.25, -1.5), (5.4, 0.25, -2.3)
    up = (0, 0.14, 0)
    right.prism([root0, bend0, bend1, root1], up, CERAMIC)
    right.prism([bend0, tip0, tip1, bend1], up, CERAMIC)
    right.prism([tip0, (6.1, 0.9, -2.4), (5.9, 0.9, -2.8), tip1], up, CERAMIC)
    for a, b in ((root0, bend0), (bend0, tip0), (tip0, (6.1, 0.9, -2.4))):  # brass on the leading edge, light under it
        right.beam((a[0], a[1] + 0.08, a[2]), (b[0], b[1] + 0.08, b[2]), 0.1, 0.18, BRASS, PLAIN, face=(0, 1, 0))
    right.beam((1.0, 0.26, 1.35), (2.2, 0.68, 0.36), 0.08, 0.08, LIT, SIDE_GLOW, face=(0, 1, 0))
    right.beam((2.5, 0.64, 0.24), (4.4, 0.36, -0.95), 0.08, 0.08, LIT, SIDE_GLOW, face=(0, 1, 0))
    right.beam((0.72, 0.0, 3.3), (0.86, 0.02, 1.2), 0.07, 0.05, LIT, SIDE_GLOW, face=(1, 0, 0))  # a line along the nose
    # The engine round the tail: a brass hoop bound in rope-turns, the tail cone through it.
    for z, r in ((-2.9, 1.0), (-3.12, 1.04), (-3.34, 1.0)):
        hoop(body, (0, 0.1, z), (0, 0, 1), r, 0.2, sides=14, deep=0.2)
    body.lathe((0, 0.1, -3.4), (0, 0, 1), [(0, 0.92), (0.6, 0.92)], WORKS, sides=14, caps=False)
    body.lathe((0, 0.1, -2.6), (0, 0, -1), [(0, 0.5), (0.9, 0.42), (2.0, 0.02)], CERAMIC, sides=10)
    body.lathe((0, 0.1, -3.5), (0, 0, -1), [(0, 0.48), (0.05, 0.48)], LIT, SIDE_GLOW, sides=10)
    for a in (0.0, math.pi / 2):  # struts holding the hoop
        body.box((1.9, 0.06, 0.3), (0, 0.1, -3.1), OLD, PLAIN, (0, 0, math.degrees(a)))
    # The sensor dome underneath.
    body.lathe((0, -0.42, 0.6), (0, -1, 0), [(0, 0.42), (0.1, 0.4)], BRASS, sides=10)
    shell(body, (0, -0.5, 0.6), (0.34, 0.3, 0.34), LIT, SIDE_GLOW, "y", -1.0, 0.0, sides=10, stacks=3)
    body.mirrored(right)
    fly = 6.0
    views = {
        "front": ((-13, -18, fly + 6.5), (0.3, 0.0, fly), 50, 0.0, (60, 0, 70)),
        "rear": ((12, 18, fly + 6.0), (0, 0, fly), 50, 0.0),
        "side": ((-30, 0, fly + 0.6), (0, 0, fly), 70, 0.0, (40, 0, -60)),
        "head_on": ((0, -30, fly + 0.8), (0, 0, fly), 70, 0.0),
        "top": ((0, -0.1, fly + 46), (0, 0, fly), 62, math.pi / 2, (30, 0, 200)),
        "below": ((-11, -15, fly - 4.5), (0, 0, fly), 50, 0.0, (60, 0, 70)),
    }
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -0.8, 0.6), "views": views, "fly": fly}
