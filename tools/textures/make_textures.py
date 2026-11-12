"""The game's surface textures: tileable sets of maps, drawn procedurally with numpy.

    python tools/textures/make_textures.py [set ...] [--save-size 512] [--sheet FILE]

Writes game/textures/<set>/albedo.png, normal.png, orm.png and, for sets that light up, glow.png.
Every map tiles seamlessly, so the game can lay them over any shape without UVs (it projects them
from the three axes, see game/surfaces.gd). Which material gets which set, and how many metres one
tile spans, is game/textures/surfaces.json.

  albedo  grey, near white with darker seams, grime and wear: the game multiplies it by the material's
          own colour, so one set serves every faction colour it is used with.
  normal  OpenGL convention (green up), from the set's height map.
  orm     R ambient occlusion, G roughness, B metallic; G and B scale the material's own values.
  glow    where the surface lights up (window panes, Luminar seams, Coma traces), white = lit.

Needs numpy, scipy and Pillow. The same seed always draws the same textures.
"""

import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "game", "textures")
N = 1024  # drawn at this size...
SAVE = 512  # ...and saved at this: sharp enough at the tile sizes used, light enough for a phone

# --- Tileable building blocks ----------------------------------------------------------------------


def rng(seed):
    return np.random.default_rng(seed)


