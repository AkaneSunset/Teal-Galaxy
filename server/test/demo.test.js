// The demo war (DEMO=1): every faction at 25% of every contested system, no footholds needed,
// five-minute locks, and a fleet carrier for every pilot.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const G = require('../galaxy');
const W = require('../war');
const { startServer } = require('../server');

function war(...factions) {
  const g = G.newGalaxy();
  for (const f of factions) {
    G.claimBase(g, f);
    assert.ok(G.chooseFaction(g, 'builder', f, f).ok);
  }
  return g;
}

// Runs `fn` with the demo war on, and turns it off again whatever happens.
function demo(fn) {
  W.setDemo(true);
  try {
    return fn();
  } finally {
    W.setDemo(false);
  }
}

test('the demo war floors every faction at 25% of every contested system', () => {
  const g = war('compact', 'ashen');
  assert.strictEqual(W.shares(g, 'teal-prime').ashen, 0, 'off: no fleets, no share');
  demo(() => {
    assert.ok(W.isDemo());
    W.recompute(g, 0);
    assert.deepStrictEqual(g.war.orbital['teal-prime'], { compact: 0.25, ashen: 0.25, luminar: 0.25, coma: 0.25 });
    assert.deepStrictEqual(g.war.orbital.marrow, { compact: 0.25, ashen: 0.25, luminar: 0.25, coma: 0.25 });
    assert.deepStrictEqual(g.war.orbital.fortitude, { compact: 0, ashen: 0, luminar: 0, coma: 0 }, 'capital systems are left alone');
    // A real share above the floor shows as it is.
    g.bases.ashen.navy.frigate = 2;
    const r = W.sendFleet(g, 'ashen', 'teal-prime', null, 0);
    W.warTick(g, r.fleet.arriveAt);
    assert.strictEqual(W.shares(g, 'teal-prime').ashen, 1);
    assert.strictEqual(W.shares(g, 'teal-prime').compact, 0.25);
  });
  W.recompute(g, 0);
  assert.strictEqual(g.war.orbital['teal-prime'].compact, 0, 'off again');
});

test('the demo war waives footholds and the 25% rule, but not capitals', () => {
  const g = war('compact', 'luminar');
  assert.match(W.canAttack(g, 'luminar', 'scar', 0).reason, /no foothold near Scar/);
  assert.match(W.canAttack(g, 'luminar', 'cinder', 0).reason, /25% orbital control/);
  demo(() => {
    assert.ok(W.canAttack(g, 'luminar', 'scar', 0).ok, 'Marrow Reach, two lanes from home');
    assert.ok(W.canAttack(g, 'luminar', 'cinder', 0).ok);
    assert.ok(W.canAttack(g, 'coma', 'eddy', 0).ok);
    assert.strictEqual(W.canAttack(g, 'luminar', 'bastion', 0).reason, "capital worlds can't be attacked");
  });
});

test('a planet taken in the demo war locks for five minutes', () => {
  const g = war('compact', 'ashen');
  demo(() => {
    const wp = W.planet(g, 'cinder');
    const t = 1_000_000;
    const order = [wp.sectors.find((s) => s.capital).id];
    for (let i = 0; i < order.length; i++) for (const id of wp.sectors.find((s) => s.id === order[i]).links) if (!order.includes(id)) order.push(id);
    for (const id of order) {
      if (wp.owner === 'ashen') break;
      assert.ok(W.capture(g, 'cinder', id, 'ashen', t).ok);
    }
    assert.strictEqual(wp.owner, 'ashen');
    assert.strictEqual(W.lockMs(), 5 * 60_000);
    assert.strictEqual(wp.lockedUntil, t + 5 * 60_000);
    assert.match(g.war.log.at(-1).text, /Cinder fell to the Ashen Collective: it is locked for 5 minutes/);
    const free = wp.sectors.find((s) => s.owner === 'ashen').id;
    assert.strictEqual(W.capture(g, 'cinder', free, 'compact', t + 60_000).reason, 'Cinder is locked for 4 more minutes');
    assert.ok(W.canAttack(g, 'compact', 'cinder', t + 5 * 60_000).ok, 'and open again after');
  });
  assert.strictEqual(W.lockMs(), W.LOCK_MS);
});

test('the welcome says whether the demo war is on: carriers for everyone', async () => {
  const hello = async (port) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    await new Promise((res) => ws.on('open', res));
    const welcome = new Promise((res) => ws.on('message', (d) => JSON.parse(d).type === 'welcome' && res(JSON.parse(d))));
    ws.send(JSON.stringify({ type: 'hello', role: 'explorer', name: 'Akane' }));
    const w = await welcome;
    ws.close();
    return w;
  };
  let server = startServer({ port: 9150, tickMs: 60000, demo: true, demoWar: true });
  try {
    const w = await hello(9150);
    assert.strictEqual(w.catalog.demo, true);
    assert.strictEqual(w.catalog.carrier, true);
    assert.strictEqual(w.catalog.war.lockMs, 5 * 60_000);
    assert.strictEqual(w.state.war.orbital['teal-prime'].ashen, 0.25);
    assert.deepStrictEqual(w.state.battles, []);
  } finally {
    await server.close();
  }
  server = startServer({ port: 9151, tickMs: 60000, demoWar: false });
  try {
    const w = await hello(9151);
    assert.strictEqual(w.catalog.demo, false);
    assert.strictEqual(w.catalog.carrier, false);
    assert.strictEqual(w.catalog.war.lockMs, W.LOCK_MS);
  } finally {
    await server.close();
  }
});

