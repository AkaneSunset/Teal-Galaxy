"""The factions' city pieces, modelled in Blender and exported for Godot.

Each piece is built to its footprint in metres (one city cell is 10 m) with its origin on the ground
in the middle, and its front (doors, signs) toward Blender's +Y, which is -Z in Godot. Small parts
(lights, rails, grates) go in a separate "detail" object that the game stops drawing from far away.
Everything else is joined into one object, so a piece is one or two meshes for the city's batches.

Run with Blender:   blender -b -P tools/blender/city_models.py -- compact [--render DIR]
or with the bpy module (pip install bpy):   python tools/blender/city_models.py compact [--render DIR]

Writes game/city/<faction>/<piece>.glb (Godot imports them; game/city.gd loads them by name).
--render also writes a PNG of each piece to DIR, for checking the look without the game.
--sheet DIR writes one PNG per faction of all its zone housing side by side.

kit.py holds the shared parts and export; housing.py the zone housing (many looks per faction).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import housing  # noqa: E402
import kit  # noqa: E402
from kit import CELL, box, compact_mats, cyl, finish, pilasters, render, reset, slits, text, twin_turret  # noqa: E402

# --- The Terran Compact ----------------------------------------------------------------------------
# Dark navy naval-industrial armour, chamfered blocks, blue window slits, amber work lights, huge
# white stencils, yellow hazard stripes, twin-barrel turrets. See the "Faction building designs" doc.

def compact_hall(M):
    """The Government Hall: a fortress keep of stepped blocks, crowned with spire towers."""
    box((64, 64, 4), (0, 0, 0), M["steel"], bevel=0.8)
    for sx in (-1, 1):  # hazard stripes on the plinth edge
        box((0.6, 60, 0.25), (sx * 31.6, 0, 4.0), M["hazard"], detail=True)
        box((60, 0.6, 0.25), (0, sx * 31.6, 4.0), M["hazard"], detail=True)
    tiers = [(54, 18, "navy", 7), (42, 16, "slate", 9), (30, 14, "navy", 0)]
    z = 4.0
    for w, h, m, bare in tiers:
        box((w, w, h), (0, 0, z), M[m], bevel=1.6)
        pilasters(M, w, w, z, h)
        slits(M, w, w, z + 2, h - 3, every=4.5, skip_front=bare)
        box((w + 1.2, w + 1.2, 1.0), (0, 0, z + h - 0.5), M["steel"], bevel=0.3)  # ledge
        z += h
    # The keep's central tower and its stepped, slightly gothic crown and mast.
    box((12, 12, 26), (0, 0, z), M["slate"], bevel=1.0)
    slits(M, 12, 12, z + 2, 22, every=3.5)
    box((14, 14, 2.5), (0, 0, z + 26), M["steel"], bevel=0.5)
    box((9, 9, 8), (0, 0, z + 28.5), M["navy"], bevel=0.8)
    box((9.4, 9.4, 1.0), (0, 0, z + 34), M["blue"])
    cyl(3.2, 10, (0, 0, z + 36.5), M["slate"], verts=8, top=0.6)
    cyl(0.35, 18, (0, 0, z + 46.5), M["steel"], verts=6)
    cyl(0.6, 0.8, (0, 0, z + 64.5), M["blue"], verts=8, detail=True)
    # Four corner spires on the second tier.
    zc = 4 + 18 + 16
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 17.5, sy * 17.5
            box((6, 6, 20), (x, y, zc), M["navy"], bevel=0.6)
            box((6.4, 6.4, 0.8), (x, y, zc + 16), M["blue"])
            cyl(2.6, 9, (x, y, zc + 20), M["slate"], verts=4, top=0.2)
            cyl(0.25, 6, (x, y, zc + 29), M["steel"], verts=6, detail=True)
    # The front: a great armoured gate, a ramp up to it, work lights, and the stencil.
    box((16, 3, 10), (0, 26.6, 4), M["dark"])
    box((18, 2.6, 1.2), (0, 27.4, 14), M["steel"], bevel=0.3)
    box((16, 6, 4), (0, 31, 0), M["deck"])
    for sx in (-1, 1):
        box((0.6, 0.6, 0.6), (sx * 9.5, 28.6, 13.0), M["amber"], detail=True)
        box((0.6, 0.6, 0.6), (sx * 25, 27.6, 20.5), M["amber"], detail=True)
    text("TERRAN COMPACT", 3.6, (0, 27.25, 18.6), M["white"])
    # The eagle, on the second tier: two swept wings either side of a shield.
    for sx in (-1, 1):
        box((8, 0.4, 1.4), (sx * 6.0, 21.2, 33.4), M["white"], rot=(0, sx * math.radians(18), 0))
        box((6, 0.4, 1.0), (sx * 5.0, 21.2, 31.4), M["white"], rot=(0, sx * math.radians(18), 0))
    box((3.0, 0.5, 4.2), (0, 21.25, 29.6), M["blue"])
    # Twin turrets on the plinth corners.
    for sx in (-1, 1):
        for sy in (-1, 1):
            twin_turret(M, (sx * 29.5, sy * 29.5, 4.0), scale=0.75)


def compact_tower(M, height, foot):
    """Tower Block and High-rise: stacked armoured blocks with blue slits and a spire crown."""
    w = foot * 0.9
    box((w, w, 3), (0, 0, 0), M["steel"], bevel=0.4)
    z = 3.0
    steps = [(0.92, 0.45), (0.8, 0.35), (0.66, 0.2)]
    body = height * 0.82 - 3
    for k, share in steps:
        h = body * share
        b = w * k
        box((b, b, h), (0, 0, z), M["navy"] if k != 0.8 else M["slate"], bevel=max(0.4, b * 0.06))
        pilasters(M, b, b, z, h)
        slits(M, b, b, z + 1.5, h - 2, every=3.2)
        box((b + 0.8, b + 0.8, 0.6), (0, 0, z + h - 0.3), M["steel"])
        for sx in (-1, 1):
            box((0.5, 0.5, 0.5), (sx * (b / 2 + 0.2), b / 2 + 0.2, z + h + 0.2), M["amber"], detail=True)
        z += h
    top = w * 0.5
    box((top, top, height * 0.06), (0, 0, z), M["slate"], bevel=0.3)
    box((top + 0.4, top + 0.4, 0.6), (0, 0, z + height * 0.06), M["blue"])
    cyl(top * 0.45, height * 0.1, (0, 0, z + height * 0.06 + 0.6), M["navy"], verts=4, top=0.2)
    cyl(0.18 * foot / 10, height * 0.12, (0, 0, z + height * 0.16), M["steel"], verts=6, detail=True)
    if height > 60:  # the high-rise's crown: four small spires round the top
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl(0.9, height * 0.07, (sx * top * 0.42, sy * top * 0.42, z + height * 0.06 + 0.6), M["slate"], verts=4, top=0.1)
    text("B-%02d" % (int(height) % 97), w * 0.16, (w * 0.22, w * 0.92 / 2 + 0.25, 5.0), M["white"])
    box((w * 0.3, 0.4, 2.6), (-w * 0.2, w / 2, 0), M["dark"])  # the door


def compact_road(M):
    box((10, 10, 0.3), (0, 0, 0), M["deck"])
    for sx in (-1, 1):
        box((0.35, 10, 0.06), (sx * 4.3, 0, 0.3), M["hazard"])
    for y in (-2.5, 2.5):
        box((1.2, 0.8, 0.05), (0, y, 0.3), M["dark"], detail=True)  # grates
    for x in (-3, 0, 3):  # the plate seams
        box((0.08, 10, 0.04), (x, 0, 0.3), M["dark"], detail=True)


def compact_plaza(M):
    box((19.8, 19.8, 0.35), (0, 0, 0), M["deck"])
    box((19.8, 0.5, 0.06), (0, 9.65, 0.35), M["hazard"])
    box((19.8, 0.5, 0.06), (0, -9.65, 0.35), M["hazard"])
    for x in (-6, -2, 2, 6):  # the bays
        box((0.25, 7, 0.05), (x, -4, 0.35), M["white"], detail=True)
    cyl(1.4, 0.8, (0, 4, 0.35), M["slate"], verts=8)
    cyl(0.15, 12, (0, 4, 1.15), M["steel"], verts=6)
    box((3.6, 0.08, 2.2), (1.85, 4, 10.5), M["navy"])  # the flag
    box((1.2, 0.1, 1.0), (1.85, 4, 11.1), M["white"], detail=True)
    for sx in (-1, 1):
        cyl(0.15, 5, (sx * 8.5, 8.5, 0.35), M["steel"], verts=6, detail=True)
        box((0.6, 0.6, 0.4), (sx * 8.5, 8.5, 5.35), M["amber"], detail=True)


def compact_wall(M):
    box((20, 4.0, 2), (0, 0, 0), M["steel"])
    box((20, 3.2, 7), (0, 0, 2), M["navy"], bevel=0.3)
    box((20, 0.6, 1.4), (0, 1.6, 9), M["slate"])  # the parapet
    box((20, 0.5, 0.2), (0, -1.3, 9), M["hazard"], detail=True)  # the walkway edge
    box((14, 0.25, 0.4), (0, 1.75, 6.0), M["blue"])
    for x in (-7, 7):
        box((0.5, 0.5, 0.5), (x, 2.0, 7.4), M["amber"], detail=True)


def compact_turret(M):
    box((9, 9, 1.0), (0, 0, 0), M["steel"], bevel=0.3)
    twin_turret(M, (0, -0.5, 1.0), scale=1.0)


COMPACT = {
    "hall": (compact_hall, (7, 7), 110),
    "tower": (lambda M: compact_tower(M, 40.0, 20.0), (2, 2), 40),
    "highrise": (lambda M: compact_tower(M, 90.0, 30.0), (3, 3), 90),
    "road": (compact_road, (1, 1), 2),
    "plaza": (compact_plaza, (2, 2), 12),
    "wall": (compact_wall, (2, 1), 10),
    "turret": (compact_turret, (1, 1), 8),
}

FACTIONS = {
    "compact": (compact_mats, COMPACT),
    "ashen": (kit.ashen_mats, {}),
    "luminar": (kit.luminar_mats, {}),
    "coma": (kit.coma_mats, {}),
}
for _faction, (_mats, _pieces) in FACTIONS.items():
    _pieces.update(housing.pieces(_faction))


def sheet(path, faction):
    """One picture of all the faction's zone housing: the low-density lots in front, the
    high-density ones behind, loaded back from the exported files."""
    reset()
    folder = os.path.join(kit.ROOT, "game", "city", faction)
    for row, (name, pitch, y) in enumerate((("zone_low", 26.0, 34.0), ("zone_high", 36.0, -14.0))):
        for v in range(1, housing.VARIANTS + 1):
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(folder, f"{name}_{v}.glb"))
            for ob in set(bpy.data.objects) - before:
                if ob.parent is None:
                    ob.location.x -= (v - 3.5) * pitch  # the camera looks back along Y: number 1 on the left
                    ob.location.y += y
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.resolution_x, scene.render.resolution_y = 1800, 900
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.4, 0.52, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scene.world = world
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(52), 0, math.radians(150)))
    bpy.context.object.data.energy = 3.0
    bpy.ops.mesh.primitive_plane_add(size=900, location=(0, 0, -0.05))
    bpy.context.object.data.materials.append(kit.mat("ground", "#3a3f44", metal=0, rough=0.9))
    bpy.ops.object.camera_add(location=(60, 235, 105))
    cam = bpy.context.object
    target = bpy.data.objects.new("target", None)
    target.location = (0, 0, 30)
    scene.collection.objects.link(target)
    c = cam.constraints.new("TRACK_TO")
    c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"
    cam.data.lens = 34
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    dirs = {}
    for flag in ("--render", "--sheet"):
        if flag in args:
            i = args.index(flag)
            dirs[flag] = args[i + 1]
            del args[i:i + 2]
            os.makedirs(dirs[flag], exist_ok=True)
    only = args[1:]  # piece names, or a family: "zone" or "zone_low" builds every one of them
    for faction in args[:1] or list(FACTIONS):
        make_mats, pieces = FACTIONS[faction]
        for piece, (build, cells, height) in pieces.items():
            if only and not any(piece == o or piece.startswith(o + "_") for o in only):
                continue
            reset()
            build(make_mats())
            finish(faction, piece)
            if "--render" in dirs:
                render(os.path.join(dirs["--render"], f"{faction}_{piece}.png"), (cells[0] * CELL, cells[1] * CELL), height)
        if "--sheet" in dirs:
            sheet(os.path.join(dirs["--sheet"], f"{faction}_housing.png"), faction)


if __name__ == "__main__":
    main(sys.argv)
