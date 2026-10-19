// The Coma Conglomerate's AI director: how it weighs the player factions, what it sends where, and
// what admins can make it do.

const test = require('node:test');
const assert = require('node:assert');
const D = require('../director');
const G = require('../galaxy');
const N = require('../navy');
const W = require('../war');

const T0 = 1_000_000;

// A galaxy with a Builder of each of the given factions, named after it.
function galaxy(...factions) {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  for (const f of factions) {
    G.claimBase(g, f);
    assert.ok(G.chooseFaction(g, 'builder', f, f, 0).ok);
  }
  return g;
}

// The director paused (so only the test gives it turns), with every faction's intensity fixed.
function steady(g, overrides = { compact: 1, ashen: 1, luminar: 1 }) {
  assert.ok(D.set(g, { paused: true, overrides }, T0).ok);
}

// A Builder's ships, from a navy topped up with them, on their way to a system.
function send(g, owner, systemId, ships, now = T0) {
  for (const [id, n] of Object.entries(ships)) g.bases[owner].navy[id] += n;
  const r = W.sendFleet(g, owner, systemId, ships, now);
  assert.ok(r.ok, r.reason);
  return r.fleet;
}

function near(actual, expected, what) {
  assert.ok(Math.abs(actual - expected) < 1e-9, `${what}: ${actual} is not ${expected}`);
}

const ships = (g, systemId) => D.armadas(g, systemId).map((fl) => fl.ships);
const round3 = (x) => Math.round(x * 1000) / 1000;

test('a new galaxy has a director: unpaused, scale 1, automatic, pushing in every contested system', () => {
  const g = G.newGalaxy();
  const d = g.director;
  assert.deepStrictEqual(Object.keys(d), ['paused', 'scale', 'overrides', 'posture', 'strength', 'auto', 'intensity', 'runAt']);
  assert.deepStrictEqual([d.paused, d.scale], [false, 1]);
  assert.deepStrictEqual(d.overrides, { compact: null, ashen: null, luminar: null });
  assert.deepStrictEqual(d.posture, { 'teal-prime': 'push', marrow: 'push', drift: 'push' });
  assert.ok(d.runAt > Date.now(), 'its first turn is a few minutes off');
  assert.strictEqual(d.auto.luminar, 1, 'Halcyon is the biggest planet to start with');
  assert.deepStrictEqual(d.intensity, d.auto);
  assert.deepStrictEqual(D.PLAYERS, ['compact', 'ashen', 'luminar']);
});

test('strength: half the ground, three tenths the orbits, a fifth the active players; the strongest gets intensity 1', () => {
  const g = galaxy('compact', 'ashen');
  const ground = g.war.planets.filter((p) => !p.capital).flatMap((p) => p.sectors).length;
  assert.strictEqual(ground, 159);
  W.warTick(g, send(g, 'compact', 'teal-prime', { frigate: 2 }).arriveAt); // all of Teal Prime's orbit
  W.warTick(g, send(g, 'ashen', 'marrow', { frigate: 1 }).arriveAt); // and all of Marrow Reach's
  // Who's active: seen in the last day.
  g.bases.compact.seenAt = T0 - 1000;
  g.bases.ashen.seenAt = T0 - D.ACTIVE_MS; // a day ago is too long
  for (const [name, f, at] of [['Pia', 'luminar', T0], ['Cy', 'compact', T0 - 5000], ['Ghost', 'ashen', undefined]]) {
    G.chooseFaction(g, 'explorer', name, f, 0);
    if (at !== undefined) g.pilots[name].seenAt = at;
  }
  const s = D.strengths(g, T0);
  near(s.compact, 0.5 * (18 / 159) + 0.3 * ((1 + 0 + 0) / 3) + 0.2 * (2 / 3), 'compact');
  near(s.ashen, 0.5 * (14 / 159) + 0.3 * ((0 + 1 + 0) / 3) + 0, 'ashen');
  near(s.luminar, 0.5 * (25 / 159) + 0 + 0.2 * (1 / 3), 'luminar');
  D.assess(g, T0);
  const d = g.director;
  assert.deepStrictEqual(d.strength, { compact: round3(s.compact), ashen: round3(s.ashen), luminar: round3(s.luminar) });
  assert.strictEqual(d.auto.compact, 1, 'the strongest is pushed hardest');
  assert.strictEqual(d.auto.ashen, round3(0.15 + (0.85 * s.ashen) / s.compact));
  assert.strictEqual(d.auto.luminar, round3(0.15 + (0.85 * s.luminar) / s.compact));
  assert.deepStrictEqual(d.intensity, d.auto, 'no overrides: the automatic levels are used');

  // Nobody holds ground, nobody is in orbit, nobody is about: every faction gets the floor.
  const h = G.newGalaxy();
  for (const p of h.war.planets) if (!p.capital) for (const x of p.sectors) x.owner = null;
  D.assess(h, T0);
  assert.deepStrictEqual(h.director.strength, { compact: 0, ashen: 0, luminar: 0 });
  assert.deepStrictEqual(h.director.auto, { compact: 0.15, ashen: 0.15, luminar: 0.15 });
});

