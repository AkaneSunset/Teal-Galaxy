"""The Coma Conglomerate's walker artillery, Mk II and III (no Mk I of its own yet): a round
graphite body carved with gold whorls, on four long sculpted legs, a crescent horn rising from its
back and curving forward over it to an amber orb it throws, and a cluster of missile pods on its
side.

Mk III: twin horns, each with amber focus halos round its orb, and a cluster on both sides.
About 5.8 and 6.8 m long.
"""

import math

from units.coma_kit import *  # noqa: F401,F403

SIZE = {2: 1.0, 3: 1.12}


def make(Part, tier):
    body, right = Part(), Part()
    # The body: a round shell, its belly dark, a ridge over its brow.
    shell(body, (0, 2.6, 0.1), (1.65, 1.5, 1.85), GRAPHITE, PLAIN, "y", sides=18, stacks=8)
    shell(body, (0, 2.0, 0.1), (1.2, 0.6, 1.4), DEEP, PLAIN, "y", -1.0, 0.0, sides=12, stacks=2, grow=0.05)
    tube(body, bezier((0, 3.3, 1.75), (0, 4.0, 1.1), (0, 4.1, -0.4), n=6), taper(6, 0.22, 0.12), GRAPHITE, sides=6, squash=1.5)
    for sx in (-1, 1):  # gold whorls on its flanks, the side's colour round its brow
        c = (sx * 1.66, 2.55, 0.35)
        for r in (0.55, 0.3):
            tube(body, [(c[0], c[1] + r * math.sin(math.tau * k / 12), c[2] + r * math.cos(math.tau * k / 12)) for k in range(12)], 0.04, GOLD, sides=4, closed=True)
        tube(body, bezier((sx * 0.45, 3.65, 1.55), (sx * 1.3, 3.45, 1.0), (sx * 1.55, 3.0, -0.3), n=6), 0.06, LIT, PAINT, sides=4, squash=1.6)
    # Four long legs, bent out and down to points.
    for a in (42, 138):
        t = math.radians(a)
        hip = (1.3 * math.sin(t), 2.2, 1.45 * math.cos(t))
        knee = (2.55 * math.sin(t), 2.3, 2.6 * math.cos(t))
        foot = (2.3 * math.sin(t), 0.0, 2.35 * math.cos(t))
        prong(right, bezier(hip, knee, (2.75 * math.sin(t), 0.9, 2.8 * math.cos(t)), foot, n=10), 0.3, glow_tip=False, flat=0.8)
        ball(right, hip, 0.36, GRAPHITE)
        shell(right, knee, (0.3, 0.42, 0.3), GRAPHITE, PLAIN, "y", sides=8, stacks=4)
    # The horns: up out of the back, curving forward over it to the orb.
    xs = (0.0,) if tier == 2 else (-0.75, 0.75)
    for x in xs:
        horn = bezier((x, 3.4, -0.9), (x * 1.1, 5.4, -1.6), (x * 1.2, 6.6, 0.0), (x * 1.2, 5.9, 0.9), n=12)
        tube(body, horn, taper(12, 0.75 if tier == 2 else 0.62, 0.32, 0.9), GRAPHITE, sides=10, squash=0.85)
        orb = (x * 1.2, 5.95, 1.05)
        ball(body, orb, 0.34, AMBER, GLOW, sides=10, stacks=5)
        tube(body, [(orb[0] + 0.38 * math.cos(math.tau * k / 12), orb[1] + 0.38 * math.sin(math.tau * k / 12), orb[2] - 0.08) for k in range(12)], 0.06, GOLD, sides=4, closed=True)
        if tier >= 3:
            ring(body, (orb[0], orb[1], orb[2] + 0.05), (0, -0.2, 1), 0.68, 0.05, sides=20)
            ring(body, (orb[0], orb[1], orb[2] + 0.1), (0, -0.2, 1), 0.92, 0.035, sides=24)
    # The missile cluster on its side (both sides at Mk III).
    clusters = (right,) if tier == 3 else (body,)
    for part in clusters:
        sx = 1
        for i, (dy, dz) in enumerate(((0, 0), (0.33, 0.18), (-0.33, 0.18), (0.33, -0.2), (-0.33, -0.2), (0, 0.38), (0, -0.4))):
            ball(part, (sx * 1.78, 2.65 + dy, 0.55 + dz), 0.2, GOLD if i % 2 else GRAPHITE, sides=7, stacks=4)
    body.mirrored(right)
    k = SIZE[tier]
    muzzle = (0.0, 5.95 * k, 1.3 * k) if tier == 2 else (0.9 * k, 5.95 * k, 1.3 * k)
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": muzzle, "view": 0.95 * k}


def build(Part):
    return make(Part, 2)
