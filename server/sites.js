// Outposts (satellite sites): each facility a Builder owns sits on its own site, in a sector of a
// contested planet their faction holds (war.js), with a free grid where the Builder lays out
// defences around the facility core.
// Sites are kept in g.system.planets with kind 'satellite' (one building, slot 0, the facility),
// so raids and the rest of the game still address a facility as (planet id, slot).
// An outpost carries `parent` (the planet it's on), `sector`, `faction` and `dormant`; sites from
// before the war have no sector and sit on their Builder's home planet until it picks a faction.

const GRID = 12; // tiles per side
const CORE = { w: 4, h: 4 }; // the facility itself, in the middle of the grid
const MAX_SITES = 5; // outposts per Builder
const PER_SECTOR = 3; // outposts in one sector, all Builders together
const NUDGE = 4; // degrees between outposts in one sector, so each stands apart on the hologram

const PIECES = {
  turret: { name: 'Turret', w: 2, h: 2, cost: { metal: 20, alloy: 5 }, attack: 4, hull: 20, seconds: 30 },
  wall: { name: 'Wall', w: 1, h: 1, cost: { metal: 5 }, attack: 0, hull: 10, seconds: 5 },
  guardpost: { name: 'Guard post', w: 2, h: 2, cost: { metal: 15 }, attack: 1, hull: 15, seconds: 20 },
  // Powers the facility's main door. Raiders who knock it out walk in the front; without one the
  // door stays sealed and the only way in is a vent.
  power: { name: 'Power plant', w: 2, h: 2, cost: { metal: 25 }, attack: 0, hull: 25, seconds: 45, max: 1 },
};

// Obstacles a new site comes with, cleared for credits like Clash of Clans' rocks and trees.
// Some leave salvage behind. They block placing defences until cleared.
const OBSTACLES = {
  boulder: { name: 'Boulder', w: 2, h: 2, clear: 120, salvage: { metal: 10 } },
  crystals: { name: 'Ice crystals', w: 1, h: 1, clear: 40, salvage: { ice: 4 } },
  wreck: { name: 'Old wreckage', w: 2, h: 1, clear: 200, salvage: { metal: 25, alloy: 2 } },
};
const SCATTER = ['boulder', 'boulder', 'boulder', 'wreck', 'wreck', 'crystals', 'crystals', 'crystals', 'crystals'];

function fail(reason) {
  return { ok: false, reason };
}

function coreRect() {
  const x = (GRID - CORE.w) / 2;
  const y = (GRID - CORE.h) / 2;
  return { x, y, w: CORE.w, h: CORE.h };
}

