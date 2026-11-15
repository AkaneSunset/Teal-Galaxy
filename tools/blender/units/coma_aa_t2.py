"""The Coma Conglomerate's mobile AA, Mk II and III (no Mk I of its own yet): a hovering bulb of
graphite, ribbed like a seed, on a ring disc pad lit amber, its top a crown of needle spires (its
missiles) round a tracking eye, and a halo round the crown that guides them. Swept fins fan out at
its foot.

Mk III: broader, with swept armoured wings either side bristling with more spires, a taller
crown, and a stack of three discs under it. About 5.4 and 6.6 m across.
"""

import math

from units.coma_kit import *  # noqa: F401,F403

SIZE = {2: 1.0, 3: 1.12}


def spire(P, at, h, r, lean=(0.0, 0.0)):
    """A needle missile standing up from `at`, `h` tall."""
    x, y, z = at
    tube(P, bezier(at, (x + lean[0] * 0.3, y + h * 0.5, z + lean[1] * 0.3), (x + lean[0], y + h, z + lean[1]), n=4), taper(4, r, 0.0, 0.8), GRAPHITE, sides=6)
    tube(P, [(x, y + 0.04, z), (x, y + 0.12, z)], r * 1.25, GOLD, sides=6)


def make(Part, tier):
    body, right = Part(), Part()
    base = 1.0 if tier == 2 else 1.6
    # The disc pad(s).
    stack = [(0.0, 1.6, 0.3)] if tier == 2 else [(0.0, 1.0, 0.25), (0.45, 1.45, 0.3), (0.95, 1.85, 0.3)]
    for y, r, h in stack:
        disc(body, (0, y, 0), r, h)
    disc(body, (0, base - 0.05, 0), 1.05 if tier == 2 else 1.25, 0.25)
    # The bulb: swelling out, ribbed, narrowing to the crown.
    c = (0, base + 1.65, 0)
    rx = 1.7 if tier == 2 else 1.55
    shell(body, c, (rx, 1.45, rx * 0.95), GRAPHITE, PLAIN, "y", -0.85, 0.85, sides=20, stacks=8)
    for a in range(0, 360, 30):
        t = math.radians(a)
        rib = [(c[0] + (rx + 0.04) * math.sin(t) * math.cos(math.radians(la)), c[1] + 1.47 * math.sin(math.radians(la)), c[2] + (rx * 0.95 + 0.04) * math.cos(t) * math.cos(math.radians(la))) for la in range(-55, 60, 15)]
        if a in (30, 330):
            tube(body, rib, 0.09, LIT, PAINT, sides=4)
        else:
            tube(body, rib, 0.06, GOLD if a % 60 == 0 else GRAPHITE, sides=4)
    # Fins fanning out at its foot.
    for a in range(30, 360, 60):
        t = math.radians(a)
        prong(body, bezier((0.9 * math.sin(t), c[1] - 1.0, 0.9 * math.cos(t)), (2.1 * math.sin(t), c[1] - 1.2, 2.1 * math.cos(t)), (2.5 * math.sin(t), c[1] - 0.6, 2.5 * math.cos(t)), n=6), 0.28, glow_tip=False, flat=2.2)
    # The crown: the eye, spires round it, the halo.
    top = c[1] + 1.25
    eye(body, (0, top + 0.05, 0.55), (0, 0.15, 1), 0.38)
    crown = [(0.0, -0.35, 2.0), (0.55, -0.05, 1.5), (-0.55, -0.05, 1.5), (0.9, 0.3, 1.3), (-0.9, 0.3, 1.3), (0.35, -0.75, 1.6), (-0.35, -0.75, 1.6), (0.75, -0.55, 1.15), (-0.75, -0.55, 1.15), (0.0, 0.1, 1.2)]
    for x, z, h in crown:
        spire(body, (x, top - 0.1, z), h * (1.0 if tier == 2 else 1.25), 0.15, (x * 0.3, z * 0.2))
    if tier == 2:
        ring(body, (0, top + 0.25, 0), (0, 1, 0), 1.9, 0.06, sides=36)
        ring(body, (0, top + 0.25, 0), (0, 1, 0), 2.3, 0.04, sides=36)
    else:  # the swept armoured wings, spires along them
        for k in range(8):
            t = k / 7
            shell(right, (1.4 + t * 1.7, c[1] + 0.3 - t * 0.5, -0.1 - t * 0.5), (0.9 - t * 0.45, 0.85 - t * 0.35, 1.0 - t * 0.4), GRAPHITE, PLAIN, "y", -0.6, 1.0, sides=10, stacks=4)
        prong(right, bezier((2.8, c[1] - 0.2, -0.6), (3.7, c[1] - 0.6, -1.0), (3.9, c[1] - 1.3, -1.3), n=6), 0.35, glow_tip=False, flat=2.0)
        for x, z, h in ((1.6, 0.1, 1.2), (2.1, -0.25, 1.05), (2.6, -0.55, 0.9), (3.05, -0.8, 0.75)):
            spire(right, (x, c[1] + 1.0 - (x - 1.6) * 0.35, z), h, 0.14, (0.15, 0.0))
    body.mirrored(right)
    k = SIZE[tier]
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, (top + 1.8) * k, 0.4 * k), "view": 0.9 * k}


def build(Part):
    return make(Part, 2)
