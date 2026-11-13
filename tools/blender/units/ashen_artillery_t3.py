"""The Ashen Collective's tier 3 mobile artillery: a low, wide hull of black angular plate on four
track pods, a slab-sided turret set back on it, and a long heavy gun. Its light is the side's
colour, in slits cut into the plating.

About 7.7 m wide and 10.4 m long without the gun (the server's tier 3 artillery is 4.7 m in radius).
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

ELEVATION = 22.0  # degrees the gun is carried at
TOP_AT = (0.0, 3.15, -1.2)  # where the turret turns, on the hull


def _pod(P, zc, length):
    """One track pod on the right: the track, its cleats, the wheels inside it and a skirt over them."""
    h = length / 2
    loop = [(zc - h + 0.55, 0.0), (zc + h - 0.55, 0.0), (zc + h, 0.55), (zc + h, 1.05), (zc + h - 0.45, 1.6), (zc - h + 0.45, 1.6), (zc - h, 1.05), (zc - h, 0.55)]
    P.extrude(loop, 2.45, 3.7, TRACK)
    for i in range(len(loop)):  # cleats across the track, all the way round
        (z0, y0), (z1, y1) = loop[i], loop[(i + 1) % len(loop)]
        run = math.hypot(z1 - z0, y1 - y0)
        n = max(1, round(run / 0.42))
        tilt = math.degrees(math.atan2(-(y1 - y0), z1 - z0))
        out = ((y0 - y1) / run, (z1 - z0) / run)  # (z, y) away from the loop's inside
        if out[0] * ((z0 + z1) / 2 - zc) + out[1] * ((y0 + y1) / 2 - 0.8) < 0:
            out = (-out[0], -out[1])
        for k in range(n):
            t = (k + 0.5) / n
            P.box((1.31, 0.1, 0.2), (3.075, y0 + (y1 - y0) * t + out[1] * 0.03, z0 + (z1 - z0) * t + out[0] * 0.03), CLEAT, PLAIN, (tilt, 0, 0))
    inner = [(zc + (z - zc) * (length - 0.6) / length, 0.8 + (y - 0.8) * 0.7) for z, y in loop]
    P.extrude(inner, 3.7, 3.75, RECESS)
    for dz in (-1.38, 0.0, 1.38):  # road wheels, each hub lit
        P.wheel(0.5, 3.66, 3.9, zc + dz, 0.56, PLATE)
        P.wheel(0.24, 3.9, 3.96, zc + dz, 0.56, RAISED, sides=8)
        P.wheel(0.11, 3.96, 3.99, zc + dz, 0.56, LIT, SIDE_GLOW, sides=6)
    for dz in (-0.7, 0.7):
        P.wheel(0.2, 3.7, 3.86, zc + dz, 1.22, PLATE, sides=8)
    # The skirt over the top run of the track, lit slits in it.
    P.slab(1.32, (3.72, 3.9, zc - h + 0.75, zc + h - 0.75), 1.78, (3.72, 3.84, zc - h + 0.55, zc + h - 0.55), RAISED)
    for dz in (-0.9, 0.9):
        P.box((0.06, 0.11, 0.85), (3.875, 1.55, zc + dz), LIT, SIDE_GLOW)


def build(Part):
    body, right = Part(), Part()

    # The hull: a tub with a long sloped glacis, a casemate on it for the turret ring.
    body.extrude([(-5.0, 0.75), (4.5, 0.75), (5.2, 1.25), (5.0, 1.75), (3.0, 2.55), (-4.7, 2.55), (-5.2, 1.9)], -2.3, 2.3, PLATE)
    body.slab(2.55, (-2.0, 2.0, -4.5, 2.6), 3.15, (-1.7, 1.7, -4.1, 1.6), PLATE)
    body.slab(3.15, (-1.3, 1.3, 0.35, 1.45), 3.22, (-1.2, 1.2, 0.45, 1.35), RAISED)
    body.slab(3.15, (-1.5, 1.5, -4.05, -3.3), 3.38, (-1.3, 1.3, -3.95, -3.4), RAISED)  # the engine deck
    for x in (-0.8, 0.0, 0.8):
        body.box((0.5, 0.04, 0.3), (x, 3.39, -3.67), LIT, SIDE_GLOW)

    # The glacis: two plates laid on the slope, a slit in each, the driver's block between them.
    tilt = math.degrees(math.atan2(0.8, 2.0))
    up = (0.0, math.cos(math.radians(tilt)), math.sin(math.radians(tilt)))

    def on_glacis(z, lift):
        y = 1.75 + (5.0 - z) * 0.4
        return (y + up[1] * lift, z + up[2] * lift)
    for x in (1.2,):
        y, z = on_glacis(4.0, 0.05)
        right.box((1.75, 0.12, 1.7), (x, y, z), RAISED, PLAIN, (tilt, 0, 0))
        y, z = on_glacis(4.35, 0.12)
        right.box((1.15, 0.05, 0.15), (x, y, z), LIT, SIDE_GLOW, (tilt, 0, 0))
        y, z = on_glacis(3.55, 0.12)
        right.box((0.5, 0.05, 0.12), (x + 0.3, y, z), LIT, SIDE_GLOW, (tilt, 0, 0))
    y, z = on_glacis(3.5, 0.12)
    body.box((0.5, 0.3, 0.7), (0, y, z), RECESS, PLAIN, (tilt, 0, 0))
    y, z = on_glacis(3.88, 0.14)
    body.box((0.34, 0.12, 0.05), (0, y + 0.03, z), LIT, SIDE_GLOW)

    # The nose: a lit bar and a lamp either side.
    right.box((0.95, 0.15, 0.08), (1.45, 1.5, 5.12), LIT, SIDE_GLOW)
    right.box((0.26, 0.15, 0.08), (0.6, 1.5, 5.12), LAMP, GLOW)
    body.slab(0.85, (-1.7, 1.7, 4.55, 4.9), 1.2, (-1.7, 1.7, 4.9, 5.28), RAISED)  # a lower lip of plate

    # The sides: a fender over the tracks, armour sloping from it up to the deck, slits in the casemate.
    right.slab(1.78, (2.3, 3.86, -5.25, 4.95), 2.2, (2.3, 3.62, -5.05, 4.35), RAISED)
    right.slab(2.2, (2.2, 3.55, -4.95, 4.1), 2.55, (2.2, 2.75, -4.7, 3.0), PLATE)
    lean = math.degrees(math.atan2(0.3, 0.6))
    for z, long in ((-3.0, 0.9), (0.3, 0.9)):
        right.box((0.06, 0.14, long), (1.87, 2.85, z), LIT, SIDE_GLOW, (0, 0, lean))
    for z in (-2.6, 1.4):  # lit seams along the fender's top, for the battle camera overhead
        right.box((0.14, 0.04, 1.5), (3.2, 2.21, z), LIT, SIDE_GLOW)

    # The running gear: two pods a side, a hanging block of armour between them.
    _pod(right, -2.75, 4.6)
    _pod(right, 2.75, 4.6)
    right.slab(0.5, (2.5, 3.78, -0.3, 0.3), 1.78, (2.5, 3.9, -0.62, 0.62), RAISED)
    right.box((0.06, 0.5, 0.14), (3.87, 1.2, 0.0), LIT, SIDE_GLOW, (0, 0, -5))

    # The stern: a plate, two light bars, exhausts.
    body.slab(1.05, (-1.6, 1.6, -5.4, -5.0), 2.0, (-1.6, 1.6, -5.45, -5.05), RAISED)
    right.box((0.9, 0.14, 0.06), (0.85, 1.55, -5.46), LIT, SIDE_GLOW)
    right.box((0.45, 0.32, 0.5), (1.95, 2.3, -5.05), RECESS)
    right.box((0.3, 0.16, 0.06), (1.95, 2.3, -5.31), LIT, SIDE_GLOW)
    body.mirrored(right)

    # --- The turret, from where it turns ---
    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 1.75), (0.22, 1.75)], RECESS, sides=12)
    top.slab(0.2, (-1.85, 1.85, -2.3, 1.7), 1.55, (-1.45, 1.45, -2.0, 0.9), PLATE)
    side.slab(0.3, (1.75, 2.25, -1.9, 1.1), 1.2, (1.6, 2.05, -1.7, 0.6), RAISED)  # cheek armour
    lean = math.degrees(math.atan2(0.2, 0.9))
    side.box((0.06, 0.13, 1.1), (2.17, 0.75, -0.75), LIT, SIDE_GLOW, (0, 0, lean))
    side.box((0.06, 0.13, 0.35), (2.17, 0.75, 0.3), LIT, SIDE_GLOW, (0, 0, lean))
    top.slab(0.3, (-1.5, 1.5, -3.5, -2.2), 1.3, (-1.25, 1.25, -3.3, -2.0), RAISED)  # the bustle
    side.box((0.8, 0.12, 0.08), (0.7, 0.62, -3.43), LIT, SIDE_GLOW)
    top.box((1.4, 0.04, 0.14), (0, 1.32, -2.7), LIT, SIDE_GLOW)
    top.slab(1.55, (-1.1, 1.1, -1.8, 0.5), 1.64, (-1.0, 1.0, -1.7, 0.4), ROOF, PAINT)  # the roof plate, in the side's colour
    side.box((0.12, 0.04, 1.3), (1.27, 1.57, -0.7), LIT, SIDE_GLOW)
    top.lathe((0.5, 1.64, -1.0), (0, 1, 0), [(0, 0.42), (0.26, 0.36)], RAISED, sides=8)  # the cupola
    top.box((0.34, 0.1, 0.06), (0.5, 1.78, -0.62), LIT, SIDE_GLOW)
    top.box((0.5, 0.36, 0.7), (-0.55, 1.82, -1.2), RECESS)  # the sight
    top.box((0.32, 0.16, 0.05), (-0.55, 1.84, -0.83), LIT, SIDE_GLOW)
    side.box((0.36, 0.9, 0.9), (1.02, 0.95, 1.3), PLATE)  # trunnion blocks

    # The gun: mantlet, recoil housing, barrel and brake, all along its line.
    e = math.radians(ELEVATION)
    pivot = (0.0, 0.95, 1.2)
    d = (0.0, math.sin(e), math.cos(e))
    n = (0.0, math.cos(e), -math.sin(e))

    def along(dist, up=0.0, x=0.0):
        return (x, pivot[1] + d[1] * dist + n[1] * up, pivot[2] + d[2] * dist + n[2] * up)
    rot = (-ELEVATION, 0, 0)
    top.box((1.7, 1.25, 1.5), along(0.5), RAISED, PLAIN, rot)
    top.box((1.0, 0.9, 2.0), along(1.9), PLATE, PLAIN, rot)
    top.box((0.14, 0.05, 1.3), along(1.9, 0.47), LIT, SIDE_GLOW, rot)
    side.box((0.05, 0.14, 1.3), along(1.9, 0.0, 0.52), LIT, SIDE_GLOW, rot)
    top.lathe(pivot, d, [(2.9, 0.42), (4.6, 0.42)], PLATE, turn=math.pi / 8)
    top.lathe(pivot, d, [(4.6, 0.5), (5.0, 0.5)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, d, [(5.0, 0.45), (5.1, 0.45)], LIT, SIDE_GLOW, turn=math.pi / 8)
    top.lathe(pivot, d, [(5.1, 0.34), (7.3, 0.34)], PLATE, turn=math.pi / 8)
    top.lathe(pivot, d, [(6.2, 0.42), (6.5, 0.42)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, d, [(7.2, 0.4), (7.3, 0.4)], LIT, SIDE_GLOW, turn=math.pi / 8)
    top.lathe(pivot, d, [(7.3, 0.5), (8.3, 0.5)], RAISED, turn=math.pi / 8)
    top.lathe(pivot, d, [(8.3, 0.3), (8.32, 0.3)], TRACK, turn=math.pi / 8)
    side.box((0.05, 0.14, 0.5), along(7.8, 0.0, 0.48), LIT, SIDE_GLOW, rot)
    top.mirrored(side)

    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": along(8.3)}
