"""The insides of city buildings: what you walk around after going in at a building's door.

An inside is its own small place, exported as game/city/<faction>/inside_<piece>.glb (or
inside_<piece>_<n>.glb where a piece has several). You come in at the origin looking along -Y, the
door back out is behind you, and the floor's top is z = 0. Rooms are built from thick slabs (floors,
walls with doorways, ceilings) so the game can stand you on them and stop you at them: it makes
everything but the "detail" mesh solid. Markers say where the way out is ("exit") and where the
lamps hang ("light1", "light2"...). The common rooms (gatehouses, halls, lobbies, corridors, a
home's mess) have displays on their walls (kit.display): the game shows the faction's propaganda
on them (tools/blender/propaganda.py makes the pictures).
"""

import math

from kit import box, collar, cyl, display, marker, ramp, ring, slab_with_hole, text, wall


def shell(x0, x1, y0, y1, h, floor, ceil, z=0.0):
    """A room's floor and ceiling over x0..x1, y0..y1 (walls are added one by one, for doorways)."""
    w, d = x1 - x0, y1 - y0
    c = ((x0 + x1) / 2, (y0 + y1) / 2)
    box((w + 0.4, d + 0.4, 0.4), (c[0], c[1], z - 0.4), floor)
    box((w + 0.4, d + 0.4, 0.4), (c[0], c[1], z + h), ceil)


def way_out(M, y, frame="hazard", door="dark", lamp="amber"):
    """The door you came in by, in the wall behind you at `y`, and the marker the game uses."""
    box((2.2, 0.2, 2.6), (0, y - 0.25, 0), M[door])
    box((2.6, 0.15, 0.15), (0, y - 0.3, 2.6), M[frame], detail=True)
    for s in (-1, 1):
        box((0.15, 0.15, 2.6), (s * 1.2, y - 0.3, 0), M[frame], detail=True)
    box((0.5, 0.1, 0.25), (0, y - 0.4, 2.9), M[lamp], detail=True)
    marker("exit", (0, y - 0.9, 1.2))


def bunk(M, at, along_y=True):
    """Two bunks, one over the other."""
    x, y, z = at
    size = (1.0, 2.1) if along_y else (2.1, 1.0)
    for zz in (0.35, 1.45):
        box((size[0], size[1], 0.12), (x, y, z + zz), M["steel"])
        box((size[0] - 0.1, size[1] - 0.1, 0.14), (x, y, z + zz + 0.12), M["white"], detail=True)
    for sx in (-1, 1):
        for sy in (-1, 1):
            box((0.08, 0.08, 1.9), (x + sx * (size[0] / 2 - 0.04), y + sy * (size[1] / 2 - 0.04), z), M["steel"], detail=True)


def table(M, at, seats=4, r=0.8):
    x, y, z = at
    cyl(r, 0.08, (x, y, z + 0.75), M["slate"], verts=10)
    cyl(0.12, 0.75, (x, y, z), M["steel"], verts=6, detail=True)
    for i in range(seats):
        a = math.tau * i / seats + 0.4
        cyl(0.22, 0.45, (x + math.cos(a) * (r + 0.45), y + math.sin(a) * (r + 0.45), z), M["steel"], verts=8, detail=True)


# --- Terran Compact --------------------------------------------------------------------------------

