"""The Ashen Collective's mobile AA, Mk I to III: a faceted wheeled hull with a cab of dark glass
up front and a turret behind carrying flak cannons raised to the sky, missile boxes either side
of them with lit cells, and a phased-array radar panel at its back. Its light is the side's colour.

Mk I: six wheels, twin 30 mm guns, one four-cell box. Mk II: eight wheels, twin 35 mm, two six-cell
boxes, a bigger radar. Mk III: triple guns. About 7, 8.4 and 9.4 m long.
"""

from units.ashen_kit import *  # noqa: F401,F403


def make(Part, tier):
    body, top = Part(), Part()
    L, W = {1: (7.0, 3.0), 2: (8.4, 3.2), 3: (9.4, 3.3)}[tier]
    hull(body, L, W, 2.4, nose=1.8)
    cab_glass(body, L, W, 2.4, 1.8)
    zs = [L / 2 - 1.3, -0.4, -L / 2 + 1.3] if tier == 1 else [L / 2 - 1.3, L / 2 - 2.9, -L / 2 + 2.9, -L / 2 + 1.3]
    axles(body, L, W, zs)
    hexagon(body, (W / 2 + 0.02, 1.7, -0.6), 0.32, (1, 0, 0))
    hexagon(body, (-W / 2 - 0.02, 1.7, -0.6), 0.32, (-1, 0, 0))
    # The turret: a faceted block, the guns raised out of its front.
    top.slab(0.0, (-1.2, 1.2, -1.4, 1.2), 1.0, (-0.95, 0.95, -1.2, 0.8), PLATE)
    top.box((1.3, 0.9, 1.4), (0, 1.2, -0.2), RAISED)
    n = 2 if tier < 3 else 3
    for i in range(n):
        x = (i - (n - 1) / 2) * 0.5
        gun(top, (x, 1.25, 0.2), 3.0 + 0.3 * tier, 0.11, along=(0, 0.6, 1))
        top.lathe((x, 1.25, 0.2), (0, 0.6, 1), [(1.2, 0.15), (1.5, 0.15)], RECESS, sides=6)
    cells_n = (2, 2) if tier == 1 else (2, 3)
    sides = (1,) if tier == 1 else (1, -1)
    for sx in sides:
        cells(top, (sx * 1.65, 1.2, 0.0), cells_n[0], cells_n[1], 0.36)
    radar(top, (0.0, 1.9 if tier == 1 else 2.0, -1.15), 1.4 if tier == 1 else 1.8, 1.0 if tier == 1 else 1.3)
    k = 1.0
    return {"body": body, "top": top, "top_at": (0.0, 2.75, -1.0), "muzzle": (0.0, 1.25 + 0.6 * 3.2 * 0.51, 0.2 + 3.2 * 0.86), "view": 0.95 + 0.05 * tier}


def build(Part):
    return make(Part, 1)
