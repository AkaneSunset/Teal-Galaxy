"""The Terran Compact's conscripts: one rifleman, drawn a little over life size so he reads from
the battle's camera. Grey fatigues, a steel helmet, a pack, and the side's colour on the pack and an
armband. The game draws a squad as five of these, each finding its own place (battle_units.gd).

He stands about 2.3 m.
"""

import math

from units.compact_kit import *  # noqa: F401,F403

CLOTH = Color(0.3, 0.31, 0.3)
BOOT = Color(0.09, 0.09, 0.09)
SKIN = Color(0.62, 0.47, 0.38)
PLACES = [(0.0, 0.0, 0.12)]  # (x, z, a lean in the stride)


def _soldier(P, x, z, stride):
    s = 0.34 * (1 if stride >= 0 else -1)
    for side in (-1, 1):
        dz = s * side
        P.box((0.26, 1.0, 0.3), (x + 0.17 * side, 0.55, z + dz * 0.5), CLOTH, PLAIN, (-18 * side * (1 if s > 0 else -1), 0, 0))
        P.box((0.28, 0.2, 0.44), (x + 0.17 * side, 0.1, z + dz + 0.05), BOOT)
    P.box((0.66, 0.8, 0.4), (x, 1.42, z), CLOTH)
    P.box((0.7, 0.36, 0.44), (x, 1.42, z), OLIVE)  # webbing
    P.box((0.5, 0.6, 0.26), (x, 1.5, z - 0.32), OLIVE)  # the pack
    P.box((0.3, 0.3, 0.04), (x, 1.55, z - 0.46), STRIPE, PAINT)
    P.box((0.52, 0.04, 0.2), (x, 1.81, z - 0.32), STRIPE, PAINT)  # the side's colour, for the camera overhead
    P.box((0.3, 0.3, 0.3), (x, 1.98, z + 0.02), SKIN)
    P.lathe((x, 2.02, z), (0, 1, 0), [(0, 0.27), (0.14, 0.25), (0.26, 0.14)], STEEL, sides=8)
    P.box((0.2, 0.62, 0.24), (x - 0.43, 1.45, z + 0.12), CLOTH, PLAIN, (-35, 0, 0))
    P.box((0.2, 0.62, 0.24), (x + 0.43, 1.45, z + 0.16), CLOTH, PLAIN, (-50, 0, 0))
    P.box((0.22, 0.16, 0.26), (x - 0.44, 1.62, z + 0.0), STRIPE, PAINT)  # an armband
    P.box((0.1, 0.16, 1.15), (x + 0.2, 1.38, z + 0.55), DARK, PLAIN, (-6, 14, 0))  # the rifle
    P.box((0.12, 0.24, 0.14), (x + 0.22, 1.24, z + 0.5), DARK)


def build(Part):
    body = Part()
    for x, z, stride in PLACES:
        _soldier(body, x, z, stride)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.25, 1.4, 1.15), "view": 0.5}
