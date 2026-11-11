// Cities, built on PC: the city a Founder builds on their terraformed Frontier world, and the
// cities on the factions' capital worlds (Bastion, Anvil, Shade, ...), which the game's admins lay
// out with the same builder. Pilots walk them on foot.
//
// On a colony world the colony's buildings (frontier.ts BUILDINGS: habitats, precincts, mines...)
// are pieces: placing one uses a building the colony has and hasn't placed yet, or builds a new one
// (paid and unlocked as the Colony page would). Taking one up puts it back in store; it keeps
// counting for the colony. Roads, plazas, parks, towers and walls are free. Homeworld cities may use
// every piece, and nothing there counts for anything.
//
// A city is a square grid of 10 m cells, CITY_CELLS on a side, the city's middle at (0, 0). Every
// piece covers a block of cells (its footprint, turned a quarter at a time) and no two pieces
// share a cell. Roads, plazas and parks are pieces too, so the editor lays out streets with the
// same taps as buildings.
//
// In the galaxy as g.cities: { [planetId]: { pieces: [{ id, type, x, z, rot }], nextId, updated } },
// where (x, z) is the piece's lowest-numbered cell and rot its quarter turns (0 to 3). Every
// player sees every city; only admins change them.

const W = require('./war');
const FR = require('./frontier.ts');

const CITY_CELLS = 120; // 1.2 km on a side
const CELL_M = 10;
const HALF = CITY_CELLS / 2; // cells run from -HALF to HALF - 1 on each axis
const MAX_PIECES = 4000;

type Piece = { id: number; type: string; x: number; z: number; rot: number };
type City = { pieces: Piece[]; nextId: number; updated: number };

// What the builder offers: [name, width, depth (cells, before turning), group, where]. `where` is
// 'any' (homeworlds and colonies), 'home' (homeworlds only) or 'colony' (a colony building, which
// homeworlds may use as scenery). A zone is a lot of housing: the builder drags zones out like
// roads, and each lot is drawn as one of its faction's many homes for that density (picked from
// the piece's id by the apps, so everyone sees the same street).
const PIECES: Record<string, { name: string; w: number; d: number; group: string; where: string }> = {};
for (const [id, name, w, d, group, where] of [
  ['road', 'Road', 1, 1, 'Ground', 'any'],
  ['plaza', 'Plaza', 2, 2, 'Ground', 'any'],
  ['park', 'Park', 3, 3, 'Ground', 'any'],
  ['zone_low', 'Low-density housing', 2, 2, 'Zones', 'any'],
  ['zone_high', 'High-density housing', 3, 3, 'Zones', 'any'],
  ['hall', 'Government Hall', 7, 7, 'Civic', 'home'],
  ['spaceport', 'Star Port', 6, 6, 'Civic', 'home'],
  ['pad', 'Landing Pad', 3, 3, 'Civic', 'any'],
  ['dock', 'Carrier Dock', 6, 6, 'Civic', 'home'],
  ['precinct', 'Precinct', 3, 3, 'Civic', 'colony'],
  ['clinic', 'Clinic', 3, 3, 'Civic', 'colony'],
  ['tower', 'Tower Block', 2, 2, 'Housing', 'any'],
  ['highrise', 'High-rise', 3, 3, 'Housing', 'any'],
  ['habitat', 'Habitat block', 4, 4, 'Housing', 'colony'],
  ['power', 'Power plant', 4, 4, 'Industry', 'colony'],
  ['mine', 'Mine', 4, 4, 'Industry', 'colony'],
  ['foundry', 'Foundry', 5, 5, 'Industry', 'colony'],
  ['smelter', 'Titanium smelter', 4, 4, 'Industry', 'colony'],
  ['works', 'Electronics works', 4, 4, 'Industry', 'colony'],
  ['reactor', 'Isotope reactor', 5, 5, 'Industry', 'colony'],
  ['hydroponics', 'Hydroponics Lab', 4, 4, 'Industry', 'home'],
  ['warehouse', 'Warehouse', 4, 4, 'Industry', 'home'],
  ['extractor', 'Extractor', 4, 4, 'Industry', 'home'],
  ['refinery', 'Refinery', 4, 4, 'Industry', 'home'],
  ['shipyard', 'Ship Foundry', 5, 5, 'Industry', 'home'],
  ['lab', 'Research Lab', 4, 4, 'Industry', 'home'],
  ['spire', 'Sensor Spire', 3, 3, 'Industry', 'home'],
  ['wall', 'Wall', 2, 1, 'Defence', 'any'],
  ['wall_tower', 'Wall Tower', 2, 2, 'Defence', 'any'],
  ['turret', 'Turret', 1, 1, 'Defence', 'any'],
] as [string, string, number, number, string, string][]) PIECES[id] = { name, w, d, group, where };

