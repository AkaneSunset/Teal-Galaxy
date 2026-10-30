// The Ship Foundry: building it, queuing warships, launching them into the navy.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const N = require('../navy');
const W = require('../war');

function base() {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity; // instant buildings: build times are tested in levels.test.js
  g.stock.metal = 1000;
  g.stock.ice = 50;
  g.stock.alloy = 100;
  g.stock.isotope = 10;
  G.setCommandLevel(g, 'aster', 3); // the Ship Foundry opens at level 3
  return g;
}

test('the Foundry needs a Star Port and Command Centre level 3, and a base gets only one', () => {
  const g = base();
  G.setCommandLevel(g, 'aster', 2);
  assert.match(G.build(g, 'aster', 6, 'foundry').reason, /Command Centre to level 3/);
  G.setCommandLevel(g, 'aster', 3);
  assert.match(G.build(g, 'aster', 6, 'foundry').reason, /Star Port first/);
  assert.ok(G.build(g, 'aster', 0, 'spaceport').ok);
  assert.ok(G.build(g, 'aster', 6, 'foundry').ok);
  assert.match(G.build(g, 'aster', 6, 'foundry').reason, /already there/);
});

test('ships build one at a time, in order, and launch into the navy', () => {
  const g = base();
  G.build(g, 'aster', 0, 'spaceport');
  G.build(g, 'aster', 6, 'foundry');
  g.buildSpeed = 1; // ships take their real time from here on
  const t = 1_000_000;
  const metal = g.stock.metal;
  assert.ok(G.queueShip(g, 'aster', 6, 'corvette', t).ok);
  assert.ok(G.queueShip(g, 'aster', 6, 'frigate', t).ok);
  assert.strictEqual(g.stock.metal, metal - 75);
  assert.strictEqual(g.stock.alloy, 90);

  G.tick(g, t + 59_000);
  assert.strictEqual(g.navy.corvette, 0);
  G.tick(g, t + 60_000);
  assert.strictEqual(g.navy.corvette, 1);
  // The frigate starts when the corvette is done, even if the server ticks late.
  G.tick(g, t + 60_000 + 179_000);
  assert.strictEqual(g.navy.frigate, 0);
  G.tick(g, t + 60_000 + 180_000);
  assert.strictEqual(g.navy.frigate, 1);
  assert.ok(g.feed.some((e) => e.text === 'Frigate launched from the Ship Foundry on Aster'));
});

test('demo build speed builds warships faster too', () => {
  const g = base();
  G.build(g, 'aster', 0, 'spaceport');
  G.build(g, 'aster', 6, 'foundry');
  g.buildSpeed = 10;
  const t = 1_000_000;
  assert.ok(G.queueShip(g, 'aster', 6, 'corvette', t).ok);
  G.tick(g, t + 5_000);
  assert.strictEqual(g.navy.corvette, 0);
  G.tick(g, t + 6_000);
  assert.strictEqual(g.navy.corvette, 1);
});

test('costs, queue and hangar limits, and cancelling refunds', () => {
  const g = base();
  G.build(g, 'aster', 0, 'spaceport');
  G.build(g, 'aster', 6, 'foundry');
  g.stock.isotope = 0;
  assert.match(G.queueShip(g, 'aster', 6, 'destroyer', 0).reason, /not enough Isotope/i);
  assert.match(G.queueShip(g, 'aster', 1, 'corvette', 0).reason, /no Ship Foundry/);

  for (let i = 0; i < N.QUEUE_MAX; i++) assert.ok(G.queueShip(g, 'aster', 6, 'corvette', 0).ok);
  assert.match(G.queueShip(g, 'aster', 6, 'corvette', 0).reason, /queue is full/);

  const metal = g.stock.metal;
  assert.ok(G.cancelShip(g, 'aster', 6).ok);
  assert.strictEqual(g.stock.metal, metal + 25);

  g.navy.corvette = N.HANGAR - 4; // 4 still queued fills the hangar
  assert.match(G.queueShip(g, 'aster', 6, 'corvette', 0).reason, /hangar is full/);
});

test('ships out with fleets keep their berths in the hangar', () => {
  const g = base();
  G.claimBase(g, 'Akane'); // takes over Aster and its economy
  G.chooseFaction(g, 'builder', 'Akane', 'compact');
  G.build(g, 'aster', 0, 'spaceport');
  G.build(g, 'aster', 6, 'foundry');
  const e = g.bases.Akane;
  e.navy.corvette = N.HANGAR;
  assert.ok(W.sendFleet(g, 'Akane', 'teal-prime', { corvette: 6 }, 0).ok);
  assert.strictEqual(G.queueShip(g, 'aster', 6, 'corvette', 0).reason, 'the hangar is full: 6 of its ships are out with your fleets');
  W.warTick(g, 10_000);
  assert.strictEqual(G.queueShip(g, 'aster', 6, 'corvette', 10_000).reason, 'the hangar is full: 6 of its ships are out with your fleets', 'in orbit too');
  e.navy.corvette = 3;
  assert.ok(G.queueShip(g, 'aster', 6, 'corvette', 10_000).ok, '3 home, 6 out, 1 building');
  assert.strictEqual(G.queueShip(g, 'aster', 6, 'corvette', 10_000).reason, 'the hangar is full: 6 of its ships are out with your fleets');
  g.war.fleets = []; // lost in battle: their berths are free again
  assert.ok(G.queueShip(g, 'aster', 6, 'corvette', 10_000).ok);
});

test('old saves get a navy', () => {
  const g = base();
  delete g.navy;
  G.recoverRaids(g);
  assert.deepStrictEqual(g.navy, { corvette: 0, frigate: 0, destroyer: 0 });
  assert.ok(g.unlocked.includes('foundry'));
});
