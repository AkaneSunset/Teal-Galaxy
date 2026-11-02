// The Star Port's buy orders: pilots sell to Builders, at full price from a berth and less the
// High Port's tariff from orbit.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');

function base() {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.claimBase(g, 'Akane');
  G.demoTopUp(g.bases.Akane);
  const p = G.pilot(g, 'Pilot A');
  p.cargo.ice = 8;
  p.hold.fuel = 5;
  return { g, e: g.bases.Akane, p };
}

test('buy orders need a Star Port, materials or supplies, a price and how many are wanted', () => {
  const { g, e } = base();
  assert.strictEqual(G.setBid(g, 'Akane', 'ice', 5, 10).reason, 'build a Star Port first');
  G.build(g, 'aster', 0, 'spaceport');
  assert.strictEqual(G.setBid(g, 'Akane', 'drive', 5, 10).reason, 'the Star Port buys materials, ores and supplies');
  assert.match(G.setBid(g, 'Akane', 'ice', 1.5, 10).reason, /whole number of credits/);
  assert.match(G.setBid(g, 'Akane', 'ice', 5, 0).reason, /want 1 to/);
  assert.ok(G.setBid(g, 'Akane', 'ice', 5, 10).ok);
  assert.ok(G.setBid(g, 'Akane', 'fuel', 20, 3).ok);
  assert.deepStrictEqual(e.bids, { ice: { price: 5, want: 10 }, fuel: { price: 20, want: 3 } });
  assert.ok(G.setBid(g, 'Akane', 'fuel', 0).ok);
  assert.deepStrictEqual(Object.keys(e.bids), ['ice']);
  assert.strictEqual(G.setBid(g, 'Nobody', 'ice', 5, 10).reason, 'you have no home planet');
});

test('pilots sell from cargo, then their hold; a berth pays in full, the High Port keeps its tariff', () => {
  const { g, e, p } = base();
  G.build(g, 'aster', 0, 'spaceport');
  G.setBid(g, 'Akane', 'ice', 10, 6);
  G.setBid(g, 'Akane', 'fuel', 20, 10);
  const [credits, ice] = [e.credits, e.stock.ice];
  assert.strictEqual(G.sellToBuilder(g, 'Pilot A', 'Akane', 'metal', 1, false).reason, "Akane isn't buying that");
  assert.strictEqual(G.sellToBuilder(g, 'Pilot A', 'Akane', 'ice', 7, false).reason, 'Akane only wants 6 more');
  assert.deepStrictEqual(G.sellToBuilder(g, 'Pilot A', 'Akane', 'ice', 4, false), { ok: true, paid: 40, tariff: 0 });
  assert.deepStrictEqual([p.credits, p.cargo.ice, e.credits, e.stock.ice, e.bids.ice.want], [40, 4, credits - 40, ice + 4, 2]);
  assert.deepStrictEqual(G.sellToBuilder(g, 'Pilot A', 'Akane', 'ice', 2, true), { ok: true, paid: 16, tariff: 4 });
  assert.strictEqual(e.bids.ice, undefined, 'filled: the order is gone');
  assert.strictEqual(G.sellToBuilder(g, 'Pilot A', 'Akane', 'fuel', 6, false).reason, 'you only have 5');
  assert.ok(G.sellToBuilder(g, 'Pilot A', 'Akane', 'fuel', 5, false).ok);
  assert.strictEqual(p.hold.fuel, 0);
  e.credits = 10;
  G.setBid(g, 'Akane', 'ice', 10, 6);
  assert.strictEqual(G.sellToBuilder(g, 'Pilot A', 'Akane', 'ice', 2, false).reason, "Akane can't pay for that many");
  assert.strictEqual(G.sellToBuilder(g, 'Akane', 'Akane', 'ice', 1, false).reason, "you can't sell to your own base");
  assert.match(e.alerts.at(-1).text, /Pilot A sold you 5 Fuel cells for 100 credits/);
});

test('over the wire: land on a berth to sell in full, or sell from the High Port with the tariff', async () => {
  const WebSocket = require('ws');
  const { startServer } = require('../server');
  const port = 18097;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000 });
  const connect = () =>
    new Promise((resolve) => {
      const ws = new WebSocket(`ws://localhost:${port}`);
      const inbox = [];
      const waiters = [];
      ws.on('message', (data) => {
        const msg = JSON.parse(data);
        const i = waiters.findIndex((w) => w.match(msg));
        if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
        else inbox.push(msg);
      });
      ws.on('open', () =>
        resolve({
          send: (msg) => ws.send(JSON.stringify(msg)),
          next(match) {
            const i = inbox.findIndex(match);
            if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
            return new Promise((res) => waiters.push({ match, resolve: res }));
          },
          close: () => ws.close(),
        })
      );
    });
  try {
    const phone = await connect();
    const pc = await connect();
    phone.send({ type: 'hello', role: 'builder', name: 'Akane' });
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await phone.next((m) => m.type === 'welcome');
    const welcome = await pc.next((m) => m.type === 'welcome');
    assert.deepStrictEqual([welcome.catalog.berthsPerLevel, welcome.catalog.tariff], [2, 0.2]);
    pc.send({ type: 'land_request', base: 'aster' });
    assert.strictEqual((await pc.next((m) => m.type === 'error')).reason, 'there is no Star Port to land at');
    phone.send({ type: 'build', planet: 'aster', slot: 0, building: 'spaceport' });
    phone.send({ type: 'set_bid', item: 'ice', price: 10, want: 20 });
    await phone.next((m) => m.type === 'state' && m.state.bases.Akane.bids?.ice);
    G.pilot(server.galaxy, 'Pilot A').cargo.ice = 10;

    pc.send({ type: 'sell_to_builder', builder: 'Akane', item: 'ice', qty: 1 });
    assert.match((await pc.next((m) => m.type === 'error')).reason, /land at Akane's Star Port or dock at their High Port/);
    pc.send({ type: 'dock_request', station: 'aster' });
    await pc.next((m) => m.type === 'dock_granted');
    pc.send({ type: 'sell_to_builder', builder: 'Akane', item: 'ice', qty: 5 });
    await pc.next((m) => m.type === 'state' && m.state.pilots['Pilot A']?.credits === 40);
    pc.send({ type: 'land_request', base: 'aster' });
    assert.deepStrictEqual(await pc.next((m) => m.type === 'berth_granted'), { type: 'berth_granted', base: 'aster', berth: 0 });
    pc.send({ type: 'sell_to_builder', builder: 'Akane', item: 'ice', qty: 5 });
    await pc.next((m) => m.type === 'state' && m.state.pilots['Pilot A']?.credits === 90);
    phone.send({ type: 'land_request', base: 'aster' });
    assert.strictEqual((await phone.next((m) => m.type === 'error')).reason, 'only pilots land at a Star Port');
    pc.send({ type: 'set_bid', item: 'ice', price: 1, want: 1 });
    assert.strictEqual((await pc.next((m) => m.type === 'error')).reason, 'only Builders run a Star Port');
    phone.close();
    pc.close();
  } finally {
    await server.close();
  }
});
