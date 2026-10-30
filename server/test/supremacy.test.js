// Supremacy: the maps and ships, sides and fodder bots, capturing and the bars, boarding, the
// attack on the reactor (and the damage kept), elite troopers, the planet bonuses, and matchmaking.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const FC = require('../facility');
const G = require('../galaxy');
const S = require('../supremacy');
const W = require('../war');

function match(opts = {}) {
  return S.newSupremacy({ planet: 'cinder', planetName: 'Cinder', attacker: 'ashen', defender: 'compact', holder: 'compact', seed: 5, map: 'highlands', ...opts });
}
const bodies = (f, pred) => [...f.bodies.values()].filter(pred);
// Everyone but `keep` out of the way, dead for good (so a test can stage a moment).
function clearField(f, keep = []) {
  for (const b of f.bodies.values()) if (!keep.includes(b)) Object.assign(b, { alive: false, respawnAt: Infinity, x: 1, z: 1 });
}
// Whether (x, z) can be reached from (fx, fz) on the match's current map.
function reach(f, [fx, fz], [x, z]) {
  return FC.flowTo(f, FC.cellOf(fx, fz, f.w, f.d))[FC.cellOf(x, z, f.w, f.d)] >= 0;
}

test('maps: ground maps of 3 to 5 points, every point reachable from both drop ships; each faction its own ship, the reactor shut off until the blast doors fall', () => {
  const counts = Object.keys(S.GROUND).map((id) => S.GROUND[id].points.length);
  assert.deepStrictEqual(counts.slice().sort(), [3, 4, 5]);
  for (const id of Object.keys(S.GROUND)) {
    const f = match({ map: id });
    for (const p of f.ground.points) for (const s of ['a', 'd']) assert.ok(reach(f, f.ground.drop[s], p), `${id}: point ${p} from ${s}`);
  }
  const layouts = new Set(['compact', 'ashen', 'luminar', 'coma'].map((fac) => JSON.stringify(S.shipLayout(fac).walls)));
  assert.strictEqual(layouts.size, 4, 'four different ship interiors');
  for (const fac of ['compact', 'ashen', 'luminar', 'coma', null]) {
    const f = match({ defender: fac });
    S.startBoarding(f, 'a');
    f.t += S.BOARD_S;
    S.step(f, 0.2);
    assert.strictEqual(f.phase, 'ship');
    const ship = f.map;
    const face = [ship.reactor[0] - ship.reactor[2] / 2 - 1.5, ship.reactor[1]];
    assert.ok(!reach(f, ship.spawns.a[0], face), `${ship.name}: the reactor is behind blast doors`);
    for (const br of f.breakables) if (br.kind === 'door') br.hp = 0;
    f.blockers = FC.blockers(f);
    f.nav = FC.navGrid(f);
    f.flows = new Map();
    assert.ok(reach(f, ship.spawns.a[0], face), `${ship.name}: breached, the reactor can be reached`);
    for (const sp of [...ship.spawns.a, ...ship.spawns.d, ...ship.holds]) assert.ok(reach(f, ship.spawns.d[0], sp), `${ship.name}: ${sp}`);
  }
});

test('sides: 16 a side with AI troopers, plus fodder bots that die very quickly and are not counted as players', () => {
  const f = match();
  assert.strictEqual(FC.team(f, 'a').length, S.TEAM_MAX);
  assert.strictEqual(FC.team(f, 'd').length, S.TEAM_MAX);
  const fodder = bodies(f, (b) => b.fodder);
  assert.strictEqual(fodder.length, 2 * S.FODDER);
  assert.ok(fodder.every((b) => b.hpMax <= 30 && b.shieldMax === 0));
  assert.ok(fodder.some((b) => b.name.startsWith('Skitter')) && fodder.some((b) => b.name.startsWith('Drudge')), "each faction's own bots");
  S.addPilot(f, 'Pilot', 'a');
  assert.strictEqual(FC.team(f, 'a').length, S.TEAM_MAX, 'a pilot takes an AI trooper\'s place');
  assert.strictEqual(FC.humans(f, 'a').length, 1);
});

