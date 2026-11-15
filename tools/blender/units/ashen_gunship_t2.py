"""The Ashen Collective's fixed-wing gunships, Mk II and III (Mk I is ashen_gunship.py): it never
hovers; it breaks armoured columns in low passes. A long faceted dagger of a fuselage, swept wings,
twin canted fins, big podded jet engines on the wing roots with lit fans, and rotary cannons slung
under its belly.

Mk II: two engines, twin rotary cannons. Mk III: four engines, a rotary cannon and a long heavy
cannon, heavier plate. About 15 and 18 m long. The origin is its middle.
"""

from units.ashen_kit import *  # noqa: F401,F403

SIZE = {2: 1.0, 3: 1.2}


def make(Part, tier):
    body, right = Part(), Part()
    loft(body, [(-6.8, 0.2, 1.1, 0.6), (-4.0, 0.2, 1.7, 0.9), (-0.5, 0.2, 1.8, 1.05), (2.6, 0.1, 1.2, 0.9), (5.2, -0.1, 0.6, 0.5), (7.6, -0.3, 0.0, 0.0)])
    loft(body, [(1.4, 0.85, 0.0, 0.0), (2.4, 0.95, 0.55, 0.35), (4.2, 0.6, 0.4, 0.25), (5.0, 0.35, 0.0, 0.0)], GLASS)
    # Swept wings with a lit leading edge, and the tailplanes.
    plate(right, [(1.4, 1.2), (8.0, -3.4), (8.0, -4.3), (1.4, -4.0)], 0.1, 0.24, bevel=0.3)
    edge(right, (1.5, 0.1, 1.15), (7.95, 0.1, -3.35), 0.08, 0.08, face=(1, 0, 1))
    plate(right, [(1.0, -5.4), (3.8, -6.8), (3.8, -7.4), (1.0, -7.2)], 0.2, 0.16)
    fin(right, (1.0, 0.8, -3.6), (2.0, 3.6, -5.6), 2.6, 1.3)
    edge(right, (1.55, 0.95, -0.5), (1.75, 0.65, 3.0), 0.06, 0.06, face=(1, 1, 0))
    edge(right, (1.8, 0.1, -1.0), (1.4, -0.3, -4.0), 0.06, 0.06, face=(1, 0, 0))
    # The engines on the wing roots, lit fans in their intakes.
    if tier == 2:
        engine(right, (2.6, 0.75, 1.6), 0.95, 4.2, intake=True)
        right.box((0.5, 0.5, 2.4), (2.0, 0.55, -0.4), PLATE)
    else:
        for x, y in ((2.6, 0.6), (4.2, -0.5)):
            engine(right, (x, y, 1.2 - (x - 2.6) * 0.4), 0.8, 3.8, intake=True)
            right.box((0.4, 0.4, 2.0), (x - 0.5, y + 0.05 * (1 if y > 0 else -1), -0.8), PLATE)
    # Cannons under the belly.
    if tier == 2:
        rotary(right, (1.3, -0.95, 1.2), 3.6, 0.3)
        right.box((0.35, 0.7, 1.8), (1.2, -0.55, 1.6), PLATE)  # its mount
    else:
        rotary(body, (0.0, -1.05, 2.4), 4.2, 0.36)
        body.box((0.5, 0.6, 2.0), (0.0, -0.7, 2.8), PLATE)
        gun(right, (1.6, -0.85, -0.5), 5.4, 0.16)
        right.box((0.5, 0.5, 3.0), (1.6, -0.75, -0.6), PLATE)
        loft(body, [(-5.0, 1.0, 0.0, 0.0), (-3.6, 1.05, 0.9, 0.3), (0.6, 1.05, 1.0, 0.32), (1.6, 0.9, 0.0, 0.0)], RAISED)  # heavier plate over the spine
    hexagon(body, (0, 1.12 if tier == 2 else 1.4, -1.4), 0.4, (0, 1, 0), RAISED, PLAIN)
    body.mirrored(right)
    k = SIZE[tier]
    fly = 9.0
    muzzle = (1.3 * k, -0.95 * k, 4.8 * k) if tier == 2 else (0.0, -1.05 * k, 6.6 * k)
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": muzzle, "views": air_views(fly, 1.05 * k), "fly": fly, "span": 2.0 * k}


def build(Part):
    return make(Part, 2)
