// Passive income: buildings produce on their own, so Builders progress with no pilots online.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');

test('mines, extractors, habitats and hydroponics produce every tick', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  e.stock.metal = 100;
  for (const [slot, type] of [[0, 'mine'], [1, 'extractor'], [2, 'habitat']]) assert.ok(G.build(g, 'aster', slot, type).ok);
  const metal = e.stock.metal;
  const credits = e.credits;
  for (let i = 0; i < 6; i++) G.tick(g, 1000 + i);
  assert.strictEqual(e.stock.metal, metal + 6);
  assert.strictEqual(e.credits, credits + 6);
  assert.strictEqual(e.stock.ice, 1, 'one ice every 6 ticks');
  assert.ok(e.unlocked.includes('hydroponics'), 'the first ice unlocks Hydroponics without a pilot');
  for (let i = 0; i < 54; i++) G.tick(g, 2000 + i);
  assert.strictEqual(e.stock.ice, 10, '10 ice in 5 minutes: enough for a Ship Foundry');
  assert.ok(G.build(g, 'aster', 3, 'hydroponics').ok);
  const c = e.credits;
  G.tick(g, 3000);
  assert.strictEqual(e.credits, c + 3);
});

test('a facility sends its vault home on its own every few minutes', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  const { site } = G.foundSite(g, 'Akane', 'refinery');
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
