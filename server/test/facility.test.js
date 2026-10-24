// Facility Battles: Pick 10 classes, the maps, teams and AI fill, shots and cover, kill streaks,
// the four rule sets, reinforcements, the facility's doors, turrets and power plant, and matchmaking.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const FC = require('../facility');
const G = require('../galaxy');
const W = require('../war');

function match(opts = {}) {
  return FC.newFacility({ planet: 'cinder', planetName: 'Cinder', attacker: 'ashen', defender: 'compact', seed: 5, rule: 'tdm', map: 3, ...opts });
}
const ais = (f, side) => [...f.bodies.values()].filter((b) => b.ai && b.side === side);
const run = (f, s) => FC.step(f, s);
// Every AI trooper stands still and harmless far away (so a test can set up a fight).
// (Call it after adding pilots: they change who's on each side.)
function park(f) {
  let i = 0;
  for (const b of f.bodies.values()) {
    if (!b.ai) continue;
    Object.assign(b, { x: 2 + (i % 10) * 0.9, z: 78 - Math.floor(i / 10) * 0.9, alive: false, respawnAt: Infinity, hitAt: 1e9 });
    i++;
  }
}

test('Pick 10: a class is at most 10 items, one primary and secondary, attachments on a primary, 3 attachments and 3 perks at most', () => {
  for (const c of Object.values(FC.DEFAULT_CLASSES)) assert.ok(FC.checkClass(c.items).ok, c.name);
  assert.match(FC.checkClass(['rifle', 'smg']).reason, /one primary/);
  assert.match(FC.checkClass(['pistol', 'scope']).reason, /primary weapon/);
  assert.match(FC.checkClass(['frag', 'stim']).reason, /needs a weapon/);
  assert.match(FC.checkClass(['rifle', 'scope', 'extmag', 'fastmag', 'suppressor']).reason, /three attachments/);
  assert.match(FC.checkClass(['rifle', 'lightweight', 'armor', 'ghost', 'hardline']).reason, /three perks/);
  assert.match(FC.checkClass(['rifle', 'rifle']).reason, /once/);
  assert.match(FC.checkClass(['railgun']).reason, /no such item/, 'power weapons only come from drops');
  assert.match(FC.checkClass(['rifle', 'scope', 'extmag', 'fastmag', 'pistol', 'lightweight', 'armor', 'ghost', 'frag', 'stim', 'launcher']).reason, /10 points/);
  // Kept on the pilot, up to three, and used by name.
  const rec = {};
  assert.ok(FC.saveClass(rec, 0, 'Breacher', ['shotgun', 'extmag', 'pistol', 'lightweight', 'armor', 'frag']).ok);
  assert.ok(!FC.saveClass(rec, 3, 'Too many', ['rifle']).ok);
  assert.strictEqual(FC.classOf('custom:0', rec.loadouts).name, 'Breacher');
  assert.strictEqual(FC.classOf('custom:2', rec.loadouts).id, 'assault', 'an empty slot falls back to Assault');
});

test("maps: a planet's rotation is three of the defending faction's maps and the generic ones; every spot can be reached", () => {
  const r = FC.rotation('cinder', 'compact');
  assert.strictEqual(r.length, 4);
  assert.deepStrictEqual(r.slice(0, 3).map((m) => m.name), ['Terran Compound', 'Terran Foundry', 'Terran Reactor']);
  assert.strictEqual(r[3].name, 'Proving Grounds');
  assert.deepStrictEqual(FC.rotation('cinder', 'compact').map((m) => m.id), r.map((m) => m.id), 'the same every match');
  for (const m of [...r, ...FC.rotation('vesper', 'ashen')]) {
    const f = match();
    Object.assign(f, { map: m, doors: m.doors.map(() => false) });
    f.nav = FC.navGrid(f);
    f.flows = new Map();
    const from = FC.flowTo(f, FC.cellOf(...m.spawns.a[0]));
    const spots = [...m.spawns.a, ...m.spawns.d, ...m.hills, ...m.points, m.flags.a, m.flags.d, ...m.holds, ...m.drops, ...m.turrets, ...(m.plant ? [m.plant] : [])];
    for (const [x, z] of spots) assert.ok(from[FC.cellOf(x, z)] >= 0, `${m.name}: (${x}, ${z}) can't be reached`);
  }
});