test('armadas are made greedily: destroyers, then frigates, then corvettes to cover the rest', () => {
  assert.deepStrictEqual(D.compose(100), { destroyer: 3, frigate: 2 });
  assert.deepStrictEqual(D.compose(30), { destroyer: 1, corvette: 1 });
  assert.deepStrictEqual(D.compose(25), { frigate: 2, corvette: 1 });
  assert.deepStrictEqual(D.compose(10), { corvette: 3 });
  assert.deepStrictEqual(D.compose(25, false), { frigate: 2 }, 'never over, when it must not be');
  assert.deepStrictEqual(D.compose(3, false), {});
});

test('push: the strongest faction there times its intensity, a patrol where there is none, armadas only', () => {
  const g = galaxy('compact', 'ashen');
  steady(g, { compact: 1, ashen: 0.5, luminar: 1 });
  // An admin's own Coma fleet is not the director's: it doesn't count towards Coma's power.
  G.claimBase(g, 'Akane');
  G.chooseFaction(g, 'builder', 'Akane', 'coma', 0, { admin: true });
  send(g, 'Akane', 'teal-prime', { destroyer: 5 });
  send(g, 'compact', 'teal-prime', { destroyer: 2 }); // 52 at intensity 1
  send(g, 'ashen', 'teal-prime', { destroyer: 3 }); // 78 at 0.5: 39
  send(g, 'compact', 'drift', { corvette: 1 }); // 4: no more than a corvette short, so nothing goes
  assert.ok(D.run(g, T0));
  assert.deepStrictEqual(ships(g, 'teal-prime'), [{ destroyer: 2 }], "matched to the Compact's 52, flying or not");
  assert.deepStrictEqual(ships(g, 'marrow'), [{ frigate: 2, corvette: 1 }], 'a patrol of 30 x the mean intensity (0.83): 25');
  assert.deepStrictEqual(ships(g, 'drift'), []);
  const [tp] = D.armadas(g, 'teal-prime');
  const [mr] = D.armadas(g, 'marrow');
  assert.deepStrictEqual([tp.owner, tp.faction, tp.ai, tp.manual, tp.status, tp.taken, tp.upkeepAt], [null, 'coma', true, undefined, 'flying', 0, 0]);
  assert.strictEqual(tp.leg, N.travelMs({ destroyer: 1 }), 'one jump from Comae');
  assert.strictEqual(mr.leg, N.travelMs({ frigate: 1 }) * 3, 'three jumps from Comae, at the frigates\' speed');
  assert.strictEqual(tp.arriveAt, T0 + tp.leg);
  const log = g.war.log.map((l) => l.text);
  assert.ok(log.includes('A Coma armada of 2 Destroyers is heading for Teal Prime'));
  assert.ok(log.includes('A Coma armada of 2 Frigates and 1 Corvette is heading for Marrow Reach'));
  assert.ok(!log.some((t) => /\d\.\d|intensity|%/.test(t)), 'the log never gives the director away');
  assert.strictEqual(g.director.runAt, T0 + D.DIRECTOR_MS);

  // Its next turn, with nothing changed, sends nothing more.
  const n = g.war.fleets.length;
  D.run(g, T0 + D.DIRECTOR_MS);
  assert.strictEqual(g.war.fleets.length, n);
  // Twice the scale: twice the target everywhere.
  assert.ok(D.set(g, { scale: 2 }, T0).ok);
  D.run(g, T0 + 2 * D.DIRECTOR_MS);
  assert.deepStrictEqual(ships(g, 'teal-prime'), [{ destroyer: 2 }, { destroyer: 2 }]);
  assert.deepStrictEqual(ships(g, 'marrow'), [{ frigate: 2, corvette: 1 }, { frigate: 2, corvette: 1 }]);
  assert.deepStrictEqual(ships(g, 'drift'), [{ corvette: 2 }], 'now 8 needed: more than a corvette short');
});

