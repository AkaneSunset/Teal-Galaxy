"""Propaganda: the posters each faction shows on the displays inside its buildings.

Each faction gets four, written to game/city/<faction>/propaganda/poster_<n>.png (512 x 768):

  1. the monument: one of its own buildings from below, against a rising sun
  2. the badge: its emblem
  3. the skyline: its city by night, lights on
  4. the notice: an order, in type

The buildings in 1 and 3 are the faction's real models, rendered in Blender from the exported
.glb files and cut down to a few flat inks; the rest is drawn with Pillow. So build the models
first (city_models.py), then:

  python tools/blender/propaganda.py [faction ...] [--sheet DIR]

--sheet also writes one picture of every poster, for looking them over. The type is Inter,
Caladea and JetBrains Mono (the script falls back to Pillow's own face where one is missing).
"""

import math
import os
import sys

import bpy
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import kit

W, H = 1024, 1536  # drawn at twice the size they are saved at
OUT = (512, 768)
TAU = math.tau
CACHE = os.path.join(kit.ROOT, "tools", "blender", ".cache")
FONTS = {
    "black": "/usr/share/fonts/opentype/inter/Inter-Black.otf",
    "bold": "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "medium": "/usr/share/fonts/opentype/inter/Inter-Medium.otf",
    "serif": "/usr/share/fonts/truetype/crosextra/Caladea-Bold.ttf",
    "mono": "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-ExtraBold.ttf",
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)


# --- Lettering -------------------------------------------------------------------------------------

def lettering(body, font, fill, squeeze=1.0, track=0.0, px=300):
    """The words as a tight picture: `squeeze` narrows the letters, `track` spaces them out
    (as a share of the type's size)."""
    try:
        f = ImageFont.truetype(FONTS[font], px)
    except OSError:
        f = ImageFont.load_default(px)
    gap = px * track
    width = int(sum(f.getlength(c) + gap for c in body)) + px
    im = Image.new("RGBA", (width, px * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x = px / 2
    for c in body:
        d.text((x, px / 2), c, font=f, fill=fill)
        x += f.getlength(c) + gap
    im = im.crop(im.getbbox())
    if squeeze != 1.0:
        im = im.resize((max(1, int(im.width * squeeze)), im.height), Image.LANCZOS)
    return im


def fitted(body, font, fill, w, h, **how):
    """The words scaled to fit inside w x h."""
    im = lettering(body, font, fill, **how)
    k = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)


def put(sheet, im, cx, y):
    """Pastes a picture with its top centre at (cx, y)."""
    sheet.alpha_composite(im, (int(cx - im.width / 2), int(y)))


def stack(sheet, lines, font, fill, x0, x1, y0, y1, gap=26, tallest=330, **how):
    """Lines of type set one under another, each as wide as the column, the whole block centred
    in y0..y1 (and shrunk to fit it)."""
    ims = [fitted(body, font, fill, x1 - x0, tallest, **how) for body in lines]
    total = sum(im.height for im in ims) + gap * (len(ims) - 1)
    if total > y1 - y0:
        k = (y1 - y0) / total
        ims = [im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS) for im in ims]
        gap *= k
        total = y1 - y0
    y = y0 + (y1 - y0 - total) / 2
    for im in ims:
        put(sheet, im, (x0 + x1) / 2, y)
        y += im.height + gap


# --- Drawing ---------------------------------------------------------------------------------------

def burst(d, cx, cy, rays, r, fill, phase=0.0):
    for i in range(rays):
        a0 = phase + TAU * i / rays
        a1 = a0 + TAU / rays / 2
        d.polygon([(cx, cy), (cx + r * math.cos(a0), cy + r * math.sin(a0)), (cx + r * math.cos(a1), cy + r * math.sin(a1))], fill=fill)


def disc(d, cx, cy, r, fill=None, outline=None, width=1):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill, outline=outline, width=width)


def poly(d, cx, cy, r, pts, fill, outline=None, width=0):
    at = [(cx + x * r, cy + y * r) for x, y in pts]
    d.polygon(at, fill=fill)
    if outline:
        d.line(at + [at[0]], fill=outline, width=width, joint="curve")


def star(d, cx, cy, r, fill, points=5, inner=0.42):
    d.polygon([(cx + (r if i % 2 == 0 else r * inner) * math.sin(TAU * i / points / 2), cy - (r if i % 2 == 0 else r * inner) * math.cos(TAU * i / points / 2)) for i in range(points * 2)], fill=fill)


