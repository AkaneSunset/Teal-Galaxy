"""The Luminar Accord's gunship (Rev 2), all three marks: a crewed hovering attack craft. A
faceted, chamfered fuselage with a glazed nose in a brass frame, an octagonal chapel dome with
pointed-arch windows on its back, stub wings carrying octagonal ducted fans at their tips, box
rocket pods under the wings, a twin hex cannon under the chin and a single tail fin. Mk II
stretches the wings to carry two rocket pods each, takes a quad chin turret and a V-tail. Mk III
lifts on four fans, raises a three-tier chapel, mounts cannon clusters on side sponsons and a
six-barrel chin gun. Its light is the side's colour.

About 9, 10 and 11 m long. The origin is its middle: aircraft are placed at their flying height.
"""

import math

from units.accord_kit import *  # noqa: F401,F403

BODY = [(-4.6, 0.35, 0.38, 0.32), (-3.0, 0.22, 0.75, 0.6), (-0.6, 0.02, 1.25, 1.0), (1.7, -0.08, 1.15, 0.92), (3.4, -0.32, 0.72, 0.6), (4.25, -0.45, 0.32, 0.3)]
GLAZE = [(0.9, 0.78, 0.86, 0.26), (2.6, 0.46, 0.62, 0.2), (3.55, 0.2, 0.3, 0.04)]


def make(Part, tier):
    body, right = Part(), Part()
    loft(body, BODY, CERAMIC, PLAIN, OCT)
    for z in (-2.6, -0.2, 2.1):
        band(body, BODY, z, 0.12, OCT, grow=0.03)
    for k in (0, 1, 2, 7):
        seam(body, BODY, OCT, k, 0.04)
    seam(right, BODY, OCT, 1, 0.05, LIT, SIDE_GLOW, t=0.5, z0=-2.4, z1=2.8)
    loft(body, GLAZE, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, GLAZE, CANOPY, k, 0.03)
    chapel(body, (0, 0.98, -0.7), 0.95, 0.55, tiers=3 if tier >= 3 else 1, roof=0.6, shrink=0.8)
    # Wings and fans.
    reach = 3.0 if tier != 2 else 3.8
    fans = [(reach + 0.6, -0.4)] if tier < 3 else [(3.5, 0.9), (3.7, -1.9)]
    for fx, fz in fans:
        wing(right, [(0.9, fz + 0.75), (fx - 0.6, fz + 0.45), (fx - 0.6, fz - 0.45), (0.9, fz - 0.95)], 0.1, 0.22)
        fan(right, (fx, 0.1, fz), 0.85)
        right.lathe((fx, 0.1, fz), (1, 0, 0), [(-0.9, 0.12), (-0.8, 0.12)], BRASS, PLAIN, 6)
    # Rocket pods or sponson cannons under the wings.
    if tier == 1:
        launcher(right, (2.0, -0.35, -0.3), (0, 0, 1), 2, 2, 0.24, 1.4)
    elif tier == 2:
        for x in (1.8, 2.75):
            launcher(right, (x, -0.38, -0.3), (0, 0, 1), 2, 2, 0.24, 1.5)
    else:
        right.box((0.9, 0.7, 1.4), (1.55, -0.35, 0.1), CERAMIC)
        for a in range(4):
            t = math.tau * (a + 0.5) / 4
            hexgun(right, (1.75 + math.cos(t) * 0.2, -0.4 + math.sin(t) * 0.2, 0.8), (0, 0, 1), 1.0, 0.08, collar=False)
    # The chin gun.
    body.box((0.8, 0.5, 0.9), (0, -0.85, 2.8), GUN)
    if tier == 1:
        for x in (-0.22, 0.22):
            muzzle = hexgun(body, (x, -0.9, 3.2), (0, 0, 1), 1.1, 0.13)
    elif tier == 2:
        for x in (-0.18, 0.18):
            for y in (-0.72, -1.08):
                muzzle = hexgun(body, (x, y, 3.2), (0, 0, 1), 1.0, 0.1)
    else:
        for a in range(6):
            t = math.tau * a / 6
            muzzle = hexgun(body, (math.cos(t) * 0.2, -0.9 + math.sin(t) * 0.2, 3.2), (0, 0, 1), 1.3, 0.07, collar=False)
        body.lathe((0, -0.9, 3.2), (0, 0, 1), [(0, 0.34), (0.3, 0.34)], BRASS, PLAIN, 6)
    # The tail.
    if tier == 2:
        fin(right, (0.2, 0.55, -3.0), (1.3, 1.75, -4.1), 1.5, 0.6)
    else:
        fin(body, (0, 0.55, -3.0), (0, 1.9, -4.2), 1.5, 0.6)
        wing(right, [(0.3, -3.4), (1.6, -4.0), (1.6, -4.5), (0.3, -4.5)], 0.35, 0.1)
    body.mirrored(right)
    k = {1: 1.0, 2: 1.1, 3: 1.22}[tier]
    fly = 7.0 + tier
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -0.9 * k, 4.4 * k), "views": air_views(fly, 0.95 * k, -0.4), "fly": fly}


def build(Part):
    return make(Part, 1)