test('push: too strong somewhere, its smallest armadas go home while what stays is enough; admins\' armadas stay', () => {
  const g = galaxy('compact');
  steady(g);
  const big = send(g, 'compact', 'teal-prime', { destroyer: 2 }); // 52
  D.run(g, T0);
  const frigate = send(g, 'compact', 'teal-prime', { frigate: 1 }); // 63
  D.run(g, T0);
  const corvettes = send(g, 'compact', 'teal-prime', { corvette: 2 }); // 71
  D.run(g, T0);
  assert.deepStrictEqual(ships(g, 'teal-prime'), [{ destroyer: 2 }, { frigate: 1 }, { corvette: 2 }]);
  const manual = D.armada(g, 'teal-prime', 10, T0).fleet; // 3 corvettes, 12
  assert.strictEqual(manual.manual, true);
  assert.strictEqual(D.armadaPower(g, 'teal-prime'), 83);
  // Down to the Compact's 52: 83 is over 1.25 x 52, so the 8 and the 11 go; the 52 has to stay.
  for (const fl of [frigate, corvettes]) W.recallFleet(g, 'compact', fl.id, T0);
  D.run(g, T0);
  assert.deepStrictEqual(ships(g, 'teal-prime'), [{ destroyer: 2 }, { corvette: 3 }]);
  assert.strictEqual(g.war.log.at(-1).text, 'The Coma armada heading for Teal Prime is turning back');
  // The Compact leaves: a patrol of 30 is all it needs, but 64 can't lose its 52 and keep 30.
  W.recallFleet(g, 'compact', big.id, T0);
  D.run(g, T0);
  assert.deepStrictEqual(ships(g, 'teal-prime'), [{ destroyer: 2 }, { corvette: 3 }]);
  // Nothing at all needed (scale 0): every armada the director sent comes home, but not the admin's.
  D.set(g, { scale: 0 }, T0);
  D.run(g, T0);
  assert.deepStrictEqual(D.armadas(g, 'teal-prime'), [manual]);
});

