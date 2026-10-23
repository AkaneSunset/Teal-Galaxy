// Sector Defense: a campaign game mode in the spirit of Halo's Firefight. A squad of 1 to 4 pilots
// of one faction holds a position on the planet against waves of AI troops: 3 sets of 5 waves,
// each wave harder than the last, a boss ending each set. The squad shares a pool of lives (a few
// more after each set), modifiers switch on as the sets go on, and supply drops land between waves.
// Surviving every wave wins the match for the squad's faction; losing every life wins it for the
// enemy's. After the last wave the bonus round starts: endless waves, every kill scoring extra
// campaign points, until the squad falls (that can't undo the win). Some maps have something to
// defend (a shield generator): if the enemy destroys it the match is lost; the others are survival.
//
// Simulated here on the server in 2D (x and z in metres over a square arena SIZE across, (0, 0)
// at a corner), like the sector battles: the enemies move and shoot here. Pilots move on their own
// screens and report where they are (defense_move) and every shot they fire (defense_fire, a ray
// from the eye); the server decides what each shot hits, so the squad shares one fight. Cover
// blocks fire both ways: the server checks every shot, the pilots' and the enemies', against it.
// In memory only: a server restart ends every match with no result.

const F = require('./factions');

const SIZE = 120; // the arena is SIZE x SIZE metres
const SQUAD_MAX = 4;
const TICK_MS = 100; // the simulation steps this often (real time)...
const STEP_S = 0.1; // ...and never more than this much simulated time in one step
const SNAPSHOT_MS = 100; // defense_state to every pilot this often
const END_KEEP_MS = 10_000;
const SETS = 3;
const WAVES = 5; // per set; the last one of each set brings a boss
const WAVE_BREAK_S = 10; // between waves...
const SET_BREAK_S = 20; // ...and between sets
const FIRST_BREAK_S = 12; // before the first wave: time to look round
const LIVES = 7; // the squad's shared lives at the start...
const LIVES_PER_SET = 3; // ...and how many more after each set
const RESPAWN_S = 5;
const HP = 100;
const SHIELD = 60;
const SHIELD_DELAY_S = 4; // shields recharge this long after the last hit...
const SHIELD_RATE = 25; // ...this fast
const PICKUP_R = 2.5; // metres to take a supply drop
const EYE = 1.6;
const MOVES_PER_S = 30;
const SHOTS_PER_S = 15;
const MAX_SPEED = 9; // metres a second a pilot may move between reports (sprint, plus slack)
const BONUS_KILLS_PER_POINT = 10; // in the bonus round, a campaign point for every this many kills
const CHEST = 1.1; // where enemies aim at a pilot...
const HEAD = 1.6; // ...or, when only that shows over cover, here (and they hit half as often)
const OBJECTIVE_REPAIR = 0.25; // the objective gets back this share of its health in every break
const OBJECTIVE_GOAL = 0.5; // on objective maps, this share of each wave goes for the objective
const OBJECTIVE_GUARD_R = 10; // ...unless a pilot they can see is this close

// Campaign points the bonus round adds to a win.
function bonusPoints(d) {
  return Math.floor(d.bonusKills / BONUS_KILLS_PER_POINT);
}

// The pilots' weapons. The rifle never runs out here (ammo crates top up what the screen counts);
// the rocket launcher is a power weapon from supply drops, its rockets counted here.
const WEAPONS = {
  rifle: { name: 'Rifle', damage: 34, range: 120, gap: 0.1 },
  rocket: { name: 'Rocket launcher', damage: 260, range: 150, gap: 1.0, splash: 5, rounds: 4 },
};

// The enemy troops. `height`: how tall they stand (for hits); `melee`: they close in to strike.
const ENEMIES = {
  grunt: { name: 'Trooper', hp: 70, speed: 3.6, damage: 5, reload: 0.9, range: 28, radius: 0.5, height: 1.8 },
  elite: { name: 'Elite', hp: 180, speed: 4.2, damage: 8, reload: 0.6, range: 32, radius: 0.55, height: 2.0 },
  brute: { name: 'Brute', hp: 360, speed: 5.0, damage: 28, reload: 1.2, range: 2.5, radius: 0.8, height: 2.3, melee: true },
  drone: { name: 'Drone', hp: 55, speed: 6.5, damage: 4, reload: 0.7, range: 24, radius: 0.5, height: 1.0, fly: 3.5 },
  boss: { name: 'Warlord', hp: 2600, speed: 3.0, damage: 22, reload: 1.0, range: 40, radius: 1.2, height: 3.2 },
};

// What switches on as the sets go on (Firefight's skulls): from set 2 tougher enemies, from set 3
// harder-hitting ones and fewer supply drops.
const MODIFIERS = {
  tough: { name: 'Tough', text: 'Enemies have 50% more health', from: 2, hp: 1.5 },
  fury: { name: 'Fury', text: 'Enemies hit 40% harder', from: 3, damage: 1.4 },
  famine: { name: 'Famine', text: 'Fewer supply drops', from: 3, drops: 0.5 },
};