def compact_hall(M):
    """The Government Hall: a gatehouse, the great hall with its dais and command table, and the
    council chamber off its right side."""
    # The gatehouse you come in through.
    shell(-5, 5, -6, 3, 5, M["deck"], M["navy"])
    wall((-5, 3), (5, 3), 0, 5, M["navy"])
    wall((-5, 3), (-5, -6), 0, 5, M["slate"])
    wall((5, 3), (5, -6), 0, 5, M["slate"])
    way_out(M, 3)
    for s in (-1, 1):
        box((0.25, 7.5, 0.25), (s * 4.6, -1.5, 2.2), M["blue"])
    for s in (-1, 1):  # displays either side of the way into the hall
        display(M, (s * 4.0, -5.8, 1.3), "+y")
    marker("light1", (0, -1.5, 4.2))
    # The great hall.
    shell(-15, 15, -50, -6, 18, M["deck"], M["navy"])
    wall((-15, -6), (15, -6), 0, 18, M["navy"], gaps=[(15, 6.0, 4.6)])
    wall((-15, -6), (-15, -50), 0, 18, M["navy"])
    wall((15, -6), (15, -50), 0, 18, M["navy"], gaps=[(20, 3.0, 3.4)])
    wall((-15, -50), (15, -50), 0, 18, M["slate"])
    box((6, 44, 0.05), (0, -28, 0), M["slate"])  # the aisle
    for s in (-1, 1):
        box((0.3, 31, 0.06), (s * 3.0, -22, 0.0), M["hazard"], detail=True)
    for i in range(6):  # ribs up both walls, lit blue, and the beams they carry
        y = -9.5 - i * 7.5
        for s in (-1, 1):
            box((1.2, 1.0, 18), (s * 14.3, y, 0), M["steel"])
            box((0.25, 0.3, 13), (s * 13.65, y, 2.5), M["blue"])
        box((30, 0.8, 1.0), (0, y, 17.0), M["steel"])
    for i in range(5):  # banners between the ribs
        y = -13.25 - i * 7.5
        for s in (-1, 1):
            if s == 1 and abs(y + 26) < 3:
                continue  # the council chamber's door is here
            box((0.15, 3.2, 8.0), (s * 14.7, y, 6.0), M["slate"])
            box((0.1, 2.0, 0.5), (s * 14.6, y, 11.5), M["white"], detail=True)
            box((0.1, 1.2, 0.5), (s * 14.6, y, 10.5), M["white"], detail=True)
            if i % 2 == 0:  # a display under every other banner
                display(M, (s * 14.8, y, 1.5), "-x" if s > 0 else "+x", w=1.3, h=1.95)
    for i in range(5):  # benches either side of the aisle
        y = -12.0 - i * 5.0
        for s in (-1, 1):
            box((7.0, 0.9, 0.5), (s * 8.0, y, 0), M["slate"], bevel=0.1)
            box((7.0, 0.25, 0.6), (s * 8.0, y + 0.45, 0.5), M["steel"], detail=True)
    box((22, 11, 1.2), (0, -44.3, 0), M["steel"], bevel=0.2)  # the dais
    box((8, 1.0, 0.8), (0, -38.4, 0), M["steel"])
    box((8, 1.0, 0.4), (0, -37.5, 0), M["steel"])
    cyl(3.0, 1.0, (0, -44, 1.2), M["slate"], verts=12)  # the command table and its map
    cyl(2.6, 0.08, (0, -44, 2.2), M["blue"], verts=12)
    ring(1.6, 0.05, (0, -44, 3.2), M["blue"], detail=True)
    ring(1.0, 0.05, (0, -44, 3.8), M["blue"], detail=True)
    for s in (-1, 1):
        box((1.4, 1.4, 3.0), (s * 8.5, -47, 1.2), M["navy"], bevel=0.2)  # consoles
        box((1.0, 0.1, 0.7), (s * 8.5, -46.25, 2.8), M["blue"], detail=True)
    text("TERRAN COMPACT", 2.4, (0, -49.7, 12.5), M["white"])
    for s in (-1, 1):  # the eagle over it
        box((6, 0.3, 1.0), (s * 4.4, -49.7, 15.6), M["white"], rot=(0, s * math.radians(16), 0))
    box((2.0, 0.3, 2.6), (0, -49.7, 14.0), M["blue"])
    for n, y in enumerate((-13, -24, -35, -45)):
        marker(f"light{n + 2}", (0, y, 15.0))
    # The council chamber.
    shell(15, 33, -35, -17, 7, M["deck"], M["navy"])
    wall((15, -17), (33, -17), 0, 7, M["slate"])
    wall((15, -35), (33, -35), 0, 7, M["slate"])
    wall((33, -17), (33, -35), 0, 7, M["navy"])
    cyl(4.6, 0.9, (24, -26, 0), M["slate"], verts=14)
    cyl(3.0, 0.92, (24, -26, 0), M["dark"], verts=14)
    ring(3.8, 0.06, (24, -26, 0.95), M["blue"], detail=True)
    for i in range(9):
        a = math.tau * i / 9
        box((0.9, 0.9, 1.1), (24 + math.cos(a) * 6.0, -26 + math.sin(a) * 6.0, 0), M["navy"], bevel=0.15, rot=(0, 0, a))
    box((0.15, 8.0, 3.2), (32.7, -26, 2.2), M["blue"])  # the wall screen
    for s in (-1, 1):
        box((14, 0.2, 0.25), (24, -26 + s * 8.75, 5.5), M["amber"], detail=True)
    marker("light6", (24, -26, 6.0))


def compact_home(M, mirror=1):
    """A barracks home: bunks, a mess table, lockers and a galley, with a store room behind."""
    s = mirror
    shell(-5, 5, -13, 2, 3.2, M["deck"], M["navy"])
    wall((-5, 2), (5, 2), 0, 3.2, M["navy"])
    wall((-5, 2), (-5, -13), 0, 3.2, M["slate"])
    wall((5, 2), (5, -13), 0, 3.2, M["slate"])
    wall((-5, -13), (5, -13), 0, 3.2, M["navy"])
    wall((-5, -8.5), (5, -8.5), 0, 3.2, M["navy"], gaps=[(5 + s * 2.5, 1.4, 2.3)], t=0.25)
    way_out(M, 2)
    bunk(M, (s * 4.2, -1.5, 0))
    bunk(M, (s * 4.2, -4.5, 0))
    table(M, (-s * 1.5, -4.0, 0))
    for i in range(3):  # lockers
        box((0.9, 0.6, 2.0), (-s * 4.5, -0.2 - i * 1.0, 0), M["steel"], bevel=0.05, rot=(0, 0, math.pi / 2))
    box((3.2, 0.8, 0.95), (-s * 3.0, -7.8, 0), M["slate"])  # the galley
    box((3.2, 0.5, 0.5), (-s * 3.0, -8.0, 1.9), M["steel"])
    box((0.8, 0.1, 0.12), (-s * 3.0, -7.75, 1.8), M["amber"], detail=True)
    for y in (-2.5, -6.0):  # light panels in place of windows
        box((0.1, 1.8, 0.5), (s * 4.75, y, 2.3), M["blue"])
        box((0.1, 1.8, 0.5), (-s * 4.75, y, 2.3), M["blue"])
    cyl(0.9, 2.2, (-s * 3.5, -11.5, 0), M["slate"], verts=10)  # the store room: a tank and crates
    box((1.2, 1.2, 1.0), (s * 3.5, -11.8, 0), M["steel"], bevel=0.08)
    box((1.0, 1.0, 0.9), (s * 3.3, -11.7, 1.0), M["slate"], bevel=0.08)
    box((1.2, 1.2, 1.0), (s * 1.9, -12.0, 0), M["steel"], bevel=0.08)
    display(M, (-s * 4.8, -4.25, 1.15), "+x" if s > 0 else "-x", w=0.6, h=0.9)  # over the mess table
    marker("light1", (0, -3.5, 2.8))
    marker("light2", (0, -11.0, 2.8))