test('capturing: one alone takes a point in 10 seconds, four together in 2.5; held points fill the bar; a full bar wins the ground and the shuttles land', () => {
  const f = match();
  const [p0, p1] = f.points;
  const a = bodies(f, (b) => b.side === 'a' && !b.fodder).slice(0, 4);
  clearField(f, a);
  Object.assign(a[0], { alive: true, x: p0.x, z: p0.z, respawnAt: 0 });
  for (const b of a.slice(1)) Object.assign(b, { alive: true, x: p1.x, z: p1.z, respawnAt: 0 });
  const hold = () => {
    Object.assign(a[0], { x: p0.x, z: p0.z });
    for (const b of a.slice(1)) Object.assign(b, { x: p1.x, z: p1.z });
  };
  for (let i = 0; i < 8; i++) {
    hold();
    S.step(f, 0.5);
  }
  hold();
  assert.strictEqual(p0.owner, null, 'one alone: not yet');
  assert.strictEqual(p1.owner, 'a', 'three together: 3x faster');
  for (let i = 0; i < 16; i++) {
    hold();
    S.step(f, 0.5);
  }
  assert.strictEqual(p0.owner, 'a');
  const bar = f.bars.a;
  hold();
  S.step(f, 1);
  assert.ok(f.bars.a > bar, 'held points fill the bar');
  f.bars.a = S.BAR_TARGET;
  hold();
  S.step(f, 0.2);
  assert.strictEqual(f.phase, 'boarding');
  assert.strictEqual(f.winner, 'a');
  assert.strictEqual(f.shuttles.length, 1 + f.points.filter((p) => p.owner === 'a').length, "a shuttle at the drop ship and every point they hold");
});

test('boarding: every pilot who reaches a shuttle in time adds 15 seconds; then the attack, in the losers\' own ship', () => {
  const f = match({ bonus: null });
  const p1 = S.addPilot(f, 'P1', 'a');
  const p2 = S.addPilot(f, 'P2', 'a');
  S.addPilot(f, 'P3', 'a');
  S.startBoarding(f, 'a');
  const [sx, sz] = f.shuttles[0];
  const p3 = f.bodies.get('P3');
  for (let i = 0; i < 22 && f.phase === 'boarding'; i++) {
    for (const p of [p1, p2]) Object.assign(p, { alive: true, x: sx + 1, z: sz });
    Object.assign(p3, { alive: true, x: 2, z: 60 }); // the third stays away
    S.step(f, 1);
  }
  assert.strictEqual(f.phase, 'ship');
  assert.strictEqual(f.pilotsAboard, 2);
  assert.ok(Math.abs(f.shipUntil - f.phaseAt - (S.SHIP_S + 2 * S.BOARD_BONUS_S)) < 0.01);
  assert.strictEqual(f.map.name, S.SHIPS.compact.name, 'aboard the Compact ship');
  assert.ok(p1.x < 16, 'boarders come in at the hangar');
  assert.ok(bodies(f, (b) => b.fodder).every((b) => b.side === 'd'), 'only the ship\'s crew of bots aboard');
});

test('the attack: shots breach blast doors and hit the reactor; destroyed, the round goes to the boarders; the damage is kept for the next attack', () => {
  const f = match();
  const p = S.addPilot(f, 'P', 'a');
  S.startBoarding(f, 'a');
  f.t += S.BOARD_S;
  S.step(f, 0.1);
  clearField(f, [p]);
  const door = f.breakables.find((br) => br.kind === 'door');
  const [dx, dz] = door.box;
  Object.assign(p, { alive: true, x: dx - 5, z: dz, lastShot: -10, reloadUntil: 0 });
  p.guns.primary.mag = 30;
  FC.fire(f, 'P', { dx: 1, dy: 0, dz: 0 });
  assert.ok(door.hp < S.BLAST_DOOR_HP, 'the shot hit the blast door');
  // The other side's pilots can't hurt their own ship.
  // Destroy the reactor: round to the boarders, back to the ground, bars reset.
  const reactor = f.breakables.find((br) => br.kind === 'reactor');
  door.hp = 1000;
  FC.hurtBreakable(f, reactor, 1e9, p);
  assert.deepStrictEqual(f.rounds, { a: 1, d: 0 });
  assert.strictEqual(f.phase, 'ground');
  assert.deepStrictEqual(f.bars, { a: 0, d: 0 });
  // The Compact ship keeps its breached door for the next attack on it; a new attack's on a fresh reactor.
  S.startBoarding(f, 'a');
  f.t += S.BOARD_S;
  S.step(f, 0.1);
  assert.strictEqual(f.breakables.find((br) => br.kind === 'door').hp, 1000);
  // Time out: the round goes to the ship's side; first to 2 wins.
  f.shipUntil = f.t;
  S.step(f, 0.2);
  assert.deepStrictEqual(f.rounds, { a: 1, d: 1 });
  S.startBoarding(f, 'd');
  f.t += S.BOARD_S;
  S.step(f, 0.1);
  assert.strictEqual(f.map.name, S.SHIPS.ashen.name, 'the Compact boards the Ashen ship');
  f.shipUntil = f.t;
  S.step(f, 0.2);
  assert.deepStrictEqual([f.result, f.how], ['a', 'time']);
});

