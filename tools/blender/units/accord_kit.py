"""What the Luminar Accord's Rev 2 units share: the angular, faceted shape language. Hulls are
lofted through hex and chamfered-octagon sections; domes are faceted octagonal drums under flat-
panelled pyramid roofs, with pointed-arch windows; fans are octagonal ducts; guns are hex barrels;
the Accord's mark is a braided-knot lozenge. White ceramic, brass along the edges and seams, dark
works underneath, and light in the side's colour along seams, under hover hulls and in muzzles,
nozzles and the fabrication orb (it is green in the concept art: the Accord's own colour).
"""

import math

from mathutils import Vector

from battle_models import Color, PLAIN, GLOW, SIDE_GLOW, PAINT  # noqa: F401
from units.luminar_kit import CERAMIC, SHADE, BRASS, OLD, WORKS, GLASS, LIT, shell, tipped  # noqa: F401
from units.coma_kit import tube, air_views, scaled  # noqa: F401

GUN = Color(0.2, 0.2, 0.21)  # gunmetal barrels and launchers

# Cross-sections, (across, up) from -1 to 1, all the way round.
OCT = [(0.5, 1), (1, 0.45), (1, -0.35), (0.6, -1), (-0.6, -1), (-1, -0.35), (-1, 0.45), (-0.5, 1)]  # a chamfered barge
HEX = [(0, 1), (0.87, 0.5), (0.87, -0.5), (0, -1), (-0.87, -0.5), (-0.87, 0.5)]  # point up
FLAT_HEX = [(0.5, 1), (1, 0), (0.5, -1), (-0.5, -1), (-1, 0), (-0.5, 1)]  # flat top and bottom
WEDGE = [(0.45, 1), (1, 0.3), (0.85, -0.55), (0.45, -1), (-0.45, -1), (-0.85, -0.55), (-1, 0.3), (-0.45, 1)]
CANOPY = [(1, 0), (0.7, 0.62), (0.25, 1), (-0.25, 1), (-0.7, 0.62), (-1, 0)]  # flat underneath
BOX = [(1, 1), (1, -1), (-1, -1), (-1, 1)]


def _at(sections, z):
    """The section (z, cy, w, h) at z, between the given ones."""
    s = sorted(sections)
    if z <= s[0][0]:
        return s[0]
    for a, b in zip(s, s[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / max(b[0] - a[0], 1e-6)
            return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))
    return s[-1]


def loft(P, sections, colour=CERAMIC, mask=PLAIN, shape=OCT, x=0.0, grow=0.0, caps=True):
    """A faceted body through cross-sections [(z, centre y, half width, half height), ...] from
    back to front; a section with no width is a point. `grow` makes it that much bigger all round."""
    sections = [(z, cy, w + grow if w > 1e-4 else 0.0, h + grow if w > 1e-4 else 0.0) for z, cy, w, h in sections]
    rings = [[Vector((x + a * w, cy + b * h, z)) for a, b in shape] for z, cy, w, h in sections]
    n = len(shape)
    for (s0, r0), (s1, r1) in zip(zip(sections, rings), zip(sections[1:], rings[1:])):
        mid = Vector((x, (s0[1] + s1[1]) / 2, (s0[0] + s1[0]) / 2))
        for k in range(n):
            j = (k + 1) % n
            if s0[2] < 1e-4:
                P.poly([Vector((x, s0[1], s0[0])), r1[j], r1[k]], colour, mask, mid)
            elif s1[2] < 1e-4:
                P.poly([r0[k], r0[j], Vector((x, s1[1], s1[0]))], colour, mask, mid)
            else:
                P.poly([r0[k], r0[j], r1[j], r1[k]], colour, mask, mid)
    if caps and sections[0][2] > 1e-4:
        P.poly(rings[0], colour, mask, Vector((x, sections[0][1], sections[0][0] + 1)))
    if caps and sections[-1][2] > 1e-4:
        P.poly(rings[-1], colour, mask, Vector((x, sections[-1][1], sections[-1][0] - 1)))


