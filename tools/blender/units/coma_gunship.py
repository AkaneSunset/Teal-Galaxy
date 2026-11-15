"""The Coma Conglomerate's gunships, Mk I to III: a hovering claw craft. A graphite dome of a shell
with a crest down its middle that comes to a beak at the front, an amber eye in the core under it
throwing a beam of light down, and talon arms curling down from under the rim, lit near their tips.

Mk I: four talons. Mk II: a second, thicker layer of shell and missile pods along its rim.
Mk III: six talons, a second dome on the first, pods all round the rim and a double halo round it.
About 8.5, 9.5 and 11 m long. The origin is its middle: aircraft are placed at their flying height.
"""

import math

from mathutils import Vector

from units.coma_kit import *  # noqa: F401,F403

SIZE = {1: 1.0, 2: 1.1, 3: 1.28}


C = (0.0, -0.45, 0.3)  # the dome's middle
R = (3.0, 2.4, 3.5)


def _rim(a, rx=3.0, rz=3.5, y=-0.9):
    t = math.radians(a)
    return (rx * math.sin(t), y + 0.2 * abs(math.cos(t)), C[2] + rz * math.cos(t))


def _on(across, la, out=0.0):
    """A point on the dome: `la` degrees along it from the front edge (0) over the top (-90) to the
    back (-180), `across` degrees out to the side, `out` off its surface."""
    a, b = math.radians(-la), math.radians(across)
    d = Vector((math.sin(b) * math.sin(a), math.sin(a) * math.cos(b), math.cos(a)))
    return (C[0] + d.x * (R[0] + out), C[1] + d.y * (R[1] + out), C[2] + d.z * (R[2] + out))


