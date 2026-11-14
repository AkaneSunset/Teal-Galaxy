"""The Ashen Collective's tier 1 stealth scout: a low faceted wedge on four wheels. One sharp hull
from a blunt nose up to a roof peak behind dark glass and down again to the tail, a blade down its
spine, lit spokes in the wheels, and twin coilguns under the nose. No turret: it points at what it
shoots. Its light is the side's colour.

About 3.1 m wide across the wheels and 5 m long (the server's scout is 3 m in radius).
"""

import math

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

PLATE = Color(0.19, 0.19, 0.21)  # the armour
RAISED = Color(0.28, 0.28, 0.3)  # plates laid over it
RECESS = Color(0.11, 0.11, 0.12)
TYRE = Color(0.07, 0.07, 0.075)
GLASS = Color(0.04, 0.05, 0.07)
ROOF = Color(0.1, 0.1, 0.1)  # painted in the side's colour
LIT = Color(1, 1, 1)

# The hull from the side, nose to the right: (z, y) down its middle, and what it thins to at its edge.
MIDDLE = [(2.6, 0.35), (2.5, 0.58), (0.9, 1.0), (-0.3, 1.38), (-1.9, 1.2), (-2.4, 0.8), (-2.4, 0.42), (-1.8, 0.3), (2.0, 0.3)]
EDGE = [(1.9, 0.42), (1.8, 0.52), (0.5, 0.7), (-0.4, 0.8), (-1.7, 0.8), (-2.2, 0.66), (-2.2, 0.46), (-1.7, 0.4), (1.5, 0.4)]


def build(Part):
    body, right = Part(), Part()

    right.extrude(MIDDLE, 0.0, 0.4, PLATE)
    right.extrude(MIDDLE, 0.4, 1.15, PLATE, profile1=EDGE)
    # Dark glass in the windscreen, and on down the flank.
    right.prism([(0.0, 1.03, 0.86), (0.37, 1.03, 0.86), (0.37, 1.37, -0.24), (0.0, 1.37, -0.24)], (0, 0.03, 0.01), GLASS)
    right.prism([(0.45, 0.99, 0.8), (1.0, 0.77, 0.52), (1.0, 0.86, -0.3), (0.45, 1.33, -0.25)], (0.03, 0.04, 0), GLASS)
    # A blade down the spine, from the roof's peak to the tail, in the side's colour.
    right.prism([(0.0, 1.38, -0.3), (0.0, 1.5, -0.8), (0.0, 1.42, -2.35), (0.0, 0.95, -2.42), (0.0, 1.2, -1.9)], (0.07, 0, 0), ROOF, PAINT)
    right.prism([(0.2, 1.36, -0.45), (0.75, 1.2, -0.7), (0.9, 1.08, -2.0), (0.2, 1.23, -1.95)], (0, 0.05, 0), RAISED)  # a plate laid on the back
    right.beam((0.95, 1.07, -0.9), (1.0, 0.98, -1.9), 0.07, 0.04, LIT, SIDE_GLOW, face=(0.4, 1, 0))

    # Lit lines: a slanted eye either side of the nose, two points between, a line along each
    # flank, lights across the tail.
    right.beam((0.5, 0.52, 2.5), (1.45, 0.62, 2.08), 0.09, 0.05, LIT, SIDE_GLOW, face=(0.3, 0.2, 1))
    right.box((0.1, 0.07, 0.05), (0.2, 0.46, 2.6), LIT, SIDE_GLOW)
    right.beam((1.16, 0.6, 1.3), (1.16, 0.66, -0.2), 0.07, 0.05, LIT, SIDE_GLOW, face=(1, 0, 0))
    right.beam((0.3, 0.72, -2.42), (1.3, 0.62, -2.22), 0.09, 0.05, LIT, SIDE_GLOW, face=(0.2, 0, -1))

    # Wheels, standing clear of the hull, each with a lit rim and three lit spokes.
    for z in (1.55, -1.5):
        right.box((0.5, 0.16, 0.16), (1.05, 0.55, z), RECESS)  # the stub axle
        right.wheel(0.56, 1.12, 1.52, z, 0.56, TYRE, sides=12)
        right.wheel(0.44, 1.52, 1.535, z, 0.56, LIT, SIDE_GLOW, sides=12)
        right.wheel(0.39, 1.52, 1.56, z, 0.56, RAISED, sides=6)
        for k in range(3):
            right.box((0.03, 0.06, 0.74), (1.565, 0.56, z), LIT, SIDE_GLOW, (60 * k, 0, 0))
        right.wheel(0.1, 1.56, 1.6, z, 0.56, RECESS, sides=6)

    # Twin coilguns under the nose.
    right.lathe((0.42, 0.3, 1.9), (0, 0, 1), [(0, 0.11), (0.7, 0.11)], RAISED, turn=math.pi / 8)
    right.lathe((0.42, 0.3, 1.9), (0, 0, 1), [(0.7, 0.07), (1.25, 0.07)], RECESS, turn=math.pi / 8)
    right.lathe((0.42, 0.3, 1.9), (0, 0, 1), [(1.25, 0.1), (1.4, 0.1)], RAISED, turn=math.pi / 8)
    right.lathe((0.42, 0.3, 1.9), (0, 0, 1), [(1.4, 0.06), (1.42, 0.06)], LIT, SIDE_GLOW, turn=math.pi / 8)
    body.mirrored(right)

    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, 0.3, 3.32), "view": 0.6}