def band(P, sections, z, deep=0.14, shape=OCT, colour=BRASS, mask=PLAIN, grow=0.04, x=0.0):
    """A band standing proud round a lofted body at z (brass trim, or a lit seam)."""
    loft(P, [_at(sections, z - deep / 2), _at(sections, z + deep / 2)], colour, mask, shape, x, grow)


def along(sections, shape, k, t=0.0, z0=None, z1=None, x=0.0, out=0.0):
    """Points down a lofted body: on the edge from corner k toward corner k + 1 (`t` of the way),
    `out` beyond its surface, between z0 and z1."""
    s = sorted(sections)
    zs = [q[0] for q in s if (z0 is None or q[0] > z0) and (z1 is None or q[0] < z1)]
    zs = ([z0] if z0 is not None else []) + zs + ([z1] if z1 is not None else [])
    a, b = Vector(shape[k % len(shape)]), Vector(shape[(k + 1) % len(shape)])
    c = a + (b - a) * t
    pts = []
    for z in zs:
        _, cy, w, h = _at(s, z)
        pts.append((x + c.x * (w + out), cy + c.y * (h + out), z))
    return pts


def seam(P, sections, shape, k, r=0.04, colour=BRASS, mask=PLAIN, t=0.0, z0=None, z1=None, x=0.0):
    """A brass (or lit) line down a lofted body, on corner k or `t` of the way to the next."""
    pts = along(sections, shape, k, t, z0, z1, x, r * 0.5)
    if len(pts) > 1:
        tube(P, pts, r, colour, mask, sides=4)


def underglow(P, sections, shape=OCT, drop=0.3, inset=0.82, x=0.0):
    """A hover hull's underside: dark works under its belly and a sheet of light under them."""
    low = [(z, cy - h * 1.0 - drop * 0.5, w * inset, drop * 0.5) for z, cy, w, h in sections if w > 1e-4]
    loft(P, low, WORKS, PLAIN, BOX, x)
    glow = [(z, cy - h - drop - 0.02, w * inset * 0.85, 0.03) for z, cy, w, h in sections if w > 1e-4]
    loft(P, glow[1:-1] if len(glow) > 3 else glow, LIT, SIDE_GLOW, BOX, x)


def drum(P, at, r, h, colour=CERAMIC, mask=PLAIN, sides=8, r1=None):
    """An upright faceted drum (r1 at its top if it tapers), a flat face to the front."""
    P.lathe(at, (0, 1, 0), [(0, r), (h, r if r1 is None else r1)], colour, mask, sides, math.pi / sides)


def pyramid(P, at, r, h, colour=CERAMIC, sides=8, ribs=True):
    """A flat-panelled pyramid roof, brass ribs down its edges."""
    P.lathe(at, (0, 1, 0), [(0, r), (h, 0.0)], colour, PLAIN, sides, math.pi / sides)
    if ribs:
        apex = Vector(at) + Vector((0, h, 0))
        for k in range(sides):
            a = math.pi / sides + math.tau * k / sides
            foot = Vector(at) + Vector((-math.sin(a) * r, 0, -math.cos(a) * r))
            tube(P, [tuple(foot), tuple(foot + (apex - foot) * 0.96)], max(0.025, r * 0.045), BRASS, PLAIN, sides=4)


def faces(sides, r):
    """(middle, outward) of each face of an upright faceted drum of radius r."""
    out = []
    for k in range(sides):
        a = math.tau * k / sides
        n = Vector((-math.sin(a), 0, -math.cos(a)))
        out.append((n * r * math.cos(math.pi / sides), n))
    return out


