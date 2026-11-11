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
// Tiers: every housing lot (a zone piece) is a building that grows as its occupants' needs are met,
// from tier 1 to 5, and slips back when they stop being met. The needs are a road at its edge,
// and power, safety (a precinct), care (a clinic) and leisure (a park or plaza), each reaching the
// lot along the roads: at full strength close by, fading to nothing by the service's reach. See
// "Tiers" below; the apps draw a lot's building bigger and richer at each tier.
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

// A housing lot also has its tier (1 to TOP_TIER, absent = 1) and how far it is toward the next one
// (`grow`, -1 to 1: below 0 it is slipping toward the tier under it).
type Piece = { id: number; type: string; x: number; z: number; rot: number; tier?: number; grow?: number };
// `updated`: when anything last changed (apps fetch the city again); `laid`: counts layout changes
// (what the needs depend on); `grownAt`: when the tiers were last moved on.
type City = { pieces: Piece[]; nextId: number; updated: number; laid?: number; grownAt?: number };

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

// The layout changed: apps fetch it again, and the lots' needs are worked out afresh.
function laid(c: City, now: number): void {
  c.updated = now;
  c.laid = (c.laid || 0) + 1;
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
  laid(c, now);
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
  laid(c, now);
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
  laid(c, now);
  return { ok: true, piece: p.id };
}

function clear(g: any, who: Who, planetId: string, now: number): Result {
  const no = refusal(g, who, planetId);
  if (no) return fail(no);
  const c = city(g, planetId);
  c.pieces = [];
  laid(c, now);
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
  laid(c, now);
  return { ok: true };
}

// --- Tiers --------------------------------------------------------------------------------------

const TOP_TIER = 5;
const GROW_HOURS = 12; // of needs met, to climb a tier
const DECLINE_HOURS = 24; // of needs unmet, to slip one
// Who answers each need, and how far its help carries along the roads, in cells (10 m): full
// strength out to `full`, fading evenly to nothing at `reach`. Traffic will slow this once people
// drive the roads; for now it is distance by road.
const SERVICES: Record<string, { from: string[]; full: number; reach: number }> = {
  power: { from: ['power'], full: 30, reach: 90 },
  safety: { from: ['precinct'], full: 15, reach: 50 },
  care: { from: ['clinic'], full: 15, reach: 50 },
  leisure: { from: ['park', 'plaza'], full: 6, reach: 24 },
};
const SERVICE_NAMES = Object.keys(SERVICES);

// A lot's needs: whether a road touches it, and each service's strength there, 0 to 1.
type Needs = { road: number; power: number; safety: number; care: number; leisure: number };

const isZone = (type: string) => type.startsWith('zone_');

// The tier a lot's needs can carry it to (the rule, in one place: the apps explain it the same way).
//   2: a road and power.   3: a precinct and a clinic in reach too.
//   4: leisure in reach, and power, safety and care at half strength or better.
//   5: all four at 0.8 or better.
function targetTier(n: Needs): number {
  if (!n.road || n.power <= 0) return 1;
  if (n.safety <= 0 || n.care <= 0) return 2;
  const weakest = Math.min(n.power, n.safety, n.care);
  if (n.leisure <= 0 || weakest < 0.5) return 3;
  if (Math.min(weakest, n.leisure) < 0.8) return 4;
  return TOP_TIER;
}

const surveys = new WeakMap<City, { laid: number; needs: Map<number, Needs> }>();