def make(Part, tier):
    body = Part()
    # The shell: a dome, high at the front, a skirt flaring out under it, a gold lip round its edge.
    shell(body, C, R, GRAPHITE, PLAIN, "y", 0.0, 1.0, sides=24, stacks=7)
    shell(body, C, (R[0] + 0.15, 0.9, R[2] + 0.15), GRAPHITE, PLAIN, "y", -0.55, 0.0, sides=24, stacks=2)
    tube(body, [_rim(a, R[0] + 0.05, R[2] + 0.05, C[1] - 0.47) for a in range(0, 360, 12)], 0.09, GOLD, PLAIN, sides=4, closed=True)
    # A tail of shell sweeping low out behind it.
    shell(body, (0, C[1], C[2] - 1.9), (2.55, 1.85, 3.3), GRAPHITE, PLAIN, "y", 0.0, 1.0, sides=18, stacks=5)
    # The crest down its middle, lying on the shell, out over the front and down to a beak.
    crest = [_on(0.0, la, 0.12) for la in range(-170, -20, 15)] + [_on(0.0, la, 0.12) for la in range(-15, 1, 5)]
    tube(body, crest, 0.3, GRAPHITE, PLAIN, sides=6, squash=0.55)
    front = Vector(_on(0.0, 0, 0.1))
    beak = bezier(tuple(front + Vector((0, 0.5, -0.4))), tuple(front + Vector((0, -0.2, 0.55))), tuple(front + Vector((0, -1.9, 0.35))), n=6)
    tube(body, beak, taper(6, 0.75, 0.0, 1.2), GRAPHITE, PLAIN, sides=6, squash=0.55)
    # The side's colour: a band each side of the crest, and a line of its light along the skirt.
    for sx in (-1, 1):
        tube(body, [_on(sx * 22.0, la, 0.03) for la in range(-150, -10, 14)], 0.13, LIT, PAINT, sides=4, squash=1.8)
    tube(body, [_rim(a, R[0] + 0.18, R[2] + 0.18, C[1] - 0.55) for a in range(-140, 141, 10)], 0.04, LIT, SIDE_GLOW, sides=4)
    # The core: a dark knot under the shell, the eye at its front, the beam below.
    ball(body, (0, -1.0, 0.4), 1.5, DEEP, sides=12, stacks=6)
    shell(body, (0, -1.1, 0.4), (1.55, 1.25, 1.6), GRAPHITE, PLAIN, "y", -1.0, -0.1, sides=12, stacks=3)
    eye(body, (0, -1.3, 2.0), (0, -0.25, 1), 0.65)
    body.lathe((0, -1.85, 1.75), (0, -0.9, 0.42), [(0, 0.16), (1.2, 0.3), (2.0, 0.36)], Color(1.0, 0.72, 0.38), GLOW, sides=8)
    # The talons.
    angles = [40, -40, 140, -140] if tier < 3 else [32, -32, 90, -90, 148, -148]
    for a in angles:
        lean = 1.0 if abs(a) < 90 else 0.85
        talon(body, around(1.8, a, -1.0), around(4.6 * lean, a, -1.3), around(3.0 * lean, a, -4.9), 0.55 if tier == 1 else 0.62)
        ball(body, around(1.75, a, -0.85), 0.62, GRAPHITE, sides=8, stacks=4)  # its shoulder
    if tier >= 2:
        # A second layer of shell over the first, and missile pods along the rim.
        shell(body, (0, C[1] + 0.1, C[2] - 0.3), (2.75, 2.3, 3.3), GRAPHITE, PLAIN, "y", 0.25, 1.0, sides=24, stacks=5, grow=0.18)
        tube(body, [(2.95 * math.sin(math.radians(a)), C[1] + 0.1 + 2.48 * 0.25 + 0.02, C[2] - 0.3 + 3.5 * math.cos(math.radians(a))) for a in range(0, 360, 12)], 0.08, GOLD, PLAIN, sides=4, closed=True)
        spots = [45, 75, 105, 135] if tier == 2 else [30, 55, 80, 105, 130, 155]
        for sx in (-1, 1):
            for a in spots:
                t = math.radians(a)
                p = (sx * 2.85 * math.sin(t), -0.1 + 0.6 * abs(math.cos(t)), -0.2 + 3.7 * math.cos(t))
                ball(body, p, 0.48, GRAPHITE, sides=8, stacks=4)
                body.lathe((p[0] + sx * 0.3, p[1], p[2]), (sx, 0, 0), [(0, 0.2), (0.22, 0.2)], AMBER, GLOW, sides=6)
    if tier >= 3:
        # A second dome on the first, and the halo: two amber rings round it.
        shell(body, (0, 1.2, -0.9), (1.9, 1.5, 2.4), GRAPHITE, PLAIN, "y", 0.0, 1.0, sides=18, stacks=5)
        tube(body, [(1.95 * math.sin(math.radians(a)), 1.22, -0.9 + 2.45 * math.cos(math.radians(a))) for a in range(0, 360, 15)], 0.08, GOLD, PLAIN, sides=4, closed=True)
        for row, y in ((0, 0.7), (1, 1.45)):
            for sx in (-1, 1):
                for a in (60, 95, 130):
                    t = math.radians(a + row * 15)
                    ball(body, (sx * (2.4 - row * 0.9) * math.sin(t), y + 0.4, -0.4 + (3.2 - row * 1.2) * math.cos(t)), 0.36, GRAPHITE, sides=8, stacks=4)
        ring(body, (0, 0.25, -0.2), (0, 1, 0), 4.7, 0.09, sides=40)
        ring(body, (0, 0.25, -0.2), (0, 1, 0), 5.25, 0.06, sides=40)
        ring(body, (0, 0.25, -0.2), (0, 1, 0), 5.7, 0.04, sides=40)
    k = SIZE[tier]
    body = scaled(body, k)
    fly = 7.0 + tier
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -1.2 * k, 2.2 * k), "views": air_views(fly, 0.95 * k, -0.6), "fly": fly}


def build(Part):
    return make(Part, 1)
