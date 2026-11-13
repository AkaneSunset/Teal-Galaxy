"""The Ashen Collective's experimental walker: a huge domed carapace of overlapping black shells
carried high on eight scythe legs, a single lit eye in its face and missile racks down
its back. The eye is its main weapon, a laser, so it has no turret: the whole walker turns to face
what it burns; the racks fire salvos at crowds of lighter units. Its light is the side's
colour: the eye, seams between the shells, a line down each leg's blade, vents at the back.

About 19 m long in the body, 12 m to the top of the carapace, and 34 m across the feet.
"""

import math

from mathutils import Vector

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT

PLATE = Color(0.19, 0.19, 0.21)  # the armour
RAISED = Color(0.28, 0.28, 0.3)  # plates laid over it
RECESS = Color(0.11, 0.11, 0.12)
ROOF = Color(0.1, 0.1, 0.1)  # painted in the side's colour
LIT = Color(1, 1, 1)

EYE = (0.0, 6.9, 9.75)  # where the laser leaves

# The carapace from the side, front to the right: (z, y) over the back, then along the belly.
ARCH = [(-9.0, 6.4), (-8.6, 8.4), (-6.2, 10.7), (-2.0, 12.0), (2.0, 12.0), (5.4, 10.7), (7.6, 8.6), (8.2, 6.6)]
BELLY = [(6.4, 5.4), (-7.2, 5.4)]


def _shell(s):
    """The carapace's profile shrunk by `s` toward the middle of its belly."""
    return [(-0.4 + (z + 0.4) * s, 5.4 + (y - 5.4) * s) for z, y in ARCH] + [(-0.4 + (z + 0.4) * s, y) for z, y in BELLY]


def _leg(P, hip_z, turn, reach, rise):
    """One right leg: out from the hull to a knee high over it, then a long blade curving down to a
    point on the ground. `turn` is degrees forward of straight out."""
    out = Vector((math.cos(math.radians(turn)), 0, math.sin(math.radians(turn))))
    up = Vector((0, 1, 0))
    axis = out.cross(up).normalized()  # across the leg
    hip = Vector((4.6, 7.0, hip_z))
    knee = hip + out * 5.2 + up * rise
    foot = Vector((hip.x + out.x * reach, 0.0, hip.z + out.z * reach))
    P.lathe(hip - out * 1.6, out, [(0, 1.35), (1.7, 1.35)], RECESS, sides=8)  # the hip, in the hull's side
    P.beam(hip, knee, 1.5, 1.9, PLATE, PLAIN, face=up, wide1=1.3, deep1=1.6)
    thigh = (knee - hip).normalized()
    over = axis.cross(thigh).normalized()
    if over.y < 0:
        over = -over
    P.beam(hip + thigh * 0.8 + over * 0.95, knee - thigh * 0.5 + over * 0.85, 1.7, 0.4, RAISED, PLAIN, face=over)  # armour along its top
    P.beam(hip + thigh * 1.6 + over * 1.17, knee - thigh * 1.4 + over * 1.07, 0.2, 0.08, LIT, SIDE_GLOW, face=over)
    P.lathe(knee - axis * 1.0, axis, [(0, 1.15), (2.0, 1.15)], RECESS, sides=8)  # the knee
    P.lathe(knee - axis * 1.06, axis, [(0, 0.4), (2.12, 0.4)], LIT, SIDE_GLOW, sides=6)
    # The blade: two lengths, bowed outward, down to a point.
    run = (foot - knee).normalized()
    bow = axis.cross(run).normalized()
    if bow.y < 0:
        bow = -bow
    mid = knee.lerp(foot, 0.48) + bow * 1.5
    P.beam(knee, mid, 1.4, 2.6, PLATE, PLAIN, face=bow, wide1=1.05, deep1=1.9)
    P.beam(mid, foot, 1.05, 1.9, PLATE, PLAIN, face=bow, wide1=0.16, deep1=0.24)
    P.beam(knee + bow * 1.2 - run * 0.9, mid + bow * 0.95 + run * 1.4, 1.65, 0.55, RAISED, PLAIN, face=bow, wide1=1.2, deep1=0.4)  # a guard over its shoulder
    for sign in (-1, 1):  # a lit line down each face of the blade
        a = mid + axis * sign * 0.56 - run * 2.0
        b = mid.lerp(foot, 0.88) + axis * sign * 0.17
        P.beam(a, b, 0.34, 0.08, LIT, SIDE_GLOW, face=axis * sign, wide1=0.1, deep1=0.06)