def arch(P, at, normal, w, h, colour=GLASS, mask=PLAIN, frame=BRASS):
    """A pointed-arch window on a wall facing `normal`, its foot at `at`."""
    n = Vector(normal).normalized()
    u = Vector((0, 1, 0)).cross(n).normalized()
    up = n.cross(u).normalized()
    if up.y < 0:
        up = -up
    a = Vector(at)
    outline = [(-0.5, 0), (0.5, 0), (0.5, 0.62), (0, 1), (-0.5, 0.62)]
    if frame is not None:
        P.prism([tuple(a + u * x * w * 1.3 + up * (y * h * 1.12 - h * 0.06)) for x, y in outline], tuple(n * 0.025), frame)
    P.prism([tuple(a + n * 0.02 + u * x * w + up * y * h) for x, y in outline], tuple(n * 0.025), colour, mask)


def chapel(P, at, r, h, tiers=1, roof=0.8, windows=True, beacon=False, sides=8, shrink=0.72, lit=False):
    """A faceted chapel dome: octagonal drums stepping in, a pointed-arch window in each face, brass
    rims and corner posts, a pyramid roof with brass ribs, a crystal beacon on top if `beacon`.
    Returns the point at the top."""
    x, y, z = at
    drum(P, (x, y - 0.06, z), r * 1.08, 0.1, BRASS, sides=sides)
    for t in range(tiers):
        drum(P, (x, y, z), r, h, CERAMIC, sides=sides)
        for k in range(sides):  # corner posts
            a = math.pi / sides + math.tau * k / sides
            c = Vector((x - math.sin(a) * r * 1.01, y, z - math.cos(a) * r * 1.01))
            tube(P, [tuple(c), tuple(c + Vector((0, h, 0)))], max(0.025, r * 0.05), BRASS, PLAIN, sides=4)
        if windows:
            for mid, n in faces(sides, r):
                arch(P, (x + mid.x, y + h * 0.2, z + mid.z), n, r * 0.34, h * 0.62, LIT if lit else GLASS, SIDE_GLOW if lit else PLAIN, OLD)
        y += h
        drum(P, (x, y - 0.02, z), r * 1.07, 0.08, BRASS, sides=sides)
        if t < tiers - 1:
            drum(P, (x, y + 0.06, z), r * 1.02, 0.08, CERAMIC, sides=sides, r1=r * shrink)
            y += 0.14
            r *= shrink
            h *= 0.8
    pyramid(P, (x, y + 0.06, z), r * 1.04, r * roof)
    top = y + 0.06 + r * roof
    if beacon:
        drum(P, (x, top - 0.08, z), r * 0.16, 0.12, BRASS, sides=sides)
        gem(P, (x, top + r * 0.22, z), r * 0.2)
        top += r * 0.45
    return (x, top, z)


def gem(P, at, r, colour=LIT, mask=SIDE_GLOW, sides=6):
    """A cut crystal: two hex pyramids base to base."""
    x, y, z = at
    P.lathe((x, y - r * 1.2, z), (0, 1, 0), [(0, 0.0), (r * 1.2, r), (r * 2.2, 0.0)], colour, mask, sides, math.pi / sides, caps=False)


def octring(P, at, r_out, r_in, h, colour=CERAMIC, mask=PLAIN, sides=8):
    """A flat octagonal ring (a duct's wall) from `at` up h."""
    x, y, z = at

    def p(k, r, yy):
        a = math.pi / sides + math.tau * k / sides
        return (x - math.sin(a) * r, yy, z - math.cos(a) * r)
    for k in range(sides):
        j = k + 1
        P.hexa([p(k, r_in, y), p(k, r_out, y), p(j, r_out, y), p(j, r_in, y)], [p(k, r_in, y + h), p(k, r_out, y + h), p(j, r_out, y + h), p(j, r_in, y + h)], colour, mask)


