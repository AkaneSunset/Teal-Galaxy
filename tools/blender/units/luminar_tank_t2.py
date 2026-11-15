"""The Luminar Accord's Undertow light tank, Mk II and Mk III (Rev 2): a hover skimmer tank. A
wide, chamfered hex-section hull on a sheet of light, brass at its seams, dark vents at the prow; a
gem-cut faceted turret with twin hex beam barrels and an octagonal commander's cupola. Mk III
raises a second hull tier, hangs a boxy sponson gun on each flank, mounts a heavier twin cannon and
a two-tier cupola. Its light is the side's colour.

About 6.2 m wide and 8.6 m long at Mk II, 7 m by 9.6 m at Mk III (the server's tank is 4 m in
radius).
"""

from units.accord_kit import *  # noqa: F401,F403

HULL = [(-3.6, 1.3, 2.4, 0.72), (-3.0, 1.35, 2.85, 0.85), (1.6, 1.35, 2.9, 0.85), (3.3, 1.15, 2.2, 0.65), (4.0, 0.95, 1.2, 0.35)]
UPPER = [(-3.2, 2.38, 2.15, 0.22), (-2.8, 2.4, 2.3, 0.26), (1.6, 2.4, 2.3, 0.26), (2.6, 2.28, 1.5, 0.14)]
TURRET = [(-1.7, 0.36, 1.25, 0.32), (-1.2, 0.42, 1.6, 0.42), (0.7, 0.42, 1.55, 0.42), (1.6, 0.32, 0.9, 0.26)]


def make(Part, tier):
    body, right, top, top_r = Part(), Part(), Part(), Part()
    loft(body, HULL, CERAMIC, PLAIN, OCT)
    underglow(body, HULL, OCT, 0.26)
    for z in (-2.4, -0.4, 1.6, 3.2):
        band(body, HULL, z, 0.14, OCT)
    for k in (0, 1, 2, 7):
        seam(body, HULL, OCT, k, 0.045)
    seam(right, HULL, OCT, 1, 0.06, LIT, SIDE_GLOW, t=0.45, z0=-2.2, z1=3.4)
    for x in (-0.8, 0.8):  # vents in the prow
        body.box((0.9, 0.3, 0.06), (x, 1.1, 3.82), WORKS)
    deck = 2.2
    if tier >= 3:
        loft(body, UPPER, CERAMIC, PLAIN, OCT)
        band(body, UPPER, -0.8, 0.12, OCT)
        seam(right, UPPER, OCT, 1, 0.045, LIT, SIDE_GLOW, t=0.5, z0=-2.6, z1=1.4)
        deck = 2.66
        right.box((0.8, 0.8, 1.6), (3.0, 1.55, 0.2), CERAMIC)  # the sponsons
        right.box((0.84, 0.08, 1.64), (3.0, 1.96, 0.2), BRASS)
        hexgun(right, (3.0, 1.55, 1.0), (0, 0, 1), 1.3, 0.2)
    drum(body, (0, deck - 0.16, -0.4), 1.5, 0.18, SHADE)
    # The turret: gem-cut, twin hex barrels, the cupola.
    loft(top, TURRET, CERAMIC, PLAIN, OCT)
    band(top, TURRET, -0.2, 0.1, OCT, grow=0.03)
    for k in (0, 1, 7):
        seam(top, TURRET, OCT, k, 0.035)
    seam(top_r, TURRET, OCT, 1, 0.04, LIT, SIDE_GLOW, t=0.5, z0=-1.0, z1=0.5)
    chapel(top, (0, 0.84, -0.6), 0.55, 0.3, tiers=2 if tier >= 3 else 1, roof=0.55, shrink=0.8)
    r = 0.2 if tier >= 3 else 0.14
    top_r.box((0.46, 0.5, 0.5), (0.4, 0.42, 1.55), CERAMIC)
    top_r.box((0.5, 0.06, 0.54), (0.4, 0.7, 1.55), BRASS)
    muzzle = hexgun(top_r, (0.4, 0.42, 1.75), (0, 0, 1), 2.4 if tier >= 3 else 2.6, r)
    top.mirrored(top_r)
    body.mirrored(right)
    k = 1.0 if tier == 2 else 1.12
    return {"body": scaled(body, k), "top": scaled(top, k), "top_at": (0.0, deck * k, -0.4 * k), "muzzle": tuple(c * k for c in muzzle), "view": 0.9 * k}


def build(Part):
    return make(Part, 2)
