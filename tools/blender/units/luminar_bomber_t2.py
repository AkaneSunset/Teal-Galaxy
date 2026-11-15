"""The Luminar Accord's Squall fast attack bomber, Mk II and Mk III (Rev 2): a crewed strike bomber.
A faceted needle fuselage on a hard-edged arrowhead delta, a faceted glass canopy in a brass frame,
an octagonal dome fairing behind it, a boxy nacelle with a hex nozzle under each wing and a belly
bay for its tidal charges. Mk III goes to a cranked double delta with down-turned tip fins, twin
tails, four nacelles and a two-tier dome fairing. Its light is the side's colour.

About 12 m long and 11 m across at Mk II, 14 m by 15 m at Mk III. The origin is its middle:
aircraft are placed at their flying height.
"""

from units.accord_kit import *  # noqa: F401,F403

NEEDLE = [(0, 1), (0.62, 0.55), (1, 0), (0.6, -0.6), (-0.6, -0.6), (-1, 0), (-0.62, 0.55)]
BODY = [(-5.2, 0.1, 0.75, 0.48), (-3.0, 0.15, 1.1, 0.66), (0.0, 0.15, 1.0, 0.62), (3.0, 0.0, 0.5, 0.36), (6.2, -0.15, 0.0, 0.0)]
GLAZE = [(0.6, 0.6, 0.5, 0.3), (2.4, 0.42, 0.38, 0.22), (3.2, 0.26, 0.15, 0.04)]
DELTA = [(0.6, 3.4), (5.6, -3.5), (5.4, -4.3), (0.6, -4.5)]
CRANKED = [(0.6, 3.6), (2.4, 0.4), (6.2, -2.8), (6.2, -3.6), (0.6, -4.6)]


def nacelle(P, x, z0, z1, y=-0.38):
    """A boxy engine nacelle under the wing: ceramic, brass at its lip, a dark intake, a hex nozzle."""
    P.slab(y - 0.38, (x - 0.42, x + 0.42, z0, z1), y + 0.38, (x - 0.38, x + 0.38, z0 + 0.1, z1 - 0.2), CERAMIC)
    P.box((0.9, 0.84, 0.1), (x, y, z1 - 0.05), BRASS)
    P.box((0.6, 0.56, 0.04), (x, y, z1 + 0.01), WORKS)
    P.box((0.05, 0.08, (z1 - z0) * 0.6), (x + 0.43, y + 0.1, (z0 + z1) / 2), LIT, SIDE_GLOW)
    nozzle(P, (x, y, z0 + 0.05), (0, 0, -1), 0.36, 0.5)
    P.box((0.16, 0.36, 0.8), (x, y + 0.52, (z0 + z1) / 2), CERAMIC)  # the pylon


def make(Part, tier):
    body, right = Part(), Part()
    loft(body, BODY, CERAMIC, PLAIN, NEEDLE)
    for k in (1, 2, 6):
        seam(body, BODY, NEEDLE, k, 0.035, z1=5.0)
    for z in (-3.6, -1.0, 1.4):
        band(body, BODY, z, 0.1, NEEDLE, grow=0.025)
    seam(right, BODY, NEEDLE, 2, 0.045, LIT, SIDE_GLOW, t=0.5, z0=-0.4, z1=3.4)
    loft(body, GLAZE, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, GLAZE, CANOPY, k, 0.025)
    body.box((1.0, 0.1, 3.0), (0, -0.45, -1.0), WORKS)  # the belly bay
    body.box((0.06, 0.04, 3.0), (0, -0.51, -1.0), BRASS)
    # The dome fairing.
    drum(body, (0, 0.55, -1.6), 0.55, 0.3, CERAMIC)
    drum(body, (0, 0.85, -1.6), 0.58, 0.06, BRASS)
    if tier >= 3:
        drum(body, (0, 0.91, -1.6), 0.46, 0.2, CERAMIC, r1=0.4)
        pyramid(body, (0, 1.11, -1.6), 0.42, 0.18, CERAMIC)
    else:
        pyramid(body, (0, 0.91, -1.6), 0.55, 0.25, CERAMIC)
    for x in (-0.35, 0.35):
        body.box((0.2, 0.07, 0.05), (x, 0.72, -1.02), LIT, SIDE_GLOW)
    if tier < 3:
        wing(right, DELTA, 0.0, 0.2, edge=2)
        right.beam((1.6, 0.11, 1.2), (4.0, 0.11, -2.4), 0.1, 0.04, LIT, SIDE_GLOW, face=(0, 1, 0))
        nacelle(right, 2.6, -3.6, -0.4)
        fin(right, (0.6, 0.5, -3.2), (1.7, 1.8, -4.6), 1.7, 0.6)
    else:
        wing(right, CRANKED, 0.0, 0.22, edge=3)
        right.beam((1.6, 0.12, 1.3), (4.6, 0.12, -2.4), 0.1, 0.04, LIT, SIDE_GLOW, face=(0, 1, 0))
        fin(right, (6.2, 0.0, -2.8), (6.6, -0.95, -3.4), 0.8, 0.45, 0.12)  # the down-turned tip
        for x in (1.9, 3.5):
            nacelle(right, x, -3.8, -0.6 if x < 3 else -1.6)
        fin(right, (0.7, 0.5, -3.2), (1.5, 2.1, -4.8), 1.8, 0.7)
    body.mirrored(right)
    k = 1.0 if tier == 2 else 1.15
    fly = 10.0
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -0.5 * k, -1.0 * k), "views": air_views(fly, 1.1 * k), "fly": fly, "span": 4.0 * k}


def build(Part):
    return make(Part, 2)
