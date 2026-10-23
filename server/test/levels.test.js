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
  G.setCommandLevel(g, 'aster', 3);
  e.stock.metal = 400; // under the Warehouse cap, so the Extractor adds to it
  const t = 1_000_000;
  assert.ok(G.build(g, 'aster', 1, 'extractor', t).ok);
  const ex = g.system.planets[0].buildings.find((b) => b.type === 'extractor');
  assert.strictEqual(ex.level, 0);
  assert.strictEqual(ex.readyAt, t + G.BUILD_S.extractor * 1000);
  const metal = e.stock.metal;
  G.tick(g, t + 29_000);
  assert.strictEqual(e.stock.metal, metal, 'no metal while under construction');
  G.tick(g, t + 30_000);
  assert.strictEqual(ex.level, 1);
  assert.strictEqual(e.stock.metal, metal + 1);
  // A Star Port still being built doesn't count for a Ship Foundry.
  assert.ok(G.build(g, 'aster', 0, 'spaceport', t).ok);
  assert.match(G.build(g, 'aster', 6, 'foundry', t).reason, /Star Port first/);
});

test('each level costs and takes twice the last, produces more, and waits for the Command Centre', () => {
  const { g, e } = base();
  g.buildSpeed = Infinity;
  G.build(g, 'aster', 1, 'extractor');
  g.buildSpeed = 1;
  const ex = g.system.planets[0].buildings.find((b) => b.type === 'extractor');
  assert.deepStrictEqual(G.levelCost('extractor', 1), { metal: 30 });
  assert.deepStrictEqual(G.levelCost('extractor', 2), { metal: 60 });
  const t = 2_000_000;
  assert.match(G.upgradeBuilding(g, 'aster', 1, t).reason, /Command Centre to level 2 first/);
  assert.ok(G.upgradeBuilding(g, 'aster', G.COMMAND_SLOT, t).ok, 'the Command Centre levels itself');
  const cc = g.system.planets[0].buildings.find((b) => b.type === 'command');
  assert.strictEqual(cc.readyAt, t + G.BUILD_S.command * 2000);
  G.tick(g, cc.readyAt);
  assert.strictEqual(G.commandLevel(g.system.planets[0]), 2);
  e.stock.metal = 400; // under the Warehouse cap, so the Extractor adds to it
  const metal = e.stock.metal;
  assert.ok(G.upgradeBuilding(g, 'aster', 1, t).ok);
  assert.strictEqual(e.stock.metal, metal - 30);
  assert.strictEqual(ex.readyAt, t + 60_000, 'level 2 takes twice the build time');
  assert.match(G.upgradeBuilding(g, 'aster', 1, t).reason, /still upgrading/);
  G.tick(g, t + 10_000);
  assert.strictEqual(e.stock.metal, metal - 30, 'no production while upgrading');
  G.tick(g, t + 60_000);
  assert.strictEqual(ex.level, 2);
  assert.strictEqual(e.stock.metal, metal - 28, 'level 2 digs 2 a tick');
  G.setCommandLevel(g, 'aster', 5);
  e.stock.metal = 5000;
  for (const lvl of [3, 4, 5]) {
    assert.ok(G.upgradeBuilding(g, 'aster', 1, t).ok);
    G.tick(g, ex.readyAt);
    assert.strictEqual(ex.level, lvl);
  }
  assert.match(G.upgradeBuilding(g, 'aster', 1, t).reason, /top level/);
  assert.match(G.upgradeBuilding(g, 'aster', G.COMMAND_SLOT, t).reason, /top level/);
});

test('every node has its own place, opened by a Command Centre level', () => {
  const { g } = base();
  g.buildSpeed = Infinity;
  assert.match(G.build(g, 'aster', 0, 'habitat').reason, /that node is for the Star Port/);
  assert.match(G.build(g, 'aster', G.COMMAND_SLOT, 'command').reason, /already there/);
  assert.match(G.build(g, 'aster', 4, 'warehouse').reason, /Command Centre to level 2/);
  G.tick(g); // ice in stock unlocks the Hydroponics Lab
  for (let level = 1; level <= G.MAX_LEVEL; level++) {
    G.setCommandLevel(g, 'aster', level);
    for (const type of G.COMMAND_LEVELS[level].nodes) assert.ok(G.build(g, 'aster', G.NODES.indexOf(type), type).ok, type);
  }
  assert.strictEqual(g.system.planets[0].buildings.length, G.NODES.length + 1);
});

test('outposts and defences take time too; unfinished defences are not there for raiders', () => {
  const { g } = base();
  const t = 1_000_000;
  G.chooseFaction(g, 'builder', 'Akane', 'compact');
  G.setCommandLevel(g, 'aster', 2);
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
  G.build(g, 'aster', 1, 'extractor');
  const ex = g.system.planets[0].buildings.find((b) => b.type === 'extractor');
  delete ex.level;
  G.recoverRaids(g);
  assert.strictEqual(ex.level, 1);
});
