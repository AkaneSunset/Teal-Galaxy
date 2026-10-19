// The war map, capturing sectors, and the navies that fight for orbital control.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const N = require('../navy');
const W = require('../war');

// A galaxy with a Builder of each of the given factions, named after it.
function war(...factions) {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  for (const f of factions) {
    G.claimBase(g, f);
    assert.ok(G.chooseFaction(g, 'builder', f, f).ok);
  }
  return g;
}

// Puts `ships` from `owner`'s navy in orbit over Teal Prime.
function station(g, owner, ships, now = 0) {
  for (const [id, n] of Object.entries(ships)) g.bases[owner].navy[id] += n;
  const r = W.sendFleet(g, owner, 'teal-prime', ships, now);
  assert.ok(r.ok, r.reason);
  W.warTick(g, r.fleet.arriveAt);
  assert.strictEqual(r.fleet.status, 'stationed');
  return r.fleet;
}

// A fleet that joined another faction's orbit, counted as if it had fought its first round there
// without losing a ship (battles themselves are tested below).
function fought(g, fleet) {
  assert.strictEqual(fleet.joining, true);
  delete fleet.joining;
  W.recompute(g, fleet.arriveAt);
  return fleet;
}

// Takes sectors of a planet for `faction` one linked step at a time, capital first, until it's theirs.
function takePlanet(g, planetId, faction, now) {
  const wp = W.planet(g, planetId);
  const order = [wp.sectors.find((s) => s.capital).id];
  for (let i = 0; i < order.length; i++) for (const id of wp.sectors.find((s) => s.id === order[i]).links) if (!order.includes(id)) order.push(id);
  for (const id of order) {
    if (wp.owner === faction) break;
    if (wp.sectors.find((s) => s.id === id).owner === faction) continue;
    const r = W.capture(g, planetId, id, faction, now);
    assert.ok(r.ok, r.reason);
  }
  assert.strictEqual(wp.owner, faction);
}

test('the war map: seven systems on two-way lanes, planets of 10 to 25 linked sectors', () => {
  const g = G.newGalaxy();
  assert.deepStrictEqual(g.war.systems.map((s) => s.id), ['teal-prime', 'fortitude', 'umbra', 'aurelia', 'comae', 'marrow', 'drift']);
  for (const s of g.war.systems) for (const id of s.lanes) assert.ok(W.system(g, id).lanes.includes(s.id), `${s.id} - ${id} both ways`);
  assert.deepStrictEqual(W.system(g, 'teal-prime'), { id: 'teal-prime', name: 'Teal Prime', pos: [0, 0], lanes: ['fortitude', 'umbra', 'aurelia', 'comae'], capitalOf: null, home: true });
  assert.deepStrictEqual(W.system(g, 'marrow').pos, [0, -2]);
  assert.strictEqual(g.war.planets.length, 17);
  const counts = new Set();
  for (const wp of g.war.planets) {
    const n = wp.sectors.length;
    counts.add(n);
    assert.ok(n >= 10 && n <= 25, `${wp.id}: ${n} sectors`);
    assert.strictEqual(n, 10 + (W.hash(wp.id) % 16));
    assert.deepStrictEqual(wp.sectors.filter((s) => s.capital).map((s) => s.id), [`${wp.id}-1`], 'sector 1 is the capital');
    assert.strictEqual(wp.sectors[6].name, `${wp.name} 7`);
    const byId = Object.fromEntries(wp.sectors.map((s) => [s.id, s]));
    for (const s of wp.sectors) {
      assert.ok(s.links.length >= 3 && !s.links.includes(s.id));
      for (const id of s.links) assert.ok(byId[id].links.includes(s.id), `${s.id} - ${id} both ways`);
      assert.ok(Math.abs(s.lat) <= 90 && s.lon >= 0 && s.lon < 360);
    }
    const seen = new Set([wp.sectors[0].id]);
    const queue = [wp.sectors[0].id];
    while (queue.length) for (const id of byId[queue.shift()].links) if (!seen.has(id)) seen.add(id) && queue.push(id);
    assert.strictEqual(seen.size, n, `every sector of ${wp.id} can be reached`);
  }
  assert.ok(counts.size > 6, 'planets differ in size');
  assert.deepStrictEqual(G.newGalaxy().war.planets, g.war.planets, 'the same map every time');
});

