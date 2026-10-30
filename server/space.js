// Space Battles: a campaign game mode, starfighters over the planet, 15 minutes at most. Each side
// has a capital ship (for the match only: no Builder loses a real ship), two escort frigates, and
// 12 pilots' fighters (AI pilots fill the empty slots) with more AI fighters filling the sky. Destroy
// the enemy capital ship: first its two shield generators, then its three subsystems (engines,
// bridge, reactor). If neither falls in 15 minutes, the side that did more damage wins.
// Pilots pick a ship class every time they launch, from their own fleet carrier's hangar:
//   Fighter: fast, good against fighters (lasers and lock-on missiles);
//   Interceptor: fastest, light guns, a few missiles;
//   Bomber: slow and tough, torpedoes against capital ships.
// Capital ships and frigates have turrets that track the nearest threat; power-ups (shield boost,
// extra ordnance) come in front-supply drops. A win adds to the winner's orbital control of the
// system until the campaign week ends (war.js spaceWin), as well as its campaign points.
//
// Simulated here in 3D (metres; the sides face each other along z, side a to the south at -z).
// Pilots fly on their own screens with the game's flight model and report where they are
// (starfight_move) and every laser shot (starfight_fire); the server checks the speed and the rate of fire,
// decides what each shot hits (capital hulls and frigates block shots), flies the missiles,
// torpedoes and AI, and runs the turrets. In memory only.

const F = require('./factions');
const TM = require('./telemetry.ts');

const PILOTS = 12; // a side, AI pilots filling the empty slots...
const SKY = 6; // ...and this many more AI fighters
const MATCH_S = 900;
const RESPAWN_S = 5;
const TICK_MS = 100;
const STEP_S = 0.1;
const SNAPSHOT_MS = 100;
const END_KEEP_MS = 10_000;
const MOVES_PER_S = 30;
const SHOTS_PER_S = 20;
const ARENA = 6000; // |x|, |z| at most; |y| at most ARENA / 2
const CAPITAL_Z = 3000; // each capital ship this far from the middle
const HULL = [260, 50, 60]; // a capital ship's half size (x along its length)
const LASER_RANGE = 1500;
const MISSILE = { speed: 450, turn: 2.2, life: 6, hit: 15, lockRange: 2000, cone: 0.55 };
const TORPEDO = { speed: 220, turn: 0.9, life: 15, hit: 40, damage: 400, range: 2500, cone: 0.7 };
const SUPPLY_EVERY_S = 60;
const PICKUP_R = 50;
const SHIELD_DELAY_S = 5;
const SHIELD_RATE = 15;
const SPACE_WIN_SHARE = 0.01; // orbital control a win adds, until the week ends

// The ship classes. `speed`/`boost` in m/s (the game's small ship is 280/392); `turn` rad/s for
// the AI; `pitch`/`yaw`/`roll` for the pilots' flight model.
const CLASSES = {
  fighter: { name: 'Fighter', text: 'Fast and agile, good against fighters: lasers and lock-on missiles', hull: 100, shields: 100, speed: 300, boost: 420, turn: 1.0, pitch: 0.9, yaw: 0.5, roll: 2.0, laser: 9, gap: 0.12, missiles: 6, missileDamage: 60, torpedoes: 0, radius: 10 },
  interceptor: { name: 'Interceptor', text: 'The fastest, with light guns and a few missiles', hull: 70, shields: 60, speed: 360, boost: 480, turn: 1.2, pitch: 1.1, yaw: 0.6, roll: 2.4, laser: 6, gap: 0.08, missiles: 4, missileDamage: 45, torpedoes: 0, radius: 9 },
  bomber: { name: 'Bomber', text: 'Slow and tough: torpedoes against capital ships and frigates', hull: 160, shields: 120, speed: 220, boost: 300, turn: 0.6, pitch: 0.55, yaw: 0.3, roll: 1.4, laser: 7, gap: 0.2, missiles: 0, missileDamage: 0, torpedoes: 6, radius: 14 },
};

// A capital ship's parts, from its middle (x along its length, y up, z toward the enemy for
// side a; mirrored for d). `r`: how close a shot must pass. Subsystems can't be hurt while a
// shield generator stands.
const PARTS = [
  { key: 'gen0', kind: 'gen', name: 'Shield generator', at: [-150, 62, 0], r: 30, hp: 2500 },
  { key: 'gen1', kind: 'gen', name: 'Shield generator', at: [150, 62, 0], r: 30, hp: 2500 },
  { key: 'engines', kind: 'sub', name: 'Engines', at: [-275, 0, 0], r: 32, hp: 5000 },
  { key: 'bridge', kind: 'sub', name: 'Bridge', at: [130, 92, 0], r: 30, hp: 4000 },
  { key: 'reactor', kind: 'sub', name: 'Reactor', at: [0, -62, 0], r: 32, hp: 5500 },
  { key: 't0', kind: 'turret', name: 'Turret', at: [-200, 55, 55], r: 12, hp: 400 },
  { key: 't1', kind: 'turret', name: 'Turret', at: [200, 55, 55], r: 12, hp: 400 },
  { key: 't2', kind: 'turret', name: 'Turret', at: [-200, 55, -55], r: 12, hp: 400 },
  { key: 't3', kind: 'turret', name: 'Turret', at: [200, 55, -55], r: 12, hp: 400 },
  { key: 't4', kind: 'turret', name: 'Turret', at: [0, -55, 62], r: 12, hp: 400 },
  { key: 't5', kind: 'turret', name: 'Turret', at: [0, -55, -62], r: 12, hp: 400 },
];
const FRIGATES = [[-900, 0, 450], [900, 0, 450]]; // from the capital ship, toward the enemy
const FRIGATE = { r: 70, hp: 3000, turrets: [[0, 40, 0], [0, -40, 0]] };
const TURRET = { range: 1200, every: 0.6, damage: 10, odds: 0.35 };

