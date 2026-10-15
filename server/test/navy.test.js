// The Ship Foundry: building it, queuing warships, launching them into the navy.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const N = require('../navy');

function base() {
  const g = G.newGalaxy();
  g.stock.metal = 1000;
  g.stock.ice = 50;
  g.stock.alloy = 100;
  g.stock.isotope = 10;
  return g;
}

test('the Foundry needs a Spaceport, and a base gets only one', () => {
  const g = base();
  assert.match(G.build(g, 'aster', 0, 'foundry').reason, /Spaceport first/);
  assert.ok(G.build(g, 'aster', 0, 'spaceport').ok);
  assert.ok(G.build(g, 'aster', 1, 'foundry').ok);
  assert.match(G.build(g, 'aster', 2, 'foundry').reason, /already have/);
});

test('ships build one at a time, in order, and launch into the navy', () => {
  const g = base();
  G.build(g, 'aster', 0, 'spaceport');
  G.build(g, 'aster', 1, 'foundry');
  const t = 1_000_000;
  const metal = g.stock.metal;
  assert.ok(G.queueShip(g, 'aster', 1, 'corvette', t).ok);
  assert.ok(G.queueShip(g, 'aster', 1, 'frigate', t).ok);
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
  assert.ok(g.feed.some((e) => e.text === 'Frigate launched from the Ship Foundry'));
});

test('costs, queue and hangar limits, and cancelling refunds', () => {
  const g = base();
  G.build(g, 'aster', 0, 'spaceport');
  G.build(g, 'aster', 1, 'foundry');
  g.stock.isotope = 0;
  assert.match(G.queueShip(g, 'aster', 1, 'destroyer', 0).reason, /not enough Isotope/i);
  assert.match(G.queueShip(g, 'aster', 0, 'corvette', 0).reason, /no Ship Foundry/);

  for (let i = 0; i < N.QUEUE_MAX; i++) assert.ok(G.queueShip(g, 'aster', 1, 'corvette', 0).ok);
  assert.match(G.queueShip(g, 'aster', 1, 'corvette', 0).reason, /queue is full/);

  const metal = g.stock.metal;
  assert.ok(G.cancelShip(g, 'aster', 1).ok);
  assert.strictEqual(g.stock.metal, metal + 25);

  g.navy.corvette = N.HANGAR - 4; // 4 still queued fills the hangar
  assert.match(G.queueShip(g, 'aster', 1, 'corvette', 0).reason, /hangar is full/);
});

test('old saves get a navy', () => {
  const g = base();
  delete g.navy;
  G.recoverRaids(g);
  assert.deepStrictEqual(g.navy, { corvette: 0, frigate: 0, destroyer: 0 });
  assert.ok(g.unlocked.includes('foundry'));
});