test('initial owners: Teal Prime split four ways, the capitals for good, the far systems neutral', () => {
  const g = G.newGalaxy();
  const owner = (id) => W.planet(g, id).owner;
  assert.deepStrictEqual(['cinder', 'vesper', 'halcyon', 'morrow'].map(owner), ['compact', 'ashen', 'luminar', 'coma']);
  assert.deepStrictEqual(['bastion', 'shade', 'radiance', 'nadir'].map(owner), ['compact', 'ashen', 'luminar', 'coma']);
  for (const id of ['scar', 'rift', 'cairn', 'eddy', 'mire']) {
    assert.strictEqual(owner(id), null);
    assert.ok(W.planet(g, id).sectors.every((s) => s.owner === null));
  }
  assert.ok(W.planet(g, 'cinder').sectors.every((s) => s.owner === 'compact'));
  assert.ok(W.planet(g, 'anvil').capital && !W.planet(g, 'cinder').capital);
  assert.deepStrictEqual(W.planet(g, 'cinder').contenders, ['compact'], 'nobody has the orbit to attack yet');
  assert.deepStrictEqual(g.war.orbital['teal-prime'], { compact: 0, ashen: 0, luminar: 0, coma: 0 });
});

test('a planet is held by whoever has its capital sector and 75% of it', () => {
  const wp = { sectors: Array.from({ length: 20 }, (_, i) => ({ id: `p-${i + 1}`, capital: i === 0, owner: 'ashen' })) };
  assert.strictEqual(W.planetOwner(wp), 'ashen');
  for (let i = 15; i < 20; i++) wp.sectors[i].owner = 'coma';
  assert.strictEqual(W.planetOwner(wp), 'ashen', '15 of 20 is exactly 75%');
  wp.sectors[14].owner = 'coma';
  assert.strictEqual(W.planetOwner(wp), null, '14 of 20 is not enough');
  wp.sectors[14].owner = 'ashen';
  wp.sectors[0].owner = 'coma';
  assert.strictEqual(W.planetOwner(wp), null, 'not without the capital sector');
});

test('footholds: a sector there, another planet in the system, or half a system next door', () => {
  const g = G.newGalaxy();
  const has = (f, id) => W.foothold(g, f, W.planet(g, id));
  for (const f of ['compact', 'ashen', 'luminar', 'coma']) assert.ok(has(f, 'vesper'), `${f} reaches Teal Prime from its capital`);
  assert.ok(has('compact', 'scar') && has('ashen', 'rift'), 'Marrow Reach is next to Fortitude and Umbra');
  assert.ok(!has('luminar', 'scar') && !has('coma', 'cairn'));
  assert.ok(has('luminar', 'eddy') && !has('compact', 'mire'));
  W.planet(g, 'mire').sectors[4].owner = 'compact';
  assert.ok(has('compact', 'mire'), 'a sector of it');
  W.planet(g, 'mire').owner = 'compact';
  assert.ok(has('compact', 'eddy'), 'another planet in the system');
  // Half of Teal Prime is a foothold in the systems next to it.
  W.planet(g, 'vesper').owner = 'compact';
  assert.strictEqual(W.systemShare(g, 'teal-prime', 'compact'), 0.5);
  assert.strictEqual(W.systemShare(g, 'fortitude', 'compact'), 1, 'a capital system is wholly its faction');
});

