"""The Luminar Accord's tier 1 assault walker: a light two-legged walker. Its torso is one long egg
of a shell tipped nose-down like a helm, a tall lit arch of a visor in its brow and a chest plate
with a brass ring under it; a narrow dark waist over a hip pod; a long shield of a pad hung at each
shoulder with a lance rifle below it, held low and pointing ahead; and two bent legs on brass joints. No turret: it faces what it
shoots. Its light is the side's colour.

About 4.4 m tall and 4.6 m across the shoulders (the server's striker is 3 m in radius).
"""

import math

from units.luminar_kit import *  # noqa: F401,F403

HEAD = (0.0, 3.6, 0.1)


def build(Part):
    body, right = Part(), Part()
    # The torso: one long egg of a shell, its nose tipped down like a helm, taller at the back.
    # Built level round HEAD, then tipped.
    head, half = Part(), Part()
    r = (1.05, 1.0, 1.38)
    shell(head, HEAD, r, CERAMIC, PLAIN, "z", -1.0, 0.8, sides=16, stacks=9)  # cut flat across the front: its face
    shell(head, HEAD, r, BRASS, PLAIN, "z", 0.72, 0.8, sides=16, stacks=1, grow=0.035)  # the brass edge of its face
    shell(head, HEAD, r, BRASS, PLAIN, "y", -0.42, -0.36, sides=18, stacks=1, grow=0.03)  # a brass line along the jaw
    shell(head, HEAD, r, SHADE, PLAIN, "z", -1.0, -0.72, sides=16, stacks=2, grow=0.02)  # a darker cap at the back
    for arc in ((0.03, 0.2), (0.3, 0.47)):  # light along each side of the crown, behind the face
        shell(head, HEAD, r, LIT, SIDE_GLOW, "y", 0.5, 0.56, sides=20, stacks=1, grow=0.025, arc=arc)
    # The visor: a tall arch of dark glass set in the brow, lit round its edge.
    fz = HEAD[2] + r[2] * 0.8 + 0.02
    vy = HEAD[1] + 0.02
    head.box((0.5, 0.42, 0.14), (0, vy - 0.1, fz), GLASS)
    head.lathe((0, vy + 0.11, fz - 0.07), (0, 0, 1), [(0, 0.25), (0.14, 0.25)], GLASS, sides=12)
    arch = [(0.3, vy - 0.32, fz + 0.06)] + [(0.3 * math.cos(t), vy + 0.11 + 0.3 * math.sin(t), fz + 0.06) for t in [math.radians(d) for d in range(0, 181, 30)]] + [(-0.3, vy - 0.32, fz + 0.06)]
    head.trace(arch, 0.09, 0.07, LIT, SIDE_GLOW, face=(0, 0, 1))
    head.box((0.1, 0.3, 0.05), (0, vy - 0.05, fz + 0.08), LIT, SIDE_GLOW)
    # The chest under it: a plate standing proud of the shell, a brass ring in its middle.
    shell(head, (0, HEAD[1] - 0.78, HEAD[2] + 0.5), (0.7, 0.45, 0.8), CERAMIC, PLAIN, "z", -0.2, 0.85, sides=12, stacks=4)
    hoop(head, (0, HEAD[1] - 0.78, HEAD[2] + 1.2), (0, 0, 1), 0.2, 0.07)
    head.lathe((0, HEAD[1] - 0.78, HEAD[2] + 1.17), (0, 0, 1), [(0, 0.14), (0.04, 0.14)], OLD, sides=10)
    # A shoulder: a dark joint out of the shell's side, and a long pad hung from it like a shield.
    half.lathe((0.85, HEAD[1] + 0.2, HEAD[2] - 0.35), (1, 0, 0), [(0, 0.36), (0.75, 0.3)], WORKS, sides=10)
    half.lathe((1.5, HEAD[1] + 0.2, HEAD[2] - 0.35), (1, 0, 0), [(0, 0.38), (0.12, 0.38)], BRASS, sides=10)
    shell(half, (1.9, HEAD[1] - 0.12, HEAD[2] - 0.35), (0.42, 0.85, 0.62), CERAMIC, PLAIN, "y", sides=12, stacks=6)
    shell(half, (1.9, HEAD[1] - 0.12, HEAD[2] - 0.35), (0.42, 0.85, 0.62), BRASS, PLAIN, "y", 0.3, 0.38, sides=12, stacks=1, grow=0.025)
    head.mirrored(half)
    tipped(body, head, HEAD, 16)
    # The waist, dark and narrow, and the hips: a pod with a joint out either side.
    body.lathe((0, 2.85, -0.1), (0, -1, 0), [(0, 0.5), (0.2, 0.36), (0.5, 0.36)], WORKS, sides=10)
    body.lathe((0, 2.62, -0.1), (0, -1, 0), [(0, 0.42), (0.07, 0.42)], BRASS, sides=10)
    shell(body, (0, 2.08, -0.05), (0.78, 0.46, 0.7), CERAMIC, PLAIN, "y", stacks=4, sides=12)
    shell(body, (0, 2.08, -0.05), (0.78, 0.46, 0.7), BRASS, PLAIN, "y", -0.1, 0.02, stacks=1, sides=12, grow=0.025)
    body.lathe((-1.0, 2.1, -0.05), (1, 0, 0), [(0, 0.3), (2.0, 0.3)], WORKS, sides=10)
    # A leg: thigh forward and down, shin back and down, a long foot.
    hip, knee, ankle = (1.15, 2.1, -0.05), (1.15, 1.35, 0.75), (1.15, 0.45, -0.25)
    right.lathe((0.95, 2.1, -0.05), (1, 0, 0), [(0, 0.4), (0.45, 0.4)], BRASS, sides=10)
    right.beam(hip, knee, 0.46, 0.5, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.36, deep1=0.44)
    right.lathe((0.9, 1.35, 0.75), (1, 0, 0), [(0, 0.3), (0.5, 0.3)], BRASS, sides=10)
    right.beam(knee, ankle, 0.34, 0.4, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.24, deep1=0.3)
    right.beam((1.37, 1.2, 0.6), (1.37, 0.6, -0.1), 0.08, 0.04, LIT, SIDE_GLOW, face=(1, 0, 0))
    right.lathe((0.95, 0.45, -0.25), (1, 0, 0), [(0, 0.22), (0.4, 0.22)], BRASS, sides=8)
    right.extrude([(-0.7, 0.0), (0.95, 0.0), (0.95, 0.14), (-0.1, 0.5), (-0.5, 0.5)], 0.9, 1.4, CERAMIC)
    right.box((0.54, 0.08, 0.3), (1.15, 0.04, 0.95), BRASS)
    # The arm down from the shoulder pad, and the lance rifle: long, hung low, pointing ahead.
    right.beam((1.9, 2.95, -0.1), (1.9, 2.2, 0.35), 0.32, 0.38, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.28, deep1=0.32)
    right.lathe((1.65, 2.2, 0.35), (1, 0, 0), [(0, 0.26), (0.5, 0.26)], BRASS, sides=8)
    at, d = (1.9, 2.1, 0.2), (0.0, -0.12, 1.0)
    right.box((0.42, 0.5, 1.5), (1.9, 2.05, 0.75), CERAMIC, PLAIN, (7, 0, 0))
    barrel(right, at, d, [(1.4, 3.5, 0.11)])
    barrel(right, at, d, [(1.4, 1.6, 0.17), (3.5, 3.8, 0.15)], BRASS)
    right.box((0.05, 0.06, 1.3), (2.12, 2.02, 0.8), LIT, SIDE_GLOW, (7, 0, 0))
    n = math.hypot(d[1], d[2])
    tip = (at[0], at[1] + d[1] / n * 3.82, at[2] + d[2] / n * 3.82)
    right.lathe(tip, d, [(0, 0.09), (0.03, 0.09)], LIT, SIDE_GLOW, sides=8)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, tip[1], tip[2]), "view": 0.72}