test('teams: AI troopers fill both sides to at least 4; pilots take their places; a fortress world adds reinforcements', () => {
  const f = match();
  assert.deepStrictEqual([ais(f, 'a').length, ais(f, 'd').length], [4, 4]);
  for (const n of ['A1', 'A2', 'A3', 'A4', 'A5']) FC.addPilot(f, n, 'a');
  assert.deepStrictEqual([ais(f, 'a').length, ais(f, 'd').length], [0, 5], 'five pilots: 5 against 5');
  FC.removePilot(f, 'A5');
  assert.strictEqual(ais(f, 'd').length, 4);
  // Reinforcements: 12 a slot (5 a side now), kept when a side shrinks again.
  assert.deepStrictEqual(f.reinforcements, { a: 5 * FC.REINFORCEMENTS, d: 5 * FC.REINFORCEMENTS });
  assert.strictEqual(match({ fortress: true }).reinforcements.d, 4 * FC.REINFORCEMENTS + FC.FORTRESS_EXTRA);
  // Each match plays one of the four rule sets.
  const rules = new Set(Array.from({ length: 30 }, (_, i) => i + 1).map((seed) => FC.newFacility({ planet: 'cinder', attacker: 'ashen', defender: 'compact', seed }).rule));
  assert.deepStrictEqual([...rules].sort(), Object.keys(FC.RULES).sort());
});

test("shots: the server checks the rate and magazine, walls stop them; Halo's precision headshots finish a body whose shield is down, a sniper's kills outright", () => {
  const f = match();
  const a = FC.addPilot(f, 'A', 'a', [], 'assault');
  park(f);
  const e = ais(f, 'd')[0];
  Object.assign(a, { x: 10, z: 30, alive: true });
  Object.assign(e, { x: 10, z: 40, alive: true, respawnAt: 0, shield: 0, hp: 100, hitAt: 1e9 });
  run(f, 0.2);
  Object.assign(e, { x: 10, z: 40 });
  // The rifle is no precision weapon: a headshot is a body shot.
  FC.fire(f, 'A', { dx: 0, dy: -0.06, dz: 1 });
  assert.strictEqual(e.hp, 100 - FC.WEAPONS.rifle.damage);
  run(f, 0.2);
  Object.assign(e, { x: 10, z: 40, hp: 100 });
  FC.fire(f, 'A', { dx: 0, dy: 0.0, dz: 1 });
  assert.strictEqual(e.hp, 100 - FC.WEAPONS.rifle.damage, 'no bonus for an automatic');
  // Too fast: the second shot doesn't count.
  Object.assign(e, { hp: 100 });
  FC.fire(f, 'A', { dx: 0, dy: -0.06, dz: 1 });
  assert.strictEqual(e.hp, 100);
  // The pistol (precision): a headshot with the shield up is a hit like any other; with it down, a kill.
  run(f, 0.4);
  FC.switchTo(f, 'A', { weapon: 'secondary' });
  Object.assign(e, { x: 10, z: 40, hp: 100, shield: 50 });
  FC.fire(f, 'A', { dx: 0, dy: 0.0, dz: 1 });
  assert.deepStrictEqual([e.hp, e.shield], [100, 25]);
  run(f, 0.4);
  Object.assign(e, { x: 10, z: 40, shield: 0 });
  FC.fire(f, 'A', { dx: 0, dy: 0.0, dz: 1 });
  assert.strictEqual(e.alive, false, 'the headshot finished it');
  assert.ok(a.medals.headshot >= 1);
  // A sniper's headshot kills through a full shield.
  const m = FC.addPilot(f, 'M', 'a', [], 'marksman');
  m.want = 'marksman';
  Object.assign(e, { alive: true, x: 7, z: 40, hp: 100, shield: 50, respawnAt: Infinity });
  Object.assign(m, { alive: true, x: 7, z: 30, lastShot: -10 });
  FC.fire(f, 'M', { dx: 0, dy: 0.0, dz: 1 });
  assert.strictEqual(e.alive, false);
  // A wall in the way stops it (Proving Grounds' cover [20, 20, 4, 4, 3]).
  run(f, 0.4);
  FC.switchTo(f, 'A', { weapon: 'primary' });
  Object.assign(a, { x: 20, z: 14 });
  Object.assign(e, { alive: true, x: 20, z: 26, hp: 100, respawnAt: Infinity });
  const r = FC.fire(f, 'A', { dx: 0, dy: -0.05, dz: 1 });
  assert.strictEqual(r.hits, 0);
  assert.strictEqual(e.hp, 100);
  // An empty magazine won't fire; a reload fills it from the reserve after the reload time.
  const g = a.guns.primary;
  g.mag = 0;
  run(f, 0.2);
  assert.match(FC.fire(f, 'A', { dx: 0, dy: 0, dz: 1 }).reason, /reload/);
  FC.reload(f, 'A');
  run(f, g.reloadS - 0.3);
  assert.strictEqual(g.mag, 0);
  run(f, 0.5);
  assert.strictEqual(g.mag, g.magMax);
});

