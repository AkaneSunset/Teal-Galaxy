// Raid rules: layouts, loot, inventory, Heat and extraction, plus a full raid over WebSockets.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const H = require('../heist');
const G = require('../galaxy');
const { startServer } = require('../server');

test('every layout keeps the vault behind its lock and everything else reachable', () => {
  for (const tier of [1, 2, 3]) {
    for (let seed = 1; seed <= 1000; seed++) {
      const L = H.generateLayout(seed, tier, 'refinery');
      const adj = (n) => L.doors.filter((d) => !d.locked && (d.a === n || d.b === n)).map((d) => (d.a === n ? d.b : d.a));
      const seen = new Set([L.entrance]);
      const queue = [L.entrance];
      while (queue.length) for (const n of adj(queue.shift())) if (!seen.has(n)) seen.add(n) && queue.push(n);
      assert.strictEqual(seen.size, L.rooms.length - 1, `tier ${tier} seed ${seed}: all but the vault reachable`);
      assert.ok(!seen.has(L.vault), 'vault is locked');
      assert.ok(L.doors.some((d) => d.locked), 'vault has a door');
      assert.strictEqual(L.guards.length, H.SECURITY[tier].guards);
      assert.ok(L.extracts.some((e) => e.kind === 'shuttle') && L.extracts.some((e) => e.kind === 'lift'));
      assert.ok(!L.containers.some((c) => c.type === 'vault' && c.room !== L.vault));
    }
  }
});

test('the same seed builds the same facility', () => {
  assert.deepStrictEqual(H.generateLayout(42, 2, 'lab'), H.generateLayout(42, 2, 'lab'));
});

test('rarer loot shows up more at higher security', () => {
  const r = H.rng(9);
  const rareShare = (tier) => {
    let rare = 0;
    let all = 0;
    for (let i = 0; i < 20000; i++)
      for (const s of H.rollTable({ rolls: [1, 1], none: 0, entries: [['scrap', 10, 1, 1], ['exotic', 1, 1, 1]] }, tier, 'plan', r)) {
        all++;
        if (s.item === 'exotic') rare++;
      }
    return rare / all;
  };
  assert.ok(rareShare(3) > rareShare(1) * 1.5);
});

test('inventory grid places, rotates and refuses overlaps', () => {
  const g = new H.Grid(3, 2);
  assert.deepStrictEqual(g.findFree([1, 3]), { x: 0, y: 0, w: 3, h: 1 }); // only fits rotated
  assert.ok(g.place('a', { x: 0, y: 0, w: 2, h: 2 }));
  assert.ok(!g.place('b', { x: 1, y: 0, w: 2, h: 1 }));
  assert.deepStrictEqual(g.findFree([1, 2]), { x: 2, y: 0, w: 1, h: 2 });
  g.remove('a');
  assert.ok(g.place('b', { x: 1, y: 0, w: 2, h: 1 }));
});

// A facility with a known vault, and a run on it at a fixed time.
function setup(vault = { alloy: 10, drive: 2 }) {
  const g = G.newGalaxy();
  g.stock.metal = 999;
  assert.ok(G.build(g, 'aster', 0, 'refinery').ok);
  const fac = G.facility(g, 'aster', 0);
  fac.vault = { ...vault };
  const r = G.startRaid(g, 'Pilot A', 'aster', 0, 0, 1234, 99);
  assert.ok(r.ok, r.reason);
  return { g, fac, run: r.run };
}

function boxWith(run, item) {
  return Object.entries(run.boxes).find(([, b]) => b.items.some((it) => it.item === item))[0];
}

test('containers reveal over time and nothing can be taken early', () => {
  const { run } = setup();
  const cid = boxWith(run, 'keycard');
  assert.ok(H.openContainer(run, cid, 0).ok);
  const card = run.boxes[cid].items.find((it) => it.item === 'keycard');
  assert.match(H.take(run, card.uid, 'backpack', 0).reason, /searching/);
  const view = H.containerView(run, 0);
  assert.ok(view.slots.every((s) => !s.item), 'only placeholders at first');
  assert.ok(H.take(run, card.uid, 'secure', 60_000).ok);
  assert.strictEqual(H.inventoryView(run)[0].grid, 'secure');
});

test('the vault is locked until a keycard or the drill opens it', () => {
  const { run } = setup();
  const vaultBox = run.layout.containers.find((c) => c.type === 'vault').id;
  assert.match(H.openContainer(run, vaultBox, 0).reason, /locked/);
  assert.match(H.useKeycard(run).reason, /keycard/);
  H.drillStart(run, 1000);
  assert.match(H.drillFinish(run, 20_000).reason, /not through/);
  assert.ok(H.drillFinish(run, 31_000).ok);
  assert.ok(run.heat >= 10, `drilling is loud: Heat ${run.heat}`);
  assert.ok(H.openContainer(run, vaultBox, 31_000).ok);
});

