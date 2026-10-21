// The Carrier Dock and its market, pilots' supply contracts, and donations to the war supply.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');

// Akane's base with a Spaceport and, unless `dock` is false, a finished Carrier Dock; she and
// the pilots named are in the given factions.
function base({ dock = true, faction = 'compact', pilots = {} } = {}) {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.claimBase(g, 'Akane');
  G.demoTopUp(g.bases.Akane);
  if (faction) G.chooseFaction(g, 'builder', 'Akane', faction);
  assert.ok(G.build(g, 'aster', 0, 'spaceport').ok);
  if (dock) assert.ok(G.build(g, 'aster', 1, 'dock').ok);
  for (const [name, f] of Object.entries(pilots)) {
    G.chooseFaction(g, 'explorer', name, f);
    g.pilots[name].credits = 1000;
  }
  return { g, e: g.bases.Akane };
}

test('the Carrier Dock: after a Spaceport, one per base, 3 minutes to build', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  G.demoTopUp(g.bases.Akane);
  g.buildSpeed = 1;
  assert.match(G.build(g, 'aster', 0, 'dock').reason, /Spaceport first/);
  g.buildSpeed = Infinity;
  G.build(g, 'aster', 0, 'spaceport');
  g.buildSpeed = 1;
  const metal = g.bases.Akane.stock.metal;
  const alloy = g.bases.Akane.stock.alloy;
  assert.ok(G.build(g, 'aster', 1, 'dock', 0).ok);
  assert.deepStrictEqual([metal - g.bases.Akane.stock.metal, alloy - g.bases.Akane.stock.alloy], [80, 10]);
  assert.strictEqual(g.system.planets[0].buildings[1].readyAt, 180_000);
  assert.match(G.build(g, 'aster', 2, 'dock').reason, /already have a Carrier Dock/);
  assert.strictEqual(G.setPrice(g, 'Akane', 'metal', 5).reason, 'build a Carrier Dock first', 'not until it is finished');
  G.tick(g, 180_000);
  assert.ok(G.setPrice(g, 'Akane', 'metal', 5).ok);
});

test('the dock market: list anything in stock at a whole-credit price, or take it off', () => {
  const { g, e } = base({ dock: false });
  assert.strictEqual(G.setPrice(g, 'Akane', 'fuel', 10).reason, 'build a Carrier Dock first');
  G.build(g, 'aster', 1, 'dock');
  assert.ok(G.setPrice(g, 'Akane', 'fuel', 10).ok);
  assert.ok(G.setPrice(g, 'Akane', 'metal', 3).ok);
  assert.ok(G.setPrice(g, 'Akane', 'ice', 100000).ok);
  assert.strictEqual(G.setPrice(g, 'Akane', 'unobtainium', 3).reason, 'no such item');
  for (const bad of [-1, 1.5, 100001, '5']) assert.match(G.setPrice(g, 'Akane', 'alloy', bad).reason, /whole number of credits from 1 to 100000/);
  assert.deepStrictEqual(e.market, { fuel: 10, metal: 3, ice: 100000 });
  assert.ok(G.setPrice(g, 'Akane', 'ice', 0).ok);
  assert.ok(G.setPrice(g, 'Akane', 'metal', null).ok);
  assert.deepStrictEqual(e.market, { fuel: 10 });
  assert.strictEqual(G.setPrice(g, 'Nobody', 'fuel', 10).reason, 'you have no home planet');
});

