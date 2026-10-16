// Satellite sites: each facility a Builder owns sits on its own site off their home planet,
// with a free grid where the Builder lays out defences around the facility core.
// Sites are kept in g.system.planets with kind 'satellite' (one building, slot 0, the facility),
// so raids and the rest of the game still address a facility as (planet id, slot).

const GRID = 12; // tiles per side
const CORE = { w: 4, h: 4 }; // the facility itself, in the middle of the grid
const MAX_SITES = 3; // satellite sites per Builder

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

// A new site record for `owner`'s facility (called `facilityName`) off their planet `home`.
function newSite(g, owner, home, facilityName) {
  const ownSites = g.system.planets.filter((p) => p.kind === 'satellite' && p.owner === owner);
  if (ownSites.length >= MAX_SITES) return fail(`you already have ${MAX_SITES} satellite sites`);
  const siblings = g.system.planets.filter((p) => p.kind === 'satellite' && p.parent === home.id);
  const orbit = [0, 1, 2, 3, 4, 5, 6, 7].find((o) => !siblings.some((s) => s.orbit === o));
  if (orbit === undefined) return fail(`no room left in orbit around ${home.name}`);
  let n = 1;
  while (g.system.planets.some((p) => p.id === `${home.id}-site-${n}`)) n++;
  return {
    ok: true,
    site: {
      id: `${home.id}-site-${n}`,
      name: `${home.name} ${facilityName}`,
      kind: 'satellite',
      owner,
      parent: home.id,
      orbit,
      slots: 1,
      grid: GRID,
      pieces: [],
      obstacles: [],
      nextPiece: 1,
      buildings: [],
    },
  };
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

// Total attack and hull of a site's defences, for fleet attacks.
function defence(site, now = Date.now()) {
  let attack = 0;
  let hull = 0;
  for (const p of site.pieces || []) {
    if (p.readyAt && now < p.readyAt) continue; // still being built
    attack += PIECES[p.type].attack;
    hull += PIECES[p.type].hull;
  }
  return { attack, hull };
}

module.exports = { GRID, CORE, MAX_SITES, PIECES, OBSTACLES, coreRect, newSite, scatter, place, remove, clear, defence };