def compact_flats(M, mirror=1):
    """A tower block from the inside: the lobby and its lifts, a corridor of numbered doors, and
    the one flat that stands open."""
    s = mirror
    shell(-7, 7, -10, 2, 5, M["deck"], M["navy"])
    wall((-7, 2), (7, 2), 0, 5, M["navy"])
    wall((-7, 2), (-7, -10), 0, 5, M["slate"])
    wall((7, 2), (7, -10), 0, 5, M["slate"])
    wall((-7, -10), (7, -10), 0, 5, M["navy"], gaps=[(7, 3.2, 2.8)])
    way_out(M, 2)
    box((4.5, 1.1, 1.1), (s * 3.2, -6.5, 0), M["slate"], bevel=0.15)  # the desk
    box((1.4, 0.1, 0.7), (s * 3.2, -5.9, 1.3), M["blue"], detail=True)
    for i in range(2):  # the lifts
        y = -2.5 - i * 3.2
        box((0.2, 2.2, 2.8), (-s * 6.7, y, 0), M["dark"])
        box((0.15, 2.5, 0.2), (-s * 6.65, y, 2.8), M["hazard"], detail=True)
        box((0.1, 0.3, 0.2), (-s * 6.6, y, 3.2), M["amber"], detail=True)
    text("BLOCK B", 0.9, (-3.5, -9.75, 3.8), M["white"])
    box((6.0, 0.15, 0.25), (3.6, -9.7, 3.8), M["blue"])
    for side in (-1, 1):  # displays either side of the corridor's mouth, and one by the desk
        display(M, (side * 4.2, -9.8, 1.25), "+y")
    display(M, (s * 6.8, -3.0, 1.3), "-x" if s > 0 else "+x")
    marker("light1", (0, -4.0, 4.3))
    # The corridor.
    shell(-1.6, 1.6, -32, -10, 3.0, M["deck"], M["slate"])
    wall((-1.6, -10), (-1.6, -32), 0, 3.0, M["navy"])
    wall((1.6, -10), (1.6, -32), 0, 3.0, M["navy"], gaps=[(11, 1.4, 2.3)])
    wall((-1.6, -32), (1.6, -32), 0, 3.0, M["navy"])
    for i in range(5):
        y = -13.0 - i * 4.0
        for side in (-1, 1):
            if side == 1 and abs(y + 21) < 0.1:
                continue  # the open flat
            box((0.12, 1.3, 2.2), (side * 1.38, y, 0), M["dark"])
            box((0.08, 0.5, 0.3), (side * 1.36, y + 1.0, 1.6), M["white"], detail=True)
        box((0.25, 1.2, 0.08), (0, y - 2.0, 2.9), M["blue"], detail=True)
    for side, y in ((-1, -15.0), (1, -19.0), (-1, -23.0), (1, -27.0)):  # small displays between the doors
        display(M, (side * 1.4, y, 1.15), "-x" if side > 0 else "+x", w=0.6, h=0.9)
    box((2.4, 0.12, 1.2), (0, -31.75, 1.2), M["blue"])  # the window at the corridor's end
    marker("light2", (0, -18.0, 2.6))
    marker("light3", (0, -27.0, 2.6))
    # The flat.
    shell(1.6, 10.6, -26, -16, 3.0, M["deck"], M["navy"])
    wall((1.6, -16), (10.6, -16), 0, 3.0, M["slate"])
    wall((1.6, -26), (10.6, -26), 0, 3.0, M["slate"])
    wall((10.6, -16), (10.6, -26), 0, 3.0, M["navy"])
    box((0.12, 6.0, 1.5), (10.35, -21, 1.0), M["blue"])  # the window wall
    for y in (-23, -21, -19):
        box((0.16, 0.12, 1.5), (10.3, y + 1.0, 1.0), M["steel"], detail=True)
    bunk(M, (9.0, -17.4, 0), along_y=False)
    bunk(M, (9.0, -24.6, 0), along_y=False)
    table(M, (6.0, -21.0, 0))
    box((0.6, 2.4, 0.95), (2.2, -24.2, 0), M["slate"])
    for i in range(2):
        box((0.9, 0.6, 2.0), (3.0 + i * 1.0, -16.5, 0), M["steel"], bevel=0.05)
    marker("light4", (6.0, -21.0, 2.6))


