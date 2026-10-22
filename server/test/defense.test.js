// Sector Defense: waves, the squad's shots and lives, supply drops, and matchmaking into it.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const DF = require('../defense');
const G = require('../galaxy');
const W = require('../war');

function match(squad = ['A']) {
  const d = DF.newDefense({ planet: 'cinder', planetName: 'Cinder', faction: 'ashen', enemy: 'compact', seed: 7 });
  for (const n of squad) DF.addPilot(d, n);
  return d;
}
const run = (d, s) => DF.step(d, s);
const alive = (d) => [...d.enemies.values()].filter((e) => e.hp > 0);

test('3 sets of 5 waves, harder as they go, a boss ending each set; bigger squads face more', () => {
  const count = (w) => w.reduce((a, [, n]) => a + n, 0);
  assert.ok(DF.waveOf(1, 5, 1).some(([t]) => t === 'boss'));
  assert.ok(!DF.waveOf(1, 4, 1).some(([t]) => t === 'boss'));
  assert.ok(count(DF.waveOf(3, 4, 1)) > count(DF.waveOf(1, 4, 1)));
  assert.ok(count(DF.waveOf(2, 1, 4)) > count(DF.waveOf(2, 1, 1)));
  assert.deepStrictEqual(DF.modifiersFor(1), []);
  assert.deepStrictEqual(DF.modifiersFor(2), ['tough']);
  assert.deepStrictEqual(DF.modifiersFor(3), ['tough', 'fury', 'famine']);
});

test('the first wave comes after the break; a rifle shot hits the enemy on its ray', () => {
  const d = match();
  run(d, DF.FIRST_BREAK_S - 0.5);
  assert.strictEqual(d.wave, 0);
  run(d, 1);
  assert.deepStrictEqual([d.set, d.wave, d.phase], [1, 1, 'wave']);
  const e = alive(d)[0];
  const p = d.pilots.get('A');
  // Aim straight at it from the pilot's eye, a little low so the ray meets its body.
  const dx = e.x - p.x;
  const dz = e.z - p.z;
  const hp = e.hp;
  assert.ok(DF.fire(d, 'A', { weapon: 'rifle', dx, dy: -0.2, dz }).hit === e.id);
  assert.strictEqual(e.hp, hp - DF.WEAPONS.rifle.damage);
  // Aimed well wide, nothing is hit.
  run(d, 0.2);
  assert.strictEqual(DF.fire(d, 'A', { weapon: 'rifle', dx: -dz, dy: 0, dz: dx }).hit, null);
  // Without rockets the launcher won't fire.
  run(d, 0.2);
  assert.strictEqual(DF.fire(d, 'A', { weapon: 'rocket', dx, dy: 0, dz }).reason, 'no rockets left');
});

test('moves are limited to how far a pilot could run, and supply drops are taken by walking over them', () => {
  const d = match();
  const p = d.pilots.get('A');
  const [x0, z0] = [p.x, p.z];
  run(d, 1);
  DF.move(d, 'A', { x: x0 + 50, z: z0, yaw: 1 });
  assert.ok(p.x - x0 <= 10.5, `moved ${p.x - x0} m in a second`);
  d.pickups.set(99, { id: 99, kind: 'rocket', x: p.x + 1, z: p.z });
  run(d, 0.5);
  DF.move(d, 'A', { x: p.x + 0.5, z: p.z });
  assert.strictEqual(p.rockets, DF.WEAPONS.rocket.rounds);
  assert.strictEqual(d.pickups.size, 0);
});

