"""The Luminar Accord's Deacon engineer (Rev 2): an amphibious hover engineer. A broad, flat-topped
octagonal slab of a hull with chamfered edges, brass round its rim and down its corners, lit slots
in its faces and a glazed bay at the front, riding on a sheet of light; on top, a stepped octagonal
plinth and a faceted brass lantern cage holding the fabrication orb, a cut gem of light in the
side's colour.

About 6.4 m across (the server's engineer is 3 m in radius).
"""

import math

from units.accord_kit import *  # noqa: F401,F403

R = 3.2  # across the flats, from the middle


def build(Part):
    body = Part()
    # The hull: an octagonal slab, chamfered top and bottom.
    body.lathe((0, 0.55, 0), (0, 1, 0), [(0, R * 0.82), (0.35, R * 0.97), (1.05, R), (1.3, R * 0.88)], CERAMIC, PLAIN, 8, math.pi / 8)
    body.lathe((0, 0.25, 0), (0, 1, 0), [(0, R * 0.72), (0.32, R * 0.8)], WORKS, PLAIN, 8, math.pi / 8)
    drum(body, (0, 0.18, 0), R * 0.66, 0.04, LIT, SIDE_GLOW)
    drum(body, (0, 1.45, 0), R * 1.015, 0.1, BRASS)
    drum(body, (0, 0.88, 0), R * 1.015, 0.06, BRASS)
    for k in range(8):  # brass down each corner, a lit slot in each face
        a = math.pi / 8 + math.tau * k / 8
        c = (-math.sin(a) * R * 1.07, 0, -math.cos(a) * R * 1.07)
        tube(body, [(c[0] * 0.95, 0.9, c[2] * 0.95), (c[0], 1.45, c[2])], 0.07, BRASS, PLAIN, sides=4)
    for mid, n in faces(8, R):
        if n.z > 0.9:
            continue
        p = mid + n * 0.02
        body.beam(tuple(p - Vector((-n.z, 0, n.x)) * 0.6 + Vector((0, 1.15, 0))), tuple(p + Vector((-n.z, 0, n.x)) * 0.6 + Vector((0, 1.15, 0))), 0.12, 0.05, LIT, SIDE_GLOW, face=tuple(n))
    # The glazed bay at the front.
    body.slab(0.8, (-1.0, 1.0, R * 0.9, R * 1.08), 1.35, (-0.85, 0.85, R * 0.9, R * 1.04), CERAMIC)
    body.box((1.5, 0.36, 0.04), (0, 1.08, R * 1.08), GLASS)
    body.box((0.04, 0.36, 0.06), (0, 1.08, R * 1.09), BRASS)
    # The deck: panel seams, a stepped plinth, the lantern cage round the orb.
    drum(body, (0, 1.85, 0), R * 0.6, 0.04, SHADE)
    drum(body, (0, 1.85, 0), 1.2, 0.18, CERAMIC, r1=1.0)
    drum(body, (0, 2.03, 0), 1.04, 0.07, BRASS)
    drum(body, (0, 2.1, 0), 0.82, 0.18, OLD, r1=0.72)
    cage = 0.7
    y0, y1 = 2.28, 3.5
    for k in range(8):
        a = math.pi / 8 + math.tau * k / 8
        x, z = -math.sin(a) * cage, -math.cos(a) * cage
        tube(body, [(x, y0, z), (x, y1, z), (0, y1 + 0.55, 0)], 0.045, BRASS, PLAIN, sides=4)
    for y in (y0 + 0.04, y1):
        octring(body, (0, y - 0.04, 0), cage + 0.05, cage - 0.05, 0.08, BRASS)
    drum(body, (0, y1 + 0.5, 0), 0.12, 0.2, BRASS)
    gem(body, (0, (y0 + y1) / 2 + 0.05, 0), 0.42)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (0.0, (y0 + y1) / 2, 0.5), "view": 0.85}
