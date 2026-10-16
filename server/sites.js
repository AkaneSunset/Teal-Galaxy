// Satellite sites: each facility a Builder owns sits on its own site off their home planet,
// with a free grid where the Builder lays out defences around the facility core.
// Sites are kept in g.system.planets with kind 'satellite' (one building, slot 0, the facility),
// so raids and the rest of the game still address a facility as (planet id, slot).

const GRID = 12; // tiles per side
const CORE = { w: 4, h: 4 }; // the facility itself, in the middle of the grid
const MAX_SITES = 3; // satellite sites per Builder

const PIECES = {
  turret: { name: 'Turret', w: 2, h: 2, cost: { metal: 20, alloy: 5 }, attack: 4, hull: 20 },
  wall: { name: 'Wall', w: 1, h: 1, cost: { metal: 5 }, attack: 0, hull: 10 },
  guardpost: { name: 'Guard post', w: 2, h: 2, cost: { metal: 15 }, attack: 1, hull: 15 },
};

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
  const def = PIECES[p.type];
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
      nextPiece: 1,
      buildings: [],
    },
  };
}

// Places a defence on a site's grid, or says why not. `pay` takes the cost or says what is short.
function place(site, type, x, y, pay) {
  const def = PIECES[type];
  if (!def) return fail('no such defence');
  if (!Number.isInteger(x) || !Number.isInteger(y)) return fail('bad position');
  const r = { x, y, w: def.w, h: def.h };
  if (x < 0 || y < 0 || x + def.w > GRID || y + def.h > GRID) return fail('off the edge of the site');
  if (overlaps(r, coreRect())) return fail('the facility is there');
  if (site.pieces.some((p) => overlaps(r, pieceRect(p)))) return fail('something is already there');
  const err = pay(def.cost);
  if (err) return fail(err);
  const piece = { id: site.nextPiece++, type, x, y };
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

// Total attack and hull of a site's defences, for fleet attacks.
function defence(site) {
  let attack = 0;
  let hull = 0;
  for (const p of site.pieces || []) {
    attack += PIECES[p.type].attack;
    hull += PIECES[p.type].hull;
  }
  return { attack, hull };
}

module.exports = { GRID, CORE, MAX_SITES, PIECES, coreRect, newSite, place, remove, defence };