test('the Dance: the shield comes back after a short delay (not while sprinting), health after a longer one; melee rounds off gun and grenade', () => {
  const f = match();
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  Object.assign(a, { x: 10, z: 10, alive: true, moveT: f.t });
  FC.hurt(f, a, a.shieldMax + 30, null); // the shield gone, and 30 health
  assert.deepStrictEqual([a.shield, a.hp], [0, 70]);
  run(f, 3.5);
  assert.deepStrictEqual([a.shield, a.hp], [0, 70], 'nothing comes back at once');
  run(f, 1);
  assert.ok(a.shield > 0, 'the shield, after its delay');
  assert.strictEqual(a.hp, 70, 'health still waiting');
  run(f, 3);
  assert.strictEqual(a.shield, a.shieldMax);
  assert.ok(a.hp > 70, 'and then health');
  // Sprinting holds the shield's recharge off.
  FC.hurt(f, a, 30, null);
  run(f, 4.5);
  let x = a.x;
  for (let i = 0; i < 20; i++) {
    x += 0.7; // 7 m/s
    FC.move(f, 'A', { x, z: 10 });
    run(f, 0.1);
  }
  assert.ok(a.shield < a.shieldMax, `no recharge while sprinting (${a.shield})`);
  run(f, 1);
  assert.ok(a.shield > a.shieldMax - 30 + 1, 'stopped, it comes back');
  // Melee: in front and close, 70 damage; not behind.
  const e = ais(f, 'd')[0];
  Object.assign(e, { alive: true, x: a.x, z: a.z - 1.5, hp: 100, shield: 50, hitAt: 1e9, respawnAt: Infinity });
  a.yaw = 0; // facing -z
  assert.strictEqual(FC.melee(f, 'A').hit, e.id);
  assert.strictEqual(e.hp + e.shield, 150 - FC.MELEE.damage);
  run(f, 1);
  a.yaw = Math.PI;
  assert.strictEqual(FC.melee(f, 'A').hit, null, 'not behind');
  run(f, 1);
  a.yaw = 0;
  Object.assign(e, { hp: 10, shield: 0 });
  FC.melee(f, 'A');
  assert.strictEqual(e.alive, false);
  assert.strictEqual(a.medals.beatdown, 1);
});