test('pilots of the dock\'s faction buy into their war goods hold', () => {
  const { g, e } = base({ pilots: { PilotA: 'compact', PilotB: 'ashen' } });
  e.stock.fuel = 30;
  e.credits = 0;
  G.setPrice(g, 'Akane', 'fuel', 12);
  assert.strictEqual(G.dockBuy(g, 'PilotB', 'Akane', 'fuel', 5).reason, 'this dock only trades with the Terran Compact');
  assert.strictEqual(G.dockBuy(g, 'PilotC', 'Akane', 'fuel', 5).reason, 'choose a faction first');
  assert.strictEqual(G.dockBuy(g, 'PilotA', 'Nobody', 'fuel', 5).reason, 'no such Builder');
  assert.strictEqual(G.dockBuy(g, 'PilotA', 'Akane', 'alloy', 5).reason, 'that is not for sale here');
  assert.strictEqual(G.dockBuy(g, 'PilotA', 'Akane', 'fuel', 31).reason, 'only 30 in stock');
  assert.strictEqual(G.dockBuy(g, 'PilotA', 'Akane', 'fuel', 0).reason, 'bad amount');
  g.pilots.PilotA.credits = 100;
  assert.strictEqual(G.dockBuy(g, 'PilotA', 'Akane', 'fuel', 20).reason, 'not enough credits');
  g.pilots.PilotA.credits = 1000;
  assert.deepStrictEqual(G.dockBuy(g, 'PilotA', 'Akane', 'fuel', 20), { ok: true, cost: 240 });
  assert.strictEqual(g.pilots.PilotA.credits, 760);
  assert.strictEqual(e.credits, 240);
  assert.strictEqual(e.stock.fuel, 10);
  assert.deepStrictEqual(g.pilots.PilotA.hold, { fuel: 20 });
  assert.strictEqual(g.feed.at(-1).text, "PilotA bought 20 Fuel cells at Akane's Carrier Dock");
  assert.strictEqual(e.alerts.at(-1).text, 'PilotA bought 20 Fuel cells at your Carrier Dock for 240 credits');
  G.dockBuy(g, 'PilotA', 'Akane', 'fuel', 10);
  assert.strictEqual(G.dockBuy(g, 'PilotA', 'Akane', 'fuel', 1).reason, 'sold out');

  // Only real listings: keys every object has are not for sale, and nobody's credits change.
  g.pilots.PilotA.credits = 1000;
  e.credits = 500;
  for (const item of ['constructor', 'toString', 'valueOf', 'hasOwnProperty', '__proto__']) {
    assert.strictEqual(G.dockBuy(g, 'PilotA', 'Akane', item, 1).reason, 'that is not for sale here', item);
    assert.strictEqual(G.setPrice(g, 'Akane', item, 5).reason, 'no such item', item);
  }
  e.market.weapon = 'free'; // however it got there, a price that isn't a whole number of credits sells nothing
  e.stock.weapon = 1;
  assert.strictEqual(G.dockBuy(g, 'PilotA', 'Akane', 'weapon', 1).reason, 'that is not for sale here');
  assert.deepStrictEqual([g.pilots.PilotA.credits, e.credits], [1000, 500]);
  assert.deepStrictEqual(g.pilots.PilotA.hold, { fuel: 30 });

  const neutral = base({ faction: null, pilots: { PilotA: 'compact' } });
  G.setPrice(neutral.g, 'Akane', 'metal', 2);
  assert.strictEqual(G.dockBuy(neutral.g, 'PilotA', 'Akane', 'metal', 1).reason, "Akane's dock isn't trading yet");
  const nodock = base({ dock: false, pilots: { PilotA: 'compact' } });
  assert.strictEqual(G.dockBuy(nodock.g, 'PilotA', 'Akane', 'metal', 1).reason, 'Akane has no Carrier Dock');
});