def fan(P, at, r, h=None, glow=True, struts=4):
    """An octagonal ducted fan, its middle at `at`: a faceted ceramic duct with brass lips, dark
    blades and a brass hub inside, light underneath."""
    h = h or r * 0.42
    x, y, z = at
    y0 = y - h / 2
    octring(P, (x, y0, z), r, r * 0.82, h)
    octring(P, (x, y0 + h - 0.02, z), r * 1.04, r * 0.84, h * 0.16, BRASS)
    octring(P, (x, y0 - 0.02, z), r * 1.04, r * 0.84, h * 0.16, BRASS)
    drum(P, (x, y - h * 0.1, z), r * 0.83, 0.05, WORKS)
    drum(P, (x, y - h * 0.2, z), r * 0.2, h * 0.5, BRASS, r1=r * 0.12)
    for k in range(struts):
        a = math.tau * (k + 0.5) / struts
        P.beam((x, y, z), (x + math.cos(a) * r * 0.84, y, z + math.sin(a) * r * 0.84), r * 0.1, 0.05, OLD, PLAIN, face=(0, 1, 0))
    if glow:
        drum(P, (x, y0 - 0.06, z), r * 0.6, 0.04, LIT, SIDE_GLOW)


def frame(f, up=(0, 1, 0)):
    """(along, across, up) for something pointing along f."""
    f = Vector(f).normalized()
    u = Vector(up).cross(f)
    u = u.normalized() if u.length > 1e-4 else Vector((1, 0, 0))
    return f, u, f.cross(u).normalized()


def obox(P, at, f, size, colour, mask=PLAIN, up=(0, 1, 0)):
    """A box centred on `at`, `size` = (across, up, along `f`)."""
    a = Vector(at)
    f, u, v = frame(f, up)
    w, h, d = size[0] / 2, size[1] / 2, size[2] / 2

    def p(i, j, k):
        return a + u * i * w + v * j * h + f * k * d
    P.hexa([p(-1, -1, -1), p(1, -1, -1), p(1, 1, -1), p(-1, 1, -1)], [p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1)], colour, mask)


def hexgun(P, at, f, length, r, colour=GUN, collar=True):
    """A hex-section barrel from `at` along f, a brass collar at its root, a lit hex muzzle."""
    f = Vector(f).normalized()
    P.lathe(at, tuple(f), [(0, r * 1.25), (length * 0.22, r * 1.25), (length * 0.24, r), (length, r)], colour, PLAIN, 6, math.pi / 6)
    if collar:
        P.lathe(at, tuple(f), [(length * 0.02, r * 1.4), (length * 0.12, r * 1.4)], BRASS, PLAIN, 6, math.pi / 6)
    P.lathe(tuple(Vector(at) + f * length * 0.96), tuple(f), [(0, r * 1.15), (length * 0.04, r * 1.15)], BRASS, PLAIN, 6, math.pi / 6)
    P.lathe(tuple(Vector(at) + f * length), tuple(f), [(0, r * 0.7), (0.02, r * 0.7)], LIT, SIDE_GLOW, 6, math.pi / 6)
    return tuple(Vector(at) + f * (length + 0.05))


def launcher(P, at, f, n_across, n_up, cell, depth, up=(0, 1, 0)):
    """A hard-edged box launcher pointing along f: ceramic, a brass face, a lit cell per missile."""
    a = Vector(at)
    f, u, v = frame(f, up)
    w, h = n_across * cell * 1.15 + cell * 0.3, n_up * cell * 1.15 + cell * 0.3
    obox(P, a, f, (w, h, depth), CERAMIC, PLAIN, up)
    obox(P, a + f * depth * 0.5, f, (w * 1.04, h * 1.04, 0.08), BRASS, PLAIN, up)
    for i in range(n_across):
        for j in range(n_up):
            c = a + f * (depth * 0.5 + 0.045) + u * (i - (n_across - 1) / 2) * cell * 1.15 + v * (j - (n_up - 1) / 2) * cell * 1.15
            P.lathe(tuple(c), tuple(f), [(0, cell * 0.42), (0.02, cell * 0.42)], LIT, SIDE_GLOW, 6, math.pi / 6)


