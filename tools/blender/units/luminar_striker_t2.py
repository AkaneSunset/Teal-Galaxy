"""The Luminar Accord's Litany assault walker, Mk II and Mk III (Rev 2): an autonomous two-legged
walker. Its torso and head are one faceted gem of a hex-prism shell, a tall coffin-shaped visor lit
round its edge in its face and a brass faceted crest on its crown; angular shoulder blocks, arms
hung down to a long lance rifle on each side with an underslung second barrel, a faceted hip pod
and two bent legs on brass joints. Mk III carries triple-barrel lances, a missile pod on each
shoulder and blade fins on its back. Its light is the side's colour.

About 4.6 m tall at Mk II, 5 m at Mk III (the server's striker is 3 m in radius).
"""

import math

from units.accord_kit import *  # noqa: F401,F403

C = (0.0, 2.95, 0.0)  # the foot of the torso


def make(Part, tier):
    body, right = Part(), Part()
    x, y, z = C
    # The torso: a faceted gem, its face to the front.
    steps = [(0, 0.5), (0.35, 0.9), (1.25, 1.05), (1.85, 0.8), (2.15, 0.35)]
    body.lathe(C, (0, 1, 0), steps, CERAMIC, PLAIN, 8, math.pi / 8, squash=0.92)
    body.lathe((x, y + 0.33, z), (0, 1, 0), [(0, 0.92), (0.07, 0.92)], BRASS, PLAIN, 8, math.pi / 8, squash=0.94)
    body.lathe((x, y + 1.82, z), (0, 1, 0), [(0, 0.83), (0.07, 0.8)], BRASS, PLAIN, 8, math.pi / 8, squash=0.94)
    pyramid(body, (x, y + 2.13, z), 0.38, 0.2, BRASS, sides=6, ribs=False)  # the crest
    if tier >= 3:
        body.box((0.08, 0.45, 0.35), (0, y + 2.4, -0.1), CERAMIC)
    # The visor: a coffin-shaped lens, lit round its edge.
    fz = 0.98
    coffin = [(0, -0.55), (0.18, -0.38), (0.22, 0.3), (0.12, 0.55), (-0.12, 0.55), (-0.22, 0.3), (-0.18, -0.38)]
    body.prism([(px * 1.25, y + 1.0 + py, fz) for px, py in coffin], (0, 0, 0.05), LIT, SIDE_GLOW)
    body.prism([(px * 0.85, y + 1.0 + py * 0.8, fz + 0.04) for px, py in coffin], (0, 0, 0.04), GLASS)
    body.box((0.5, 0.08, 0.05), (0, y + 0.2, 0.86), LIT, SIDE_GLOW)
    right.box((0.05, 0.4, 0.07), (0.72, y + 1.1, 0.6), LIT, SIDE_GLOW, (0, 40, 0))
    # Shoulders: angular blocks on dark joints.
    right.lathe((0.75, y + 1.35, -0.1), (1, 0, 0), [(0, 0.32), (0.5, 0.28)], WORKS, PLAIN, 8)
    right.slab(y + 0.85, (1.15, 1.85, -0.55, 0.45), y + 1.75, (1.2, 1.75, -0.45, 0.35), CERAMIC)
    right.slab(y + 1.75, (1.2, 1.75, -0.45, 0.35), y + 1.95, (1.3, 1.6, -0.3, 0.2), CERAMIC)
    right.box((0.72, 0.06, 1.02), (1.5, y + 1.25, -0.05), BRASS)
    # The arm down to the lance rifle, hung low, pointing ahead and down.
    right.beam((1.5, y + 0.9, -0.05), (1.5, y - 0.35, 0.25), 0.32, 0.36, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.28, deep1=0.3)
    right.lathe((1.3, y - 0.35, 0.25), (1, 0, 0), [(0, 0.24), (0.4, 0.24)], BRASS, PLAIN, 8)
    d = (0.0, -0.3, 1.0)
    dn = (0.0, -0.3 / math.hypot(0.3, 1.0), 1.0 / math.hypot(0.3, 1.0))
    at = (1.5, y - 0.45, 0.1)
    obox(right, (1.5, at[1] + dn[1] * 1.4, at[2] + dn[2] * 1.4), d, (0.36, 0.42, 3.0), CERAMIC)
    obox(right, (1.69, at[1] + dn[1] * 1.4 + 0.05, at[2] + dn[2] * 1.4), d, (0.04, 0.08, 2.3), LIT, SIDE_GLOW)
    obox(right, (1.5, at[1] + dn[1] * 1.4 + 0.23, at[2] + dn[2] * 1.4), d, (0.4, 0.06, 2.4), BRASS)
    barrels = [(0.0, 0.0), (0.0, -0.26)] if tier < 3 else [(-0.1, 0.0), (0.1, 0.0), (0.0, -0.26)]
    for bx, by in barrels:
        tip = hexgun(right, (1.5 + bx, at[1] + dn[1] * 2.8 + by, at[2] + dn[2] * 2.8), dn, 0.9, 0.08, collar=False)
    if tier >= 3:  # missile pods on the shoulders, blade fins on the back
        launcher(right, (1.5, y + 2.25, -0.1), (0, 0.3, 1), 3, 2, 0.17, 0.75)
        fin(right, (0.5, y + 1.6, -0.75), (1.4, y + 2.8, -1.5), 0.9, 0.3, 0.08)
    # The hips: a faceted pod, a joint across.
    body.lathe((0, y + 0.05, -0.05), (0, -1, 0), [(0, 0.45), (0.25, 0.36)], WORKS, PLAIN, 8)
    body.lathe((0, y - 0.2, -0.05), (0, -1, 0), [(0, 0.72), (0.3, 0.8), (0.55, 0.5)], CERAMIC, PLAIN, 8, math.pi / 8)
    body.lathe((-1.0, y - 0.48, -0.05), (1, 0, 0), [(0, 0.26), (2.0, 0.26)], WORKS, PLAIN, 8)
    # A leg: thigh forward and down, shin back and down, a faceted foot.
    hip, knee, ankle = (0.95, y - 0.48, -0.05), (0.95, 1.4, 0.8), (0.95, 0.45, -0.25)
    right.lathe((0.75, hip[1], hip[2]), (1, 0, 0), [(0, 0.36), (0.42, 0.36)], BRASS, PLAIN, 8)
    right.beam(hip, knee, 0.44, 0.5, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.34, deep1=0.42)
    right.lathe((0.7, 1.4, 0.8), (1, 0, 0), [(0, 0.28), (0.5, 0.28)], BRASS, PLAIN, 8)
    right.beam(knee, ankle, 0.34, 0.4, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.26, deep1=0.3)
    right.beam((1.15, 1.2, 0.6), (1.15, 0.6, -0.1), 0.07, 0.04, LIT, SIDE_GLOW, face=(1, 0, 0))
    right.lathe((0.75, 0.45, -0.25), (1, 0, 0), [(0, 0.2), (0.4, 0.2)], BRASS, PLAIN, 8)
    right.extrude([(-0.7, 0.0), (0.95, 0.0), (0.95, 0.14), (0.3, 0.4), (-0.1, 0.5), (-0.5, 0.42)], 0.7, 1.2, CERAMIC)
    right.box((0.54, 0.08, 0.26), (0.95, 0.04, 0.95), BRASS)
    body.mirrored(right)
    k = 1.0 if tier == 2 else 1.1
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, tip[1] * k, tip[2] * k), "view": 0.92 * k}


def build(Part):
    return make(Part, 2)