test('supply contracts: the reward is held, shared out by what each Builder brings, and exact in total', () => {
  const { g, e } = base({ pilots: { PilotA: 'compact', PilotB: 'ashen' } });
  G.claimBase(g, 'Rin');
  G.demoTopUp(g.bases.Rin);
  G.chooseFaction(g, 'builder', 'Rin', 'compact');
  assert.strictEqual(G.postContract(g, 'PilotC', 'fuel', 10, 100).reason, 'choose a faction first');
  for (const item of ['drive', 'shard', 'syringe', 'nothing']) assert.strictEqual(G.postContract(g, 'PilotA', item, 10, 100).reason, 'contracts are for materials and supplies', item);
  for (const amount of [0, 1001, 2.5]) assert.strictEqual(G.postContract(g, 'PilotA', 'metal', amount, 100).reason, 'ask for 1 to 1000');
  assert.strictEqual(G.postContract(g, 'PilotA', 'metal', 10, 0).reason, 'the reward must be at least 1 credit');
  assert.strictEqual(G.postContract(g, 'PilotA', 'metal', 10, 5000).reason, 'not enough credits');
  assert.ok(G.CONTRACT_ITEMS.includes('hauler') && G.CONTRACT_ITEMS.includes('alloy') && G.CONTRACT_ITEMS.includes('ice'));

  const { contract: c } = G.postContract(g, 'PilotA', 'alloy', 3, 100);
  assert.deepStrictEqual(c, { id: 1, pilot: 'PilotA', faction: 'compact', item: 'alloy', amount: 3, reward: 100, filled: 0, paid: 0, contributions: {}, status: 'open' });
  assert.strictEqual(g.pilots.PilotA.credits, 900, 'held from the pilot\'s credits');
  const credits = e.credits;
  G.chooseFaction(g, 'builder', 'Akane', 'ashen'); // already set: stays Compact
  assert.strictEqual(G.fillContract(g, 'Akane', 99, 1).reason, 'no open contract');
  assert.strictEqual(G.fillContract(g, 'Akane', c.id, 4).reason, 'only 3 more needed');
  assert.strictEqual(G.fillContract(g, 'Akane', c.id, 0).reason, 'bad amount');
  e.stock.alloy = 0;
  assert.strictEqual(G.fillContract(g, 'Akane', c.id, 1).reason, 'not enough Alloy plate');
  e.stock.alloy = 10;
  assert.deepStrictEqual(G.fillContract(g, 'Akane', c.id, 1), { ok: true, paid: 33 });
  assert.deepStrictEqual(G.fillContract(g, 'Rin', c.id, 1), { ok: true, paid: 33 });
  assert.deepStrictEqual(G.fillContract(g, 'Akane', c.id, 1), { ok: true, paid: 34 }, 'the last fill gets the rest');
  assert.strictEqual(c.status, 'done');
  assert.strictEqual(c.paid, 100);
  assert.deepStrictEqual(c.contributions, { Akane: 2, Rin: 1 });
  assert.strictEqual(e.credits, credits + 67);
  assert.strictEqual(e.stock.alloy, 8);
  assert.deepStrictEqual(g.pilots.PilotA.hold, { alloy: 3 });
  assert.strictEqual(G.fillContract(g, 'Akane', c.id, 1).reason, 'no open contract');

  // Rounding never pays out more than the reward, and the total is always exact.
  const { contract: d } = G.postContract(g, 'PilotA', 'metal', 8, 5);
  for (let i = 0; i < 8; i++) assert.ok(G.fillContract(g, 'Akane', d.id, 1).ok);
  assert.strictEqual(d.paid, 5);
  // Another faction's Builder can't fill it; cancelling refunds what wasn't paid.
  const { contract: x } = G.postContract(g, 'PilotB', 'fuel', 10, 100);
  assert.strictEqual(G.fillContract(g, 'Akane', x.id, 1).reason, 'that contract is for the Ashen Collective');
  const { contract: y } = G.postContract(g, 'PilotA', 'metal', 10, 100);
  G.fillContract(g, 'Akane', y.id, 4);
  assert.strictEqual(y.paid, 40);
  const before = g.pilots.PilotA.credits;
  assert.strictEqual(G.cancelContract(g, 'PilotB', y.id).reason, 'no open contract of yours');
  assert.deepStrictEqual(G.cancelContract(g, 'PilotA', y.id), { ok: true, refunded: 60 });
  assert.strictEqual(g.pilots.PilotA.credits, before + 60);
  assert.strictEqual(y.status, 'cancelled');
  assert.deepStrictEqual(g.pilots.PilotA.hold, { alloy: 3, metal: 12 }, 'what was delivered stays delivered');
  // Five open contracts at a time.
  for (let i = 0; i < 5; i++) assert.ok(G.postContract(g, 'PilotA', 'ice', 1, 1).ok);
  assert.strictEqual(G.postContract(g, 'PilotA', 'ice', 1, 1).reason, 'you already have 5 open contracts');
});

test('donations go to the faction\'s war supply and earn War Merit and ranks', () => {
  const { g, e } = base({ faction: null });
  assert.strictEqual(G.donate(g, 'Akane', 'metal', 10).reason, 'choose a faction first');
  G.chooseFaction(g, 'builder', 'Akane', 'coma', 0, { admin: true }); // an admin playing the Conglomerate
  assert.strictEqual(G.donate(g, 'Akane', 'metal', 0).reason, 'bad amount');
  assert.strictEqual(G.donate(g, 'Akane', 'gold', 1).reason, 'no such item');
  assert.strictEqual(G.donate(g, 'Akane', 'metal', 99999).reason, 'not enough metal');
  const metal = e.stock.metal;
  assert.deepStrictEqual(G.donate(g, 'Akane', 'metal', 200), { ok: true, merit: 400, rank: 'Recruit' });
  assert.strictEqual(e.stock.metal, metal - 200);
  assert.deepStrictEqual(g.war.supply['teal-prime'].coma, { metal: 200 });
  assert.deepStrictEqual(g.war.supply['teal-prime'].compact, {});
  assert.deepStrictEqual(G.donate(g, 'Akane', 'ice', 50), { ok: true, merit: 550, rank: 'Supplier' });
  assert.strictEqual(e.alerts.at(-1).text, '550 War Merit: you are now a Supplier');
  assert.ok(g.feed.some((f) => f.text === 'Akane donated 50 ice to the Coma Conglomerate'));
  e.stock.exotic = 2;
  G.donate(g, 'Akane', 'exotic', 2); // 900 each
  assert.strictEqual(e.merit, 2350);
  assert.deepStrictEqual(g.war.supply['teal-prime'].coma, { metal: 200, ice: 50, exotic: 2 });
  assert.strictEqual(G.MERIT_VALUE.fuel, 12);
  assert.strictEqual(G.MERIT_VALUE.metal, 2);
});
