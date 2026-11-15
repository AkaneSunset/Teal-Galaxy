"""The Coma Conglomerate's scout plane: a light crescent of a flying wing, unarmed, a smooth bulb
in its middle with a cluster of amber sensor lenses looking ahead and down, its long thin horns
swept back and turned up at their tips.

About 5.5 m long and 12 m across. The origin is its middle.
"""

from units.coma_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    # The bulb: smooth, swelling down under the wing.
    shell(body, (0, -0.15, 0.2), (1.05, 0.95, 1.9), GRAPHITE, PLAIN, "z", sides=14, stacks=8)
    shell(body, (0, 0.2, -0.6), (0.7, 0.55, 2.0), GRAPHITE, PLAIN, "z", sides=10, stacks=6)
    # The wing: a thin crescent, its horns swept back and turned up.
    spine = bezier((0.3, 0.1, 0.4), (3.4, 0.3, 0.4), (5.6, 0.5, -1.4), (6.2, 1.5, -3.2), n=14)
    R = taper(14, 0.32, 0.015, 1.1)
    S = [max(1.0, 1.6 * (1 - k / 14) ** 0.7 / max(r, 1e-3)) for k, r in enumerate(R)]
    tube(right, spine, R, GRAPHITE, PLAIN, sides=10, squash=S)
    tube(right, [(p[0], p[1] + R[k] * 0.9, p[2] + R[k] * 0.3) for k, p in enumerate(spine[:12])], 0.04, LIT, PAINT, sides=4, squash=1.5)
    for x, z in ((1.7, 0.2), (3.0, -0.1), (4.2, -0.6)):  # small lenses along the wing
        eye(right, (x, 0.42, z + 0.15), (0, 1, 0), 0.16)
    # The sensor lenses: a big one in the nose, two small below it.
    eye(body, (0, -0.1, 2.05), (0, -0.1, 1), 0.38)
    eye(right, (0.38, -0.65, 1.55), (0.3, -0.5, 1), 0.17)
    body.mirrored(right)
    fly = 11.0
    return {"body": body, "top": None, "top_at": (0, 0, 0), "views": air_views(fly, 0.8), "fly": fly}