test('shields soak damage and recharge; a fallen pilot costs a life and comes back; no lives left and all down loses', () => {
  const d = match(['A', 'B']);
  const a = d.pilots.get('A');
  DF.hurtPilot(d, a, 40);
  assert.deepStrictEqual([a.shield, a.hp], [DF.SHIELD - 40, DF.HP]);
  run(d, 6.5);
  assert.strictEqual(a.shield, DF.SHIELD, 'shields come back after a few seconds');
  DF.hurtPilot(d, a, 500);
  assert.strictEqual(a.alive, false);
  assert.strictEqual(d.lives, DF.LIVES - 1);
  run(d, DF.RESPAWN_S + 0.2);
  assert.ok(a.alive && a.hp === DF.HP);
  d.lives = 0;
  for (const n of ['A', 'B']) DF.hurtPilot(d, d.pilots.get(n), 500);
  run(d, 0.2);
  assert.strictEqual(d.result, 'lost');
});

test('clearing every wave of all three sets wins; sets add lives and drops', () => {
  const d = match();
  const lives = d.lives;
  for (let guard = 0; guard < 200 && !d.result; guard++) {
    run(d, 2);
    for (const e of alive(d)) e.hp = 0; // the squad is very good
    d.pilots.get('A').hp = DF.HP; // and never hurt
  }
  assert.strictEqual(d.result, 'won');
  assert.deepStrictEqual([d.set, d.wave], [DF.SETS, DF.WAVES]);
  assert.strictEqual(d.lives, lives + DF.LIVES_PER_SET * (DF.SETS - 1));
});

test('matchmaking: a lone squad goes in after the wait, four go in at once; the result scores for the campaign', () => {
  W.setDemo(true);
  const g = G.newGalaxy();
  let clock = C.DEMO_CYCLE_MS * 300;
  C.tick(g, clock);
  const sent = [];
  const defenses = DF.createDefenses({ now: () => clock, send: (c, m) => sent.push([c.name, m]), changed: () => {}, onEnd: (d, w) => C.score(g, d.planet, 'defense', w, true, clock) });
  defenses.close();
  const battles = { campaignMatches: () => [], room: () => false };
  const mm = C.createMatchmaking({ galaxy: () => g, now: () => clock, battles, defenses, where: (me) => ({ over: me.over }), factionOf: (me) => me.faction, send: (c, m) => sent.push([c.name, m]), changed: () => {}, wait: 5000 });
  mm.close();
  const pilot = (name, faction) => ({ name, faction, over: 'cinder' });
  const a = pilot('A', 'ashen');
  assert.ok(mm.join(a, 'cinder', 'defense').ok);
  mm.fill();
  assert.ok(!a.defense, 'waits for more of the squad');
  clock += 6000;
  mm.fill();
  const [d] = defenses.running('cinder');
  assert.deepStrictEqual([a.defense, d.faction, d.enemy], [d.id, 'ashen', 'compact']);
  assert.ok(sent.some(([n, m]) => n === 'A' && m.type === 'defense_joined' && m.enemy === 'compact'));
  // During the break another Ashen pilot backfills the squad.
  const b = pilot('B', 'ashen');
  mm.join(b, 'cinder', 'defense');
  assert.strictEqual(b.defense, d.id);
  // Four Luminar pilots go in together at once.
  const lums = ['L1', 'L2', 'L3', 'L4'].map((n) => pilot(n, 'luminar'));
  for (const p of lums.slice(0, 3)) mm.join(p, 'cinder', 'defense');
  assert.ok(lums.slice(0, 3).every((p) => !p.defense));
  mm.join(lums[3], 'cinder', 'defense');
  assert.ok(lums.every((p) => p.defense && p.defense === lums[0].defense));
  // The Ashen squad wins: half of 6 points (it's always against AI).
  d.result = 'won';
  defenses.tick();
  assert.strictEqual(g.war.campaigns.cinder.points.ashen, 3);
  assert.ok(sent.some(([n, m]) => n === 'A' && m.type === 'defense_end' && m.won && /\+3 campaign points/.test(m.text)));
  // The Luminar squad falls: the Compact (the enemy) scores.
  const l = defenses.matches.get(lums[0].defense);
  l.result = 'lost';
  defenses.tick();
  assert.strictEqual(g.war.campaigns.cinder.points.compact, 3);
  W.setDemo(false);
});