test('elite troopers: credits from kills and captures buy a tougher, better-armed respawn', () => {
  const f = match({ bonus: null });
  const p = S.addPilot(f, 'P', 'a');
  const foes = bodies(f, (b) => b.side === 'd' && !b.fodder);
  for (let i = 0; i < 15; i++) {
    const t = foes[i % foes.length];
    Object.assign(t, { alive: true, hp: 1, shield: 0 });
    FC.hurt(f, t, 10, p);
  }
  assert.strictEqual(p.credits, 15 * S.CREDITS.kill);
  assert.ok(p.credits >= S.ELITE_COST);
  p.wantElite = true;
  FC.hurt(f, p, 9999, null);
  S.step(f, 5);
  assert.ok(p.alive && p.elite);
  assert.deepStrictEqual([p.hpMax, p.damageMul], [S.ELITE.hp, S.ELITE.damage]);
  assert.strictEqual(p.credits, 15 * S.CREDITS.kill - S.ELITE_COST);
  assert.strictEqual(p.wantElite, false, 'once, until asked again');
});

test("planet bonuses: the holder's extra boarding time, faster credits, or kill streaks", () => {
  const b = match({ bonus: 'boarding' });
  S.startBoarding(b, 'd');
  b.t += S.BOARD_S;
  S.step(b, 0.1);
  assert.ok(Math.abs(b.shipUntil - b.phaseAt - (S.SHIP_S + S.BONUSES.boarding.seconds)) < 0.01);
  const c = match({ bonus: 'credits' });
  const holder = S.addPilot(c, 'H', 'd');
  const t = bodies(c, (x) => x.side === 'a' && !x.fodder)[0];
  Object.assign(t, { alive: true, hp: 1, shield: 0 });
  FC.hurt(c, t, 10, holder);
  assert.strictEqual(holder.credits, S.CREDITS.kill * 1.5);
  const s = match({ bonus: 'streaks' });
  const sh = S.addPilot(s, 'H', 'd');
  const sa = S.addPilot(s, 'A', 'a');
  for (const [who, foeSide] of [[sh, 'a'], [sa, 'd']]) {
    const foes = bodies(s, (x) => x.side === foeSide && !x.fodder);
    for (let i = 0; i < 5; i++) {
      Object.assign(foes[i], { alive: true, hp: 1, shield: 0 });
      FC.hurt(s, foes[i], 10, who);
    }
  }
  assert.deepStrictEqual(sh.earned, ['sensor', 'drop', 'barrage']);
  assert.deepStrictEqual(sa.earned, [], 'no streaks for the other side');
  assert.ok(['boarding', 'credits', 'streaks'].includes(S.bonusOf('cinder')));
});

test("the ship is the faction's navy ship over the planet: its biggest warship there, or its own capital ship", () => {
  W.setDemo(true);
  const g = G.newGalaxy();
  const wp = W.planet(g, 'cinder');
  assert.strictEqual(S.shipName(g, wp, 'ashen'), 'Ashen carrier');
  g.war.fleets.push({ id: 1, owner: 'Akane', faction: 'ashen', system: wp.system, ships: { frigate: 2, destroyer: 1 }, status: 'holding' });
  assert.strictEqual(S.shipName(g, wp, 'ashen'), "Akane's destroyer");
  W.setDemo(false);
});

test('matchmaking: a lone faction plays the holder\'s AI after the wait; the winner scores 8, half against AI', () => {
  W.setDemo(true);
  const g = G.newGalaxy();
  let clock = C.DEMO_CYCLE_MS * 500;
  C.tick(g, clock);
  const sent = [];
  const supremacies = S.createSupremacies({ now: () => clock, send: (c, m) => sent.push([c.name, m]), changed: () => {}, onEnd: (f, w, vsAi) => C.score(g, f.planet, 'supremacy', w, vsAi, clock) });
  supremacies.close();
  const battles = { campaignMatches: () => [], room: () => false };
  const mm = C.createMatchmaking({ galaxy: () => g, now: () => clock, battles, supremacies, where: (me) => ({ over: me.over }), factionOf: (me) => me.faction, send: (c, m) => sent.push([c.name, m]), changed: () => {}, wait: 5000 });
  mm.close();
  const a = { name: 'A', faction: 'ashen', over: 'cinder' };
  assert.ok(mm.join(a, 'cinder', 'supremacy').ok);
  clock += 6000;
  mm.fill();
  const [f] = supremacies.running('cinder');
  assert.deepStrictEqual([a.supremacy, f.factions.a, f.factions.d], [f.id, 'ashen', 'compact']);
  const j = sent.find(([n, m]) => n === 'A' && m.type === 'supremacy_joined')[1];
  assert.ok(j.maps.ground.points.length >= 3 && j.maps['ship-d'].name);
  assert.ok(j.bonus && j.bonus.name);
  f.result = 'a';
  supremacies.tick();
  assert.strictEqual(g.war.campaigns.cinder.points.ashen, 4);
  assert.ok(sent.some(([n, m]) => n === 'A' && m.type === 'supremacy_end' && m.won));
  W.setDemo(false);
});
