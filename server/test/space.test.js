// Space Battles: sides and the sky's AI, ship classes, shots (hulls block them), missiles and
// torpedoes, the capital ship's shield generators and subsystems, turrets, power-ups, the end,
// the shipyard bonus, orbital control, and matchmaking.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const G = require('../galaxy');
const SB = require('../space');
const W = require('../war');

function match(opts = {}) {
  return SB.newSpace({ planet: 'cinder', planetName: 'Cinder', attacker: 'ashen', defender: 'compact', seed: 3, ...opts });
}
const all = (f, pred) => [...f.craft.values()].filter(pred);
// Everyone but `keep` out of the fight (for a test to stage a moment).
function park(f, keep = []) {
  for (const c of f.craft.values()) if (!keep.includes(c)) Object.assign(c, { alive: false, respawnAt: Infinity });
}
// A pilot at `pos` facing `fwd`, as its screen reports it.
function place(f, c, pos, fwd) {
  Object.assign(c, { pos: { x: pos[0], y: pos[1], z: pos[2] }, fwd: { x: fwd[0], y: fwd[1], z: fwd[2] }, history: [], lastShot: -10, missileCd: 0, alive: true });
}

test('sides: 12 pilots a side (AI in the empty slots) plus AI fighters filling the sky; a pilot launches from their own carrier', () => {
  const f = match();
  for (const s of ['a', 'd']) {
    assert.strictEqual(all(f, (c) => c.side === s && !c.sky).length, SB.PILOTS);
    assert.strictEqual(all(f, (c) => c.side === s && c.sky).length, SB.SKY);
  }
  const p = SB.addPilot(f, 'Akane', 'a');
  assert.strictEqual(all(f, (c) => c.side === 'a' && !c.sky).length, SB.PILOTS, 'an AI pilot steps aside');
  assert.strictEqual(f.carriers.a[0].name, 'Akane');
  assert.ok(Math.hypot(p.pos.x - f.carriers.a[0].pos.x, p.pos.z - f.carriers.a[0].pos.z) < 250, 'launched from their carrier');
  assert.deepStrictEqual([p.cls, p.maxHp], ['fighter', SB.CLASSES.fighter.hull]);
});

test('lasers: the rate is checked, they hit what is in front, and a capital hull blocks them', () => {
  const f = match();
  const p = SB.addPilot(f, 'P', 'a');
  const e = all(f, (c) => c.side === 'd')[0];
  park(f, [p, e]);
  place(f, p, [2000, 0, 0], [1, 0, 0]);
  place(f, e, [2500, 0, 0], [1, 0, 0]);
  Object.assign(e, { shield: 0, hp: 100 });
  assert.strictEqual(SB.fire(f, 'P', { dx: 1, dy: 0, dz: 0 }).hit, e.id);
  assert.strictEqual(e.hp, 100 - SB.CLASSES.fighter.laser);
  assert.strictEqual(SB.fire(f, 'P', { dx: 1, dy: 0, dz: 0 }).hit, undefined, 'too soon after the last bolt');
  // The enemy capital ship's hull between them: the bolt stops on it.
  const cap = f.capitals.d;
  place(f, p, [cap.x, cap.y, cap.z - 500], [0, 0, 1]);
  place(f, e, [cap.x, cap.y, cap.z + 500], [0, 0, 1]);
  e.hp = 100;
  SB.fire(f, 'P', { dx: 0, dy: 0, dz: 1 });
  assert.strictEqual(e.hp, 100);
});

