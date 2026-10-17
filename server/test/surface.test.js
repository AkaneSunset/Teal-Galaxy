// Where home bases and satellite sites sit on their planet: far enough apart to tell apart on the
// High Port's hologram.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const S = require('../sites');

test('every site gets its own place on the planet, well apart from the base and each other', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.claimBase(g, 'Akane');
  G.demoTopUp(g.bases.Akane);
  for (const type of ['refinery', 'lab', 'spire']) assert.ok(G.foundSite(g, 'Akane', type).ok, type);
  const home = g.system.planets.find((p) => p.id === 'aster');
  const sites = g.system.planets.filter((p) => p.kind === 'satellite');
  const spots = [home.surface, ...sites.map((s) => s.surface)];
  for (const s of spots) assert.ok(Array.isArray(s) && Math.abs(s[0]) <= 60, 'a place, away from the poles');
  for (let i = 0; i < spots.length; i++) {
    for (let j = i + 1; j < spots.length; j++) {
      assert.ok(S.angleBetween(spots[i], spots[j]) >= 60, `spots ${i} and ${j} are at least 60 degrees apart`);
    }
  }
});

test('sites founded before places existed get one on load, and places never move', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.claimBase(g, 'Akane');
  G.demoTopUp(g.bases.Akane);
  G.foundSite(g, 'Akane', 'refinery');
  G.foundSite(g, 'Akane', 'lab');
  const [a, b] = g.system.planets.filter((p) => p.kind === 'satellite');
  const kept = a.surface.slice();
  delete b.surface; // an old save
  S.locate(g);
  assert.deepStrictEqual(a.surface, kept);
  assert.ok(Array.isArray(b.surface) && S.angleBetween(a.surface, b.surface) >= 60);
});