test('Heat rises with time and reported noise, rate-limited per kind', () => {
  const { run } = setup();
  H.report(run, 'gunshot', 0);
  H.report(run, 'gunshot', 100); // too soon: ignored
  H.report(run, 'spotted', 200);
  assert.strictEqual(run.heat, 13);
  H.heatTick(run, 60_000);
  assert.strictEqual(run.heat, 15);
  H.addHeat(run, 50);
  assert.strictEqual(H.HEAT_LEVELS[H.heatLevel(run.heat)].name, 'Lockdown');
  assert.strictEqual(H.extractStates(run, 4 * 60_000).pod.open, false, 'Lockdown seals the Escape Pod');
  H.addHeat(run, 20);
  assert.strictEqual(H.extractStates(run, 4 * 60_000).shuttle.countdown, 40, 'Purge doubles extract timers');
});

test('extraction needs the full countdown, and the lift eats a keycard', () => {
  const { run } = setup();
  assert.match(H.extractStart(run, 'lift', 0).reason, /keycard/);
  assert.ok(H.extractStart(run, 'shuttle', 0).ok);
  assert.match(H.extractFinish(run, 10_000).reason, /countdown/);
  assert.ok(H.extractFinish(run, 20_000).ok);
});

test('the Builder loses only what a raider carries out; the rest goes back in the vault', () => {
  const { g, fac, run } = setup({ alloy: 10, drive: 2 });
  assert.deepStrictEqual(fac.escrow, { alloy: 6, drive: 2 }, '60% of each stack is exposed');
  assert.deepStrictEqual(fac.vault, { alloy: 4, drive: 0 });
  run.vaultOpen = true;
  const box = run.layout.containers.find((c) => c.type === 'vault' && run.boxes[c.id].items.some((it) => it.item === 'drive')).id;
  H.openContainer(run, box, 0);
  const drive = run.boxes[box].items.find((it) => it.item === 'drive');
  assert.ok(H.take(run, drive.uid, 'backpack', 60_000).ok);
  H.extractStart(run, 'shuttle', 300_000);
  assert.ok(H.extractFinish(run, 320_000).ok);
  const result = G.endRaid(g, run, 'extracted', 320_000);
  assert.deepStrictEqual(result.stolen, { drive: 1 });
  assert.deepStrictEqual(fac.vault, { alloy: 10, drive: 1 });
  assert.deepStrictEqual(g.pilots['Pilot A'].stash, [{ item: 'drive', qty: 1, fih: true }]);
  assert.ok(fac.cooldownUntil > 320_000, 'facility recovers before the next raid');
  assert.match(G.startRaid(g, 'Pilot B', 'aster', 0, 330_000, 1, 1).reason, /alert/);
});

test('dying keeps only the Secure Case', () => {
  const { g, run } = setup({ drive: 2 });
  run.vaultOpen = true;
  const box = run.layout.containers.find((c) => c.type === 'vault' && run.boxes[c.id].items.some((it) => it.item === 'drive')).id;
  H.openContainer(run, box, 0);
  const [d1, d2] = run.boxes[box].items.filter((it) => it.item === 'drive');
  H.take(run, d1.uid, 'secure', 60_000);
  if (d2) H.take(run, d2.uid, 'backpack', 60_000);
  const result = G.endRaid(g, run, 'killed', 70_000);
  assert.deepStrictEqual(result.kept.map((k) => k.item), ['drive']);
  assert.strictEqual(result.kept[0].fih, false);
});

test('blueprint cases are too big to protect', () => {
  const { run } = setup({ blueprint: 1 });
  run.vaultOpen = true;
  const box = boxWith(run, 'blueprint');
  H.openContainer(run, box, 0);
  const bp = run.boxes[box].items.find((it) => it.item === 'blueprint');
  assert.match(H.take(run, bp.uid, 'secure', 60_000).reason, /Secure Case/);
  assert.ok(H.take(run, bp.uid, 'backpack', 60_000).ok);
});

test('facilities fill their vaults, ship to HQ and buy security', () => {
  const g = G.newGalaxy();
  g.stock.metal = 999;
  g.credits = 5000;
  G.build(g, 'aster', 1, 'refinery');
  for (let i = 0; i < 15; i++) G.tick(g);
  const fac = G.facility(g, 'aster', 1);
  assert.deepStrictEqual(fac.vault, { alloy: 15, isotope: 2 });
  assert.ok(G.ship(g, 'aster', 1, 0).ok);
  assert.strictEqual(g.stock.alloy, 15);
  assert.match(G.ship(g, 'aster', 1, 1000).reason, /freighter/);
  assert.match(G.secure(g, 'aster', 1).reason, /Design drive/);
  g.stock.drive = 1;
  assert.ok(G.secure(g, 'aster', 1).ok);
  assert.strictEqual(fac.security, 2);
});

// --- Over the wire ---------------------------------------------------------------------------

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