test("the capital ship: subsystems are shielded until both generators fall; all three subsystems down and it's destroyed", () => {
  const f = match();
  const p = SB.addPilot(f, 'P', 'a');
  const part = (k) => f.parts.get(`d:${k}`);
  SB.hurtPart(f, part('reactor'), 1000, p);
  assert.strictEqual(part('reactor').hp, part('reactor').maxHp, 'shielded');
  SB.hurtPart(f, part('gen0'), 1e9, p);
  SB.hurtPart(f, part('reactor'), 1000, p);
  assert.strictEqual(part('reactor').hp, part('reactor').maxHp, 'one generator still shields it');
  SB.hurtPart(f, part('gen1'), 1e9, p);
  SB.hurtPart(f, part('reactor'), 1000, p);
  assert.strictEqual(part('reactor').hp, part('reactor').maxHp - 1000);
  for (const k of ['engines', 'bridge']) SB.hurtPart(f, part(k), 1e9, p);
  assert.strictEqual(f.result, null);
  SB.hurtPart(f, part('reactor'), 1e9, p);
  assert.deepStrictEqual([f.result, f.how], ['a', 'destroyed']);
  assert.ok(f.damage.a > 0);
});

test('missiles home on a locked fighter ahead; bombers carry torpedoes for capital ships; frigates take turrets down with them', () => {
  const f = match();
  const p = SB.addPilot(f, 'P', 'a');
  const e = all(f, (c) => c.side === 'd')[0];
  park(f, [p, e]);
  place(f, p, [0, 2000, 0], [1, 0, 0]);
  place(f, e, [800, 2000, 0], [0, 0, 1]);
  Object.assign(e, { shield: 0, hp: 100, hitAt: 1e9, vel: { x: 0, y: 0, z: 200 } });
  assert.match(SB.missile(f, 'P', { target: 'nobody' }).reason, /no target/);
  place(f, e, [-800, 2000, 0], [0, 0, 1]);
  assert.match(SB.missile(f, 'P', { target: e.id }).reason, /ahead/);
  place(f, e, [800, 2000, 0], [0, 0, 1]);
  assert.ok(SB.missile(f, 'P', { target: e.id }).ok);
  for (let i = 0; i < 40 && e.hp === 100; i++) SB.step(f, 0.1);
  assert.strictEqual(e.hp, 100 - SB.CLASSES.fighter.missileDamage);
  assert.match(SB.torpedo(f, 'P', { target: 'd:f0' }).reason, /only bombers/);
  // A bomber: torpedoes into a frigate (which takes its turrets with it).
  p.want = 'bomber';
  SB.hurt(f, p, 1e9, null);
  SB.step(f, SB.RESPAWN_S + 0.2);
  assert.strictEqual(p.cls, 'bomber');
  const fr = f.parts.get('d:f0');
  place(f, p, [fr.pos.x, fr.pos.y, fr.pos.z - 1200], [0, 0, 1]);
  for (let n = 0; n < 8 && fr.hp > 0; n++) {
    p.torpedoes = 6;
    p.missileCd = 0;
    place(f, p, [fr.pos.x, fr.pos.y, fr.pos.z - 1200], [0, 0, 1]);
    assert.ok(SB.torpedo(f, 'P', { target: 'd:f0' }).ok);
    for (let i = 0; i < 80; i++) SB.step(f, 0.1);
  }
  assert.strictEqual(fr.hp, 0);
  assert.ok(['d:f0t0', 'd:f0t1'].every((id) => f.parts.get(id).hp === 0));
});

test('turrets track the nearest threat in range; power-ups are taken by flying through them', () => {
  const f = match();
  const p = SB.addPilot(f, 'P', 'a');
  park(f, [p]);
  const t = f.parts.get('d:t0');
  place(f, p, [t.pos.x, t.pos.y + 300, t.pos.z], [1, 0, 0]);
  p.hitAt = 1e9; // no shield recharge
  const hp = p.hp + p.shield;
  for (let i = 0; i < 100; i++) {
    place(f, p, [t.pos.x, t.pos.y + 300, t.pos.z], [1, 0, 0]);
    SB.step(f, 0.1);
  }
  assert.ok(p.hp + p.shield < hp, 'the turrets shot at it');
  f.drops.set(99, { id: 99, kind: 'shield', pos: { x: 0, y: 0, z: 10 } });
  Object.assign(p, { alive: true, hp: 100, moveT: f.t - 1 });
  place(f, p, [0, 0, -20], [0, 0, 1]);
  SB.move(f, 'P', { x: 0, y: 0, z: 0 });
  assert.strictEqual(p.shield, p.maxShield * 1.5);
  assert.strictEqual(f.drops.size, 0);
});