def header(sheet, P, title, y=62):
    """The faction's name across the top, between two rules."""
    d = ImageDraw.Draw(sheet)
    im = fitted(title, P["font"], P["ink"], W - 420, 38, squeeze=P["squeeze"], track=0.22)
    put(sheet, im, W / 2, y)
    mid = y + im.height / 2
    for s in (-1, 1):
        d.line((W / 2 + s * (im.width / 2 + 34), mid, W / 2 + s * (W / 2 - 70), mid), fill=P["accent"], width=6)


def border(sheet, P):
    d = ImageDraw.Draw(sheet)
    d.rectangle((24, 24, W - 25, H - 25), outline=P["ink"], width=6)
    d.rectangle((38, 38, W - 39, H - 39), outline=P["accent"], width=2)


# --- The emblems -----------------------------------------------------------------------------------

def compact_emblem(d, cx, cy, r, P):
    """A shield between spread wings, a star over it: the eagle that hangs in the Government Hall."""
    for s in (-1, 1):
        for k in range(3):
            y0 = -0.42 + k * 0.24
            poly(d, cx, cy, r, [(s * 0.24, y0 + 0.16), (s * (1.12 - k * 0.2), y0 - 0.2 + k * 0.05), (s * (1.12 - k * 0.2), y0 - 0.02 + k * 0.05), (s * 0.24, y0 + 0.34)], P["ink"])
    poly(d, cx, cy, r, [(-0.34, -0.56), (0.34, -0.56), (0.34, 0.2), (0, 0.78), (-0.34, 0.2)], P["glow"], P["ink"], 10)
    poly(d, cx, cy, r, [(-0.07, -0.56), (0.07, -0.56), (0.07, 0.64), (0, 0.78), (-0.07, 0.64)], P["ink"])
    star(d, cx, cy - r * 0.9, r * 0.2, P["sun"])


def ashen_emblem(d, cx, cy, r, P):
    """A hive with its furnace slit, crowned with thorns."""
    for i in range(7):
        a = math.pi * (0.5 + (i - 3) * 0.19)
        tip = (cx + r * 1.12 * math.cos(a), cy - 0.1 * r - r * 1.12 * math.sin(a))
        side = (math.sin(a) * 0.07 * r, math.cos(a) * 0.07 * r)
        root = (cx + r * 0.3 * math.cos(a), cy - 0.1 * r - r * 0.3 * math.sin(a))
        d.polygon([(root[0] - side[0], root[1] - side[1]), tip, (root[0] + side[0], root[1] + side[1])], fill=P["ink"])
    poly(d, cx, cy, r, [(0, -0.8), (0.7, 0.62), (-0.7, 0.62)], P["band"], P["ink"], 10)
    poly(d, cx, cy, r, [(0, -0.4), (0.07, 0.1), (0, 0.5), (-0.07, 0.1)], P["glow"])
    d.rectangle((cx - r * 0.86, cy + r * 0.7, cx + r * 0.86, cy + r * 0.78), fill=P["ink"])


def luminar_emblem(d, cx, cy, r, P):
    """A crystal spire between two lesser ones, under a halo."""
    disc(d, cx, cy - r * 0.2, r * 0.86, outline=P["glow"], width=10)
    for i in range(9):
        a = math.pi * (0.5 + (i - 4) * 0.1)
        d.line((cx + r * 0.95 * math.cos(a), cy - 0.2 * r - r * 0.95 * math.sin(a), cx + r * 1.14 * math.cos(a), cy - 0.2 * r - r * 1.14 * math.sin(a)), fill=P["glow"], width=8)
    for x, k in ((-0.5, 0.6), (0.5, 0.6), (0.0, 1.0)):
        c = (cx + x * r, cy + (1 - k) * r * 0.95)
        poly(d, c[0], c[1], r * k, [(0, -1), (0.27, -0.55), (0.27, 0.62), (0, 0.95), (-0.27, 0.62), (-0.27, -0.55)], P["ink"])
        poly(d, c[0], c[1], r * k, [(0, -1), (0.27, -0.55), (0.27, 0.62), (0, 0.95)], P["light"])
        poly(d, c[0], c[1], r * k, [(0, -0.5), (0.06, 0), (0, 0.5), (-0.06, 0)], P["glow"])


