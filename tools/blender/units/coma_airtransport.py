"""The Coma Conglomerate's air troop transport (provisional): a seed pod of an airframe. A ribbed
graphite shell over a troop bay for two squads, hooked crescent wings curving down either side,
twin ring lift engines under its front, and a belly hatch of petals that opens to lower the troops
to the ground on an amber drop beam.

About 15 m long. The origin is its middle.
"""

import math

from units.coma_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    # The pod: a ribbed shell, longer than it's wide, high at the front and running out to a tail.
    shell(body, (0, 0.0, 0.6), (3.2, 2.9, 4.4), GRAPHITE, PLAIN, "y", -0.35, 1.0, sides=24, stacks=8)
    shell(body, (0, 0.0, -1.6), (2.6, 2.5, 4.4), GRAPHITE, PLAIN, "y", -0.2, 1.0, sides=18, stacks=6)
    for b in (-56, -34, -12, 12, 34, 56):  # its ribs, lying on the shell from front to back
        rib = []
        for la in range(8, 165, 12):
            u, v = math.radians(b), math.radians(la)
            rib.append((3.24 * math.sin(u) * math.sin(v), 2.94 * math.cos(u) * math.sin(v), 0.6 + 4.44 * math.cos(v)))
        tube(body, rib, 0.15, GRAPHITE, PLAIN, sides=5)
    tube(body, [(0.25, 2.0, 3.8), (0.3, 2.95, 1.0), (0.25, 2.55, -2.6)], 0.07, LIT, PAINT, sides=4)
    tube(body, [(-0.25, 2.0, 3.8), (-0.3, 2.95, 1.0), (-0.25, 2.55, -2.6)], 0.07, LIT, PAINT, sides=4)
    # The hooked crescent wings: out from the shell's sides, back and down to points.
    prong(right, bezier((2.6, 0.9, 1.6), (6.4, 1.6, 0.2), (7.4, -0.4, -3.6), (6.2, -3.4, -5.4), n=14), 0.9, glow_tip=False, flat=1.6)
    # The ring lift engines: nacelles under its front, lit rings looking forward.
    right.lathe((2.2, -1.4, 0.2), (0, 0, 1), [(0, 0.7), (0.4, 1.0), (2.2, 1.0), (2.5, 0.9)], GRAPHITE, sides=14)
    eye(right, (2.2, -1.4, 2.72), (0, 0, 1), 0.82)
    ring(right, (2.2, -1.4, 2.8), (0, 0, 1), 1.0, 0.06, sides=20)
    right.box((1.0, 0.4, 1.6), (1.4, -0.9, 1.2), GRAPHITE)
    # The belly hatch: petals closing round the drop beam.
    for a in range(0, 360, 60):
        t = math.radians(a)
        prong(body, bezier((0.9 * math.sin(t), -1.0, 2.0 + 0.9 * math.cos(t)), (1.4 * math.sin(t), -2.1, 2.1 + 1.4 * math.cos(t)), (0.35 * math.sin(t), -3.2, 2.2 + 0.35 * math.cos(t)), n=6), 0.5, glow_tip=False, flat=1.8)
    body.lathe((0, -2.9, 2.2), (0, -1, 0.15), [(0, 0.25), (1.6, 0.45), (2.4, 0.55)], Color(1.0, 0.72, 0.38), GLOW, sides=10)
    body.mirrored(right)
    fly = 12.0
    return {"body": body, "top": None, "top_at": (0, 0, 0), "views": air_views(fly, 1.15), "fly": fly, "span": 3.0}
