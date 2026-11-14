"""The Ashen Collective's tier 1 assault bot: a compact two-legged walker. Squat legs bent forward
at the knee, a faceted chest with the emblem lit on it, a low head with a lit visor, twin pulse
rifles for forearms and a rocket pod over its left shoulder. Its light is the side's colour.

The legs and hips are the body; everything from the waist up is the top, so it turns to face what
it shoots at. About 4.4 m wide across the rifles and 5.2 m tall (the server's striker is 3 m in
radius).
"""

import math

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

PLATE = Color(0.19, 0.19, 0.21)  # the armour
RAISED = Color(0.28, 0.28, 0.3)  # plates laid over it
RECESS = Color(0.11, 0.11, 0.12)
ROOF = Color(0.1, 0.1, 0.1)  # painted in the side's colour
LIT = Color(1, 1, 1)

TOP_AT = (0.0, 2.75, 0.0)  # the waist


def _ring(y, x0, x1, z0, z1):
    return [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]


def build(Part):
    body, right = Part(), Part()

    # A leg (the right; the left is its mirror): a broad foot, a shin leaning forward to the knee,
    # a thigh leaning back to the hip.
    right.slab(0.0, (0.5, 1.5, -0.65, 0.9), 0.42, (0.62, 1.38, -0.45, 0.55), PLATE)
    right.slab(0.0, (0.55, 1.45, 0.85, 1.35), 0.3, (0.6, 1.4, 0.8, 1.05), RAISED)
    right.box((0.5, 0.04, 0.1), (1.0, 0.31, 0.9), LIT, SIDE_GLOW)
    right.hexa(_ring(0.4, 0.68, 1.32, -0.38, 0.3), _ring(1.55, 0.62, 1.38, 0.08, 0.88), PLATE)  # the shin
    right.hexa(_ring(0.55, 0.76, 1.24, 0.26, 0.42), _ring(1.65, 0.7, 1.3, 0.84, 1.04), RAISED)
    right.box((0.86, 0.5, 0.74), (1.0, 1.65, 0.52), RAISED)  # the knee
    right.wheel(0.26, 0.5, 1.5, 0.52, 1.65, RECESS, sides=8)
    right.wheel(0.1, 1.5, 1.53, 0.52, 1.65, LIT, SIDE_GLOW, sides=6)
    right.hexa(_ring(1.75, 0.62, 1.38, 0.12, 0.88), _ring(2.6, 0.48, 1.32, -0.55, 0.36), PLATE)  # the thigh
    right.hexa(_ring(1.85, 1.34, 1.52, 0.1, 0.78), _ring(2.55, 1.3, 1.5, -0.46, 0.28), RAISED)
    right.line([(0.3, 2.05), (-0.12, 2.42)], 1.53, LIT, wide=0.08)
    right.wheel(0.42, 0.45, 1.4, -0.1, 2.5, RECESS, sides=8)  # the hip joint

    # The hips.
    body.slab(2.25, (-0.8, 0.8, -0.6, 0.55), 2.75, (-1.0, 1.0, -0.65, 0.6), PLATE)
    body.hexa(_ring(1.95, -0.3, 0.3, 0.45, 0.6), _ring(2.7, -0.5, 0.5, 0.55, 0.75), RAISED)
    body.mirrored(right)

    # --- From the waist up, measured from the waist ---
    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 0.62), (0.25, 0.62)], RECESS, sides=8)
    top.hexa(_ring(0.2, -0.8, 0.8, -0.7, 0.7), _ring(1.5, -1.15, 1.15, -0.9, 1.0), PLATE)  # the chest
    top.slab(1.5, (-1.15, 1.15, -0.9, 1.0), 1.9, (-0.95, 0.95, -0.8, 0.55), PLATE)
    top.box((1.1, 0.95, 0.14), (0, 0.95, 0.9), RAISED, PLAIN, (-13, 0, 0))  # the chest plate, the emblem lit on it
    hexagon = [(0.24 * math.cos(math.tau * k / 6), 0.95 + 0.24 * math.sin(math.tau * k / 6), 1.0 + (0.24 * math.sin(math.tau * k / 6)) * 0.23) for k in range(7)]
    top.trace(hexagon, 0.06, 0.05, LIT)
    top.trace([(-0.12, 0.82, 0.97), (0.12, 1.08, 1.03)], 0.06, 0.05, LIT)
    side.box((0.4, 0.07, 0.05), (0.75, 0.55, 0.86), LIT, SIDE_GLOW, (-13, 0, 0))
    top.hexa(_ring(0.3, -0.7, 0.7, -1.25, -0.7), _ring(1.6, -0.6, 0.6, -1.2, -0.85), RAISED)  # the pack on its back
    side.box((0.14, 0.7, 0.06), (0.3, 0.95, -1.24), LIT, SIDE_GLOW)

    # The head: low and wide, a lit visor across it.
    top.slab(1.9, (-0.52, 0.52, -0.5, 0.72), 2.45, (-0.44, 0.44, -0.45, 0.42), RAISED)
    top.box((0.78, 0.1, 0.06), (0, 2.12, 0.62), LIT, SIDE_GLOW, (-29, 0, 0))
    top.slab(2.45, (-0.36, 0.36, -0.38, 0.3), 2.5, (-0.32, 0.32, -0.34, 0.26), ROOF, PAINT)  # its crown, in the side's colour

    # A shoulder, an upper arm, and for a forearm a twin pulse rifle carried level.
    side.hexa(_ring(1.0, 1.15, 1.9, -0.5, 0.5), _ring(1.75, 1.1, 1.75, -0.42, 0.42), RAISED)
    side.slab(1.75, (1.18, 1.68, -0.34, 0.34), 1.8, (1.22, 1.64, -0.3, 0.3), ROOF, PAINT)
    side.box((0.46, 0.75, 0.5), (1.58, 0.68, 0.05), PLATE)
    side.box((0.62, 0.62, 1.5), (1.6, 0.3, 0.85), RAISED)
    side.box((0.05, 0.1, 0.9), (1.93, 0.3, 0.85), LIT, SIDE_GLOW)
    side.box((0.2, 0.04, 0.8), (1.6, 0.62, 0.9), LIT, SIDE_GLOW)
    for y in (0.14, 0.46):
        side.lathe((1.6, y, 1.6), (0, 0, 1), [(0, 0.15), (0.5, 0.15)], PLATE, turn=math.pi / 8)
        side.lathe((1.6, y, 1.6), (0, 0, 1), [(0.5, 0.1), (1.35, 0.1)], RECESS, turn=math.pi / 8)
        side.lathe((1.6, y, 1.6), (0, 0, 1), [(1.35, 0.14), (1.6, 0.14)], RAISED, turn=math.pi / 8)
        side.lathe((1.6, y, 1.6), (0, 0, 1), [(1.6, 0.09), (1.63, 0.09)], LIT, SIDE_GLOW, turn=math.pi / 8)
    top.mirrored(side)

    # The rocket pod over its left shoulder: nine tubes, a rocket's lit tip in each.
    top.box((0.3, 0.5, 0.3), (-1.45, 1.95, -0.15), RECESS)
    top.box((0.95, 0.8, 1.0), (-1.5, 2.5, -0.1), RAISED)
    top.box((0.8, 0.66, 0.05), (-1.5, 2.5, 0.41), RECESS)
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            top.box((0.14, 0.12, 0.05), (-1.5 + i * 0.24, 2.5 + j * 0.2, 0.44), LIT, SIDE_GLOW)

    views = {
        "front": ((-9.5, -13.5, 6.6), (0.2, 0, 2.9), 50, 0.0, (60, 0, 70)),
        "rear": ((8, 12, 5.6), (0, 0, 2.6), 50, 0.0),
        "side": ((-20, 0, 2.8), (0, 0.6, 2.7), 60, 0.0, (40, 0, -60)),
        "head_on": ((0, -20, 3.0), (0, 0, 2.7), 60, 0.0),
        "top": ((0, -0.6, 26), (0, -0.5, 0), 62, math.pi / 2, (30, 0, 200)),
    }
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (1.6, 0.3, 3.23), "views": views}
