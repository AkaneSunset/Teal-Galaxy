"""The Coma Conglomerate's bombers, Mk I to III: a broad manta of a wing, a crescent whose horns
sweep back and curl down, round a heavy body with a dark mouth at its nose and an amber ordnance
ring glowing in its belly, and banks of round missile pods hung under the wing either side.

Mk II: a second, smaller crescent wing stacked over the first, and bigger pod banks. Mk III: the
same wrapped in two great amber halos. About 14, 17 and 20 m long. The origin is its middle.
"""

import math

from units.coma_kit import *  # noqa: F401,F403

SIZE = {1: 1.0, 2: 1.15, 3: 1.32}


def _wing(P, y, span, chord, thick, sweep):
    """One crescent wing's right half: thick at the body, out to a horn swept back and curled down."""
    spine = bezier((0.4, y, 0.6), (span * 0.62, y + 0.25, 0.9), (span * 0.95, y - 0.4, -sweep * 0.45), (span * 0.9, y - 1.9, -sweep), n=14)
    R = taper(14, thick, 0.02, 1.15)
    S = [max(1.0, chord * (1 - k / 14) ** 0.8 / max(r, 1e-3)) for k, r in enumerate(R)]
    tube(P, spine, R, GRAPHITE, PLAIN, sides=10, squash=S)
    tube(P, [(p[0], p[1] + R[k] * 0.9, p[2] + R[k] * 0.2) for k, p in enumerate(spine[:12])], 0.05, LIT, PAINT, sides=4, squash=1.5)
    return spine


def make(Part, tier):
    body, right = Part(), Part()
    # The body: a heavy rounded shell, a ridge over it, a dark mouth at the nose.
    shell(body, (0, 0.1, 0.2), (1.7, 1.25, 4.6), GRAPHITE, PLAIN, "z", sides=14, stacks=9)
    tube(body, bezier((0, 1.15, -3.6), (0, 1.75, 0.0), (0, 1.1, 3.4), n=8), taper(8, 0.5, 0.2), GRAPHITE, sides=8, squash=1.4)
    body.lathe((0, 0.0, 4.2), (0, 0, 1), [(0, 0.62), (0.7, 0.55)], GRAPHITE, sides=12, caps=False)
    body.lathe((0, 0.0, 4.75), (0, 0, 1), [(0, 0.42), (0.1, 0.42)], DEEP, sides=12)
    tube(body, [(0.6 * math.cos(math.tau * k / 14), 0.6 * math.sin(math.tau * k / 14), 4.9) for k in range(14)], 0.08, GOLD, sides=4, closed=True)
    # The belly's ordnance ring, glowing amber.
    eye(body, (0, -1.0, 2.0), (0, -0.55, 1), 0.95)
    ring(body, (0, -1.05, 1.0), (0, -1, 0.15), 1.05, 0.1, sides=24)
    # The wing.
    _wing(right, 0.15, 7.0, 3.0, 0.42, 5.2)
    tube(right, bezier((1.6, 0.0, 2.4), (4.6, 0.2, 2.2), (6.5, -0.4, -1.2), n=8), 0.035, LIT, SIDE_GLOW, sides=4)
    # Pod banks under the wing: two rows of round pods each side.
    n = 3 if tier == 1 else 4
    for row in range(2):
        for i in range(n):
            ball(right, (1.9 + i * 0.85 - row * 0.2, -0.75 - row * 0.62, 0.7 - row * 0.3 - i * 0.05), 0.42 if tier == 1 else 0.48, GRAPHITE)
    if tier >= 2:  # a second crescent over the first, its horns swept back over the wing
        shell(body, (0, 1.4, 0.6), (1.0, 0.8, 2.6), GRAPHITE, PLAIN, "z", sides=12, stacks=6)
        _wing(right, 1.55, 4.8, 1.8, 0.3, 4.6)
        eye(body, (0, 2.05, 1.5), (0, 1, 0.5), 0.45)
    if tier >= 3:  # two great halos round it, and a third bank of pods
        ring(body, (0, 0.3, -0.6), (0, 0, 1), 6.4, 0.11, sides=44)
        ring(body, (0, 0.3, -0.7), (0, 0, 1), 7.1, 0.07, sides=44)
        for i in range(3):
            ball(right, (1.3 + i * 0.85, -0.55, -1.2), 0.42, GRAPHITE)
    body.mirrored(right)
    k = SIZE[tier]
    fly = 10.0
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -1.2 * k, 1.8 * k), "views": air_views(fly, 1.15 * k), "fly": fly, "span": 4.0 * k}


def build(Part):
    return make(Part, 1)
