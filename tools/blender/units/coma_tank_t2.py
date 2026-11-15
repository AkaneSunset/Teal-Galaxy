"""The Coma Conglomerate's hover tanks, Mk II and III (it has no Mk I of its own yet): a low,
flowing graphite hull, its edge lobed like poured metal, riding on stacked ring discs lit amber
round their rims, a domed turret drawn out into a long thin lance cannon with an amber muzzle, and
missile pods along its flanks.

Mk II: three ring discs, one hull missile pod. Mk III: four discs, a pod on each flank, a heavier
lance. About 7.2 and 8.4 m long.
"""

import math

from units.coma_kit import *  # noqa: F401,F403

SIZE = {2: 1.0, 3: 1.15}


def make(Part, tier):
    body, top = Part(), Part()
    # The hull: a low flowing shell, lobes swelling out of its edge at the corners.
    shell(body, (0, 1.1, 0.0), (3.0, 1.15, 3.7), GRAPHITE, PLAIN, "y", -0.35, 1.0, sides=24, stacks=6)
    for x, z, r in ((2.3, 2.0, 1.15), (-2.3, 2.0, 1.15), (2.6, -1.5, 1.2), (-2.6, -1.5, 1.2), (0, -3.2, 1.1)):
        shell(body, (x, 0.95, z), (r, 0.55, r * 1.15), GRAPHITE, PLAIN, "y", -0.4, 1.0, sides=14, stacks=4)
    shell(body, (0, 0.85, 0.0), (2.6, 0.5, 3.2), DEEP, PLAIN, "y", -1.0, 0.0, sides=18, stacks=2)
    # A raised spine down the front, an amber spiral boss on its nose.
    tube(body, bezier((0, 2.0, -1.0), (0, 2.25, 1.6), (0, 1.35, 3.6), n=8), taper(8, 0.32, 0.18), GRAPHITE, sides=6, squash=1.4)
    eye(body, (0, 1.45, 3.2), (0, 0.55, 1), 0.42)
    for sx in (-1, 1):  # the side's colour in a sweep down each side, its light along the skirt
        tube(body, bezier((sx * 0.9, 2.0, 2.4), (sx * 2.4, 1.85, 0.8), (sx * 2.6, 1.6, -2.4), n=8), 0.1, LIT, PAINT, sides=4, squash=1.6)
        tube(body, bezier((sx * 2.0, 0.72, 3.1), (sx * 3.3, 0.72, 0.0), (sx * 2.2, 0.72, -3.2), n=10), 0.04, LIT, SIDE_GLOW, sides=4)
    # The ring discs it rides on.
    discs = [(2.1, 2.2), (-2.1, 2.2), (0, -2.7)] if tier == 2 else [(2.3, 2.2), (-2.3, 2.2), (2.3, -2.3), (-2.3, -2.3)]
    for x, z in discs:
        disc(body, (x, 0.05, z), 1.25, 0.32)
        disc(body, (x, 0.42, z), 1.0, 0.28)
    # Missile pods along its flanks.
    for sx in ((1,) if tier == 2 else (1, -1)):
        missile(body, (sx * 2.55, 1.75, -1.6), (0, 0, 1), 2.6, 0.32, tip=AMBER)
        body.box((0.3, 0.3, 1.2), (sx * 2.35, 1.55, -0.4), GRAPHITE)
    # The turret: a dome drawn out into the lance.
    shell(top, (0, 0.0, -0.3), (1.35, 1.05, 1.75), GRAPHITE, PLAIN, "y", 0.0, 1.0, sides=16, stacks=5)
    for a in (-30, 30):
        t = math.radians(a)
        tube(top, [(1.37 * math.sin(t) * math.cos(math.radians(la)), 1.07 * math.sin(math.radians(la)), -0.3 + 1.77 * math.cos(t) * math.cos(math.radians(la))) for la in range(0, 91, 15)], 0.05, GOLD, sides=4)
    r0 = 0.5 if tier == 2 else 0.6
    lance = bezier((0, 0.4, 0.6), (0, 0.6, 2.6), (0, 0.5, 5.9), n=12)
    tube(top, lance, taper(12, r0, 0.11, 0.35), GRAPHITE, sides=10)
    top.lathe(lance[-1], (0, 0, 1), [(0, 0.17), (0.35, 0.17)], GOLD, sides=10)
    top.lathe((0, 0.5, 5.9 + 0.35), (0, 0, 1), [(0, 0.12), (0.08, 0.12)], AMBER, GLOW, sides=10)
    k = SIZE[tier]
    return {"body": scaled(body, k), "top": scaled(top, k), "top_at": (0, 2.05 * k, -0.4 * k), "muzzle": (0.0, 0.5 * k, 6.35 * k), "view": 0.95 * k}


def build(Part):
    return make(Part, 2)