COMPACT = {
    "inside_hall": compact_hall,
    "inside_zone_low_1": compact_home,
    "inside_zone_low_2": lambda M: compact_home(M, mirror=-1),
    "inside_zone_high_1": compact_flats,
    "inside_zone_high_2": lambda M: compact_flats(M, mirror=-1),
}


# --- Ashen Collective ------------------------------------------------------------------------------
# Black plating cut at angles, every room lit red: from slits in the walls, lamps let into the
# pillars, lines along the floor, and the furnaces that burn under the grates.

OCT = math.pi / 8
FACING = {"+x": (1, 0), "-x": (-1, 0), "+y": (0, 1), "-y": (0, -1)}


def _against(at, facing):
    """box() for things built against a wall: sizes and places given as (out from the wall, along
    it, up), from `at` on the wall's face, which looks `facing`."""
    n = FACING[facing]

    def put(size, pos, m, **kw):
        du, dv, dz = size
        u, v, z = pos
        where = (at[0] + n[0] * u + (0 if n[0] else v), at[1] + n[1] * u + (v if n[0] else 0), at[2] + z)
        return box((du, dv, dz) if n[0] else (dv, du, dz), where, m, **kw)

    return put


def cut_corner(M, x, y, size, h, z=0.0):
    """Cuts a room's corner off at 45 degrees, `size` along each wall."""
    box((size * 1.4142, size * 1.4142, h), (x, y, z), M["plate"], rot=(0, 0, math.pi / 4))


def floor_light(M, a, b, z=0.03):
    """A line of light let into the floor (or, higher, along a wall) from `a` to `b`."""
    box((max(abs(b[0] - a[0]), 0.07), max(abs(b[1] - a[1]), 0.07), 0.05), ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, z), M["strip"], detail=True)


def pillar(M, at, w, h, lamp=3.0):
    """A heavy pier with a foot, a head and a lamp let into each face."""
    x, y, z = at
    box((w, w, h), at, M["frame"], bevel=w * 0.16)
    box((w * 1.4, w * 1.4, 1.0), at, M["plate"], bevel=0.22)
    box((w * 1.4, w * 1.4, 1.3), (x, y, z + h - 1.3), M["plate"], bevel=0.22)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        size = (0.06, 0.2, lamp) if dx else (0.2, 0.06, lamp)
        box(size, (x + dx * (w / 2 + 0.01), y + dy * (w / 2 + 0.01), z + 1.7), M["strip"], detail=True)


def rail(M, c, length, angle, z, h=1.05):
    """A solid length of parapet centred on `c` (x, y), turned `angle`: plating, a rail along its
    top and a line of light along its foot."""
    box((length, 0.18, h), (c[0], c[1], z), M["plate"], rot=(0, 0, angle))
    box((length, 0.28, 0.1), (c[0], c[1], z + h), M["frame"], rot=(0, 0, angle), detail=True)
    box((length * 0.82, 0.24, 0.05), (c[0], c[1], z + 0.14), M["strip"], rot=(0, 0, angle), detail=True)


def rail_ring(M, c, apothem, z, sides=8, skip=()):
    """Parapet round an eight-sided opening whose flats lie `apothem` from `c`; `skip` leaves
    sides open (numbered from the +X side, anticlockwise)."""
    length = 2 * apothem * math.tan(math.pi / sides)
    for k in range(sides):
        if k in skip:
            continue
        a = k * math.tau / sides
        rail(M, (c[0] + math.cos(a) * apothem, c[1] + math.sin(a) * apothem), length, a + math.pi / 2, z)


def tank(M, at, r, h):
    """A pressure tank: a drum on a skirt with a domed head, banded, lit up its sides."""
    x, y, z = at
    cyl(r * 1.07, 0.5, at, M["plate"], verts=12)
    cyl(r, h, at, M["frame"], verts=12)
    cyl(r, r * 0.5, (x, y, z + h), M["plate"], verts=12, top=r * 0.45)
    cyl(r * 0.45, 0.35, (x, y, z + h + r * 0.5), M["frame"], verts=12)
    cyl(r * 1.04, 0.3, (x, y, z + h * 0.6), M["plate"], verts=12, detail=True)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        box((0.16, 0.16, h * 0.4), (x + math.cos(a) * (r - 0.02), y + math.sin(a) * (r - 0.02), z + h * 0.12), M["strip"], detail=True, rot=(0, 0, a))


def pod(M, at, facing, length=2.4):
    """A sleeping cell: an open-fronted box against a wall, a pad in it and a light at its back.
    `at` is on the wall's face at the pod's foot, in the middle of its length."""
    put = _against(at, facing)
    put((1.15, length, 0.12), (0.575, 0, 0), M["plate"])
    put((1.15, length, 0.12), (0.575, 0, 1.0), M["plate"])
    for v in (-1, 1):
        put((1.15, 0.14, 1.0), (0.575, v * (length / 2 - 0.07), 0.06), M["frame"])
    put((0.08, length, 1.0), (0.04, 0, 0.06), M["frame"])
    put((0.95, length - 0.4, 0.1), (0.6, 0, 0.12), M["char"], detail=True)
    put((0.04, length - 0.9, 0.05), (0.1, 0, 0.85), M["strip"], detail=True)
    put((0.06, length - 0.2, 0.06), (1.15, 0, 1.06), M["strip"], detail=True)


