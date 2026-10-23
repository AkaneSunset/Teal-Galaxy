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
  const rules = new Set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((seed) => FC.newFacility({ planet: 'cinder', attacker: 'ashen', defender: 'compact', seed }).rule));
  assert.deepStrictEqual([...rules].sort(), Object.keys(FC.RULES).sort());
});

test('shots: the server checks the rate and magazine, walls stop them, headshots hit harder, reloading takes time', () => {
  const f = match();
  const a = FC.addPilot(f, 'A', 'a');
  park(f);
  const e = ais(f, 'd')[0];
  Object.assign(a, { x: 10, z: 30, alive: true });
  Object.assign(e, { x: 10, z: 40, alive: true, respawnAt: 0, shield: 0, hp: 100 });
  run(f, 0.2);
  Object.assign(e, { x: 10, z: 40 });
  // Body shot, then a headshot.
  FC.fire(f, 'A', { dx: 0, dy: -0.06, dz: 1 });
  assert.strictEqual(e.hp, 100 - FC.WEAPONS.rifle.damage);
  run(f, 0.2);
  Object.assign(e, { x: 10, z: 40, hp: 100 });
  FC.fire(f, 'A', { dx: 0, dy: 0.0, dz: 1 });
  assert.strictEqual(e.hp, 100 - FC.WEAPONS.rifle.damage * 1.5, 'a headshot');
  // Too fast: the second shot doesn't count.
  Object.assign(e, { hp: 100 });
  FC.fire(f, 'A', { dx: 0, dy: -0.06, dz: 1 });
  assert.strictEqual(e.hp, 100);
  // A wall in the way stops it (Proving Grounds' cover [20, 20, 4, 4, 3]).
  run(f, 0.2);
  Object.assign(a, { x: 20, z: 14 });
  Object.assign(e, { x: 20, z: 26, hp: 100 });
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

test('Domination: standing alone on a point takes it in 5 seconds, then it scores', () => {
  const f = match({ rule: 'domination' });
  const d = FC.addPilot(f, 'D', 'd');
  park(f);
  const p = f.points[0];
  Object.assign(d, { x: p.x, z: p.z });
  run(f, 4);
  assert.strictEqual(p.owner, null);
  Object.assign(d, { x: p.x, z: p.z });
  run(f, 1.5);
  assert.strictEqual(p.owner, 'd');
  const s = f.score.d;
  run(f, 5);
  assert.ok(f.score.d >= s + 2.2, 'a point every 2 seconds');
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
  for (const [rule, map] of [['tdm', 0], ['koth', 1], ['domination', 2], ['ctf', 0]]) {
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
