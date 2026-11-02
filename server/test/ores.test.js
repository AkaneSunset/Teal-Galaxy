// The Extractor's ores and refineries, the galactic market, and the Star Port's sell listings.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');

function base(extractorLevel) {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  G.setCommandLevel(g, 'aster', 5);
  G.build(g, 'aster', 0, 'spaceport');
  G.build(g, 'aster', 1, 'extractor');
  Object.assign(e.stock, { metal: 100, ice: 0 });
  const ex = g.system.planets[0].buildings.find((b) => b.type === 'extractor');
  ex.level = extractorLevel;
  return { g, e, ex };
}

function ticks(g, n) {
  for (let i = 0; i < n; i++) G.tick(g, 1_000_000 + i);
}

test('level 1 digs metal and ice only; each level adds an ore and a refinery', () => {
  let { g, e } = base(1);
  ticks(g, 48);
  assert.deepStrictEqual(Object.keys(e.stock).filter((k) => e.stock[k] > 0).sort(), ['ice', 'metal']);
  ({ g, e } = base(2));
  ticks(g, 12);
  assert.strictEqual(e.stock.copper, 0, 'two copper dug, both refined');
  assert.strictEqual(e.stock.alloy, 1, 'the Alloy Refinery: 4 metal and 2 copper make an Alloy plate');
  assert.strictEqual(e.stock.metal, 100 + 24 - 4);
  ({ g, e } = base(5));
  Object.assign(e.stock, { alloy: 2, titanium: 0, ti_alloy: 1, ir_alloy: 1 });
  ticks(g, 96);
  for (const ore of ['copper', 'titanium', 'iridium', 'xenite']) assert.ok(e.stock[ore] !== undefined, ore);
  assert.strictEqual(e.stock.exotic, 1, 'the Exotic Matter Refinery ran');
});

test('a refinery turned off keeps its inputs; it waits for inputs it lacks', () => {
  let { g, e } = base(2);
  assert.ok(G.setRefinery(g, 'Akane', 2, false).ok);
  ticks(g, 12);
  assert.strictEqual(e.stock.copper, 2);
  assert.strictEqual(e.stock.alloy || 0, 0);
  assert.match(G.setRefinery(g, 'Akane', 3, true).reason, /Titanium Refinery comes with Extractor level 3/);
  ({ g, e } = base(3));
  G.setRefinery(g, 'Akane', 2, false);
  ticks(g, 24);
  assert.strictEqual(e.stock.titanium, 2);
  assert.strictEqual(e.stock.ti_alloy || 0, 0, 'no Alloy plate: the Titanium Refinery waits');
  e.stock.alloy = 2;
  ticks(g, 1);
  assert.strictEqual(e.stock.ti_alloy, 1, 'ready, it runs as soon as the inputs are in');
});

test('the galactic market buys from stock through the Star Port, under what pilots pay', () => {
  const { g, e } = base(1);
  e.stock.alloy = 10;
  const credits = e.credits;
  assert.strictEqual(G.galacticPrice('alloy'), 24);
  assert.deepStrictEqual(G.marketSell(g, 'Akane', 'alloy', 5), { ok: true, paid: 120 });
  assert.deepStrictEqual([e.stock.alloy, e.credits], [5, credits + 120]);
  assert.strictEqual(G.marketSell(g, 'Akane', 'alloy', 6).reason, 'you only have 5');
  assert.match(G.marketSell(g, 'Akane', 'drive', 1).reason, /buys materials, ores and supplies/);
});

test('the Star Port sells to pilots: a berth pays the price, the High Port adds its tariff', () => {
  const { g, e } = base(1);
  e.stock.copper = 30;
  const p = G.pilot(g, 'Pilot A');
  p.credits = 100;
  assert.strictEqual(G.buyFromBuilder(g, 'Pilot A', 'Akane', 'copper', 1, false).reason, "Akane isn't selling that");
  assert.ok(G.setAsk(g, 'Akane', 'copper', 5).ok);
  assert.deepStrictEqual(G.buyFromBuilder(g, 'Pilot A', 'Akane', 'copper', 10, false), { ok: true, cost: 50, tariff: 0 });
  assert.deepStrictEqual(G.buyFromBuilder(g, 'Pilot A', 'Akane', 'copper', 5, true), { ok: true, cost: 25, tariff: 5 });
  assert.deepStrictEqual([p.credits, p.cargo.copper, e.stock.copper], [20, 15, 15]);
  assert.strictEqual(G.buyFromBuilder(g, 'Pilot A', 'Akane', 'copper', 5, false).reason, 'not enough credits');
  assert.strictEqual(G.buyFromBuilder(g, 'Pilot A', 'Akane', 'copper', 50, false).reason, 'only 15 in stock');
  assert.ok(G.setAsk(g, 'Akane', 'copper', 0).ok);
  assert.deepStrictEqual(e.asks, {});
});