def cell_door(M, at, facing, lit=True):
    """A closed door to somebody's cell, on a wall's face, with its light over it."""
    put = _against(at, facing)
    put((0.14, 1.3, 2.2), (0.05, 0, 0), M["black"])
    put((0.1, 1.7, 0.2), (0.06, 0, 2.2), M["frame"], detail=True)
    if lit:
        put((0.06, 1.1, 0.06), (0.12, 0, 2.27), M["strip"], detail=True)
        put((0.05, 0.08, 0.5), (0.13, 0.85, 1.0), M["strip"], detail=True)


def portal(M, at, facing, r=1.6, tall=1.4):
    """A six-sided window onto the furnace light, in a heavy frame, on a wall's face: `at` is its
    middle."""
    n = FACING[facing]
    rot = (0, math.pi / 2, 0) if n[0] else (math.pi / 2, 0, 0)
    for rr, depth, name, detail in ((r * 1.34, 0.5, "plate", False), (r * 1.12, 0.8, "frame", True), (r, 1.0, "ember", True)):
        ob = cyl(rr, depth, (at[0] + n[0] * depth / 2, at[1] + n[1] * depth / 2, at[2]), M[name], verts=6, rot=rot, detail=detail)
        ob.scale = (tall, 1, 1) if n[0] else (1, tall, 1)


def furnace_core(M, at, h=11.0, r=1.5):
    """The fire column of a great furnace, ribbed, between two cheeks under a hood."""
    x, y, z = at
    cyl(r * 2.5, 0.7, at, M["plate"], verts=8, turn=OCT)
    cyl(r, h, (x, y, z + 0.7), M["ember"], verts=12)
    for i in range(int(h / 1.15)):
        cyl(r * 1.16, 0.55, (x, y, z + 1.1 + i * 1.15), M["frame"], verts=12, detail=True)
    box((r * 3.4, 0.8, h + 0.7), (x, y - r - 0.5, z), M["frame"], bevel=0.25)
    for s in (-1, 1):
        box((1.5, 3.0, h + 0.7), (x + s * (r + 1.25), y - 0.3, z), M["plate"], bevel=0.3)
        box((2.4, 3.8, h * 0.32), (x + s * (r + 1.7), y - 0.3, z), M["plate"], bevel=0.35)
        box((0.08, 0.3, h * 0.5), (x + s * (r + 0.48), y + 1.22, z + h * 0.4), M["strip"], detail=True)
    box((r * 2 + 5.4, 4.0, 1.8), (x, y - 0.3, z + h + 0.7), M["plate"], bevel=0.45)
    cyl(r * 1.5, 1.2, (x, y - 0.3, z + h + 2.5), M["frame"], verts=8, top=r * 0.9, turn=OCT)
    box((r * 2 + 3.0, 0.1, 0.12), (x, y + 1.72, z + h + 1.1), M["strip"], detail=True)


def hearth(M, at, r=1.5, hood_at=None):
    """A fire pit under a grate, with its kerb; `hood_at` hangs a hood over it from that height."""
    x, y, z = at
    cyl(r * 1.22, 0.38, at, M["frame"], verts=8, turn=OCT)
    cyl(r, 0.4, at, M["grate"], verts=8, turn=OCT)
    if hood_at:
        cyl(r * 1.3, hood_at[1] - hood_at[0], (x, y, hood_at[0]), M["plate"], verts=8, top=r * 0.6, turn=OCT)
        collar(r * 1.22, r * 1.32, 0.07, (x, y, hood_at[0] - 0.02), M["strip"], detail=True)