test('hold sends and recalls nothing; withdraw calls every armada home at once; home, they stand down', () => {
  const g = galaxy('compact');
  steady(g);
  D.run(g, T0); // patrols everywhere
  assert.deepStrictEqual(ships(g, 'drift'), [{ destroyer: 1, corvette: 1 }]);
  const manual = D.armada(g, 'drift', 100, T0).fleet;
  assert.ok(D.set(g, { posture: { drift: 'hold', marrow: 'hold' }, scale: 0 }, T0).ok);
  D.run(g, T0 + 1000);
  assert.strictEqual(D.armadas(g, 'drift').length, 2, 'hold: 130 where nothing is needed, and none go home');
  assert.strictEqual(D.armadas(g, 'marrow').length, 1);
  assert.strictEqual(D.armadas(g, 'teal-prime').length, 0, 'push: not needed, so home');
  assert.ok(D.recall(g, D.armadas(g, 'marrow')[0].id, T0 + 1000).ok);
  D.set(g, { scale: 1 }, T0 + 2000);
  D.run(g, T0 + 2000);
  assert.strictEqual(D.armadas(g, 'marrow').length, 0, 'hold: nothing new either...');
  assert.strictEqual(D.armadas(g, 'teal-prime').length, 1, '...while a system it pushes in gets its patrol back');
  // Withdraw takes effect at once, paused or not, the admin's armada too.
  W.warTick(g, T0 + 200_000); // the drift armadas are in orbit by now
  assert.strictEqual(manual.status, 'stationed');
  assert.ok(D.set(g, { posture: { drift: 'withdraw' } }, T0 + 200_000).ok);
  assert.deepStrictEqual(D.armadas(g, 'drift'), []);
  assert.strictEqual(manual.status, 'returning');
  assert.strictEqual(manual.returnAt, T0 + 200_000 + manual.leg);
  assert.ok(g.war.log.some((l) => l.text === 'The Coma armada over The Drift is withdrawing'));
  assert.match(D.armada(g, 'drift', 50, T0).reason, /withdrawing from The Drift: set it to push or hold first/);
  // Home at Comae, an armada disbands: its ships go to nobody.
  const navies = JSON.stringify(Object.values(g.bases).map((e) => e.navy)) + JSON.stringify(g.navy);
  W.warTick(g, manual.returnAt);
  assert.ok(!g.war.fleets.includes(manual));
  assert.strictEqual(JSON.stringify(Object.values(g.bases).map((e) => e.navy)) + JSON.stringify(g.navy), navies);
  assert.ok(g.war.log.some((l) => l.text === 'The Coma armada from The Drift is back at Comae'));
  D.run(g, manual.returnAt);
  assert.deepStrictEqual(D.armadas(g, 'drift'), [], 'and it stays out while withdrawn');
});

test('the cap: all armadas together under 600 x scale, the strongest faction\'s systems served first', () => {
  const setup = () => {
    const g = galaxy('compact', 'ashen');
    steady(g);
    send(g, 'compact', 'teal-prime', { destroyer: 20 }); // 520
    send(g, 'ashen', 'marrow', { destroyer: 10 }); // 260
    return g;
  };
  const g = setup();
  D.run(g, T0);
  assert.ok(g.director.strength.compact > g.director.strength.ashen);
  assert.deepStrictEqual(ships(g, 'teal-prime'), [{ destroyer: 20 }], 'the Compact first: all 520');
  assert.deepStrictEqual(ships(g, 'marrow'), [{ destroyer: 3 }], 'then as much of the 260 as fits under the cap');
  assert.deepStrictEqual(ships(g, 'drift'), [], 'and no room left for a patrol');
  const total = g.war.fleets.filter((fl) => fl.ai).reduce((a, fl) => a + W.power(fl.ships), 0);
  assert.ok(total <= D.ARMADA_CAP, `${total}`);
  assert.strictEqual(D.ARMADA_CAP, 600);
  // Make the Ashen the stronger, and Marrow Reach is served first.
  const h = setup();
  for (const x of W.planet(h, 'rift').sectors) x.owner = 'ashen';
  for (const x of W.planet(h, 'scar').sectors) x.owner = 'ashen';
  D.run(h, T0);
  assert.ok(h.director.strength.ashen > h.director.strength.compact);
  assert.deepStrictEqual(ships(h, 'marrow'), [{ destroyer: 10 }]);
  assert.deepStrictEqual(ships(h, 'teal-prime'), [{ destroyer: 13 }]);
  // At half the scale the cap is 300: with 598 out, nothing new goes anywhere.
  D.set(h, { scale: 0.5 }, T0);
  D.run(h, T0 + 1000);
  assert.deepStrictEqual(ships(h, 'drift'), [], 'not even a patrol');
  assert.strictEqual(h.war.fleets.filter((fl) => fl.ai && fl.status !== 'returning').length, 2);
});