test('power on a timer: pads come up at known times with a ten-second warning naming the place; the Overshield takes hold after a moment and wears off', () => {
  const f = match({ map: 0 });
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const rail = f.pads.find((p) => p.kind === 'railgun');
  const over = f.pads.find((p) => p.kind === 'overshield');
  assert.ok(rail && over);
  const feed = [];
  const tick = (s) => {
    run(f, s);
    feed.push(...FC.frame(f).feed);
  };
  tick(FC.POWER.first - FC.POWER.warn + 0.2);
  assert.ok(feed.some((x) => x.power === 'railgun' && /Railgun in 10 seconds at \w/.test(x.text)), JSON.stringify(feed));
  assert.ok(![...f.pickups.values()].some((u) => u.weapon === 'railgun'));
  tick(FC.POWER.warn);
  const u = [...f.pickups.values()].find((x) => x.weapon === 'railgun');
  assert.ok(u, 'up on time');
  Object.assign(a, { alive: true, x: u.x, z: u.z - 1, moveT: f.t });
  FC.move(f, 'A', { x: u.x, z: u.z });
  assert.strictEqual(a.power.weapon, 'railgun');
  assert.ok(Math.abs(rail.next - (f.t + FC.POWER.again)) < 0.01, 'next one in 90 seconds');
  // The Overshield.
  tick(over.next - f.t + 0.1);
  const o = [...f.pickups.values()].find((x) => x.kind === 'overshield');
  Object.assign(a, { x: o.x, z: o.z - 1, moveT: f.t });
  FC.move(f, 'A', { x: o.x, z: o.z });
  assert.strictEqual(a.shield, a.shieldMax, 'not yet');
  tick(FC.OVERSHIELD.delay + 0.1);
  assert.ok(a.shield > a.shieldMax + FC.OVERSHIELD.amount - 2, 'it took hold');
  tick(5);
  assert.ok(a.shield < a.shieldMax + FC.OVERSHIELD.amount - 15, 'and wears off');
});

test('equipment from racks: a Threat Sensor shows enemies near it; a Drop Wall stops their shots, not ours; the Thruster; it drops when you fall', () => {
  const f = match({ map: 0 });
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  run(f, 6); // the racks fill
  const rack = [...f.pickups.values()].find((u) => u.kind === 'gear' && u.gear === 'sensor');
  Object.assign(a, { alive: true, x: rack.x, z: rack.z - 1, moveT: f.t });
  FC.move(f, 'A', { x: rack.x, z: rack.z });
  assert.deepStrictEqual(a.gear, { kind: 'sensor', charges: FC.GEAR.sensor.charges });
  const e = ais(f, 'd')[0];
  Object.assign(e, { alive: true, x: rack.x + 5, z: rack.z + 10, hp: 100, shield: 50, hitAt: 1e9, respawnAt: Infinity });
  assert.ok(FC.useGear(f, 'A', { x: rack.x, z: rack.z + 9 }).ok);
  run(f, 0.2);
  assert.ok(f.spotted.a.has(e.id), 'the sensor shows it');
  assert.strictEqual(a.gear.charges, 1);
  // A Drop Wall: their shots stop on it, ours go through.
  a.gear = { kind: 'wall', charges: 1 };
  Object.assign(a, { x: 10, z: 20, yaw: Math.PI }); // facing +z
  Object.assign(e, { x: 10, z: 30, hp: 100, shield: 0 });
  assert.ok(FC.useGear(f, 'A', {}).ok);
  assert.strictEqual(a.gear, null, 'no charges left');
  run(f, 0.2);
  FC.fire(f, 'A', { dx: 0, dy: -0.06, dz: 1 });
  assert.ok(e.hp < 100, 'our shot through our own wall');
  assert.ok(FC.blocked(f, { x: 10, y: 1.5, z: 30 }, { x: 10, y: 1.5, z: 20 }, 'd') < 1, 'theirs stops');
  // The Thruster: a move further than running allows.
  a.gear = { kind: 'thruster', charges: 3 };
  run(f, 0.2);
  a.moveT = f.t - 0.1;
  FC.useGear(f, 'A', {});
  const z0 = a.z;
  FC.move(f, 'A', { x: a.x, z: z0 - 7 });
  assert.ok(z0 - a.z > 6, `thrusted ${z0 - a.z} m`);
  // Falling drops what's left.
  FC.hurt(f, a, 999, null);
  assert.ok([...f.pickups.values()].some((u) => u.kind === 'gear' && u.gear === 'thruster' && u.charges === 2));
});