type Result = { ok: true; [k: string]: unknown } | { ok: false; reason: string };
const fail = (reason: string): Result => ({ ok: false, reason });

type Who = { name: string; admin: boolean };

// The planets a city may stand on: the capital worlds.
function isHomeworld(g: any, planetId: string): boolean {
  return !!W.planet(g, planetId)?.capital;
}

// The Frontier cluster whose colony stands on this planet, or null.
function colonyCluster(g: any, planetId: string): any {
  const m = /^(fr-.+-s\d+)-p\d+$/.exec(planetId);
  if (!m) return null;
  const c = FR.clusterOfSystem(FR.frontier(g), m[1]);
  return c?.colony?.planet === planetId ? c : null;
}

// Why `who` may not build here, or null: admins build on the homeworlds, a Founder on their own
// living colony.
function refusal(g: any, who: Who, planetId: string): string | null {
  if (isHomeworld(g, planetId)) return who.admin ? null : "only the game's admins build on the homeworlds"; // the Coma's too, which only admins ever visit
  const c = colonyCluster(g, planetId);
  if (!c) return 'cities are built on terraformed worlds and the homeworlds';
  if (c.owner !== who.name) return 'only its Founder builds this city';
  if (c.colony.collapseAt) return 'resettle the colony first';
  return null;
}

function city(g: any, planetId: string): City {
  g.cities ??= {};
  return (g.cities[planetId] ??= { pieces: [], nextId: 1, updated: 0 });
}

// A piece's width and depth in cells, as turned.
function size(type: string, rot: number): [number, number] {
  const p = PIECES[type];
  return rot % 2 ? [p.d, p.w] : [p.w, p.d];
}

function overlaps(a: { x: number; z: number; w: number; d: number }, b: { x: number; z: number; w: number; d: number }): boolean {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.z < b.z + b.d && b.z < a.z + a.d;
}

// Whether a piece fits at (x, z): inside the city and on no other piece's cells (`skip`: the piece
// being moved or turned).
function fits(c: City, type: string, x: number, z: number, rot: number, skip = 0): string | null {
  const [w, d] = size(type, rot);
  if (x < -HALF || z < -HALF || x + w > HALF || z + d > HALF) return 'that is outside the city';
  const box = { x, z, w, d };
  for (const p of c.pieces) {
    if (p.id === skip) continue;
    const [pw, pd] = size(p.type, p.rot);
    if (overlaps(box, { x: p.x, z: p.z, w: pw, d: pd })) return `${PIECES[p.type].name} is in the way`;
  }
  return null;
}

function cellArgs(x: unknown, z: unknown, rot: unknown): [number, number, number] | null {
  const [xi, zi, ri] = [Number(x), Number(z), Number(rot ?? 0)];
  if (![xi, zi, ri].every(Number.isInteger) || ri < 0 || ri > 3) return null;
  return [xi, zi, ri];
}

// How many of a colony building type are standing in the city.
function placed(c: City, type: string): number {
  return c.pieces.filter((p) => p.type === type).length;
}

