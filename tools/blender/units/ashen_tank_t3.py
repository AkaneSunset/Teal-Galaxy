"""The Ashen Collective's tier 3 heavy tank: a long, low wedge of black plate. Full-length tracks
under deep angular skirts, a glacis that runs most of the way up the hull, a flat turret that
tapers forward and to the sides, and a thick gun carried level, its muzzle lit. Its light is the
side's colour: conduits zigzagging along the skirts, slits in the plating.

About 9.9 m wide and 12 m long without the gun (the server's tier 3 tank is 6.25 m in radius).
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
LAMP = Color(1.0, 0.92, 0.8)

TOP_AT = (0.0, 3.1, -0.9)  # where the turret turns, on the hull


def build(Part):
    body, right = Part(), Part()

    # The hull between the tracks: a tub whose glacis climbs from the nose to the turret ring.
    body.extrude([(-5.6, 0.9), (4.6, 0.9), (6.2, 1.7), (6.0, 2.1), (3.0, 3.1), (-5.3, 3.1), (-5.8, 2.4)], -2.9, 2.9, PLATE)
    tilt = math.degrees(math.atan2(1.0, 3.0))
    up = (0.0, math.cos(math.radians(tilt)), math.sin(math.radians(tilt)))

    def on_glacis(z, lift):
        y = 2.1 + (6.0 - z) / 3.0
        return (y + up[1] * lift, z + up[2] * lift)
    y, z = on_glacis(4.5, 0.05)
    right.box((2.2, 0.12, 2.5), (1.45, y, z), RAISED, PLAIN, (tilt, 0, 0))  # two plates on the slope
    y, z = on_glacis(5.1, 0.12)
    right.box((1.5, 0.05, 0.15), (1.45, y, z), LIT, SIDE_GLOW, (tilt, 0, 0))
    y, z = on_glacis(4.0, 0.12)
    right.box((0.15, 0.05, 1.1), (2.3, y, z), LIT, SIDE_GLOW, (tilt, 0, 0))
    y, z = on_glacis(3.9, 0.1)
    body.box((0.5, 0.26, 0.9), (0, y, z), RECESS, PLAIN, (tilt, 0, 0))  # the driver's block
    y, z = on_glacis(4.38, 0.13)
    body.box((0.34, 0.12, 0.05), (0, y + 0.02, z), LIT, SIDE_GLOW)
    body.slab(1.0, (-2.2, 2.2, 5.0, 5.5), 1.5, (-2.2, 2.2, 5.5, 6.25), RAISED)  # the lower lip
    right.box((1.2, 0.16, 0.08), (1.7, 1.9, 6.12), LIT, SIDE_GLOW)
    right.box((0.3, 0.16, 0.08), (0.7, 1.9, 6.12), LAMP, GLOW)

    # The tracks, one a side the whole length of the hull, road wheels showing under the skirt.
    loop = [(-5.0, 0.0), (4.9, 0.0), (5.9, 0.9), (5.9, 1.5), (5.2, 2.1), (-5.3, 2.1), (-5.9, 1.5), (-5.9, 0.8)]
    right.track(loop, 2.9, 4.7, TRACK, CLEAT, every=0.5)
    for z in (-4.4, -2.65, -0.9, 0.85, 2.6, 4.35):
        right.wheel(0.58, 4.5, 4.76, z, 0.62, PLATE, sides=8)
    right.wheel(0.5, 4.5, 4.8, 5.3, 1.3, PLATE, sides=8)  # the front sprocket, clear of the skirt
    right.wheel(0.14, 4.8, 4.84, 5.3, 1.3, LIT, SIDE_GLOW, sides=6)

    # The skirt: a deep plate over the track, cut to six angles, two more plates laid on it and
    # the conduit zigzagging between them.
    right.extrude([(-5.6, 1.05), (-4.9, 0.6), (3.6, 0.6), (4.5, 1.15), (4.85, 2.0), (4.2, 2.75), (-5.2, 2.75), (-5.8, 2.1)], 4.68, 4.9, RAISED)
    right.extrude([(-5.3, 1.2), (-4.8, 0.78), (-2.3, 0.78), (-1.05, 2.03), (-5.5, 2.03)], 4.9, 4.97, PLATE)
    right.extrude([(0.6, 0.78), (3.5, 0.78), (4.3, 1.25), (4.55, 2.0), (4.3, 2.4), (2.6, 2.4), (1.6, 1.15), (0.25, 1.15)], 4.9, 4.97, PLATE)
    right.line([(-5.3, 2.22), (-0.95, 2.22), (0.2, 0.97), (1.7, 0.97), (2.85, 2.58), (4.1, 2.58)], 4.99, LIT)
    right.line([(-4.3, 1.4), (-2.9, 1.4)], 4.99, LIT)
    right.line([(2.6, 1.55), (3.7, 1.55)], 4.99, LIT)

    # Over the track: armour sloping from the skirt's top edge up to the deck.
    right.slab(2.1, (2.9, 4.72, -5.85, 5.2), 2.75, (2.9, 4.9, -5.75, 4.6), PLATE)
    right.slab(2.75, (2.6, 4.9, -5.75, 4.6), 3.1, (2.6, 3.6, -5.3, 3.0), PLATE)
    right.slab(3.1, (2.95, 3.5, -4.8, 1.2), 3.17, (3.0, 3.45, -4.7, 1.1), RAISED)
    lean = -math.degrees(math.atan2(0.35, 1.3))
    for z, long in ((-3.6, 1.6), (0.2, 1.6)):  # lit seams on the slope, for the battle camera overhead
        right.box((0.16, 0.05, long), (4.25, 2.95, z), LIT, SIDE_GLOW, (0, 0, lean))

    # The engine deck and the stern: a plate with a hatch, light bars, exhausts.
    body.slab(3.1, (-2.3, 2.3, -5.2, -4.3), 3.3, (-2.1, 2.1, -5.1, -4.4), RAISED)
    for x in (-1.3, 0.0, 1.3):
        body.box((0.8, 0.04, 0.4), (x, 3.31, -4.75), LIT, SIDE_GLOW)
    body.slab(1.1, (-2.3, 2.3, -5.95, -5.6), 2.6, (-2.3, 2.3, -6.0, -5.65), RAISED)
    body.box((1.5, 1.0, 0.1), (0, 1.85, -6.0), RECESS)
    right.box((0.9, 0.16, 0.06), (1.6, 2.3, -6.02), LIT, SIDE_GLOW)
    right.box((0.9, 0.16, 0.06), (1.6, 1.4, -6.02), LIT, SIDE_GLOW)
    right.box((0.5, 0.36, 0.5), (2.5, 2.85, -5.6), RECESS)
    right.box((0.32, 0.18, 0.06), (2.5, 2.85, -5.86), LIT, SIDE_GLOW)
    body.mirrored(right)

    # --- The turret, from where it turns: tallest behind its middle, falling away forward and to
    # both sides, so from any side it is a flat wedge. ---
    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 2.3), (0.3, 2.3)], RECESS, sides=12)
    mid = [(-3.6, 0.25), (3.2, 0.25), (3.6, 0.7), (3.3, 1.05), (0.2, 1.75), (-2.6, 1.75), (-3.7, 1.2)]
    edge = [(-3.0, 0.25), (2.2, 0.25), (2.5, 0.55), (2.3, 0.8), (0.0, 1.1), (-2.3, 1.1), (-3.1, 0.8)]
    top.extrude(mid, -1.2, 1.2, PLATE)
    side.extrude(mid, 1.2, 2.75, PLATE, profile1=edge)
    side.extrude([(-2.6, 0.3), (1.9, 0.3), (2.1, 0.55), (1.9, 0.72), (-0.1, 0.95), (-2.1, 0.95), (-2.7, 0.7)], 2.75, 2.9, RAISED)  # cheek plate
    side.line([(-2.1, 0.62), (0.4, 0.62)], 2.92, LIT, wide=0.12)
    side.line([(0.9, 0.5), (1.6, 0.5)], 2.92, LIT, wide=0.12)
    lean = -math.degrees(math.atan2(0.65, 1.55))
    side.box((0.16, 0.05, 1.9), (2.0, 1.45, -1.3), LIT, SIDE_GLOW, (0, 0, lean))  # lit seam on the roof's slope
    top.slab(1.75, (-1.0, 1.0, -2.4, 0.0), 1.83, (-0.9, 0.9, -2.3, -0.1), ROOF, PAINT)  # the roof plate, in the side's colour
    top.lathe((0.45, 1.83, -1.5), (0, 1, 0), [(0, 0.42), (0.24, 0.36)], RAISED, sides=8)  # the cupola
    top.box((0.34, 0.1, 0.06), (0.45, 1.96, -1.12), LIT, SIDE_GLOW)
    top.box((0.5, 0.3, 0.7), (-0.5, 1.98, -0.9), RECESS)  # the sight
    top.box((0.32, 0.14, 0.05), (-0.5, 2.0, -0.53), LIT, SIDE_GLOW)
    slope = math.degrees(math.atan2(0.7, 3.1))
    side.box((0.7, 0.05, 0.14), (0.75, 1.3, 2.2 + 0.03), LIT, SIDE_GLOW, (slope, 0, 0))  # slits on the turret's brow
    side.box((0.9, 0.14, 0.08), (0.65, 0.75, -3.68), LIT, SIDE_GLOW)  # and across its back

    # The gun, level: mantlet, a heavy sleeve, the barrel and a muzzle that glows.
    pivot = (0.0, 0.68, 3.3)
    top.box((1.5, 0.85, 0.9), (0, 0.68, 3.55), RAISED)
    top.lathe(pivot, (0, 0, 1), [(0.6, 0.52), (2.6, 0.52)], PLATE, turn=math.pi / 8)
    side.box((0.05, 0.14, 1.4), (0.5, 0.68, 4.9), LIT, SIDE_GLOW)
    top.box((0.14, 0.05, 1.4), (0, 1.18, 4.9), LIT, SIDE_GLOW)
    top.lathe(pivot, (0, 0, 1), [(2.6, 0.58), (2.95, 0.58)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, (0, 0, 1), [(2.95, 0.38), (5.6, 0.38)], PLATE, turn=math.pi / 8)
    top.lathe(pivot, (0, 0, 1), [(4.2, 0.45), (4.5, 0.45)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, (0, 0, 1), [(5.5, 0.44), (5.6, 0.44)], LIT, SIDE_GLOW, turn=math.pi / 8)
    top.lathe(pivot, (0, 0, 1), [(5.6, 0.54), (6.6, 0.54)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, (0, 0, 1), [(6.6, 0.36), (6.66, 0.36)], LIT, SIDE_GLOW, turn=math.pi / 8)  # the lit muzzle
    side.box((0.05, 0.14, 0.5), (0.52, 0.68, 9.4), LIT, SIDE_GLOW)
    top.mirrored(side)

    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": (0.0, 0.68, 9.96), "view": 1.25}