def ashen_home(M, mirror=1):
    """A brood den: sleeping cells stacked along one wall, a hearth in the middle of the floor, a
    bench and canisters along the other, and a store behind."""
    s = mirror
    shell(-6, 6, -14, 2, 3.6, M["floor"], M["plate"])
    wall((-6, 2), (6, 2), 0, 3.6, M["plate"])
    wall((-6, 2), (-6, -14), 0, 3.6, M["plate"])
    wall((6, 2), (6, -14), 0, 3.6, M["plate"])
    wall((-6, -14), (6, -14), 0, 3.6, M["plate"])
    wall((-6, -9.5), (6, -9.5), 0, 3.6, M["plate"], gaps=[(6 - s * 3.0, 1.6, 2.4)], t=0.3)
    way_out(M, 2, frame="strip", door="black", lamp="ember")
    for sx in (-1, 1):
        cut_corner(M, sx * 5.8, 1.8, 1.3, 3.6)
        floor_light(M, (sx * 5.74, 0.4), (sx * 5.74, -9.3), z=0.12)
    hearth(M, (0, -4.6, 0), 1.4, hood_at=(2.6, 3.6))
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        cyl(0.32, 0.45, (math.cos(a) * 2.7, -4.6 + math.sin(a) * 2.7, 0), M["frame"], verts=6)
    side = "-x" if s > 0 else "+x"
    for i in range(3):  # the sleeping cells, two high
        for z in (0.2, 1.6):
            pod(M, (s * 5.8, -0.3 - i * 2.8, z), side)
    box((0.7, 0.5, 0.6), (s * 4.3, -7.2, 0), M["frame"], bevel=0.06)  # the step up to the upper cells
    other = "+x" if s > 0 else "-x"
    box((1.0, 3.6, 0.9), (-s * 5.3, -5.6, 0), M["frame"], bevel=0.08)  # the bench
    box((0.7, 1.0, 0.05), (-s * 5.3, -5.0, 0.9), M["strip"], detail=True)
    display(M, (-s * 5.8, -5.6, 1.35), other, w=0.6, h=0.9, frame="black", lamp="strip")
    for i in range(3):  # canisters
        cyl(0.42, 1.9, (-s * 5.2, -0.4 - i * 1.0, 0), M["frame"], verts=6)
        cyl(0.44, 0.1, (-s * 5.2, -0.4 - i * 1.0, 1.4), M["strip"], verts=6, detail=True)
    for y in (-1.2, -7.8):  # ribs across the roof, lit beneath
        box((11.6, 0.5, 0.4), (0, y, 3.2), M["frame"])
        box((7.0, 0.1, 0.05), (0, y, 3.16), M["strip"], detail=True)
    tank(M, (-s * 3.6, -12.0, 0), 1.0, 1.9)  # the store
    box((1.2, 1.2, 1.0), (s * 4.6, -12.6, 0), M["frame"], bevel=0.1)
    box((1.0, 1.0, 0.9), (s * 4.5, -12.5, 1.0), M["plate"], bevel=0.1)
    box((1.2, 1.2, 1.0), (s * 3.0, -12.9, 0), M["plate"], bevel=0.1)
    floor_light(M, (-5.6, -13.74), (5.6, -13.74), z=0.12)
    marker("light1", (0, 0.2, 3.0))
    marker("light2", (0, -12.0, 3.0))
    marker("light3", (-3.8, -6.6, 3.0))
    marker("light4", (3.8, -6.6, 3.0))


def ashen_spire(M, mirror=1):
    """A spire from the inside: galleries of cells round a furnace shaft, a bridge to the column
    that runs up through it, and one cell standing open."""
    s = mirror
    c = (0.0, -12.0)
    H = 14.0
    slab_with_hole((28.4, 28.4), 5.0, 0.4, (c[0], c[1], -0.4), M["floor"])
    box((28.4, 28.4, 0.4), (c[0], c[1], H), M["plate"])
    wall((-14, 2), (14, 2), 0, H, M["plate"])
    wall((-14, -26), (14, -26), 0, H, M["plate"])
    wall((-s * 14, 2), (-s * 14, -26), 0, H, M["plate"])
    wall((s * 14, 2), (s * 14, -26), 0, H, M["plate"], gaps=[(14, 1.6, 2.4)])
    for sx in (-1, 1):
        for y in (1.8, -25.8):
            cut_corner(M, sx * 13.8, y, 5.0, H)
    way_out(M, 2, frame="strip", door="black", lamp="ember")
    # The shaft: its lining, the fire at its foot, the column up through it and the way across.
    collar(5.0, 5.5, 9.0, (c[0], c[1], -9.4), M["plate"])
    cyl(5.5, 0.3, (c[0], c[1], -9.7), M["grate"], verts=8, turn=OCT)
    cyl(1.3, H + 9.4, (c[0], c[1], -9.4), M["frame"], verts=8, turn=OCT)
    for i in range(9):
        cyl(1.36, 0.45, (c[0], c[1], -8.2 + i * 2.6), M["ember"], verts=8, turn=OCT, detail=True)
    collar(1.25, 2.8, 0.4, (c[0], c[1], -0.4), M["floor"])
    apothem = 5.0 * math.cos(OCT)
    for side in (1, -1):  # the two bridges, front and back
        y = c[1] + side * (apothem + 2.8 * math.cos(OCT)) / 2
        box((2.2, apothem - 2.8 * math.cos(OCT) + 0.3, 0.4), (0, y, -0.4), M["floor"])
        for sx in (-1, 1):
            rail(M, (sx * 1.1, y), apothem - 2.8 * math.cos(OCT) - 0.2, math.pi / 2, 0)
            rail(M, (sx * 1.52, c[1] + side * (apothem + 0.2)), 0.82, 0, 0)
    rail_ring(M, c, apothem + 0.2, 0, skip=(2, 6))
    rail_ring(M, c, 2.8 * math.cos(OCT) - 0.12, 0, skip=(2, 6))
    cyl(3.4, 0.1, (c[0], c[1], H - 0.1), M["strip"], verts=8, turn=OCT, detail=True)
    # The galleries above, their cells shut.
    for z in (5.0, 9.5):
        slab_with_hole((28.4, 28.4), 9.0, 0.4, (c[0], c[1], z - 0.4), M["floor"])
        rail_ring(M, c, 9.0 * math.cos(OCT) + 0.2, z)
        for k in range(8):  # light under the gallery's edge
            a = k * math.tau / 8
            box((6.4, 0.12, 0.05), (c[0] + math.cos(a) * 8.1, c[1] + math.sin(a) * 8.1, z - 0.46), M["strip"], rot=(0, 0, a + math.pi / 2), detail=True)
    for z in (0.0, 5.0, 9.5):
        for x in (-5.5, 0.0, 5.5):
            cell_door(M, (x, -25.8, z), "+y")
        for y in (-6.5, -12.0, -17.5):
            cell_door(M, (-s * 13.8, y, z), "+x" if s > 0 else "-x")
            if not (z == 0.0 and y == -12.0):  # the open cell
                cell_door(M, (s * 13.8, y, z), "-x" if s > 0 else "+x")
    for sx in (-1, 1):
        for y in (-3.5, -20.5):
            pillar(M, (sx * 8.6, y, 0), 1.5, H, lamp=2.6)
        display(M, (sx * 4.6, 1.8, 1.3), "-y", frame="black", lamp="strip")
        floor_light(M, (sx * 13.74, -2.6), (sx * 13.74, -21.4), z=0.12)
    floor_light(M, (-8.6, -25.74), (8.6, -25.74), z=0.12)
    for sx in (-1, 1):  # lines in the floor from the door to the bridge
        floor_light(M, (sx * 1.3, 0.6), (sx * 1.3, c[1] + apothem + 0.6))
    marker("light1", (0, -2.5, 4.0))
    marker("light2", (4.5, -12.0, 12.5))
    marker("light3", (-10.0, -12.0, 4.0))
    marker("light4", (10.0, -12.0, 4.0))
    marker("light5", (0, -22.0, 4.0))
    marker("light6", (3.2, -12.0, -5.0))
    # The open cell.
    x0, x1 = (14, 22) if s > 0 else (-22, -14)
    shell(x0, x1, -16, -8, 3.2, M["floor"], M["plate"])
    wall((x0, -8), (x1, -8), 0, 3.2, M["plate"])
    wall((x0, -16), (x1, -16), 0, 3.2, M["plate"])
    wall((s * 22, -8), (s * 22, -16), 0, 3.2, M["plate"])
    for y in (-10.0, -14.0):
        for z in (0.2, 1.6):
            pod(M, (s * 21.8, y, z), "-x" if s > 0 else "+x", length=2.2)
    hearth(M, (s * 17.5, -12.0, 0), 0.8)
    box((2.6, 0.8, 0.9), (s * 17.0, -15.3, 0), M["frame"], bevel=0.08)
    display(M, (s * 17.5, -8.2, 1.2), "-y", w=0.6, h=0.9, frame="black", lamp="strip")
    floor_light(M, (x0 + 0.4, -15.74), (x1 - 0.4, -15.74), z=2.9)
    marker("light7", (s * 18.0, -12.0, 2.7))


