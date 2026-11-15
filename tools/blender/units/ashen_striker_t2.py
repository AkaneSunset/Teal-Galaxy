"""The Ashen Collective's assault walkers, Mk II and III (Mk I is ashen_striker.py): big blocky
two-legged walkers in layered faceted plate, a low head with a lit visor slit, the emblem lit on the
chest, weapons for forearms and rocket pods on the shoulders.

Mk II: twin rotary pulse guns, one rocket pod. Mk III: a 50 mm rail cannon arm and a rotary arm,
two pods, heavier plate. The legs and hips are the body; from the waist up is the top, so it turns
to face what it shoots. About 4.6 and 5.4 m tall.
"""

from units.ashen_kit import *  # noqa: F401,F403

SIZE = {2: 1.0, 3: 1.15}
WAIST = 2.55


def make(Part, tier):
    body, top, right_b, right_t = Part(), Part(), Part(), Part()
    # The legs: thick thighs, knees forward, heavy shins and wide feet.
    right_b.box((0.75, 0.55, 0.8), (0.75, 2.35, 0.0), PLATE)  # hip
    right_b.box((0.62, 1.15, 0.72), (0.8, 1.75, 0.18), PLATE, PLAIN, (-14, 0, 0))  # thigh
    right_b.box((0.72, 0.7, 0.62), (0.8, 1.18, 0.45), RAISED)  # knee
    right_b.box((0.66, 1.1, 0.78), (0.8, 0.62, 0.1), PLATE, PLAIN, (8, 0, 0))  # shin
    right_b.box((0.8, 0.24, 1.35), (0.8, 0.12, 0.2), PLATE)  # foot
    right_b.box((0.5, 0.08, 0.05), (0.8, 1.2, 0.77), LIT, SIDE_GLOW)
    body.box((1.0, 0.5, 0.75), (0, WAIST - 0.15, 0), RECESS)
    # The torso: a wide faceted chest, layered plates, the emblem, the visor slit in a low head.
    top.slab(0.0, (-1.0, 1.0, -0.6, 0.55), 0.4, (-1.15, 1.15, -0.75, 0.75), PLATE)
    top.slab(0.4, (-1.15, 1.15, -0.75, 0.75), 1.5, (-1.0, 1.0, -0.7, 0.6), PLATE)
    top.slab(1.5, (-1.0, 1.0, -0.7, 0.6), 1.85, (-0.7, 0.7, -0.5, 0.35), PLATE)
    top.slab(0.6, (-0.75, 0.75, 0.55, 0.62), 1.3, (-0.6, 0.6, 0.55, 0.68), RAISED)
    hexagon(top, (0, 0.95, 0.72), 0.26, (0, 0, 1))
    top.slab(1.7, (-0.45, 0.45, -0.2, 0.75), 2.25, (-0.4, 0.4, -0.1, 0.62), RAISED)  # head
    top.box((0.62, 0.1, 0.05), (0, 2.02, 0.71), LIT, SIDE_GLOW)
    if tier >= 3:
        top.slab(1.85, (-0.7, 0.7, -0.75, -0.2), 2.2, (-0.6, 0.6, -0.7, -0.3), RAISED)
    # Shoulders and upper arms.
    right_t.box((0.75, 0.75, 0.95), (1.45, 1.35, 0.0), RAISED)
    right_t.box((0.5, 0.75, 0.55), (1.5, 0.75, 0.05), PLATE)
    # The weapon arms: a rotary pulse gun (right; both at Mk II), a rail cannon (left at Mk III).
    def rotary_arm(P, sx):
        P.box((0.62, 0.62, 1.4), (sx * 1.5, 0.3, 0.55), PLATE)
        for dy in ((0.12, -0.26) if tier == 2 else (0.0,)):
            rotary(P, (sx * 1.5, 0.3 + dy, 1.2), 1.6, 0.17)
    rotary_arm(right_t, 1)
    if tier == 2:
        rotary_arm(top, -1)
    else:
        top.box((0.62, 0.62, 1.6), (-1.5, 0.3, 0.6), PLATE)
        gun(top, (-1.5, 0.3, 1.4), 2.2, 0.15)
        top.box((0.75, 0.75, 0.95), (-1.45, 1.35, 0.0), RAISED)
        top.box((0.5, 0.75, 0.55), (-1.5, 0.75, 0.05), PLATE)
    if tier == 2:
        top.box((0.75, 0.75, 0.95), (-1.45, 1.35, 0.0), RAISED)
        top.box((0.5, 0.75, 0.55), (-1.5, 0.75, 0.05), PLATE)
    # Rocket pods on the shoulders: one (the left) at Mk II, both at Mk III.
    pods = (-1,) if tier == 2 else (-1, 1)
    for sx in pods:
        cells(top, (sx * 1.15, 2.2, 0.0), 3, 3 if tier == 3 else 2, 0.26)
    body.mirrored(right_b)
    top.mirrored(right_t) if False else top.extend(right_t)
    k = SIZE[tier]
    muzzle = (1.5 * k, 0.3 * k, 2.85 * k) if tier == 2 else (-1.5 * k, 0.3 * k, 3.65 * k)
    return {"body": scaled(body, k), "top": scaled(top, k), "top_at": (0, WAIST * k, 0), "muzzle": muzzle, "view": 0.8 * k}


def build(Part):
    return make(Part, 2)