test('capital worlds, the week lock and the 25% orbital rule', () => {
  const g = war('compact', 'ashen');
  assert.match(W.canAttack(g, 'ashen', 'bastion', 0).reason, /capital worlds can't be attacked/);
  assert.match(W.canAttack(g, 'ashen', 'nowhere', 0).reason, /no such planet/);
  assert.match(W.canAttack(g, 'pirates', 'cinder', 0).reason, /no such faction/);
  assert.strictEqual(W.canAttack(g, 'ashen', 'cinder', 0).reason, 'you need 25% orbital control of Teal Prime: you have 0%');
  station(g, 'compact', { frigate: 2 }); // power 22
  fought(g, station(g, 'ashen', { corvette: 1 })); // power 4
  assert.strictEqual(W.canAttack(g, 'ashen', 'cinder', 0).reason, 'you need 25% orbital control of Teal Prime: you have 15%');
  fought(g, station(g, 'ashen', { corvette: 2 })); // 12 of 34
  assert.ok(W.canAttack(g, 'ashen', 'cinder', 0).ok, '35% is enough');
  assert.ok(g.war.orbital['teal-prime'].ashen > 0.35 && g.war.orbital['teal-prime'].compact < 0.65);
  assert.deepStrictEqual(W.planet(g, 'cinder').contenders, ['compact', 'ashen']);
  assert.deepStrictEqual(W.planet(g, 'halcyon').contenders, ['compact', 'ashen', 'luminar'], 'a front line: two attackers and the owner');
  W.planet(g, 'cinder').lockedUntil = 6.5 * 24 * 3600_000;
  assert.strictEqual(W.canAttack(g, 'ashen', 'cinder', 0).reason, 'Cinder is locked for 7 more days');
  assert.strictEqual(W.canAttack(g, 'ashen', 'cinder', 6 * 24 * 3600_000).reason, 'Cinder is locked for 12 more hours');
  assert.ok(W.canAttack(g, 'ashen', 'cinder', 0, { lock: false }).ok, 'contenders ignore the lock');
});

test('capture: linked sectors one by one; the capital and 75% win the planet and lock it a week', () => {
  const g = war('compact', 'ashen');
  station(g, 'ashen', { corvette: 1 });
  const cinder = W.planet(g, 'cinder');
  const t = 1_000_000;
  assert.match(W.capture(g, 'cinder', 'cinder-99', 'ashen', t).reason, /no such sector/);
  // With no sector there yet, any will do: the capital sector costs the Compact the planet.
  assert.ok(W.capture(g, 'cinder', 'cinder-1', 'ashen', t).ok);
  assert.strictEqual(cinder.owner, null);
  assert.strictEqual(cinder.lockedUntil, 0, 'losing a planet to nobody does not lock it');
  assert.match(W.capture(g, 'cinder', 'cinder-1', 'ashen', t).reason, /already holds Cinder 1/);
  const far = cinder.sectors.find((s) => !s.capital && !s.links.includes('cinder-1'));
  assert.match(W.capture(g, 'cinder', far.id, 'ashen', t).reason, /isn't next to a sector you hold/);
  assert.ok(g.war.log.some((l) => l.text === 'Ashen Collective took Cinder 1 from the Terran Compact'));
  assert.ok(g.war.log.some((l) => l.text === 'Terran Compact lost control of Cinder'));
  takePlanet(g, 'cinder', 'ashen', t);
  const held = cinder.sectors.filter((s) => s.owner === 'ashen').length;
  assert.strictEqual(held, Math.ceil(0.75 * cinder.sectors.length), 'won with exactly 75%');
  assert.strictEqual(cinder.lockedUntil, t + W.LOCK_MS);
  assert.ok(g.war.log.at(-1).text.startsWith('Cinder fell to the Ashen Collective'));
  const left = cinder.sectors.find((s) => s.owner === 'compact');
  assert.strictEqual(W.capture(g, 'cinder', left.id, 'ashen', t + 1000).reason, 'Cinder is locked for 7 more days');
  assert.strictEqual(W.capture(g, 'cinder', left.id, 'compact', t + W.LOCK_MS - 3600_000).reason, 'Cinder is locked for 1 more hour', 'nobody, owner or not');
  assert.ok(g.feed.some((f) => f.text.startsWith('Cinder fell')), 'the galaxy feed hears of it too');
  assert.ok(g.war.log.length <= 30);
});

test('fleets fly to Teal Prime, take up station, and win it orbital control', () => {
  const g = war('compact', 'ashen');
  G.claimBase(g, 'Nobody');
  assert.match(W.sendFleet(g, 'Nobody', 'teal-prime', null, 0).reason, /choose a faction first/);
  assert.match(W.sendFleet(g, 'Ghost', 'teal-prime', null, 0).reason, /no home planet/);
  assert.match(W.sendFleet(g, 'compact', 'teal-prime', null, 0).reason, /no ships/);
  g.bases.compact.navy = { corvette: 3, frigate: 1, destroyer: 0 };
  assert.match(W.sendFleet(g, 'compact', 'fortitude', null, 0).reason, /capital systems can't be contested/);
  assert.match(W.sendFleet(g, 'compact', 'nowhere', null, 0).reason, /no such system/);
  const { fleet } = W.sendFleet(g, 'compact', 'teal-prime', { corvette: 2, frigate: 0 }, 0);
  assert.deepStrictEqual(g.bases.compact.navy, { corvette: 1, frigate: 1, destroyer: 0 }, 'they leave the hangar');
  assert.deepStrictEqual(fleet.ships, { corvette: 2 });
  assert.strictEqual(fleet.faction, 'compact');
  assert.strictEqual(fleet.leg, N.travelMs({ corvette: 2 }) * 0.25, 'crossing your own system is quick');
  assert.strictEqual(fleet.arriveAt, 10_000);
  assert.strictEqual(W.warTick(g, 9_000), false, 'nothing to report while it flies');
  assert.strictEqual(g.war.orbital['teal-prime'].compact, 0, 'only fleets in orbit count');
  assert.strictEqual(W.warTick(g, 10_000), true);
  assert.strictEqual(fleet.status, 'stationed');
  assert.strictEqual(g.bases.compact.credits, 500 - 2 * W.FUEL_CREDITS, 'supplied as it takes station');
  assert.strictEqual(fleet.upkeepAt, 10_000 + W.UPKEEP_MS);
  assert.strictEqual(fleet.joining, undefined, 'alone in orbit: it holds it at once');
  assert.strictEqual(g.war.orbital['teal-prime'].compact, 1);
  assert.strictEqual(W.power({ corvette: 1, frigate: 1, destroyer: 1 }), 4 + 11 + 26);
  // A second faction arrives: it has no say until it has fought a round there...
  const frigate = station(g, 'ashen', { frigate: 1 }, 10_000);
  assert.strictEqual(frigate.joining, true);
  assert.deepStrictEqual([g.war.orbital['teal-prime'].compact, g.war.orbital['teal-prime'].ashen], [1, 0]);
  // ...then control splits by power: after the first round the Compact has a corvette left (4) and
  // the Ashen frigate its 11.
  W.warTick(g, g.war.battleAt['teal-prime']);
  assert.strictEqual(frigate.joining, undefined);
  assert.ok(Math.abs(g.war.orbital['teal-prime'].compact - 4 / 15) < 1e-9);
  assert.ok(Math.abs(g.war.orbital['teal-prime'].ashen - 11 / 15) < 1e-9);
  assert.strictEqual(W.warTick(g, g.war.battleAt['teal-prime'] - 1000), false, 'and stays put between ticks');
});

test('a fleet called home before every round never fights, never wins control, and pays every time it takes station', () => {
  const g = war('compact', 'ashen');
  g.bases.ashen.stock.fuel = 1000;
  station(g, 'ashen', { frigate: 3 });
  const e = g.bases.compact;
  e.navy.corvette = 10;
  e.stock.fuel = 0;
  e.credits = 1000;
  // Each time: in orbit, recalled 110 s later (before the round two minutes after they meet), home
  // 10 s after that, and straight back out.
  let t = 100_000;
  let control = 0;
  for (let i = 0; i < 4; i++) {
    const { fleet } = W.sendFleet(g, 'compact', 'teal-prime', null, t);
    W.warTick(g, fleet.arriveAt);
    assert.strictEqual(fleet.status, 'stationed');
    for (let at = fleet.arriveAt; at < fleet.arriveAt + 110_000; at += 5000) {
      W.warTick(g, at);
      control = Math.max(control, g.war.orbital['teal-prime'].compact);
    }
    assert.ok(W.recallFleet(g, 'compact', fleet.id, fleet.arriveAt + 110_000).ok);
    t = fleet.returnAt;
    W.warTick(g, t);
  }
  assert.strictEqual(control, 0, 'no say in the orbit without a fight');
  assert.ok(!g.war.log.some((l) => l.text.startsWith('Battle over')));
  assert.strictEqual(e.credits, 1000 - 4 * 10 * W.FUEL_CREDITS, '10 cells each time it took station');
  assert.strictEqual(e.navy.corvette, 10);
  assert.strictEqual(g.war.orbital['teal-prime'].ashen, 1);
});

test('fleets reach any system but a capital, a jump per lane from Teal Prime, and come home the same way', () => {
  const g = war('compact');
  assert.strictEqual(W.laneJumps(g, 'teal-prime', 'marrow'), 2, 'through Fortitude or Umbra');
  assert.strictEqual(W.laneJumps(g, 'teal-prime', 'drift'), 2);
  assert.strictEqual(W.laneJumps(g, 'comae', 'marrow'), 3);
  assert.strictEqual(W.laneJumps(g, 'comae', 'comae'), 0);
  g.bases.compact.navy = { corvette: 2, frigate: 1, destroyer: 1 };
  for (const id of ['fortitude', 'umbra', 'aurelia', 'comae']) assert.strictEqual(W.sendFleet(g, 'compact', id, null, 0).reason, "capital systems can't be contested");
  const marrow = W.sendFleet(g, 'compact', 'marrow', { corvette: 1 }, 0).fleet;
  assert.strictEqual(marrow.leg, N.travelMs({ corvette: 1 }) * 2);
  const drift = W.sendFleet(g, 'compact', 'drift', { destroyer: 1 }, 0).fleet;
  assert.strictEqual(drift.leg, 240_000, 'two jumps at speed 1');
  const home = W.sendFleet(g, 'compact', 'teal-prime', { frigate: 1 }, 0).fleet;
  assert.strictEqual(home.leg, N.travelMs({ frigate: 1 }) * 0.25, 'a quarter jump within the home system');
  W.warTick(g, marrow.arriveAt);
  assert.strictEqual(marrow.status, 'stationed');
  assert.strictEqual(g.war.orbital.marrow.compact, 1, 'Marrow Reach can be contested');
  assert.ok(W.recallFleet(g, 'compact', marrow.id, marrow.arriveAt + 1000).ok);
  assert.strictEqual(marrow.returnAt, marrow.arriveAt + 1000 + marrow.leg, 'the same leg home');
  assert.ok(W.recallFleet(g, 'compact', drift.id, 60_000).ok);
  assert.strictEqual(drift.returnAt, 120_000, 'turned round a quarter of the way there');
  W.warTick(g, marrow.returnAt);
  assert.deepStrictEqual(g.bases.compact.navy, { corvette: 2, frigate: 0, destroyer: 1 });
});

test('recalled fleets turn round and their ships rejoin the navy', () => {
  const g = war('compact');
  g.bases.compact.navy.frigate = 2;
  const { fleet } = W.sendFleet(g, 'compact', 'teal-prime', null, 0); // 15 s out
  assert.ok(W.recallFleet(g, 'compact', fleet.id, 5_000).ok);
  assert.strictEqual(fleet.returnAt, 10_000, 'back the way it came, as far as it got');
  assert.match(W.recallFleet(g, 'compact', fleet.id, 6_000).reason, /already on its way home/);
  assert.match(W.recallFleet(g, 'someone', fleet.id, 6_000).reason, /no such fleet/);
  W.warTick(g, 10_000);
  assert.strictEqual(g.bases.compact.navy.frigate, 2);
  assert.strictEqual(g.war.fleets.length, 0);
  // A stationed fleet takes the full leg home.
  const f2 = station(g, 'compact', { corvette: 1 }, 30_000);
  assert.ok(W.recallFleet(g, 'compact', f2.id, 100_000).ok);
  assert.strictEqual(f2.returnAt, 100_000 + f2.leg);
  W.warTick(g, f2.returnAt);
  assert.strictEqual(g.bases.compact.navy.corvette, 1);
});

test('fleet battles: a round every 2 minutes, lightest ships first, damage carried over, always the same', () => {
  const fight = () => {
    const g = war('compact', 'ashen');
    const c = station(g, 'compact', { corvette: 2 }, 0);
    const a = station(g, 'ashen', { frigate: 1 }, 0);
    const start = Math.max(c.arriveAt, a.arriveAt);
    W.warTick(g, start);
    assert.strictEqual(g.war.battleAt['teal-prime'], a.arriveAt + W.BATTLE_MS, 'the first round two minutes after they meet');
    W.warTick(g, g.war.battleAt['teal-prime'] - 1);
    assert.strictEqual(c.ships.corvette, 2, 'no shots yet');
    W.warTick(g, g.war.battleAt['teal-prime']);
    return { g, c, a };
  };
  const { g, c, a } = fight();
  // Round 1: two corvettes deal 2 x 2 x 3 = 12 to the frigate (30 hull); the frigate deals 15,
  // sinking one corvette (10) and leaving 5 on the next.
  assert.deepStrictEqual(c.ships, { corvette: 1 });
  assert.strictEqual(c.taken, 5);
  assert.strictEqual(a.taken, 12);
  assert.strictEqual(g.war.log.at(-1).text, 'Battle over Teal Prime: Compact lost 1 Corvette');
  // Round 2 finishes the Compact's fleet; the empty fleet is gone and its Builder told.
  W.warTick(g, g.war.battleAt['teal-prime']);
  assert.strictEqual(a.taken, 18);
  assert.ok(!g.war.fleets.includes(c));
  assert.ok(g.bases.compact.alerts.some((x) => x.text === 'Your fleet over Teal Prime was destroyed'));
  assert.strictEqual(g.war.battleAt['teal-prime'], undefined, 'one side left: no more rounds');
  assert.strictEqual(g.war.orbital['teal-prime'].ashen, 1);
  assert.deepStrictEqual(fight().g.war.fleets, fight().g.war.fleets, 'the same battle always ends the same way');

  // Three sides: each splits its damage over the others by their power.
  const h = war('compact', 'ashen', 'luminar');
  const d = station(h, 'compact', { destroyer: 1 }, 0);
  const f1 = station(h, 'ashen', { frigate: 1 }, 0);
  const f2 = station(h, 'luminar', { frigate: 1 }, 0);
  W.warTick(h, 100_000);
  W.warTick(h, h.war.battleAt['teal-prime']);
  assert.strictEqual(f1.taken, Math.round((36 * 11 / 22 + 15 * 11 / 37) * 100) / 100);
  assert.strictEqual(f2.taken, f1.taken);
  assert.strictEqual(d.taken, Math.round((2 * 15 * 26 / 37) * 100) / 100);
});

test('stationed fleets eat fuel cells, then credits, and come home when neither is left', () => {
  const g = war('compact');
  const e = g.bases.compact;
  e.stock.fuel = 5;
  e.credits = 100;
  const fl = station(g, 'compact', { frigate: 2 }, 0); // 4 cells as it takes station, then every 10 minutes
  assert.strictEqual(e.stock.fuel, 1);
  assert.strictEqual(e.credits, 100);
  assert.strictEqual(fl.upkeepAt, fl.arriveAt + W.UPKEEP_MS);
  W.warTick(g, fl.upkeepAt);
  assert.strictEqual(e.stock.fuel, 0, 'the last cell...');
  assert.strictEqual(e.credits, 40, '...and 20 credits for each of the other three');
  const due = fl.upkeepAt;
  W.warTick(g, due);
  assert.strictEqual(fl.status, 'returning');
  assert.strictEqual(e.credits, 40, 'nothing taken when it can\'t be paid');
  assert.strictEqual(e.alerts.at(-1).text, 'Your fleet over Teal Prime ran out of supplies and is coming home');
  W.warTick(g, fl.returnAt);
  assert.strictEqual(e.navy.frigate, 2);
  assert.deepStrictEqual(W.UPKEEP, { corvette: 1, frigate: 2, destroyer: 4 });
});

test('the galaxy tick runs the war and says when it changed', () => {
  const g = war('compact');
  g.bases.compact.navy.corvette = 1;
  W.sendFleet(g, 'compact', 'teal-prime', null, 0);
  assert.strictEqual(G.tick(g, 5_000), false);
  assert.strictEqual(G.tick(g, 10_000), true, 'the fleet arriving is news');
  assert.strictEqual(g.war.orbital['teal-prime'].compact, 1);
});