test("earned information: the motion tracker shows enemies close by who run or fire, not those crouch-walking; spawns are weighted like Halo's", () => {
  const f = match();
  const a = FC.addPilot(f, 'A', 'a');
  const d = FC.addPilot(f, 'D', 'd');
  park(f);
  Object.assign(a, { alive: true, x: 10, z: 10, moveT: f.t });
  Object.assign(d, { alive: true, x: 10, z: 25, moveT: f.t, loudUntil: 0 });
  run(f, 1);
  FC.move(f, 'D', { x: 10, z: 24.5 }); // half a metre a second: crouch-walking
  assert.deepStrictEqual(FC.tracker(f, a), []);
  run(f, 0.5);
  FC.move(f, 'D', { x: 10, z: 22 }); // running
  assert.deepStrictEqual(FC.tracker(f, a), ['D']);
  Object.assign(d, { x: 10, z: 60, loudUntil: f.t + 5 });
  assert.deepStrictEqual(FC.tracker(f, a), [], 'out of its reach');
  // Spawns: away from enemies and their sight, near teammates, not where someone just died.
  Object.assign(d, { x: 30, z: 40 });
  const open = FC.spawnScore(f, a, 70, 70);
  assert.ok(FC.spawnScore(f, a, 33, 40) < open - 500, 'beside an enemy');
  Object.assign(a, { x: 70, z: 72 });
  const lone = FC.spawnScore(f, d, 72, 72);
  Object.assign(d, { x: 72, z: 70 });
  assert.ok(FC.spawnScore(f, d, 72, 72) < lone, 'its enemy is right there');
  f.deaths.push({ x: 50, z: 50, t: f.t });
  Object.assign(a, { x: 5, z: 5 });
  Object.assign(d, { x: 5, z: 7 });
  assert.ok(FC.spawnScore(f, d, 50, 50) < FC.spawnScore(f, d, 50, 70) - 300, 'a fresh death');
});

test('medals and the Postgame Carnage Report: multikills, sprees, and everyone ranked', () => {
  const f = match();
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const foes = ais(f, 'd');
  for (let i = 0; i < 5; i++) {
    Object.assign(foes[i % foes.length], { alive: true, hp: 1, shield: 0 });
    FC.hurt(f, foes[i % foes.length], 10, a);
  }
  assert.deepStrictEqual([a.medals.double, a.medals.triple, a.medals.overkill, a.medals.spree], [1, 1, 2, 1]);
  const r = FC.carnage(f);
  assert.strictEqual(r.rows[0].name, 'A');
  assert.strictEqual(r.rows[0].kills, 5);
  assert.deepStrictEqual([r.planet, r.mode], ['cinder', 'facility']);
});

