"""The Ashen Collective's bombers, Mk I to III: faceted flying wings. A blended body rising out of
a broad arrow of a wing, its trailing edge sawtoothed, engines buried in it and their exhausts lit
in the side's colour, lines of light along its leading edges.

Mk I (the fast attack bomber): a narrow lifting body, sawtooth edges all round its tail. Mk II:
broader, with two open bomb bays under it, bombs showing. Mk III (the strategic bomber): a huge
wing, rows of lit exhausts under its leading edge and two gun turrets on its back. About 12.5, 15
and 19 m long. The origin is its middle.
"""

from units.ashen_kit import *  # noqa: F401,F403

SIZE = {1: 1.0, 2: 1.15, 3: 1.45}


def make(Part, tier):
    body, right = Part(), Part()
    span = {1: 6.6, 2: 8.2, 3: 9.0}[tier]
    nose = 6.4
    # The wing: an arrow from the nose out to the tips, its trailing edge sawtoothed.
    teeth = []
    n = 5 if tier != 2 else 3
    for i in range(n):
        x0 = span * (1 - i / n)
        x1 = span * (1 - (i + 0.5) / n)
        teeth += [(x0, -3.0 + 0.3 * i / n), (x1, -3.7 + 0.3 * i / n)]
    outline = [(0.0, nose), (span, -2.6)] + teeth + [(0.0, -4.4 if tier != 2 else -2.6)]
    if tier == 2:  # a W of a trailing edge: notched back to the tail
        outline = [(0.0, nose), (span, -3.0), (span * 0.9, -3.8), (span * 0.55, -1.9), (span * 0.3, -3.9), (0.0, -2.6)]
    plate(right, outline, 0.0, 0.26, bevel=0.3)
    edge(right, (0.4, -0.05, nose - 0.8), (span - 0.2, -0.05, -2.55), 0.08, 0.1, face=(1, 0, 1))
    edge(right, (0.6, 0.3, nose - 1.6), (span * 0.6, 0.25, -0.2), 0.05, 0.05, face=(0, 1, 0))
    # The blended body over it, the cockpit's dark glass.
    loft(body, [(-4.2, 0.15, 1.2, 0.35), (-1.6, 0.35, 1.8, 0.75), (1.6, 0.35, 1.5, 0.75), (4.2, 0.2, 0.7, 0.45), (nose, 0.0, 0.0, 0.0)], PLATE, shape=FLAT)
    loft(body, [(1.6, 0.85, 0.0, 0.0), (2.5, 0.95, 0.5, 0.25), (3.8, 0.7, 0.35, 0.2), (4.4, 0.5, 0.0, 0.0)], GLASS)
    for x in (0.7, 1.3):  # buried engines: lit slots at the tail
        right.box((0.5, 0.18, 0.06), (x, 0.25, -4.15 if tier != 2 else -2.55), LIT, SIDE_GLOW)
    if tier == 2:  # open bomb bays, two bombs in each
        for x in (1.0, 1.6):
            body_bombs = right
            body_bombs.box((1.4, 0.3, 2.6), (2.6, -0.3, -0.2), RECESS)
            body_bombs.lathe((x + 1.3, -0.45, -1.2), (0, 0, 1), [(0, 0.22), (1.6, 0.22), (2.1, 0.0)], RAISED, sides=6)
        edge(right, (1.9, -0.2, 1.1), (3.3, -0.2, 1.1), 0.04, 0.04, face=(0, -1, 0))
    if tier == 3:  # lit exhausts under the leading edge, gun turrets on the back
        for i in range(4):
            x = 2.2 + i * 1.3
            z = nose - 1.2 - x * (nose + 2.6) / span * 0.95
            right.box((1.0, 0.35, 0.5), (x, -0.4, z - 0.3), PLATE)
            right.box((0.8, 0.22, 0.05), (x, -0.4, z - 0.04), LIT, SIDE_GLOW)
        for z in (0.6, -2.0):
            body.lathe((0.0, 0.95 if z > 0 else 0.75, z), (0, 1, 0), [(0, 0.55), (0.4, 0.45)], RAISED, sides=6)
            for sx in (-0.14, 0.14):
                gun(body, (sx, 1.2 if z > 0 else 1.0, z + 0.2), 1.3, 0.06)
    hexagon(body, (0, 1.0, -0.6), 0.4, (0, 1, 0), RAISED, PLAIN)
    body.mirrored(right)
    k = SIZE[tier]
    fly = 10.0
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -0.5 * k, 0.0), "views": air_views(fly, 1.5 * k), "fly": fly, "span": 4.0 * k}


def build(Part):
    return make(Part, 1)
