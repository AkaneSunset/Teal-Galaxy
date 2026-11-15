"""The Ashen Collective's troop carrier: a fast eight-wheeled armoured carrier. A tall faceted hull
sloped at the nose, dark vision slits across its front, a door at the back, lit lines along its
plating, and a small turret with a 20 mm autocannon on its roof.

About 7.6 m long and 3.2 m wide.
"""

from units.ashen_kit import *  # noqa: F401,F403


def build(Part):
    body, top = Part(), Part()
    L, W = 7.6, 3.2
    hull(body, L, W, 2.7, nose=2.0)
    cab_glass(body, L, W, 2.7, 2.0)
    axles(body, L, W, [L / 2 - 1.2, L / 2 - 2.6, -L / 2 + 2.6, -L / 2 + 1.2])
    for sx in (-1, 1):  # lit frames up the sides at the back, the hexagon on each flank
        body.beam((sx * (W / 2 + 0.01), 1.2, -L / 2 + 0.25), (sx * (W / 2 + 0.01), 2.6, -L / 2 + 0.6), 0.07, 0.04, LIT, SIDE_GLOW, face=(sx, 0, 0))
        hexagon(body, (sx * (W / 2 + 0.02), 2.0, -0.6), 0.3, (sx, 0, 0), RAISED, PLAIN)
    body.box((1.4, 1.3, 0.08), (0, 1.75, -L / 2 - 0.02), RAISED)  # the door
    top.slab(0.0, (-0.7, 0.7, -0.8, 0.7), 0.6, (-0.55, 0.55, -0.6, 0.4), PLATE)
    gun(top, (0.0, 0.35, 0.5), 1.8, 0.09)
    top.box((0.3, 0.25, 0.4), (0.45, 0.75, -0.2), RAISED)
    return {"body": body, "top": top, "top_at": (0.0, 3.0, 0.4), "muzzle": (0.0, 0.35, 2.3), "view": 0.95}