function overlaps(a, b) {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

function pieceRect(p) {
  const def = PIECES[p.type] || OBSTACLES[p.type];
  return { x: p.x, y: p.y, w: def.w, h: def.h };
}

// The outposts in one sector, all Builders'.
function sectorSites(g, sectorId) {
  return g.system.planets.filter((p) => p.kind === 'satellite' && p.sector === sectorId);
}

// A new outpost record for `owner`'s facility (called `facilityName`) in `sector` of the war
// planet `planet`, for `faction`. Says why not if the Builder or the sector is full.
function newSite(g, owner, planet, sector, faction, facilityName) {
  const ownSites = g.system.planets.filter((p) => p.kind === 'satellite' && p.owner === owner);
  if (ownSites.length >= MAX_SITES) return fail(`you already have ${MAX_SITES} outposts`);
  if (sectorSites(g, sector.id).length >= PER_SECTOR) return fail(`${sector.name} already has ${PER_SECTOR} outposts`);
  let n = 1;
  while (g.system.planets.some((p) => p.id === `${planet.id}-op-${n}`)) n++;
  const site = {
    id: `${planet.id}-op-${n}`,
    kind: 'satellite',
    owner,
    faction,
    slots: 1,
    grid: GRID,
    pieces: [],
    obstacles: [],
    nextPiece: 1,
    buildings: [],
    dormant: false,
  };
  settle(g, site, planet, sector, facilityName);
  return { ok: true, site };
}

// Puts an outpost in `sector` of `planet`: its parent, name and the first free place in the sector.
function settle(g, site, planet, sector, facilityName) {
  const others = sectorSites(g, sector.id).filter((p) => p !== site && Array.isArray(p.surface));
  let i = 0;
  while (others.some((p) => angleBetween(p.surface, sectorSpot(sector, i)) < 1)) i++;
  site.surface = sectorSpot(sector, i);
  site.parent = planet.id;
  site.sector = sector.id;
  site.name = `${sector.name} ${facilityName}`;
  delete site.orbit;
}

// Where the `index`th outpost of a sector stands: the first at the sector's centre, the next ones
// on a small ring round it.
function sectorSpot(sector, index) {
  if (index <= 0) return [sector.lat, sector.lon];
  const a = ((index - 1) * 2 * Math.PI) / Math.max(2, PER_SECTOR - 1) + Math.PI / 2;
  const lat = Math.max(-89, Math.min(89, sector.lat + NUDGE * Math.cos(a)));
  const lon = sector.lon + (NUDGE * Math.sin(a)) / Math.max(0.2, Math.cos((sector.lat * Math.PI) / 180));
  const round = (x) => Math.round(x * 10) / 10;
  return [round(lat), round(((lon % 360) + 360) % 360)];
}

// --- Where sites sit on the planet ----------------------------------------------------------

// Every home base and satellite site has a place on its planet's surface, [lat, lon] in degrees.
// New sites take the spot furthest from everything already on the planet, so on the hologram in
// the High Port's Terminal Hall each one stands clearly apart. Candidates keep away from the poles.
const HOME_SPOT = [15, 30];

function angleBetween(a, b) {
  const r = Math.PI / 180;
  const [la1, lo1, la2, lo2] = [a[0] * r, a[1] * r, b[0] * r, b[1] * r];
  const c = Math.sin(la1) * Math.sin(la2) + Math.cos(la1) * Math.cos(la2) * Math.cos(lo1 - lo2);
  return Math.acos(Math.max(-1, Math.min(1, c))) / r;
}

function surfaceSpot(taken) {
  let best = null;
  let bestGap = -1;
  for (let lat = -60; lat <= 60; lat += 10) {
    for (let lon = 0; lon < 360; lon += 10) {
      const gap = Math.min(...taken.map((t) => angleBetween(t, [lat, lon])));
      if (gap > bestGap + 1e-9) [best, bestGap] = [[lat, lon], gap];
    }
  }
  return best;
}

// Gives every home planet and site from before the war that has no place on its planet one, in
// founding order. Outposts in a sector have their place from the sector, so this leaves them alone.
// Safe to call any time (on load, after founding a site): places already given never change.
function locate(g) {
  for (const home of g.system.planets.filter((p) => p.kind !== 'satellite')) {
    if (!Array.isArray(home.surface)) home.surface = HOME_SPOT.slice();
    for (const site of g.system.planets.filter((p) => p.kind === 'satellite' && p.parent === home.id)) {
      if (site.sector || Array.isArray(site.surface)) continue;
      const taken = [home.surface, ...g.system.planets
        .filter((p) => p.kind === 'satellite' && p.parent === home.id && Array.isArray(p.surface))
        .map((p) => p.surface)];
      site.surface = surfaceSpot(taken);
    }
  }
}

// Scatters the starting obstacles on free tiles, the same way every time for a given site id.
function scatter(site) {
  site.obstacles ||= [];
  let seed = [...site.id].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
  const rand = (n) => {
    seed = (seed * 1103515245 + 12345) >>> 0;
    return (seed >>> 8) % n;
  };
  for (const type of SCATTER) {
    const def = OBSTACLES[type];
    for (let tries = 0; tries < 40; tries++) {
      const r = { x: rand(GRID - def.w + 1), y: rand(GRID - def.h + 1), w: def.w, h: def.h };
      if (overlaps(r, coreRect()) || taken(site, r)) continue;
      site.obstacles.push({ id: site.nextPiece++, type, x: r.x, y: r.y });
      break;
    }
  }
}

function taken(site, r) {
  return [...site.pieces, ...(site.obstacles || [])].some((p) => overlaps(r, pieceRect(p)));
}

// Places a defence on a site's grid, or says why not. `pay` takes the cost or says what is short.
// It takes the defence's build time (divided by `speed`) to become ready.
function place(site, type, x, y, pay, now = Date.now(), speed = 1) {
  const def = PIECES[type];
  if (!def) return fail('no such defence');
  if (!Number.isInteger(x) || !Number.isInteger(y)) return fail('bad position');
  const r = { x, y, w: def.w, h: def.h };
  if (x < 0 || y < 0 || x + def.w > GRID || y + def.h > GRID) return fail('off the edge of the site');
  if (overlaps(r, coreRect())) return fail('the facility is there');
  if (taken(site, r)) return fail('something is already there');
  if (def.max && site.pieces.filter((p) => p.type === type).length >= def.max) return fail(`only ${def.max} ${def.name} per site`);
  const err = pay(def.cost);
  if (err) return fail(err);
  const piece = { id: site.nextPiece++, type, x, y };
  const ms = (def.seconds * 1000) / speed;
  if (ms > 0) piece.readyAt = now + ms;
  site.pieces.push(piece);
  return { ok: true, piece, name: def.name };
}

// Removes a defence and refunds half its cost (rounded down) to economy `e`.
function remove(site, pieceId, e) {
  const i = site.pieces.findIndex((p) => p.id === pieceId);
  if (i < 0) return fail('nothing there');
  const [piece] = site.pieces.splice(i, 1);
  for (const [res, amount] of Object.entries(PIECES[piece.type].cost)) {
    const back = Math.floor(amount / 2);
    if (res === 'credits') e.credits += back;
    else e.stock[res] = (e.stock[res] || 0) + back;
  }
  return { ok: true, name: PIECES[piece.type].name };
}

// Clears an obstacle for its price in credits from economy `e`; any salvage goes to its stock.
function clear(site, obstacleId, e) {
  const i = (site.obstacles || []).findIndex((o) => o.id === obstacleId);
  if (i < 0) return fail('nothing there');
  const def = OBSTACLES[site.obstacles[i].type];
  if (e.credits < def.clear) return fail(`clearing the ${def.name} costs ${def.clear} credits`);
  e.credits -= def.clear;
  site.obstacles.splice(i, 1);
  for (const [res, n] of Object.entries(def.salvage)) e.stock[res] = (e.stock[res] || 0) + n;
  return { ok: true, name: def.name, salvage: def.salvage };
}

module.exports = { GRID, CORE, MAX_SITES, PER_SECTOR, PIECES, OBSTACLES, coreRect, sectorSites, newSite, settle, sectorSpot, scatter, place, remove, clear, locate, angleBetween };