def ashen_hall(M):
    """The Furnace Court: a gatehouse, then the great hall, with its furnace hatch in the floor,
    piers and galleries down both sides, a gantry across, and the great furnace on its dais."""
    shell(-5, 5, -6, 3, 5, M["floor"], M["plate"])
    wall((-5, 3), (5, 3), 0, 5, M["plate"])
    wall((-5, 3), (-5, -6), 0, 5, M["plate"])
    wall((5, 3), (5, -6), 0, 5, M["plate"])
    way_out(M, 3, frame="strip", door="black", lamp="ember")
    for s in (-1, 1):
        cut_corner(M, s * 4.8, 2.8, 1.4, 5)
        box((0.08, 6.5, 0.2), (s * 4.76, -1.5, 2.4), M["strip"], detail=True)
        display(M, (s * 3.9, -5.8, 1.3), "+y", frame="black", lamp="strip")
    marker("light1", (0, -1.5, 4.2))
    H = 16.0
    shell(-16, 16, -56, -6, H, M["floor"], M["plate"])
    wall((-16, -6), (16, -6), 0, H, M["plate"], gaps=[(16, 5.0, 4.4)])
    wall((-16, -6), (-16, -56), 0, H, M["plate"])
    wall((16, -6), (16, -56), 0, H, M["plate"])
    wall((-16, -56), (16, -56), 0, H, M["plate"])
    for s in (-1, 1):
        cut_corner(M, s * 15.8, -55.8, 4.5, H)
    # The furnace hatch, with its warning border.
    box((7.0, 7.0, 0.05), (0, -20, 0), M["grate"])
    for a in range(4):
        dx, dy = ((1, 0), (0, 1), (-1, 0), (0, -1))[a]
        box((0.5, 8.0, 0.06) if dx else (8.0, 0.5, 0.06), (dx * 3.75, -20 + dy * 3.75, 0), M["hazard"], detail=True)
    for s in (-1, 1):
        floor_light(M, (s * 4.6, -8.0), (s * 4.6, -36.5))
    # Piers, the galleries behind them and the ramps up.
    rows = [-12.0, -21.0, -30.0, -39.0, -48.0]
    for s in (-1, 1):
        for y in rows:
            pillar(M, (s * 10.5, y, 0), 1.8, H, lamp=5.0)
        box((5.7, 50.0, 0.4), (s * 13.25, -31.0, 5.1), M["floor"])
        wall((s * 10.4, -6.2), (s * 10.4, -55.8), 5.5, 1.05, M["plate"], gaps=[(27.1, 2.4, 1.05)], t=0.18)
        box((0.12, 44.0, 0.05), (s * 10.6, -31.0, 5.04), M["strip"], detail=True)
        ramp(2.2, 11.0, 5.5, (s * 8.0, -45.5, 0), M["floor"], along="+y")
        for i in range(1, 22):  # treads
            box((2.2, 0.08, 0.05), (s * 8.0, -45.5 + i * 0.5, i * 0.25), M["frame"], detail=True)
        box((3.7, 2.4, 0.4), (s * 8.85, -33.3, 5.1), M["floor"])
        rail(M, (s * 8.85, -32.2), 3.7, 0, 5.5)
        rail(M, (s * 7.1, -33.3), 2.2, math.pi / 2, 5.5)
        out = "-x" if s > 0 else "+x"
        for y in (-16.5, -25.5, -43.5, -52.0):
            cell_door(M, (s * 15.8, y, 5.5), out)
        for y in (-16.5, -34.5):
            portal(M, (s * 15.8, y, 11.0), out, r=1.5, tall=1.5)
        for y in (-25.5, -43.5):
            display(M, (s * 15.8, y, 1.4), out, w=1.2, h=1.8, frame="black", lamp="strip")
        for y in (-16.5, -34.5, -52.0):
            cell_door(M, (s * 15.8, y, 0), out)
        box((0.08, 48.0, 0.05), (s * 15.76, -31.0, 0.12), M["strip"], detail=True)
        tank(M, (s * 6.8, -10.8, 0), 2.3, 5.2)
        marker(f"light{5 + (s > 0)}", (s * 13.2, -25.5, 4.0))
        marker(f"light{7 + (s > 0)}", (s * 13.2, -43.5, 4.0))
    for y in rows:  # beams over, lit beneath
        box((32.0, 1.0, 1.2), (0, y, H - 1.2), M["frame"])
        box((16.0, 0.14, 0.06), (0, y, H - 1.26), M["strip"], detail=True)
    # The gantry across the hall.
    box((19.4, 2.6, 0.5), (0, -30.0, 9.3), M["frame"])
    for sy in (-1, 1):
        rail(M, (0, -30.0 + sy * 1.2), 19.2, 0, 9.8)
        box((15.0, 0.1, 0.05), (0, -30.0 + sy * 0.9, 9.26), M["strip"], detail=True)
    cyl(1.3, 1.5, (0, -30.0, 7.8), M["frame"], verts=8, turn=OCT)
    cyl(0.8, 0.16, (0, -30.0, 7.66), M["ember"], verts=8, turn=OCT, detail=True)
    # The dais and the great furnace.
    cyl(9.0, 0.6, (0, -48.0, 0), M["floor"], verts=8, turn=OCT)
    cyl(6.6, 0.6, (0, -48.0, 0.6), M["floor"], verts=8, turn=OCT)
    ramp(4.0, 2.3, 0.6, (0, -48.0 + 9.0 * math.cos(OCT) + 2.3, 0), M["floor"], along="-y")
    ramp(4.0, 2.2, 0.6, (0, -48.0 + 6.6 * math.cos(OCT) + 2.2, 0.6), M["floor"], along="-y")
    cyl(9.02, 0.06, (0, -48.0, 0.5), M["strip"], verts=8, turn=OCT, detail=True)
    furnace_core(M, (0, -50.0, 1.2), h=10.5, r=1.5)
    for s in (-1, 1):
        box((1.7, 1.0, 1.1), (s * 3.8, -44.2, 1.2), M["frame"], bevel=0.1)
        box((1.4, 0.75, 0.05), (s * 3.8, -44.2, 2.36), M["strip"], rot=(math.radians(-22), 0, 0), detail=True)
        portal(M, (s * 9.0, -55.8, 7.0), "+y", r=2.1, tall=1.5)
    text("ASHEN", 1.5, (8.6, -55.7, 11.4), M["strip"])  # +x is on your left as you come in
    text("COLLECTIVE", 1.5, (-8.6, -55.7, 11.4), M["strip"])
    marker("light2", (0, -14.0, 13.0))
    marker("light3", (0, -24.0, 13.0))
    marker("light4", (0, -38.0, 13.0))
    marker("light9", (0, -44.0, 8.5))
    marker("light10", (0, -20.0, 3.0))