test('a fleet carrier jumps from its galaxy map to any system or planet, and only a fleet carrier', async () => {
  // An app's connection: every message kept, waited for by type.
  const connect = async (port, name) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    const inbox = [];
    ws.on('message', (d) => inbox.push(JSON.parse(d)));
    await new Promise((res) => ws.on('open', res));
    ws.send(JSON.stringify({ type: 'hello', role: 'explorer', name }));
    const next = async (pred) => {
      for (let i = 0; i < 200; i++) {
        const k = inbox.findIndex(pred);
        if (k >= 0) return inbox.splice(k, 1)[0];
        await new Promise((res) => setTimeout(res, 10));
      }
      throw new Error(`${name}: no such message`);
    };
    await next((m) => m.type === 'welcome');
    return { send: (m) => ws.send(JSON.stringify(m)), next, close: () => ws.close() };
  };
  let server = startServer({ port: 9152, tickMs: 60000, demoWar: true });
  try {
    const a = await connect(9152, 'Pilot A');
    const b = await connect(9152, 'Pilot B');
    a.send({ type: 'carrier_jump', planet: 'scar' });
    assert.match((await a.next((m) => m.type === 'error')).reason, /aboard your own fleet carrier/);
    a.send({ type: 'enter_space', space: 'ship:Pilot A', pos: [0, 0, 0], yaw: 0, anim: 'idle' });
    await a.next((m) => m.type === 'space_joined');
    a.send({ type: 'carrier_jump', planet: 'nowhere' });
    assert.match((await a.next((m) => m.type === 'error')).reason, /no such planet/);
    // Straight into Scar's orbit, in Marrow Reach, two lanes from home.
    a.send({ type: 'carrier_jump', planet: 'scar' });
    const note = await a.next((m) => m.type === 'carrier_jump');
    assert.deepStrictEqual([note.owner, note.system, note.planet, note.seconds], ['Pilot A', 'marrow', 'scar', 5]);
    a.send({ type: 'carrier_jump', system: 'drift' });
    assert.match((await a.next((m) => m.type === 'error')).reason, /already jumping/);
    // Out the far end, the others see which system the carrier is in.
    a.send({ type: 'ship', pos: [1, 2, 3], rot: [0, 0, 0], over: 'scar', system: 'marrow' });
    const seen = await b.next((m) => m.type === 'ship' && m.name === 'Pilot A');
    assert.deepStrictEqual([seen.system, seen.over], ['marrow', 'scar']);
    a.close();
    b.close();
  } finally {
    await server.close();
  }
  // Without the demo war's fleet carriers, no ship has the drive.
  server = startServer({ port: 9153, tickMs: 60000, demoWar: false });
  try {
    const a = await connect(9153, 'Pilot A');
    a.send({ type: 'carrier_jump', system: 'marrow' });
    assert.match((await a.next((m) => m.type === 'error')).reason, /only fleet carriers can jump/);
    a.close();
  } finally {
    await server.close();
    W.setDemo(false);
  }
});

test("each faction's players get their own faction's orders in the state, and not the others'", async () => {
  const server = startServer({ port: 9154, tickMs: 50, demoWar: true });
  try {
    const join = async (name, faction) => {
      const ws = new WebSocket('ws://localhost:9154');
      const inbox = [];
      ws.on('message', (d) => inbox.push(JSON.parse(d)));
      await new Promise((res) => ws.on('open', res));
      ws.send(JSON.stringify({ type: 'hello', role: 'explorer', name }));
      ws.send(JSON.stringify({ type: 'choose_faction', faction }));
      return { ws, inbox };
    };
    const a = await join('Ash', 'ashen');
    const c = await join('Cora', 'compact');
    const latest = async (who, faction) => {
      for (let i = 0; i < 100; i++) {
        const st = who.inbox.filter((m) => m.type === 'state').at(-1)?.state;
        const op = st?.war?.orders?.op;
        if (op && op.factions[faction]) return op;
        await new Promise((res) => setTimeout(res, 20));
      }
      throw new Error('no orders arrived');
    };
    const opA = await latest(a, 'ashen');
    const opC = await latest(c, 'compact');
    assert.deepStrictEqual(Object.keys(opA.factions), ['ashen']);
    assert.deepStrictEqual(Object.keys(opC.factions), ['compact']);
    a.ws.close();
    c.ws.close();
  } finally {
    await server.close();
    W.setDemo(false);
  }
});