def coma_emblem(d, cx, cy, r, P):
    """The sigil its keeps wear: a ring on a staff, barred."""
    disc(d, cx, cy, r * 1.0, outline=P["shade"], width=int(r * 0.2))
    disc(d, cx, cy, r * 0.72, outline=P["sun"], width=int(r * 0.09))
    d.rectangle((cx - r * 0.045, cy - r * 0.98, cx + r * 0.045, cy + r * 1.3), fill=P["sun"])
    d.rectangle((cx - r * 0.52, cy - r * 0.045, cx + r * 0.52, cy + r * 0.045), fill=P["sun"])
    disc(d, cx, cy, r * 0.13, fill=P["glow"])
    for s in (-1, 1):
        disc(d, cx + s * r * 1.0, cy, r * 0.05, fill=P["sun"])


# --- The edging on a notice ------------------------------------------------------------------------

def edging(d, P, y0, y1):
    kind = P["edging"]
    h = y1 - y0
    if kind == "hazard":  # diagonal warning stripes
        d.rectangle((0, y0, W, y1), fill=P["sun"])
        for x in range(-h, W + h, 96):
            d.polygon([(x, y1), (x + 48, y1), (x + 48 + h, y0), (x + h, y0)], fill=P["band"])
    elif kind == "thorns":  # a row of teeth
        d.rectangle((0, y0, W, y1), fill=P["band"])
        for x in range(0, W, 64):
            d.polygon([(x, y1), (x + 32, y0 + 8), (x + 64, y1)], fill=P["glow"])
    elif kind == "crystals":  # a row of shards
        d.rectangle((0, y0, W, y1), fill=P["band"])
        for i, x in enumerate(range(32, W, 64)):
            k = 0.48 if i % 2 else 0.3
            d.polygon([(x, y0 + h * (0.5 - k)), (x + 16, y0 + h / 2), (x, y0 + h * (0.5 + k)), (x - 16, y0 + h / 2)], fill=P["glow"])
    else:  # rings
        d.rectangle((0, y0, W, y1), fill=P["band"])
        for x in range(64, W, 128):
            disc(d, x, y0 + h / 2, h * 0.32, outline=P["sun"], width=5)
            disc(d, x, y0 + h / 2, h * 0.07, fill=P["glow"])


# --- Renders of the faction's own models -----------------------------------------------------------

def stage(faction, pieces):
    """An empty scene with the pieces set out: [(piece, x, y, turn)]. Returns their bounds."""
    kit.reset()
    lo, hi = [1e9] * 3, [-1e9] * 3
    for piece, x, y, turn in pieces:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(kit.ROOT, "game", "city", faction, piece + ".glb"))
        new = set(bpy.data.objects) - before
        for ob in new:
            if ob.parent is None:
                ob.rotation_mode = "XYZ"
                ob.rotation_euler = (0, 0, turn)
                ob.location = (ob.location.x + x, ob.location.y + y, ob.location.z)
        bpy.context.view_layer.update()
        for ob in new:
            if ob.type == "MESH":
                for c in ob.bound_box:
                    p = ob.matrix_world @ kit.Vector(c)
                    lo = [min(a, b) for a, b in zip(lo, p)]
                    hi = [max(a, b) for a, b in zip(hi, p)]
    return lo, hi


def shoot(path, size, eye, look, lens=None, ortho=None, sun=None, ambient=0.0):
    """Renders the staged scene on a clear background."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = size
    world = bpy.data.worlds.new("sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (1, 1, 1, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = ambient
    scene.world = world
    if sun:
        bpy.ops.object.light_add(type="SUN", rotation=(math.radians(sun[0]), 0, math.radians(sun[1])))
        bpy.context.object.data.energy = 4.0
    bpy.ops.object.camera_add(location=eye)
    cam = bpy.context.object
    target = bpy.data.objects.new("target", None)
    target.location = look
    scene.collection.objects.link(target)
    c = cam.constraints.new("TRACK_TO")
    c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.lens = lens
    cam.data.clip_end = 5000
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def inked(path, P):
    """A render cut down to the poster's inks: three tones by brightness, and the glow colour
    wherever the model's own lights are."""
    im = Image.open(path).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(1.0))).astype(float) / 255.0
    col, alpha = a[..., :3], a[..., 3]
    lum = col @ np.array([0.2126, 0.7152, 0.0722])
    top, low = col.max(-1), col.min(-1)
    out = np.zeros(col.shape[:2] + (4,))
    out[:] = P["shade"]
    out[lum > P["cuts"][0]] = P["mid"]
    out[lum > P["cuts"][1]] = P["light"]
    out[(((top - low) / (top + 1e-6) > 0.42) & (top > 0.5)) | (lum > 0.9)] = P["glow"]
    out[..., 3] = np.clip((alpha - 0.35) * 4.0, 0, 1) * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def hero(faction, piece, P):
    """The monument, seen from the ground at its foot."""
    lo, hi = stage(faction, [(piece, 0, 0, 0.0)])
    h = hi[2]
    reach = max(h, (hi[0] - lo[0]) * 1.3)
    path = os.path.join(CACHE, f"{faction}_hero.png")
    shoot(path, (768, 1152), (reach * 0.5, reach * 1.25, 2.0), (0, 0, h * 0.47), lens=36, sun=(58, 215), ambient=0.12)
    return inked(path, P)