def build(Part):
    body, right = Part(), Part()

    # The carapace: a painted spine down the middle, and three shells a side stepping down from
    # it, each tucked under the one above, a lit seam showing in every step.
    body.extrude(_shell(1.035), -0.7, 0.7, ROOF, PAINT)
    for x0, x1, s0, s1, colour in ((0.7, 2.6, 1.0, 0.93, PLATE), (2.6, 4.4, 0.89, 0.78, RAISED), (4.4, 6.0, 0.74, 0.55, PLATE)):
        right.extrude(_shell(s0), x0, x1, colour, profile1=_shell(s1))
    for x, s in ((2.6, 0.912), (4.4, 0.762)):
        right.extrude(_shell(s), x - 0.08, x + 0.07, LIT, SIDE_GLOW)
    # Missile racks along the back, four a side on the first shell: each a block lying on the
    # curve, four tubes in its top with a missile's lit tip in every one.
    for z in (-5.3, -2.65, 0.0, 2.65):
        i = max(k for k in range(len(ARCH) - 1) if ARCH[k][0] <= z)
        (z0, y0), (z1, y1) = ARCH[i], ARCH[i + 1]
        y = 5.4 + (y0 + (y1 - y0) * (z - z0) / (z1 - z0) - 5.4) * 0.955
        tilt = -math.degrees(math.atan2(y1 - y0, z1 - z0)) * 0.955
        fwd = Vector((0, -math.sin(math.radians(tilt)), math.cos(math.radians(tilt))))
        up = Vector((0, fwd.z, -fwd.y))
        at = Vector((1.65, y, z))
        right.box((1.5, 0.7, 2.0), at + up * 0.2, RAISED, PLAIN, (tilt, 0, 0))
        for dx in (-0.36, 0.36):
            for dz in (-0.48, 0.48):
                c = at + Vector((dx, 0, 0)) + fwd * dz
                right.box((0.52, 0.06, 0.7), c + up * 0.56, RECESS, PLAIN, (tilt, 0, 0))
                right.box((0.3, 0.1, 0.42), c + up * 0.6, LIT, SIDE_GLOW, (tilt, 0, 0))

    # Under it: the belly, hung lower between the legs.
    body.slab(4.3, (-2.6, 2.6, -5.5, 4.5), 5.5, (-3.8, 3.8, -7.0, 6.2), RECESS)
    for z in (-3.0, 0.0, 3.0):
        right.box((1.6, 0.06, 0.5), (1.4, 4.28, z), LIT, SIDE_GLOW)

    # The face, under the carapace's brow: a wedge of plate around the eye, a fang either side.
    body.hexa([(-2.0, 5.0, 7.0), (2.0, 5.0, 7.0), (1.0, 5.4, 9.5), (-1.0, 5.4, 9.5)],
              [(-2.2, 8.6, 7.0), (2.2, 8.6, 7.0), (1.2, 8.2, 9.6), (-1.2, 8.2, 9.6)], RAISED)
    body.prism([(-0.75, 7.9, 9.62), (0.75, 7.9, 9.62), (1.0, 7.0, 9.6), (0.0, 5.7, 9.55), (-1.0, 7.0, 9.6)], (0, 0, 0.14), LIT, SIDE_GLOW)  # the eye
    right.prism([(0.95, 8.1, 9.62), (1.5, 8.2, 9.3), (1.6, 6.9, 9.3), (0.35, 5.3, 9.5), (1.2, 6.9, 9.62)], (0.1, 0, 0.3), PLATE)  # its lids
    right.beam((1.6, 5.6, 8.6), (0.8, 3.3, 9.6), 0.8, 0.9, RAISED, PLAIN, face=(1, 0, 0), wide1=0.12, deep1=0.14)
    right.beam((1.95, 5.2, 8.7), (1.2, 3.75, 9.35), 0.1, 0.3, LIT, SIDE_GLOW, face=(1, 0, 0), wide1=0.06, deep1=0.1)
    right.beam((2.6, 7.6, 7.3), (1.5, 7.9, 9.3), 0.5, 0.1, LIT, SIDE_GLOW, face=(1, 0, 0.5))  # a slit back along each cheek

    # The stern: a core housing, lit vents up it.
    body.hexa([(-1.6, 5.2, -9.6), (1.6, 5.2, -9.6), (2.0, 5.2, -7.5), (-2.0, 5.2, -7.5)],
              [(-1.3, 8.8, -9.4), (1.3, 8.8, -9.4), (1.8, 9.2, -7.5), (-1.8, 9.2, -7.5)], RAISED)
    for y in (5.9, 6.7, 7.5, 8.3):
        body.box((1.5, 0.4, 0.12), (0, y, -9.56), LIT, SIDE_GLOW, (3, 0, 0))

    # Eight legs: the front pair reaching forward, the back pair trailing.
    _leg(right, 5.2, 48, 13.5, 4.6)
    _leg(right, 1.8, 16, 12.5, 5.2)
    _leg(right, -1.8, -16, 12.5, 5.2)
    _leg(right, -5.4, -48, 13.5, 4.6)
    body.mirrored(right)

    views = {
        "front": ((-34, -46, 22), (0, 0, 6.0), 50, 0.0, (60, 0, 70)),
        "rear": ((32, 46, 20), (0, 0, 6.0), 50, 0.0),
        "side": ((-80, 0, 8.0), (0, 0, 6.0), 60, 0.0, (40, 0, -60)),
        "head_on": ((0, -80, 9.0), (0, 0, 6.0), 60, 0.0),
        "top": ((0, -1.0, 150), (0, -0.9, 0), 62, math.pi / 2, (30, 0, 200)),
    }
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": EYE, "views": views, "span": 22.0}