function fail(reason) {
  return { ok: false, reason };
}

const r1 = (x) => Math.round(x * 10) / 10;
const num = (v) => typeof v === 'number' && Number.isFinite(v);
const other = (side) => (side === 'a' ? 'd' : 'a');
const v = (x = 0, y = 0, z = 0) => ({ x, y, z });
const add = (a, b) => v(a.x + b.x, a.y + b.y, a.z + b.z);
const sub = (a, b) => v(a.x - b.x, a.y - b.y, a.z - b.z);
const mul = (a, k) => v(a.x * k, a.y * k, a.z * k);
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const len = (a) => Math.hypot(a.x, a.y, a.z);
const norm = (a) => {
  const l = len(a) || 1;
  return v(a.x / l, a.y / l, a.z / l);
};
const dist = (a, b) => len(sub(a, b));

function random(state) {
  state.s = (state.s + 0x6d2b79f5) >>> 0;
  let t = state.s;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// Turns unit vector `from` toward `to` by at most `rate` radians.
function turn(from, to, rate) {
  const c = Math.max(-1, Math.min(1, dot(from, to)));
  const a = Math.acos(c);
  if (a <= rate || a < 1e-6) return to;
  const k = rate / a;
  return norm(add(mul(from, 1 - k), mul(to, k)));
}

// Where a ray from `o` along unit `d` first meets a sphere (c, r), or null.
function raySphere(o, d, c, r) {
  const oc = sub(o, c);
  const b = dot(oc, d);
  const q = dot(oc, oc) - r * r;
  const h = b * b - q;
  if (h < 0) return null;
  const t = -b - Math.sqrt(h);
  if (t >= 0) return t;
  return q <= 0 ? 0 : null;
}

// Where a ray first meets an axis-aligned box (centre c, half size h), or null.
function rayBox(o, d, c, h) {
  let t0 = 0;
  let t1 = Infinity;
  for (const k of ['x', 'y', 'z']) {
    const lo = c[k] - h[k === 'x' ? 0 : k === 'y' ? 1 : 2];
    const hi = c[k] + h[k === 'x' ? 0 : k === 'y' ? 1 : 2];
    if (Math.abs(d[k]) < 1e-9) {
      if (o[k] < lo || o[k] > hi) return null;
      continue;
    }
    let ta = (lo - o[k]) / d[k];
    let tb = (hi - o[k]) / d[k];
    if (ta > tb) [ta, tb] = [tb, ta];
    t0 = Math.max(t0, ta);
    t1 = Math.min(t1, tb);
    if (t0 > t1) return null;
  }
  return t0;
}

function insideBox(p, c, h, pad = 0) {
  return Math.abs(p.x - c.x) < h[0] + pad && Math.abs(p.y - c.y) < h[1] + pad && Math.abs(p.z - c.z) < h[2] + pad;
}

// --- A match ---------------------------------------------------------------------------------------

// A new match on `planet` between side a (`attacker`) and side d (`defender`). `bonus`: the
// planet's campaign bonus (a shipyard world gives its holder's fighters 10% more hull), `holder` the
// faction holding it.
function newSpace({ id = 'v1', planet, planetName = '', attacker, defender = null, holder = null, bonus = null, seed = 1, now = Date.now(), speed = 1 }) {
  const f = {
    id,
    planet,
    planetName,
    factions: { a: attacker, d: defender },
    rng: { s: seed >>> 0 },
    speed,
    startedAt: now,
    t: 0,
    nextId: 1,
    craft: new Map(), // id -> a fighter
    parts: new Map(), // id -> a capital ship's part, or a frigate (and its turrets)
    capitals: { a: v(0, 0, -CAPITAL_Z), d: v(0, 0, CAPITAL_Z) },
    carriers: { a: [], d: [] }, // pilots' fleet carriers: [{ name, pos }]
    hullBonus: bonus === 'shipyard' && holder ? (holder === attacker ? 'a' : holder === defender ? 'd' : null) : null,
    missiles: [],
    drops: new Map(),
    nextDrop: SUPPLY_EVERY_S / 2,
    damage: { a: 0, d: 0 }, // done to the other side's capital ship and frigates
    kills: { a: 0, d: 0 },
    shots: [],
    feed: [],
    result: null,
    how: null,
  };
  for (const side of ['a', 'd']) {
    const c = f.capitals[side];
    const s = side === 'a' ? 1 : -1; // toward the enemy
    for (const p of PARTS) f.parts.set(`${side}:${p.key}`, { id: `${side}:${p.key}`, side, kind: p.kind, name: p.name, pos: v(c.x + p.at[0], c.y + p.at[1], c.z + p.at[2] * s), r: p.r, hp: p.hp, maxHp: p.hp, cd: 0 });
    FRIGATES.forEach(([x, y, z], i) => {
      const pos = v(c.x + x, c.y + y, c.z + z * s);
      f.parts.set(`${side}:f${i}`, { id: `${side}:f${i}`, side, kind: 'frigate', name: 'Escort frigate', pos, r: FRIGATE.r, hp: FRIGATE.hp, maxHp: FRIGATE.hp, cd: 0 });
      FRIGATE.turrets.forEach(([tx, ty, tz], j) => f.parts.set(`${side}:f${i}t${j}`, { id: `${side}:f${i}t${j}`, side, kind: 'turret', name: 'Frigate turret', pos: v(pos.x + tx, pos.y + ty, pos.z + tz), r: 12, hp: 300, maxHp: 300, cd: 0, frigate: `${side}:f${i}` }));
    });
  }
  balance(f);
  return f;
}

// Where a side's fighters launch: a pilot's own carrier's hangar (carriers stand in a row behind
// the capital ship), the capital ship's hangar for the AI.
function launchPoint(f, c) {
  const s = c.side === 'a' ? 1 : -1;
  const cap = f.capitals[c.side];
  const carrier = f.carriers[c.side].find((k) => k.name === c.name);
  const base = carrier ? carrier.pos : add(cap, v(0, 0, (HULL[2] + 40) * s));
  const spread = (random(f.rng) - 0.5) * 120;
  return add(base, v(spread, (random(f.rng) - 0.5) * 60, (carrier ? 120 : 0) * s));
}

function launch(f, c) {
  const k = CLASSES[c.want] ? c.want : 'fighter';
  const cls = CLASSES[k];
  const hullMul = f.hullBonus === c.side ? 1.1 : 1;
  const s = c.side === 'a' ? 1 : -1;
  Object.assign(c, {
    cls: k,
    alive: true,
    pos: launchPoint(f, c),
    fwd: v(0, 0, s),
    up: v(0, 1, 0),
    vel: v(0, 0, 150 * s),
    hp: cls.hull * hullMul,
    maxHp: cls.hull * hullMul,
    shield: cls.shields,
    maxShield: cls.shields,
    hitAt: -100,
    missiles: cls.missiles,
    torpedoes: cls.torpedoes,
    lastShot: -100,
    missileCd: 0,
    cd: 0,
    moveT: f.t,
    history: [],
    breakUntil: 0,
    launchedAt: f.t,
  });
  c.history.push([f.t, c.pos.x, c.pos.y, c.pos.z]);
}

function newCraft(f, { id, name, side, ai = false, sky = false, want = 'fighter' }) {
  const c = { id, name, side, ai, sky, present: true, want, kills: 0, deaths: 0, respawnAt: 0 };
  f.craft.set(id, c);
  launch(f, c);
  return c;
}

const pilots = (f, side) => [...f.craft.values()].filter((c) => c.present && c.side === side && !c.sky);
const humans = (f, side) => pilots(f, side).filter((c) => !c.ai);

// Each side: PILOTS slots (AI pilots in the empty ones, stepping aside as pilots join), and the sky's
// AI fighters.
function balance(f) {
  for (const side of ['a', 'd']) {
    let p = pilots(f, side);
    while (p.length < PILOTS) {
      const n = f.nextId++;
      newCraft(f, { id: `ai${n}`, name: `Wing ${n}`, side, ai: true, want: ['fighter', 'fighter', 'interceptor', 'bomber'][n % 4] });
      p = pilots(f, side);
    }
    const ais = p.filter((c) => c.ai).sort((x, y) => Number(x.alive) - Number(y.alive));
    while (p.length > PILOTS && ais.length) {
      f.craft.delete(ais.shift().id);
      p = pilots(f, side);
    }
    const sky = [...f.craft.values()].filter((c) => c.side === side && c.sky).length;
    for (let i = sky; i < SKY; i++) {
      const n = f.nextId++;
      newCraft(f, { id: `sky${n}`, name: `Escort ${n}`, side, ai: true, sky: true, want: n % 3 === 0 ? 'interceptor' : 'fighter' });
    }
  }
}

function addPilot(f, name, side) {
  let c = f.craft.get(name);
  if (c) {
    c.present = true;
    return c;
  }
  // Their own fleet carrier joins the row behind the capital ship.
  const row = f.carriers[side];
  const s = side === 'a' ? 1 : -1;
  row.push({ name, pos: add(f.capitals[side], v(-700 + (row.length % 8) * 200, 40, -800 * s)) });
  c = newCraft(f, { id: name, name, side, want: 'fighter' });
  balance(f);
  return c;
}

function removePilot(f, name) {
  const c = f.craft.get(name);
  if (!c) return;
  c.present = false;
  c.alive = false;
  c.respawnAt = Infinity;
  balance(f);
}

// --- Flying and fighting -----------------------------------------------------------------------------

// starfight_move: where the pilot's ship is and which way it points. It can't have gone further than
// its class could fly since the last report (with slack), nor out of the battle space.
function move(f, name, msg) {
  const c = f.craft.get(name);
  if (!c?.present || !c.alive || c.ai || ![msg.x, msg.y, msg.z].every(num)) return { ok: true, quiet: true };
  const dt = Math.max(0.05, f.t - c.moveT);
  const want = v(msg.x, msg.y, msg.z);
  const step = sub(want, c.pos);
  const far = len(step);
  const most = CLASSES[c.cls].boost * 1.3 * dt + 30;
  c.pos = far > most ? add(c.pos, mul(step, most / far)) : want;
  c.pos.x = Math.max(-ARENA, Math.min(ARENA, c.pos.x));
  c.pos.y = Math.max(-ARENA / 2, Math.min(ARENA / 2, c.pos.y));
  c.pos.z = Math.max(-ARENA, Math.min(ARENA, c.pos.z));
  if ([msg.fx, msg.fy, msg.fz].every(num)) c.fwd = norm(v(msg.fx, msg.fy, msg.fz));
  if ([msg.ux, msg.uy, msg.uz].every(num)) c.up = norm(v(msg.ux, msg.uy, msg.uz));
  if ([msg.vx, msg.vy, msg.vz].every(num)) c.vel = v(msg.vx, msg.vy, msg.vz);
  c.moveT = f.t;
  c.history.push([f.t, c.pos.x, c.pos.y, c.pos.z]);
  while (c.history.length > 6) c.history.shift();
  // Flying into a capital ship's hull hurts.
  for (const cap of Object.values(f.capitals)) {
    if (insideBox(c.pos, cap, HULL, CLASSES[c.cls].radius)) {
      hurt(f, c, 60, null);
      c.pos = add(c.pos, mul(norm(sub(c.pos, cap)), 120));
    }
  }
  // Supply drops close enough are taken.
  for (const d of [...f.drops.values()]) if (dist(d.pos, c.pos) <= PICKUP_R) take(f, c, d);
  return { ok: true };
}

function take(f, c, d) {
  f.drops.delete(d.id);
  if (d.kind === 'shield') c.shield = c.maxShield * 1.5; // a boost past full, until it's shot off
  else {
    c.missiles += CLASSES[c.cls].missiles ? 3 : 0;
    c.torpedoes += CLASSES[c.cls].torpedoes ? 2 : 0;
  }
  f.feed.push({ name: c.name, took: d.kind, text: `${c.name} took a ${d.kind === 'shield' ? 'shield boost' : 'load of ordnance'}` });
}

// The things a shot can hit (or be stopped by) on the other side, and the hulls in the way.
function firstHit(f, c, o, d, range) {
  let best = null;
  let at = range;
  for (const cap of Object.values(f.capitals)) {
    const t = rayBox(o, d, cap, HULL);
    if (t !== null && t < at) [best, at] = [{ hull: true }, t];
  }
  for (const p of f.parts.values()) {
    if (p.hp <= 0) continue;
    const t = raySphere(o, d, p.pos, p.r);
    if (t === null || t >= at + (p.kind === 'frigate' ? 0 : p.r)) continue;
    // Frigates block shots at anything behind them; the other side's parts take them.
    if (p.side === c.side && p.kind !== 'frigate') continue;
    [best, at] = [p.side === c.side ? { hull: true } : { part: p }, Math.max(0, t)];
  }
  for (const t of f.craft.values()) {
    if (!t.alive || t.side === c.side) continue;
    // Lag-tolerant: the ray may pass the target where it is or anywhere it was in the last moments.
    const r = CLASSES[t.cls].radius + 6;
    let hitAt = null;
    for (const h of [[f.t, t.pos.x, t.pos.y, t.pos.z], ...t.history]) {
      if (f.t - h[0] > 0.35) continue;
      const k = raySphere(o, d, v(h[1], h[2], h[3]), r);
      if (k !== null && (hitAt === null || k < hitAt)) hitAt = k;
    }
    if (hitAt !== null && hitAt < at) [best, at] = [{ craft: t }, hitAt];
  }
  return { best, at };
}

// starfight_fire: one laser bolt along (dx, dy, dz) from the ship (within 10 degrees of its nose).
function fire(f, name, msg) {
  const c = f.craft.get(name);
  if (!c?.present || !c.alive || c.ai || f.result) return { ok: true, quiet: true };
  const cls = CLASSES[c.cls];
  if (f.t - c.lastShot < cls.gap * 0.8) return { ok: true, quiet: true };
  c.lastShot = f.t;
  let d = [msg.dx, msg.dy, msg.dz].every(num) ? norm(v(msg.dx, msg.dy, msg.dz)) : c.fwd;
  if (dot(d, c.fwd) < Math.cos(0.18)) d = c.fwd;
  return laser(f, c, d, cls.laser);
}

function laser(f, c, d, damage) {
  const o = add(c.pos, mul(d, CLASSES[c.cls].radius + 2));
  const { best, at } = firstHit(f, c, o, d, LASER_RANGE);
  const end = add(o, mul(d, at));
  f.shots.push([r1(o.x), r1(o.y), r1(o.z), r1(end.x), r1(end.y), r1(end.z), c.side]);
  if (best?.craft) hurt(f, best.craft, damage, c);
  else if (best?.part) hurtPart(f, best.part, damage, c);
  return { ok: true, hit: best?.craft?.id || best?.part?.id || null };
}

// starfight_missile: a lock-on missile at an enemy fighter in front (the screen did the locking; the
// server checks the target's in range and in front).
function missile(f, name, msg) {
  const c = f.craft.get(name);
  if (!c?.alive || f.result) return { ok: true, quiet: true };
  return launchMissile(f, c, f.craft.get(String(msg.target)));
}

function launchMissile(f, c, t) {
  if (c.missiles <= 0) return fail('no missiles left');
  if (f.t < c.missileCd) return fail('missiles reloading');
  if (!t?.alive || t.side === c.side) return fail('no target locked');
  const to = sub(t.pos, c.pos);
  if (len(to) > MISSILE.lockRange || dot(norm(to), c.fwd) < Math.cos(MISSILE.cone)) return fail('the target has to be ahead and in range');
  c.missiles -= 1;
  c.missileCd = f.t + 1.2;
  f.missiles.push({ id: f.nextId++, kind: 'missile', side: c.side, by: c.id, target: t.id, pos: add(c.pos, mul(c.fwd, 15)), dir: c.fwd, speed: MISSILE.speed, turn: MISSILE.turn, life: MISSILE.life, hit: MISSILE.hit, damage: CLASSES[c.cls].missileDamage });
  return { ok: true };
}

// starfight_torpedo: a bomber's torpedo at a part of the enemy capital ship, or a frigate.
function torpedo(f, name, msg) {
  const c = f.craft.get(name);
  if (!c?.alive || f.result) return { ok: true, quiet: true };
  return launchTorpedo(f, c, f.parts.get(String(msg.target)));
}

function launchTorpedo(f, c, p) {
  if (c.torpedoes <= 0) return fail(CLASSES[c.cls].torpedoes ? 'no torpedoes left' : 'only bombers carry torpedoes');
  if (f.t < c.missileCd) return fail('torpedo tube reloading');
  if (!p || p.hp <= 0 || p.side === c.side) return fail('no target for the torpedo');
  const to = sub(p.pos, c.pos);
  if (len(to) > TORPEDO.range || dot(norm(to), c.fwd) < Math.cos(TORPEDO.cone)) return fail('the target has to be ahead and in range');
  c.torpedoes -= 1;
  c.missileCd = f.t + 2;
  f.missiles.push({ id: f.nextId++, kind: 'torpedo', side: c.side, by: c.id, part: p.id, pos: add(c.pos, mul(c.fwd, 20)), dir: c.fwd, speed: TORPEDO.speed, turn: TORPEDO.turn, life: TORPEDO.life, hit: TORPEDO.hit, damage: TORPEDO.damage });
  return { ok: true };
}

function hurt(f, t, damage, by) {
  if (!t.alive || f.result) return;
  t.hitAt = f.t;
  const s = Math.min(t.shield, damage);
  t.shield -= s;
  t.hp -= damage - s;
  if (t.hp > 0) return;
  t.alive = false;
  t.hp = 0;
  t.deaths += 1;
  t.respawnAt = f.t + RESPAWN_S;
  if (by && by.side !== t.side) {
    by.kills += 1;
    f.kills[by.side] += 1;
  }
  if (!t.sky || (by && !by.ai)) f.feed.push({ kill: [by ? by.name : null, t.name], text: by ? `${by.name} shot down ${t.name}` : `${t.name} was destroyed` });
}

// Damage to a capital ship's part or a frigate. Subsystems are shielded while a generator stands.
function hurtPart(f, p, damage, by) {
  if (p.hp <= 0 || f.result) return;
  if (p.kind === 'sub' && genUp(f, p.side)) return;
  const dealt = Math.min(p.hp, damage);
  p.hp -= dealt;
  if (by) f.damage[other(p.side)] += dealt;
  if (p.hp > 0) return;
  const whose = shipName(f, p.side);
  if (p.kind === 'gen') f.feed.push({ text: `A shield generator on ${whose} is down${genUp(f, p.side) ? '' : ': its subsystems are open to attack'}` });
  else if (p.kind === 'sub') f.feed.push({ text: `${whose}: the ${p.name.toLowerCase()} is destroyed` });
  else if (p.kind === 'frigate') {
    f.feed.push({ text: `An escort frigate of ${whose} is destroyed` });
    for (const t of f.parts.values()) if (t.frigate === p.id) t.hp = 0;
  }
  if (p.kind === 'sub' && ['engines', 'bridge', 'reactor'].every((k) => f.parts.get(`${p.side}:${k}`).hp <= 0)) {
    f.feed.push({ text: `${whose} is destroyed` });
    [f.result, f.how] = [other(p.side), 'destroyed'];
  }
}

function genUp(f, side) {
  return f.parts.get(`${side}:gen0`).hp > 0 || f.parts.get(`${side}:gen1`).hp > 0;
}

function shipName(f, side) {
  const fac = f.factions[side];
  return fac && F.FACTIONS[fac] ? `the ${F.FACTIONS[fac].name.split(' ')[0]} capital ship` : 'the militia capital ship';
}

// --- The AI ---------------------------------------------------------------------------------------------

// What an AI pilot goes for: bombers the enemy capital ship's weak points (its shield generators
// first, then the subsystems), the rest the nearest enemy fighter.
function aiTarget(f, c) {
  if (c.cls === 'bomber') {
    const enemy = other(c.side);
    const gens = ['gen0', 'gen1'].map((k) => f.parts.get(`${enemy}:${k}`)).filter((p) => p.hp > 0);
    const list = gens.length ? gens : ['engines', 'bridge', 'reactor'].map((k) => f.parts.get(`${enemy}:${k}`)).filter((p) => p.hp > 0);
    const p = list.sort((x, y) => dist(x.pos, c.pos) - dist(y.pos, c.pos))[0];
    return p ? { part: p, pos: p.pos } : null;
  }
  let best = null;
  let bd = Infinity;
  for (const t of f.craft.values()) {
    if (!t.alive || t.side === c.side) continue;
    const d = dist(t.pos, c.pos) * (t.cls === 'bomber' ? 0.8 : 1); // bombers first, a little
    if (d < bd) [best, bd] = [t, d];
  }
  return best ? { craft: best, pos: best.pos } : null;
}

function aiStep(f, c, dt) {
  const cls = CLASSES[c.cls];
  const tgt = aiTarget(f, c);
  let want = c.fwd;
  if (tgt) {
    // Lead a moving target a little.
    const lead = tgt.craft ? add(tgt.pos, mul(tgt.craft.vel || v(), Math.min(1.5, dist(tgt.pos, c.pos) / 900))) : tgt.pos;
    want = norm(sub(lead, c.pos));
    // A bomber that's fired breaks off, then comes round again.
    if (c.cls === 'bomber' && f.t < c.breakUntil) want = norm(add(mul(want, -1), v(0, 0.4, 0)));
  }
  // Keep off the capital hulls and out of the edges of the battle.
  for (const cap of Object.values(f.capitals)) if (insideBox(c.pos, cap, HULL, 180)) want = norm(sub(c.pos, cap));
  if (Math.abs(c.pos.x) > ARENA * 0.9 || Math.abs(c.pos.z) > ARENA * 0.9 || Math.abs(c.pos.y) > ARENA * 0.4) want = norm(mul(c.pos, -1));
  c.fwd = turn(c.fwd, want, cls.turn * dt);
  const speedNow = cls.speed * (c.cls === 'bomber' && f.t < c.breakUntil ? 1.3 : 1);
  c.vel = mul(c.fwd, speedNow);
  c.pos = add(c.pos, mul(c.vel, dt));
  c.history.push([f.t, c.pos.x, c.pos.y, c.pos.z]);
  while (c.history.length > 6) c.history.shift();
  if (!tgt || f.result) return;
  const to = sub(tgt.pos, c.pos);
  const d = len(to);
  const ahead = dot(norm(to), c.fwd);
  // Lasers: in range and lined up; the odds fall with range (and against small, fast targets).
  if (d < 900 && ahead > Math.cos(0.1) && f.t - c.lastShot >= cls.gap * 2) {
    c.lastShot = f.t;
    const odds = 0.55 * (1 - d / 1200) * (tgt.craft?.cls === 'interceptor' ? 0.75 : 1);
    if (tgt.craft) {
      if (random(f.rng) < odds) hurt(f, tgt.craft, cls.laser, c);
      f.shots.push([r1(c.pos.x), r1(c.pos.y), r1(c.pos.z), r1(tgt.pos.x), r1(tgt.pos.y), r1(tgt.pos.z), c.side]);
    } else laser(f, c, norm(to), cls.laser);
  }
  if (tgt.craft && c.missiles > 0 && f.t >= c.missileCd && d < 1500 && ahead > Math.cos(0.26)) launchMissile(f, c, tgt.craft);
  if (tgt.part && c.torpedoes > 0 && f.t >= c.missileCd && d < 1200 && ahead > Math.cos(0.3) && launchTorpedo(f, c, tgt.part).ok) c.breakUntil = f.t + 5;
}

// --- The simulation ---------------------------------------------------------------------------------------

function missilesStep(f, dt) {
  for (const m of f.missiles) {
    m.life -= dt;
    const target = m.kind === 'missile' ? f.craft.get(m.target) : f.parts.get(m.part);
    const alive = m.kind === 'missile' ? target?.alive : target?.hp > 0;
    if (alive) m.dir = turn(m.dir, norm(sub(target.pos, m.pos)), m.turn * dt);
    m.pos = add(m.pos, mul(m.dir, m.speed * dt));
    if (alive && dist(m.pos, target.pos) <= m.hit + (m.kind === 'torpedo' ? target.r : 0)) {
      const by = f.craft.get(m.by) || null;
      if (m.kind === 'missile') hurt(f, target, m.damage, by);
      else hurtPart(f, target, m.damage, by);
      m.life = 0;
      f.shots.push([r1(m.pos.x), r1(m.pos.y), r1(m.pos.z), r1(m.pos.x), r1(m.pos.y), r1(m.pos.z), m.kind]);
    }
    // A missile that hits a hull is gone.
    for (const cap of Object.values(f.capitals)) if (m.life > 0 && insideBox(m.pos, cap, HULL)) m.life = 0;
  }
  f.missiles = f.missiles.filter((m) => m.life > 0);
}

// Turrets track the nearest threat in range: fighters, and torpedoes coming for their ship.
function turretsStep(f, dt) {
  for (const t of f.parts.values()) {
    if (t.kind !== 'turret' || t.hp <= 0) continue;
    t.cd -= dt;
    if (t.cd > 0) continue;
    let best = null;
    let bd = TURRET.range;
    for (const c of f.craft.values()) {
      if (!c.alive || c.side === t.side) continue;
      const d = dist(c.pos, t.pos);
      if (d < bd) [best, bd] = [c, d];
    }
    if (!best) continue;
    t.cd = TURRET.every;
    const odds = TURRET.odds * (1 - bd / (TURRET.range * 1.25)) * (best.cls === 'interceptor' ? 0.7 : best.cls === 'bomber' ? 1.3 : 1);
    if (random(f.rng) < odds) hurt(f, best, TURRET.damage, null);
    f.shots.push([r1(t.pos.x), r1(t.pos.y), r1(t.pos.z), r1(best.pos.x), r1(best.pos.y), r1(best.pos.z), `turret-${t.side}`]);
  }
}

function dropsStep(f) {
  if (f.t < f.nextDrop) return;
  f.nextDrop = f.t + SUPPLY_EVERY_S;
  const d = { id: f.nextId++, kind: random(f.rng) < 0.5 ? 'shield' : 'ordnance', pos: v((random(f.rng) - 0.5) * 2400, (random(f.rng) - 0.5) * 600, (random(f.rng) - 0.5) * 2400) };
  f.drops.set(d.id, d);
  f.feed.push({ text: `Front supply drop: ${d.kind === 'shield' ? 'a shield boost' : 'ordnance'}` });
}

function tick(f, dt) {
  f.t += dt;
  for (const c of f.craft.values()) {
    if (!c.present) continue;
    if (!c.alive && f.t >= c.respawnAt) launch(f, c);
    if (!c.alive) continue;
    if (c.shield < c.maxShield && f.t - c.hitAt >= SHIELD_DELAY_S) c.shield = Math.min(c.maxShield, c.shield + SHIELD_RATE * dt);
    if (c.ai) aiStep(f, c, dt);
  }
  missilesStep(f, dt);
  turretsStep(f, dt);
  dropsStep(f);
  if (!f.result && f.t >= MATCH_S) {
    [f.result, f.how] = [f.damage.a > f.damage.d ? 'a' : f.damage.d > f.damage.a ? 'd' : 'draw', 'time'];
  }
}

function step(f, dt) {
  for (let left = dt; left > 1e-9 && !f.result; left -= STEP_S) tick(f, Math.min(STEP_S, left));
}

// --- What the pilots see -----------------------------------------------------------------------------------

function frame(f) {
  const out = {
    match: f.id,
    t: r1(f.t),
    left: Math.max(0, Math.round(MATCH_S - f.t)),
    damage: { a: Math.round(f.damage.a), d: Math.round(f.damage.d) },
    kills: { ...f.kills },
    craft: [...f.craft.values()].filter((c) => c.present).map((c) => [c.id, c.name, c.side, c.cls, r1(c.pos.x), r1(c.pos.y), r1(c.pos.z), r1(c.fwd.x * 100) / 100, r1(c.fwd.y * 100) / 100, r1(c.fwd.z * 100) / 100, r1(c.up.x * 100) / 100, r1(c.up.y * 100) / 100, r1(c.up.z * 100) / 100, Math.round((100 * (c.hp + c.shield)) / (c.maxHp + c.maxShield)), c.alive, c.ai, c.kills, c.deaths, c.sky ? 1 : 0]),
    parts: [...f.parts.values()].map((p) => [p.id, Math.round(p.hp)]),
    missiles: f.missiles.map((m) => [m.id, m.kind, r1(m.pos.x), r1(m.pos.y), r1(m.pos.z)]),
    drops: [...f.drops.values()].map((d) => [d.id, d.kind, r1(d.pos.x), r1(d.pos.y), r1(d.pos.z)]),
    shots: f.shots,
    feed: f.feed,
    result: f.result,
  };
  f.shots = [];
  f.feed = [];
  return out;
}

function stateFor(f, fr, name) {
  const c = f.craft.get(name);
  return {
    type: 'starfight_state',
    ...fr,
    me: c ? { side: c.side, cls: c.cls, want: c.want, alive: c.alive, respawnIn: c.alive ? 0 : r1(Math.max(0, c.respawnAt - f.t)), hp: Math.round(c.hp), maxHp: Math.round(c.maxHp), shield: Math.round(c.shield), maxShield: Math.round(c.maxShield), missiles: c.missiles, torpedoes: c.torpedoes, kills: c.kills, x: r1(c.pos.x), y: r1(c.pos.y), z: r1(c.pos.z) } : null,
  };
}

function joined(f, name) {
  const c = f.craft.get(name);
  return {
    type: 'starfight_joined',
    match: f.id,
    planet: f.planet,
    planetName: f.planetName,
    side: c.side,
    factions: f.factions,
    seconds: MATCH_S,
    classes: CLASSES,
    capitals: Object.fromEntries(Object.entries(f.capitals).map(([s, p]) => [s, { pos: [p.x, p.y, p.z], half: HULL, name: shipName(f, s) }])),
    parts: [...f.parts.values()].map((p) => ({ id: p.id, side: p.side, kind: p.kind, name: p.name, pos: [r1(p.pos.x), r1(p.pos.y), r1(p.pos.z)], r: p.r, maxHp: p.maxHp })),
    carriers: { a: f.carriers.a.map((k) => ({ name: k.name, pos: [k.pos.x, k.pos.y, k.pos.z] })), d: f.carriers.d.map((k) => ({ name: k.name, pos: [k.pos.x, k.pos.y, k.pos.z] })) },
    hullBonus: f.hullBonus,
    laserRange: LASER_RANGE,
    missile: { lockRange: MISSILE.lockRange, cone: MISSILE.cone },
    torpedo: { range: TORPEDO.range, cone: TORPEDO.cone },
    arena: ARENA,
    start: { pos: [c.pos.x, c.pos.y, c.pos.z], fwd: [c.fwd.x, c.fwd.y, c.fwd.z] },
  };
}

// --- The server's matches --------------------------------------------------------------------------------

// Space Battles a server runs. `onEnd(f, winner, vsAi)` scores the result (campaign points and
// orbital control) and returns the points.
function createSpaces({ now = Date.now, speed = 1, send, changed, onEnd = null }) {
  const matches = new Map();
  const conns = new Map();
  let nextId = 1;
  let ticks = 0;
  const timers = new Set();

  function start(planet, planetName, attacker, defender, opts = {}) {
    const n = nextId++;
    const f = newSpace({ id: `v${n}`, planet, planetName, attacker, defender, seed: (Date.now() ^ (n * 2654435761)) >>> 0, now: now(), speed, ...opts });
    matches.set(f.id, f);
    conns.set(f.id, new Map());
    return f;
  }

  function enlist(me, f, side) {
    if (me.spaceMatch && me.spaceMatch !== f.id) leave(me);
    addPilot(f, me.name, side);
    conns.get(f.id).set(me.name, me);
    me.spaceMatch = f.id;
    send(me, joined(f, me.name));
    changed();
    return { ok: true, match: f.id };
  }

  function leave(me) {
    const f = me.spaceMatch && matches.get(me.spaceMatch);
    me.spaceMatch = null;
    if (!f) return { ok: true };
    if (conns.get(f.id)?.get(me.name) === me) {
      conns.get(f.id).delete(me.name);
      removePilot(f, me.name);
      if (!f.result && !['a', 'd'].some((s) => humans(f, s).length)) [f.result, f.how] = ['draw', 'abandoned'];
      changed();
    }
    return { ok: true };
  }

  function handle(me, msg) {
    if (msg.type === 'starfight_leave') return leave(me);
    const f = me.spaceMatch && matches.get(me.spaceMatch);
    if (!f || f.result || String(msg.match) !== f.id) return { ok: true, quiet: true };
    const t = Date.now();
    const key = msg.type === 'starfight_move' ? 'moves' : 'shots';
    const cap = msg.type === 'starfight_move' ? MOVES_PER_S : SHOTS_PER_S;
    me.spaceWindow ||= {};
    if (t - (me.spaceWindow[key + 'At'] || 0) >= 1000) [me.spaceWindow[key + 'At'], me.spaceWindow[key]] = [t, 0];
    if (++me.spaceWindow[key] > cap) return { ok: true, quiet: true };
    switch (msg.type) {
      case 'starfight_move':
        return move(f, me.name, msg);
      case 'starfight_fire':
        return fire(f, me.name, msg);
      case 'starfight_missile':
        return missile(f, me.name, msg);
      case 'starfight_torpedo':
        return torpedo(f, me.name, msg);
      case 'starfight_class': {
        // The class to launch with next life (or now, if this one has only just launched).
        const c = f.craft.get(me.name);
        if (!c || !CLASSES[msg.cls]) return fail('no such ship class');
        c.want = msg.cls;
        if (c.alive && f.t - c.launchedAt < 10 && c.cls !== msg.cls) launch(f, c);
        return { ok: true };
      }
      default:
        return fail(`unknown message ${msg.type}`);
    }
  }

  function finish(f) {
    const winner = f.result === 'a' || f.result === 'd' ? f.factions[f.result] : null;
    const vsAi = !humans(f, 'a').length || !humans(f, 'd').length;
    const pts = winner && onEnd ? onEnd(f, winner, vsAi) : 0;
    const how = f.how === 'destroyed' ? `${shipName(f, other(f.result))} destroyed` : f.how === 'time' ? `more damage done in 15 minutes, ${f.damage.a} to ${f.damage.d}` : '';
    const text = f.how === 'abandoned' ? 'The battle ended: everyone left' : winner ? `${F.FACTIONS[winner].name} won the Space Battle (${how}): +${pts} campaign points on ${f.planetName}, and 1% more orbital control until the week ends` : `A draw: no campaign points`;
    const fr = frame(f);
    for (const [name, c] of conns.get(f.id)) {
      send(c, stateFor(f, fr, name));
      send(c, { type: 'starfight_end', match: f.id, winner: f.result, won: f.craft.get(name)?.side === f.result, text });
    }
    changed();
    const timer = setTimeout(() => {
      timers.delete(timer);
      matches.delete(f.id);
      for (const c of conns.get(f.id)?.values() || []) if (c.spaceMatch === f.id) c.spaceMatch = null;
      conns.delete(f.id);
    }, END_KEEP_MS);
    timers.add(timer);
  }

  function tickAll() {
    ticks++;
    const snap = ticks % Math.max(1, Math.round(SNAPSHOT_MS / TICK_MS)) === 0;
    for (const f of matches.values()) {
      if (f.ended) continue;
      if (!f.result) step(f, (TICK_MS / 1000) * speed);
      if (f.result) {
        f.ended = true;
        finish(f);
        continue;
      }
      if (!snap) continue;
      const fr = frame(f);
      for (const [name, c] of conns.get(f.id)) send(c, stateFor(f, fr, name));
    }
  }
  const ticker = setInterval(TM.timed('space', tickAll), TICK_MS);

  function running(planet) {
    return [...matches.values()].filter((f) => !f.result && f.planet === planet);
  }

  function room(f, side) {
    return humans(f, side).length < PILOTS;
  }

  function list() {
    return [...matches.values()]
      .filter((f) => !f.result)
      .map((f) => ({ id: f.id, planet: f.planet, attacker: f.factions.a, defender: f.factions.d, damage: { a: Math.round(f.damage.a), d: Math.round(f.damage.d) }, pilots: [...f.craft.values()].filter((c) => c.present && !c.ai).map((c) => c.name) }));
  }

  function close() {
    clearInterval(ticker);
    for (const t of timers) clearTimeout(t);
  }

  return { matches, start, enlist, leave, handle, running, room, list, tick: tickAll, close };
}

module.exports = {
  PILOTS,
  SKY,
  MATCH_S,
  RESPAWN_S,
  CLASSES,
  PARTS,
  FRIGATE,
  TORPEDO,
  MISSILE,
  HULL,
  SPACE_WIN_SHARE,
  newSpace,
  addPilot,
  removePilot,
  move,
  fire,
  missile,
  torpedo,
  hurt,
  hurtPart,
  step,
  frame,
  stateFor,
  joined,
  createSpaces,
};