def night(faction, row, P):
    """The skyline: the pieces in a row, square on, nothing lit but their own lights."""
    pieces = []
    x = 0.0
    for piece, width in row:
        pieces.append((piece, x + width / 2, 0, 0.0))
        x += width + 3.0
    pieces = [(p, px - x / 2, py, t) for p, px, py, t in pieces]
    lo, hi = stage(faction, pieces)
    path = os.path.join(CACHE, f"{faction}_night.png")
    span = (hi[0] - lo[0]) * 1.02
    shoot(path, (1536, 1536), (0, 600, span / 2), (0, 0, span / 2), ortho=span)
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).astype(float) / 255.0
    out = np.zeros(a.shape)
    out[:] = np.array(P["band"]) / 255.0
    out[a[..., :3].max(-1) > 0.16] = np.array(P["glow"]) / 255.0
    out[..., 3] = a[..., 3]
    out = Image.fromarray((out * 255).astype(np.uint8), "RGBA")
    return out.crop(out.getbbox())


# --- The four posters ------------------------------------------------------------------------------

def sheet_of(P, fill=None):
    return Image.new("RGBA", (W, H), fill or P["bg"])


def monument(P, art, lines, sub):
    im = sheet_of(P)
    d = ImageDraw.Draw(im)
    cx, cy = W / 2, 640
    burst(d, cx, cy, 18, 1500, P["bg2"], phase=0.09)
    disc(d, cx, cy, 350, fill=P["sun"])
    k = min(880 / art.width, 950 / art.height)
    art = art.resize((int(art.width * k), int(art.height * k)), Image.LANCZOS)
    im.alpha_composite(art, (int(cx - art.width / 2), 1112 - art.height))
    d.rectangle((0, 1110, W, H), fill=P["band"])
    d.rectangle((0, 1110, W, 1120), fill=P["accent"])
    stack(im, lines, P["font"], P["ink"], 96, W - 96, 1160, 1400, squeeze=P["squeeze"], track=P["track"])
    put(im, fitted(sub, P["font"], P["accent"], W - 200, 32, squeeze=P["squeeze"], track=0.16), W / 2, 1428)
    header(im, P, P["name"])
    border(im, P)
    return im


def badge(P, emblem, lines, sub):
    im = sheet_of(P)
    d = ImageDraw.Draw(im)
    cx, cy, r = W / 2, 610, 290
    burst(d, cx, cy, 28, 1500, P["bg2"])
    disc(d, cx, cy, r * 1.52, fill=P["accent"])
    disc(d, cx, cy, r * 1.46, fill=P["band"])
    disc(d, cx, cy, r * 1.4, outline=P["accent"], width=4)
    emblem(d, cx, cy, r, P)
    stack(im, lines, P["font"], P["ink"], 96, W - 96, 1100, 1390, squeeze=P["squeeze"], track=P["track"])
    put(im, fitted(sub, P["font"], P["accent"], W - 200, 32, squeeze=P["squeeze"], track=0.16), W / 2, 1420)
    header(im, P, P["name"])
    border(im, P)
    return im


