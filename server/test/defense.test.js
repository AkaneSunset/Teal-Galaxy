// Sector Defense: waves, the squad's shots and lives, supply drops, cover, the bonus round,
// objective maps, and matchmaking into it.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const DF = require('../defense');
const G = require('../galaxy');
const W = require('../war');

function match(squad = ['A'], map = 'outpost') {
  const d = DF.newDefense({ planet: 'cinder', planetName: 'Cinder', faction: 'ashen', enemy: 'compact', seed: 7, map });
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

// Steps until no wave is on, the squad clearing every enemy (and never getting hurt).
function clearWaves(d, until) {
  for (let guard = 0; guard < 400 && !d.result && !until(d); guard++) {
    run(d, 2);
    for (const e of alive(d)) {
      e.hp = 0;
      if (d.bonus) d.bonusKills += 1; // (as hurtEnemy counts them)
    }
    for (const p of d.pilots.values()) p.hp = DF.HP;
  }
}

test('clearing every wave of all three sets wins; then the bonus round runs until the squad falls, and can only add', () => {
  const d = match();
  const lives = d.lives;
  clearWaves(d, (m) => m.bonus);
  assert.ok(d.bonus, 'the bonus round started');
  assert.strictEqual(d.result, null, 'the match goes on');
  assert.strictEqual(d.set, DF.SETS + 1);
  assert.strictEqual(d.lives, lives + DF.LIVES_PER_SET * (DF.SETS - 1), 'no lives come with the bonus round');
  assert.deepStrictEqual(DF.modifiersFor(d.set), ['tough', 'fury', 'famine']);
  // Endless waves, a boss every fifth.
  assert.ok(DF.waveOf(DF.SETS + 1, 5, 1).some(([t]) => t === 'boss'));
  clearWaves(d, (m) => m.bonusKills >= 25);
  assert.ok(d.wave >= 1 && d.phase);
  // Kills in the bonus round count, with hurtEnemy too.
  run(d, 30);
  const e = alive(d)[0];
  const before = d.bonusKills;
  assert.ok(e, 'a bonus wave is on');
  const p = d.pilots.get('A');
  Object.assign(p, { x: 10, z: 10, alive: true, hp: DF.HP });
  Object.assign(e, { x: 15, z: 10, hp: 1 });
  DF.fire(d, 'A', { weapon: 'rifle', dx: 1, dy: -0.2, dz: 0 });
  assert.strictEqual(d.bonusKills, before + 1);
  assert.strictEqual(DF.bonusPoints(d), Math.floor(d.bonusKills / DF.BONUS_KILLS_PER_POINT));
  // The squad falls: the bonus round is over and the match is still won.
  d.lives = 0;
  DF.hurtPilot(d, d.pilots.get('A'), 500);
  run(d, 0.2);
  assert.deepStrictEqual([d.result, d.how], ['won', 'bonus']);
});

test('cover stops fire both ways: shots end at the wall, rockets burst on it, enemies close in instead of shooting through', () => {
  const d = match();
  d.breakUntil = 1e9; // no waves
  const p = d.pilots.get('A');
  // The wall [60, 30, 3, 8, 2.6] stands between the pilot at z 20 and the trooper at z 40.
  Object.assign(p, { x: 60, z: 20 });
  d.enemies.set(1, { id: 1, type: 'grunt', x: 60, z: 40, hp: 70, maxHp: 70, cd: 0, heading: 0, state: 'move', side: 1, detourUntil: 0, goal: 'pilots' });
  const e = d.enemies.get(1);
  const r = DF.fire(d, 'A', { weapon: 'rifle', dx: 0, dy: -0.01, dz: 1 });
  assert.strictEqual(r.hit, null, 'the wall took the shot');
  assert.ok(Math.abs(r.wall - 6) < 0.1, `the shot stopped ${r.wall} m out, at the wall`);
  assert.strictEqual(e.hp, 70);
  p.rockets = 1;
  run(d, 1.1);
  Object.assign(e, { x: 60, z: 36 }); // just behind it, within the splash if the wall weren't there
  DF.fire(d, 'A', { weapon: 'rocket', dx: 0, dy: -0.01, dz: 1 });
  assert.strictEqual(e.hp, 70, "the blast didn't come through the wall");
  // Over low cover a pilot can shoot (the eye is above it).
  assert.strictEqual(DF.blocked(d, { x: 40, y: 1.6, z: 36 }, { x: 40, y: 1.6, z: 44 }), 1, 'low cover: a pilot sees over it');
  assert.ok(DF.blocked(d, { x: 40, y: 1.0, z: 36 }, { x: 40, y: 1.0, z: 44 }) < 1, 'low cover hides a body');
  // The trooper can't see the pilot: it holds its fire and works its way round the wall.
  Object.assign(e, { x: 60, z: 40, cd: 0 });
  d.shots = [];
  const shield = p.shield;
  DF.enemyStep(d, e, 0.1);
  assert.strictEqual(d.shots.length, 0, 'no shot through the wall');
  assert.strictEqual(p.shield, shield);
  let fired = false;
  for (let i = 0; i < 200 && !fired; i++) {
    DF.enemyStep(d, e, 0.1);
    const inWall = Math.abs(e.x - 60) < 1.5 && Math.abs(e.z - 30) < 4;
    assert.ok(!inWall, `the trooper walked into the wall at ${e.x}, ${e.z}`);
    fired = d.shots.length > 0;
  }
  assert.ok(fired, 'round the wall, it opens fire');
});

test('objective maps: part of each wave goes for the generator; it is patched up between waves; destroyed, the match is lost', () => {
  const d = match(['A'], 'relay');
  assert.strictEqual(d.objective.kind, 'generator');
  assert.strictEqual(DF.joined(d, 'A').objective.name, 'Shield generator');
  assert.strictEqual(DF.frame(d).objective[0], d.objective.maxHp);
  assert.strictEqual(match(['A'], 'outpost').objective, null, 'survival maps have none');
  // A wave: some go for the generator, and hit it.
  run(d, DF.FIRST_BREAK_S + 0.5);
  const goals = alive(d).map((e) => e.goal);
  assert.ok(goals.includes('objective') && goals.includes('pilots'), goals.join());
  d.pilots.get('A').hp = 1e9; // the squad holds on
  run(d, 40);
  assert.ok(d.objective.hp < d.objective.maxHp, 'the generator was hit');
  // Patched up between waves.
  for (const e of alive(d)) e.hp = 0;
  const hp = d.objective.hp;
  run(d, 0.2);
  assert.strictEqual(d.phase, 'break');
  assert.ok(d.objective.hp > hp || d.objective.hp === d.objective.maxHp);
  // Destroyed: lost.
  DF.hurtObjective(d, 1e9);
  assert.deepStrictEqual([d.result, d.how], ['lost', 'objective']);
  // In the bonus round it only ends the round: still a win.
  const b = match(['A'], 'relay');
  b.bonus = true;
  DF.hurtObjective(b, 1e9);
  assert.deepStrictEqual([b.result, b.how], ['won', 'bonus']);
  // Without a map named, the seed picks one.
  const maps = new Set([1, 2, 3, 4, 5, 6].map((seed) => DF.newDefense({ planet: 'x', planetName: 'X', faction: 'ashen', seed }).map));
  assert.deepStrictEqual([...maps].sort(), Object.keys(DF.MAPS).sort());
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
