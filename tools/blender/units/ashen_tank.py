"""The Ashen Collective's tier 1 light tank: low, fast and faceted. A shallow hull whose nose is
four blunt prows (one over each track, two between them) around a sunken glacis, skirts over the
top half of the tracks with the road wheels showing below, a flat faceted turret with a lit
hexagon on each cheek, and a thin rail cannon with a boxed muzzle. Its light is the side's colour,
in thin lines along the plating.

About 6.5 m wide and 8.4 m long without the gun (the server's tier 1 tank is 4 m in radius).
"""

import math

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

PLATE = Color(0.19, 0.19, 0.21)  # the armour
RAISED = Color(0.28, 0.28, 0.3)  # plates laid over it
RECESS = Color(0.11, 0.11, 0.12)
TRACK = Color(0.07, 0.07, 0.075)
CLEAT = Color(0.14, 0.14, 0.15)
ROOF = Color(0.1, 0.1, 0.1)  # painted in the side's colour
LIT = Color(1, 1, 1)

TOP_AT = (0.0, 2.1, -0.5)  # where the turret turns, on the hull


def _ring(y, x0, x1, z0, z1):
    return [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]


def build(Part):
    body, right = Part(), Part()

    # The hull between the tracks, its glacis sunk between the prows.
    body.extrude([(-3.7, 0.6), (3.0, 0.6), (4.1, 1.1), (4.0, 1.4), (1.6, 2.1), (-3.5, 2.1), (-3.9, 1.6)], -2.0, 2.0, PLATE)
    tilt = math.degrees(math.atan2(0.7, 2.4))
    up = (0.0, math.cos(math.radians(tilt)), math.sin(math.radians(tilt)))

    def on_glacis(z, lift):
        y = 1.4 + (4.0 - z) * 0.7 / 2.4
        return (y + up[1] * lift, z + up[2] * lift)
    y, z = on_glacis(2.7, 0.04)
    body.box((1.1, 0.1, 1.9), (0, y, z), RAISED, PLAIN, (tilt, 0, 0))
    y, z = on_glacis(2.7, 0.1)
    right.beam((0.12, y - 0.2, z + 0.7), (0.45, y + 0.2, z - 0.7), 0.07, 0.04, LIT, SIDE_GLOW, face=up)

    # The tracks, and six road wheels a side showing under the skirt.
    loop = [(-3.3, 0.0), (3.2, 0.0), (3.9, 0.6), (3.9, 1.0), (3.4, 1.4), (-3.5, 1.4), (-3.9, 1.0), (-3.9, 0.55)]
    right.track(loop, 2.0, 3.1, TRACK, CLEAT, every=0.36)
    right.extrude([(-3.1, 0.2), (3.0, 0.2), (3.5, 0.65), (3.1, 1.2), (-3.2, 1.2), (-3.6, 0.7)], 3.1, 3.13, RECESS)
    for z in (-2.9, -1.75, -0.6, 0.55, 1.7, 2.85):
        right.wheel(0.42, 3.05, 3.2, z, 0.46, PLATE, sides=10)
        right.wheel(0.17, 3.2, 3.24, z, 0.46, RAISED, sides=6)

    # The skirt over the top of the track: one faceted plate, thin lit lines traced across it.
    right.extrude([(-3.95, 0.98), (-3.5, 0.78), (2.9, 0.78), (3.6, 1.0), (4.0, 1.5), (3.4, 1.95), (-3.6, 1.95), (-4.0, 1.6)], 3.1, 3.28, RAISED)
    right.extrude([(-3.5, 0.9), (-1.5, 0.9), (-0.7, 1.82), (-3.7, 1.82)], 3.28, 3.33, PLATE)
    right.extrude([(1.1, 0.9), (2.85, 0.9), (3.5, 1.1), (3.75, 1.5), (3.35, 1.82), (1.8, 1.82)], 3.28, 3.33, PLATE)
    right.line([(-3.7, 1.88), (-0.62, 1.88), (0.15, 0.95), (1.0, 0.95), (1.75, 1.88), (3.3, 1.88)], 3.34, LIT, wide=0.06, proud=0.05)
    right.line([(-3.0, 1.2), (-2.0, 1.2)], 3.35, LIT, wide=0.06, proud=0.05)
    right.line([(2.2, 1.3), (3.1, 1.3)], 3.35, LIT, wide=0.06, proud=0.05)

    # Over the track: a fender, then armour sloping up to the deck.
    right.slab(1.4, (2.0, 3.2, -3.95, 3.5), 1.95, (2.0, 3.28, -3.9, 3.2), PLATE)
    right.slab(1.95, (1.8, 3.28, -3.9, 3.2), 2.1, (1.8, 2.5, -3.5, 1.6), PLATE)
    right.line([(-2.8, 2.05), (0.6, 2.05)], 2.52, LIT, wide=0.06, proud=0.5)  # a lit seam along the deck's edge, for the camera overhead

    # The prows: one over the track's front, one inboard of it, a lit bar across each.
    for x0, x1, y0, y1, z in ((2.02, 3.26, 1.0, 1.97, 3.15), (0.75, 1.85, 0.9, 1.8, 3.3)):
        right.hexa(_ring(y0, x0, x1, z, z + 1.15), _ring(y1, x0 + 0.06, x1 - 0.06, z - 0.1, z + 0.5), RAISED)
        lean = -math.degrees(math.atan2(0.65, y1 - y0))
        right.box((x1 - x0 - 0.5, 0.1, 0.06), ((x0 + x1) / 2, y0 + 0.28, z + 1.0), LIT, SIDE_GLOW, (lean, 0, 0))

    # The stern: a plate, a hatch, two small lights.
    body.slab(0.8, (-1.7, 1.7, -4.05, -3.7), 1.9, (-1.7, 1.7, -4.1, -3.75), RAISED)
    body.box((1.4, 0.6, 0.08), (0, 1.25, -4.1), RECESS)
    right.box((0.4, 0.1, 0.06), (1.25, 1.65, -4.11), LIT, SIDE_GLOW)
    right.box((0.5, 0.1, 0.06), (2.6, 1.6, -3.97), LIT, SIDE_GLOW)
    body.slab(2.1, (-1.4, 1.4, -3.4, -2.75), 2.22, (-1.3, 1.3, -3.3, -2.85), RAISED)  # the engine deck
    body.mirrored(right)

    # --- The turret, from where it turns: flat and faceted, falling away forward and to the sides ---
    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 1.5), (0.2, 1.5)], RECESS, sides=12)
    mid = [(-2.3, 0.15), (2.0, 0.15), (2.3, 0.45), (1.9, 0.8), (0.3, 1.2), (-1.6, 1.2), (-2.4, 0.8)]
    edge = [(-1.9, 0.15), (1.3, 0.15), (1.5, 0.4), (1.3, 0.6), (0.1, 0.85), (-1.4, 0.85), (-2.0, 0.6)]
    top.extrude(mid, -0.7, 0.7, PLATE)
    side.extrude(mid, 0.7, 1.75, PLATE, profile1=edge)
    side.extrude([(-1.7, 0.2), (1.1, 0.2), (1.25, 0.4), (1.1, 0.55), (0.0, 0.78), (-1.3, 0.78), (-1.8, 0.55)], 1.75, 1.84, RAISED)  # cheek plate
    hexagon = [(-0.25 + 0.27 * math.cos(math.tau * k / 6), 0.49 + 0.27 * math.sin(math.tau * k / 6)) for k in range(7)]
    side.line(hexagon, 1.86, LIT, wide=0.06, proud=0.05)  # the lit hexagon
    side.line([(-0.33, 0.49), (-0.17, 0.49)], 1.86, LIT, wide=0.12, proud=0.05)
    lean = -math.degrees(math.atan2(0.35, 1.05))
    side.box((0.08, 0.04, 1.4), (1.25, 1.04, -0.7), LIT, SIDE_GLOW, (0, 0, lean))  # a lit seam on the roof's slope
    top.slab(1.2, (-0.6, 0.6, -1.45, 0.15), 1.26, (-0.54, 0.54, -1.39, 0.09), ROOF, PAINT)  # the roof plate, in the side's colour
    top.box((0.5, 0.26, 0.6), (0, 1.36, -0.9), RAISED)  # the sensor
    top.box((0.3, 0.1, 0.05), (0, 1.38, -0.58), LIT, SIDE_GLOW)
    side.box((0.5, 0.1, 0.06), (0.5, 0.5, -2.37), LIT, SIDE_GLOW)

    # The rail cannon: a mantlet, a boxed breech, a thin barrel, a boxed muzzle with two lit points a side.
    top.box((0.95, 0.6, 0.7), (0, 0.55, 2.25), RAISED)
    top.box((0.5, 0.46, 1.5), (0, 0.55, 3.2), PLATE)
    side.box((0.05, 0.08, 0.8), (0.26, 0.55, 3.25), LIT, SIDE_GLOW)
    top.lathe((0, 0.55, 3.9), (0, 0, 1), [(0, 0.15), (2.7, 0.15)], PLATE, turn=math.pi / 8)
    top.lathe((0, 0.55, 3.9), (0, 0, 1), [(1.2, 0.2), (1.4, 0.2)], RAISED, turn=math.pi / 8)
    top.box((0.42, 0.36, 0.9), (0, 0.55, 7.0), RAISED)
    for z in (6.8, 7.15):
        side.box((0.05, 0.1, 0.12), (0.22, 0.55, z), LIT, SIDE_GLOW)
    top.box((0.16, 0.16, 0.04), (0, 0.55, 7.46), LIT, SIDE_GLOW)
    top.mirrored(side)

    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, 0.55, 7.48), "view": 0.82}