def skyline(P, art, lines, sub):
    im = sheet_of(P, P["band"])
    d = ImageDraw.Draw(im)
    for y in range(0, 1260, 4):  # the sky, lighter toward the horizon
        f = (y / 1260) ** 1.6
        d.rectangle((0, y, W, y + 4), fill=tuple(int(a + (b - a) * f) for a, b in zip(P["band"], P["bg2"])))
    disc(d, W / 2, 1010, 400, fill=P["sun"])
    k = (W * 1.04) / art.width
    art = art.resize((int(art.width * k), int(art.height * k)), Image.LANCZOS)
    im.alpha_composite(art.crop((0, max(0, art.height - 1250), art.width, art.height)), (int(W / 2 - art.width / 2), 1250 - min(art.height, 1250)))
    d.rectangle((0, 1250, W, H), fill=P["band"])
    d.rectangle((0, 1250, W, 1258), fill=P["accent"])
    stack(im, lines, P["font"], P["ink"], 96, W - 96, 150, 470, squeeze=P["squeeze"], track=P["track"])
    put(im, fitted(sub, P["font"], P["accent"], W - 200, 32, squeeze=P["squeeze"], track=0.16), W / 2, 492)
    put(im, fitted(P["name"], P["font"], P["ink"], W - 300, 56, squeeze=P["squeeze"], track=0.22), W / 2, 1330)
    border(im, P)
    return im


def notice(P, emblem, lines, sub):
    im = sheet_of(P, P["notice"])
    d = ImageDraw.Draw(im)
    edging(d, P, 0, 132)
    edging(d, P, H - 132, H)
    stack(im, lines, P["font"], P["notice_ink"], 90, W - 90, 190, 1040, gap=34, tallest=300, squeeze=P["squeeze"], track=P["track"])
    disc(d, W / 2, 1190, 118, fill=P["band"])
    emblem(d, W / 2, 1190, 74, P)
    put(im, fitted(sub, P["font"], P["notice_ink"], W - 220, 34, squeeze=P["squeeze"], track=0.16), W / 2, 1338)
    return im


# --- The factions ----------------------------------------------------------------------------------

def inks(**hexes):
    return {k: rgb(v) if isinstance(v, str) and v.startswith("#") else v for k, v in hexes.items()}


FACTIONS = {
    "compact": {
        "inks": inks(name="TERRAN COMPACT", font="black", squeeze=0.8, track=0.0, edging="hazard", cuts=(0.2, 0.6),
                     bg="#16304f", bg2="#1d3f66", sun="#ffa733", band="#0b1626", ink="#eef2f6", accent="#ffa733",
                     shade="#0b1626", mid="#274c74", light="#86a9cc", glow="#8fd4ff", notice="#ffa733", notice_ink="#0b1626"),
        "emblem": compact_emblem,
        "hero": "hall",
        "row": [("zone_high_2_t5", 30), ("tower", 20), ("zone_high_1_t5", 30), ("hall", 70), ("highrise", 30), ("zone_high_3_t5", 30), ("zone_high_4_t5", 30)],
        "posters": [
            ("monument", ["THE WALL", "HOLDS"], "BECAUSE YOU HOLD IT"),
            ("badge", ["ONE COMPACT", "ONE SHIELD"], "OVER EVERY HOME ON EVERY WORLD"),
            ("skyline", ["BUILT", "TO LAST"], "WHAT WE RAISE, WE KEEP"),
            ("notice", ["YOUR", "SHIFT", "ARMS", "THE GUNS"], "REPORT ON TIME. THE LINE IS WAITING."),
        ],
    },
    "ashen": {
        "inks": inks(name="ASHEN COLLECTIVE", font="mono", squeeze=0.86, track=0.0, edging="thorns", cuts=(0.03, 0.12),
                     bg="#a3231c", bg2="#b93026", sun="#f0d9c0", band="#0d0706", ink="#f0d9c0", accent="#ff5a3c",
                     shade="#0a0505", mid="#2c1a17", light="#6e4a42", glow="#ff4a2e", notice="#0d0706", notice_ink="#f0d9c0"),
        "emblem": ashen_emblem,
        "hero": "zone_high_1_t5",
        "row": [("zone_high_5_t5", 30), ("zone_high_3_t5", 30), ("zone_high_2_t5", 30), ("zone_high_1_t5", 30), ("zone_high_4_t5", 30), ("zone_high_6_t5", 30)],
        "posters": [
            ("monument", ["THE HIVE", "REMEMBERS"], "EVERY HAND. EVERY DEBT."),
            ("badge", ["MANY HANDS", "ONE WILL"], "NO ONE STANDS ALONE IN THE ASH"),
            ("skyline", ["UNSEEN", "WE ARRIVE"], "THEY WILL NOT HEAR US COMING"),
            ("notice", ["FEED", "THE", "FURNACE"], "WASTE NOTHING. BURN THE REST."),
        ],
    },
    "luminar": {
        "inks": inks(name="LUMINAR ACCORD", font="serif", squeeze=0.9, track=0.04, edging="crystals", cuts=(0.3, 0.7),
                     bg="#12382b", bg2="#184a37", sun="#c9f7de", band="#0b241b", ink="#f4f8f2", accent="#4fd992",
                     shade="#58786a", mid="#b4c8bc", light="#f4f8f2", glow="#1fce7c", notice="#eef3ea", notice_ink="#12382b"),
        "emblem": luminar_emblem,
        "hero": "zone_high_1_t5",
        "row": [("zone_high_3_t5", 30), ("zone_high_5_t5", 30), ("zone_high_1_t5", 30), ("zone_high_4_t5", 30), ("zone_high_2_t5", 30), ("zone_high_6_t5", 30)],
        "posters": [
            ("monument", ["RAISE", "THE SPIRE"], "EVERY STONE A PROMISE KEPT"),
            ("badge", ["WALK IN", "THE LIGHT"], "THE ACCORD SEES YOU SAFELY HOME"),
            ("skyline", ["THE ACCORD", "KEEPS ITS WORD"], "ON HALCYON AS ON AURELIA"),
            ("notice", ["CLARITY", "IS A", "DUTY"], "ONE THOUGHT. ONE STRIKE. NO DOUBT."),
        ],
    },
    "coma": {
        "inks": inks(name="COMA CONGLOMERATE", font="medium", squeeze=1.0, track=0.14, edging="rings", cuts=(0.05, 0.2),
                     bg="#0e0e16", bg2="#171722", sun="#f0b545", band="#07070b", ink="#f3e2b0", accent="#f0b545",
                     shade="#07070b", mid="#2b2e3a", light="#5d6276", glow="#fff3c4", notice="#07070b", notice_ink="#f0b545"),
        "emblem": coma_emblem,
        "hero": "zone_high_2_t5",
        "row": [("zone_high_1_t5", 30), ("zone_high_6_t5", 30), ("zone_high_2_t5", 30), ("zone_high_4_t5", 30), ("zone_high_3_t5", 30), ("zone_high_5_t5", 30)],
        "posters": [
            ("monument", ["REST", "WE ARE AWAKE"], "THE CONGLOMERATE KEEPS WATCH"),
            ("badge", ["ALL THINGS", "ARE HELD"], "NOTHING IS LOST THAT IS OWNED"),
            ("skyline", ["THE CONGLOMERATE", "PROVIDES"], "ASK FOR NOTHING. WANT FOR NOTHING."),
            ("notice", ["YOU", "ARE", "ACCOUNTED", "FOR"], "EVERY ONE OF YOU. ALWAYS."),
        ],
    },
}


