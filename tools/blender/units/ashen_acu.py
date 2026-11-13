"""The Ashen Collective's Armoured Command Unit: a hunched walker of black plate. Heavy legs that
bend forward at the knee over two-toed feet, a chest that widens upward, a hooded head sunk
between the shoulders, and from each shoulder three blades fanned up, out and back. Its right
arm is the cannon, its left the build arm. Its light is the side's colour: a V in the chest and in
the visor, vents down the back, slits in the plating.

The legs and hips are the body; everything from the waist up is the top, so it turns to face what
it shoots at. About 9.6 m wide across the arms and 9.2 m to the top of the head (11 m to the
blades); the server's ACU is 5 m in radius.
"""

import math

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

PLATE = Color(0.19, 0.19, 0.21)  # the armour
RAISED = Color(0.28, 0.28, 0.3)  # plates laid over it
RECESS = Color(0.11, 0.11, 0.12)
ROOF = Color(0.1, 0.1, 0.1)  # painted in the side's colour
LIT = Color(1, 1, 1)

TOP_AT = (0.0, 5.0, 0.0)  # the waist


def _ring(y, x0, x1, z0, z1):
    return [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]


def build(Part):
    body, right = Part(), Part()

    # A leg (the right; the left is its mirror): foot, two toes and a heel, a shin leaning forward
    # to the knee, a thigh leaning back to the hip.
    right.slab(0.0, (1.0, 2.8, -1.3, 1.7), 0.75, (1.25, 2.55, -0.9, 0.9), PLATE)
    for x in (1.05, 1.98):
        right.slab(0.0, (x, x + 0.78, 1.6, 2.7), 0.5, (x + 0.06, x + 0.72, 1.5, 2.1), RAISED)
        right.box((0.4, 0.05, 0.12), (x + 0.39, 0.52, 1.75), LIT, SIDE_GLOW)
    right.slab(0.0, (1.5, 2.3, -1.9, -1.2), 0.55, (1.6, 2.2, -1.5, -1.1), RAISED)
    right.hexa(_ring(0.7, 1.35, 2.45, -0.75, 0.5), _ring(2.7, 1.25, 2.55, 0.1, 1.5), PLATE)  # the shin
    right.hexa(_ring(0.95, 1.5, 2.3, 0.45, 0.72), _ring(2.9, 1.4, 2.4, 1.45, 1.8), RAISED)  # its armour
    lean = math.degrees(math.atan2(1.05, 1.95))
    right.box((0.14, 0.9, 0.06), (1.9, 1.95, 1.3), LIT, SIDE_GLOW, (lean, 0, 0))
    right.hexa(_ring(1.0, 2.45, 2.7, -0.6, 0.4), _ring(2.6, 2.55, 2.8, 0.1, 1.2), RAISED)  # a plate down its outside
    right.box((1.5, 0.9, 1.3), (1.9, 2.85, 0.95), RAISED)  # the knee
    right.wheel(0.42, 1.1, 2.7, 0.95, 2.85, RECESS, sides=8)
    right.wheel(0.16, 2.7, 2.74, 0.95, 2.85, LIT, SIDE_GLOW, sides=6)
    right.hexa(_ring(3.0, 1.25, 2.55, 0.2, 1.5), _ring(4.7, 0.95, 2.45, -1.0, 0.6), PLATE)  # the thigh
    right.hexa(_ring(3.2, 2.5, 2.85, 0.15, 1.3), _ring(4.6, 2.45, 2.8, -0.85, 0.45), RAISED)
    right.line([(0.55, 3.55), (-0.25, 4.3)], 2.86, LIT, wide=0.14)
    right.hexa(_ring(3.3, 1.4, 2.4, 1.3, 1.55), _ring(4.6, 1.2, 2.3, 0.45, 0.75), RAISED)  # and its front plate
    right.wheel(0.75, 0.9, 2.6, -0.2, 4.6, RECESS, sides=8)  # the hip joint

    # The hips: a block between the legs, a plate hanging at the front.
    body.slab(4.1, (-1.4, 1.4, -1.0, 0.9), 5.0, (-1.9, 1.9, -1.15, 1.05), PLATE)
    body.hexa(_ring(3.5, -0.5, 0.5, 0.75, 1.0), _ring(4.9, -0.9, 0.9, 0.95, 1.3), RAISED)
    body.box((0.16, 0.7, 0.06), (0, 4.2, 1.2), LIT, SIDE_GLOW, (-9, 0, 0))
    body.slab(3.9, (-1.0, 1.0, -1.3, -0.9), 4.9, (-1.3, 1.3, -1.45, -1.05), RAISED)
    body.mirrored(right)

    # --- From the waist up, measured from the waist ---
    top, side = Part(), Part()
    top.lathe((0, 0, 0), (0, 1, 0), [(0, 1.05), (0.5, 1.05)], RECESS, sides=8)
    # The torso: a narrow waist widening to broad shoulders, the chest leaning out over the hips.
    top.hexa(_ring(0.4, -1.1, 1.1, -1.0, 1.0), _ring(2.3, -2.5, 2.5, -1.5, 1.9), PLATE)
    top.slab(2.3, (-2.5, 2.5, -1.5, 1.9), 3.0, (-2.1, 2.1, -1.4, 1.2), PLATE)
    top.slab(3.0, (-1.3, 1.3, -1.3, 0.1), 3.08, (-1.2, 1.2, -1.2, 0.0), ROOF, PAINT)  # the back plate, in the side's colour

    def chest(x, y, lift=0.0):  # a point on the chest's leaning front
        return (x, y - 0.428 * lift, 1.0 + (y - 0.4) * 0.474 + 0.904 * lift)
    out = (0.0, -0.428 * 0.2, 0.904 * 0.2)
    # Chest plates: each a blade pointing down and in to the core, a lit line along its lower edge.
    side.prism([chest(0.2, 2.25), chest(2.35, 2.25), chest(2.25, 1.65), chest(0.55, 0.9), chest(0.2, 1.15)], out, RAISED)
    side.beam(chest(2.15, 1.5, 0.2), chest(0.6, 0.8, 0.2), 0.16, 0.08, LIT, face=out)
    side.prism([chest(0.15, 0.95), chest(0.75, 0.6), chest(0.85, 0.42), chest(0.15, 0.42)], (0, -0.04, 0.1), RAISED)  # belly plates
    top.prism([chest(-0.22, 2.2), chest(0.22, 2.2), chest(0.22, 1.3), chest(0.0, 1.05), chest(-0.22, 1.3)], (0, -0.13, 0.28), RECESS)  # the core's housing
    top.beam(chest(0, 2.0, 0.31), chest(0, 1.35, 0.31), 0.14, 0.06, LIT, face=out)
    # The reactor on its back, three vents down it.
    top.hexa(_ring(0.7, -1.2, 1.2, -2.2, -1.2), _ring(2.8, -1.3, 1.3, -2.3, -1.4), RAISED)
    for x in (-0.7, 0.0, 0.7):
        top.box((0.26, 1.5, 0.1), (x, 1.8, -2.27), LIT, SIDE_GLOW, (-3, 0, 0))

    # The head: a hood sunk into the shoulders. From the front an arrowhead, broad at the brow and
    # down to a point at the chin; from the side a beak thrust forward, its crest running back.
    crown = [(-0.5, 3.2), (0.8, 2.4), (2.2, 2.2), (2.8, 3.3), (1.9, 4.1), (0.3, 4.25)]
    brow = [(-0.3, 3.2), (0.8, 3.0), (1.7, 3.0), (2.0, 3.45), (1.5, 3.9), (0.3, 3.95)]
    top.extrude(crown, -0.3, 0.3, PLATE)
    side.extrude(crown, 0.3, 1.15, PLATE, profile1=brow)
    top.box((0.2, 0.3, 1.5), (0, 4.2, 1.0), RAISED, PLAIN, (8, 0, 0))  # the crest
    side.beam((0.98, 3.25, 2.13), (0.1, 2.58, 2.5), 0.24, 0.12, LIT, face=(0.4, -0.3, 1))  # the visor: a lit V down the face

    # A shoulder: a block over the arm, and three blades fanned up and out from it, each leaning
    # back as it rises: a short one in front, the long one over the arm, a tall one behind the head.
    side.hexa(_ring(1.8, 2.3, 4.5, -1.3, 1.3), _ring(3.0, 2.2, 4.0, -1.1, 1.0), RAISED)
    side.hexa(_ring(0.9, 4.45, 4.8, -1.1, 1.1), _ring(2.9, 4.1, 4.5, -1.3, 1.3), PLATE)  # a shield plate down over the upper arm
    side.line([(0.0, 1.2), (0.0, 1.8)], 4.76, LIT, wide=0.16, proud=0.1)

    def blade(points, z0, lean, thick, colour):
        side.prism([(x, y, z0 - (y - points[0][1]) * lean) for x, y in points], (0, 0, -thick), colour)
    blade([(2.0, 2.3), (4.5, 2.1), (5.0, 2.9), (4.6, 4.2), (3.1, 3.3)], 1.25, 0.45, 0.4, RAISED)
    blade([(2.2, 2.7), (4.7, 2.5), (5.35, 3.5), (5.0, 5.3), (3.5, 4.0), (2.4, 3.5)], 0.45, 0.5, 0.5, PLATE)
    blade([(1.3, 2.9), (3.1, 3.0), (3.9, 6.0), (2.3, 4.4)], -0.7, 0.35, 0.45, PLATE)
    side.beam((4.55, 2.45, 1.2), (4.75, 3.0, 0.97), 0.14, 0.06, LIT)  # lit edges on the blades
    side.beam((4.95, 3.0, 0.24), (5.05, 4.3, -0.4), 0.16, 0.06, LIT)
    side.beam((3.6, 3.2, 1.0), (2.5, 2.75, 1.2), 0.14, 0.06, LIT)
    side.box((1.2, 0.05, 0.18), (3.2, 3.02, -0.5), LIT, SIDE_GLOW)  # lit seam on top, for the camera overhead
    # The upper arm, hanging from it.
    side.box((1.15, 2.3, 1.25), (3.75, 0.95, 0.0), PLATE)
    side.wheel(0.55, 3.05, 4.45, 0.1, -0.25, RECESS, sides=8)  # the elbow
    top.mirrored(side)

    # The forearms, carried forward and a little down. Right: the cannon. Left: the build arm.
    drop = 18.0
    d = (0.0, -math.sin(math.radians(drop)), math.cos(math.radians(drop)))
    n = (0.0, math.cos(math.radians(drop)), math.sin(math.radians(drop)))
    elbow = (3.75, -0.25, 0.1)

    def along(dist, up=0.0, x=0.0, sign=1):
        return (sign * (elbow[0] + x), elbow[1] + d[1] * dist + n[1] * up, elbow[2] + d[2] * dist + n[2] * up)
    rot = (drop, 0, 0)
    top.box((1.55, 1.5, 3.4), along(1.5), PLATE, PLAIN, rot)
    top.box((0.12, 1.0, 2.3), along(1.6, 0.0, 0.8), RAISED, PLAIN, rot)
    top.box((0.06, 0.2, 1.5), along(1.6, 0.0, 0.88), LIT, SIDE_GLOW, rot)
    top.box((0.9, 0.12, 2.3), along(1.6, 0.8), RAISED, PLAIN, rot)
    top.box((0.2, 0.06, 1.5), along(1.6, 0.88), LIT, SIDE_GLOW, rot)
    gun = along(0.0)
    top.lathe(gun, d, [(3.2, 0.62), (3.6, 0.62)], RAISED, turn=math.pi / 8)
    top.lathe(gun, d, [(3.6, 0.46), (4.7, 0.46)], RECESS, turn=math.pi / 8)
    top.lathe(gun, d, [(4.7, 0.56), (5.2, 0.56)], RAISED, turn=math.pi / 8)
    top.lathe(gun, d, [(5.2, 0.38), (5.26, 0.38)], LIT, SIDE_GLOW, turn=math.pi / 8)  # the lit muzzle
    muzzle = along(5.26)

    top.box((1.4, 1.35, 2.8), along(1.2, sign=-1), PLATE, PLAIN, rot)
    top.box((0.12, 0.9, 1.9), along(1.3, 0.0, 0.73, sign=-1), RAISED, PLAIN, rot)
    top.box((0.06, 0.2, 1.2), along(1.3, 0.0, 0.81, sign=-1), LIT, SIDE_GLOW, rot)
    top.box((0.9, 0.9, 0.5), along(2.8, sign=-1), RECESS, PLAIN, rot)  # the wrist
    for x in (-0.42, 0.42):  # two prongs, the emitter lit between them
        top.box((0.22, 0.7, 1.5), along(3.6, 0.0, x, sign=-1), RAISED, PLAIN, rot)
    top.box((0.4, 0.4, 0.5), along(3.2, sign=-1), LIT, SIDE_GLOW, rot)

    views = {
        "front": ((-15, -21, 9.5), (0.5, 0, 4.9), 50, 0.0, (60, 0, 70)),
        "rear": ((14, 21, 9.0), (0, 0, 4.9), 50, 0.0),
        "side": ((-34, 0, 5.0), (0, 0, 5.0), 60, 0.0, (40, 0, -60)),
        "head_on": ((0, -34, 5.2), (0, 0, 5.0), 60, 0.0),
        "top": ((0, -1.0, 46), (0, -0.9, 0), 62, math.pi / 2, (30, 0, 200)),
    }
    return {"body": body, "top": top, "top_at": TOP_AT, "muzzle": muzzle, "views": views}
