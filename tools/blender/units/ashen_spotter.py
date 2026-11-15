"""The Ashen Collective's scout aircraft: a small faceted diamond of a flying wing, unarmed, its
engines buried, mapping the battle with passive sensors. A low body with dark glass rises from its
middle; lines of the side's light run along its edges and under its nose.

About 8 m long and 9 m across. The origin is its middle.
"""

from units.ashen_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    plate(right, [(0.0, 4.4), (4.6, -0.6), (4.3, -1.0), (0.0, -3.8)], 0.0, 0.26, bevel=0.25)
    loft(body, [(-3.2, 0.1, 0.5, 0.2), (-1.0, 0.25, 0.95, 0.45), (1.4, 0.25, 0.8, 0.45), (3.6, 0.05, 0.0, 0.0)], PLATE, shape=FLAT)
    loft(body, [(0.2, 0.55, 0.0, 0.0), (0.9, 0.62, 0.32, 0.16), (1.9, 0.45, 0.22, 0.12), (2.4, 0.3, 0.0, 0.0)], GLASS)
    edge(right, (0.3, -0.04, 4.0), (4.45, -0.04, -0.5), 0.06, 0.08, face=(1, 0, 1))
    edge(right, (0.5, -0.14, 1.6), (2.4, -0.14, 0.2), 0.05, 0.04, face=(0, -1, 0))
    right.box((0.5, 0.12, 0.05), (0.45, 0.12, -3.3), LIT, SIDE_GLOW)
    hexagon(body, (0, 0.71, -0.8), 0.3, (0, 1, 0))
    body.mirrored(right)
    fly = 11.0
    return {"body": body, "top": None, "top_at": (0, 0, 0), "views": air_views(fly, 1.0), "fly": fly}