test('kill streaks: earned by kills without dying (Hardline: one fewer), used once; a Sensor Array shows the enemy, a barrage shells the mark, a nuke ends the match', () => {
  const f = match();
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const foes = ais(f, 'd');
  const killOne = (t) => {
    Object.assign(t, { alive: true, hp: 1, shield: 0 });
    FC.hurt(f, t, 10, a);
  };
  killOne(foes[0]);
  killOne(foes[1]);
  assert.deepStrictEqual(a.earned, []);
  killOne(foes[2]);
  assert.deepStrictEqual(a.earned, ['sensor']);
  // Dying resets the count, not what was earned.
  FC.hurt(f, a, 999, null);
  assert.deepStrictEqual([a.streak, a.earned], [0, ['sensor']]);
  run(f, FC.RESPAWN_S + 0.2);
  assert.ok(a.alive);
  // The sensor: every (non-Ghost) enemy shows on the attackers' map.
  const t = foes.slice(3).find((b) => !b.items.includes('ghost')) || foes[3];
  t.items = t.items.filter((i) => i !== 'ghost'); // (Ghost would hide it from the sensor)
  Object.assign(t, { alive: true, x: 60, z: 60, hp: 100, respawnAt: 0 });
  assert.ok(FC.useStreak(f, 'A', { streak: 'sensor' }).ok);
  assert.match(FC.useStreak(f, 'A', { streak: 'sensor' }).reason, /haven't earned/);
  run(f, 0.2);
  assert.ok(f.spotted.a.has(t.id));
  // A barrage on the mark (from orbit: cover doesn't help).
  a.earned.push('barrage');
  assert.match(FC.useStreak(f, 'A', { streak: 'barrage' }).reason, /mark/);
  Object.assign(t, { x: 40, z: 72, hp: 100, shield: 0 });
  FC.useStreak(f, 'A', { streak: 'barrage', x: 40, z: 72 });
  for (let i = 0; i < 80 && t.alive; i++) {
    run(f, 0.1);
    Object.assign(t, { x: 40, z: 72 });
  }
  assert.ok(t.hp < 100 || !t.alive, 'the barrage hit');
  // Hardline: a streak one kill sooner.
  const h = FC.addPilot(f, 'H', 'a');
  h.items.push('hardline');
  for (let i = 4; i < 6; i++) {
    Object.assign(foes[i % foes.length], { alive: true, hp: 1, shield: 0 });
    FC.hurt(f, foes[i % foes.length], 10, h);
  }
  assert.deepStrictEqual(h.earned, ['sensor']);
  // The nuke.
  a.earned.push('nuke');
  FC.useStreak(f, 'A', { streak: 'nuke' });
  run(f, 9);
  assert.strictEqual(f.result, null);
  run(f, 1.5);
  assert.deepStrictEqual([f.result, f.how], ['a', 'nuke']);
});

test('King of the Hill: a side alone on the hill scores; the hill moves every minute', () => {
  const f = match({ rule: 'koth' });
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const [x, z] = f.map.hills[0];
  Object.assign(a, { x, z });
  run(f, 10);
  Object.assign(a, { x, z });
  assert.ok(f.score.a >= 9 && f.score.d === 0, `scored ${f.score.a}`);
  // Contested: nobody scores.
  const d = FC.addPilot(f, 'D', 'd');
  Object.assign(d, { x: x + 1, z });
  const before = f.score.a;
  run(f, 2);
  assert.ok(Math.abs(f.score.a - before) < 0.5);
  run(f, 50);
  assert.strictEqual(f.hill, 1);
});

test('Strongholds: zones are taken by standing in them alone; two held score 1 a second, three 2; a contested zone stops the scoring', () => {
  const f = match({ rule: 'strongholds' });
  const d1 = FC.addPilot(f, 'D1', 'd');
  const d2 = FC.addPilot(f, 'D2', 'd');
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const [p0, p1, p2] = f.points;
  const stand = () => {
    Object.assign(d1, { alive: true, x: p0.x, z: p0.z });
    Object.assign(d2, { alive: true, x: p1.x, z: p1.z });
  };
  Object.assign(a, { alive: true, x: 2, z: 2 });
  stand();
  run(f, 4);
  assert.strictEqual(p0.owner, null);
  stand();
  run(f, 1.5);
  assert.deepStrictEqual([p0.owner, p1.owner], ['d', 'd']);
  assert.ok(d1.medals.zone >= 1);
  let s = f.score.d;
  stand();
  run(f, 4);
  assert.ok(f.score.d >= s + 3.5 && f.score.d <= s + 4.5, 'two zones: 1 a second');
  // An attacker steps into a held zone: no scoring while it's contested.
  s = f.score.d;
  Object.assign(a, { x: p0.x + 1, z: p0.z });
  stand();
  run(f, 3);
  assert.ok(Math.abs(f.score.d - s) < 0.01);
  // All three: 2 a second.
  Object.assign(a, { x: 2, z: 2 });
  p2.owner = 'd';
  p2.progress = 1;
  s = f.score.d;
  stand();
  run(f, 2);
  assert.ok(f.score.d >= s + 3.5);
});

test('Oddball: hold the ball to score; its carrier fights with melee only; dropped, it goes back after a while', () => {
  const f = match({ rule: 'oddball' });
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const [bx, bz] = [f.ball.x, f.ball.z];
  Object.assign(a, { alive: true, x: bx, z: bz - 1, moveT: f.t });
  FC.move(f, 'A', { x: bx, z: bz });
  assert.strictEqual(f.ball.carrier, 'A');
  run(f, 5);
  assert.ok(f.score.a >= 4.5);
  assert.match(FC.fire(f, 'A', { dx: 0, dy: 0, dz: 1 }).reason, /ball: melee only/);
  FC.hurt(f, a, 999, null);
  assert.strictEqual(f.ball.carrier, null);
  run(f, FC.RULES.oddball.resetS + 0.2);
  assert.deepStrictEqual([f.ball.x, f.ball.z], f.ball.home);
});

test('Team Deathmatch to the kill target; a side out of reinforcements with everyone down loses', () => {
  const f = match();
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const foe = ais(f, 'd')[0];
  for (let i = 0; i < FC.RULES.tdm.target; i++) {
    Object.assign(foe, { alive: true, hp: 1, shield: 0 });
    FC.hurt(f, foe, 10, a);
  }
  run(f, 0.1);
  assert.deepStrictEqual([f.result, f.how], ['a', 'score']);
  const g = match({ rule: 'koth' });
  park(g);
  g.reinforcements.d = 0;
  for (const b of ais(g, 'd')) FC.hurt(g, Object.assign(b, { alive: true }), 999, null);
  run(g, 0.1);
  assert.deepStrictEqual([g.result, g.how], ['a', 'wiped']);
});

test('Capture the Flag: take the enemy flag home (with your own there) to score; a dropped flag goes back', () => {
  const f = match({ rule: 'ctf' });
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const [fx, fz] = f.map.flags.d;
  FC.move(f, 'A', { x: a.x, z: a.z });
  Object.assign(a, { x: fx, z: fz - 1 });
  run(f, 0.1);
  FC.move(f, 'A', { x: fx, z: fz });
  assert.strictEqual(f.flags.d.carrier, 'A');
  // Dropped when they die, back home after a while.
  FC.hurt(f, a, 999, null);
  assert.strictEqual(f.flags.d.carrier, null);
  run(f, 21);
  assert.deepStrictEqual([f.flags.d.x, f.flags.d.z], f.map.flags.d);
  // Carried home: a capture.
  Object.assign(a, { alive: true, x: fx, z: fz - 1, moveT: f.t });
  FC.move(f, 'A', { x: fx, z: fz });
  const [hx, hz] = f.map.flags.a;
  Object.assign(a, { x: hx, z: hz + 1, moveT: f.t });
  FC.move(f, 'A', { x: hx, z: hz });
  assert.strictEqual(f.score.a, 1);
  assert.strictEqual(f.flags.d.carrier, null);
});

test('the facility: doors open for whoever comes near and stop shots shut; attackers hack the plant to open the shortcut; defenders repair turrets', () => {
  const f = match({ map: 0 }); // Terran Compound: doors, turrets, a locked shortcut
  park(f);
  const m = f.map;
  const lockedAt = m.doors.findIndex((d) => d[4]);
  assert.ok(lockedAt >= 0);
  const a = FC.addPilot(f, 'A', 'a');
  const [dx, dz] = m.doors[0];
  Object.assign(a, { x: dx, z: dz - 6 });
  run(f, 0.2);
  assert.strictEqual(f.doors[0], false, 'shut with nobody near');
  assert.ok(FC.blocked(f, { x: dx, y: 1.5, z: dz - 3 }, { x: dx, y: 1.5, z: dz + 3 }) < 1, 'a shut door stops shots');
  Object.assign(a, { x: dx, z: dz - 2 });
  run(f, 0.2);
  assert.strictEqual(f.doors[0], true);
  // The locked door stays shut until the plant is hacked: hold use for 6 seconds.
  Object.assign(a, { x: m.doors[lockedAt][0] + 1.5, z: m.doors[lockedAt][1] });
  run(f, 0.2);
  assert.strictEqual(f.doors[lockedAt], false);
  Object.assign(a, { x: m.plant[0] + 1, z: m.plant[1] });
  for (let i = 0; i < 30; i++) {
    FC.use(f, 'A');
    run(f, 0.25);
    Object.assign(a, { x: m.plant[0] + 1, z: m.plant[1] });
  }
  assert.ok(f.hacked);
  assert.strictEqual(f.doors[lockedAt], true);
  // A destroyed turret, repaired by a defender holding use.
  const tu = f.turrets[0];
  tu.hp = 0;
  const d = FC.addPilot(f, 'D', 'd');
  for (let i = 0; i < 20; i++) {
    Object.assign(d, { x: tu.x + 1, z: tu.z });
    FC.use(f, 'D');
    run(f, 0.25);
  }
  assert.strictEqual(tu.hp, tu.maxHp);
});

test('AI troopers find their way round the facility and fight: an AI-only match ends with a result', () => {
  for (const [rule, map] of [['tdm', 0], ['koth', 1], ['strongholds', 2], ['ctf', 0], ['oddball', 3]]) {
    const f = match({ rule, map, seed: 11 });
    const start = [...f.bodies.values()].map((b) => [b.x, b.z]);
    run(f, 30);
    const moved = [...f.bodies.values()].filter((b, i) => Math.hypot(b.x - start[i][0], b.z - start[i][1]) > 5).length;
    assert.ok(moved >= 4, `${rule}: ${moved} troopers moved`);
    for (const b of f.bodies.values()) {
      const inWall = f.map.walls.some(([x, z, w, d]) => Math.abs(b.x - x) < w / 2 - 0.05 && Math.abs(b.z - z) < d / 2 - 0.05);
      assert.ok(!inWall, `${rule}: ${b.name} in a wall at ${b.x}, ${b.z}`);
    }
    run(f, FC.MATCH_S);
    assert.ok(f.result, `${rule}: a result`);
    assert.ok(f.kills.a + f.kills.d > 0, `${rule}: they fought`);
  }
});

test('matchmaking: a lone faction plays the holder\'s AI after the wait; the winner scores 4 (half against AI)', () => {
  W.setDemo(true);
  const g = G.newGalaxy();
  let clock = C.DEMO_CYCLE_MS * 400;
  C.tick(g, clock);
  const sent = [];
  const facilities = FC.createFacilities({ now: () => clock, send: (c, m) => sent.push([c.name, m]), changed: () => {}, onEnd: (f, w, vsAi) => C.score(g, f.planet, 'facility', w, vsAi, clock) });
  facilities.close();
  const battles = { campaignMatches: () => [], room: () => false };
  const mm = C.createMatchmaking({ galaxy: () => g, now: () => clock, battles, facilities, where: (me) => ({ over: me.over }), factionOf: (me) => me.faction, send: (c, m) => sent.push([c.name, m]), changed: () => {}, wait: 5000 });
  mm.close();
  const pilot = (name, faction) => ({ name, faction, over: 'cinder' });
  const a = pilot('A', 'ashen');
  assert.ok(mm.join(a, 'cinder', 'facility').ok);
  mm.fill();
  assert.ok(!a.facility);
  clock += 6000;
  mm.fill();
  const [f] = facilities.running('cinder');
  assert.deepStrictEqual([a.facility, f.factions.a, f.factions.d], [f.id, 'ashen', 'compact']);
  assert.ok(sent.some(([n, m]) => n === 'A' && m.type === 'facility_joined' && m.side === 'a' && m.map.name));
  // A Compact pilot backfills the defenders, in place of a trooper.
  const c = pilot('C', 'compact');
  mm.join(c, 'cinder', 'facility');
  assert.strictEqual(c.facility, f.id);
  assert.strictEqual(f.bodies.get('C').side, 'd');
  facilities.leave(c);
  // Ashen wins; it was against AI: half of 4.
  f.result = 'a';
  f.how = 'score';
  facilities.tick();
  assert.strictEqual(g.war.campaigns.cinder.points.ashen, 2);
  assert.ok(sent.some(([n, m]) => n === 'A' && m.type === 'facility_end' && m.won && /\+2 campaign points/.test(m.text)));
  W.setDemo(false);
});
