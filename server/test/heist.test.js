// Raid rules: the site and its levels, the breach, loot, inventory, Heat, reinforcements, the
// self-destruct and extraction, plus full raids over WebSockets.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const H = require('../heist');
const G = require('../galaxy');
const { startServer } = require('../server');

test('every level connects, the lifts line up, and the safe room is locked on the deepest', () => {
  for (const tier of [1, 2, 3])
    for (let floors = 1; floors <= H.MAX_FLOORS; floors++)
      for (let seed = 1; seed <= 300; seed++) {
        const L = H.generateLayout(seed, tier, 'refinery', { floors });
        const at = (id) => L.rooms.find((r) => r.id === id);
        assert.strictEqual(L.floors.length, floors);
        assert.deepStrictEqual(at(L.floors[0].entrance).pos, [0, 0], 'level 1 lift is under the core');
        for (const fl of L.floors) {
          const own = L.rooms.filter((r) => r.floor === fl.n);
          const adj = (n) => L.doors.filter((d) => !d.locked && (d.a === n || d.b === n)).map((d) => (d.a === n ? d.b : d.a));
          const seen = new Set([fl.entrance]);
          const queue = [fl.entrance];
          while (queue.length) for (const n of adj(queue.shift())) if (!seen.has(n)) seen.add(n) && queue.push(n);
          const last = fl.n === floors;
          assert.strictEqual(seen.size, own.length - (last ? 1 : 0), `tier ${tier} floors ${floors} seed ${seed} level ${fl.n}`);
          assert.ok([...seen].every((id) => at(id).floor === fl.n), 'doors stay on their level');
          if (last) assert.ok(fl.safe === L.vault && !seen.has(L.vault), 'safe room locked');
          else assert.deepStrictEqual(at(L.floors[fl.n].entrance).pos, at(fl.down).pos, 'lift down lands under itself');
        }
        assert.ok(!L.containers.some((c) => c.type === 'vault' && c.room !== L.vault));
        assert.ok(L.guards.every((g) => g.route.every((id) => at(id).floor === g.floor)));
        assert.deepStrictEqual(L.extracts.map((e) => e.kind), ['ship']);
      }
});