test('moves are limited to what the class could fly; flying into a hull hurts', () => {
  const f = match();
  const p = SB.addPilot(f, 'P', 'a');
  place(f, p, [0, 0, 0], [1, 0, 0]);
  p.moveT = f.t;
  SB.step(f, 1);
  SB.move(f, 'P', { x: 5000, y: 0, z: 0 });
  assert.ok(p.pos.x <= SB.CLASSES.fighter.boost * 1.3 + 31, `moved ${p.pos.x} m in a second`);
  const cap = f.capitals.d;
  const before = p.hp + p.shield;
  p.moveT = f.t - 10;
  SB.move(f, 'P', { x: cap.x, y: cap.y, z: cap.z });
  assert.ok(p.hp + p.shield < before);
});

test('AI-only battles end with a capital ship destroyed, or on damage after 15 minutes', () => {
  const f = match({ seed: 7 });
  SB.step(f, SB.MATCH_S);
  assert.ok(['a', 'd', 'draw'].includes(f.result));
  assert.ok(['destroyed', 'time'].includes(f.how));
  assert.ok(f.kills.a + f.kills.d > 10, 'they fought');
});

test("a shipyard world's holder flies with 10% more hull", () => {
  const f = match({ holder: 'compact', bonus: 'shipyard' });
  assert.strictEqual(f.hullBonus, 'd');
  const d = all(f, (c) => c.side === 'd')[0];
  const a = all(f, (c) => c.side === 'a')[0];
  assert.ok(Math.abs(d.maxHp - SB.CLASSES[d.cls].hull * 1.1) < 1e-9);
  assert.strictEqual(a.maxHp, SB.CLASSES[a.cls].hull);
});

test("a win adds 1% to the winner's orbital control of the system until the week ends; matchmaking scores 6 (half against AI)", () => {
  W.setDemo(true);
  const g = G.newGalaxy();
  let clock = C.DEMO_CYCLE_MS * 600;
  C.tick(g, clock);
  const wp = W.planet(g, 'cinder');
  const before = g.war.orbital[wp.system].ashen;
  const sent = [];
  const spaces = SB.createSpaces({
    now: () => clock,
    send: (c, m) => sent.push([c.name, m]),
    changed: () => {},
    onEnd: (f, w, vsAi) => {
      const pts = C.score(g, f.planet, 'space', w, vsAi, clock);
      W.spaceWin(g, wp.system, w, g.war.campaigns[f.planet].endsAt, SB.SPACE_WIN_SHARE, clock);
      return pts;
    },
  });
  spaces.close();
  const battles = { campaignMatches: () => [], room: () => false };
  const mm = C.createMatchmaking({ galaxy: () => g, now: () => clock, battles, spaces, where: (me) => ({ over: me.over }), factionOf: (me) => me.faction, send: (c, m) => sent.push([c.name, m]), changed: () => {}, wait: 5000 });
  mm.close();
  const a = { name: 'A', faction: 'ashen', over: 'cinder' };
  assert.ok(mm.join(a, 'cinder', 'space').ok);
  clock += 6000;
  mm.fill();
  const [f] = spaces.running('cinder');
  assert.deepStrictEqual([a.spaceMatch, f.factions.a, f.factions.d], [f.id, 'ashen', 'compact']);
  assert.ok(sent.some(([n, m]) => n === 'A' && m.type === 'starfight_joined' && m.parts.length > 10));
  f.result = 'a';
  f.how = 'destroyed';
  spaces.tick();
  assert.strictEqual(g.war.campaigns.cinder.points.ashen, 3);
  assert.ok(Math.abs(g.war.orbital[wp.system].ashen - (before + SB.SPACE_WIN_SHARE)) < 1e-9);
  // It runs out with the week.
  W.recompute(g, g.war.campaigns.cinder.endsAt + 1);
  assert.ok(Math.abs(g.war.orbital[wp.system].ashen - before) < 1e-9);
  W.setDemo(false);
});
