"""The Ashen Collective's fighters, Mk I to III: a faceted dart. A long ridged fuselage to a needle
nose, dark glass let into it, cropped delta wings, twin canted fins, two engines side by side
astern, and cannons in the wing roots. Its light is the side's colour: seams along the fuselage,
the wings' leading edges, the exhausts.

Mk I: two missiles. Mk II: four, and heavier cannons. Mk III: six, a long rail cannon out of its
nose and raised engine nacelles. About 12, 13.5 and 15.5 m long. The origin is its middle.
"""

from units.ashen_kit import *  # noqa: F401,F403

SIZE = {1: 1.0, 2: 1.12, 3: 1.3}


def make(Part, tier):
    body, right = Part(), Part()
    loft(body, [(-5.6, 0.0, 1.25, 0.55), (-3.4, 0.05, 1.45, 0.7), (-0.6, 0.15, 1.2, 0.85), (2.0, 0.15, 0.78, 0.7), (4.4, 0.0, 0.42, 0.42), (6.4, -0.1, 0.0, 0.0)])
    loft(body, [(0.6, 0.62, 0.0, 0.0), (1.6, 0.72, 0.45, 0.32), (3.4, 0.52, 0.35, 0.25), (4.2, 0.35, 0.0, 0.0)], GLASS)
    # The intakes either side of the cockpit.
    loft(right, [(-1.5, 0.0, 0.42, 0.45), (1.0, 0.0, 0.42, 0.45), (1.4, -0.05, 0.3, 0.35)], PLATE, x=1.3)
    right.box((0.6, 0.6, 0.05), (1.3, 0.0, 1.42), RECESS, PLAIN, (0, 0, 0))
    # The wing, a lit leading edge; a strake running forward to the cockpit.
    plate(right, [(0.9, 1.6), (5.4, -2.6), (5.4, -3.6), (3.2, -3.6), (2.6, -4.4), (0.9, -4.4)], 0.0, 0.2, bevel=0.3)
    plate(right, [(0.6, 3.8), (1.4, 1.2), (1.2, -0.5), (0.6, -0.5)], 0.1, 0.16)
    edge(right, (1.0, 0.0, 1.55), (5.35, 0.0, -2.55), 0.07, 0.07, face=(1, 0, 1))
    edge(right, (0.62, 0.72, -0.5), (0.95, 0.5, -4.2), 0.05, 0.05, face=(1, 1, 0))
    edge(right, (1.05, 0.12, 3.6), (1.6, 0.0, 1.0), 0.05, 0.05, face=(1, 1, 0))
    # Twin fins, canted out; the tailplanes.
    fin(right, (0.95, 0.55, -2.4), (1.75, 2.6, -4.0), 2.0, 1.0)
    plate(right, [(1.3, -4.2), (3.6, -5.6), (3.6, -6.2), (1.3, -6.0)], -0.05, 0.14)
    # Two engines astern, their exhausts lit.
    engine(right, (0.6, 0.0, -4.4), 0.5, 1.4)
    # Cannons in the wing roots.
    gun(right, (1.35, -0.3, 0.8), 2.2 if tier == 1 else 2.6, 0.08 if tier == 1 else 0.11)
    # Missiles under the wings.
    xs = {1: (3.4,), 2: (2.6, 4.2), 3: (2.2, 3.4, 4.6)}[tier]
    for x in xs:
        missile(right, (x, -0.45, -2.4 + (x - 2.2) * -0.3), 2.4, 0.15)
    if tier >= 3:  # a rail cannon out of the nose; raised nacelles over the engines
        gun(body, (0.0, -0.1, 6.0), 1.9, 0.1)
        loft(right, [(-4.6, 0.75, 0.0, 0.0), (-3.6, 0.85, 0.45, 0.38), (-0.6, 0.85, 0.5, 0.42), (0.2, 0.7, 0.0, 0.0)], PLATE, x=0.9)
        edge(right, (1.4, 0.85, -0.6), (1.4, 0.85, -3.6), 0.05, 0.05, face=(1, 0, 0))
    hexagon(body, (0, 0.98, -1.4), 0.35, (0, 1, 0), RAISED, PLAIN)
    body.mirrored(right)
    k = SIZE[tier]
    fly = 9.0
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (1.35 * k, -0.3 * k, 3.2 * k), "views": air_views(fly, 0.85 * k), "fly": fly}


def build(Part):
    return make(Part, 1)
