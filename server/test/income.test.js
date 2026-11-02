// Passive income: buildings produce on their own, so Builders progress with no pilots online.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');

// `owner`'s outpost on Cinder, which their faction (the Terran Compact) holds. Each sector takes 3.
function outpost(g, owner, type, sector = 'cinder-1') {
  G.setCommandLevel(g, G.claimBase(g, owner).id, 5); // room for every outpost
  if (!g.bases[owner].faction) G.chooseFaction(g, 'builder', owner, 'compact');
  const r = G.foundSite(g, owner, type, 'cinder', sector);
  assert.ok(r.ok, r.reason);
  return r;
}

test('extractors, habitats and hydroponics produce every tick', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity; // instant buildings: build times are tested in levels.test.js
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  e.stock.metal = 100;
  for (const [slot, type] of [[1, 'extractor'], [2, 'habitat']]) assert.ok(G.build(g, 'aster', slot, type).ok);
  const metal = e.stock.metal;
  const credits = e.credits;
  for (let i = 0; i < 6; i++) G.tick(g, 1000 + i);
  assert.strictEqual(e.stock.metal, metal + 6, 'the Extractor digs metal');
  assert.strictEqual(e.credits, credits + 6);
  assert.strictEqual(e.stock.ice, 1, 'and one ice every 6 ticks');
  assert.ok(e.unlocked.includes('hydroponics'), 'the first ice unlocks Hydroponics without a pilot');
  for (let i = 0; i < 54; i++) G.tick(g, 2000 + i);
  assert.strictEqual(e.stock.ice, 10, '10 ice in 5 minutes');
  assert.match(G.build(g, 'aster', 3, 'hydroponics').reason, /Command Centre to level 2/);
  G.setCommandLevel(g, 'aster', 2);
  assert.ok(G.build(g, 'aster', 3, 'hydroponics').ok);
  const c = e.credits;
  G.tick(g, 3000);
  assert.strictEqual(e.credits, c + 3);
});

test('the Power Plant adds 10% a level; the Warehouse decides how much metal and ice the base makes', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.claimBase(g, 'Akane');
  G.setCommandLevel(g, 'aster', 2);
  const e = g.bases.Akane;
  e.stock.metal = 200;
  e.stock.ice = 20;
  assert.ok(G.build(g, 'aster', 1, 'extractor').ok);
  assert.ok(G.build(g, 'aster', 5, 'power').ok);
  const metal = e.stock.metal;
  for (let i = 0; i < 10; i++) G.tick(g, 1000 + i);
  assert.strictEqual(e.stock.metal, metal + 11, '1.1 metal a tick');

  assert.strictEqual(G.storageCap(g, 'aster'), G.STORAGE_BASE);
  e.stock.metal = G.STORAGE_BASE - 1;
  for (let i = 0; i < 5; i++) G.tick(g, 2000 + i);
  assert.strictEqual(e.stock.metal, G.STORAGE_BASE, 'production stops at the cap');
  assert.ok(G.build(g, 'aster', 4, 'warehouse').ok);
  assert.strictEqual(G.storageCap(g, 'aster'), G.STORAGE_BASE + G.STORAGE_PER_LEVEL);
  e.stock.metal = G.STORAGE_BASE;
  G.tick(g, 3000);
  assert.ok(e.stock.metal > G.STORAGE_BASE, 'room again with a Warehouse');
});

test('a facility sends its vault home on its own every few minutes', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity; // instant buildings: build times are tested in levels.test.js
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  const { site } = outpost(g, 'Akane', 'refinery');
  const t = 1_000_000;
  G.tick(g, t);
  const b = G.facility(g, site.id, 0);
  assert.ok(b.vault.alloy > 0);
  assert.strictEqual(e.stock.alloy || 0, 0);
  G.tick(g, t + G.AUTO_SHIP_MS - 1);
  assert.strictEqual(e.stock.alloy || 0, 0, 'goods wait in the vault, where they can be raided');
  G.tick(g, t + G.AUTO_SHIP_MS);
  assert.ok(e.stock.alloy > 0);
  assert.ok(b.vault.alloy <= 1, 'the vault starts filling again');
  assert.ok(g.feed.some((f) => f.text.startsWith('Scheduled freighter')));
});

test('demo mode gives each base enough to build everything, once', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity; // instant buildings: build times are tested in levels.test.js
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  assert.ok(G.demoTopUp(e));
  assert.ok(!G.demoTopUp(e), 'only once, so spending sticks');
  G.setCommandLevel(g, 'aster', 5);
  for (const type of G.NODES) assert.ok(G.build(g, 'aster', G.NODES.indexOf(type), type).ok, type);
  for (const type of ['refinery', 'lab', 'spire']) outpost(g, 'Akane', type);
  for (const type of ['ordnance', 'haulers']) outpost(g, 'Akane', type, 'cinder-2');
  const site = g.system.planets.find((p) => p.owner === 'Akane' && p.kind === 'satellite');
  assert.ok(G.secure(g, site.id, 0).ok, 'security tier 2');
  assert.ok(G.secure(g, site.id, 0).ok, 'security tier 3');
  assert.ok(G.queueShip(g, 'aster', 6, 'destroyer', 0).ok);
});
