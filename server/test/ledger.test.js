// The war-supply ledger: sources, the arena and Frontier shares, the underdog multiplier, and
// campaigns rolling over.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const G = require('../galaxy');
const L = require('../ledger.ts');
const W = require('../war');

// A demo-war galaxy (every faction in every campaign) with its campaigns started, and the player
// factions equally strong (every multiplier 1).
function setup() {
  W.setDemo(true);
  const g = G.newGalaxy();
  const t = C.DEMO_CYCLE_MS * 100;
  C.tick(g, t);
  g.director.strength = { compact: 0.3, ashen: 0.3, luminar: 0.3 };
  return { g, t };
}

test('credits by source, with no daily cap, and receipts for whoever earned them', () => {
  const { g, t } = setup();
  for (let i = 0; i < 40; i++) L.credit(g, { planet: 'cinder', faction: 'compact', source: 'builder', base: 25, who: 'builder/Akane' }, t + i);
  const r = L.credit(g, { planet: 'cinder', faction: 'compact', source: 'battle', base: 10, who: 'explorer/Kite', factionName: () => 'Terran Compact' }, t + 50);
  assert.strictEqual(r.text, '+10 war supply for the Terran Compact on Cinder from battles');
  const v = L.frontView(g, 'cinder', t + 60);
  assert.strictEqual(v.factions.compact.total, 1010, 'a thousand from one Builder in a day: no cap');
  assert.deepStrictEqual(v.factions.compact.sources, { builder: 1000, battle: 10, arena: 0, frontier: 0 });
  assert.strictEqual(v.factions.compact.perHour, 1010);
  assert.strictEqual(L.receipts(g, 'builder/Akane').length, 20, 'the last ledger.receiptsKept receipts');
  assert.strictEqual(L.receipts(g, 'explorer/Kite')[0].credited, 10);
  assert.strictEqual(L.frontView(g, 'cinder', t + 60 + 3600_000).factions.compact.perHour, 0, 'the rate is over the last hour');
  assert.strictEqual(L.credit(g, { planet: 'bastion', faction: 'compact', source: 'battle', base: 10 }, t), null, 'no campaign on a capital world');
  assert.strictEqual(L.credit(g, { planet: 'cinder', faction: 'compact', source: 'orders', base: 10 }, t), null, 'orders never pay war supply');
});

test('the arena is at most 15% of a faction\'s war supply on a front, the Frontier at most 40%', () => {
  const { g, t } = setup();
  const credit = (source, base) => L.credit(g, { planet: 'vesper', faction: 'ashen', source, base, factionName: () => 'Ashen Collective' }, t);
  const first = credit('arena', 10);
  assert.deepStrictEqual([first.credited, first.capped], [0, 10], 'arena supply alone credits nothing');
  assert.match(first.text, /^\+0 of 10 war supply for the Ashen Collective on Vesper: the arena may be at most 15% of a faction's war supply on a front, and 10 would have gone past it$/);
  credit('battle', 85);
  const r = credit('arena', 40);
  assert.strictEqual(r.credited, 15, 'up to 15 of 100');
  let s = L.frontView(g, 'vesper', t).factions.ashen;
  assert.strictEqual(s.sources.arena / s.total, 0.15);
  assert.strictEqual(s.capped.arena, 35);
  credit('frontier', 1000);
  s = L.frontView(g, 'vesper', t).factions.ashen;
  assert.ok(Math.abs(s.sources.frontier / s.total - 0.4) < 0.001, `Frontier ${s.sources.frontier} of ${s.total}`);
  assert.ok(s.sources.arena / s.total < 0.15, 'the shares are of the total, so the arena share drops');
  assert.strictEqual(credit('arena', 5).credited, 5, 'and it has room again');
});

test('the underdog multiplier: 0.8 to 1.3 by strength, on war supply only', () => {
  const { g, t } = setup();
  g.director.strength = { compact: 0.6, ashen: 0.3, luminar: 0.1 };
  const m = L.multipliers(g);
  assert.deepStrictEqual(m, { compact: 0.8, ashen: 1.05, luminar: 1.3 });
  const r = L.credit(g, { planet: 'halcyon', faction: 'luminar', source: 'battle', base: 10, factionName: () => 'Luminar Accord' }, t);
  assert.strictEqual(r.credited, 13);
  assert.strictEqual(r.text, '+13 war supply for the Luminar Accord on Halcyon from battles (10 x1.3 underdog multiplier)');
  assert.strictEqual(L.multiplier(g, 'coma'), 1, 'Coma is not weighed');
  g.director.strength = { compact: 0, ashen: 0, luminar: 0 };
  assert.strictEqual(L.multiplier(g, 'compact'), 1, 'no strength anywhere: 1');
});

test('a new campaign files the last one in the front\'s history and starts from nothing', () => {
  const { g, t } = setup();
  L.credit(g, { planet: 'morrow', faction: 'compact', source: 'battle', base: 10 }, t);
  const c = g.war.campaigns.morrow;
  assert.strictEqual(L.credit(g, { planet: 'morrow', faction: 'compact', source: 'battle', base: 10 }, c.endsAt), null, 'nothing once the campaign is over');
  assert.strictEqual(L.credit(g, { planet: 'morrow', faction: 'nobody', source: 'battle', base: 10 }, t), null, 'only factions in the campaign');
  C.tick(g, c.endsAt);
  const v = L.frontView(g, 'morrow', c.endsAt + 1);
  assert.deepStrictEqual(v.factions, {});
  assert.strictEqual(v.history[0].factions.compact.total, 10);
  assert.strictEqual(v.history[0].campaign, c.startsAt);
  const all = L.view(g, c.endsAt + 1);
  assert.ok(all.fronts.morrow && all.fronts.cinder);
  assert.deepStrictEqual(all.shares, { arena: 0.15, frontier: 0.4 });
  W.setDemo(false);
});
