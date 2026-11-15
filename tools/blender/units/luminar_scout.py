"""The Luminar Accord's tier 1 stealth scout: a small four-legged walker. A smooth teardrop of a
shell, blunt at the front where one big lit eye looks out of a brass ring, thinning to a tail; a
mushroom of a sensor on a stalk on its back, a brass aerial behind, and four thin bent legs.
Its light is the side's colour.

About 2.6 m wide across the legs and 5 m long (the server's scout is 3 m in radius).
"""

import math

from units.luminar_kit import *  # noqa: F401,F403

AT = (0.0, 1.75, -0.2)
R = (0.95, 0.72, 2.5)


def build(Part):
    body, right = Part(), Part()
    shell(body, AT, R, CERAMIC, PLAIN, "z", -1.0, 0.86, sides=14, stacks=9)
    shell(body, AT, R, BRASS, PLAIN, "z", 0.28, 0.33, sides=14, stacks=1, grow=0.03)  # a brass band behind the head
    shell(body, AT, R, BRASS, PLAIN, "z", 0.8, 0.86, sides=14, stacks=1, grow=0.03)  # the eye's ring
    face = AT[2] + R[2] * 0.86
    body.lathe((0, AT[1], face), (0, 0, 1), [(0, 0.44), (0.06, 0.36)], GLASS, sides=12)
    body.lathe((0, AT[1], face + 0.06), (0, 0, 1), [(0, 0.2), (0.05, 0.14)], LIT, SIDE_GLOW, sides=10)
    shell(body, (0, 1.42, -0.2), (0.6, 0.4, 1.7), WORKS, PLAIN, "z", stacks=4, sides=10)  # the works under the shell
    # The sensor on its stalk, and an aerial.
    body.lathe((0, 2.4, -0.3), (0, 1, 0), [(0, 0.16), (0.1, 0.1), (0.5, 0.08)], BRASS, sides=8)
    shell(body, (0, 3.0, -0.3), (0.5, 0.2, 0.5), CERAMIC, PLAIN, "y", stacks=3, sides=12)
    shell(body, (0, 3.0, -0.3), (0.5, 0.2, 0.5), BRASS, PLAIN, "y", -0.5, -0.2, stacks=1, sides=12, grow=0.02)
    body.box((0.04, 0.9, 0.04), (0.3, 2.75, -1.3), BRASS)
    hoop(body, (0.3, 3.3, -1.3), (0, 0, 1), 0.13, 0.03, sides=8)
    # Legs: a shoulder under the shell, an upper leg out and down, a lower leg to a small foot.
    for z, lean in ((1.0, 0.45), (-1.5, -0.35)):
        hip, knee, foot = (0.75, 1.5, z), (1.15, 0.95, z - lean), (1.25, 0.08, z + lean * 0.6)
        right.lathe((0.5, 1.5, z), (1, 0, 0), [(0, 0.3), (0.42, 0.3)], CERAMIC, sides=8)
        right.beam(hip, knee, 0.26, 0.3, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.2, deep1=0.24)
        right.lathe((1.0, 0.95, z - lean), (1, 0, 0), [(0, 0.17), (0.32, 0.17)], BRASS, sides=8)
        right.beam(knee, foot, 0.18, 0.2, CERAMIC, PLAIN, face=(1, 0, 0), wide1=0.1, deep1=0.12)
        right.box((0.2, 0.08, 0.36), (1.25, 0.04, z + lean * 0.6 + 0.08), BRASS)
    right.box((0.04, 0.06, 1.6), (0.93, 1.72, -0.2), LIT, SIDE_GLOW)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, AT[1], face + 0.12), "view": 0.6}
