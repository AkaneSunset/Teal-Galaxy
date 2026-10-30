// Sector battles: who may start and join one, mass and drops, engineers, orders, combat, driving a
// unit, the defender AI, how a battle is won, and the whole thing over the wire.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const B = require('../battle');
const G = require('../galaxy');
const W = require('../war');
const { startServer } = require('../server');

const C = B.CATALOG;

// A galaxy with pilots of the given factions, named after them ('ashen', 'ashen2', ...).
function galaxy(...names) {
  const g = G.newGalaxy();
  for (const n of names) assert.ok(G.chooseFaction(g, 'explorer', n, n.replace(/\d+$/, '')).ok);
  return g;
}

// A battle over Cinder's sector `index` (Terran Compact's), attacked by the Ashen Collective, with
// the AI asleep unless `ai`. Pilot 'A' is in it on the attacking side.
function battle({ index = 3, ai = false, defender } = {}) {
  const g = G.newGalaxy();
  const wp = W.planet(g, 'cinder');
  const sector = wp.sectors[index];
  const b = B.newBattle({ wp, sector, attacker: 'ashen', defender: defender === undefined ? sector.owner : defender, now: 0 });
  if (!ai) b.aiAt = Infinity;
  B.addPilot(b, 'A', 'a', 'ashen');
  return b;
}

const units = (b, pred) => [...b.units.values()].filter(pred);
const run = (b, s) => B.step(b, s);

// Runs the manager's rules: fake connections, a fake clock, messages kept per connection.
function manager(g, clock = { t: 1_000_000 }) {
  const changes = [];
  const m = B.createBattles({ galaxy: () => g, now: () => clock.t, speed: 1, send: (c, msg) => c.inbox.push(msg), changed: () => changes.push(1) });
  let id = 1;
  const pilot = (name) => ({ id: id++, name, role: 'explorer', inbox: [] });
  return { m, pilot, changes, clock };
}

const over = (planet) => ({ over: planet, station: null });
const nowhere = { over: null, station: null };

