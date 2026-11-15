"""The Luminar Accord's line infantry (Rev 2): one soldier in angular, faceted ceramic plate
trimmed in brass, a faceted helmet with a lit slit visor, a lit gem in the chest, angular shoulder
plates with the braided-knot lozenge, a straight-cut tabard, and a long beam rifle held across the
body. The game draws a squad as several of these.

About 2.3 m tall (drawn a little over life size so they read from the battle's camera).
"""

from units.accord_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    right.slab(0.55, (0.04, 0.27, -0.13, 0.15), 1.1, (0.05, 0.3, -0.15, 0.16), CERAMIC)  # thigh
    right.slab(0.1, (0.06, 0.26, -0.12, 0.13), 0.55, (0.05, 0.28, -0.13, 0.17), CERAMIC)  # shin
    right.box((0.24, 0.14, 0.42), (0.16, 0.07, 0.06), OLD)  # boot
    right.slab(0.5, (0.08, 0.26, 0.1, 0.2), 0.68, (0.1, 0.24, 0.12, 0.2), BRASS)  # knee plate
    body.box((0.5, 0.26, 0.3), (0, 1.15, 0), WORKS)  # hips
    body.slab(1.25, (-0.27, 0.27, -0.16, 0.16), 1.6, (-0.36, 0.36, -0.2, 0.24), CERAMIC)  # chest
    body.slab(1.6, (-0.36, 0.36, -0.2, 0.24), 1.86, (-0.24, 0.24, -0.16, 0.14), CERAMIC)
    body.box((0.1, 0.12, 0.04), (0, 1.55, 0.255), LIT, SIDE_GLOW)  # the gem in the chest
    body.box((0.16, 0.18, 0.03), (0, 1.55, 0.245), BRASS)
    # The tabard, straight-cut, front and back, brass at its hem.
    body.slab(0.55, (-0.17, 0.17, 0.17, 0.2), 1.2, (-0.15, 0.15, 0.15, 0.19), CERAMIC)
    body.box((0.34, 0.05, 0.05), (0, 0.56, 0.2), BRASS)
    body.slab(0.6, (-0.2, 0.2, -0.2, -0.17), 1.2, (-0.17, 0.17, -0.18, -0.15), CERAMIC)
    # The helmet: faceted, a lit slit visor.
    body.slab(1.88, (-0.15, 0.15, -0.16, 0.16), 2.08, (-0.17, 0.17, -0.17, 0.2), CERAMIC)
    body.slab(2.08, (-0.17, 0.17, -0.17, 0.2), 2.26, (-0.1, 0.1, -0.12, 0.1), CERAMIC)
    body.box((0.2, 0.04, 0.03), (0, 2.08, 0.205), LIT, SIDE_GLOW)
    body.box((0.03, 0.18, 0.03), (0, 2.0, 0.2), LIT, SIDE_GLOW)
    body.box((0.04, 0.09, 0.3), (0, 2.26, 0.0), BRASS)  # the crest ridge
    # Angular shoulder plates, the lozenge on the left; arms forward to the rifle.
    right.slab(1.6, (0.3, 0.56, -0.18, 0.18), 1.82, (0.32, 0.48, -0.14, 0.14), CERAMIC)
    body.slab(1.6, (-0.56, -0.3, -0.18, 0.18), 1.82, (-0.48, -0.32, -0.14, 0.14), CERAMIC)
    right.box((0.28, 0.04, 0.38), (0.43, 1.6, 0.0), BRASS)
    body.box((0.28, 0.04, 0.38), (-0.43, 1.6, 0.0), BRASS)
    lozenge(body, (-0.565, 1.69, 0.0), (-1, 0, 0), 0.07)
    right.box((0.13, 0.36, 0.14), (0.42, 1.4, 0.08), CERAMIC, PLAIN, (-30, 0, 0))
    right.box((0.12, 0.13, 0.36), (0.32, 1.26, 0.32), CERAMIC)
    body.box((0.13, 0.36, 0.14), (-0.42, 1.4, 0.1), CERAMIC, PLAIN, (-45, 0, 0))
    body.box((0.12, 0.13, 0.4), (-0.22, 1.3, 0.42), CERAMIC)
    # The long beam rifle: white, a lit line down it, a lit muzzle.
    body.box((0.1, 0.16, 1.0), (0.18, 1.3, 0.6), CERAMIC)
    body.box((0.06, 0.07, 0.55), (0.18, 1.32, 1.35), GUN)
    body.box((0.04, 0.04, 0.6), (0.235, 1.33, 0.65), LIT, SIDE_GLOW)
    body.box((0.11, 0.05, 0.3), (0.18, 1.4, 0.4), BRASS)
    body.box((0.07, 0.08, 0.03), (0.18, 1.32, 1.63), LIT, SIDE_GLOW)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.18, 1.32, 1.66), "view": 0.45}
