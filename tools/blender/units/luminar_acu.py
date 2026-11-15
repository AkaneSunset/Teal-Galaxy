"""The Luminar Accord's Armoured Command Unit (Rev 2): a crewed hover barge, amphibious. A long
chamfered octagonal hull in two stepped tiers riding on a sheet of light, brass at every seam, a
faceted chapel of three octagonal tiers with pointed-arch windows and a crystal beacon on its
pyramid roof, a glazed bridge forward, twin hex beam cannons in housings either side of the prow,
and the braided-knot lozenge on each flank. Its light is the side's colour.

About 6 m wide and 11.5 m long (the server's ACU is 5 m in radius).
"""

from units.accord_kit import *  # noqa: F401,F403

LOW = [(-5.4, 1.45, 2.3, 0.75), (-4.7, 1.45, 2.9, 0.9), (2.4, 1.45, 3.0, 0.9), (4.7, 1.3, 2.2, 0.7), (5.7, 1.2, 1.1, 0.42)]
HIGH = [(-4.7, 2.75, 2.2, 0.42), (-4.1, 2.8, 2.45, 0.48), (1.4, 2.8, 2.45, 0.48), (3.4, 2.65, 1.6, 0.32)]


def build(Part):
    body, right = Part(), Part()
    loft(body, LOW, CERAMIC, PLAIN, OCT)
    loft(body, HIGH, CERAMIC, PLAIN, OCT)
    underglow(body, LOW, OCT, 0.32)
    for z in (-4.2, -1.9, 0.6, 2.9):
        band(body, LOW, z, 0.16, OCT)
    for z in (-3.0, -0.4):
        band(body, HIGH, z, 0.12, OCT)
    for k in (0, 1, 2, 7):
        seam(body, LOW, OCT, k, 0.05)
    for k in (0, 1, 6, 7):
        seam(body, HIGH, OCT, k, 0.04)
    seam(right, LOW, OCT, 1, 0.06, LIT, SIDE_GLOW, t=0.35, z0=-4.4, z1=3.6)  # light down each flank
    seam(right, HIGH, OCT, 1, 0.05, LIT, SIDE_GLOW, t=0.5, z0=-3.8, z1=1.2)
    for z in (-2.9, -0.3):
        lozenge(right, (3.03, 1.5, z), (1, 0, 0), 0.5)
    # The bridge: faceted glass in a brass frame at the front of the upper tier.
    glass = [(0.6, 3.2, 1.75, 0.34), (2.3, 3.17, 1.55, 0.26), (3.05, 3.05, 1.05, 0.08)]
    loft(body, glass, GLASS, PLAIN, CANOPY)
    for k in (1, 2, 3, 4):
        seam(body, glass, CANOPY, k, 0.035)
    # The chapel, three tiers, the beacon on top.
    chapel(body, (0, 3.25, -1.4), 1.55, 0.95, tiers=3, roof=0.95, beacon=True)
    # Twin hex beam cannons in their housings beside the prow.
    for z in (2.6, 3.8):
        right.box((1.15, 0.9, 0.12), (1.95, 1.75, z), BRASS)
    right.slab(1.3, (1.4, 2.5, 2.2, 4.4), 2.2, (1.5, 2.4, 2.3, 4.2), CERAMIC)
    muzzle = hexgun(right, (1.95, 1.75, 4.3), (0, 0, 1), 2.4, 0.26)
    # Lamps across the stern.
    for x in (-1.3, 0.0, 1.3):
        body.lathe((x, 1.45, -5.42), (0, 0, -1), [(0, 0.26), (0.04, 0.26)], LIT, SIDE_GLOW, 6)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": muzzle, "view": 1.3}
