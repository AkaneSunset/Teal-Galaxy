// Build times and upgrade levels.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const H = require('../heist');

function base() {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  Object.assign(g.bases.Akane.stock, { metal: 5000, ice: 500, alloy: 100 });
  g.bases.Akane.credits = 5000;
  return { g, e: g.bases.Akane };
}

test('a building does nothing until its build time is up', () => {
  const { g, e } = base();
  const t = 1_000_000;
  assert.ok(G.build(g, 'aster', 0, 'mine', t).ok);
  const mine = g.system.planets[0].buildings[0];
  assert.strictEqual(mine.level, 0);
  assert.strictEqual(mine.readyAt, t + G.BUILD_S.mine * 1000);
  const metal = e.stock.metal;
  G.tick(g, t + 19_000);
  assert.strictEqual(e.stock.metal, metal, 'no metal while under construction');
  G.tick(g, t + 20_000);
  assert.strictEqual(mine.level, 1);
  assert.strictEqual(e.stock.metal, metal + 1);
  // A Spaceport still being built doesn't count for a Ship Foundry.
  assert.ok(G.build(g, 'aster', 1, 'spaceport', t).ok);
  assert.match(G.build(g, 'aster', 2, 'foundry', t).reason, /Spaceport first/);
});

test('each level costs and takes twice the last, and produces more', () => {
  const { g, e } = base();
  g.buildSpeed = Infinity;
  G.build(g, 'aster', 0, 'mine');
  g.buildSpeed = 1;
  const mine = g.system.planets[0].buildings[0];
  assert.deepStrictEqual(G.levelCost('mine', 1), { metal: 20 });
  assert.deepStrictEqual(G.levelCost('mine', 2), { metal: 40 });
  const t = 2_000_000;
  const metal = e.stock.metal;
  assert.ok(G.upgradeBuilding(g, 'aster', 0, t).ok);
  assert.strictEqual(e.stock.metal, metal - 20);
  assert.strictEqual(mine.readyAt, t + 40_000, 'level 2 takes twice the build time');
  assert.match(G.upgradeBuilding(g, 'aster', 0, t).reason, /still upgrading/);
  G.tick(g, t + 10_000);
  assert.strictEqual(e.stock.metal, metal - 20, 'no production while upgrading');
  G.tick(g, t + 40_000);
  assert.strictEqual(mine.level, 2);
  assert.strictEqual(e.stock.metal, metal - 18, 'level 2 digs 2 a tick');
  for (const lvl of [3, 4, 5]) {
    assert.ok(G.upgradeBuilding(g, 'aster', 0, t).ok);
    G.tick(g, mine.readyAt);
    assert.strictEqual(mine.level, lvl);
  }
  assert.match(G.upgradeBuilding(g, 'aster', 0, t).reason, /top level/);
});

test('outposts and defences take time too; unfinished defences are not there for raiders', () => {
  const { g } = base();
  const t = 1_000_000;
  G.chooseFaction(g, 'builder', 'Akane', 'compact');
  const { site } = G.foundSite(g, 'Akane', 'fuel', 'cinder', 'cinder-1', t);
  const fac = site.buildings[0];
  assert.strictEqual(fac.level, 0);
  assert.strictEqual(fac.readyAt, t + G.BUILD_S.fuel * 1000);
  site.obstacles = [];
  assert.ok(G.placePiece(g, site.id, 'turret', 0, 0).ok);
  const turret = site.pieces[0];
  const pieces = (now) => H.generateLayout(1, 1, 'fuel', { site, now }).pieces.filter((p) => !p.ring).map((p) => p.type);
  assert.deepStrictEqual(pieces(turret.readyAt - 1), []);
  assert.deepStrictEqual(pieces(turret.readyAt), ['turret']);
});

test('old saves keep their buildings working at level 1', () => {
  const { g } = base();
  g.buildSpeed = Infinity;
  G.build(g, 'aster', 0, 'mine');
  delete g.system.planets[0].buildings[0].level;
  G.recoverRaids(g);
  assert.strictEqual(g.system.planets[0].buildings[0].level, 1);
});