test('a raid over the wire: board, search, steal from the vault, alarm, extract', async () => {
  const port = 18090;
  let clock = 1_000_000;
  const server = startServer({ port, tickMs: 60000, now: () => clock });
  try {
    const phone = await connect(port);
    const pc = await connect(port);
    phone.send({ type: 'hello', role: 'builder', name: 'Akane' });
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await phone.next((m) => m.type === 'welcome');
    await pc.next((m) => m.type === 'welcome');

    phone.send({ type: 'build', planet: 'aster', slot: 2, building: 'refinery' });
    await phone.next((m) => m.type === 'state' && m.state.system.planets[0].buildings.length === 1);
    server.galaxy.system.planets[0].buildings[0].vault = { isotope: 5 };

    pc.send({ type: 'raid_start', planet: 'aster', slot: 2 });
    const begin = await pc.next((m) => m.type === 'raid' && m.ev === 'begin');
    assert.ok(begin.run.layout.rooms.length >= 9);
    assert.ok(!JSON.stringify(begin).includes('"isotope"'), 'no container contents in the briefing');
    await phone.next((m) => m.type === 'state' && m.state.raids.length === 1);

    // Find the keycard the way a player would: open containers until one shows it.
    const run = server.runs.get('Pilot A');
    const cid = Object.entries(run.boxes).find(([, b]) => b.items.some((it) => it.item === 'keycard'))[0];
    pc.send({ type: 'raid_open', container: cid });
    const view = await pc.next((m) => m.type === 'raid' && m.ev === 'container');
    assert.ok(view.slots.every((s) => !s.item), 'placeholders only');
    clock += 30_000;
    const card = await pc.next((m) => m.type === 'raid' && m.ev === 'reveal' && m.item.item === 'keycard');
    pc.send({ type: 'raid_take', uid: card.item.uid, to: 'backpack' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'inventory' && m.items.length === 1);

    pc.send({ type: 'raid_keycard' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.vaultOpen);
    const vault = run.layout.containers.find((c) => c.type === 'vault' && run.boxes[c.id].items.some((it) => it.item === 'isotope')).id;
    pc.send({ type: 'raid_open', container: vault });
    await pc.next((m) => m.type === 'raid' && m.ev === 'container' && m.container === vault);
    clock += 30_000;
    const iso = await pc.next((m) => m.type === 'raid' && m.ev === 'reveal' && m.item.item === 'isotope');
    pc.send({ type: 'raid_take', uid: iso.item.uid, to: 'backpack' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'inventory' && m.items.length === 2);

    // The Builder hears about it and sounds the alarm from the phone.
    phone.send({ type: 'sound_alarm', planet: 'aster', slot: 2 });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.heat >= 25);
    await phone.next((m) => m.type === 'state' && m.state.raids[0]?.heat >= 25);

    clock += 4 * 60_000;
    pc.send({ type: 'raid_extract_start', extract: 'shuttle' });
    const ex = await pc.next((m) => m.type === 'raid' && m.ev === 'extracting');
    clock += ex.countdown * 1000;
    pc.send({ type: 'raid_extract_finish' });
    const end = await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.strictEqual(end.result.outcome, 'extracted');
    assert.ok(end.result.kept.some((k) => k.item === 'isotope'));

    const after = await phone.next((m) => m.type === 'state' && m.state.raids.length === 0);
    const fac = after.state.system.planets[0].buildings[0];
    assert.ok(fac.vault.isotope < 5, 'the Builder lost what was carried out');
    assert.strictEqual(after.state.raidLog[0].outcome, 'extracted');

    server.galaxy.bases.Akane.stock.metal = 100;
    phone.send({ type: 'build', planet: 'aster', slot: 0, building: 'spaceport' });
    await pc.next((m) => m.type === 'state' && m.state.system.planets[0].buildings.length === 2);
    pc.send({ type: 'sell' });
    const sold = await pc.next((m) => m.type === 'state' && m.state.pilots['Pilot A']?.credits > 0);
    assert.strictEqual(sold.state.pilots['Pilot A'].stash.length, 0);

    for (const c of [phone, pc]) c.close();
  } finally {
    await server.close();
  }
});

test('the run clock ends a raid as missing in action', async () => {
  const port = 18091;
  let clock = 0;
  const server = startServer({ port, tickMs: 60000, now: () => clock });
  try {
    const pc = await connect(port);
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await pc.next((m) => m.type === 'welcome');
    server.galaxy.stock.metal = 999;
    G.build(server.galaxy, 'aster', 0, 'spire');
    pc.send({ type: 'raid_start', planet: 'aster', slot: 0 });
    await pc.next((m) => m.type === 'raid' && m.ev === 'begin');
    clock += 13 * 60_000;
    const end = await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.strictEqual(end.result.outcome, 'mia');
    pc.close();
  } finally {
    await server.close();
  }
});