test('armadas need no supplies, and fight Builder fleets like any other', () => {
  const g = galaxy('compact');
  steady(g);
  const armada = D.armada(g, 'teal-prime', 10, T0).fleet; // 3 corvettes
  assert.deepStrictEqual(armada.ships, { corvette: 3 });
  W.warTick(g, armada.arriveAt);
  assert.strictEqual(armada.status, 'stationed');
  assert.strictEqual(armada.upkeepAt, 0);
  assert.ok(g.war.log.some((l) => l.text === 'The Coma armada arrived over Teal Prime'));
  assert.strictEqual(g.war.orbital['teal-prime'].coma, 1);
  const feed = g.feed.length;
  W.warTick(g, armada.arriveAt + 3 * W.UPKEEP_MS);
  assert.strictEqual(armada.status, 'stationed', 'still there, unsupplied, hours on');
  assert.strictEqual(g.feed.length, feed, 'and nothing about running out');
  // A Compact destroyer comes to fight it.
  g.bases.compact.stock.fuel = 100;
  const fl = send(g, 'compact', 'teal-prime', { destroyer: 1 }, armada.arriveAt + 3 * W.UPKEEP_MS);
  W.warTick(g, fl.arriveAt);
  assert.ok(g.war.log.at(-1).text.startsWith('Fleets of the Terran Compact and the Coma Conglomerate met over Teal Prime'));
  W.warTick(g, g.war.battleAt['teal-prime']);
  // The destroyer deals 12 x 3 = 36 and sinks all three corvettes; they deal 3 x 2 x 3 = 18.
  assert.strictEqual(fl.taken, 18);
  assert.ok(!g.war.fleets.includes(armada));
  assert.ok(g.war.log.some((l) => l.text === 'Battle over Teal Prime: Coma lost 3 Corvettes'));
  assert.ok(g.war.log.some((l) => l.text === 'The Coma armada over Teal Prime was destroyed'));
  assert.ok(!g.bases.compact.alerts.some((a) => /destroyed/.test(a.text)));
  assert.strictEqual(g.war.orbital['teal-prime'].compact, 1);
  // And the other way: armadas sink Builder fleets, and their Builders hear of it.
  const h = galaxy('ashen');
  steady(h);
  const small = send(h, 'ashen', 'teal-prime', { corvette: 1 });
  W.warTick(h, small.arriveAt);
  const big = D.armada(h, 'teal-prime', 100, small.arriveAt).fleet;
  W.warTick(h, big.arriveAt);
  W.warTick(h, h.war.battleAt['teal-prime']);
  assert.ok(!h.war.fleets.includes(small));
  assert.strictEqual(h.bases.ashen.alerts.at(-1).text, 'Your fleet over Teal Prime was destroyed');
  assert.strictEqual(h.war.orbital['teal-prime'].coma, 1);
});

test('the director runs every 5 minutes from the galaxy tick, unless paused, and always the same way', () => {
  const play = () => {
    const g = galaxy('compact', 'ashen');
    g.director.runAt = T0;
    send(g, 'compact', 'teal-prime', { destroyer: 3, frigate: 1 });
    send(g, 'ashen', 'drift', { frigate: 4, corvette: 2 });
    g.bases.compact.seenAt = T0;
    for (let t = T0; t <= T0 + 4 * D.DIRECTOR_MS; t += 5000) G.tick(g, t);
    return g;
  };
  const g = play();
  assert.strictEqual(g.director.runAt, T0 + 5 * D.DIRECTOR_MS, 'five turns, one every 5 minutes');
  assert.ok(g.war.fleets.some((fl) => fl.ai));
  const a = play();
  assert.deepStrictEqual(a.war, g.war, 'the same galaxy and clock: the same war');
  assert.deepStrictEqual(a.director, g.director);
  // Paused, it does nothing.
  const h = galaxy('compact');
  h.director.runAt = T0;
  D.set(h, { paused: true }, T0);
  assert.strictEqual(G.tick(h, T0 + D.DIRECTOR_MS), false);
  assert.strictEqual(D.tick(h, T0 + 10 * D.DIRECTOR_MS), false);
  assert.ok(!h.war.fleets.some((fl) => fl.ai));
  D.set(h, { paused: false }, T0 + 10 * D.DIRECTOR_MS);
  assert.ok(h.war.fleets.some((fl) => fl.ai), 'unpaused, it takes its turn at once');
  assert.strictEqual(h.director.runAt, T0 + 11 * D.DIRECTOR_MS);
});

