"""The Luminar Accord's mobile AA (Rev 2), all three marks: a crewed hover skimmer. An angular
chamfered wedge of a hull on a sheet of light, a faceted glass canopy in a brass frame, and a
turret of an octagonal drum under a pyramid roof with a quad box launcher on an arm either side,
pointing at the sky. No forward gun. Mk II adds a launcher pod on a sponson either side of the
hull; Mk III raises a second hull tier, hangs two 8-tube launchers on each side, trades the quad
launchers for twin flak cannons and adds a three-tier drum and a bladed radar mast.
Its light is the side's colour.

About 4.2 m wide and 6.6 m long at Mk I (the server's AA is 3 m in radius).
"""

from units.accord_kit import *  # noqa: F401,F403

HULL = [(-3.0, 1.15, 1.75, 0.5), (-2.5, 1.2, 2.05, 0.6), (0.9, 1.2, 2.0, 0.6), (2.5, 1.0, 1.3, 0.45), (3.5, 0.85, 0.5, 0.22)]
GLASS_AT = [(0.3, 1.75, 0.95, 0.3), (1.6, 1.68, 0.8, 0.2), (2.35, 1.5, 0.45, 0.04)]


def make(Part, tier):
    body, right, top, top_r = Part(), Part(), Part(), Part()
    loft(body, HULL, CERAMIC, PLAIN, WEDGE)
    underglow(body, HULL, WEDGE, 0.24)
    for z in (-2.2, 0.2, 2.3):
        band(body, HULL, z, 0.12, WEDGE)
    for k in (0, 1, 7):
        seam(body, HULL, WEDGE, k, 0.04)
    seam(right, HULL, WEDGE, 1, 0.05, LIT, SIDE_GLOW, t=0.5, z0=-2.4, z1=2.2)
    loft(body, GLASS_AT, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, GLASS_AT, CANOPY, k, 0.03)
    deck = 1.8
    if tier >= 3:  # a raised second tier behind the canopy
        upper = [(-2.8, 2.0, 1.6, 0.25), (-2.4, 2.05, 1.75, 0.3), (0.0, 2.05, 1.7, 0.3), (0.6, 1.95, 1.3, 0.2)]
        loft(body, upper, CERAMIC, PLAIN, OCT)
        band(body, upper, -1.2, 0.1, OCT)
        seam(right, upper, OCT, 1, 0.04, LIT, SIDE_GLOW, t=0.5, z0=-2.2, z1=-0.1)
        deck = 2.3
    drum(body, (0, deck - 0.2, -1.0), 1.15, 0.22, SHADE)  # the turret's ring
    if tier >= 2:  # launchers on sponsons either side
        right.slab(0.9, (1.7, 2.35, -1.6, 0.4), 1.5, (1.7, 2.3, -1.5, 0.3), CERAMIC)
        right.box((0.06, 0.64, 2.0), (2.36, 1.2, -0.6), BRASS)
        if tier == 2:
            launcher(right, (2.45, 1.55, -0.3), (0, 0, 1), 2, 2, 0.3, 1.3)
        else:
            for y in (1.4, 2.0):
                launcher(right, (2.55, y, -0.4), (0, 0, 1), 4, 2, 0.22, 1.5)
    # The turret: an octagonal drum under a pyramid roof.
    chapel(top, (0, 0.0, 0), 0.82, 0.55, tiers=3 if tier >= 3 else 1, roof=0.75, shrink=0.8)
    if tier < 3:  # a quad launcher on an arm either side, pointing at the sky
        top_r.box((0.5, 0.18, 0.5), (0.95, 0.3, 0.0), OLD)
        top_r.slab(0.2, (0.95, 1.25, -0.3, 0.3), 0.85, (1.0, 1.2, -0.15, 0.15), CERAMIC)
        launcher(top_r, (1.38, 1.15, 0.1), (0, 0.8, 0.6), 2, 2, 0.32, 1.25)
        muzzle = (1.38, 1.15 + 0.8 * 0.7, 0.1 + 0.6 * 0.7)
    else:  # twin flak cannons either side, a bladed radar mast behind
        top_r.box((0.5, 0.5, 0.6), (1.05, 0.45, 0.1), CERAMIC)
        top_r.box((0.54, 0.08, 0.64), (1.05, 0.72, 0.1), BRASS)
        for x in (0.93, 1.17):
            muzzle = hexgun(top_r, (x, 0.65, 0.3), (0, 0.6, 0.8), 1.5, 0.08)
        top.box((0.18, 1.1, 0.18), (0, 2.0, -0.75), CERAMIC)
        fin(top, (0, 2.0, -0.6), (0.0, 2.85, -1.0), 0.7, 0.25, 0.08)
        for s in (-1, 1):
            fin(top, (0, 2.35, -0.65), (s * 0.55, 2.75, -0.95), 0.4, 0.15, 0.06)
    top.mirrored(top_r)
    body.mirrored(right)
    top_at = (0.0, deck, -1.0)
    return {"body": body, "top": top, "top_at": top_at, "muzzle": muzzle, "view": 0.95 + 0.07 * tier}


def build(Part):
    return make(Part, 1)
