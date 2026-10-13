// Plays the prototype's "done when" loop end to end: a builder and two pilots over real WebSockets.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const { startServer } = require('../server');

function connect(port) {
  return new Promise((resolve, reject) => {
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
    ws.on('error', reject);
  });
}

const isState = (pred) => (m) => m.type === 'state' && pred(m.state);

test('builder and two pilots complete the ice job', async () => {
  const port = 18080;
  const server = startServer({ port, tickMs: 60000 });
  try {
    const phone = await connect(port);
    const pc1 = await connect(port);
    const pc2 = await connect(port);
    phone.send({ type: 'hello', role: 'builder', name: 'Akane' });
    pc1.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    pc2.send({ type: 'hello', role: 'explorer', name: 'Pilot B' });
    await phone.next((m) => m.type === 'welcome');
    await pc1.next((m) => m.type === 'welcome');
    await pc2.next((m) => m.type === 'welcome');

    // Posting a job before a Spaceport exists is refused.
    phone.send({ type: 'post_job', resource: 'ice', amount: 10, reward: 100 });
    assert.match((await phone.next((m) => m.type === 'error')).reason, /Spaceport/);

    // Phone builds a Spaceport; both PCs see it appear.
    phone.send({ type: 'build', planet: 'aster', slot: 0, building: 'spaceport' });
    const hasPort = (s) => s.system.planets[0].buildings.some((b) => b.type === 'spaceport');
    await pc1.next(isState(hasPort));
    await pc2.next(isState(hasPort));

    // Phone posts the ice job; pilots see it.
    phone.send({ type: 'post_job', resource: 'ice', amount: 10, reward: 100 });
    await pc1.next(isState((s) => s.jobs.length === 1));

    // Pilots see each other's ships.
    pc1.send({ type: 'ship', pos: [1, 2, 3], rot: [0, 0, 0] });
    const ship = await pc2.next((m) => m.type === 'ship');
    assert.deepStrictEqual(ship.pos, [1, 2, 3]);
    assert.strictEqual(ship.name, 'Pilot A');

    // Pilot A mines 6 ice, Pilot B mines 4, both deliver.
    for (let i = 0; i < 2; i++) pc1.send({ type: 'collect', resource: 'ice', amount: 3 });
    for (let i = 0; i < 2; i++) pc2.send({ type: 'collect', resource: 'ice', amount: 2 });
    await pc2.next(isState((s) => s.pilots['Pilot B']?.cargo.ice === 4));
    pc1.send({ type: 'deliver', job: 1 });
    await phone.next(isState((s) => s.jobs[0]?.delivered === 6));
    pc2.send({ type: 'deliver', job: 1 });

    // Phone sees the job complete, ice in stock, and Hydroponics unlocked.
    const done = await phone.next(isState((s) => s.jobs[0]?.status === 'done'));
    assert.strictEqual(done.state.stock.ice, 10);
    assert.ok(done.state.unlocked.includes('hydroponics'));
    assert.strictEqual(done.state.pilots['Pilot A'].credits, 60);
    assert.strictEqual(done.state.pilots['Pilot B'].credits, 40);

    for (const c of [phone, pc1, pc2]) c.close();
  } finally {
    await server.close();
  }
});
