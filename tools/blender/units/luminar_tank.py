"""The Luminar Accord's tier 1 light tank: a hover skimmer. A long smooth shell like a river stone,
ribbed in brass, riding on a line of light over dark works; a low lens of a turret with one beam
gun and a small cupola. Its light is the side's colour.

About 5.4 m wide and 7.4 m long (the server's tank is 4 m in radius).
"""

import math

from units.luminar_kit import *  # noqa: F401,F403

AT = (0.0, 1.35, 0.0)
R = (2.7, 0.95, 3.7)
TOP_AT = (0.0, 2.05, -0.5)


def build(Part):
    body = Part()
    shell(body, AT, R, CERAMIC, PLAIN, "z", sides=18, stacks=10)
    for lo, hi in ((0.52, 0.56), (-0.1, -0.06), (-0.62, -0.58)):  # brass ribs round it
        shell(body, AT, R, BRASS, PLAIN, "z", lo, hi, sides=18, stacks=1, grow=0.035)
    shell(body, AT, R, BRASS, PLAIN, "z", 0.95, 1.0, sides=18, stacks=2, grow=0.03)  # a brass prow
    shell(body, AT, R, BRASS, PLAIN, "y", -0.34, -0.26, sides=20, stacks=1, grow=0.04)  # a brass rail above the skirt
    shell(body, AT, R, LIT, SIDE_GLOW, "y", 0.2, 0.25, sides=20, stacks=1, grow=0.02, arc=(0.08, 0.42))  # light along each flank
    shell(body, AT, R, LIT, SIDE_GLOW, "y", 0.2, 0.25, sides=20, stacks=1, grow=0.02, arc=(0.58, 0.92))
    hover(body, AT, R)
    for x in (-1.0, 0.0, 1.0):  # lamps across the tail
        body.box((0.5, 0.12, 0.08), (x, 1.3, -3.6 + abs(x) * 0.14), LIT, SIDE_GLOW)
    shell(body, (0, 1.95, -0.5), (1.75, 0.3, 2.1), SHADE, PLAIN, "y", -0.2, 1.0, stacks=2)  # the turret's seat

    top = Part()  # the turret, from where it turns
    r = (1.65, 0.62, 2.0)
    shell(top, (0, 0.3, 0), r, CERAMIC, PLAIN, "y", -0.45, 1.0, sides=16, stacks=5)
    shell(top, (0, 0.3, 0), r, BRASS, PLAIN, "y", -0.45, -0.3, sides=16, stacks=1, grow=0.03)
    shell(top, (0, 0.3, 0), r, BRASS, PLAIN, "z", -0.05, 0.0, sides=16, stacks=1, grow=0.03)
    for x in (-1, 1):  # a brass ring on each cheek
        hoop(top, (x * 1.5, 0.42, -0.5), (1, 0, 0), 0.28, 0.07)
    top.box((0.7, 0.22, 0.8), (0, 0.95, -0.5), CERAMIC)  # the cupola
    top.box((0.74, 0.07, 0.84), (0, 0.84, -0.5), BRASS)
    top.box((0.4, 0.08, 0.05), (0, 0.97, -0.09), LIT, SIDE_GLOW)
    top.box((0.8, 0.5, 0.7), (0, 0.32, 1.7), BRASS)  # the gun's collar
    barrel(top, (0, 0.32, 1.9), (0, 0, 1), [(0.0, 0.7, 0.24), (0.7, 3.3, 0.15)])
    barrel(top, (0, 0.32, 1.9), (0, 0, 1), [(0.7, 0.85, 0.2), (3.3, 3.7, 0.2)], BRASS)
    top.lathe((0, 0.32, 5.6), (0, 0, 1), [(0, 0.12), (0.03, 0.12)], LIT, SIDE_GLOW, sides=10)
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, 0.32, 5.65), "view": 0.85}