// Cover in the arena: [x, z, width, depth, height], centred on (x, z). The same for everyone;
// clients draw it and collide with it, and it stops shots and rockets, both ways.
const COVER = [
  [60, 60, 10, 10, 1.4], [40, 40, 6, 2, 1.2], [80, 40, 6, 2, 1.2], [40, 80, 6, 2, 1.2], [80, 80, 6, 2, 1.2],
  [60, 30, 3, 8, 2.6], [60, 90, 3, 8, 2.6], [30, 60, 8, 3, 2.6], [90, 60, 8, 3, 2.6],
  [22, 22, 4, 4, 3.0], [98, 22, 4, 4, 3.0], [22, 98, 4, 4, 3.0], [98, 98, 4, 4, 3.0],
];

// The maps. Survival maps are only the waves; objective maps also have something the squad must
// keep standing (`objective`: [x, z, width, depth, height] like cover, and its health).
const MAPS = {
  outpost: { name: 'Outpost', text: 'Survive every wave', cover: COVER, objective: null },
  ridge: {
    name: 'Ridge',
    text: 'Survive every wave',
    cover: [
      [60, 45, 24, 2, 1.2], [60, 75, 24, 2, 1.2], [36, 60, 2, 14, 2.6], [84, 60, 2, 14, 2.6],
      [30, 30, 6, 6, 3.0], [90, 30, 6, 6, 3.0], [30, 90, 6, 6, 3.0], [90, 90, 6, 6, 3.0],
      [60, 18, 8, 3, 1.4], [60, 102, 8, 3, 1.4], [18, 60, 3, 8, 1.4], [102, 60, 3, 8, 1.4],
    ],
    objective: null,
  },
  relay: {
    name: 'Relay Station',
    text: 'Defend the shield generator: if it falls, the sector is lost',
    cover: [
      [60, 44, 12, 2, 1.2], [60, 76, 12, 2, 1.2], [44, 60, 2, 12, 1.2], [76, 60, 2, 12, 1.2],
      [40, 40, 4, 4, 2.6], [80, 40, 4, 4, 2.6], [40, 80, 4, 4, 2.6], [80, 80, 4, 4, 2.6],
      [60, 24, 3, 8, 2.6], [60, 96, 3, 8, 2.6], [24, 60, 8, 3, 2.6], [96, 60, 8, 3, 2.6],
    ],
    objective: { kind: 'generator', name: 'Shield generator', box: [60, 60, 6, 6, 3.2], hp: 4000 },
  },
};
const MAP_IDS = Object.keys(MAPS);
const SPAWNS = [[60, 4], [116, 60], [60, 116], [4, 60]]; // where waves come in: the arena's edges
const PLAYER_SPAWNS = [[55, 52], [65, 52], [55, 68], [65, 68]];

function fail(reason) {
  return { ok: false, reason };
}

const r1 = (x) => Math.round(x * 10) / 10;
const r2 = (x) => Math.round(x * 100) / 100;
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const num = (v) => typeof v === 'number' && Number.isFinite(v);

