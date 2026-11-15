"""The Terran Compact's tier 1 engineer, the construction crawler: a tracked box of a hull with a
cab at the front, a dozer blade ahead of it, and a hydraulic crane on the deck reaching back over
the tail. The side's colour is painted on as chevrons along the hull, the Compact's mark, and twin
stripes on the roof and the crane.

About 4.2 m wide at the blade and 7 m long without the crane's reach (the server's engineer is 3 m in radius).
"""

import math

from units.compact_kit import *  # noqa: F401,F403

BEACON = Color(1.0, 0.6, 0.1)


def build(Part):
    body, right = Part(), Part()
    gear(right, [(-3.0, 0.0), (2.3, 0.0), (3.0, 0.5), (3.0, 0.8), (2.6, 1.1), (-3.2, 1.1), (-3.6, 0.8), (-3.6, 0.5)], 1.15, 1.85, (-2.7, -1.8, -0.9, 0.0, 0.9, 1.8), 0.36)
    body.extrude([(-3.5, 0.55), (2.9, 0.55), (3.1, 1.1), (-3.5, 1.1)], -1.15, 1.15, DARK)
    # The hull over the tracks: a deck behind, the cab standing up at the front with a sloped face.
    hull = [(-3.6, 1.1), (3.2, 1.1), (3.2, 1.9), (2.6, 2.95), (1.0, 2.95), (0.8, 2.45), (-3.6, 2.45)]
    body.extrude(hull, -1.72, 1.72, STEEL)
    for x in (-0.8, 0.8):  # the windscreen, in two panes
        body.prism([(x - 0.62, 2.05, 3.13), (x + 0.62, 2.05, 3.13), (x + 0.62, 2.8, 2.7), (x - 0.62, 2.8, 2.7)], (0, 0.03, 0.05), GLASS)
    right.box((0.06, 0.6, 1.0), (1.72, 2.5, 1.9), GLASS)
    right.box((0.08, 1.1, 0.06), (1.72, 1.9, 1.2), DARK)  # the door's seam
    emblem(right, 1.73, -0.3, 1.8, 0.34)
    for z in (-1.5, -2.2, -2.9):  # chevrons pointing the way it drives
        right.line([(z - 0.38, 2.25), (z + 0.1, 1.78), (z - 0.38, 1.31)], 1.73, STRIPE, PAINT, wide=0.15, proud=0.05)
    stripes(right, 1.73, 2.6, 1.2, 1.95, wide=0.13, gap=0.1)
    top_stripes(body, 0.0, 2.96, 1.1, 2.5, wide=0.2, gap=0.16)
    right.box((0.5, 0.2, 2.0), (1.35, 2.55, -2.3), LIGHT)  # tool lockers along the deck's edge
    right.box((0.5, 0.2, 1.2), (1.35, 2.55, -0.4), OLIVE)
    right.box((0.3, 0.16, 0.08), (1.2, 1.55, 3.22), LAMP, GLOW)
    right.box((0.25, 0.1, 0.06), (1.3, 2.2, -3.62), TAIL, GLOW)
    right.box((0.2, 0.14, 0.2), (1.2, 3.02, 1.4), BEACON, GLOW)
    # The dozer blade: curved, on two arms.
    blade = [(3.75, 0.12), (4.05, 0.15), (3.95, 0.8), (4.2, 1.5), (4.05, 1.55), (3.7, 0.8)]
    body.extrude(blade, -2.1, 2.1, LIGHT)
    body.box((4.2, 0.1, 0.1), (0, 0.17, 4.07), DARK)  # its cutting edge
    right.beam((1.0, 1.0, 3.0), (1.0, 0.65, 3.8), 0.2, 0.22, DARK, PLAIN, face=(1, 0, 0))
    right.beam((2.0, 0.9, 2.4), (2.0, 0.6, 3.8), 0.14, 0.14, DARK, PLAIN, face=(1, 0, 0))
    # Prefab panels racked on the deck.
    for k in range(3):
        body.box((0.1, 1.0, 1.7), (-0.75 - 0.16 * k, 3.0, 0.0), LIGHT, PLAIN, (0, 0, 8))
    # The crane: a turntable, a column, a boom up and back, a jib down from its end, a hook.
    body.lathe((0.2, 2.45, -1.6), (0, 1, 0), [(0, 0.62), (0.22, 0.55)], DARK, sides=10)
    body.box((0.55, 1.5, 0.6), (0.2, 3.4, -1.6), STEEL)
    body.beam((0.2, 4.0, -1.5), (0.2, 5.6, -3.7), 0.5, 0.42, STEEL, PLAIN, face=(1, 0, 0), wide1=0.36, deep1=0.32)
    body.beam((0.2, 5.6, -3.7), (0.2, 4.7, -5.3), 0.34, 0.3, DARK, PLAIN, face=(1, 0, 0), wide1=0.22, deep1=0.2)
    body.beam((0.2, 2.9, -2.1), (0.2, 4.75, -2.75), 0.16, 0.16, LIGHT, PLAIN, face=(1, 0, 0))  # the ram that lifts it
    body.beam((0.2, 4.9, -2.85), (0.2, 5.25, -4.3), 0.12, 0.12, LIGHT, PLAIN, face=(1, 0, 0))
    for x in (-0.02, 0.42):  # the side's colour banded on the boom
        for t in (0.35, 0.5):
            body.box((0.03, 0.5, 0.16), (x, 4.0 + 1.6 * t, -1.5 - 2.2 * t), STRIPE, PAINT, (-54, 0, 0))
    body.box((0.04, 1.2, 0.04), (0.2, 4.1, -5.3), DARK)  # the cable
    body.box((0.22, 0.3, 0.22), (0.2, 3.4, -5.3), LIGHT)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.2, 3.3, -5.3), "view": 0.9}
