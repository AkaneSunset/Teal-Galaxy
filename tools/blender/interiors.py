"""The insides of city buildings: what you walk around after going in at a building's door.

An inside is its own small place, exported as game/city/<faction>/inside_<piece>.glb (or
inside_<piece>_<n>.glb where a piece has several). You come in at the origin looking along -Y, the
door back out is behind you, and the floor's top is z = 0. Rooms are built from thick slabs (floors,
walls with doorways, ceilings) so the game can stand you on them and stop you at them: it makes
everything but the "detail" mesh solid. Markers say where the way out is ("exit") and where the
lamps hang ("light1", "light2"...).
"""

import math

from kit import box, cyl, marker, ring, text, wall


def shell(x0, x1, y0, y1, h, floor, ceil, z=0.0):
    """A room's floor and ceiling over x0..x1, y0..y1 (walls are added one by one, for doorways)."""
    w, d = x1 - x0, y1 - y0
    c = ((x0 + x1) / 2, (y0 + y1) / 2)
    box((w + 0.4, d + 0.4, 0.4), (c[0], c[1], z - 0.4), floor)
    box((w + 0.4, d + 0.4, 0.4), (c[0], c[1], z + h), ceil)


def way_out(M, y, frame="hazard"):
    """The door you came in by, in the wall behind you at `y`, and the marker the game uses."""
    box((2.2, 0.2, 2.6), (0, y - 0.25, 0), M["dark"])
    box((2.6, 0.15, 0.15), (0, y - 0.3, 2.6), M[frame], detail=True)
    for s in (-1, 1):
        box((0.15, 0.15, 2.6), (s * 1.2, y - 0.3, 0), M[frame], detail=True)
    box((0.5, 0.1, 0.25), (0, y - 0.4, 2.9), M["amber"], detail=True)
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

INSIDES = {"compact": COMPACT}
