"""The Luminar Accord's tier 1 engineer: a round hover hull like an upturned bowl on a line of
light, banded in brass, and on top of it a cage of brass arches round the fabrication orb, a globe
of light in the side's colour, with a ring at the cage's crown.

About 6 m across (the server's engineer is 3 m in radius).
"""

import math

from units.luminar_kit import *  # noqa: F401,F403

AT = (0.0, 1.25, 0.0)
R = (3.0, 0.95, 3.0)
ORB = (0.0, 2.75, 0.0)


def build(Part):
    body = Part()
    shell(body, AT, R, CERAMIC, PLAIN, "y", -0.7, 0.86, sides=20, stacks=7)
    shell(body, AT, R, BRASS, PLAIN, "y", 0.3, 0.36, sides=20, stacks=1, grow=0.03)
    shell(body, AT, R, BRASS, PLAIN, "y", -0.32, -0.26, sides=20, stacks=1, grow=0.03)
    shell(body, AT, R, LIT, SIDE_GLOW, "y", -0.05, 0.0, sides=20, stacks=1, grow=0.02)  # a line of light round its widest
    for k in range(6):  # brass seams down the bowl
        a = k / 6
        shell(body, AT, R, BRASS, PLAIN, "y", -0.26, 0.3, sides=120, stacks=3, grow=0.025, arc=(a + 0.079, a + 0.088))
    hover(body, AT, R)
    # The cage: a brass seat, six arches up to a crown, a ring on top, the orb inside.
    top_y = AT[1] + R[1] * 0.86
    body.lathe((0, top_y - 0.05, 0), (0, 1, 0), [(0, 1.62), (0.16, 1.55)], BRASS, sides=18)
    body.lathe((0, top_y + 0.1, 0), (0, 1, 0), [(0, 1.3), (0.05, 1.3)], WORKS, sides=18)
    for k in range(6):
        a = math.tau * k / 6
        pts = [(math.cos(a) * 1.45 * math.cos(t), top_y + 0.1 + 1.55 * math.sin(t), math.sin(a) * 1.45 * math.cos(t)) for t in [math.radians(d) for d in (0, 22, 45, 68, 86)]]
        for p, q in zip(pts, pts[1:]):
            body.beam(p, q, 0.16, 0.1, BRASS, PLAIN, face=(-math.sin(a), 0, math.cos(a)))
    hoop(body, (0, top_y + 1.2, 0), (0, 1, 0), 0.9, 0.07, sides=12)
    body.lathe((0, top_y + 1.6, 0), (0, 1, 0), [(0, 0.3), (0.12, 0.2)], BRASS, sides=10)
    hoop(body, (0, top_y + 1.92, 0), (1, 0, 0), 0.2, 0.06, sides=10)
    shell(body, ORB, (0.68, 0.68, 0.68), LIT, SIDE_GLOW, "y", sides=12, stacks=6)
    body.lathe((0, top_y + 0.1, 0), (0, 1, 0), [(0, 0.4), (0.3, 0.22)], BRASS, sides=8)  # the orb's cup
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, ORB[1], 0.7), "view": 0.8}