// Every lot's needs, worked out once per layout: a flood along the roads from each service's
// buildings gives every road cell its distance to the nearest one.
function survey(c: City): Map<number, Needs> {
  const cached = surveys.get(c);
  if (cached && cached.laid === (c.laid || 0)) return cached.needs;
  const N = CITY_CELLS;
  const at = (x: number, z: number) => (z + HALF) * N + (x + HALF);
  const road = new Uint8Array(N * N);
  for (const p of c.pieces) if (p.type === 'road') road[at(p.x, p.z)] = 1;
  // The road cells along a piece's edges.
  const doorsteps = (p: Piece): number[] => {
    const [w, d] = size(p.type, p.rot);
    const out: number[] = [];
    const take = (x: number, z: number) => {
      if (x >= -HALF && z >= -HALF && x < HALF && z < HALF && road[at(x, z)]) out.push(at(x, z));
    };
    for (let x = p.x; x < p.x + w; x++) take(x, p.z - 1), take(x, p.z + d);
    for (let z = p.z; z < p.z + d; z++) take(p.x - 1, z), take(p.x + w, z);
    return out;
  };
  const dist: Record<string, Int32Array> = {};
  for (const name of SERVICE_NAMES) {
    const d = (dist[name] = new Int32Array(N * N).fill(-1));
    let edge: number[] = [];
    for (const p of c.pieces) if (SERVICES[name].from.includes(p.type)) for (const cell of doorsteps(p)) if (d[cell] < 0) (d[cell] = 0), edge.push(cell);
    while (edge.length) {
      const next: number[] = [];
      for (const cell of edge) {
        const x = cell % N;
        for (const to of [x > 0 ? cell - 1 : -1, x < N - 1 ? cell + 1 : -1, cell - N, cell + N]) {
          if (to < 0 || to >= N * N || !road[to] || d[to] >= 0) continue;
          d[to] = d[cell] + 1;
          next.push(to);
        }
      }
      edge = next;
    }
  }
  const needs = new Map<number, Needs>();
  for (const p of c.pieces) {
    if (!isZone(p.type)) continue;
    const steps = doorsteps(p);
    const n: Needs = { road: steps.length ? 1 : 0, power: 0, safety: 0, care: 0, leisure: 0 };
    for (const name of SERVICE_NAMES) {
      const { full, reach } = SERVICES[name];
      let best = -1;
      for (const cell of steps) if (dist[name][cell] >= 0 && (best < 0 || dist[name][cell] < best)) best = dist[name][cell];
      (n as any)[name] = best < 0 ? 0 : best <= full ? 1 : Math.max(0, 1 - (best - full) / (reach - full));
    }
    // A park or plaza next door is leisure without driving anywhere.
    if (n.leisure < 1) {
      const [w, d] = size(p.type, p.rot);
      const near = { x: p.x - 2, z: p.z - 2, w: w + 4, d: d + 4 };
      for (const q of c.pieces) {
        if (!SERVICES.leisure.from.includes(q.type)) continue;
        const [qw, qd] = size(q.type, q.rot);
        if (overlaps(near, { x: q.x, z: q.z, w: qw, d: qd })) n.leisure = 1;
      }
    }
    needs.set(p.id, n);
  }
  surveys.set(c, { laid: c.laid || 0, needs });
  return needs;
}

// Moves every living city's lots on toward the tier their needs carry: up after GROW_HOURS of
// needs met, down after DECLINE_HOURS unmet. True when a lot changed tier (the apps redraw it).
function tick(g: any, now: number): boolean {
  let changed = false;
  for (const [planetId, c] of Object.entries((g.cities || {}) as Record<string, City>)) {
    if (!c.pieces.length) continue;
    if (!isHomeworld(g, planetId) && !colonyCluster(g, planetId)) continue; // ruins don't grow
    const hours = c.grownAt ? Math.min(Math.max(now - c.grownAt, 0) / FR.hourMs(), GROW_HOURS) : 0;
    c.grownAt = now;
    if (hours <= 0) continue;
    const needs = survey(c);
    for (const p of c.pieces) {
      if (!isZone(p.type)) continue;
      let tier = p.tier || 1;
      let grow = p.grow || 0;
      const target = targetTier(needs.get(p.id)!);
      if (target > tier) grow += hours / GROW_HOURS;
      else if (target < tier) grow -= hours / DECLINE_HOURS;
      else grow = grow > 0 ? Math.max(0, grow - hours / GROW_HOURS) : Math.min(0, grow + hours / DECLINE_HOURS);
      if (grow >= 1) (tier += 1), (grow = 0);
      else if (grow <= -1) (tier -= 1), (grow = 0);
      if (tier !== (p.tier || 1)) {
        c.updated = now;
        changed = true;
      }
      p.tier = tier;
      p.grow = grow;
    }
  }
  return changed;
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
// A housing lot comes with its tier, its progress, its needs [road, power, safety, care, leisure]
// (each 0 to 1) and the tier those carry it to.
function view(g: any, planetId: string): { planet: string; pieces: any[]; updated: number } {
  const c: City | undefined = Object.hasOwn(g.cities || {}, planetId) ? g.cities[planetId] : undefined;
  if (!c) return { planet: planetId, pieces: [], updated: 0 };
  const needs = survey(c);
  const round = (v: number) => Math.round(v * 100) / 100;
  const pieces = c.pieces.map((p) => {
    if (!isZone(p.type)) return p;
    const n = needs.get(p.id)!;
    return { ...p, tier: p.tier || 1, grow: round(p.grow || 0), needs: [n.road, round(n.power), round(n.safety), round(n.care), round(n.leisure)], target: targetTier(n) };
  });
  return { planet: planetId, pieces, updated: c.updated };
}

const CATALOG = { cells: CITY_CELLS, cell: CELL_M, pieces: PIECES, tiers: { top: TOP_TIER, growHours: GROW_HOURS, declineHours: DECLINE_HOURS, services: SERVICES } };

module.exports = { CITY_CELLS, CELL_M, HALF, PIECES, CATALOG, isHomeworld, colonyCluster, refusal, city, size, fits, place, remove, move, clear, copy, stamps, view, tick, survey, targetTier, TOP_TIER, GROW_HOURS, DECLINE_HOURS, SERVICES };