test('director_set checks everything first; overrides fix a faction\'s intensity; intensityFor is the scale times it', () => {
  const g = galaxy('compact');
  D.set(g, { paused: true }, T0);
  const d = g.director;
  const bad = [
    [{ paused: 'yes' }, 'paused is true or false'],
    [{ scale: 2.5 }, 'the scale runs from 0 to 2'],
    [{ scale: -1 }, 'the scale runs from 0 to 2'],
    [{ scale: 'max' }, 'the scale runs from 0 to 2'],
    [{ overrides: 1 }, 'overrides are a level for each faction'],
    [{ overrides: { coma: 1 } }, "the Coma Conglomerate is the director's own faction"],
    [{ overrides: { pirates: 1 } }, 'no such faction'],
    [{ overrides: { ashen: 1.5 } }, 'an override is a level from 0 to 1, or null for automatic'],
    [{ posture: { fortitude: 'push' } }, "capital systems can't be contested"],
    [{ posture: { nowhere: 'push' } }, 'no such system'],
    [{ posture: { marrow: 'attack' } }, 'a posture is push, hold or withdraw'],
    [{ scale: 1.5, overrides: { ashen: 7 } }, 'an override is a level from 0 to 1, or null for automatic'],
  ];
  for (const [changes, reason] of bad) assert.strictEqual(D.set(g, changes, T0).reason, reason, JSON.stringify(changes));
  assert.strictEqual(d.scale, 1, 'a refused change changes nothing');
  assert.ok(D.set(g, { scale: 1.5, overrides: { ashen: 0.4 }, posture: { marrow: 'hold' } }, T0).ok);
  assert.deepStrictEqual([d.scale, d.overrides.ashen, d.intensity.ashen, d.posture.marrow], [1.5, 0.4, 0.4, 'hold']);
  assert.notStrictEqual(d.auto.ashen, 0.4, 'the automatic level is still worked out');
  // The seam for phase 3: how hard Coma's ground forces fight a faction.
  assert.strictEqual(D.intensityFor(g, 'ashen'), 0, 'paused: Coma fields nothing of its own');
  D.set(g, { paused: false }, T0);
  assert.strictEqual(D.intensityFor(g, 'ashen'), 1.5 * 0.4);
  assert.strictEqual(D.intensityFor(g, 'coma'), 0);
  assert.ok(D.set(g, { overrides: { ashen: null } }, T0).ok);
  assert.strictEqual(d.intensity.ashen, d.auto.ashen, 'back to automatic');
  assert.strictEqual(D.intensityFor(g, 'ashen'), 1.5 * d.auto.ashen);
});

test('admins send and recall armadas by hand', () => {
  const g = galaxy('compact');
  steady(g);
  assert.strictEqual(D.armada(g, 'nowhere', 50, T0).reason, 'no such system');
  assert.strictEqual(D.armada(g, 'comae', 50, T0).reason, "capital systems can't be contested");
  for (const p of [9, 401, '50', null]) assert.strictEqual(D.armada(g, 'marrow', p, T0).reason, "an armada's power is 10 to 400");
  const r = D.armada(g, 'marrow', 400, T0);
  assert.ok(r.ok);
  assert.deepStrictEqual(r.fleet.ships, { destroyer: 15, corvette: 3 }, 'about 400: 402');
  assert.strictEqual(r.fleet.leg, N.travelMs({ destroyer: 1 }) * 3);
  assert.strictEqual(g.war.log.at(-1).text, 'A Coma armada of 15 Destroyers and 3 Corvettes is heading for Marrow Reach');
  assert.strictEqual(D.recall(g, 999, T0).reason, 'no such armada');
  const builder = send(g, 'compact', 'teal-prime', { corvette: 1 });
  assert.strictEqual(D.recall(g, builder.id, T0).reason, 'no such armada', "a Builder's fleet is theirs");
  assert.ok(D.recall(g, r.fleet.id, T0 + 60_000).ok);
  assert.strictEqual(r.fleet.returnAt, T0 + 120_000);
  assert.strictEqual(g.war.log.at(-1).text, 'The Coma armada heading for Marrow Reach is turning back');
  assert.strictEqual(D.recall(g, r.fleet.id, T0 + 60_000).reason, 'that armada is already on its way home');
  assert.strictEqual(W.recallFleet(g, 'compact', r.fleet.id, T0).reason, 'no such fleet', 'and Builders can\'t recall armadas');
});