ASHEN = {
    "inside_hall": ashen_hall,
    "inside_zone_low_1": ashen_home,
    "inside_zone_low_2": lambda M: ashen_home(M, mirror=-1),
    "inside_zone_high_1": ashen_spire,
    "inside_zone_high_2": lambda M: ashen_spire(M, mirror=-1),
}

INSIDES = {"compact": COMPACT, "ashen": ASHEN}

# More views of an inside for --render, after the one from the door: (eye, look at, lens).
VIEWS = {
    "ashen": {
        "inside_hall": [((0, -7.5, 1.7), (0, -48, 6.0), 15), ((-12.8, -14.5, 7.4), (6.0, -40.0, 5.5), 15),
                        ((4.5, -36.5, 1.8), (0, -50.0, 7.5), 16), ((-7.5, -13.5, 1.7), (3.0, -24.0, 1.0), 16)],
        "inside_zone_high_1": [((2.9, -9.3, 3.2), (1.2, -11.2, -9.4), 13), ((-12.0, -9.0, 7.0), (6.0, -14.0, 3.5), 14),
                               ((14.6, -12.0, 1.6), (22.0, -12.6, 1.1), 15)],
        "inside_zone_low_1": [((-4.6, 0.6, 1.7), (3.5, -7.0, 1.0), 16)],
    },
}

