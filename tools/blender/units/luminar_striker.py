"""The Luminar Accord's tier 1 assault walker: a light two-legged walker. A smooth domed head and
body in one, a lit arch of a visor in its face, shoulders out wide carrying a long lance rifle
each, hung low and pointing ahead, and two bent legs on brass joints. No turret: it faces what it
shoots. Its light is the side's colour.

About 4.4 m tall and 4.6 m across the shoulders (the server's striker is 3 m in radius).
"""

import math

from units.luminar_kit import *  # noqa: F401,F403

HEAD = (0.0, 3.45, 0.0)


def build(Part):
    body, right = Part(), Part()
    r = (1.15, 1.0, 1.3)
    shell(body, HEAD, r, CERAMIC, PLAIN, "y", -0.75, 1.0, sides=14, stacks=6)
    shell(body, HEAD, r, BRASS, PLAIN, "y", -0.75, -0.62, sides=14, stacks=1, grow=0.03)
    shell(body, HEAD, r, BRASS, PLAIN, "z", 0.1, 0.16, sides=14, stacks=1, grow=0.03)  # a brass band over the crown
    # The visor: a dark arch in the face, lit round its edge.
    body.box((0.62, 0.62, 0.1), (0, 3.6, 1.2), GLASS, PLAIN, (-12, 0, 0))
    for x in (-0.3, 0.3):
        body.box((0.08, 0.6, 0.06), (x, 3.6, 1.27), LIT, SIDE_GLOW, (-12, 0, 0))
    body.box((0.68, 0.08, 0.06), (0, 3.92, 1.2), LIT, SIDE_GLOW, (-12, 0, 0))
    hoop(body, (0, 3.05, 1.2), (0, 0, 1), 0.16, 0.05)  # a brass ring under it
    # The hips.
    body.lathe((0, 2.75, 0), (0, -1, 0), [(0, 0.5), (0.35, 0.42)], WORKS, sides=10)
    shell(body, (0, 2.1, -0.05), (0.75, 0.5, 0.7), CERAMIC, PLAIN, "y", stacks=4, sides=12)
    body.box((2.1, 0.3, 0.3), (0, 2.1, -0.05), WORKS)
    # A leg: thigh forward and down, shin back and down, a long foot.
    hip, knee, ankle = (1.15, 2.1, -0.05), (1.15, 1.35, 0.75), (1.15, 0.45, -0.25)
    right.lathe((0.95, 2.1, -0.05), (1, 0, 0), [(0, 0.4), (0.45, 0.4)], BRASS, sides=10)
    right.beam(hip, knee, 0.46, 0.5, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.36, deep1=0.44)
    right.lathe((0.9, 1.35, 0.75), (1, 0, 0), [(0, 0.3), (0.5, 0.3)], BRASS, sides=10)
    right.beam(knee, ankle, 0.34, 0.4, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.24, deep1=0.3)
    right.beam((1.37, 1.2, 0.6), (1.37, 0.6, -0.1), 0.08, 0.04, LIT, SIDE_GLOW, face=(1, 0, 0))
    right.lathe((0.95, 0.45, -0.25), (1, 0, 0), [(0, 0.22), (0.4, 0.22)], BRASS, sides=8)
    right.extrude([(-0.7, 0.0), (0.95, 0.0), (0.95, 0.14), (-0.1, 0.5), (-0.5, 0.5)], 0.9, 1.4, CERAMIC)
    right.box((0.54, 0.08, 0.3), (1.15, 0.04, 0.95), BRASS)
    # A shoulder, an arm down from it, and the lance rifle: long, hung low, pointing ahead.
    shell(right, (1.75, 3.5, -0.05), (0.55, 0.62, 0.7), CERAMIC, PLAIN, "y", stacks=4, sides=12)
    right.box((0.5, 0.3, 0.3), (1.25, 3.4, -0.05), WORKS)
    right.beam((1.8, 3.2, -0.05), (1.9, 2.2, 0.35), 0.34, 0.4, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.3, deep1=0.34)
    right.lathe((1.65, 2.2, 0.35), (1, 0, 0), [(0, 0.26), (0.5, 0.26)], BRASS, sides=8)
    at, d = (1.9, 2.1, 0.2), (0.0, -0.12, 1.0)
    right.box((0.42, 0.5, 1.5), (1.9, 2.05, 0.75), CERAMIC, PLAIN, (7, 0, 0))
    barrel(right, at, d, [(1.4, 3.5, 0.11)])
    barrel(right, at, d, [(1.4, 1.6, 0.17), (3.5, 3.8, 0.15)], BRASS)
    right.box((0.05, 0.06, 1.3), (2.12, 2.02, 0.8), LIT, SIDE_GLOW, (7, 0, 0))
    n = math.hypot(d[1], d[2])
    tip = (at[0], at[1] + d[1] / n * 3.82, at[2] + d[2] / n * 3.82)
    right.lathe(tip, d, [(0, 0.09), (0.03, 0.09)], LIT, SIDE_GLOW, sides=8)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, tip[1], tip[2]), "view": 0.72}
