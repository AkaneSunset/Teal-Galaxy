"""The Ashen Collective's tier 1 light artillery: a six-wheeled gun carrier. A faceted cab at the
front with a sensor mast, a crew box behind it marked with a lit emblem, and a flat bed at the back
carrying a howitzer on a turntable, two stabiliser legs let down behind. Its light is the side's
colour, in thin lines along the plating.

About 4.4 m wide and 8.2 m long (the server's tier 1 artillery is 3 m in radius).
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

ELEVATION = 30.0
TOP_AT = (0.0, 1.9, -2.3)  # where the gun turns, on the bed


def emblem(part, x, y, z, r, wide=0.06):
    """The Ashen mark on a side wall at `x`: a hexagon struck through."""
    part.line([(z + r * math.cos(math.tau * k / 6), y + r * math.sin(math.tau * k / 6)) for k in range(7)], x, LIT, wide=wide, proud=0.05)
    part.line([(z - r * 0.5, y - r * 0.55), (z + r * 0.5, y + r * 0.55)], x, LIT, wide=wide, proud=0.05)


def build(Part):
    body, right = Part(), Part()

    # The chassis, and six wheels.
    body.extrude([(-3.9, 0.75), (3.9, 0.75), (4.1, 1.5), (-3.9, 1.5)], -1.45, 1.45, RECESS)
    for z in (2.5, -0.7, -2.6):
        right.wheel(0.78, 1.4, 2.15, z, 0.78, TYRE, sides=12)
        right.wheel(0.4, 2.15, 2.2, z, 0.78, RAISED, sides=8)
        right.wheel(0.12, 2.2, 2.23, z, 0.78, RECESS, sides=6)
        right.slab(1.6, (1.45, 2.2, z - 0.95, z + 0.95), 1.75, (1.45, 2.15, z - 0.75, z + 0.75), PLATE)  # a guard over it

    # The cab: faceted, narrowing to the roof, dark glass in its windscreen and sides.
    cab = [(0.5, 1.5), (4.15, 1.5), (4.1, 2.1), (3.3, 2.95), (1.9, 3.2), (0.5, 3.2)]
    thin = [(0.5, 1.5), (4.05, 1.5), (3.95, 2.05), (3.2, 2.75), (1.9, 2.95), (0.5, 2.95)]
    body.extrude(cab, -1.2, 1.2, PLATE)
    right.extrude(cab, 1.2, 1.6, PLATE, profile1=thin)
    slope = (0.0, 0.8 / 1.167, 0.85 / 1.167)  # out of the windscreen
    body.prism([(-1.0, 2.2, 4.03), (1.0, 2.2, 4.03), (0.9, 2.85, 3.42), (-0.9, 2.85, 3.42)], (0, slope[1] * 0.05, slope[2] * 0.05), GLASS)
    right.extrude([(1.0, 2.2), (2.9, 2.2), (2.6, 2.7), (1.0, 2.75)], 1.5, 1.62, GLASS)
    body.slab(1.0, (-1.5, 1.5, 3.9, 4.25), 1.55, (-1.5, 1.5, 3.95, 4.3), RAISED)  # the bumper
    right.box((0.75, 0.1, 0.06), (0.95, 1.85, 4.17), LIT, SIDE_GLOW)  # headlamps, in the side's colour
    right.line([(0.9, 1.7), (3.6, 1.7), (3.9, 2.0)], 1.63, LIT, wide=0.06, proud=0.06)
    body.slab(3.2, (-0.8, 0.8, 0.7, 1.8), 3.26, (-0.74, 0.74, 0.76, 1.74), ROOF, PAINT)  # the roof plate, in the side's colour
    # The sensor mast on the cab's roof.
    body.box((0.1, 1.5, 0.1), (-0.85, 3.95, 1.0), RECESS)
    body.lathe((-0.85, 4.35, 1.0), (0, 1, 0), [(0, 0.28), (0.22, 0.28)], RAISED, sides=8)
    body.box((0.1, 0.1, 0.1), (-0.85, 4.72, 1.0), LIT, SIDE_GLOW)

    # The crew box behind the cab, the emblem lit on each side.
    body.slab(1.5, (-1.62, 1.62, -1.2, 0.5), 3.0, (-1.5, 1.5, -1.1, 0.5), RAISED)
    emblem(right, 1.6, 2.3, -0.35, 0.36)
    right.box((0.08, 0.04, 1.2), (1.2, 3.01, -0.35), LIT, SIDE_GLOW)

    # The bed: low, with lockers down each side, and two stabiliser legs let down behind.
    body.slab(1.5, (-1.6, 1.6, -3.95, -1.2), 1.9, (-1.6, 1.6, -3.9, -1.2), PLATE)
    right.slab(1.9, (1.0, 1.6, -3.7, -1.3), 2.3, (1.05, 1.55, -3.6, -1.4), RAISED)
    right.line([(-3.4, 1.72), (-1.5, 1.72)], 1.62, LIT, wide=0.06, proud=0.06)
    right.beam((1.35, 1.4, -3.7), (2.1, 0.12, -4.7), 0.3, 0.34, PLATE, PLAIN, face=(1, 0, 0), wide1=0.22, deep1=0.24)
    right.box((0.6, 0.12, 0.7), (2.1, 0.06, -4.75), RAISED)
    right.beam((1.56, 1.2, -3.86), (2.2, 0.35, -4.52), 0.06, 0.05, LIT, SIDE_GLOW, face=(1, 0.3, 0))
    right.box((0.5, 0.12, 0.06), (1.0, 1.25, -3.96), LIT, SIDE_GLOW)  # tail lights
    body.mirrored(right)

    # --- The gun, from where it turns ---
    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 0.95), (0.22, 0.95)], RECESS, sides=10)
    side.prism([(0.42, 0.2, -0.9), (0.42, 0.2, 0.7), (0.42, 1.0, 0.5), (0.42, 1.25, -0.2), (0.42, 0.9, -0.9)], (0.24, 0, 0), RAISED)  # the cradle's cheeks
    side.box((0.05, 0.3, 0.06), (0.69, 0.75, 0.0), LIT, SIDE_GLOW)
    e = math.radians(ELEVATION)
    pivot = (0.0, 0.9, 0.0)
    d = (0.0, math.sin(e), math.cos(e))
    n = (0.0, math.cos(e), -math.sin(e))

    def along(dist, up=0.0, x=0.0):
        return (x, pivot[1] + d[1] * dist + n[1] * up, pivot[2] + d[2] * dist + n[2] * up)
    rot = (-ELEVATION, 0, 0)
    top.box((0.78, 0.8, 1.9), along(-0.1), PLATE, PLAIN, rot)  # the breech
    top.box((0.5, 0.3, 1.2), along(0.6, 0.5), RAISED, PLAIN, rot)  # the recuperator over it
    top.box((0.1, 0.04, 0.8), along(0.6, 0.67), LIT, SIDE_GLOW, rot)
    top.lathe(pivot, d, [(0.85, 0.34), (2.1, 0.34)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, d, [(2.1, 0.2), (5.0, 0.2)], PLATE, turn=math.pi / 8)
    top.lathe(pivot, d, [(3.4, 0.26), (3.6, 0.26)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, d, [(4.9, 0.25), (5.0, 0.25)], LIT, SIDE_GLOW, turn=math.pi / 8)
    top.lathe(pivot, d, [(5.0, 0.31), (5.6, 0.31)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, d, [(5.6, 0.17), (5.62, 0.17)], RECESS, turn=math.pi / 8)
    top.mirrored(side)

    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": along(5.6), "view": 0.9}
