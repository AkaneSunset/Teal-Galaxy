"""The Coma Conglomerate's fighters, Mk I to III: a claw-shaped interceptor. A rounded head at the
back with an amber ring-eye engine on top and another looking out behind, and three talons reaching
forward from it, the long one down the middle, two curving out and in again, all tipped in amber.

Mk II: missile pods tucked between its talons. Mk III: four pods, a halo round its rear engine, and
heavier plating along the spine. About 9, 10 and 11 m long. The origin is its middle.
"""

import math

from units.coma_kit import *  # noqa: F401,F403

SIZE = {1: 1.0, 2: 1.1, 3: 1.2}


def make(Part, tier):
    body, right = Part(), Part()
    # The head: a long rounded shell at the back, the spine's ridge along its top.
    shell(body, (0, 0.1, -2.6), (1.55, 1.05, 2.6), GRAPHITE, PLAIN, "z", sides=14, stacks=8)
    shell(body, (0, 0.55, -2.4), (0.75, 0.75, 2.4), GRAPHITE, PLAIN, "z", sides=10, stacks=6)
    tube(body, bezier((0, 1.2, -4.6), (0, 1.5, -2.6), (0, 0.6, 0.6), n=8), taper(8, 0.22, 0.08), GRAPHITE, sides=6, squash=0.6)
    # The middle talon, flattened, down to a point well out in front.
    prong(body, bezier((0, 0.0, -1.0), (0, 0.1, 2.0), (0, -0.25, 5.6), n=8), 0.75, flat=1.5)
    # The outer talons: out from the head, round and forward, their points turned in.
    prong(right, bezier((1.0, 0.0, -3.0), (3.6, 0.1, -1.2), (3.0, -0.1, 2.6), (1.9, -0.3, 4.9), n=12), 0.62, flat=1.3)
    # The side's colour along the head, its light in a line down the talon.
    tube(right, bezier((0.72, 0.62, -4.4), (1.25, 0.75, -2.6), (0.6, 0.35, -0.4), n=6), 0.09, LIT, PAINT, sides=4)
    tube(right, bezier((2.0, 0.42, -1.8), (3.25, 0.62, 0.0), (2.6, 0.38, 2.9), n=6), 0.04, LIT, SIDE_GLOW, sides=4)
    # The engines: a ring-eye looking up out of the head, and one looking out behind.
    eye(body, (0, 1.0, -2.2), (0, 1, 0.25), 0.62)
    eye(body, (0, 0.1, -5.15), (0, 0, -1), 0.55)
    if tier >= 2:  # missile pods between the talons
        for x in ((1.25,) if tier == 2 else (0.95, 1.7)):
            missile(right, (x, -0.3 - (0.15 if x > 1.0 and tier == 3 else 0.0), -1.6), (0, 0, 1), 3.4 if tier == 2 else 3.0, 0.36, tip=AMBER if tier == 3 else GOLD)
    if tier >= 3:  # heavier plating along the spine, a halo round the rear engine
        for k in range(4):
            shell(body, (0, 0.95 - k * 0.08, -3.8 + k * 1.05), (0.95 - k * 0.1, 0.3, 0.75), GRAPHITE, PLAIN, "y", 0.0, 1.0, sides=10, stacks=2, grow=0.05)
        ring(body, (0, 0.1, -5.4), (0, 0, 1), 1.55, 0.08, sides=30)
        ring(body, (0, 0.1, -5.55), (0, 0, 1), 1.8, 0.05, sides=30)
    body.mirrored(right)
    k = SIZE[tier]
    fly = 9.0
    return {"body": scaled(body, k), "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, -0.25 * k, 5.6 * k), "views": air_views(fly, 0.85 * k), "fly": fly}


def build(Part):
    return make(Part, 1)