test('starting a battle: the war rules, adjacency, and aboard a carrier over the planet', () => {
  const g = galaxy('ashen', 'ashen2', 'compact', 'luminar');
  const { m, pilot } = manager(g);
  try {
    const a = pilot('ashen');
    const wp = W.planet(g, 'cinder');
    assert.strictEqual(m.start(a, null, 'cinder', 'cinder-1', over('cinder')).reason, 'choose a faction first');
    assert.strictEqual(m.start(a, 'ashen', 'cinder', 'cinder-99', over('cinder')).reason, 'no such sector');
    assert.strictEqual(m.start(a, 'ashen', 'nowhere', 'x', over('cinder')).reason, 'no such planet');
    // The 25% rule, as for W.capture.
    assert.match(m.start(a, 'ashen', 'cinder', 'cinder-1', over('cinder')).reason, /25% orbital control of Teal Prime: you have 0%/);
    assert.strictEqual(m.start(a, 'ashen', 'bastion', 'bastion-1', over('bastion')).reason, "capital worlds can't be attacked");

    W.setDemo(true);
    W.recompute(g, 0);
    // A faction holding sectors there must attack next to one.
    const held = wp.sectors[0];
    held.owner = 'ashen';
    const far = wp.sectors.find((s) => s !== held && !held.links.includes(s.id) && !s.links.includes(held.id));
    assert.strictEqual(m.start(a, 'ashen', 'cinder', far.id, over('cinder')).reason, `${far.name} isn't next to a sector you hold`);
    assert.strictEqual(m.start(a, 'ashen', 'cinder', held.id, over('cinder')).reason, `the Ashen Collective already holds ${held.name}`);
    const next = wp.sectors.find((s) => s.id === held.links[0]);
    // Aboard a carrier over Cinder: not away from it, nor over another planet.
    assert.strictEqual(m.start(a, 'ashen', 'cinder', next.id, nowhere).reason, 'you need to be aboard a carrier over Cinder');
    assert.strictEqual(m.start(a, 'ashen', 'cinder', next.id, over('vesper')).reason, 'you need to be aboard a carrier over Cinder');
    const r = m.start(a, 'ashen', 'cinder', next.id, over('cinder'));
    assert.ok(r.ok, r.reason);
    const joined = a.inbox.find((x) => x.type === 'battle_joined');
    assert.strictEqual(joined.battle, r.battle);
    assert.deepStrictEqual(
      [joined.planet, joined.sector, joined.sectorName, joined.planetName, joined.size, joined.attacker, joined.defender, joined.side, joined.mass],
      ['cinder', next.id, next.name, 'Cinder', 1600, 'ashen', 'compact', 'a', 400]
    );
    assert.strictEqual(joined.seed, B.seedFor('cinder', next.id));
    assert.strictEqual(joined.lz.r, 120);
    assert.ok(joined.massPoints.length >= 10 && joined.massPoints.length <= 14);
    assert.strictEqual(joined.units, C);
    assert.match(g.war.log.at(-1).text, new RegExp(`Ashen Collective attacked ${next.name}, held by the Terran Compact`));
    assert.deepStrictEqual(m.list().map((x) => [x.id, x.attacker, x.defender, x.pilots.length]), [[r.battle, 'ashen', 'compact', 1]]);

    // Starting it again joins it: the attacker's faction as attacker, the defender's as defender
    // (from the planet's station too); anyone else is refused.
    const a2 = pilot('ashen2');
    assert.strictEqual(m.start(a2, 'ashen', 'cinder', next.id, over('cinder')).side, 'a');
    const d = pilot('compact');
    assert.match(m.start(d, 'compact', 'cinder', next.id, nowhere).reason, /at Cinder's station or aboard a carrier over it/);
    assert.strictEqual(m.start(d, 'compact', 'cinder', next.id, { over: null, station: 'cinder' }).side, 'd');
    assert.strictEqual(d.inbox.find((x) => x.type === 'battle_joined').side, 'd');
    assert.deepStrictEqual(d.inbox.find((x) => x.type === 'battle_joined').lz, joined.enemyLz, "the defender's landing zone is the base");
    const l = pilot('luminar');
    assert.strictEqual(m.start(l, 'luminar', 'cinder', next.id, over('cinder')).reason, 'a battle between the Ashen Collective and the Terran Compact is already on there');
    assert.strictEqual(m.join(l, 'luminar', r.battle, over('cinder')).reason, 'a battle between the Ashen Collective and the Terran Compact is already on there');
    assert.strictEqual(m.join(l, 'luminar', 'b999', over('cinder')).reason, 'no such battle');
  } finally {
    W.setDemo(false);
    m.close();
  }
});

test('joining: at most 32 pilots, and an unclaimed sector is held by a militia', () => {
  const g = galaxy('ashen', 'compact');
  const { m, pilot } = manager(g);
  W.setDemo(true);
  try {
    const first = pilot('ashen');
    const r = m.start(first, 'ashen', 'cinder', 'cinder-2', over('cinder'));
    for (let i = 2; i <= 32; i++) assert.ok(m.join(pilot(`Ash ${i}`), 'ashen', r.battle, over('cinder')).ok);
    assert.strictEqual(m.join(pilot('Ash 33'), 'ashen', r.battle, over('cinder')).reason, 'that battle is full: 32 pilots');
    assert.ok(m.join(first, 'ashen', r.battle, over('cinder')).ok, 'someone already in it may join again');
    m.leave(first);
    assert.ok(m.join(pilot('Ash 34'), 'ashen', r.battle, over('cinder')).ok, 'a place came free');

    // Marrow Reach's planets start unclaimed: a militia holds them, and nobody can fight on its side.
    const s = W.planet(g, 'scar').sectors[0];
    const militia = m.start(pilot('ashen'), 'ashen', 'scar', s.id, over('scar'));
    assert.ok(militia.ok, militia.reason);
    const b = m.battles.get(militia.battle);
    assert.strictEqual(b.defender, null);
    assert.strictEqual(b.ai.k, 0.6);
    assert.strictEqual(m.join(pilot('compact'), 'compact', militia.battle, over('scar')).reason, 'a battle between the Ashen Collective and the militia is already on there');
  } finally {
    W.setDemo(false);
    m.close();
  }
});

test('the map: deterministic from the seed, a landing zone and a base at opposite edges', () => {
  const a = B.layout(B.seedFor('cinder', 'cinder-4'), [{ name: 'Cinder 4 Fuel Depot' }]);
  const b = B.layout(B.seedFor('cinder', 'cinder-4'), [{ name: 'Cinder 4 Fuel Depot' }]);
  assert.deepStrictEqual(a, b);
  assert.notDeepStrictEqual(B.layout(B.seedFor('cinder', 'cinder-5')).massPoints, a.massPoints);
  for (const seed of [1, 2, 3, 42, 99999, B.seedFor('vesper', 'vesper-7')]) {
    const map = B.layout(seed);
    assert.ok(map.massPoints.length >= 10 && map.massPoints.length <= 14);
    for (const p of map.massPoints) {
      assert.ok(p.x > 0 && p.x < 1600 && p.z > 0 && p.z < 1600);
      for (const q of map.massPoints) if (p !== q) assert.ok(Math.hypot(p.x - q.x, p.z - q.z) >= 80, `seed ${seed}: points ${p.id} and ${q.id} too close`);
    }
    assert.ok(map.lz.z < 400 && map.node.z > 1200, 'opposite edges');
  }
  // The defender's base: the node, two turrets by it, extractors on the three points nearest it,
  // and the defender's outposts, named.
  const g = G.newGalaxy();
  const wp = W.planet(g, 'cinder');
  const bt = B.newBattle({ wp, sector: wp.sectors[3], attacker: 'ashen', defender: 'compact', outposts: [{ name: 'Cinder 4 Fuel Depot' }, { name: 'Cinder 4 Mine' }], now: 0 });
  const d = units(bt, (u) => u.side === 'd');
  assert.deepStrictEqual(d.map((u) => u.type).sort(), ['extractor', 'extractor', 'extractor', 'node', 'outpost', 'outpost', 'turret', 'turret']);
  const node = bt.units.get(bt.nodeId);
  const nearest = bt.massPoints.slice().sort((p, q) => Math.hypot(p.x - node.x, p.z - node.z) - Math.hypot(q.x - node.x, q.z - node.z)).slice(0, 3);
  assert.deepStrictEqual(d.filter((u) => u.type === 'extractor').map((u) => u.point).sort(), nearest.map((p) => p.id).sort());
  assert.deepStrictEqual(d.filter((u) => u.type === 'outpost').map((u) => u.name), ['Cinder 4 Fuel Depot', 'Cinder 4 Mine']);
  assert.deepStrictEqual(Object.values(B.joined((B.addPilot(bt, 'A', 'a', 'ashen'), bt), 'A').names), ['Cinder 4 Fuel Depot', 'Cinder 4 Mine']);
});

test('mass and drops: paid up front, landing by drop pod six seconds later, a cap of 120', () => {
  const b = battle();
  const p = b.pilots.get('A');
  assert.strictEqual(p.mass, 400);
  assert.deepStrictEqual(B.drop(b, 'A', 'tank', 4), { ok: false, reason: 'not enough mass: 4 Tanks cost 520 mass and 1300 energy' });
  assert.strictEqual(B.drop(b, 'A', 'node', 1).reason, 'no such unit');
  assert.strictEqual(B.drop(b, 'A', 'turret', 1).reason, 'no such unit', 'structures are built, not dropped');
  assert.strictEqual(B.drop(b, 'A', 'scout', 11).reason, 'drop 1 to 10 at a time');
  assert.strictEqual(B.drop(b, 'A', 'scout', 0).reason, 'drop 1 to 10 at a time');
  assert.strictEqual(B.drop(b, 'Nobody', 'scout', 1).reason, 'not in that battle');
  const r = B.drop(b, 'A', 'tank', 3);
  assert.ok(r.ok);
  assert.strictEqual(p.mass, 10);
  const pods = r.units.map((id) => b.units.get(id));
  assert.ok(pods.every((u) => u.state === 'drop' && Math.hypot(u.x - b.lz.x, u.z - b.lz.z) < 40), 'in a small ring on the landing zone');
  assert.deepStrictEqual(B.frame(b).units.filter((u) => r.units.includes(u[0])).map((u) => u[8]), ['drop', 'drop', 'drop']);
  run(b, 5.9);
  assert.ok(pods.every((u) => u.dropAt), 'still coming down');
  run(b, 0.2);
  assert.ok(pods.every((u) => !u.dropAt && u.state === 'idle'));
  // 2 mass a second from the carrier.
  assert.ok(Math.abs(p.mass - (10 + 2 * 6.1)) < 1e-6, String(p.mass));
  assert.strictEqual(B.income(b, 'A'), 2);
  // The cap: 120 units a pilot.
  [p.mass, p.energy] = [1e9, 1e9];
  for (let i = 0; i < 11; i++) assert.ok(B.drop(b, 'A', 'scout', 10).ok);
  assert.strictEqual(B.drop(b, 'A', 'scout', 8).reason, 'you can field 120 units');
  assert.ok(B.drop(b, 'A', 'scout', 7).ok);
  run(b, 1);
  assert.strictEqual(p.mass, 5000, 'mass caps at 5000');
  assert.strictEqual(p.energy, B.ENERGY_CAP, 'energy caps too');
});

test('engineers build extractors on free mass points, paying 15 mass a second each', () => {
  const b = battle();
  const p = b.pilots.get('A');
  const e1 = B.spawn(b, 'engineer', 'a', 'A', b.lz.x, b.lz.z);
  const e2 = B.spawn(b, 'engineer', 'a', 'A', b.lz.x + 5, b.lz.z);
  const point = b.massPoints.filter((m) => !units(b, (u) => u.point === m.id).length).sort((m, n) => Math.hypot(m.x - b.lz.x, m.z - b.lz.z) - Math.hypot(n.x - b.lz.x, n.z - b.lz.z))[0];
  assert.strictEqual(B.order(b, 'A', { units: [e1.id], order: 'build', structure: 'extractor', x: point.x + 20, z: point.z }).reason, 'extractors go on a free mass point');
  const taken = units(b, (u) => u.type === 'extractor')[0];
  assert.strictEqual(B.order(b, 'A', { units: [e1.id], order: 'build', structure: 'extractor', x: taken.x, z: taken.z }).reason, 'extractors go on a free mass point');
  assert.strictEqual(B.order(b, 'A', { units: [e1.id], order: 'build', structure: 'node', x: 800, z: 800 }).reason, 'engineers build extractors, generators, turrets and factories');
  assert.strictEqual(B.order(b, 'A', { units: [e1.id], order: 'build', structure: 'turret', x: taken.x + 3, z: taken.z }).reason, 'something is already built there');
  // Both engineers on one extractor (snapped onto the point from 5 m off).
  assert.ok(B.order(b, 'A', { units: [e1.id, e2.id], order: 'build', structure: 'extractor', x: point.x + 5, z: point.z }).ok);
  let site = null;
  for (let i = 0; i < 400 && !site; i++) {
    run(b, 0.1);
    site = units(b, (u) => u.type === 'extractor' && u.side === 'a')[0];
  }
  assert.ok(site, 'the engineers reached the point and started');
  assert.deepStrictEqual([site.x, site.z, site.point, site.built], [point.x, point.z, point.id, false]);
  const [massAt, paidAt] = [p.mass, site.paid];
  const frame = B.frame(b);
  assert.ok(frame.build.some(([id]) => id === site.id));
  // 60 mass at up to 30 a second (two engineers): two seconds or a little more, once both are there.
  let t = 0;
  while (!site.built && t < 10) {
    run(b, 0.1);
    t += 0.1;
  }
  assert.ok(site.built && t < 4.5, `built in ${t}`);
  assert.ok(Math.abs(massAt + 2 * t - (60 - paidAt) - p.mass) < 0.5, 'it cost 60');
  assert.strictEqual(B.income(b, 'A'), 5, '+3 a second from the extractor');
  assert.ok(B.frame(b).feed.includes('A built a Mass Extractor'));
  assert.strictEqual(B.order(b, 'A', { units: [e1.id], order: 'build', structure: 'extractor', x: point.x, z: point.z }).reason, 'extractors go on a free mass point', 'now it is taken');
  // With no mass in hand, building goes only as fast as the mass comes in (5 a second here).
  const e3 = B.spawn(b, 'engineer', 'a', 'A', b.lz.x, b.lz.z + 20);
  p.mass = 0;
  B.order(b, 'A', { units: [e3.id], order: 'build', structure: 'turret', x: b.lz.x, z: b.lz.z + 30 });
  run(b, 2);
  const turret = units(b, (u) => u.type === 'turret' && u.side === 'a')[0];
  assert.ok(turret && !turret.built && turret.paid <= 10 + 1e-6, String(turret?.paid));
});

test('factories make land units at 20 mass a second of their price, paying half of it', () => {
  const b = battle();
  const p = b.pilots.get('A');
  const f = B.spawn(b, 'factory', 'a', 'A', 800, 400);
  assert.strictEqual(B.produce(b, 'A', f.id, 'gunship', 1).reason, 'a factory makes land units only');
  assert.ok(B.produce(b, 'A', 9999, 'tank', 1).quiet, 'unknown ids, quietly');
  assert.ok(B.produce(b, 'A', f.id, 'scout', 2).ok);
  run(b, 1.3);
  assert.strictEqual(units(b, (u) => u.type === 'scout').length, 1, '25 mass at 20 a second');
  run(b, 1.3);
  assert.strictEqual(units(b, (u) => u.type === 'scout').length, 2);
  assert.ok(units(b, (u) => u.type === 'scout').every((u) => Math.hypot(u.x - f.x, u.z - f.z) < 40 && u.owner === 'A'));
  assert.strictEqual(f.queue.length, 0);
  assert.ok(Math.abs(p.mass - (400 + 2 * 2.6 - 25)) < 0.01, 'two scouts at half of 25 mass each');
});

test('orders: move, queued waypoints, stop, formations, and only your own units', () => {
  const b = battle();
  B.addPilot(b, 'Other', 'a', 'ashen');
  const s1 = B.spawn(b, 'scout', 'a', 'A', 400, 400);
  const s2 = B.spawn(b, 'scout', 'a', 'A', 410, 400);
  const theirs = B.spawn(b, 'scout', 'a', 'Other', 420, 400);
  B.order(b, 'A', { units: [s1.id, s2.id, theirs.id, 12345], order: 'move', x: 400, z: 600 });
  assert.strictEqual(theirs.orders.length, 0);
  assert.deepStrictEqual(s1.orders.map((o) => [o.order, Math.round(o.x), o.z]), [['move', 395, 600]], 'the group keeps its offsets');
  assert.deepStrictEqual(s2.orders.map((o) => [o.order, Math.round(o.x), o.z]), [['move', 405, 600]]);
  B.order(b, 'A', { units: [s1.id], order: 'move', x: 600, z: 600, queue: true });
  assert.strictEqual(s1.orders.length, 2);
  run(b, 9.2); // 200 m at 22 m/s
  assert.ok(Math.hypot(s1.x - 395, s1.z - 600) < 3, 'reached the first waypoint');
  assert.strictEqual(s1.orders.length, 1);
  run(b, 12);
  assert.ok(Math.hypot(s1.x - 600, s1.z - 600) < 3, 'then the queued one');
  assert.strictEqual(s1.orders.length, 0);
  B.order(b, 'A', { units: [s2.id], order: 'move', x: 1500, z: 1500 });
  run(b, 1);
  B.order(b, 'A', { units: [s2.id], order: 'stop' });
  const at = [s2.x, s2.z];
  run(b, 2);
  assert.deepStrictEqual([s2.x, s2.z], at);
  assert.strictEqual(B.order(b, 'A', { units: [s2.id], order: 'dance' }).quiet, true);
  // A big group keeps its shape, pulled in.
  const many = Array.from({ length: 16 }, (_, i) => B.spawn(b, 'striker', 'a', 'A', 200 + (i % 4) * 100, 200 + Math.floor(i / 4) * 100));
  B.order(b, 'A', { units: many.map((u) => u.id), order: 'amove', x: 800, z: 800 });
  const spots = many.map((u) => u.orders[0]);
  assert.ok(spots.every((o) => Math.hypot(o.x - 800, o.z - 800) <= 8 + 4 * 4 + 1e-6));
  assert.strictEqual(new Set(spots.map((o) => `${o.x},${o.z}`)).size, 16, 'each its own spot');
});

test('amove stops to fight what it meets; move shoots on the way without stopping; attack chases', () => {
  const b = battle();
  const am = B.spawn(b, 'striker', 'a', 'A', 700, 500);
  const mv = B.spawn(b, 'striker', 'a', 'A', 900, 500);
  const foe1 = B.spawn(b, 'engineer', 'd', '', 730, 600);
  const foe2 = B.spawn(b, 'engineer', 'd', '', 930, 600);
  for (const f of [foe1, foe2]) f.orders = [{ order: 'move', x: f.x, z: f.z }];
  B.order(b, 'A', { units: [am.id], order: 'amove', x: 700, z: 1000 });
  B.order(b, 'A', { units: [mv.id], order: 'move', x: 900, z: 1000 });
  run(b, 16);
  assert.ok(!b.units.has(foe1.id), 'the amove striker killed it');
  assert.ok(am.z < 700, `and stopped to do it (z ${am.z})`);
  assert.ok(mv.z > 600, 'the moving one kept going');
  assert.ok(foe2.hp < C.engineer.hp, 'shooting as it passed');
  // attack: chase a target out of range.
  const runner = B.spawn(b, 'engineer', 'd', '', 300, 300);
  runner.orders = [{ order: 'move', x: 300, z: 300 }];
  B.order(b, 'A', { units: [mv.id], order: 'attack', target: runner.id });
  run(b, 80);
  assert.ok(!b.units.has(runner.id));
  assert.strictEqual(mv.orders.length, 0, 'done once it is dead');
  // Attacking a friend, or nothing, is ignored.
  B.order(b, 'A', { units: [mv.id], order: 'attack', target: am.id });
  assert.strictEqual(mv.orders.length, 0);
});

test('orders are limited to 20 a second, drives to 30; other battles and unknown ids are ignored', () => {
  const g = galaxy('ashen');
  const { m, pilot } = manager(g);
  W.setDemo(true);
  try {
    const a = pilot('ashen');
    const r = m.start(a, 'ashen', 'cinder', 'cinder-3', over('cinder'));
    const b = m.battles.get(r.battle);
    const u = B.spawn(b, 'scout', 'a', 'ashen', 500, 500);
    let given = 0;
    for (let i = 0; i < 25; i++) {
      u.orders = [];
      m.handle(a, { type: 'battle_order', battle: r.battle, units: [u.id], order: 'move', x: 600, z: 600 });
      if (u.orders.length) given++;
    }
    assert.ok(given >= 20 && given <= 21, `${given} orders went through`); // a second can tick over mid-loop
    assert.ok(m.handle(a, { type: 'battle_order', battle: 'b999', units: [u.id], order: 'stop' }).quiet);
    a.orderWindow = 0;
    assert.ok(m.handle(a, { type: 'battle_order', battle: r.battle, units: [777], order: 'stop' }).quiet);
    assert.strictEqual(m.handle(a, { type: 'battle_drop', battle: r.battle, unit: 'tank', count: 9 }).reason, 'not enough mass: 9 Tanks cost 1170 mass and 2925 energy');
    m.handle(a, { type: 'battle_possess', battle: r.battle, unit: u.id });
    let drives = 0;
    for (let i = 0; i < 40; i++) {
      u.driven.t = -1;
      m.handle(a, { type: 'battle_drive', battle: r.battle, move: [1, 0], aim: [0, 0], fire: false });
      if (u.driven.t !== -1) drives++;
    }
    assert.ok(drives >= 30 && drives <= 31, `${drives} drives went through`);
    m.handle(a, { type: 'battle_leave' });
    assert.strictEqual(a.battle, null);
    assert.strictEqual(u.driven, null, 'leaving hands the unit back');
    assert.deepStrictEqual(m.list()[0].pilots, []);
    assert.ok(b.units.has(u.id), 'their units stay');
  } finally {
    W.setDemo(false);
    m.close();
  }
});

test('attack orders only go to units that can hit the target; queues are capped', () => {
  const b = battle();
  const eng = B.spawn(b, 'engineer', 'a', 'A', 800, 800);
  const striker = B.spawn(b, 'striker', 'a', 'A', 806, 800);
  const aa = B.spawn(b, 'aa', 'a', 'A', 812, 800);
  const gunship = B.spawn(b, 'gunship', 'd', '', 800, 1000);
  B.order(b, 'A', { units: [striker.id], order: 'move', x: 900, z: 900 });
  B.order(b, 'A', { units: [eng.id, striker.id, aa.id], order: 'attack', target: gunship.id });
  assert.deepStrictEqual(eng.orders, [], 'an engineer shoots nothing');
  assert.strictEqual(striker.orders[0].order, 'move', "a striker can't hit a gunship: it carries on");
  assert.deepStrictEqual(aa.orders, [{ order: 'attack', target: gunship.id }]);

  // Artillery told to attack something inside its least range backs off, then fires.
  const art = B.spawn(b, 'artillery', 'a', 'A', 400, 400);
  const close = B.spawn(b, 'engineer', 'd', '', 400, 420);
  B.order(b, 'A', { units: [art.id], order: 'attack', target: close.id });
  run(b, 8);
  assert.ok(Math.hypot(art.x - close.x, art.z - close.z) >= C.artillery.minRange, 'it stepped back');
  assert.ok(close.hp < C.engineer.hp || b.shells.length, 'and fired');

  // At most 32 queued orders a unit, and 10 jobs a factory.
  for (let i = 0; i < 50; i++) B.order(b, 'A', { units: [striker.id], order: 'move', x: 100 + i, z: 100, queue: true });
  assert.strictEqual(striker.orders.length, 32);
  const f = B.spawn(b, 'factory', 'a', 'A', 600, 300);
  b.pilots.get('A').mass = 0;
  for (let i = 0; i < 10; i++) assert.ok(B.produce(b, 'A', f.id, 'scout', 1).ok);
  assert.strictEqual(B.produce(b, 'A', f.id, 'scout', 1).reason, 'a factory queues 10 orders');

  // A side fields at most 32 x 120 units, whoever owns them (pilots who left included).
  for (let i = 0; i < 32 * 120 - 6; i++) B.spawn(b, 'scout', 'a', `Gone ${i % 40}`, 50, 50);
  b.pilots.get('A').mass = 5000;
  assert.strictEqual(B.drop(b, 'A', 'scout', 3).reason, 'your side has 3840 units in the field', 'four of its own and 3834 others');
  assert.ok(B.drop(b, 'A', 'scout', 2).ok);
});

test('combat: a tank beats a striker, aa only hits air, gunships only fall to aa, turrets and gunships', () => {
  // Tank and striker meet.
  let b = battle();
  const tank = B.spawn(b, 'tank', 'a', 'A', 800, 700);
  const striker = B.spawn(b, 'striker', 'd', '', 800, 740);
  run(b, 30);
  assert.ok(!b.units.has(striker.id) && b.units.has(tank.id));
  assert.ok(tank.hp < C.tank.hp, 'but not unscathed');
  assert.ok(B.frame(b).dead.includes(striker.id), 'reported dead once...');
  assert.deepStrictEqual(B.frame(b).dead, [], '...only once');

  // AA by a tank: neither hurts the other. AA against a gunship: the gunship falls.
  b = battle();
  const aa = B.spawn(b, 'aa', 'a', 'A', 800, 700);
  const enemyTank = B.spawn(b, 'tank', 'd', '', 800, 760);
  const gunship = B.spawn(b, 'gunship', 'd', '', 760, 700);
  run(b, 3);
  assert.strictEqual(enemyTank.hp, C.tank.hp, 'aa never shoots at land');
  assert.ok(gunship.hp < C.gunship.hp);
  const shots = B.frame(b).shots;
  assert.ok(shots.some(([from, , , type]) => from === aa.id && type === 'aa'));
  run(b, 30);
  assert.ok(!b.units.has(gunship.id));

  // Strikers and tanks can't touch a gunship; it can hit them.
  b = battle();
  const ground = B.spawn(b, 'striker', 'a', 'A', 800, 700);
  const gs = B.spawn(b, 'gunship', 'd', '', 800, 720);
  run(b, 5);
  assert.strictEqual(gs.hp, C.gunship.hp);
  assert.ok(ground.hp < C.striker.hp);
  // A gunship hits another gunship.
  const mine = B.spawn(b, 'gunship', 'a', 'A', 800, 760);
  run(b, 3);
  assert.ok(gs.hp < C.gunship.hp && mine.hp <= C.gunship.hp);
});

test('artillery: splash hits a group, nothing inside its minimum range, shells take time to land', () => {
  const b = battle();
  const art = B.spawn(b, 'artillery', 'a', 'A', 800, 500);
  const group = [0, 1, 2].map((i) => B.spawn(b, 'scout', 'd', '', 790 + i * 8, 650));
  const close = B.spawn(b, 'striker', 'd', '', 2000, 2000); // off the map, clamped to a corner: out of the way
  B.order(b, 'A', { units: [art.id], order: 'stop' });
  for (const u of group) u.orders = [{ order: 'move', x: u.x, z: u.z }]; // they hold still (and are out of their own range)
  run(b, 0.1);
  const shot = B.frame(b).shots.find(([from]) => from === art.id);
  assert.ok(shot, 'fired at 150 m');
  assert.strictEqual(b.shells.length, 1);
  assert.ok(group.every((u) => u.hp === C.scout.hp), 'not landed yet');
  run(b, 1.0); // 150 m at 160 m/s
  assert.strictEqual(b.shells.length, 0);
  const hit = group.filter((u) => u.hp < C.scout.hp);
  assert.ok(hit.length >= 2, `splash hit ${hit.length}`);
  assert.ok(close.hp === C.striker.hp);

  // Inside 30 m the artillery can't fire at all.
  const b2 = battle();
  const art2 = B.spawn(b2, 'artillery', 'a', 'A', 800, 500);
  const near = B.spawn(b2, 'engineer', 'd', '', 800, 515);
  run(b2, 5);
  assert.ok(!B.frame(b2).shots.some(([from]) => from === art2.id));
  assert.strictEqual(near.hp, C.engineer.hp);
});

test('taking control of a unit: drive it, aim and fire for +25%, release it', () => {
  const b = battle();
  const p = b.pilots.get('A');
  const tank = B.spawn(b, 'tank', 'a', 'A', 800, 600);
  const other = B.spawn(b, 'tank', 'a', 'A', 900, 600);
  const enemy = B.spawn(b, 'striker', 'd', '', 800, 800);
  enemy.orders = [{ order: 'move', x: 800, z: 800 }];
  const factory = B.spawn(b, 'factory', 'a', 'A', 500, 500);
  assert.strictEqual(B.possess(b, 'A', factory.id).reason, 'you can only drive land and air units');
  assert.ok(B.possess(b, 'A', 9999).quiet);
  const pod = B.drop(b, 'A', 'scout', 1).units[0];
  assert.strictEqual(B.possess(b, 'A', pod).reason, 'that unit is still coming down');
  assert.ok(B.possess(b, 'A', tank.id).ok);
  assert.strictEqual(p.drive, tank.id);
  // It ignores orders while driven.
  B.order(b, 'A', { units: [tank.id], order: 'move', x: 100, z: 100 });
  assert.strictEqual(tank.orders.length, 0);
  // A pilot keeps sending; the unit stops when they stop (a second with nothing).
  const driveFor = (msg, s) => {
    for (let t = 0; t < s - 1e-9; t += 0.5) {
      B.drive(b, 'A', msg);
      run(b, Math.min(0.5, s - t));
    }
  };
  // Drive north at full speed for 2 s: 18 m. A move longer than 1 counts as 1.
  driveFor({ move: [0, 5], aim: [800, 800], fire: false }, 2);
  assert.ok(Math.abs(tank.z - 618) < 0.5 && Math.abs(tank.x - 800) < 0.01, `${tank.x},${tank.z}`);
  assert.strictEqual(B.frame(b).units.find((u) => u[0] === tank.id)[8], 'driven');
  // Fire at the aim point, within 6 m of the striker and in range: 50 * 1.25.
  B.drive(b, 'A', { move: [0, 0], aim: [804, 640], fire: true });
  enemy.x = 800;
  enemy.z = 645;
  run(b, 0.1);
  assert.strictEqual(enemy.hp, C.striker.hp - 62.5);
  // Aimed at bare ground: the shot lands there, hitting nothing.
  driveFor({ move: [0, 0], aim: [760, 620], fire: true }, 1.6);
  assert.strictEqual(enemy.hp, C.striker.hp - 62.5, "the striker wasn't near the aim");
  assert.ok(B.frame(b).shots.some(([from, x, z]) => from === tank.id && x === 760 && z === 620));
  // Aimed past its range, the shot falls at the range.
  driveFor({ move: [0, 0], aim: [600, 618], fire: true }, 1.6);
  const far = B.frame(b).shots.find(([from]) => from === tank.id);
  assert.ok(Math.abs(Math.hypot(far[1] - tank.x, far[2] - tank.z) - C.tank.range) < 0.2, String(far));
  // One unit at a time: taking another hands the first back.
  B.possess(b, 'A', other.id);
  assert.strictEqual(tank.driven, null);
  assert.ok(other.driven);
  B.release(b, 'A');
  assert.strictEqual(other.driven, null);
  assert.strictEqual(p.drive, null);
  B.order(b, 'A', { units: [other.id], order: 'move', x: 900, z: 700 });
  assert.strictEqual(other.orders.length, 1, 'takes orders again');
});

test('the defender AI: engineers on mass points, a defence group, waves, and always the same', () => {
  const play = () => {
    const b = battle({ ai: true });
    for (let i = 0; i < 24; i++) B.spawn(b, 'tank', 'a', 'A', b.lz.x + (i % 6) * 9, b.lz.z + Math.floor(i / 6) * 9);
    const frames = [];
    for (let i = 0; i < 400; i++) { // (its first wave goes after five minutes)
      run(b, 1);
      if (i % 30 === 0) frames.push(JSON.stringify(B.frame(b)));
    }
    return { b, frames };
  };
  const one = play();
  const two = play();
  assert.deepStrictEqual(one.frames, two.frames, 'deterministic');
  const { b } = one;
  const ai = units(b, (u) => u.side === 'd' && u.owner === '');
  assert.ok(ai.filter((u) => u.type === 'engineer').length <= 3);
  assert.ok(units(b, (u) => u.type === 'extractor' && u.side === 'd').length > 3, 'its engineers took more mass points');
  const army = ai.filter((u) => !['engineer', 'node', 'turret', 'extractor', 'outpost', 'factory'].includes(u.type));
  assert.ok(army.length >= 5, `an army of ${army.length}`);
  assert.ok(new Set(army.map((u) => u.type)).size >= 3, 'a mix');
  assert.ok(army.some((u) => u.role === 'defence') && army.some((u) => u.role === 'attack'));
  assert.ok(b.ai.waves >= 1, 'it sent a wave');

  // Its income: 6/s plus 3 per extractor, at the start.
  const fresh = battle({ ai: true });
  assert.strictEqual(B.income(fresh, ''), 6 + 3 * 3);
  // Coma's AI is the director's intensity against the attacker, doubled (at least 0.5).
  const g = G.newGalaxy();
  assert.strictEqual(B.aiRate(g, 'ashen', 'compact'), 1);
  assert.strictEqual(B.aiRate(g, 'ashen', null), 0.6);
  g.director.intensity.ashen = 0.8;
  g.director.scale = 1;
  assert.strictEqual(B.aiRate(g, 'ashen', 'coma'), 1.6);
  g.director.intensity.ashen = 0.1;
  assert.strictEqual(B.aiRate(g, 'ashen', 'coma'), 0.5);
});

test('the defender AI meets a small attack too, and k sets how big its army is', () => {
  // A fresh pilot's first drop: seven strikers by the landing zone.
  const play = () => {
    const b = battle({ ai: true });
    for (let i = 0; i < 7; i++) B.spawn(b, 'striker', 'a', 'A', b.lz.x + (i % 6) * 9, b.lz.z + Math.floor(i / 6) * 9);
    run(b, 290);
    assert.strictEqual(b.ai.waves, 0, 'five minutes to dig in first');
    run(b, 310);
    return b;
  };
  const army = (b) => units(b, (u) => u.side === 'd' && u.owner === '' && !['engineer', 'node', 'turret', 'extractor', 'outpost', 'factory'].includes(u.type)).reduce((a, u) => a + C[u.type].cost, 0);
  const compact = play();
  assert.ok(compact.ai.waves >= 1, 'it counter-attacked (after five minutes)');
  assert.ok(units(compact, (u) => u.side === 'a' && u.type === 'striker').length < 7, 'and the wave fought');
  // A militia (k 0.6) fields less.
  const weak = battle({ ai: true, defender: null });
  weak.ai.k = 0.6;
  run(weak, 600);
  assert.ok(army(weak) < army(compact), `${army(weak)} against ${army(compact)}`);
});

test('destroying the Command Node takes the sector: W.capture runs and every pilot hears', () => {
  const g = galaxy('ashen', 'compact');
  const { m, pilot, changes } = manager(g);
  W.setDemo(true);
  try {
    const a = pilot('ashen');
    const d = pilot('compact');
    const r = m.start(a, 'ashen', 'cinder', 'cinder-3', over('cinder'));
    m.join(d, 'compact', r.battle, { over: null, station: 'cinder' });
    const b = m.battles.get(r.battle);
    b.units.get(b.nodeId).hp = 0;
    m.tick();
    const end = a.inbox.find((x) => x.type === 'battle_end');
    assert.deepStrictEqual(end, { type: 'battle_end', battle: r.battle, winner: 'ashen', side: 'a', text: 'Sector taken: Cinder 3 falls to the Ashen Collective' });
    assert.deepStrictEqual(d.inbox.find((x) => x.type === 'battle_end'), end);
    assert.strictEqual(W.planet(g, 'cinder').sectors.find((s) => s.id === 'cinder-3').owner, 'ashen');
    assert.ok(g.war.log.some((e) => e.text === 'Ashen Collective took Cinder 3 from the Terran Compact'));
    assert.ok(changes.length > 0);
    assert.deepStrictEqual(m.list(), [], 'over');
    // Orders after the end are ignored, and the sector can be fought over again.
    assert.ok(m.handle(a, { type: 'battle_drop', battle: r.battle, unit: 'scout', count: 1 }).quiet);
    assert.ok(m.start(pilot('compact'), 'compact', 'cinder', 'cinder-3', over('cinder')).ok);
  } finally {
    W.setDemo(false);
    m.close();
  }
});

test('the defender wins when time runs out, or when the attackers abandon the field', () => {
  const g = galaxy('ashen');
  const { m, pilot, clock } = manager(g);
  W.setDemo(true);
  try {
    const a = pilot('ashen');
    const r = m.start(a, 'ashen', 'cinder', 'cinder-3', over('cinder'));
    const b = m.battles.get(r.battle);
    assert.strictEqual(b.endsAt, clock.t + 30 * 60_000);
    clock.t = b.endsAt;
    m.tick();
    assert.deepStrictEqual(a.inbox.find((x) => x.type === 'battle_end'), { type: 'battle_end', battle: r.battle, winner: 'compact', side: 'd', text: 'Attack failed: the Terran Compact held Cinder 3 (the clock ran out)' });
    assert.strictEqual(W.planet(g, 'cinder').sectors.find((s) => s.id === 'cinder-3').owner, 'compact');
    assert.match(g.war.log.at(-1).text, /Ashen Collective's attack on Cinder 3 failed/);
  } finally {
    W.setDemo(false);
    m.close();
  }

  // The attackers' units fall but their ACU stands: still on. The ACU falls: the defenders win.
  const b = battle();
  const u = B.spawn(b, 'scout', 'a', 'A', 100, 100);
  B.removePilot(b, 'A');
  u.hp = 0;
  run(b, 70);
  assert.strictEqual(b.result, null, 'their ACU still stands');
  units(b, (x) => x.type === 'acu')[0].hp = 0;
  run(b, 0.2);
  assert.deepStrictEqual([b.result, b.how], ['d', 'acus']);

  // Abandoned too: units still on the field, but none of the attackers' pilots for five minutes.
  const left = battle();
  B.spawn(left, 'scout', 'a', 'A', 100, 100);
  B.removePilot(left, 'A');
  run(left, 299);
  assert.strictEqual(left.result, null);
  B.addPilot(left, 'A', 'a', 'ashen');
  run(left, 10);
  B.removePilot(left, 'A');
  run(left, 299);
  assert.strictEqual(left.result, null, 'the clock starts again when a pilot comes back');
  run(left, 1.2);
  assert.deepStrictEqual([left.result, left.how], ['d', 'abandoned']);
});

test('a pilot leads one attack at a time, joining again changes nothing, and a lock calls attacks off', () => {
  const g = galaxy('ashen', 'ashen2');
  const { m, pilot, changes } = manager(g);
  W.setDemo(true);
  try {
    const a = pilot('ashen');
    const first = m.start(a, 'ashen', 'cinder', 'cinder-2', over('cinder'));
    assert.ok(first.ok, first.reason);
    const n = changes.length;
    for (let i = 0; i < 5; i++) assert.ok(m.join(a, 'ashen', first.battle, over('cinder')).ok);
    assert.strictEqual(changes.length, n, 'joining a battle you are in only says battle_joined again');
    // Starting another gives up the first, which nobody else fights.
    const second = m.start(a, 'ashen', 'cinder', 'cinder-3', over('cinder'));
    assert.ok(second.ok, second.reason);
    assert.deepStrictEqual([m.battles.get(first.battle).result, m.battles.get(first.battle).how], ['d', 'abandoned']);
    assert.deepStrictEqual(m.list().map((x) => x.id), [second.battle]);
    // Unless someone else still fights it.
    const a2 = pilot('ashen2');
    assert.ok(m.join(a2, 'ashen', second.battle, over('cinder')).ok);
    const third = m.start(a, 'ashen', 'cinder', 'cinder-4', over('cinder'));
    assert.ok(third.ok, third.reason);
    assert.strictEqual(m.battles.get(second.battle).result, null, 'Ashen 2 fights on');

    // Cinder locks (another battle took it): every attack on it is called off, and nobody joins one.
    W.planet(g, 'cinder').lockedUntil = m.battles.get(third.battle).startedAt + 60_000;
    assert.match(m.join(pilot('ashen'), 'ashen', second.battle, over('cinder')).reason, /Cinder is locked/);
    for (let i = 0; i < 10; i++) m.tick();
    assert.deepStrictEqual(m.list(), []);
    const end = a.inbox.find((x) => x.type === 'battle_end' && x.battle === third.battle);
    assert.match(end.text, /^Attack called off: Cinder is locked for/);
    assert.match(g.war.log.at(-1).text, /attack on Cinder \d+ was called off/);
  } finally {
    W.setDemo(false);
    m.close();
  }
});

test('snapshots: every unit, the dead, shots, building progress, pilots, rounded to 0.1', () => {
  const b = battle();
  B.addPilot(b, 'D', 'd', 'compact');
  const t = B.spawn(b, 'tank', 'a', 'A', 123.456, 654.321);
  B.spawn(b, 'turret', 'a', 'A', 300, 300, { built: false });
  run(b, 0.1);
  const f = B.frame(b);
  const s = B.stateFor(b, f, 'A');
  assert.deepStrictEqual(Object.keys(s).sort(), ['battle', 'build', 'dead', 'endsAt', 'energy', 'energyCap', 'energyIncome', 'factories', 'feed', 'income', 'mass', 'massCap', 'pilots', 'shots', 'stalled', 't', 'type', 'units'].sort());
  assert.strictEqual(s.type, 'battle_state');
  assert.strictEqual(s.t, 0.1);
  assert.strictEqual(s.mass, 400.2);
  assert.deepStrictEqual(s.units.find((u) => u[0] === t.id), [t.id, 'tank', 'a', 'A', 123.5, 654.3, 750, 0, 'idle', 0, null, 1]);
  assert.deepStrictEqual(s.units.find((u) => u[1] === 'node').slice(1, 4), ['node', 'd', '']);
  assert.ok(s.build.some(([, progress]) => progress === 0));
  assert.deepStrictEqual(s.pilots, [{ name: 'A', side: 'a', out: false, resign: false }, { name: 'D', side: 'd', out: false, resign: false }]);
  assert.strictEqual(B.stateFor(b, f, 'D').mass, 400.2);
});

// --- Over the wire ----------------------------------------------------------------------------

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

test('over the wire: an attacker from a carrier over Cinder, a defender from its station', async () => {
  const port = 9153;
  const server = startServer({ port, tickMs: 60000, demo: true, demoWar: true, battleSpeed: 20 });
  const type = (t) => (m) => m.type === t;
  try {
    const att = await connect(port);
    const def = await connect(port);
    att.send({ type: 'hello', role: 'explorer', name: 'Akane' });
    def.send({ type: 'hello', role: 'explorer', name: 'Rin' });
    await att.next(type('welcome'));
    await def.next(type('welcome'));
    att.send({ type: 'choose_faction', faction: 'ashen' });
    def.send({ type: 'choose_faction', faction: 'compact' });
    await att.next((m) => m.type === 'state' && m.state.pilots.Rin?.faction === 'compact' && m.state.pilots.Akane?.faction === 'ashen');

    // Not aboard a carrier yet.
    att.send({ type: 'battle_start', planet: 'cinder', sector: 'cinder-3' });
    assert.strictEqual((await att.next(type('error'))).reason, 'you need to be aboard a carrier over Cinder');
    // Up from the pilot's chair, in her carrier, flying over Cinder.
    att.send({ type: 'enter_space', space: 'ship:Akane' });
    await att.next(type('space_joined'));
    att.send({ type: 'ship', pos: [0, 0, 0], rot: [0, 0, 0], over: 'cinder' });
    att.send({ type: 'battle_start', planet: 'cinder', sector: 'cinder-3' });
    const joined = await att.next(type('battle_joined'));
    assert.deepStrictEqual([joined.side, joined.attacker, joined.defender, joined.sectorName], ['a', 'ashen', 'compact', 'Cinder 3']);
    const listed = await def.next((m) => m.type === 'state' && m.state.battles?.length === 1);
    assert.deepStrictEqual(listed.state.battles[0].pilots, [{ name: 'Akane', side: 'a' }]);

    // The defender joins from Cinder Orbital.
    def.send({ type: 'battle_join', battle: joined.battle });
    assert.match((await def.next(type('error'))).reason, /Cinder's station or aboard a carrier over it/);
    def.send({ type: 'dock_request', station: 'cinder' });
    await def.next(type('dock_granted'));
    def.send({ type: 'enter_space', space: 'station:cinder' });
    await def.next(type('space_joined'));
    def.send({ type: 'battle_join', battle: joined.battle });
    const djoined = await def.next(type('battle_joined'));
    assert.strictEqual(djoined.side, 'd');

    // Snapshots for both; the attacker's drop shows up, lands, and takes orders.
    att.send({ type: 'battle_drop', battle: joined.battle, unit: 'tank', count: 2 });
    const dropped = await att.next((m) => m.type === 'battle_state' && m.units.some((u) => u[3] === 'Akane' && u[1] === 'tank'));
    const mine = dropped.units.filter((u) => u[3] === 'Akane' && u[1] !== 'acu').map((u) => u[0]);
    assert.strictEqual(mine.length, 2);
    assert.ok(dropped.mass < 400 - 260 + 20, `paid: ${dropped.mass}`);
    assert.ok((await def.next((m) => m.type === 'battle_state' && m.pilots.length === 2)).units.some((u) => u[3] === 'Akane'));
    att.send({ type: 'battle_drop', battle: joined.battle, unit: 'tank', count: 9 });
    assert.match((await att.next(type('error'))).reason, /not enough mass/);
    await att.next((m) => m.type === 'battle_state' && m.units.filter((u) => mine.includes(u[0])).every((u) => u[8] !== 'drop'));
    att.send({ type: 'battle_order', battle: joined.battle, units: mine, order: 'amove', x: joined.enemyLz.x, z: joined.enemyLz.z });
    await att.next((m) => m.type === 'battle_state' && m.units.some((u) => mine.includes(u[0]) && ['move', 'fight'].includes(u[8])));
    att.send({ type: 'battle_possess', battle: joined.battle, unit: mine[0] });
    att.send({ type: 'battle_drive', battle: joined.battle, move: [1, 0], aim: [800, 800], fire: true });
    await att.next((m) => m.type === 'battle_state' && m.units.some((u) => u[0] === mine[0] && u[8] === 'driven'));
    att.send({ type: 'battle_release', battle: joined.battle });

    // The Command Node falls: the sector is Ashen's.
    const b = server.battles.battles.get(joined.battle);
    b.units.get(b.nodeId).hp = 0;
    const end = await att.next(type('battle_end'));
    assert.deepStrictEqual([end.winner, end.side, end.text], ['ashen', 'a', 'Sector taken: Cinder 3 falls to the Ashen Collective']);
    assert.strictEqual((await def.next(type('battle_end'))).winner, 'ashen');
    const taken = await def.next((m) => m.type === 'state' && m.state.war.planets.find((p) => p.id === 'cinder').sectors[2].owner === 'ashen');
    assert.deepStrictEqual(taken.state.battles, []);

    // Builders don't fight sector battles.
    const phone = await connect(port);
    phone.send({ type: 'hello', role: 'builder', name: 'Builder' });
    await phone.next(type('welcome'));
    phone.send({ type: 'battle_start', planet: 'cinder', sector: 'cinder-3' });
    assert.strictEqual((await phone.next(type('error'))).reason, 'only pilots fight sector battles');
    for (const c of [att, def, phone]) c.close();
  } finally {
    W.setDemo(false);
    await server.close();
  }
});

test('energy: everything costs mass and energy; the carrier gives 10 a second, each Power Generator 20 more', () => {
  const b = battle();
  const p = b.pilots.get('A');
  assert.strictEqual(p.energy, B.ENERGY_START);
  p.mass = 5000;
  p.energy = 300;
  assert.strictEqual(B.drop(b, 'A', 'tank', 1).reason, 'not enough energy: 1 Tank cost 130 mass and 325 energy');
  assert.ok(B.drop(b, 'A', 'striker', 2).ok);
  assert.strictEqual(p.energy, 24);
  assert.strictEqual(B.energyIncome(b, 'A'), 10);
  const e = B.spawn(b, 'engineer', 'a', 'A', 800, 300);
  assert.ok(B.order(b, 'A', { units: [e.id], order: 'build', structure: 'generator', x: 800, z: 320 }).ok);
  run(b, 6);
  const gen = units(b, (u) => u.type === 'generator')[0];
  assert.ok(gen?.built, 'a generator: 20 mass, no energy');
  assert.strictEqual(B.energyIncome(b, 'A'), 30);
  const before = p.energy;
  run(b, 1);
  assert.ok(Math.abs(p.energy - before - 30) < 0.01);
});

test('the carrier drops tier 1 only; factories upgrade to tiers 2 and 3 and make bigger, faster, stronger units', () => {
  const b = battle();
  const p = b.pilots.get('A');
  [p.mass, p.energy] = [5000, 25000];
  assert.match(B.drop(b, 'A', 'tank_t2', 1).reason, /tier 1 units only/);
  const [t1, t2, t3] = ['tank', 'tank_t2', 'tank_t3'].map((t) => B.CATALOG[t]);
  for (const f of ['hp', 'damage', 'speed', 'radius', 'cost', 'energy']) assert.ok(t1[f] < t2[f] && t2[f] < t3[f], `${f} grows with the tier`);
  assert.strictEqual(t3.name, 'Tank Mk III');
  const f = B.spawn(b, 'factory', 'a', 'A', 800, 400);
  assert.match(B.produce(b, 'A', f.id, 'tank_t2', 1).reason, /tier 1 factory can't make the Tank Mk II: upgrade it to tier 2/);
  assert.ok(B.upgradeFactory(b, 'A', f.id).ok);
  assert.match(B.upgradeFactory(b, 'A', f.id).reason, /already upgrading/);
  const mass = p.mass;
  run(b, 20.2); // 400 mass at 20 a second
  assert.strictEqual(f.tier, 2);
  assert.ok(Math.abs(mass - p.mass - 400 + 20.2 * 2) < 0.5, 'the upgrade is paid in full');
  assert.ok(B.produce(b, 'A', f.id, 'tank_t2', 1).ok);
  assert.match(B.produce(b, 'A', f.id, 'tank_t3', 1).reason, /upgrade it to tier 3/);
  const energy = p.energy;
  run(b, t2.cost / 20 + 0.2);
  const made = units(b, (u) => u.type === 'tank_t2');
  assert.strictEqual(made.length, 1);
  assert.strictEqual(made[0].hp, t2.hp);
  assert.ok(Math.abs(energy + (t2.cost / 20 + 0.2) * 10 - p.energy - t2.energy / 2) < 1, 'made on the planet at half price');
  assert.ok(B.upgradeFactory(b, 'A', f.id).ok);
  run(b, 46);
  assert.strictEqual(f.tier, 3);
  assert.match(B.upgradeFactory(b, 'A', f.id).reason, /tier 3, the top/);
  const s = B.stateFor(b, B.frame(b), 'A');
  assert.deepStrictEqual(s.factories, [[f.id, 3, null, 0]]);
});

test('command: every attacker lands an ACU, and the defender gets a Command Node and drop zone for each', () => {
  const b = battle();
  const acus = () => units(b, (u) => u.type === 'acu');
  assert.strictEqual(acus().length, 1);
  assert.strictEqual(acus()[0].owner, 'A');
  assert.strictEqual(acus()[0].state, 'drop', 'it comes down by drop pod');
  assert.strictEqual(B.aliveNodes(b).length, 1);
  B.addPilot(b, 'A2', 'a', 'ashen');
  B.addPilot(b, 'A3', 'a', 'ashen');
  assert.strictEqual(acus().length, 3);
  const nodes = B.aliveNodes(b);
  assert.strictEqual(nodes.length, 3, 'one Node per attacking commander');
  assert.ok(nodes.every((n, i) => nodes.every((m, j) => i === j || Math.hypot(n.x - m.x, n.z - m.z) > 200)), 'spread across the map');
  // The AI's drops come down by each of its Nodes in turn.
  const near = (u) => nodes.findIndex((n) => Math.hypot(u.x - n.x, u.z - n.z) < 90);
  const pods = [0, 1, 2].map(() => B.dropUnits(b, 'd', '', 'scout', 1)[0]);
  assert.strictEqual(new Set(pods.map(near)).size, 3, 'one drop by each Node');
  // A defending pilot takes command of a free Node; their drops land by it.
  B.addPilot(b, 'D', 'd', 'compact');
  const mine = nodes.find((n) => n.commander === 'D');
  assert.ok(mine);
  b.pilots.get('D').mass = 5000;
  const r = B.drop(b, 'D', 'scout', 1);
  const u = b.units.get(r.units[0]);
  assert.ok(Math.hypot(u.x - mine.x, u.z - mine.z) < 90, 'by their own Node');
  // The ACU builds what an engineer does.
  run(b, 7);
  const acu = acus().find((x) => x.owner === 'A');
  assert.ok(B.order(b, 'A', { units: [acu.id], order: 'build', structure: 'generator', x: acu.x + 25, z: acu.z + 10 }).ok);
  assert.strictEqual(acu.orders[0].order, 'build');
});

test("command: a fallen ACU blasts what's round it and puts its commander out; the last one loses the battle", () => {
  const b = battle();
  B.addPilot(b, 'A2', 'a', 'ashen');
  run(b, 7);
  const acu = units(b, (u) => u.type === 'acu' && u.owner === 'A')[0];
  const nearby = B.spawn(b, 'tank', 'd', '', acu.x + 15, acu.z);
  const far = B.spawn(b, 'tank', 'd', '', acu.x + 200, acu.z);
  const friend = B.spawn(b, 'striker', 'a', 'A2', acu.x - 10, acu.z);
  acu.hp = 0;
  run(b, 0.2);
  assert.ok(!b.units.has(nearby.id), 'the blast destroyed the tank beside it');
  assert.ok(!b.units.has(friend.id), "and a friend too close to it");
  assert.strictEqual(far.hp, B.CATALOG.tank.hp, 'but not one 200 m off');
  assert.strictEqual(b.pilots.get('A').out, true);
  assert.strictEqual(b.result, null, "A2's ACU still stands");
  b.pilots.get('A').mass = 5000;
  assert.match(B.drop(b, 'A', 'scout', 1).reason, /you're out of this battle/);
  assert.match(B.order(b, 'A', { units: [], order: 'stop' }).reason, /you're out/);
  units(b, (u) => u.type === 'acu')[0].hp = 0;
  run(b, 0.2);
  assert.deepStrictEqual([b.result, b.how], ['d', 'acus']);
});

test('command: the attackers win when every Command Node is down; a side resigns at 66% of its commanders', () => {
  const b = battle();
  B.addPilot(b, 'A2', 'a', 'ashen');
  const nodes = B.aliveNodes(b);
  assert.strictEqual(nodes.length, 2);
  nodes[0].hp = 0;
  run(b, 0.2);
  assert.strictEqual(b.result, null, 'one Node still stands');
  nodes[1].hp = 0;
  run(b, 0.2);
  assert.deepStrictEqual([b.result, b.how], ['a', 'node']);

  const r = battle();
  B.addPilot(r, 'A2', 'a', 'ashen');
  B.addPilot(r, 'A3', 'a', 'ashen');
  assert.deepStrictEqual(B.resign(r, 'A', true), { ok: true, votes: 1, voters: 3 });
  assert.strictEqual(r.result, null);
  B.resign(r, 'A2', true);
  assert.deepStrictEqual([r.result, r.how], ['d', 'resign'], 'two of three is 66%');
  const t = battle();
  B.addPilot(t, 'A2', 'a', 'ashen');
  B.resign(t, 'A', true);
  B.resign(t, 'A', false);
  B.resign(t, 'A2', true);
  assert.strictEqual(t.result, null, 'a vote taken back no longer counts');
});

test('economy tiers: extractors and generators upgrade; an extractor uses 5 generators of energy and stops at zero', () => {
  const b = battle();
  const p = b.pilots.get('A');
  const ex = B.spawn(b, 'extractor', 'a', 'A', 300, 300);
  assert.strictEqual(B.income(b, 'A'), 2 + B.EXTRACTOR_MASS[1]);
  assert.strictEqual(B.energyIncome(b, 'A'), 10 - 5 * B.GENERATOR_POWER_T[1], 'one extractor uses 100 energy a second');
  const gens = [0, 1, 2, 3, 4].map((i) => B.spawn(b, 'generator', 'a', 'A', 400 + i * 20, 300));
  assert.strictEqual(B.energyIncome(b, 'A'), 10, 'five generators run it');
  // Upgrade a generator and the extractor.
  [p.mass, p.energy] = [5000, 25000];
  assert.ok(B.upgradeFactory(b, 'A', gens[0].id).ok);
  run(b, 200 / 20 + 0.2);
  assert.strictEqual(gens[0].tier, 2);
  assert.strictEqual(B.energyIncome(b, 'A'), 10 + 60 - 20);
  assert.ok(B.upgradeFactory(b, 'A', ex.id).ok);
  run(b, 300 / 20 + 0.2);
  assert.strictEqual(ex.tier, 2);
  assert.strictEqual(B.income(b, 'A'), 2 + B.EXTRACTOR_MASS[2]);
  // Out of energy, the extractor stops; the carrier's mass still comes.
  for (const g of gens) g.hp = 0;
  run(b, 0.2);
  p.energy = 1;
  run(b, 1);
  assert.strictEqual(p.energy, 0);
  assert.strictEqual(B.income(b, 'A'), 2);
  const m = p.mass;
  run(b, 1);
  assert.ok(Math.abs(p.mass - m - 2) < 0.01);
});

test('air factories make air units at tiers; shields soak damage; storage raises the caps', () => {
  const b = battle();
  const p = b.pilots.get('A');
  [p.mass, p.energy] = [5000, 25000];
  const af = B.spawn(b, 'airfactory', 'a', 'A', 800, 400);
  assert.strictEqual(B.produce(b, 'A', af.id, 'tank', 1).reason, 'an air factory makes air units only');
  assert.match(B.produce(b, 'A', af.id, 'fighter_t2', 1).reason, /upgrade it to tier 2/);
  assert.ok(B.produce(b, 'A', af.id, 'fighter', 1).ok);
  run(b, B.CATALOG.fighter.cost / 20 + 0.3);
  assert.strictEqual(units(b, (u) => u.type === 'fighter').length, 1);
  // A shield generator charges its dome and takes the hits on what's under it.
  const sh = B.spawn(b, 'shield', 'a', 'A', 500, 500);
  const t = B.spawn(b, 'tank', 'a', 'A', 510, 500);
  run(b, 10);
  assert.ok(sh.shieldHp > 300);
  const before = sh.shieldHp;
  const hp = t.hp;
  b.units.get(t.id).hp; // (the hit comes from an enemy tank)
  const foe = B.spawn(b, 'tank', 'd', '', 560, 500);
  foe.cd = 0;
  run(b, 0.1);
  assert.strictEqual(t.hp, hp, 'the dome soaked the shot');
  assert.ok(sh.shieldHp < before);
  // Storage: more room for mass and energy.
  B.spawn(b, 'massstorage', 'a', 'A', 700, 700);
  B.spawn(b, 'energystorage', 'a', 'A', 720, 700);
  const s = B.stateFor(b, B.frame(b), 'A');
  assert.deepStrictEqual([s.massCap, s.energyCap], [B.MASS_CAP + 1500, B.ENERGY_CAP + 8000]);
});

test('veterancy: kills earn stars that heal and toughen a unit', () => {
  const b = battle();
  const t = B.spawn(b, 'tank', 'a', 'A', 300, 300);
  for (let i = 0; i < 3; i++) {
    const v = B.spawn(b, 'scout', 'd', '', 320, 300);
    v.lastHit = t.id;
    v.hp = 0;
    run(b, 0.1);
  }
  assert.strictEqual(t.vet, 1, 'three tier 1 kills: a star');
  assert.ok(Math.abs(t.maxHp - B.CATALOG.tank.hp * 1.1) < 1e-6);
  assert.deepStrictEqual(B.frame(b).units.find((u) => u[0] === t.id)[9], 1);
});