def noise(cx, cy, seed, n=None):
    """Smooth value noise in 0..1 that tiles: a cx by cy lattice of random values, interpolated."""
    n = n or N
    g = rng(seed).random((cy, cx))
    ys = np.arange(n) * cy / n
    xs = np.arange(n) * cx / n
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    y1 = (y0 + 1) % cy
    x1 = (x0 + 1) % cx
    a = g[y0][:, x0]
    b = g[y0][:, x1]
    c = g[y1][:, x0]
    d = g[y1][:, x1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(cells, seed, octaves=5, stretch=(1, 1), gain=0.5):
    """Fractal noise in roughly 0..1. `stretch` (x, y) multiplies the lattice: (1, 16) gives streaks
    running along x (brushed metal), (4, 1) streaks running down."""
    total = np.zeros((N, N))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        cx = min(N, max(1, int(c * stretch[0])))
        cy = min(N, max(1, int(c * stretch[1])))
        total += amp * noise(cx, cy, seed * 31 + o)
        norm += amp
        amp *= gain
    return total / norm


def blur(a, s):
    return ndimage.gaussian_filter(a, s, mode="wrap")


def norm01(a):
    lo, hi = a.min(), a.max()
    return (a - lo) / (hi - lo + 1e-9)


def edge_distance(ids):
    """Pixels from the nearest boundary between regions of `ids` (tiling)."""
    edge = (ids != np.roll(ids, 1, 0)) | (ids != np.roll(ids, 1, 1))
    big = np.tile(~edge, (3, 3))
    d = ndimage.distance_transform_edt(big)
    return d[N:2 * N, N:2 * N]


def panels(seed, grid, sizes, tall=False):
    """A tiling layout of rectangular panels on a grid x grid lattice. Returns (ids, rects): ids is
    the panel number of every pixel; rects are (x, y, w, h) in lattice units, wrapping."""
    r = rng(seed)
    occ = -np.ones((grid, grid), int)
    rects = []
    for y in range(grid):
        for x in range(grid):
            if occ[y, x] >= 0:
                continue
            w = int(r.choice(sizes))
            h = int(r.choice(sizes)) * (2 if tall else 1)
            # shrink until it fits over free cells (wrapping round)
            while w > 1 and any(occ[y, (x + i) % grid] >= 0 for i in range(w)):
                w -= 1
            while h > 1 and any(occ[(y + j) % grid, (x + i) % grid] >= 0 for i in range(w) for j in range(h)):
                h -= 1
            k = len(rects)
            for j in range(h):
                for i in range(w):
                    if occ[(y + j) % grid, (x + i) % grid] < 0:
                        occ[(y + j) % grid, (x + i) % grid] = k
            rects.append((x, y, w, h))
    u = N // grid
    ids = np.kron(occ, np.ones((u, u), int))
    return ids, rects


def stamp(h, cx, cy, radius, height, dome=True):
    """Adds a round bump (a rivet, a bolt, a pad) to height map h at pixel (cx, cy), wrapping."""
    r = int(np.ceil(radius)) + 1
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    d = np.sqrt(xx ** 2 + yy ** 2) / radius
    bump = np.clip(1 - d, 0, 1)
    bump = np.sqrt(bump) if dome else (d < 1).astype(float)
    ys = (np.arange(-r, r + 1) + int(cy)) % N
    xs = (np.arange(-r, r + 1) + int(cx)) % N
    region = h[np.ix_(ys, xs)]
    h[np.ix_(ys, xs)] = np.maximum(region, bump * height) if height > 0 else np.minimum(region, bump * height)


def rivets_round(h, rects, u, inset, spacing, radius, height, r, chance=1.0):
    """Rivets along the inside of every panel's edges."""
    for (x, y, w, hh) in rects:
        if r.random() > chance:
            continue
        x0, y0, x1, y1 = x * u + inset, y * u + inset, (x + w) * u - inset, (y + hh) * u - inset
        nx = max(1, int((x1 - x0) // spacing))
        ny = max(1, int((y1 - y0) // spacing))
        for i in range(nx + 1):
            px = x0 + (x1 - x0) * i / nx
            stamp(h, px, y0, radius, height)
            stamp(h, px, y1, radius, height)
        for j in range(1, ny):
            py = y0 + (y1 - y0) * j / ny
            stamp(h, x0, py, radius, height)
            stamp(h, x1, py, radius, height)


def voronoi(count, seed, sy=1.0):
    """Tiling cells round `count` random points: (nearest-point index, distance to it, distance to the
    edge between it and the next nearest), in pixels. sy > 1 stretches cells tall."""
    pts = rng(seed).random((count, 2)) * N
    offs = [(dx, dy) for dx in (-N, 0, N) for dy in (-N, 0, N)]
    allp = np.concatenate([pts + o for o in offs])
    idx = np.tile(np.arange(count), 9)
    yy, xx = np.mgrid[0:N, 0:N]
    q = np.stack([xx.ravel(), yy.ravel() / sy], 1)
    tree = cKDTree(np.stack([allp[:, 0], allp[:, 1] / sy], 1))
    d, k = tree.query(q, 2)
    near = idx[k[:, 0]].reshape(N, N)
    d1 = d[:, 0].reshape(N, N)
    d2 = d[:, 1].reshape(N, N)
    return near, d1, (d2 - d1) / 2


def grime(seed, amount=0.25, streaks=True):
    """Dirt: blotches, and with `streaks` rain marks running down. 0 clean .. 1 filthy."""
    g = fbm(4, seed, 5) * 0.6 + fbm(16, seed + 1, 3) * 0.4
    g = np.clip((g - 0.45) * 2.2, 0, 1)
    if streaks:
        s = fbm(24, seed + 2, 3, stretch=(1, 0.08))
        g = np.maximum(g, np.clip((s - 0.55) * 2.5, 0, 1) * 0.8)
    return g * amount


def cavity(h, s=6):
    """How far each pixel lies below its surroundings, 0..1: dirt collects there."""
    c = np.clip(blur(h, s) - h, 0, None)
    return c / (c.max() + 1e-9)


# --- Writing ---------------------------------------------------------------------------------------


def to_normal(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def img(a, size=None):
    im = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))
    return im.resize((size, size), Image.LANCZOS) if size and size != im.width else im


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{src}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def import_settings(path):
    """Godot's import settings beside a map: compressed for the GPU (so a phone holds them) with
    mipmaps, and normal maps flagged as such. Godot fills in the rest on first import."""
    src = "res://" + os.path.relpath(path, os.path.join(ROOT, "game")).replace(os.sep, "/")
    with open(path + ".import", "w") as f:
        f.write(IMPORT.format(src=src, normal=1 if path.endswith("normal.png") else 2))


def save(name, albedo, height, rough, metal=None, ao=None, glow=None, strength=40.0):
    """Writes one set. albedo: N x N (grey) or N x N x 3; height 0..1; rough/metal multipliers 0..1."""
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    if ao is None:
        ao = 1 - cavity(height) * 0.6
    if metal is None:
        metal = np.ones_like(height)
    img(albedo, SAVE).save(os.path.join(d, "albedo.png"), optimize=True)
    img(to_normal(height, strength * N / 1024), SAVE).save(os.path.join(d, "normal.png"), optimize=True)
    img(np.stack([ao, rough, metal], -1), SAVE).save(os.path.join(d, "orm.png"), optimize=True)
    if glow is not None:
        img(glow, SAVE).save(os.path.join(d, "glow.png"), optimize=True)
    for f in os.listdir(d):
        if f.endswith(".png"):
            import_settings(os.path.join(d, f))
    print("textures/" + name)


# --- The sets --------------------------------------------------------------------------------------
# Each draws a height map first, then colour, roughness and metal from it.


def hull_panels(seed=11):
    """Painted hull plating: big panels in staggered sizes, recessed seams, rivet rows, scuffed paint
    at the edges and dirt streaks. Teal hulls, faction paint, the base's walls."""
    r = rng(seed)
    grid = 16
    u = N // grid
    ids, rects = panels(seed, grid, [2, 3, 4, 4, 6])
    e = edge_distance(ids)
    h = np.clip(e / 3.0, 0, 1) * 0.6 + 0.4
    lift = r.random(len(rects))[ids] * 0.06  # panels sit at slightly different depths
    h = h + lift
    rivets_round(h, rects, u, u * 0.18, u * 0.5, 2.6, 1.08, r, chance=0.55)
    h += fbm(64, seed, 3) * 0.02
    tone = 0.92 + r.normal(0, 0.025, len(rects))[ids]
    wear = np.clip(1 - e / 6.0, 0, 1) * np.clip((fbm(32, seed + 3, 4) - 0.5) * 3, 0, 1)  # chipped edges
    dirt = grime(seed + 5, 0.3) + cavity(h, 4) * 0.4
    albedo = np.clip(tone * (1 - dirt) + wear * 0.18, 0, 1)
    albedo[e < 1.5] *= 0.45  # the seam itself
    rough = np.clip(0.78 + dirt * 0.3 - wear * 0.25 + r.normal(0, 0.03, len(rects))[ids], 0, 1)
    save("hull_panels", albedo, h, rough)


def trim_plates(seed=12):
    """Small trim plates with vents and a bolt in each corner: navy bands, frames, pod casings."""
    r = rng(seed)
    grid = 8
    u = N // grid
    ids, rects = panels(seed, grid, [1, 1, 2, 3])
    e = edge_distance(ids)
    h = np.clip(e / 4.0, 0, 1) * 0.7 + 0.3
    yy, xx = np.mgrid[0:N, 0:N]
    for k, (x, y, w, hh) in enumerate(rects):
        x0, y0 = x * u, y * u
        if w * hh >= 2 and r.random() < 0.45:  # a vent: rows of slots
            m = ((xx - x0) % N < w * u - u * 0.25) & ((xx - x0) % N > u * 0.25) & ((yy - y0) % N < hh * u - u * 0.25) & ((yy - y0) % N > u * 0.25)
            slots = (((yy - y0) % N) // 10) % 2 == 0
            h[m & slots & (ids == k)] = 0.15
        for cx, cy in ((x0 + 12, y0 + 12), (x0 + w * u - 12, y0 + 12), (x0 + 12, y0 + hh * u - 12), (x0 + w * u - 12, y0 + hh * u - 12)):
            stamp(h, cx, cy, 4.5, 1.1)
    h += fbm(64, seed, 3) * 0.02
    dirt = grime(seed + 5, 0.25, streaks=False) + cavity(h, 3) * 0.5
    albedo = np.clip(0.9 + r.normal(0, 0.03, len(rects))[ids] - dirt, 0, 1)
    rough = np.clip(0.75 + dirt * 0.3, 0, 1)
    save("trim_plates", albedo, h, rough, strength=30)


def brushed_steel(seed=13):
    """Brushed metal with a few bolted seams: girders, masts, turrets, doors."""
    r = rng(seed)
    streak = fbm(2, seed, 6, stretch=(1, 64)) * 0.6 + fbm(1, seed + 1, 6, stretch=(1, 160)) * 0.4
    h = 0.5 + (streak - 0.5) * 0.08
    grid = 4
    u = N // grid
    ids, rects = panels(seed, grid, [1, 2, 4])
    e = edge_distance(ids)
    h = h * (0.6 + 0.4 * np.clip(e / 2.0, 0, 1))
    for (x, y, w, hh) in rects:
        for cx, cy in ((x * u + 14, y * u + 14), ((x + w) * u - 14, (y + hh) * u - 14)):
            stamp(h, cx, cy, 6, 1.0)
    dirt = grime(seed + 5, 0.18, streaks=False) + cavity(h, 3) * 0.3
    albedo = np.clip(0.82 + (streak - 0.5) * 0.35 - dirt, 0, 1)
    rough = np.clip(0.55 + (streak - 0.5) * 0.6 + dirt * 0.4, 0, 1)
    save("brushed_steel", albedo, h, rough, strength=20)


def deck_plate(seed=14):
    """Diamond tread plate with weld seams, worn bright along the walkways: decks, floors, pads."""
    r = rng(seed)
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    cell = N / 32
    cy, cx = (yy % cell) / cell - 0.5, (xx % cell) / cell - 0.5
    flip = ((yy // cell + xx // cell) % 2) * 2 - 1
    a = np.where(flip > 0, (cx + cy), (cx - cy)) / 1.414
    b = np.where(flip > 0, (cx - cy), (cx + cy)) / 1.414
    lozenge = np.clip(1 - np.sqrt((a / 0.42) ** 2 + (b / 0.09) ** 2), 0, 1)
    h = 0.35 + np.sqrt(lozenge) * 0.4
    seam = (np.abs((xx % (N / 2)) - 2) < 3) | (np.abs((yy % (N / 2)) - 2) < 3)
    weld = fbm(128, seed, 2)
    h = np.where(seam, 0.45 + weld * 0.2, h)
    h += fbm(64, seed + 2, 3) * 0.03
    walk = np.clip((fbm(3, seed + 4, 4) - 0.45) * 3, 0, 1)  # where feet and wheels go
    dirt = cavity(h, 3) * 0.6 + grime(seed + 5, 0.2, streaks=False)
    albedo = np.clip(0.85 - dirt + walk * lozenge * 0.25, 0, 1)
    rough = np.clip(0.8 + dirt * 0.2 - walk * lozenge * 0.45, 0, 1)
    save("deck_plate", albedo, h, rough, strength=35)


def grip_dark(seed=15):
    """Hexagonal rubber grip over a grating: dark doors, hatches, dark trim."""
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    # hexes repeat every 3s across and every sqrt(3)s down: pick s to fit 11 repeats across, then
    # squeeze rows a hair so a whole number of them fits down too, so the pattern tiles
    s = N / (3 * 11)
    rows = round(N / (np.sqrt(3) * s))
    yy = yy * (np.sqrt(3) * s * rows / N)
    q = (2 / 3 * xx) / s
    rr = (-1 / 3 * xx + np.sqrt(3) / 3 * yy) / s
    # distance to the nearest hex centre on a tiling axial grid
    cube = np.stack([q, rr, -q - rr], -1)
    rc = np.round(cube)
    diff = np.abs(rc - cube)
    i = np.argmax(diff, -1)
    for k in range(3):
        o = [(k + 1) % 3, (k + 2) % 3]
        rc[..., k] = np.where(i == k, -rc[..., o[0]] - rc[..., o[1]], rc[..., k])
    d = np.max(np.abs(rc - cube), -1)
    h = np.clip((0.5 - d) / 0.5, 0, 1)
    h = np.clip(h * 3, 0, 1) * 0.6 + 0.2
    h += fbm(48, seed, 3) * 0.08
    albedo = np.clip(0.75 + (h - 0.5) * 0.3 - grime(seed, 0.2, streaks=False), 0, 1)
    rough = np.clip(0.9 - h * 0.15, 0, 1)
    save("grip_dark", albedo, h, rough, strength=25)


def glass(seed=16):
    """Canopy glass: almost clean, with smudges and a few scratches that catch the light."""
    r = rng(seed)
    smudge = np.clip((fbm(6, seed, 5) - 0.5) * 2.5, 0, 1)
    h = np.full((N, N), 0.5)
    scratch = np.zeros((N, N))
    for _ in range(40):
        x, y = r.random(2) * N
        ang = r.random() * np.pi
        for t in range(int(r.integers(30, 160))):
            scratch[int(y + np.sin(ang) * t) % N, int(x + np.cos(ang) * t) % N] = 1
    scratch = blur(scratch, 0.7)
    h -= scratch * 0.4
    albedo = np.clip(0.97 - smudge * 0.08, 0, 1)
    rough = np.clip(0.3 + smudge * 0.5 + scratch * 0.6, 0, 1)
    save("glass", albedo, h, rough, ao=np.ones((N, N)), strength=15)


def window_lights(seed=17):
    """Rows of window panes behind mullions, each room lit a little differently: portholes, bridge
    windows, the Compact's blue slits."""
    r = rng(seed)
    cols, rows = 8, 8
    pw, ph = N // cols, N // rows
    yy, xx = np.mgrid[0:N, 0:N]
    fx, fy = xx % pw, yy % ph
    frame = (fx < 8) | (fx > pw - 8) | (fy < 10) | (fy > ph - 10)
    mid = (np.abs(fx - pw / 2) < 3)
    room = r.random((rows, cols))
    lit = 0.55 + 0.45 * room[yy // ph, xx // pw]
    lit = np.where(room[yy // ph, xx // pw] < 0.12, 0.25, lit)  # the odd room dark
    glow = np.where(frame | mid, 0.0, lit * (0.9 + 0.1 * fbm(8, seed, 3)))
    h = np.where(frame | mid, 1.0, 0.3)
    albedo = np.where(frame | mid, 0.35, 0.9)
    rough = np.where(frame | mid, 0.7, 0.15)
    save("window_lights", albedo, h, rough, glow=glow, strength=20)


def light_panel(seed=18):
    """A light behind a louvred grille, a little brighter in the middle: running lights, lamps,
    the factions' glowing trim."""
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    louvre = 0.5 + 0.5 * np.cos(yy / N * 2 * np.pi * 48)
    glow = 0.78 + 0.22 * louvre
    glow *= 0.92 + 0.08 * fbm(4, seed, 3)
    h = louvre * 0.5
    save("light_panel", glow, h, np.full((N, N), 0.4), glow=glow, strength=10)


def rock(seed=19):
    """Rough rock with strata and pits: asteroids, cliffs, boulders."""
    base = fbm(4, seed, 7)
    ridged = 1 - np.abs(fbm(8, seed + 1, 5) * 2 - 1)
    strata = 0.5 + 0.5 * np.sin((np.arange(N)[:, None] / N * 2 * np.pi * 12) + base * 6)
    h = base * 0.5 + ridged * 0.35 + strata * 0.15
    albedo = np.clip(0.7 + (h - 0.5) * 0.5 - cavity(h, 5) * 0.4, 0, 1)
    rough = np.clip(0.85 + cavity(h, 5) * 0.15, 0, 1)
    save("rock", albedo, h, rough, metal=np.zeros((N, N)), strength=60)


def ice(seed=20):
    """Ice: smooth, with a web of cracks and frosted patches."""
    _, _, edge = voronoi(90, seed)
    crack = np.clip(1 - edge / 3, 0, 1)
    frost = np.clip((fbm(8, seed + 1, 5) - 0.5) * 2, 0, 1)
    h = 0.6 - crack * 0.3 + frost * 0.1
    albedo = np.clip(0.95 - crack * 0.15 + frost * 0.05, 0, 1)
    rough = np.clip(0.2 + frost * 0.6 + crack * 0.3, 0, 1)
    save("ice", albedo, h, rough, metal=np.zeros((N, N)), strength=30)


# Terran Compact: armoured, bolted, utilitarian.

def armour_plate(seed=21):
    """The Compact's heavy armour: thick rectangular plates, deep seams, bolt rows top and bottom,
    stencilled marks and dirt. Navy and slate walls."""
    r = rng(seed)
    grid = 8
    u = N // grid
    ids, rects = panels(seed, grid, [2, 2, 3, 4])
    e = edge_distance(ids)
    h = np.clip(e / 6.0, 0, 1) ** 0.7
    h += r.random(len(rects))[ids] * 0.08
    for (x, y, w, hh) in rects:
        for i in range(w * 3 + 1):
            px = x * u + 14 + (w * u - 28) * i / (w * 3)
            stamp(h, px, y * u + 14, 4.5, 1.12)
            stamp(h, px, (y + hh) * u - 14, 4.5, 1.12)
    stencil = np.zeros((N, N))
    for (x, y, w, hh) in rects:  # a stencilled ident block on some plates
        if r.random() < 0.3:
            x0, y0 = int(x * u + w * u * 0.2), int(y * u + hh * u * 0.4)
            for b in range(int(r.integers(2, 5))):
                stencil[np.ix_(np.arange(y0, y0 + 14) % N, np.arange(x0 + b * 18, x0 + b * 18 + 12) % N)] = 1
    h += fbm(64, seed, 3) * 0.02
    dirt = grime(seed + 5, 0.35) + cavity(h, 5) * 0.5
    wear = np.clip(1 - e / 5.0, 0, 1) * np.clip((fbm(32, seed + 3, 4) - 0.5) * 3, 0, 1)
    albedo = np.clip(0.9 + r.normal(0, 0.03, len(rects))[ids] - dirt + wear * 0.2 + stencil * 0.35, 0, 1)
    rough = np.clip(0.8 + dirt * 0.25 - wear * 0.3, 0, 1)
    save("armour_plate", albedo, h, rough, strength=45)


def hazard_stripes(seed=22):
    """Black and yellow chevrons, chipped and dirty. The colour is the material's (hazard yellow);
    the stripes are dark."""
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    p = N / 8
    stripe = ((xx + yy) % p) < p / 2
    chip = np.clip((fbm(24, seed, 5) - 0.6) * 4, 0, 1)
    dirt = grime(seed + 1, 0.3)
    albedo = np.where(stripe & (chip < 0.5), 0.07, 0.95) * (1 - dirt)
    h = np.where(stripe & (chip < 0.5), 0.55, 0.5) + fbm(64, seed + 2, 3) * 0.03
    rough = np.clip(0.7 + dirt * 0.3 + chip * 0.1, 0, 1)
    save("hazard_stripes", albedo, h, rough, strength=20)


def ferrocrete(seed=23):
    """Cast ferrocrete: formwork panel lines, tie holes, pores and water stains. Compact white walls
    and interiors."""
    r = rng(seed)
    grid = 4
    u = N // grid
    yy, xx = np.mgrid[0:N, 0:N]
    joint = ((xx % u) < 3) | ((yy % (u // 2)) < 2)
    h = 0.6 + fbm(32, seed, 5) * 0.12
    pores = (fbm(256, seed + 1, 2) > 0.78).astype(float)
    h -= pores * 0.15
    h[joint] = 0.35
    for gy in range(grid * 2):
        for gx in range(grid):
            for (ox, oy) in ((0.25, 0.5), (0.75, 0.5)):
                stamp(h, gx * u + ox * u, gy * u / 2 + oy * u / 2, 5, -0.1, dome=False)
    stain = grime(seed + 3, 0.35)
    albedo = np.clip(0.88 + (fbm(16, seed + 4, 4) - 0.5) * 0.12 - stain - pores * 0.1, 0, 1)
    rough = np.clip(0.9 + pores * 0.1 - stain * 0.2, 0, 1)
    save("ferrocrete", albedo, h, rough, metal=np.full((N, N), 0.2), strength=30)


# Ashen Collective: grown, not built.

def chitin(seed=24):
    """Overlapping chitin scales, each domed with growth rings, glossy, with dark sutures between.
    The Ashen black and char."""
    near, d1, edge = voronoi(160, seed, sy=1.6)
    r = rng(seed)
    size = r.uniform(0.8, 1.2, 160)[near]
    dome = np.clip(1 - d1 / (60 * size), 0, 1)
    rings = 0.5 + 0.5 * np.sin(d1 / 4.0)
    suture = np.clip(1 - edge / 4, 0, 1)
    h = dome * 0.6 + rings * 0.06 + (1 - suture) * 0.3
    h += fbm(64, seed, 3) * 0.03
    albedo = np.clip(0.85 + r.normal(0, 0.06, 160)[near] - suture * 0.5 + dome * 0.1, 0, 1)
    rough = np.clip(0.35 + suture * 0.5 + (1 - dome) * 0.2, 0, 1)
    save("chitin", albedo, h, rough, strength=50)


def moss(seed=25):
    """Swamp growth: matted fibres, clumps and wet hollows."""
    clumps = fbm(12, seed, 6)
    fibre = fbm(8, seed + 1, 6, stretch=(6, 1))
    h = clumps * 0.7 + fibre * 0.3
    wet = np.clip((0.45 - clumps) * 4, 0, 1)
    albedo = np.clip(0.75 + (clumps - 0.5) * 0.6 - wet * 0.25, 0, 1)
    rough = np.clip(0.95 - wet * 0.6, 0, 1)
    save("moss", albedo, h, rough, metal=np.zeros((N, N)), strength=40)


def vein_glow(seed=26):
    """Glowing veins branching through dark tissue: the Ashen's red light and their cores."""
    _, d1, edge = voronoi(70, seed)
    _, _, edge2 = voronoi(260, seed + 1)
    vein = np.maximum(np.clip(1 - edge / 6, 0, 1), np.clip(1 - edge2 / 2.5, 0, 1) * 0.6)
    pulse = 0.75 + 0.25 * fbm(6, seed + 2, 3)
    glow = np.clip(0.25 + vein * 0.9, 0, 1) * pulse
    h = 0.4 + vein * 0.4 + fbm(32, seed + 3, 4) * 0.1
    save("vein_glow", glow, h, np.full((N, N), 0.45), glow=glow, strength=30)


# The Ashen's insides: black plating cut at angles, lit red from slits, seams and the furnaces below.

def plates(seed, grid, sizes, chamfer, tall=False):
    """Rectangular panels with their corners cut off at 45 degrees (the Ashen's angular plating).
    Returns (ids, d, rects, lx, ly, w, h): d is how many pixels each pixel lies inside its own
    panel's cut outline, lx/ly its place in the panel from the panel's corner, w/h the panel's size,
    all per pixel. `chamfer` is the cut's size as a part of the panel's shorter side."""
    ids, rects = panels(seed, grid, sizes, tall)
    u = N // grid
    d = np.zeros((N, N))
    lx = np.zeros((N, N))
    ly = np.zeros((N, N))
    pw = np.ones((N, N))
    ph = np.ones((N, N))
    for k, (x, y, w, h) in enumerate(rects):
        ys = np.arange(y * u, (y + h) * u) % N
        xs = np.arange(x * u, (x + w) * u) % N
        yy, xx = np.meshgrid(np.arange(h * u), np.arange(w * u), indexing="ij")
        own = ids[np.ix_(ys, xs)] == k  # a panel shrunk to fit keeps only its own cells
        ex = np.minimum(xx, w * u - 1 - xx)
        ey = np.minimum(yy, h * u - 1 - yy)
        c = chamfer * min(w, h) * u
        inside = np.minimum(np.minimum(ex, ey), (ex + ey - c) / np.sqrt(2))
        for target, value in ((d, inside), (lx, xx), (ly, yy), (pw, np.full(xx.shape, w * u)), (ph, np.full(xx.shape, h * u))):
            region = target[np.ix_(ys, xs)]
            region[own] = value[own]
            target[np.ix_(ys, xs)] = region
    return ids, d, rects, lx, ly, pw, ph


def groove(d, at, width=1.6):
    """A thin line cut round every panel, `at` pixels in from its outline."""
    return np.clip(1 - np.abs(d - at) / width, 0, 1)


def black_plating(seed=31):
    """The Ashen's inside walls: black plates with their corners cut, a line or two scored round
    each, bolts in the cuts, louvres in some, and here and there a slit that glows."""
    r = rng(seed)
    ids, d, rects, lx, ly, pw, ph = plates(seed, 8, [1, 2, 2, 3, 4], 0.22)
    n = len(rects)
    plate = np.clip(d / 5.0, 0, 1) ** 0.7
    score = groove(d, 16) + groove(d, 24) * (r.random(n) < 0.5)[ids]
    step = (r.random(n) < 0.35)[ids] * np.clip((d - 34) / 3, 0, 1) * 0.25  # a raised middle on some
    h = plate * (0.7 + r.random(n)[ids] * 0.1) - score * 0.18 + step
    # Louvres: a block of slots across the middle of some wide plates.
    kind = r.random(n)[ids]
    cx, cy = lx - pw / 2, ly - ph / 2
    in_block = (np.abs(cx) < pw * 0.28) & (np.abs(cy) < ph * 0.22) & (d > 30)
    louvre = in_block & (kind < 0.22) & (np.sin(ly * np.pi / 7.0) > 0.2)
    h = np.where(louvre, h - 0.35, h)
    # Slits: one long thin light across a plate, or up it.
    across = (np.abs(cy) < 3.5) & (np.abs(cx) < pw * 0.32) & (kind > 0.74) & (kind < 0.9) & (d > 20)
    up = (np.abs(cx) < 3.5) & (np.abs(cy) < ph * 0.3) & (kind >= 0.9) & (d > 20)
    slit = (across | up).astype(float)
    housing = blur(slit, 5) > 0.02
    h = np.where(housing, h - 0.12, h)
    h = np.where(slit > 0, h - 0.3, h)
    for (x, y, w, hh) in rects:  # a bolt in each cut corner
        u = N // 8
        c = 0.22 * min(w, hh) * u * 0.62
        for sx, sy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            stamp(h, x * u + (c if sx == 0 else w * u - c), y * u + (c if sy == 0 else hh * u - c), 3.5, 1.0)
    h += fbm(96, seed, 3) * 0.015
    brushed = fbm(3, seed + 1, 5, stretch=(1, 40))
    edge_wear = np.clip(1 - d / 4.0, 0, 1) * np.clip((fbm(40, seed + 3, 4) - 0.45) * 3, 0, 1)
    dirt = grime(seed + 5, 0.22) + cavity(h, 5) * 0.45
    albedo = np.clip(0.86 + r.normal(0, 0.035, n)[ids] + (brushed - 0.5) * 0.1 - dirt - score * 0.3 + edge_wear * 0.25
                     - louvre * 0.45 + slit * 0.3, 0, 1)
    rough = np.clip(0.5 + (brushed - 0.5) * 0.35 + dirt * 0.5 - edge_wear * 0.25, 0, 1)
    glow = np.clip(blur(slit, 0.8) * 1.2, 0, 1)
    save("black_plating", albedo, h, rough, glow=glow, strength=42)


def black_deck(seed=32):
    """The Ashen's floors: big plates with cut corners, scored twice round, worn glossy where feet
    go, with red light leaking up through some of the seams."""
    r = rng(seed)
    ids, d, rects, lx, ly, pw, ph = plates(seed, 4, [1, 1, 2], 0.3)
    n = len(rects)
    plate = np.clip(d / 6.0, 0, 1) ** 0.6
    score = groove(d, 22, 2.0) + groove(d, 34, 1.4)
    tread = 0.5 + 0.5 * np.sin((lx + ly) * np.pi / 9.0) * np.sin((lx - ly) * np.pi / 9.0)  # a fine diamond grip
    grip = (d > 44) & (r.random(n) < 0.6)[ids]
    h = plate * 0.75 - score * 0.16 + np.where(grip, tread * 0.05, 0.0)
    u = N // 4
    for (x, y, w, hh) in rects:
        for i in range(w * 4 + 1):  # bolts along the top and bottom edges
            px = x * u + 30 + (w * u - 60) * i / (w * 4)
            stamp(h, px, y * u + 12, 3.5, 0.95)
            stamp(h, px, (y + hh) * u - 12, 3.5, 0.95)
    h += fbm(96, seed, 3) * 0.012
    scuff = np.clip((fbm(5, seed + 2, 5, stretch=(1, 3)) - 0.5) * 3.5, 0, 1)
    dirt = grime(seed + 5, 0.2, streaks=False) + cavity(h, 6) * 0.5
    albedo = np.clip(0.84 + r.normal(0, 0.03, n)[ids] - dirt - score * 0.3 + scuff * 0.12, 0, 1)
    rough = np.clip(0.62 - scuff * 0.3 + dirt * 0.5, 0, 1)
    lit = (r.random(n) < 0.13)[ids]  # the plates whose seams leak light
    seam = np.clip(1 - np.abs(d - 1.0) / 2.5, 0, 1) * lit * (0.55 + 0.45 * fbm(8, seed + 7, 3))
    save("black_deck", albedo, h, rough, glow=np.clip(blur(seam, 0.7) * 1.3, 0, 1), strength=38)


def ember_grate(seed=33):
    """Grating over a furnace: a mesh of flat bars in a heavier frame, the fire showing through."""
    yy, xx = np.mgrid[0:N, 0:N]
    cell, frame = N // 16, N // 4
    bar = (np.minimum(xx % cell, cell - xx % cell) < 5) | (np.minimum(yy % (cell * 2), cell * 2 - yy % (cell * 2)) < 4)
    beam = (np.minimum(xx % frame, frame - xx % frame) < 14) | (np.minimum(yy % frame, frame - yy % frame) < 14)
    solid = (bar | beam).astype(float)
    h = blur(solid, 1.2) * 0.7 + beam * 0.3
    fire = 0.45 + 0.55 * norm01(fbm(5, seed, 5) + fbm(20, seed + 1, 3) * 0.4)
    glow = np.clip((1 - blur(solid, 1.0)) * fire, 0, 1)
    wear = np.clip((fbm(30, seed + 2, 4) - 0.5) * 3, 0, 1)
    albedo = np.clip(solid * (0.8 + wear * 0.15) + (1 - solid) * 0.12, 0, 1)
    rough = np.clip(0.55 - wear * 0.2 + (1 - solid) * 0.4, 0, 1)
    save("ember_grate", albedo, h, rough, glow=glow, strength=55)


def black_machinery(seed=34):
    """Machine faces for pillars, tanks and engines: small panels of louvres, ribbed conduit, hatches
    and status lights, packed tight."""
    r = rng(seed)
    ids, d, rects, lx, ly, pw, ph = plates(seed, 16, [1, 2, 2, 3, 4], 0.12, tall=True)
    n = len(rects)
    kind = r.random(n)[ids]
    plate = np.clip(d / 3.5, 0, 1) ** 0.7
    h = plate * (0.55 + r.random(n)[ids] * 0.3)
    inner = d > 9
    louvre = inner & (kind < 0.25) & (np.sin(ly * np.pi / 5.0) > 0.1)
    rib = np.where(inner & (kind >= 0.25) & (kind < 0.5), 0.5 + 0.5 * np.cos(lx * np.pi / 6.0), 0.0)  # conduit running up
    hatch = groove(d, 12, 1.4) * ((kind >= 0.5) & (kind < 0.78))
    h = np.where(louvre, h - 0.3, h) + rib * 0.22 - hatch * 0.15
    lamp = np.zeros((N, N))
    u = N // 16
    for k, (x, y, w, hh) in enumerate(rects):
        v = r.random()
        if v < 0.16 and w >= 2:  # a row of status lights
            for i in range(int(r.integers(2, 5))):
                stamp(lamp, x * u + 16 + i * 14, y * u + hh * u * 0.5, 3.2, 1.0, dome=False)
        elif v < 0.24 and hh >= 2:  # a short upright light bar
            x0, y0 = int(x * u + w * u * 0.5), int(y * u + hh * u * 0.3)
            lamp[np.ix_(np.arange(y0, y0 + int(hh * u * 0.4)) % N, np.arange(x0 - 2, x0 + 3) % N)] = 1
        for sx in (0, 1):
            for sy in (0, 1):
                stamp(h, x * u + (8 if sx == 0 else w * u - 8), y * u + (8 if sy == 0 else hh * u - 8), 2.4, 1.0)
    h = np.where(lamp > 0, h - 0.1, h) + fbm(96, seed, 3) * 0.015
    dirt = grime(seed + 5, 0.25) + cavity(h, 4) * 0.55
    albedo = np.clip(0.84 + r.normal(0, 0.05, n)[ids] - dirt - louvre * 0.4 + rib * 0.08 - hatch * 0.25 + lamp * 0.3, 0, 1)
    rough = np.clip(0.5 + dirt * 0.5 - rib * 0.15, 0, 1)
    save("black_machinery", albedo, h, rough, glow=np.clip(blur(lamp, 0.7) * 1.3, 0, 1), strength=42)


# Luminar Accord: pale ceramic in long tapering plates, green light in every seam.

def ceramic_plates(seed=27):
    """Long vertical ceramic plates of varying width, each tapering to a point at the top where the
    next begins; the seams between are what the game lights green."""
    r = rng(seed)
    yy, xx = np.mgrid[0:N, 0:N].astype(float)
    widths = []
    while sum(widths) < N:
        widths.append(int(r.choice([64, 96, 128, 128, 160])))
    widths[-1] -= sum(widths) - N
    if widths[-1] < 32:
        widths[-2] += widths.pop()
    col = np.zeros(N, int)
    left = np.zeros(N)
    x = 0
    for k, w in enumerate(widths):
        col[x:x + w] = k
        left[x:x + w] = x
        x += w
    wcol = np.array(widths)[col][None, :]
    u = (xx - left[None, :]) / wcol  # 0..1 across the column
    phase = r.random(len(widths))[col][None, :] * N
    plate_h = r.choice([256, 512, 512], len(widths))[col][None, :]  # divides N, so columns tile
    # each plate's top comes to a point that sits in a notch cut in the bottom of the plate above
    point = plate_h * 0.3 * (1 - np.abs(u - 0.5) * 2)
    v = ((yy + phase + point) % plate_h) / plate_h  # 0 top .. 1 bottom of a plate
    slope = np.sqrt(1 + (0.6 * plate_h / wcol) ** 2)  # the chevron's steepness, for seam width
    dist = np.minimum(np.minimum(u, 1 - u) * wcol, np.minimum(v, 1 - v) * plate_h / slope)
    seam = np.clip(1 - dist / 3.0, 0, 1)
    h = np.clip(dist / 10.0, 0, 1) * 0.7 + 0.25
    h += (1 - np.abs(u - 0.5) * 2) * 0.05  # each plate gently crowned
    h += fbm(32, seed, 4) * 0.02
    sheen = r.normal(0, 0.025, len(widths))[col][None, :]
    albedo = np.clip(0.95 + sheen - seam * 0.6 - grime(seed + 5, 0.08), 0, 1)
    rough = np.clip(0.35 + seam * 0.4 + (fbm(16, seed + 6, 4) - 0.5) * 0.2, 0, 1)
    glow = np.clip(1 - dist / 4.0, 0, 1)
    save("ceramic_plates", albedo, h, rough, glow=glow, strength=35)


def crystal(seed=28):
    """Faceted crystal: flat facets, each at its own brightness, with bright edges."""
    near, _, edge = voronoi(120, seed)
    r = rng(seed)
    facet = r.uniform(0.6, 1.0, 120)[near]
    glow = np.clip(facet + np.clip(1 - edge / 3, 0, 1) * 0.4, 0, 1)
    h = facet * 0.5 + np.clip(edge / 20, 0, 1) * 0.3
    save("crystal", glow, h, np.full((N, N), 0.1), metal=np.zeros((N, N)), glow=glow, strength=60)


# Coma Conglomerate: dark gunmetal traced with gold.

def gunmetal_traces(seed=29):
    """Polished dark gunmetal in large panels, engraved with circuit traces that end in pads; the
    traces are what the game lights gold."""
    r = rng(seed)
    grid = 64
    step = N // grid
    trace = np.zeros((N, N))
    pads = []
    dirs = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    for _ in range(70):
        x, y = r.integers(0, grid, 2)
        d = int(r.integers(0, 8)) // 2 * 2  # start straight
        pads.append((x, y))
        for _ in range(int(r.integers(6, 28))):
            if r.random() < 0.25:
                d = (d + r.choice([-1, 1])) % 8
            nx, ny = x + dirs[d][0], y + dirs[d][1]
            for t in np.linspace(0, 1, step + 1):
                px = int((x + (nx - x) * t) * step) % N
                py = int((y + (ny - y) * t) * step) % N
                trace[py, px] = 1
            x, y = nx, ny
        pads.append((x, y))
    trace = np.clip(ndimage.grey_dilation(np.tile(trace, (3, 3)), size=(3, 3))[N:2 * N, N:2 * N], 0, 1)
    padmap = np.zeros((N, N))
    for (x, y) in pads:
        stamp(padmap, x * step, y * step, 6, 1.0, dome=False)
    lit = np.maximum(trace, padmap)
    lit = blur(lit, 0.6)
    ids, rects = panels(seed, 4, [1, 2, 2])
    e = edge_distance(ids)
    brushed = fbm(2, seed + 1, 6, stretch=(1, 80))
    h = 0.6 + (brushed - 0.5) * 0.04 - lit * 0.2
    h = h * (0.5 + 0.5 * np.clip(e / 3, 0, 1))
    albedo = np.clip(0.85 + (brushed - 0.5) * 0.2 - np.clip(1 - e / 2, 0, 1) * 0.5 + lit * 0.6, 0, 1)
    rough = np.clip(0.45 + (brushed - 0.5) * 0.5 + grime(seed + 5, 0.15, streaks=False), 0, 1)
    save("gunmetal_traces", albedo, h, rough, glow=np.clip(lit * 1.3, 0, 1), strength=25)


def hammered_gold(seed=30):
    """Hammered metal: a field of shallow dimples, bright on their rims."""
    near, d1, edge = voronoi(260, seed)
    dimple = np.sqrt(d1 / (d1 + edge + 1e-6))
    h = blur(dimple ** 2, 1.5) * 0.5 + 0.3
    albedo = np.clip(0.85 + dimple * 0.15, 0, 1)
    rough = np.clip(0.25 + (1 - dimple) * 0.2 + grime(seed + 1, 0.15, streaks=False), 0, 1)
    save("hammered_gold", albedo, h, rough, strength=40)


SETS = {f.__name__: f for f in [hull_panels, trim_plates, brushed_steel, deck_plate, grip_dark, glass, window_lights,
                                light_panel, rock, ice, armour_plate, hazard_stripes, ferrocrete, chitin, moss, vein_glow,
                                black_plating, black_deck, ember_grate, black_machinery,
                                ceramic_plates, crystal, gunmetal_traces, hammered_gold]}


def sheet(path):
    """A contact sheet: every set's albedo (lit by its normal map) and its glow, for a quick look."""
    from PIL import ImageDraw
    names = sorted(n for n in os.listdir(OUT) if os.path.isdir(os.path.join(OUT, n)))
    cell = 256
    cols = 5
    rows = (len(names) + cols - 1) // cols
    out = Image.new("RGB", (cols * cell, rows * (cell + 22)), (20, 22, 26))
    draw = ImageDraw.Draw(out)
    light = np.array([-0.5, 0.6, 0.62])
    light /= np.linalg.norm(light)
    for i, n in enumerate(names):
        a = np.asarray(Image.open(os.path.join(OUT, n, "albedo.png")).convert("RGB").resize((cell, cell)), float) / 255
        nm = np.asarray(Image.open(os.path.join(OUT, n, "normal.png")).convert("RGB").resize((cell, cell)), float) / 255 * 2 - 1
        shade = np.clip(nm @ light, 0, 1)[..., None] * 0.8 + 0.25
        rgb = a * shade
        gp = os.path.join(OUT, n, "glow.png")
        if os.path.exists(gp):
            g = np.asarray(Image.open(gp).convert("L").resize((cell, cell)), float)[..., None] / 255
            rgb = rgb * 0.6 + g * np.array([0.3, 0.9, 1.0]) * 0.6
        x, y = (i % cols) * cell, (i // cols) * (cell + 22)
        out.paste(img(rgb), (x, y))
        draw.text((x + 6, y + cell + 4), n, fill=(220, 225, 230))
    out.save(path)
    print(path)


def main(argv):
    global SAVE
    names, sheet_path = [], None
    i = 0
    while i < len(argv):
        if argv[i] == "--save-size":
            SAVE = int(argv[i + 1])
            i += 2
        elif argv[i] == "--sheet":
            sheet_path = argv[i + 1]
            i += 2
        else:
            names.append(argv[i])
            i += 1
    for n in names or SETS:
        if n not in SETS:
            sys.exit(f"no texture set {n!r}: one of {', '.join(SETS)}")
        SETS[n]()
    if sheet_path:
        sheet(sheet_path)


if __name__ == "__main__":
    main(sys.argv[1:])
