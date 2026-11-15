"""The Ashen Collective's line infantry: one soldier in black faceted plate, a helmet with a lit
visor slit, the side's emblem on the shoulder, a coil rifle held ready. The game draws a squad as
several of these.

About 2.3 m tall (drawn a little over life size so they read from the battle's camera).
"""

from units.ashen_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    right.box((0.24, 0.55, 0.28), (0.15, 0.82, 0.02), PLATE)  # thigh
    right.box((0.22, 0.55, 0.26), (0.16, 0.3, -0.02), PLATE)  # shin
    right.box((0.24, 0.14, 0.42), (0.16, 0.07, 0.06), RECESS)  # boot
    right.box((0.26, 0.2, 0.2), (0.16, 0.6, 0.08), RAISED)  # knee plate
    body.box((0.52, 0.3, 0.32), (0, 1.15, 0), RECESS)  # hips
    body.slab(1.25, (-0.28, 0.28, -0.17, 0.17), 1.75, (-0.36, 0.36, -0.2, 0.22), PLATE)  # chest
    body.slab(1.75, (-0.36, 0.36, -0.2, 0.22), 1.85, (-0.26, 0.26, -0.16, 0.16), PLATE)
    body.box((0.32, 0.2, 0.12), (0, 1.6, 0.22), RAISED)
    body.box((0.4, 0.42, 0.22), (0, 1.5, -0.3), RECESS)  # pack
    # The helmet, its visor slit lit.
    body.slab(1.88, (-0.16, 0.16, -0.16, 0.18), 2.18, (-0.14, 0.14, -0.15, 0.14), PLATE)
    body.slab(2.18, (-0.14, 0.14, -0.15, 0.14), 2.26, (-0.08, 0.08, -0.1, 0.08), PLATE)
    body.box((0.24, 0.04, 0.03), (0, 2.06, 0.19), LIT, SIDE_GLOW)
    # Shoulders, the emblem on the left; arms forward to the rifle.
    right.box((0.24, 0.22, 0.3), (0.42, 1.68, 0.0), RAISED)
    body.box((0.24, 0.22, 0.3), (-0.42, 1.68, 0.0), RAISED)
    hexagon(body, (-0.55, 1.68, 0.0), 0.07, (-1, 0, 0))
    right.box((0.13, 0.36, 0.14), (0.42, 1.42, 0.08), PLATE, PLAIN, (-30, 0, 0))
    right.box((0.12, 0.13, 0.36), (0.32, 1.28, 0.32), PLATE)
    body.box((0.13, 0.36, 0.14), (-0.42, 1.42, 0.1), PLATE, PLAIN, (-45, 0, 0))
    body.box((0.12, 0.13, 0.4), (-0.22, 1.32, 0.42), PLATE)
    # The coil rifle.
    body.box((0.1, 0.16, 0.9), (0.18, 1.32, 0.55), RECESS)
    body.box((0.06, 0.06, 0.5), (0.18, 1.32, 1.15), PLATE)
    body.box((0.04, 0.03, 0.4), (0.24, 1.36, 0.6), LIT, SIDE_GLOW)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.18, 1.32, 1.42), "view": 0.45}