def lozenge(P, at, normal, s, back=SHADE):
    """The Accord's braided-knot lozenge: a brass diamond woven through with a lattice, on a plate."""
    n = Vector(normal).normalized()
    u = Vector((0, 1, 0)).cross(n)
    u = u.normalized() if u.length > 1e-4 else Vector((1, 0, 0))
    v = n.cross(u).normalized()
    a = Vector(at)

    def p(x, y, lift=0.0):
        return a + u * x * s + v * y * s + n * lift
    P.prism([tuple(p(x, y)) for x, y in ((0, -1.15), (1.15, 0), (0, 1.15), (-1.15, 0))], tuple(n * 0.03), back)
    corners = [(0, -1), (1, 0), (0, 1), (-1, 0)]
    for (x0, y0), (x1, y1) in zip(corners, corners[1:] + corners[:1]):
        P.beam(tuple(p(x0, y0, 0.05)), tuple(p(x1, y1, 0.05)), s * 0.16, 0.05, BRASS, PLAIN, face=tuple(n))
    for t in (-1 / 3, 1 / 3):  # the weave, both ways
        P.beam(tuple(p(-0.5 + t, -0.5 - t, 0.06)), tuple(p(0.5 + t, 0.5 - t, 0.06)), s * 0.13, 0.05, BRASS, PLAIN, face=tuple(n))
        P.beam(tuple(p(-0.5 + t, 0.5 + t, 0.07)), tuple(p(0.5 + t, -0.5 + t, 0.07)), s * 0.13, 0.05, BRASS, PLAIN, face=tuple(n))


def nozzle(P, at, f, r, length, sides=6):
    """A faceted hex engine nozzle at the back, its exhaust lit."""
    f = Vector(f).normalized()
    P.lathe(at, tuple(f), [(0, r * 0.9), (length * 0.7, r), (length, r * 1.08)], GUN, PLAIN, sides, math.pi / sides)
    P.lathe(tuple(Vector(at) + f * length * 0.9), tuple(f), [(0, r * 1.12), (length * 0.12, r * 1.12)], BRASS, PLAIN, sides, math.pi / sides)
    P.lathe(tuple(Vector(at) + f * length), tuple(f), [(0, r * 0.82), (0.03, r * 0.82)], LIT, SIDE_GLOW, sides, math.pi / sides)


def wing(P, outline, y, thick, colour=CERAMIC, edge=2, bevel=0.35):
    """A flat faceted wing panel of the outline [(x, z), ...] at height y: a thinner raised facet on
    top, brass along its first `edge` corners (the leading edge)."""
    P.prism([(x, y - thick / 2, z) for x, z in outline], (0, thick, 0), colour)
    cx = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)
    inner = [(cx + (x - cx) * (1 - bevel), cz + (z - cz) * (1 - bevel)) for x, z in outline]
    P.prism([(x, y + thick / 2 - 0.005, z) for x, z in inner], (0, thick * 0.45, 0), colour)
    if edge:
        P.trace([(x, y + 0.01, z) for x, z in outline[:edge]], thick * 0.9, thick * 1.1, BRASS, PLAIN, face=(0, 1, 0))


def fin(P, root, tip, chord_root, chord_tip, thick=0.14, colour=CERAMIC):
    """A canted fin from its root's leading edge `root` (x, y, z) to its tip's `tip`, swept back,
    brass along its leading edge."""
    a, b = Vector(root), Vector(tip)
    pts = [a, b, b - Vector((0, 0, chord_tip)), a - Vector((0, 0, chord_root))]
    n = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
    P.prism([tuple(p - n * thick / 2) for p in pts], tuple(n * thick), colour)
    P.beam(tuple(a), tuple(b), thick * 1.3, thick * 1.3, BRASS, PLAIN, face=tuple(n))