// mulberry32, so a match's waves and drops are the same for the same seed.
function random(state) {
  state.s = (state.s + 0x6d2b79f5) >>> 0;
  let t = state.s;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// The modifiers on in set `set`.
function modifiersFor(set) {
  return Object.keys(MODIFIERS).filter((m) => set >= MODIFIERS[m].from);
}

// What wave `wave` (1-5) of set `set` (1-3) sends, for a squad of `squad`: [[type, count], ...].
// The bonus round is set SETS + 1, its waves counting up without end (a boss every fifth).
function waveOf(set, wave, squad = 1) {
  const extra = Math.max(0, squad - 1);
  const k = (set - 1) * WAVES + wave; // 1 to 15
  const out = [['grunt', 3 + Math.ceil(k / 2) + extra * 2]];
  if (k >= 2) out.push(['drone', Math.floor(k / 3) + extra]);
  if (k >= 3) out.push(['elite', Math.floor((k - 1) / 3) + extra]);
  if (k >= 4) out.push(['brute', Math.floor((k - 2) / 4) + Math.floor(extra / 2)]);
  if (wave % WAVES === 0) out.push(['boss', 1]);
  return out.filter(([, n]) => n > 0);
}

// A new match on planet `planetName` for the squad's `faction` against `enemy` (a faction's AI
// troops, or null for the militia). `seed` fixes its waves and drops, and the map unless `map`
// names one. `fortress`: the squad's faction holds a fortress world. Times are in simulated seconds.
function newDefense({ id = 'd1', planet, planetName, faction, enemy = null, seed = 1, now = Date.now(), speed = 1, map = null, fortress = false }) {
  const mapId = MAPS[map] ? map : MAP_IDS[(seed >>> 0) % MAP_IDS.length];
  const o = MAPS[mapId].objective;
  return {
    id,
    planet,
    planetName,
    faction,
    enemy,
    seed,
    rng: { s: seed >>> 0 },
    speed,
    map: mapId,
    cover: MAPS[mapId].cover,
    objective: o ? { kind: o.kind, name: o.name, box: o.box, hp: o.hp, maxHp: o.hp, warned: 1 } : null,
    startedAt: now,
    t: 0,
    set: 1,
    wave: 0, // 0 before the first wave
    phase: 'break', // 'break' between waves, 'wave' while one is on
    breakUntil: FIRST_BREAK_S,
    lives: LIVES + (fortress ? LIVES_PER_SET : 0), // a fortress world's holder: an extra wave of lives
    nextId: 1,
    enemies: new Map(),
    pilots: new Map(), // name -> { name, x, z, yaw, hp, shield, hitAt, alive, respawnAt, present, rockets, kills, moveT }
    pickups: new Map(), // id -> { id, kind, x, z }
    shots: [], // what happened since the last snapshot: [from, x, z, tx, tz]
    feed: [],
    kills: 0,
    bonus: false, // the bonus round is on: the match is won whatever happens now
    bonusKills: 0,
    result: null, // 'won' or 'lost'
  };
}

// --- Pilots ----------------------------------------------------------------------------------

function addPilot(d, name) {
  let p = d.pilots.get(name);
  if (!p) {
    const [x, z] = PLAYER_SPAWNS[d.pilots.size % PLAYER_SPAWNS.length];
    d.pilots.set(name, (p = { name, x, z, yaw: 0, hp: HP, shield: SHIELD, hitAt: -100, alive: true, respawnAt: 0, present: true, rockets: 0, kills: 0, deaths: 0, moveT: 0, lastShot: -100 }));
  }
  p.present = true;
  return p;
}

function removePilot(d, name) {
  const p = d.pilots.get(name);
  if (p) p.present = false;
}

function present(d) {
  return [...d.pilots.values()].filter((p) => p.present);
}

// defense_move: where a pilot stands and faces, as their screen has it. A pilot can't be further
// than they could have run since the last report (the server's limit on cheating), nor off the map.
function move(d, name, msg) {
  const p = d.pilots.get(name);
  if (!p?.present || !p.alive || !num(msg.x) || !num(msg.z)) return { ok: true, quiet: true };
  const dt = Math.max(0.05, d.t - p.moveT);
  const dx = msg.x - p.x;
  const dz = msg.z - p.z;
  const far = Math.hypot(dx, dz);
  const most = MAX_SPEED * dt + 1;
  const k = far > most ? most / far : 1;
  p.x = clamp(p.x + dx * k, 0.5, SIZE - 0.5);
  p.z = clamp(p.z + dz * k, 0.5, SIZE - 0.5);
  if (num(msg.yaw)) p.yaw = msg.yaw;
  p.moveT = d.t;
  // Supply drops close enough are taken.
  for (const u of [...d.pickups.values()]) if (Math.hypot(u.x - p.x, u.z - p.z) <= PICKUP_R) take(d, p, u);
  return { ok: true };
}

// A pilot takes a supply drop: health, a shield recharge, ammo (their screen refills it), or a
// rocket launcher (its rockets counted here).
function take(d, p, u) {
  d.pickups.delete(u.id);
  if (u.kind === 'health') p.hp = HP;
  else if (u.kind === 'shield') p.shield = SHIELD;
  else if (u.kind === 'rocket') p.rockets += WEAPONS.rocket.rounds;
  d.feed.push({ name: p.name, took: u.kind });
}

// --- Cover ------------------------------------------------------------------------------------

// What stops shots and bodies: the map's cover, and the objective while it stands.
function blockers(d) {
  return d.objective && d.objective.hp > 0 ? [...d.cover, d.objective.box] : d.cover;
}

// Where the segment from a to b (points {x, y, z}) first enters a box [x, z, width, depth, height]
// standing on the ground: the share of the way along it, or null if it misses.
function segBox(a, b, box) {
  const [cx, cz, w, dd, h] = box;
  const lo = [cx - w / 2, 0, cz - dd / 2];
  const hi = [cx + w / 2, h, cz + dd / 2];
  const o = [a.x, a.y, a.z];
  const v = [b.x - a.x, b.y - a.y, b.z - a.z];
  let t0 = 0;
  let t1 = 1;
  for (let i = 0; i < 3; i++) {
    if (Math.abs(v[i]) < 1e-9) {
      if (o[i] < lo[i] || o[i] > hi[i]) return null;
      continue;
    }
    let ta = (lo[i] - o[i]) / v[i];
    let tb = (hi[i] - o[i]) / v[i];
    if (ta > tb) [ta, tb] = [tb, ta];
    t0 = Math.max(t0, ta);
    t1 = Math.min(t1, tb);
    if (t0 > t1) return null;
  }
  return t0;
}

// The share of the way from a to b where cover first stops a shot (1 if nothing does).
// `skip`: a box the shot is aimed at, so it doesn't stop itself.
function blocked(d, a, b, skip = null) {
  let t = 1;
  for (const box of blockers(d)) {
    if (box === skip) continue;
    const h = segBox(a, b, box);
    if (h !== null && h < t) t = h;
  }
  return t;
}

function clear(d, a, b, skip = null) {
  return blocked(d, a, b, skip) >= 1;
}

// How far (x, z) is from a box's footprint (0 inside it), and the nearest point of it.
function boxNear(box, x, z) {
  const [cx, cz, w, dd] = box;
  const qx = clamp(x, cx - w / 2, cx + w / 2);
  const qz = clamp(z, cz - dd / 2, cz + dd / 2);
  return { r: Math.hypot(x - qx, z - qz), x: qx, z: qz };
}

// A body of radius `r` at (x, z), pushed out of any cover it overlaps.
function pushOut(d, x, z, r) {
  for (const box of blockers(d)) {
    const q = boxNear(box, x, z);
    if (q.r >= r) continue;
    if (q.r > 1e-6) {
      x = q.x + ((x - q.x) / q.r) * r;
      z = q.z + ((z - q.z) / q.r) * r;
      continue;
    }
    // Inside it: out by the nearest side.
    const [cx, cz, w, dd] = box;
    const out = [
      [cx - w / 2 - r - x, 0],
      [cx + w / 2 + r - x, 0],
      [0, cz - dd / 2 - r - z],
      [0, cz + dd / 2 + r - z],
    ].sort((m, n) => Math.abs(m[0] + m[1]) - Math.abs(n[0] + n[1]))[0];
    x += out[0];
    z += out[1];
  }
  return [x, z];
}

// Distance from the ray (o, dir) to a standing enemy (a vertical segment), and how far along the
// ray that is; null if the ray misses it or it's out of range.
function rayHit(o, dir, e, range) {
  const c = ENEMIES[e.type];
  const base = c.fly || 0;
  // Closest approach in the ground plane.
  const len2 = dir.x * dir.x + dir.z * dir.z;
  if (len2 < 1e-9) return null;
  let t = ((e.x - o.x) * dir.x + (e.z - o.z) * dir.z) / len2;
  if (t < 0) return null;
  const px = o.x + dir.x * t;
  const pz = o.z + dir.z * t;
  const miss = Math.hypot(px - e.x, pz - e.z);
  if (miss > c.radius + 0.25) return null;
  const y = o.y + dir.y * t;
  if (y < base - 0.2 || y > base + c.height + 0.2) return null;
  const along = t * Math.sqrt(len2 + dir.y * dir.y);
  return along <= range ? along : null;
}

// defense_fire: a pilot fired `weapon` from (x, y, z) along (dx, dy, dz). The rifle hits the
// nearest enemy on the ray; a rocket bursts on the first enemy in its way (or at full range) and
// hurts everything within its splash.
function fire(d, name, msg) {
  const p = d.pilots.get(name);
  if (!p?.present || !p.alive || d.result) return { ok: true, quiet: true };
  const w = WEAPONS[msg.weapon] ? msg.weapon : 'rifle';
  const def = WEAPONS[w];
  if (w === 'rocket' && p.rockets <= 0) return fail('no rockets left');
  if (d.t - p.lastShot < def.gap * 0.8) return { ok: true, quiet: true };
  if (w === 'rocket') p.rockets -= 1;
  p.lastShot = d.t;
  if (![msg.dx, msg.dy, msg.dz].every(num)) return { ok: true, quiet: true };
  const n = Math.hypot(msg.dx, msg.dy, msg.dz) || 1;
  const dir = { x: msg.dx / n, y: msg.dy / n, z: msg.dz / n };
  const o = { x: p.x, y: num(msg.y) ? clamp(msg.y, 0, 4) : EYE, z: p.z }; // shots start where the server has the pilot
  const end = { x: o.x + dir.x * def.range, y: o.y + dir.y * def.range, z: o.z + dir.z * def.range };
  // Cover stops the shot: nothing behind it can be hit.
  const wall = blocked(d, o, end) * def.range;
  let best = null;
  let at = wall;
  for (const e of d.enemies.values()) {
    if (e.hp <= 0) continue;
    const h = rayHit(o, dir, e, def.range);
    if (h !== null && h < at) [best, at] = [e, h];
  }
  const hx = o.x + dir.x * at;
  const hz = o.z + dir.z * at;
  d.shots.push([name, r1(o.x), r1(o.z), r1(hx), r1(hz), w]);
  if (w === 'rocket') {
    // The blast hurts what's near where it burst, but not through cover.
    const back = Math.max(0, at - 0.3);
    const burst = { x: o.x + dir.x * back, y: o.y + dir.y * back, z: o.z + dir.z * back };
    for (const e of d.enemies.values()) {
      const c = ENEMIES[e.type];
      const r = Math.hypot(e.x - hx, e.z - hz);
      if (e.hp <= 0 || r > def.splash + c.radius) continue;
      if (e !== best && !clear(d, burst, { x: e.x, y: (c.fly || 0) + c.height / 2, z: e.z })) continue;
      hurtEnemy(d, e, def.damage * (r < 1 ? 1 : 1 - (0.6 * r) / def.splash), p);
    }
  } else if (best) hurtEnemy(d, best, def.damage, p);
  return { ok: true, hit: best ? best.id : null, wall: best ? null : at < def.range ? r2(at) : null };
}

function hurtEnemy(d, e, damage, p) {
  if (e.hp <= 0) return;
  e.hp -= damage;
  if (e.hp > 0) return;
  d.kills += 1;
  if (d.bonus) d.bonusKills += 1;
  if (p) p.kills += 1;
  if (e.type === 'boss') d.feed.push({ text: `${p ? p.name : 'The squad'} brought the ${ENEMIES.boss.name} down` });
}

function hurtPilot(d, p, damage) {
  if (!p.alive) return;
  p.hitAt = d.t;
  const s = Math.min(p.shield, damage);
  p.shield -= s;
  p.hp -= damage - s;
  if (p.hp > 0) return;
  p.alive = false;
  p.hp = 0;
  p.deaths += 1;
  p.rockets = 0;
  if (d.lives > 0) {
    d.lives -= 1;
    p.respawnAt = d.t + RESPAWN_S;
    d.feed.push({ text: `${p.name} is down: ${d.lives} ${d.lives === 1 ? 'life' : 'lives'} left` });
  } else {
    p.respawnAt = Infinity;
    d.feed.push({ text: `${p.name} is down, and no lives are left` });
  }
}

// The enemy hits the objective. Destroyed, it loses the match (in the bonus round it only ends it).
function hurtObjective(d, damage) {
  const o = d.objective;
  if (!o || o.hp <= 0 || d.result) return;
  o.hp = Math.max(0, o.hp - damage);
  for (const at of [0.5, 0.25]) {
    if (o.hp > 0 && o.hp / o.maxHp <= at && o.warned > at) {
      o.warned = at;
      d.feed.push({ text: `The ${o.name.toLowerCase()} is down to ${Math.round(at * 100)}%` });
    }
  }
  if (o.hp > 0) return;
  d.feed.push({ text: `The ${o.name.toLowerCase()} has been destroyed` });
  [d.result, d.how] = d.bonus ? ['won', 'bonus'] : ['lost', 'objective'];
}

// --- Waves -----------------------------------------------------------------------------------

function spawnEnemy(d, type, i) {
  const r = random(d.rng);
  const [sx, sz] = SPAWNS[Math.floor(r * SPAWNS.length) % SPAWNS.length];
  const spread = (i % 5) * 2.5 - 5;
  const c = ENEMIES[type];
  const hp = c.hp * (modifiersFor(d.set).includes('tough') ? MODIFIERS.tough.hp : 1);
  const e = { id: d.nextId++, type, x: clamp(sx + (sx === 60 ? spread : 0), 1, SIZE - 1), z: clamp(sz + (sz === 60 ? spread : 0), 1, SIZE - 1), hp, maxHp: hp, cd: random(d.rng) * c.reload, heading: 0, state: 'move', target: null, side: random(d.rng) < 0.5 ? 1 : -1, detourUntil: 0 };
  // On objective maps some of each wave go for the objective instead of the squad.
  e.goal = d.objective && type !== 'boss' && random(d.rng) < OBJECTIVE_GOAL ? 'objective' : 'pilots';
  d.enemies.set(e.id, e);
  return e;
}

function startWave(d) {
  if (!d.bonus && d.wave >= WAVES) {
    d.set += 1;
    d.wave = 0;
  }
  d.wave += 1;
  d.phase = 'wave';
  let i = 0;
  for (const [type, n] of waveOf(d.set, d.wave, Math.max(1, present(d).length))) for (let k = 0; k < n; k++) spawnEnemy(d, type, i++);
  const lead = d.wave % WAVES === 0 ? `: a ${ENEMIES.boss.name} leads them` : '';
  d.feed.push({ text: d.bonus ? `Bonus wave ${d.wave}${lead}` : `Set ${d.set}, wave ${d.wave}${lead}` });
}

// A wave is cleared: a break, supply drops, and after a set more lives and the next modifiers.
// After the last wave of the last set the match is won, and the bonus round begins.
function endWave(d) {
  d.phase = 'break';
  const lastOfSet = d.wave % WAVES === 0;
  if (!d.bonus && lastOfSet && d.set === SETS) {
    d.bonus = true;
    d.set = SETS + 1;
    d.wave = 0;
    d.breakUntil = d.t + SET_BREAK_S;
    d.feed.push({ text: 'Every wave held: the sector is secure, and the match is won' });
    d.feed.push({ text: `Bonus round: endless waves, a campaign point for every ${BONUS_KILLS_PER_POINT} kills, until the squad falls` });
  } else {
    d.breakUntil = d.t + (lastOfSet && !d.bonus ? SET_BREAK_S : WAVE_BREAK_S);
    if (lastOfSet && !d.bonus) {
      d.lives += LIVES_PER_SET;
      const next = modifiersFor(d.set + 1).filter((m) => !modifiersFor(d.set).includes(m));
      d.feed.push({ text: `Set ${d.set} cleared: +${LIVES_PER_SET} lives${next.length ? `. Next set: ${next.map((m) => MODIFIERS[m].name).join(', ')}` : ''}` });
    }
  }
  drops(d, lastOfSet);
  // The objective is patched up a little between waves.
  const o = d.objective;
  if (o && o.hp > 0) {
    o.hp = Math.min(o.maxHp, o.hp + o.maxHp * OBJECTIVE_REPAIR);
    o.warned = o.hp / o.maxHp > 0.5 ? 1 : o.hp / o.maxHp > 0.25 ? 0.5 : 0.25;
  }
  // The fallen come back for the break.
  for (const p of d.pilots.values()) if (!p.alive && p.respawnAt === Infinity && d.lives > 0) [p.respawnAt, d.lives] = [d.t + 1, d.lives - 1];
}

// Supply drops land near the middle: ammo and health always, shields often, a rocket launcher at
// the end of a set (and sometimes between waves). Famine halves them.
function drops(d, lastOfSet) {
  const kinds = ['ammo', 'health'];
  if (random(d.rng) < 0.6) kinds.push('shield');
  if (lastOfSet || random(d.rng) < 0.35) kinds.push('rocket');
  if (present(d).length > 2) kinds.push('ammo');
  const keep = modifiersFor(d.set).includes('famine') ? Math.ceil(kinds.length * MODIFIERS.famine.drops) : kinds.length;
  for (const kind of kinds.slice(0, keep)) {
    const a = random(d.rng) * Math.PI * 2;
    const r = 10 + random(d.rng) * 18;
    const u = { id: d.nextId++, kind, x: r1(60 + Math.cos(a) * r), z: r1(60 + Math.sin(a) * r) };
    d.pickups.set(u.id, u);
  }
  d.feed.push({ text: 'Supply drop inbound' });
}

// --- The simulation --------------------------------------------------------------------------

function nearestPilot(d, e) {
  let best = null;
  let bd = Infinity;
  for (const p of d.pilots.values()) {
    if (!p.present || !p.alive) continue;
    const r = Math.hypot(p.x - e.x, p.z - e.z);
    if (r < bd) [best, bd] = [p, r];
  }
  return best ? { p: best, r: bd } : null;
}

// What an enemy goes for: the nearest pilot, or (if it was sent for it and no pilot is close) the
// objective. `aims`: the points it would shoot at, `skip`: the box it's shooting at.
function targetOf(d, e) {
  const t = nearestPilot(d, e);
  const o = d.objective;
  if (o && o.hp > 0 && e.goal === 'objective' && !(t && t.r <= OBJECTIVE_GUARD_R)) {
    const q = boxNear(o.box, e.x, e.z);
    return { obj: o, r: q.r, x: q.x, z: q.z, aims: [{ x: q.x, y: o.box[4] / 2, z: q.z }], skip: o.box };
  }
  if (!t) return null;
  return { p: t.p, r: t.r, x: t.p.x, z: t.p.z, aims: [{ x: t.p.x, y: CHEST, z: t.p.z }, { x: t.p.x, y: HEAD, z: t.p.z }], skip: null };
}

// An enemy walks `step` metres along `heading`, round cover: when it's walking into a wall it turns
// aside for a moment (to its own side, swapping if that's blocked too).
function walk(d, e, heading, step) {
  const c = ENEMIES[e.type];
  const go = (h) => {
    const x = e.x + Math.sin(h) * step;
    const z = e.z + Math.cos(h) * step;
    return c.fly ? [x, z] : pushOut(d, x, z, c.radius);
  };
  const ways = e.detourUntil > d.t ? [heading + e.side * 1.2, heading] : [heading, heading + e.side * 1.2, heading - e.side * 1.2];
  for (let i = 0; i < ways.length; i++) {
    const [x, z] = go(ways[i]);
    if (Math.hypot(x - e.x, z - e.z) < step * 0.5 && i < ways.length - 1) continue;
    if (ways[i] !== heading && !(e.detourUntil > d.t)) {
      e.detourUntil = d.t + 1.5;
      if (i === 2) e.side = -e.side;
    }
    e.x = clamp(x, 0.5, SIZE - 0.5);
    e.z = clamp(z, 0.5, SIZE - 0.5);
    return;
  }
}

function enemyStep(d, e, dt) {
  const c = ENEMIES[e.type];
  e.cd = Math.max(0, e.cd - dt);
  const t = targetOf(d, e);
  if (!t) {
    e.state = 'idle';
    return;
  }
  e.heading = Math.atan2(t.x - e.x, t.z - e.z);
  // Can it see what it's after? Cover between them blocks its fire, so it closes in instead.
  const muzzle = { x: e.x, y: (c.fly || 0) + c.height * 0.8, z: e.z };
  const sees = t.aims.map((a) => clear(d, muzzle, a, t.skip));
  const seen = sees.some(Boolean);
  const stand = c.melee ? c.range * 0.8 : seen ? c.range * 0.7 : 1.5;
  if (t.r > stand) {
    walk(d, e, e.heading, Math.min(c.speed * dt, t.r - stand));
    e.state = 'move';
  } else e.state = 'fight';
  if (seen && t.r <= c.range && e.cd <= 0) {
    e.cd = c.reload;
    const fury = modifiersFor(d.set).includes('fury') ? MODIFIERS.fury.damage : 1;
    // Ranged shots miss more often from further away, and half as often hit a pilot showing only
    // their head over cover; strikes up close always land.
    const odds = (0.75 - (0.35 * t.r) / c.range) * (sees[0] ? 1 : 0.5);
    const hit = c.melee || random(d.rng) < odds;
    if (hit && t.p) hurtPilot(d, t.p, c.damage * fury);
    else if (hit) hurtObjective(d, c.damage * fury);
    d.shots.push([`e${e.id}`, r1(e.x), r1(e.z), r1(t.x), r1(t.z), hit ? 'hit' : 'miss']);
  }
}

function tick(d, dt) {
  d.t += dt;
  for (const p of d.pilots.values()) {
    if (!p.alive && p.present && d.t >= p.respawnAt) {
      const [x, z] = PLAYER_SPAWNS[Math.floor(random(d.rng) * PLAYER_SPAWNS.length)];
      Object.assign(p, { alive: true, hp: HP, shield: SHIELD, x, z, hitAt: -100 });
      d.feed.push({ name: p.name, respawned: true });
    }
    if (p.alive && p.shield < SHIELD && d.t - p.hitAt >= SHIELD_DELAY_S) p.shield = Math.min(SHIELD, p.shield + SHIELD_RATE * dt);
  }
  for (const e of d.enemies.values()) if (e.hp > 0) enemyStep(d, e, dt);
  for (const [id, e] of d.enemies) if (e.hp <= 0) d.enemies.delete(id);
  if (d.phase === 'break' && d.t >= d.breakUntil) startWave(d);
  else if (d.phase === 'wave' && d.enemies.size === 0) endWave(d);
  // Everyone down with no lives left: the enemy wins (in the bonus round, the round is over).
  const here = present(d);
  if (!d.result && here.length && here.every((p) => !p.alive) && d.lives <= 0 && here.every((p) => p.respawnAt === Infinity)) {
    [d.result, d.how] = d.bonus ? ['won', 'bonus'] : ['lost', 'fallen'];
    d.feed.push({ text: d.bonus ? 'The squad has fallen: the bonus round is over' : 'The squad has fallen' });
  }
}

function step(d, dt) {
  for (let left = dt; left > 1e-9 && !d.result; left -= STEP_S) tick(d, Math.min(STEP_S, left));
}

// --- What the pilots see ---------------------------------------------------------------------

function frame(d) {
  const out = {
    match: d.id,
    t: r1(d.t),
    set: d.set,
    wave: d.wave,
    phase: d.phase,
    breakLeft: d.phase === 'break' ? r1(Math.max(0, d.breakUntil - d.t)) : 0,
    lives: d.lives,
    bonus: d.bonus,
    bonusKills: d.bonusKills,
    objective: d.objective ? [Math.round(d.objective.hp), d.objective.maxHp] : null,
    modifiers: modifiersFor(d.set),
    enemies: [...d.enemies.values()].map((e) => [e.id, e.type, r1(e.x), r1(e.z), Math.max(0, Math.round(e.hp)), Math.round(e.maxHp), r1(e.heading), e.state]),
    pilots: [...d.pilots.values()].filter((p) => p.present).map((p) => [p.name, r1(p.x), r1(p.z), r1(p.yaw), Math.round(p.hp), Math.round(p.shield), p.alive, p.kills]),
    pickups: [...d.pickups.values()].map((u) => [u.id, u.kind, u.x, u.z]),
    shots: d.shots,
    feed: d.feed,
    kills: d.kills,
  };
  d.shots = [];
  d.feed = [];
  return out;
}

function stateFor(d, f, name) {
  const p = d.pilots.get(name);
  return { type: 'defense_state', ...f, me: p ? { hp: Math.round(p.hp), shield: Math.round(p.shield), alive: p.alive, respawnIn: p.alive || p.respawnAt === Infinity ? 0 : r1(p.respawnAt - d.t), rockets: p.rockets, x: r1(p.x), z: r1(p.z) } : null };
}

function joined(d, name) {
  const p = d.pilots.get(name);
  return {
    type: 'defense_joined',
    match: d.id,
    planet: d.planet,
    planetName: d.planetName,
    faction: d.faction,
    enemy: d.enemy,
    size: SIZE,
    seed: d.seed,
    map: d.map,
    mapName: MAPS[d.map].name,
    mapText: MAPS[d.map].text,
    cover: d.cover,
    objective: d.objective ? { kind: d.objective.kind, name: d.objective.name, box: d.objective.box, maxHp: d.objective.maxHp } : null,
    bonusKillsPerPoint: BONUS_KILLS_PER_POINT,
    spawns: SPAWNS,
    enemies: ENEMIES,
    weapons: WEAPONS,
    modifiers: MODIFIERS,
    sets: SETS,
    waves: WAVES,
    hp: HP,
    shield: SHIELD,
    start: [p.x, p.z],
  };
}

// --- The server's matches ----------------------------------------------------------------------

// Sector Defense matches a server runs. `send(me, msg)` sends one connection a message;
// `onEnd(d, winner)` scores the result for the campaign (winner: the squad's faction, or the
// enemy's, or null for the militia) and returns the points (bonusPoints(d) on top for a win);
// `speed` makes matches run faster (tests).
function createDefenses({ now = Date.now, speed = 1, send, changed, onEnd = null }) {
  const matches = new Map();
  const conns = new Map(); // match id -> Map(name -> connection)
  let nextId = 1;
  let ticks = 0;
  const timers = new Set();

  // A new match for a squad (matchmaking puts the pilots in with enlist).
  function start(planet, planetName, faction, enemy, opts = {}) {
    const n = nextId++;
    const d = newDefense({ id: `d${n}`, planet, planetName, faction, enemy, seed: (Date.now() ^ (n * 2654435761)) >>> 0, now: now(), speed, ...opts });
    matches.set(d.id, d);
    conns.set(d.id, new Map());
    return d;
  }

  function enlist(me, d) {
    if (me.defense && me.defense !== d.id) leave(me);
    addPilot(d, me.name);
    conns.get(d.id).set(me.name, me);
    me.defense = d.id;
    send(me, joined(d, me.name));
    changed();
    return { ok: true, match: d.id };
  }

  function leave(me) {
    const d = me.defense && matches.get(me.defense);
    me.defense = null;
    if (!d) return { ok: true };
    if (conns.get(d.id)?.get(me.name) === me) {
      conns.get(d.id).delete(me.name);
      removePilot(d, me.name);
      if (!d.result && !present(d).length) [d.result, d.how] = d.bonus ? ['won', 'bonus'] : ['lost', 'abandoned'];
      changed();
    }
    return { ok: true };
  }

  function handle(me, msg) {
    if (msg.type === 'defense_leave') return leave(me);
    const d = me.defense && matches.get(me.defense);
    if (!d || d.result || String(msg.match) !== d.id) return { ok: true, quiet: true };
    const t = Date.now();
    const key = msg.type === 'defense_move' ? 'moves' : 'shots';
    const cap = msg.type === 'defense_move' ? MOVES_PER_S : SHOTS_PER_S;
    me.defenseWindow ||= {};
    if (t - (me.defenseWindow[key + 'At'] || 0) >= 1000) [me.defenseWindow[key + 'At'], me.defenseWindow[key]] = [t, 0];
    if (++me.defenseWindow[key] > cap) return { ok: true, quiet: true };
    if (msg.type === 'defense_move') return move(d, me.name, msg);
    if (msg.type === 'defense_fire') return fire(d, me.name, msg);
    return fail(`unknown message ${msg.type}`);
  }

  function finish(d) {
    const winner = d.result === 'won' ? d.faction : d.enemy;
    const pts = onEnd ? onEnd(d, winner) : 0;
    const gain = (who) => (who ? `: +${pts} campaign points for ${F.the(who)}` : '');
    const text =
      d.result === 'won' && d.bonus
        ? `Sector held: every wave beaten, then ${d.bonusKills} more enemies down in the bonus round (to bonus wave ${d.wave})${gain(winner)}`
        : d.result === 'won'
          ? `Sector held: every wave beaten, ${d.kills} enemies down${gain(winner)}`
          : d.how === 'abandoned'
            ? 'The squad left the field'
            : d.how === 'objective'
              ? `The ${d.objective.name.toLowerCase()} was destroyed in set ${d.set}, wave ${d.wave}${gain(winner)}`
              : `The squad fell in set ${d.set}, wave ${d.wave}${gain(winner)}`;
    const f = frame(d);
    for (const [name, c] of conns.get(d.id)) {
      send(c, stateFor(d, f, name));
      send(c, { type: 'defense_end', match: d.id, won: d.result === 'won', text });
    }
    changed();
    const timer = setTimeout(() => {
      timers.delete(timer);
      matches.delete(d.id);
      for (const c of conns.get(d.id)?.values() || []) if (c.defense === d.id) c.defense = null;
      conns.delete(d.id);
    }, END_KEEP_MS);
    timers.add(timer);
  }

  function tickAll() {
    ticks++;
    const snap = ticks % Math.max(1, Math.round(SNAPSHOT_MS / TICK_MS)) === 0;
    for (const d of matches.values()) {
      if (d.ended) continue;
      if (!d.result) step(d, (TICK_MS / 1000) * speed);
      if (d.result) {
        d.ended = true;
        finish(d);
        continue;
      }
      if (!snap) continue;
      const f = frame(d);
      for (const [name, c] of conns.get(d.id)) send(c, stateFor(d, f, name));
    }
  }
  const ticker = setInterval(tickAll, TICK_MS);

  function running(planet) {
    return [...matches.values()].filter((d) => !d.result && d.planet === planet);
  }

  function room(d) {
    return present(d).length < SQUAD_MAX;
  }

  function list() {
    return [...matches.values()]
      .filter((d) => !d.result)
      .map((d) => ({ id: d.id, planet: d.planet, faction: d.faction, enemy: d.enemy, map: d.map, set: d.set, wave: d.wave, bonus: d.bonus, pilots: present(d).map((p) => p.name) }));
  }

  function close() {
    clearInterval(ticker);
    for (const t of timers) clearTimeout(t);
  }

  return { matches, start, enlist, leave, handle, running, room, list, tick: tickAll, close };
}

module.exports = {
  SIZE,
  SQUAD_MAX,
  SETS,
  WAVES,
  LIVES,
  LIVES_PER_SET,
  HP,
  SHIELD,
  RESPAWN_S,
  FIRST_BREAK_S,
  WAVE_BREAK_S,
  SET_BREAK_S,
  WEAPONS,
  ENEMIES,
  MODIFIERS,
  COVER,
  MAPS,
  BONUS_KILLS_PER_POINT,
  bonusPoints,
  blocked,
  modifiersFor,
  waveOf,
  newDefense,
  addPilot,
  removePilot,
  move,
  fire,
  rayHit,
  hurtPilot,
  hurtObjective,
  enemyStep,
  step,
  frame,
  stateFor,
  joined,
  createDefenses,
};