test('the raid map mirrors the Builder\'s site', () => {
  const site = {
    kind: 'satellite',
    grid: 12,
    pieces: [
      { id: 1, type: 'turret', x: 0, y: 0 },
      { id: 2, type: 'power', x: 10, y: 10 },
      { id: 3, type: 'wall', x: 5, y: 2 },
      { id: 4, type: 'guardpost', x: 0, y: 10, readyAt: 5000 }, // still being built
    ],
    obstacles: [{ id: 5, type: 'boulder', x: 2, y: 4 }],
  };
  const L = H.generateLayout(7, 1, 'lab', { site, now: 1000 });
  assert.deepStrictEqual(L.pieces.map((p) => p.id), ['p1', 'p2', 'p3', 'o5']);
  const turret = L.pieces[0];
  assert.deepStrictEqual(turret.pos, [-20, -20], 'top-left 2x2 tile, in metres round the core');
  assert.deepStrictEqual(turret.size, [8, 8]);
  assert.strictEqual(L.powered, 'plant');
  assert.strictEqual(H.generateLayout(7, 1, 'lab', { site: { ...site, pieces: [] }, now: 1000 }).powered, 'core');
  // A facility without a site gets a power plant and defences from its tier.
  const d = H.generateLayout(7, 3, 'lab');
  assert.strictEqual(d.pieces.filter((p) => p.type === 'power').length, 1);
  assert.strictEqual(d.pieces.filter((p) => p.type === 'turret').length, 3);
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
function setup(vault = { alloy: 10, drive: 2 }, { security = 1, inside = true } = {}) {
  const g = G.newGalaxy();
  g.stock.metal = 999;
  assert.ok(G.build(g, 'aster', 0, 'refinery').ok);
  const fac = G.facility(g, 'aster', 0);
  fac.vault = { ...vault };
  fac.security = security;
  const r = G.startRaid(g, 'Pilot A', 'aster', 0, 0, 1234, 99);
  assert.ok(r.ok, r.reason);
  if (inside) {
    H.ventStart(r.run, 'v0', 0);
    assert.ok(H.ventFinish(r.run, 6000).ok);
  }
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
  assert.match(H.useKeycard(run, 0).reason, /keycard/);
  H.drillStart(run, 1000);
  assert.match(H.drillFinish(run, 20_000).reason, /not through/);
  assert.ok(H.drillFinish(run, 31_000).ok);
  assert.ok(run.heat >= 10, `drilling is loud: Heat ${run.heat}`);
  assert.ok(H.openContainer(run, vaultBox, 31_000).ok);
  assert.strictEqual(run.selfDestructAt, 31_000 + H.selfDestructSeconds(1) * 1000, 'opening the vault starts the self-destruct');
});

test('breach: the blast door opens only when the power plant is down; vents take time', () => {
  const { run } = setup({}, { inside: false });
  const cid = run.layout.containers[0].id;
  assert.match(H.openContainer(run, cid, 0).reason, /inside/);
  assert.match(H.enterDoor(run, 0).reason, /power plant/);
  const turret = run.layout.pieces.find((p) => p.type === 'turret' || p.type === 'guardpost');
  assert.ok(H.destroy(run, turret.id, 0).changed);
  assert.ok(!H.destroy(run, turret.id, 0).changed, 'only counts once');
  assert.strictEqual(run.heat, 5, 'explosions are loud');
  const wall = run.layout.pieces.find((p) => p.type === 'wall');
  assert.match(H.destroy(run, wall.id, 0).reason, /can't/);
  const power = run.layout.pieces.find((p) => p.type === 'power');
  assert.ok(H.destroy(run, power.id, 0).doorOpened);
  assert.ok(H.enterDoor(run, 1000).ok);
  assert.strictEqual(H.stage(run, 1000).stage, 'loot');

  const quiet = setup({}, { inside: false }).run;
  H.ventStart(quiet, 'v1', 0);
  assert.match(H.ventFinish(quiet, 3000).reason, /not cut/);
  assert.ok(H.ventFinish(quiet, 6000).ok);
  assert.strictEqual(quiet.breached, 'vent');
  assert.strictEqual(quiet.heat, 0, 'a vent is silent');
});

test('every minute inside brings a bigger wave', () => {
  const { run } = setup(); // inside at 6 s
  assert.strictEqual(H.waveTick(run, 60_000), null);
  assert.deepStrictEqual(H.waveTick(run, 66_000), { wave: 1, count: 1 });
  assert.strictEqual(H.waveTick(run, 70_000), null, 'once per minute');
  assert.deepStrictEqual(H.waveTick(run, 126_000), { wave: 2, count: 2 });
  run.selfDestructAt = 999_999;
  assert.deepStrictEqual(H.waveTick(run, 10 * 60_000), { wave: 9, count: 7 }, 'capped, plus two in the self-destruct');
});

test('each level of the facility adds a level of better loot below', () => {
  const { run } = setup({}, { security: 3 });
  assert.strictEqual(run.floors, 3);
  assert.strictEqual(run.layout.rooms.filter((r) => r.floor === 3).length, 16);
  const key = run.layout.containers.find((c) => run.boxes[c.id].items.some((it) => it.item === 'keycard'));
  assert.strictEqual(key.floor, 3, 'the keycard is on the deepest level');
  assert.ok(H.reachFloor(run, 2).ok);
  assert.match(H.reachFloor(run, 4).reason, /level/);
  assert.strictEqual(H.selfDestructSeconds(3), 150);
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
});

test('boarding the ship needs the full countdown, before the self-destruct ends', () => {
  const { run } = setup();
  assert.ok(H.extractStart(run, 'ship', 0).ok);
  assert.match(H.extractFinish(run, 1000).reason, /countdown/);
  assert.ok(H.extractFinish(run, 3000).ok);
  run.selfDestructAt = 2000;
  assert.match(H.extractFinish(run, 3000).reason, /too late/);
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
  H.extractStart(run, 'ship', 300_000);
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
  assert.deepStrictEqual(H.finish(run, 'destroyed', 70_000).kept.map((k) => k.item), ['drive'], 'same when the self-destruct gets you');
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
    assert.strictEqual(begin.run.stage, 'breach');
    await phone.next((m) => m.type === 'state' && m.state.raids.length === 1);

    // Stage 1: knock out the power plant and walk in through the blast door.
    pc.send({ type: 'raid_enter' });
    await pc.next((m) => m.type === 'error' && /sealed/.test(m.reason));
    const power = begin.run.layout.pieces.find((p) => p.type === 'power');
    pc.send({ type: 'raid_destroy', piece: power.id });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.doorOpen);
    pc.send({ type: 'raid_enter' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.stage === 'loot');
    clock += 61_000;
    const wave = await pc.next((m) => m.type === 'raid' && m.ev === 'wave');
    assert.strictEqual(wave.count, 1);

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
    const opened = await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.vaultOpen);
    assert.strictEqual(opened.stage, 'escape');
    assert.ok(opened.selfDestruct > 60_000, 'the self-destruct is counting down');
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

    clock += 10_000;
    pc.send({ type: 'raid_extract_start', extract: 'ship' });
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

    server.galaxy.stock.metal = 100;
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
    clock += 17 * 60_000;
    const end = await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.strictEqual(end.result.outcome, 'mia');
    pc.close();
  } finally {
    await server.close();
  }
});

test('the self-destruct kills a raider still inside when it ends', async () => {
  const port = 18092;
  let clock = 0;
  const server = startServer({ port, tickMs: 60000, now: () => clock });
  try {
    const pc = await connect(port);
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await pc.next((m) => m.type === 'welcome');
    server.galaxy.stock.metal = 999;
    server.galaxy.stock.ice = 99;
    assert.ok(G.build(server.galaxy, 'aster', 0, 'lab').ok);
    pc.send({ type: 'raid_start', planet: 'aster', slot: 0 });
    await pc.next((m) => m.type === 'raid' && m.ev === 'begin');
    pc.send({ type: 'raid_vent_start', vent: 'v2' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'vent');
    clock += 6000;
    pc.send({ type: 'raid_vent_finish' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.breached === 'vent');
    pc.send({ type: 'raid_drill_start' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'drill');
    clock += 30_000;
    pc.send({ type: 'raid_drill_finish' });
    const open = await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.vaultOpen);
    clock += open.selfDestruct;
    const end = await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.strictEqual(end.result.outcome, 'destroyed');
    assert.match(server.galaxy.feed.at(-1).text, /self-destruct/);
    pc.close();
  } finally {
    await server.close();
  }
});
