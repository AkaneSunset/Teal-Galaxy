"""The Luminar Accord's tier 1 fast attack bomber: one crescent of a wing, its tips swept back to
long horns, round a slim body with a glass canopy in a brass frame. A ring-duct engine sits in the
wing either side, a brass hoop round a small pod, and light in the side's colour runs along the
leading edges and the spine.

About 13 m across the horns and 11 m long. Its origin is its middle: aircraft are placed at their
flying height.
"""

import math

from units.luminar_kit import *  # noqa: F401,F403

# The right wing from above: (x, z), nose forward, the horn sweeping out and back to its tip.
WING = [(0.0, 5.2), (0.9, 3.4), (2.6, 1.6), (4.6, 0.3), (5.9, -1.2), (6.5, -3.0), (6.3, -4.6), (5.6, -3.0), (4.6, -1.8), (3.4, -1.3), (2.3, -1.6), (1.4, -2.6), (0.6, -4.2), (0.0, -5.4)]


def build(Part):
    body, right = Part(), Part()
    right.prism([(x, -0.12, z) for x, z in WING], (0, 0.3, 0), CERAMIC)
    inner = [(0.0, 4.4), (0.7, 2.9), (1.9, 1.5), (2.6, 0.4), (2.2, -1.0), (1.2, -2.2), (0.5, -3.6), (0.0, -4.6)]
    right.prism([(x, 0.18, z) for x, z in inner], (0, 0.2, 0), CERAMIC)  # the wing thickening to the body
    # Brass along the leading edge, light just under it, light along the trailing horn.
    lead = [(x, 0.03, z) for x, z in WING[:7]]
    for a, b in zip(lead, lead[1:]):
        out = (b[2] - a[2], 0, a[0] - b[0])
        n = math.hypot(out[0], out[2])
        off = (-out[0] / n * 0.03, 0, -out[2] / n * 0.03)
        right.beam((a[0] + off[0], 0.1, a[2] + off[2]), (b[0] + off[0], 0.1, b[2] + off[2]), 0.14, 0.2, BRASS, PLAIN, face=(0, 1, 0))
        right.beam((a[0] + off[0] * 2, -0.08, a[2] + off[2] * 2), (b[0] + off[0] * 2, -0.08, b[2] + off[2] * 2), 0.1, 0.1, LIT, SIDE_GLOW, face=(0, 1, 0))
    right.trace([(1.5, 0.4, 0.9), (2.4, 0.2, -0.6), (3.4, 0.2, -1.15)], 0.08, 0.05, LIT, SIDE_GLOW, face=(0, 1, 0))
    # The body: a slim shell down the middle, the canopy in its brass frame, a lit spine.
    shell(body, (0, 0.25, 0.2), (1.05, 0.62, 5.0), CERAMIC, PLAIN, "z", sides=12, stacks=8)
    shell(body, (0, 0.5, 2.1), (0.62, 0.52, 1.7), GLASS, PLAIN, "z", sides=10, stacks=5)
    shell(body, (0, 0.47, 2.1), (0.68, 0.46, 1.8), BRASS, PLAIN, "y", -0.3, 0.1, sides=14, stacks=1)
    body.box((0.08, 0.06, 3.4), (0, 0.84, -2.2), LIT, SIDE_GLOW, (3.5, 0, 0))
    body.box((0.5, 0.1, 2.2), (0, -0.36, 0.0), WORKS)  # the bomb bay's doors
    body.box((0.06, 0.04, 2.2), (0, -0.42, 0.0), BRASS)
    # A ring-duct engine in the wing: a dark well, a brass hoop round it, a pod in the middle.
    at = (3.15, 0.2, -0.05)
    right.lathe((at[0], 0.19, at[2]), (0, 1, 0), [(0, 0.95), (0.02, 0.95)], WORKS, sides=14)
    right.lathe((at[0], -0.14, at[2]), (0, 1, 0), [(0, 0.95), (0.02, 0.95)], WORKS, sides=14)
    hoop(right, (at[0], 0.3, at[2]), (0, 1, 0), 1.0, 0.2, sides=14, deep=0.2)
    hoop(right, (at[0], 0.43, at[2]), (0, 1, 0), 1.0, 0.06, OLD, sides=14, deep=0.1)
    shell(right, (at[0], 0.32, at[2]), (0.4, 0.3, 0.62), BRASS, PLAIN, "z", sides=8, stacks=4)
    right.box((1.9, 0.06, 0.1), (at[0], 0.3, at[2]), OLD)
    right.lathe((at[0], -0.17, at[2]), (0, 1, 0), [(0, 0.6), (0.02, 0.6)], LIT, SIDE_GLOW, sides=12)  # its light underneath
    body.mirrored(right)
    fly = 6.0
    views = {
        "front": ((-15, -20, fly + 8.0), (0.3, 0.0, fly), 50, 0.0, (60, 0, 70)),
        "rear": ((14, 20, fly + 7.5), (0, 0, fly), 50, 0.0),
        "side": ((-34, 0, fly + 0.6), (0, 0, fly), 70, 0.0, (40, 0, -60)),
        "head_on": ((0, -34, fly + 0.8), (0, 0, fly), 70, 0.0),
        "top": ((0, -0.1, fly + 52), (0, 0, fly), 62, math.pi / 2, (30, 0, 200)),
        "below": ((-12, -16, fly - 5.0), (0, 0, fly), 50, 0.0, (60, 0, 70)),
    }
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -0.5, 0.0), "views": views, "fly": fly}