def build(faction):
    """Makes the faction's posters and returns them."""
    F = FACTIONS[faction]
    P = F["inks"]
    os.makedirs(CACHE, exist_ok=True)
    folder = os.path.join(kit.ROOT, "game", "city", faction, "propaganda")
    os.makedirs(folder, exist_ok=True)
    art = {"monument": hero(faction, F["hero"], P), "skyline": night(faction, F["row"], P)}
    out = []
    for n, (kind, lines, sub) in enumerate(F["posters"], 1):
        if kind == "monument":
            im = monument(P, art[kind], lines, sub)
        elif kind == "skyline":
            im = skyline(P, art[kind], lines, sub)
        elif kind == "badge":
            im = badge(P, F["emblem"], lines, sub)
        else:
            im = notice(P, F["emblem"], lines, sub)
        im = im.resize(OUT, Image.LANCZOS).convert("RGB")
        im.save(os.path.join(folder, f"poster_{n}.png"), optimize=True)
        print(f"{faction}/propaganda/poster_{n}.png")
        out.append(im)
    return out


def main(argv):
    args = argv[1:]
    where = None
    if "--sheet" in args:
        i = args.index("--sheet")
        where = args[i + 1]
        del args[i:i + 2]
        os.makedirs(where, exist_ok=True)
    rows = {faction: build(faction) for faction in (args or list(FACTIONS))}
    if where:
        pad = 24
        w, h = OUT
        sheet = Image.new("RGB", (pad + 4 * (w + pad), pad + len(rows) * (h + pad)), (24, 26, 30))
        for r, ims in enumerate(rows.values()):
            for c, im in enumerate(ims):
                sheet.paste(im, (pad + c * (w + pad), pad + r * (h + pad)))
        sheet.save(os.path.join(where, "propaganda.png"))


if __name__ == "__main__":
    main(sys.argv)
