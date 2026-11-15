"""The Ashen Collective's self-propelled howitzer, Mk II: an eight-wheeled faceted carrier with a
cab of dark glass, a fire-control mast over it, the lit emblem on its crew box, and a 130 mm
howitzer on a turntable at the back, stabiliser legs let down behind. Its light is the side's
colour.

About 9.2 m long and 3.3 m wide.
"""

import math

from units.ashen_kit import *  # noqa: F401,F403

ELEV = math.radians(28)


def build(Part):
    body, top = Part(), Part()
    L, W = 9.2, 3.3
    hull(body, L, W, 1.7, nose=0.8, roof=0.3)
    body.slab(1.9, (-W / 2, W / 2, 1.0, L / 2 - 0.4), 3.1, (-W / 2 + 0.3, W / 2 - 0.3, 1.3, L / 2 - 1.5), PLATE)  # the cab
    windscreen(body, W - 0.9, 2.3, 3.0, L / 2 - 0.5, L / 2 - 1.4)
    hexagon(body, (W / 2 - 0.12, 2.5, 0.6), 0.32, (1, 0, 0))
    hexagon(body, (-W / 2 + 0.12, 2.5, 0.6), 0.32, (-1, 0, 0))
    body.box((0.16, 2.2, 0.16), (-0.9, 4.1, 1.8), PLATE)  # the mast
    body.lathe((-0.9, 5.0, 1.8), (0, 1, 0), [(0, 0.3), (0.18, 0.3)], RAISED, sides=6)
    body.box((0.08, 0.08, 0.08), (-0.9, 5.25, 1.8), LIT, SIDE_GLOW)
    axles(body, L, W, [L / 2 - 1.3, L / 2 - 2.8, -L / 2 + 2.8, -L / 2 + 1.3])
    for sx in (-1, 1):  # stabiliser legs, let down behind
        body.beam((sx * 1.4, 1.4, -L / 2 + 0.4), (sx * 1.9, 0.1, -L / 2 - 0.7), 0.24, 0.24, PLATE, PLAIN, face=(sx, 0, 0))
        body.box((0.6, 0.12, 0.6), (sx * 1.9, 0.06, -L / 2 - 0.75), RAISED)
    # The howitzer: a mount on its turntable, the gun raised over the cab.
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 1.3), (0.35, 1.2)], RAISED, sides=8)
    for sx in (-1, 1):
        top.slab(0.35, (sx * 0.45, sx * 1.15, -1.6, 0.6), 1.9, (sx * 0.5, sx * 1.05, -1.2, 0.2), PLATE)
    d = (0, math.sin(ELEV), math.cos(ELEV))
    top.lathe((0, 1.4, 0.0), d, [(-1.6, 0.42), (1.0, 0.42)], PLATE, sides=8)
    gun(top, (0, 1.4, 0.0), 6.0, 0.17, along=d)
    for sx in (-1, 1):
        top.lathe((sx * 0.6, 1.0, -0.8), d, [(0, 0.16), (1.6, 0.16)], RAISED, sides=6)  # the recoil cylinders
    return {"body": body, "top": top, "top_at": (0.0, 2.05, -2.3), "muzzle": (0.0, 1.4 + 6.0 * d[1], 6.0 * d[2]), "view": 1.1}
