"""The Luminar Accord's troop carrier (Rev 2): a crewed amphibious hover carrier. A faceted
chamfered hull on a sheet of light, a glazed cab forward under a small faceted turret with a light
beam gun, an open troop bay behind spanned by three pointed arches in brass, a tall ramp frame at
the stern lit along its inside, and the braided-knot lozenge on each flank. Its light is the
side's colour.

About 4.4 m wide and 8.4 m long (the server's carrier is 4 m in radius).
"""

from units.accord_kit import *  # noqa: F401,F403

HULL = [(-4.0, 1.25, 2.0, 0.72), (-3.6, 1.3, 2.2, 0.8), (1.4, 1.3, 2.2, 0.8), (3.4, 1.05, 1.5, 0.6), (4.4, 0.85, 0.6, 0.3)]
CAB = [(-0.1, 2.3, 1.75, 0.32), (1.1, 2.32, 1.7, 0.32), (2.6, 2.12, 1.1, 0.12)]
GLAZE = [(1.1, 2.4, 1.6, 0.26), (2.2, 2.28, 1.25, 0.16), (2.75, 2.12, 0.75, 0.02)]


def build(Part):
    body, right, top = Part(), Part(), Part()
    loft(body, HULL, CERAMIC, PLAIN, OCT)
    underglow(body, HULL, OCT, 0.26)
    for z in (-3.0, 0.0, 2.6):
        band(body, HULL, z, 0.14, OCT)
    for k in (0, 1, 2, 7):
        seam(body, HULL, OCT, k, 0.045)
    seam(right, HULL, OCT, 1, 0.06, LIT, SIDE_GLOW, t=0.55, z0=-3.6, z1=3.0)
    lozenge(right, (2.23, 1.42, -1.4), (1, 0, 0), 0.5)
    # The cab, glazed in a brass frame, the turret's seat on its roof.
    loft(body, CAB, CERAMIC, PLAIN, OCT)
    loft(body, GLAZE, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, GLAZE, CANOPY, k, 0.03)
    drum(body, (0, 2.6, 0.5), 0.75, 0.16, BRASS)
    # The troop bay: low side walls and three pointed arches across it.
    right.slab(2.05, (1.6, 2.1, -3.5, -0.1), 2.6, (1.65, 2.05, -3.45, -0.15), CERAMIC)
    right.box((0.5, 0.06, 3.4), (1.85, 2.62, -1.8), BRASS)
    body.box((3.2, 0.06, 3.4), (0, 2.08, -1.8), WORKS)
    for z in (-0.7, -1.75, -2.8):
        right.trace([(1.85, 2.55, z), (1.85, 2.95, z), (1.2, 3.35, z), (0.0, 3.55, z)], 0.24, 0.26, BRASS, PLAIN, face=(0, 0, 1))
    # The ramp frame at the stern, leaning back, lit inside.
    frame_pts = [(1.85, 2.1, -3.55), (1.85, 3.2, -3.85), (1.3, 3.75, -4.0), (0.0, 3.9, -4.05)]
    right.trace(frame_pts, 0.3, 0.32, CERAMIC, PLAIN, face=(0, 0.25, 1))
    right.trace([(x - 0.18 if x > 0.1 else x, y - 0.12, z + 0.02) for x, y, z in frame_pts], 0.08, 0.1, LIT, SIDE_GLOW, face=(0, 0.25, 1))
    right.trace([(1.85, 2.6, -2.8), (1.85, 3.2, -3.85)], 0.2, 0.2, BRASS, PLAIN, face=(1, 0, 0))
    for x in (-1.2, 1.2):  # lamps at the stern
        body.lathe((x, 1.1, -4.02), (0, 0, -1), [(0, 0.22), (0.04, 0.22)], LIT, SIDE_GLOW, 6)
    # The turret: a faceted drum under a pyramid, a light beam gun.
    drum(top, (0, 0, 0), 0.6, 0.32)
    drum(top, (0, 0.3, 0), 0.64, 0.06, BRASS)
    pyramid(top, (0, 0.36, 0), 0.6, 0.38)
    top.box((0.34, 0.3, 0.4), (0, 0.2, 0.62), CERAMIC)
    muzzle = hexgun(top, (0, 0.2, 0.75), (0, 0, 1), 1.1, 0.09)
    body.mirrored(right)
    return {"body": body, "top": top, "top_at": (0.0, 2.76, 0.5), "muzzle": muzzle, "view": 1.0}