function place(g: any, who: Who, planetId: string, type: string, x: unknown, z: unknown, rot: unknown, now: number): Result {
  const no = refusal(g, who, planetId);
  if (no) return fail(no);
  if (!Object.hasOwn(PIECES, type)) return fail('no such piece');
  const colony = colonyCluster(g, planetId);
  if (colony && PIECES[type].where === 'home') return fail(`a ${PIECES[type].name} is for the homeworlds`);
  const at = cellArgs(x, z, rot);
  if (!at) return fail('bad position');
  const c = city(g, planetId);
  if (c.pieces.length >= MAX_PIECES) return fail(`a city holds at most ${MAX_PIECES} pieces`);
  const why = fits(c, type, ...at);
  if (why) return fail(why);
  // A colony building: one in store, or a new one built (and paid for) now.
  let built = false;
  if (colony && PIECES[type].where === 'colony' && placed(c, type) >= (colony.colony.buildings[type] || 0)) {
    const r = FR.buildIn(g, who.name, colony.id, type);
    if (!r.ok) return r;
    built = true;
  }
  const piece = { id: c.nextId++, type, x: at[0], z: at[1], rot: at[2] };
  c.pieces.push(piece);
  c.updated = now;
  return { ok: true, piece: piece.id, built };
}

function find(g: any, who: Who, planetId: string, id: unknown): [City, Piece] | null {
  if (refusal(g, who, planetId)) return null;
  const c = city(g, planetId);
  const p = c.pieces.find((q) => q.id === Number(id));
  return p ? [c, p] : null;
}

function remove(g: any, who: Who, planetId: string, id: unknown, now: number): Result {
  const found = find(g, who, planetId, id);
  if (!found) return fail('no such piece');
  const [c, p] = found;
  c.pieces = c.pieces.filter((q) => q !== p);
  c.updated = now;
  return { ok: true };
}

// Moves and/or turns a piece; it keeps its id.
function move(g: any, who: Who, planetId: string, id: unknown, x: unknown, z: unknown, rot: unknown, now: number): Result {
  const found = find(g, who, planetId, id);
  if (!found) return fail('no such piece');
  const [c, p] = found;
  const at = cellArgs(x, z, rot);
  if (!at) return fail('bad position');
  const why = fits(c, p.type, ...at, p.id);
  if (why) return fail(why);
  [p.x, p.z, p.rot] = at;
  c.updated = now;
  return { ok: true, piece: p.id };
}

function clear(g: any, who: Who, planetId: string, now: number): Result {
  const no = refusal(g, who, planetId);
  if (no) return fail(no);
  const c = city(g, planetId);
  c.pieces = [];
  c.updated = now;
  return { ok: true };
}

// Copies one homeworld's city onto another (replacing what was there), to start from a layout.
function copy(g: any, who: Who, from: string, to: string, now: number): Result {
  if (!who.admin) return fail('admins only');
  if (!isHomeworld(g, from) || !isHomeworld(g, to)) return fail('copy between homeworlds');
  if (from === to) return fail('pick another world');
  const src = city(g, from);
  const c = city(g, to);
  c.pieces = src.pieces.map((p) => ({ ...p }));
  c.nextId = src.nextId;
  c.updated = now;
  return { ok: true };
}

// What goes out in every state broadcast: each city's last change, not its pieces. A full city
// is thousands of pieces, so apps ask for the one they stand in (city_get) and ask again when its
// stamp moves.
function stamps(g: any): Record<string, number> {
  const out: Record<string, number> = {};
  for (const [id, c] of Object.entries(g.cities || {})) out[id] = (c as City).updated;
  return out;
}

// One city as an app draws it (empty if nothing was ever built there).
function view(g: any, planetId: string): { planet: string; pieces: Piece[]; updated: number } {
  const c: City | undefined = Object.hasOwn(g.cities || {}, planetId) ? g.cities[planetId] : undefined;
  return { planet: planetId, pieces: c?.pieces || [], updated: c?.updated || 0 };
}

const CATALOG = { cells: CITY_CELLS, cell: CELL_M, pieces: PIECES };

module.exports = { CITY_CELLS, CELL_M, HALF, PIECES, CATALOG, isHomeworld, colonyCluster, refusal, city, size, fits, place, remove, move, clear, copy, stamps, view };
