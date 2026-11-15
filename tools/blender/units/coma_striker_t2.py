"""The Coma Conglomerate's phase-shift assault walkers, Mk II and III (no Mk I of its own yet): a
tall, narrow two-legged warrior in curved graphite plates edged in gold. A crescent crest sweeps up
over its head, an amber eye burns in its chest, round missile pods sit on its shoulders, and each
long arm ends in a pair of scythe claws. It stands on bent-back legs with clawed feet.

Mk III: heavier plates washed in gold (its full phase field), and a halo standing behind it.
About 5.4 and 6.2 m tall.
"""

import math

from units.coma_kit import *  # noqa: F401,F403

SIZE = {2: 1.0, 3: 1.15}


def make(Part, tier):
    body, right = Part(), Part()
    plate = GRAPHITE if tier == 2 else Color(0.42, 0.33, 0.18)
    # The legs: bent back, clawed feet.
    tube(right, [(0.5, 2.6, 0.0), (0.72, 1.65, 0.45), (0.74, 0.55, -0.4), (0.74, 0.12, -0.05)], [0.3, 0.26, 0.2, 0.18], GRAPHITE, sides=7)
    shell(right, (0.62, 2.15, 0.25), (0.36, 0.62, 0.36), plate, PLAIN, "y", sides=8, stacks=5)  # thigh plate
    shell(right, (0.74, 1.15, 0.0), (0.26, 0.6, 0.3), plate, PLAIN, "y", sides=8, stacks=5)  # shin plate
    for dx in (-0.18, 0.0, 0.18):
        prong(right, bezier((0.74, 0.15, 0.0), (0.74 + dx * 1.6, 0.2, 0.55), (0.74 + dx * 2.2, 0.0, 0.85), n=4), 0.12, glow_tip=False)
    prong(right, bezier((0.74, 0.2, -0.1), (0.74, 0.15, -0.5), (0.74, 0.0, -0.75), n=4), 0.1, glow_tip=False)
    # The hips, waist and chest.
    shell(body, (0, 2.75, 0.0), (0.72, 0.35, 0.45), GRAPHITE, PLAIN, "y", sides=12, stacks=4)
    tube(body, [(0, 2.8, 0), (0, 3.3, 0.02)], 0.32, DEEP, sides=8)
    shell(body, (0, 3.95, 0.0), (1.0, 0.9, 0.66), plate, PLAIN, "y", -0.7, 1.0, sides=16, stacks=6)
    shell(body, (0, 3.35, 0.08), (0.6, 0.4, 0.45), plate, PLAIN, "y", sides=10, stacks=4)
    for sx in (-1, 1):  # gold edges down the chest, the side's colour beside them
        tube(body, bezier((sx * 0.18, 4.75, 0.5), (sx * 0.75, 4.2, 0.65), (sx * 0.3, 3.3, 0.55), n=6), 0.05, GOLD, sides=4)
        tube(body, bezier((sx * 0.45, 4.6, 0.48), (sx * 0.95, 4.1, 0.45), (sx * 0.55, 3.45, 0.42), n=6), 0.06, LIT, PAINT, sides=4, squash=1.5)
    eye(body, (0, 3.98, 0.66), (0, 0, 1), 0.3)
    # The head under its crescent crest.
    shell(body, (0, 4.85, 0.18), (0.32, 0.36, 0.4), GRAPHITE, PLAIN, "y", sides=10, stacks=5)
    crest = bezier((0, 4.35, -0.55), (0, 5.9, -0.3), (0, 5.85, 0.9), (0, 5.0, 1.45), n=12)
    tube(body, crest, [0.18 + 0.32 * math.sin(math.pi * k / 12) for k in range(13)], plate, PLAIN, sides=8, squash=0.9)
    tube(body, [(p[0], p[1] + 0.06, p[2]) for p in crest[2:11]], 0.05, GOLD, sides=4, squash=1.0)
    # The shoulders: plates, and the pods on them.
    shell(right, (1.2, 4.45, 0.0), (0.55, 0.45, 0.58), plate, PLAIN, "y", -0.3, 1.0, sides=10, stacks=4)
    ball(right, (1.3, 4.95, 0.05), 0.48, GRAPHITE, sides=10, stacks=5)
    pods(right, (1.3, 4.95, 0.42), (1, 0, 0), (0, 1, 0), 3, 2 if tier == 2 else 3, 0.11)
    # The arms, and the scythe claws on them.
    tube(right, [(1.22, 4.3, 0.0), (1.5, 3.4, 0.15), (1.62, 2.55, 0.5)], [0.22, 0.2, 0.18], GRAPHITE, sides=7)
    shell(right, (1.56, 2.95, 0.33), (0.3, 0.55, 0.32), plate, PLAIN, "y", sides=8, stacks=4)
    blade = plate if tier == 2 else GOLD
    prong(right, bezier((1.64, 2.6, 0.55), (2.75, 2.1, 0.75), (2.4, 0.9, 0.9), (1.75, 0.5, 0.7), n=12), 0.28, glow_tip=False, flat=0.45)
    prong(right, bezier((1.6, 2.5, 0.6), (2.15, 1.75, 1.05), (1.55, 1.15, 1.15), n=8), 0.18, glow_tip=False, flat=0.45)
    tube(right, bezier((1.75, 2.62, 0.6), (2.8, 2.15, 0.8), (2.45, 0.95, 0.95), n=8), 0.05, blade if tier == 3 else GOLD, sides=4)
    if tier >= 3:  # the halo behind it
        ring(body, (0, 3.9, -0.85), (0, 0, 1), 2.7, 0.07, sides=40)
    body.mirrored(right)
    k = SIZE[tier]
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, 3.98 * k, 0.9 * k), "view": 1.05 * k}


def build(Part):
    return make(Part, 2)
