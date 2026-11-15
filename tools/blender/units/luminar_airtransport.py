"""The Luminar Accord's air troop transport (Rev 2, provisional): a crewed lift transport. An angular,
boxy faceted hull with a glazed nose, a nave of pointed-arch windows down each flank, a faceted
dome on its back, four octagonal fan pods (two under the hull forward, two high on arms at the
stern), a chin beam gun, and a boarding ramp let down from its right side. Its light is the side's
colour.

About 15 m long. The origin is its middle: aircraft are placed at their flying height.
"""

from units.accord_kit import *  # noqa: F401,F403

HULL = [(-6.6, 0.6, 1.3, 1.1), (-5.8, 0.4, 1.9, 1.6), (3.2, 0.4, 1.95, 1.65), (5.6, 0.05, 1.5, 1.25), (7.0, -0.25, 0.6, 0.55)]
GLAZE = [(4.0, 1.25, 1.35, 0.32), (5.6, 0.85, 1.05, 0.26), (6.55, 0.35, 0.55, 0.06)]


def pod(P, at, r=0.85, h=1.0):
    """An octagonal fan pod: a faceted drum banded in brass, a tapered cap, light underneath."""
    x, y, z = at
    drum(P, (x, y - h / 2, z), r, h)
    drum(P, (x, y - h / 2 - 0.2, z), r * 0.8, 0.2, CERAMIC, r1=r)
    drum(P, (x, y + h / 2, z), r, 0.25, CERAMIC, r1=r * 0.7)
    for yy in (y - h * 0.3, y + h * 0.3):
        drum(P, (x, yy, z), r * 1.04, 0.1, BRASS)
    drum(P, (x, y - h / 2 - 0.24, z), r * 0.55, 0.04, LIT, SIDE_GLOW)


def build(Part):
    body, right = Part(), Part()
    loft(body, HULL, CERAMIC, PLAIN, OCT)
    for z in (-5.0, -2.6, -0.2, 2.2, 4.4):
        band(body, HULL, z, 0.16, OCT)
    for k in (0, 1, 2, 7):
        seam(body, HULL, OCT, k, 0.05)
    seam(right, HULL, OCT, 2, 0.06, LIT, SIDE_GLOW, t=0.5, z0=-5.4, z1=4.2)
    loft(body, GLAZE, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, GLAZE, CANOPY, k, 0.035)
    # The nave: pointed-arch windows down each flank, lit sills.
    for z in (-1.8, -0.6, 0.6, 1.8, 3.0):
        arch(right, (1.96, 0.5, z), (1, 0, 0), 0.55, 1.1)
        right.box((0.04, 0.07, 0.5), (1.98, 0.42, z), LIT, SIDE_GLOW)
    # The dome on its back.
    chapel(body, (0, 2.05, -0.8), 1.25, 0.6, tiers=1, roof=0.55, lit=True)
    # Fan pods: two under the hull forward, two high on arms at the stern.
    right.box((0.4, 1.0, 0.5), (1.3, -1.6, 2.8), OLD)
    pod(right, (1.9, -2.5, 2.8))
    right.beam((1.8, 1.2, -4.6), (3.4, 1.4, -4.8), 0.4, 0.4, CERAMIC, PLAIN, face=(0, 1, 0))
    pod(right, (3.8, 1.4, -4.8))
    pod(body, (-1.9, -2.5, -2.4))
    body.box((0.4, 1.0, 0.5), (-1.3, -1.6, -2.4), OLD)
    pod(body, (1.9, -2.5, -2.4))
    body.box((0.4, 1.0, 0.5), (1.3, -1.6, -2.4), OLD)
    # The ramp, let down from the right side aft, lit along its edges.
    ramp = [(2.0, -0.9, -3.0), (2.0, -0.9, -4.8), (4.2, -2.6, -4.8), (4.2, -2.6, -3.0)]
    body.prism(ramp, (0, 0.12, 0), SHADE)
    body.trace([ramp[0], ramp[3]], 0.1, 0.1, LIT, SIDE_GLOW, face=(0, 1, 0))
    body.trace([ramp[1], ramp[2]], 0.1, 0.1, LIT, SIDE_GLOW, face=(0, 1, 0))
    body.box((0.06, 1.6, 1.8), (2.0, -0.1, -3.9), WORKS)  # the open door
    # The chin beam gun.
    body.box((0.7, 0.5, 0.8), (0, -1.15, 5.4), GUN)
    hexgun(body, (0, -1.2, 5.7), (0, 0, 1), 1.0, 0.12)
    body.mirrored(right)
    fly = 12.0
    return {"body": body, "top": None, "top_at": (0, 0, 0), "views": air_views(fly, 1.15), "fly": fly, "span": 3.0}
