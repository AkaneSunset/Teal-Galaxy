"""The Luminar Accord's Vespers light artillery, Mk II and Mk III (Rev 2): a hover skimmer. A long,
faceted wedge of a hull on a sheet of light, a glazed cab at the prow, an octagonal chapel with
pointed-arch windows and a tall pyramid roof at the stern, and before it twin hex plasma mortars on
a trunnion, thrown up to lob over the line. Mk III keeps the hull, takes a quad mortar battery and
a taller two-tier chapel. Its light is the side's colour.

About 3.8 m wide and 8 m long at Mk II (the server's artillery is 3 m in radius).
"""

import math

from units.accord_kit import *  # noqa: F401,F403

HULL = [(-3.5, 1.3, 1.6, 0.78), (-2.7, 1.35, 1.9, 0.85), (0.4, 1.25, 1.7, 0.7), (2.8, 0.95, 1.0, 0.45), (4.2, 0.72, 0.3, 0.14)]
GLAZE = [(0.7, 1.86, 0.85, 0.24), (2.2, 1.58, 0.6, 0.16), (3.0, 1.34, 0.3, 0.03)]
PITCH = 35  # degrees up


def make(Part, tier):
    body, right, top = Part(), Part(), Part()
    loft(body, HULL, CERAMIC, PLAIN, WEDGE)
    underglow(body, HULL, WEDGE, 0.24)
    for z in (-1.4, 0.6, 2.4):
        band(body, HULL, z, 0.14, WEDGE)
    for k in (0, 1, 7):
        seam(body, HULL, WEDGE, k, 0.04)
    seam(right, HULL, WEDGE, 1, 0.05, LIT, SIDE_GLOW, t=0.5, z0=-0.8, z1=3.2)
    loft(body, GLAZE, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, GLAZE, CANOPY, k, 0.03)
    # The chapel at the stern, a brass finial on its roof.
    tip = chapel(body, (0, 2.1, -2.4), 1.05, 0.95, tiers=2 if tier >= 3 else 1, roof=1.25, shrink=0.85)
    tube(body, [tip, (tip[0], tip[1] + 0.45, tip[2])], 0.06, BRASS, PLAIN, sides=4)
    for x in (-0.55, 0.55):  # lit slots down its foot
        body.box((0.07, 0.5, 0.05), (x, 2.4, -1.37), LIT, SIDE_GLOW)
    drum(body, (0, 2.0, -0.4), 0.9, 0.14, SHADE)
    # The mortars on their trunnion.
    top.box((1.5, 0.5, 1.2), (0, 0.25, 0), GUN)
    top.box((1.6, 0.08, 1.3), (0, 0.52, 0), BRASS)
    d = (0, math.sin(math.radians(PITCH)), math.cos(math.radians(PITCH)))
    rows = [(0.32, 0.75)] if tier < 3 else [(0.32, 0.6), (0.32, 1.12)]
    for x, y in rows:
        for s in (-1, 1):
            muzzle = hexgun(top, (s * x, y, -0.6), d, 2.6, 0.2 if tier < 3 else 0.17)
    k = 1.0 if tier == 2 else 1.08
    body.mirrored(right)
    return {"body": scaled(body, k), "top": scaled(top, k), "top_at": (0.0, 2.1 * k, -0.4 * k), "muzzle": tuple(c * k for c in muzzle), "view": 0.95 * k}


def build(Part):
    return make(Part, 2)
