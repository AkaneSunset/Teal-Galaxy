// Where home bases and outposts sit on their planet: far enough apart to tell apart on the
// High Port's hologram.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const S = require('../sites');
const W = require('../war');

// A satellite site as saves from before the war have them: off the home planet, with no sector
// or faction.
function oldSite(g, owner, type, n) {
  const home = g.system.planets.find((p) => p.owner === owner && p.kind !== 'satellite');
  const site = {
    id: `${home.id}-site-${n}`, name: `${home.name} ${type}`, kind: 'satellite', owner, parent: home.id, orbit: n - 1,
    slots: 1, grid: 12, pieces: [], obstacles: [], nextPiece: 1,
    buildings: [{ slot: 0, type, level: 1, security: 1, vault: {}, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} }],
  };
  g.system.planets.push(site);
  return site;
}

test('outposts stand in their sector, apart from each other and from other sectors', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.setCommandLevel(g, G.claimBase(g, 'Akane').id, 5);
  G.demoTopUp(g.bases.Akane);
  G.chooseFaction(g, 'builder', 'Akane', 'compact');
  const sector = (id) => W.planet(g, 'cinder').sectors.find((s) => s.id === id);
  const one = ['refinery', 'lab', 'spire'].map((type) => G.foundSite(g, 'Akane', type, 'cinder', 'cinder-1').site);
  const two = ['fuel', 'drones'].map((type) => G.foundSite(g, 'Akane', type, 'cinder', 'cinder-2').site);
  const centre = [sector('cinder-1').lat, sector('cinder-1').lon];
  assert.deepStrictEqual(one[0].surface, centre, 'the first in a sector stands at its centre');
  assert.deepStrictEqual(two[0].surface, [sector('cinder-2').lat, sector('cinder-2').lon]);
  for (const s of one.slice(1)) {
    const d = S.angleBetween(s.surface, centre);
    assert.ok(d > 3.5 && d < 5, `the rest on a small ring round it (${d})`);
  }
  assert.ok(S.angleBetween(one[1].surface, one[2].surface) > 6, 'and apart from each other');
  for (const a of one) for (const b of two) assert.ok(S.angleBetween(a.surface, b.surface) > 25, 'sectors are well apart');
  assert.deepStrictEqual(g.system.planets.find((p) => p.id === 'aster').surface, [15, 30], 'the home base keeps its place');
});

test('sites from before the war get a place on load; places never move, and outposts are left alone', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.setCommandLevel(g, G.claimBase(g, 'Akane').id, 5);
  G.demoTopUp(g.bases.Akane);
  const a = oldSite(g, 'Akane', 'refinery', 1);
  const b = oldSite(g, 'Akane', 'lab', 2);
  S.locate(g);
  for (const s of [a, b]) assert.ok(Array.isArray(s.surface) && Math.abs(s.surface[0]) <= 60, 'a place, away from the poles');
  assert.ok(S.angleBetween(a.surface, b.surface) >= 60 && S.angleBetween(a.surface, [15, 30]) >= 60);
  const kept = a.surface.slice();
  delete b.surface; // an old save
  S.locate(g);
  assert.deepStrictEqual(a.surface, kept);
  assert.ok(Array.isArray(b.surface) && S.angleBetween(a.surface, b.surface) >= 60);

  G.setCommandLevel(g, G.claimBase(g, 'Rin').id, 5);
  G.demoTopUp(g.bases.Rin);
  G.chooseFaction(g, 'builder', 'Rin', 'luminar');
  const op = G.foundSite(g, 'Rin', 'fuel', 'halcyon', 'halcyon-3').site;
  op.surface = [1, 2];
  S.locate(g);
  assert.deepStrictEqual(op.surface, [1, 2], 'an outpost in a sector keeps the place its sector gave it');
});
