// Supremacy: a campaign game mode in two phases, about 20 minutes, best of up to 3 rounds.
//   Phase 1, on the ground: a large outdoor sector with 3 to 5 control points (set by the map).
//   Stand on a point to capture it (more of your side captures faster); every held point fills
//   your side's bar, and the first bar full wins the ground.
//   Boarding: the winners have a short window to reach a boarding shuttle (one at their drop ship
//   and one at each point they hold); every one who boards in time adds 15 seconds to the attack.
//   Phase 2, aboard the losers' capital ship (the faction's actual navy ship over the planet, each
//   faction's ship its own layout: a very large main path to the reactor and a secondary route,
//   joined by passages, with blast doors to breach): the boarders have 5 minutes plus their boarding
//   time to destroy the reactor. If they do, they win the round; if not, the ship's side does.
//   Either way the fight goes back to the ground with the bars reset, and the damage done aboard
//   (doors breached, reactor damage) is kept for that side's next attack. First to 2 rounds wins.
// Up to 16 a side: AI troopers fill the empty player slots, and fodder bots (cheap, basic bots in
// each faction's own design that die very quickly) fight on both sides to make it a full battle.
// Respawns are unlimited, at your drop ship or a point you hold (in the ship: the hangar for the
// boarders, the reactor decks for the crew). Pick 10 classes from Facility Battles, no kill
// streaks, power weapons from front-supply drops; a trooper doing well (with enough battle credits,
// from kills and captures) can come back as an elite trooper, tougher and better armed. Each planet
// gives its holder one Supremacy bonus: extra boarding time, faster credits, or some kill streaks.
//
// Runs on the Facility Battles engine (facility.js: bodies, weapons, shots and cover, the AI and
// its navigation grid); this file adds the phases, maps and rules. In memory only.

const FC = require('./facility');
const F = require('./factions');
const N = require('./navy');
const TM = require('./telemetry.ts');
const W = require('./war');

const TEAM_MAX = 16; // a side, AI troopers filling the empty slots
const FODDER = 10; // fodder bots a side on the ground...
const CREW = 8; // ...and the ship's crew of them aboard
const FODDER_HP = 30;
const RESPAWN_S = 4;
const CREW_RESPAWN_S = 8; // aboard, the ship's side comes back slower (its decks are far from the fight)
const BAR_TARGET = 100;
const BAR_RATE = 0.2; // bar per second for each held point
const CAPTURE_S = 10; // a point takes this long for one trooper alone; up to 4 together, 4x faster
const POINT_R = 6;
const GROUND_MAX_S = 300; // the ground goes to the fuller bar after this long
const BOARD_S = 20;
const BOARD_R = 5;
const BOARD_BONUS_S = 15; // every pilot who boards adds this to the attack...
const SHIP_S = 300; // ...on top of this
const BONUS_BOARDING_S = 60;
const ROUNDS_TO_WIN = 2;
const REACTOR_HP = 4500;
const BLAST_DOOR_HP = 5000;
const ELITE_COST = 150; // battle credits for an elite trooper
const CREDITS = { kill: 10, fodder: 2, capture: 25 };
const ELITE = { hp: 150, shield: 50, damage: 1.3, speed: 1.05 };

// One of these per planet, for its holder.
const BONUSES = {
  boarding: { name: 'Boarding drills', text: 'The holder gets 60 more seconds to attack aboard', seconds: BONUS_BOARDING_S },
  credits: { name: 'War chest', text: "The holder's troops earn battle credits (for elite troopers) 50% faster", credits: 1.5 },
  streaks: { name: 'Orbital support', text: "The holder's troops earn kill streaks: Sensor Array, Supply Drop and Orbital Barrage", streaks: ['sensor', 'drop', 'barrage'] },
};
const BONUS_IDS = Object.keys(BONUSES);

function bonusOf(planetId) {
  return BONUS_IDS[W.hash(`supremacy/${planetId}`) % BONUS_IDS.length];
}

function fail(reason) {
  return { ok: false, reason };
}

const r1 = (x) => Math.round(x * 10) / 10;
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const other = (side) => (side === 'a' ? 'd' : 'a');

// --- Ground maps -----------------------------------------------------------------------------------

// GROUND_W x GROUND_D metres; side a's drop ship to the south (low z), side d's (the holder's) to
// the north. Boxes are [x, z, width, depth, height], centred on (x, z).
const GROUND_W = 160;
const GROUND_D = 120;
const DROP_A = [80, 6];
const RING = [[-8, 0], [-4, 3], [0, 4], [4, 3], [8, 0], [-10, 4], [10, 4], [0, 7]];
const GROUND = {
  highlands: {
    name: 'Highlands',
    points: [[30, 60], [80, 60], [130, 60], [80, 34], [80, 86]],
    walls: [
      [55, 45, 6, 4, 3], [105, 45, 6, 4, 3], [55, 75, 6, 4, 3], [105, 75, 6, 4, 3], [80, 52, 10, 1, 1.2], [80, 68, 10, 1, 1.2],
      [30, 48, 8, 1, 1.2], [30, 72, 8, 1, 1.2], [130, 48, 8, 1, 1.2], [130, 72, 8, 1, 1.2],
      [20, 30, 5, 5, 3], [140, 30, 5, 5, 3], [20, 90, 5, 5, 3], [140, 90, 5, 5, 3],
      [60, 20, 4, 8, 3], [100, 20, 4, 8, 3], [60, 100, 4, 8, 3], [100, 100, 4, 8, 3],
      [45, 60, 2, 10, 3], [115, 60, 2, 10, 3], [80, 24, 12, 1, 1.2], [80, 96, 12, 1, 1.2],
    ],
    drops: [[55, 60], [105, 60]],
  },
  canyon: {
    name: 'Canyon',
    points: [[80, 30], [80, 60], [80, 90]],
    walls: [
      [50, 25, 3, 30, 3], [50, 60, 3, 28, 3], [50, 95, 3, 30, 3], [110, 25, 3, 30, 3], [110, 60, 3, 28, 3], [110, 95, 3, 30, 3],
      [70, 45, 4, 4, 3], [90, 45, 4, 4, 3], [70, 75, 4, 4, 3], [90, 75, 4, 4, 3], [80, 52, 8, 1, 1.2], [80, 68, 8, 1, 1.2],
      [25, 60, 6, 6, 3], [135, 60, 6, 6, 3], [25, 30, 4, 4, 1.2], [135, 90, 4, 4, 1.2],
    ],
    drops: [[25, 45], [135, 75]],
  },
  outskirts: {
    name: 'Outskirts',
    points: [[40, 40], [120, 40], [40, 80], [120, 80]],
    walls: [
      [80, 60, 14, 14, 3], [40, 60, 10, 2, 3], [120, 60, 10, 2, 3], [60, 40, 2, 10, 3], [100, 40, 2, 10, 3], [60, 80, 2, 10, 3], [100, 80, 2, 10, 3],
      [40, 25, 8, 1, 1.2], [120, 25, 8, 1, 1.2], [40, 95, 8, 1, 1.2], [120, 95, 8, 1, 1.2], [20, 60, 4, 4, 3], [140, 60, 4, 4, 3],
    ],
    drops: [[80, 40], [80, 80]],
  },
};
const GROUND_IDS = Object.keys(GROUND);

function groundMap(id) {
  const g = GROUND[id];
  const drop = { a: DROP_A, d: [DROP_A[0], GROUND_D - DROP_A[1]] };
  return {
    id,
    name: g.name,
    kind: 'ground',
    w: GROUND_W,
    d: GROUND_D,
    walls: g.walls,
    doors: [],
    turrets: [],
    plant: null,
    points: g.points,
    drop,
    spawns: { a: RING.map(([dx, dz]) => [drop.a[0] + dx, drop.a[1] + dz]), d: RING.map(([dx, dz]) => [drop.d[0] + dx, drop.d[1] - dz]) },
    hills: [],
    flags: { a: drop.a, d: drop.d },
    holds: g.points,
    drops: g.drops,
  };
}

// --- The capital ships -------------------------------------------------------------------------------

// SHIP_W x SHIP_D metres, the hangar at the west end (x 0-16), the reactor room at the east
// (x 124-140). A very large main path runs the ship's length, a narrow secondary route beside it
// (to the south, or the north), joined by passages; blast doors stand across both, placed so no
// way round the passages reaches the reactor without breaching one.
const SHIP_W = 140;
const SHIP_D = 36;
const SHIPS = {
  compact: { name: 'Compact cruiser', secondary: 'south', passages: [40, 70, 100], main: [55, 95], side: [80], cover: 'crates' },
  ashen: { name: 'Ashen carrier', secondary: 'north', passages: [35, 60, 90, 110], main: [45, 85], side: [65, 105], cover: 'pillars' },
  luminar: { name: 'Luminar ark', secondary: 'south', passages: [50, 85], main: [70], side: [60, 100], cover: 'pillars' },
  coma: { name: 'Coma dreadnought', secondary: 'north', passages: [30, 65, 100], main: [50, 80, 110], side: [90], cover: 'crates' },
  militia: { name: 'Militia frigate', secondary: 'south', passages: [45, 90], main: [70], side: [80], cover: 'crates' },
};

function shipLayout(faction) {
  const p = SHIPS[faction] || SHIPS.militia;
  const flip = p.secondary === 'north';
  const fz = (z) => (flip ? SHIP_D - z : z);
  const box = ([x, z, w, d, h]) => [x, fz(z), w, d, h];
  const walls = [];
  // The divider between the routes (z 10), open at each passage.
  let from = 16;
  for (const x of [...p.passages.slice().sort((a, b) => a - b), 125.5]) {
    const to = x - 1.5;
    if (to > from) walls.push([(from + to) / 2, 10, to - from, 1, 3]);
    from = x + 1.5;
  }
  // Across the main path: walls either side of each blast door's 6 m gap.
  const c = 23;
  for (const x of p.main) walls.push([x, (10.5 + (c - 3)) / 2, 1, c - 3 - 10.5, 3], [x, (c + 3 + SHIP_D) / 2, 1, SHIP_D - (c + 3), 3]);
  const cover = p.cover === 'crates'
    ? [[30, 16, 2, 2, 1.2], [30, 30, 2, 2, 1.2], [65, 18, 3, 2, 1.2], [85, 28, 3, 2, 1.2], [110, 15, 2, 2, 1.2], [110, 31, 2, 2, 1.2]]
    : [[40, 17, 1.5, 1.5, 3], [40, 29, 1.5, 1.5, 3], [76, 17, 1.5, 1.5, 3], [76, 29, 1.5, 1.5, 3], [104, 17, 1.5, 1.5, 3], [104, 29, 1.5, 1.5, 3]];
  walls.push(...cover.filter(([x]) => ![...p.main, ...p.side].some((d) => Math.abs(d - x) < 3)));
  const doors = [...p.main.map((x) => [x, c, 1, 6, 3]), ...p.side.map((x) => [x, 5.25, 1, 9.5, 3])].map(box);
  return {
    id: `ship-${faction || 'militia'}`,
    name: p.name,
    kind: 'ship',
    w: SHIP_W,
    d: SHIP_D,
    walls: walls.map(box),
    doors: [],
    turrets: [],
    plant: null,
    points: [],
    blastDoors: doors,
    reactor: box([132, c, 6, 6, 3]),
    spawns: {
      a: [[4, 8], [4, 16], [4, 24], [4, 30], [8, 12], [8, 20], [8, 28], [10, 5]].map(([x, z]) => [x, fz(z)]),
      d: [[127, 6], [127, 31], [137, 8], [137, 31], [120, 18], [120, 28], [126, 14], [138, 20]].map(([x, z]) => [x, fz(z)]),
    },
    hills: [],
    flags: { a: [4, 18], d: [136, 18] },
    holds: [[121, 23], [121, 16], [121, 30], [118, 5], [110, 23], [100, 23]].map(([x, z]) => [x, fz(z)]),
    drops: [],
  };
}

// The name of a faction's ship over the planet: its biggest warship in the system (a Builder's, or
// the faction's armada), or a capital ship of its own when it has none there.
function shipName(g, wp, faction) {
  const word = faction && F.FACTIONS[faction] ? F.FACTIONS[faction].name.split(' ')[0] : 'Militia';
  const here = (g?.war?.fleets || []).filter((fl) => fl.faction === faction && fl.system === wp?.system && fl.status !== 'flying' && fl.status !== 'returning');
  let best = null;
  for (const fl of here) for (const id of Object.keys(fl.ships || {})) if (N.SHIPS[id] && fl.ships[id] > 0 && (!best || N.SHIPS[id].hull > N.SHIPS[best.id].hull)) best = { id, fl };
  if (!best) return `${word} ${(SHIPS[faction] || SHIPS.militia).name.split(' ').slice(1).join(' ')}`;
  return best.fl.owner ? `${best.fl.owner}'s ${N.SHIPS[best.id].name.toLowerCase()}` : `the ${word} armada's ${N.SHIPS[best.id].name.toLowerCase()}`;
}

// --- A match -----------------------------------------------------------------------------------------

// A new match on `planet` between side a (`attacker`) and side d (`defender`, the holder). `map`
// picks the ground map (else the seed does); `bonus` is the planet's Supremacy bonus and `holder`
// its holder; `ships`: the names of each side's ship over the planet.
function newSupremacy({ id = 's1', planet, planetName = '', attacker, defender = null, holder = null, bonus = null, map = null, seed = 1, ships = {}, now = Date.now(), speed = 1 }) {
  const rng = { s: seed >>> 0 };
  const groundId = GROUND[map] ? map : GROUND_IDS[Math.floor(FC.random(rng) * GROUND_IDS.length) % GROUND_IDS.length];
  const f = {
    id,
    mode: 'supremacy',
    rule: 'supremacy',
    planet,
    planetName,
    factions: { a: attacker, d: defender },
    seed,
    rng,
    speed,
    startedAt: now,
    t: 0,
    nextId: 1,
    bodies: new Map(),
    ground: groundMap(groundId),
    shipMaps: { a: shipLayout(attacker), d: shipLayout(defender) },
    shipNames: { a: ships.a || shipName(null, null, attacker), d: ships.d || shipName(null, null, defender) },
    // What's been done to each side's ship, kept from one boarding to the next.
    damage: { a: null, d: null },
    bonus: BONUSES[bonus] ? bonus : null,
    holderSide: holder && holder === defender ? 'd' : holder && holder === attacker ? 'a' : null,
    round: 1,
    rounds: { a: 0, d: 0 },
    phase: 'ground', // 'ground', 'boarding', 'ship'
    phaseAt: 0,
    bars: { a: 0, d: 0 },
    points: [],
    winner: null, // who won the ground (the boarders)
    shuttles: [],
    boarders: 0,
    shipUntil: 0,
    kills: { a: 0, d: 0 },
    score: { a: 0, d: 0 },
    reinforcements: { a: 0, d: 0 },
    unlimited: true,
    respawnS: RESPAWN_S,
    doors: [],
    turrets: [],
    hacked: false,
    plant: { progress: 0, by: null, at: -100 },
    flags: { a: { home: [0, 0], x: 0, z: 0, carrier: null, droppedAt: null }, d: { home: [0, 0], x: 0, z: 0, carrier: null, droppedAt: null } },
    pickups: new Map(),
    nextSupply: FC.SUPPLY_EVERY_S / 2,
    active: [],
    spotted: { a: new Map(), d: new Map() },
    grenades: [],
    shots: [],
    feed: [],
    breakables: [],
    deaths: [],
    dropWalls: [],
    gearObjs: [],
    result: null,
    how: null,
  };
  // The engine's hooks.
  f.spawnSpots = spawnSpots;
  f.onSpawn = onSpawn;
  f.onKill = onKill;
  f.onBreak = onBreak;
  f.aiGoal = aiGoal;
  f.holding = (m, b) => m.phase === 'ship' && b.side !== m.winner;
  f.breakFirst = (m, b) => m.phase === 'ship' && b.side === m.winner;
  f.streaksFor = (m, b) => m.bonus === 'streaks' && b.side === m.holderSide;
  f.streakIds = BONUSES.streaks.streaks;
  setMap(f, f.ground);
  f.points = f.ground.points.map(([x, z]) => ({ x, z, owner: null, progress: 0 }));
  balance(f);
  fodder(f);
  return f;
}

// Into a map: the ground, or a ship (its breakables those of `shipSide`'s ship, as left last time).
function setMap(f, map, shipSide = null) {
  f.map = map;
  f.w = map.w;
  f.d = map.d;
  f.doors = [];
  f.turrets = [];
  f.pickups.clear();
  f.grenades = [];
  if (shipSide) {
    f.damage[shipSide] ||= {
      doors: map.blastDoors.map((box) => ({ kind: 'door', box, hp: BLAST_DOOR_HP, maxHp: BLAST_DOOR_HP, side: shipSide })),
      reactor: { kind: 'reactor', box: map.reactor, hp: REACTOR_HP, maxHp: REACTOR_HP, side: shipSide },
    };
    f.breakables = [...f.damage[shipSide].doors, f.damage[shipSide].reactor];
  } else f.breakables = [];
  f.blockers = FC.blockers(f);
  f.nav = FC.navGrid(f);
  f.flows = new Map();
}

const team = (f, side) => FC.team(f, side);
const humans = (f, side) => FC.humans(f, side);

// Both sides at TEAM_MAX, AI troopers filling the empty player slots (a trooper steps aside for a
// pilot who joins).
function balance(f) {
  for (const side of ['a', 'd']) {
    let t = team(f, side);
    while (t.length < TEAM_MAX) {
      const n = f.nextId++;
      const b = FC.newBody(f, { id: `ai${n}`, name: `Trooper ${n}`, side, ai: true, cls: ['assault', 'heavy', 'cqb', 'marksman'][n % 4] });
      b.wantElite = true;
      t = team(f, side);
    }
    const ais = t.filter((b) => b.ai).sort((x, y) => Number(x.alive) - Number(y.alive));
    while (t.length > TEAM_MAX && ais.length) {
      f.bodies.delete(ais.shift().id);
      t = team(f, side);
    }
  }
}

// The fodder bots: FODDER a side on the ground; aboard, only the ship's crew.
function fodder(f) {
  for (const [id, b] of f.bodies) if (b.fodder) f.bodies.delete(id);
  const want = f.phase === 'ship' ? { [f.winner]: 0, [other(f.winner)]: CREW } : { a: FODDER, d: FODDER };
  for (const side of ['a', 'd']) {
    for (let i = 0; i < want[side]; i++) {
      const n = f.nextId++;
      FC.newBody(f, { id: `fb${n}`, name: `${botName(f, side)} ${n}`, side, ai: true, fodder: true, cls: 'assault' });
    }
  }
}

function botName(f, side) {
  const fac = f.factions[side];
  return { compact: 'Drudge', ashen: 'Skitter', luminar: 'Wisp', coma: 'Husk' }[fac] || 'Militia bot';
}

// --- The engine's hooks --------------------------------------------------------------------------------

// Where a body comes back: aboard, the boarders at the hangar and the crew by the reactor; on the
// ground, at the side's drop ship or round a point it holds.
function spawnSpots(f, b) {
  if (f.phase === 'ship') return f.map.spawns[b.side === f.winner ? 'a' : 'd'];
  const out = f.map.spawns[b.side].slice();
  for (const p of f.points) if (p.owner === b.side) for (const [dx, dz] of [[-7, 0], [7, 0], [0, -7], [0, 7]]) out.push([p.x + dx, p.z + dz]);
  return out.map(([x, z]) => FC.pushOut(f, clamp(x, 1, f.w - 1), clamp(z, 1, f.d - 1)));
}

// A fodder bot is frail; a trooper with the credits (who asked for it) comes back elite.
function onSpawn(f, b) {
  if (b.fodder) {
    Object.assign(b, { hp: FODDER_HP, hpMax: FODDER_HP, shield: 0, shieldMax: 0, speed: 1 });
    return;
  }
  b.credits ||= 0;
  if (b.wantElite && b.credits >= ELITE_COST) {
    b.credits -= ELITE_COST;
    b.elite = true;
    b.hpMax = ELITE.hp;
    b.hp = ELITE.hp;
    b.shieldMax += ELITE.shield;
    b.shield = b.shieldMax;
    b.damageMul = ELITE.damage;
    b.speed *= ELITE.speed;
    if (!b.ai) {
      b.wantElite = false;
      f.feed.push({ text: `${b.name} is back as an elite trooper`, side: b.side });
    }
  }
  if (f.phase === 'ship') b.yaw = b.side === f.winner ? -Math.PI / 2 : Math.PI / 2; // along the ship
}

function earn(f, b, n) {
  if (!b || b.fodder || !f.bodies.has(b.id)) return;
  b.credits = (b.credits || 0) + n * (f.bonus === 'credits' && b.side === f.holderSide ? BONUSES.credits.credits : 1);
}

function onKill(f, t, by) {
  if (by && by.side !== t.side) earn(f, by, t.fodder ? CREDITS.fodder : CREDITS.kill);
  if (f.phase === 'ship' && t.side !== f.winner && t.respawnAt !== Infinity) t.respawnAt = f.t + CREW_RESPAWN_S;
}

function onBreak(f, br, by) {
  if (br.kind === 'reactor') {
    f.feed.push({ text: `${by ? by.name : 'The boarders'} destroyed the reactor of ${f.shipNames[br.side]}` });
    endRound(f, other(br.side), 'reactor');
  } else f.feed.push({ text: `${by ? by.name : 'The boarders'} breached a blast door` });
}

// Where an AI body heads. Ground: the nearest point its side doesn't hold (or holds under attack);
// boarding: the nearest shuttle; aboard, the boarders push for the reactor (breaching the blast doors
// in the way, half by the main path and half by the secondary route), the crew hold the reactor corridors.
function aiGoal(f, b) {
  const idx = Number(String(b.id).replace(/\D/g, '')) || 0;
  if (f.phase === 'boarding') {
    const s = f.shuttles.slice().sort((p, q) => Math.hypot(p[0] - b.x, p[1] - b.z) - Math.hypot(q[0] - b.x, q[1] - b.z));
    return s[0] || null;
  }
  if (f.phase === 'ship') {
    if (b.side !== f.winner) return f.map.holds[idx % f.map.holds.length];
    const reactor = f.damage[other(f.winner)].reactor.box;
    const here = FC.cellOf(b.x, b.z, f.w, f.d);
    const face = [reactor[0] - reactor[2] / 2 - 2, reactor[1]];
    if (FC.flowTo(f, FC.cellOf(face[0], face[1], f.w, f.d))[here] >= 0) return face;
    // The reactor is shut off: the nearest blast door still standing, on this trooper's route.
    const doors = f.breakables.filter((br) => br.kind === 'door' && br.hp > 0);
    const mine = doors.filter((br) => (Math.abs(br.box[1] - SHIP_D / 2) < 6) === (idx % 2 === 0));
    let best = null;
    let bd = Infinity;
    for (const br of mine.length ? mine : doors) {
      const front = [br.box[0] - 2.5, br.box[1]];
      const d = FC.flowTo(f, FC.cellOf(front[0], front[1], f.w, f.d))[here];
      if (d >= 0 && d < bd) [best, bd] = [front, d];
    }
    return best || face;
  }
  const wanted = f.points.filter((p) => p.owner !== b.side || contested(f, p));
  const list = wanted.length ? wanted : f.points;
  const p = list.slice().sort((x, y) => Math.hypot(x.x - b.x, x.z - b.z) - Math.hypot(y.x - b.x, y.z - b.z))[(idx % 3 === 0 && list.length > 1) ? 1 : 0];
  // Spread round the point rather than all on its middle.
  const a = (idx * 2.4) % (Math.PI * 2);
  return [p.x + Math.cos(a) * 3, p.z + Math.sin(a) * 3];
}

function inside(f, x, z, r) {
  const s = { a: 0, d: 0 };
  for (const b of f.bodies.values()) if (b.alive && Math.hypot(b.x - x, b.z - z) <= r) s[b.side] += 1;
  return s;
}

function contested(f, p) {
  const s = inside(f, p.x, p.z, POINT_R);
  return s.a > 0 && s.d > 0;
}

// --- The phases ------------------------------------------------------------------------------------------

function groundStep(f, dt) {
  for (const p of f.points) {
    const s = inside(f, p.x, p.z, POINT_R);
    const diff = s.d - s.a;
    if (diff !== 0) {
      const was = p.owner;
      p.progress = clamp(p.progress + (Math.sign(diff) * Math.min(4, Math.abs(diff)) * dt) / CAPTURE_S, -1, 1);
      const owner = p.progress <= -1 ? 'a' : p.progress >= 1 ? 'd' : p.owner && Math.sign(p.progress) === (p.owner === 'a' ? -1 : 1) ? p.owner : null;
      if (owner !== was) {
        p.owner = owner;
        const name = 'ABCDE'[f.points.indexOf(p)];
        f.feed.push({ text: owner ? `${sideName(f, owner)} took point ${name}` : `Point ${name} is neutral` });
        if (owner) for (const b of f.bodies.values()) if (b.alive && b.side === owner && Math.hypot(b.x - p.x, b.z - p.z) <= POINT_R) earn(f, b, CREDITS.capture);
      }
    }
    if (p.owner) f.bars[p.owner] += BAR_RATE * dt;
  }
  supply(f);
  const full = ['a', 'd'].find((s) => f.bars[s] >= BAR_TARGET);
  const late = f.t - f.phaseAt >= GROUND_MAX_S;
  if (full || late) startBoarding(f, full || (f.bars.a > f.bars.d ? 'a' : 'd'));
}

function supply(f) {
  if (f.t < f.nextSupply || !f.map.drops.length) return;
  f.nextSupply = f.t + FC.SUPPLY_EVERY_S;
  const [x, z] = f.map.drops[Math.floor(FC.random(f.rng) * f.map.drops.length) % f.map.drops.length];
  const u = { id: f.nextId++, weapon: FC.random(f.rng) < 0.5 ? 'railgun' : 'rockets', x, z };
  f.pickups.set(u.id, u);
  f.feed.push({ text: `Front supply drop: a ${FC.WEAPONS[u.weapon].name}` });
}

// The ground is won: boarding shuttles land at the winners' drop ship and every point they hold.
function startBoarding(f, side) {
  f.phase = 'boarding';
  f.phaseAt = f.t;
  f.winner = side;
  f.shuttles = [f.map.drop[side], ...f.points.filter((p) => p.owner === side).map((p) => [p.x, p.z])];
  f.feed.push({ text: `${sideName(f, side)} won the ground: board the shuttles! ${BOARD_S} seconds` });
}

function boardingStep(f) {
  if (f.t - f.phaseAt < BOARD_S) return;
  const boarders = [...f.bodies.values()].filter((b) => b.alive && !b.fodder && b.side === f.winner && f.shuttles.some(([x, z]) => Math.hypot(b.x - x, b.z - z) <= BOARD_R));
  f.boarders = boarders.length;
  f.pilotsAboard = boarders.filter((b) => !b.ai).length; // only pilots add time
  const extra = f.bonus === 'boarding' && f.winner === f.holderSide ? BONUSES.boarding.seconds : 0;
  const shipSide = other(f.winner);
  f.phase = 'ship';
  f.phaseAt = f.t;
  f.shipUntil = f.t + SHIP_S + BOARD_BONUS_S * f.pilotsAboard + extra;
  setMap(f, f.shipMaps[shipSide], shipSide);
  fodder(f);
  for (const b of f.bodies.values()) if (b.present) FC.spawn(f, b);
  f.feed.push({ text: `${f.boarders} aboard ${f.shipNames[shipSide]} (${f.pilotsAboard} pilots, +${BOARD_BONUS_S * f.pilotsAboard} s): ${Math.round(f.shipUntil - f.t)} seconds to destroy its reactor` });
}

function shipStep(f) {
  if (f.t >= f.shipUntil) {
    f.feed.push({ text: `The attack on ${f.shipNames[other(f.winner)]} failed` });
    endRound(f, other(f.winner), 'time');
  }
}

// A round ends; first to ROUNDS_TO_WIN wins the match, else back to the ground, bars reset.
function endRound(f, side, how) {
  f.rounds[side] += 1;
  f.score = { ...f.rounds };
  f.feed.push({ text: `Round ${f.round} to ${sideName(f, side)} (${f.rounds.a}–${f.rounds.d})` });
  if (f.rounds[side] >= ROUNDS_TO_WIN) {
    [f.result, f.how] = [side, how];
    return;
  }
  f.round += 1;
  f.phase = 'ground';
  f.phaseAt = f.t;
  f.winner = null;
  f.shuttles = [];
  f.bars = { a: 0, d: 0 };
  setMap(f, f.ground);
  f.points = f.ground.points.map(([x, z]) => ({ x, z, owner: null, progress: 0 }));
  fodder(f);
  for (const b of f.bodies.values()) if (b.present) FC.spawn(f, b);
}

function sideName(f, side) {
  const fac = f.factions[side];
  return fac && F.FACTIONS[fac] ? F.FACTIONS[fac].name : 'the militia';
}

function tick(f, dt) {
  f.t += dt;
  for (const b of f.bodies.values()) {
    if (!b.present) continue;
    if (!b.alive && f.t >= b.respawnAt) FC.spawn(f, b);
    if (!b.alive) continue;
    FC.finishReload(f, b);
    FC.vitals(f, b, dt);
  }
  for (const b of [...f.bodies.values()]) if (b.ai && b.alive && !f.result) FC.aiStep(f, b, dt);
  FC.grenadesStep(f, dt);
  FC.streaksStep(f);
  if (!f.result) {
    if (f.phase === 'ground') groundStep(f, dt);
    else if (f.phase === 'boarding') boardingStep(f);
    else shipStep(f);
  }
  for (const s of ['a', 'd']) for (const [id, until] of f.spotted[s]) if (until < f.t) f.spotted[s].delete(id);
  if (f.t - (f.flowsAt || 0) > 2) {
    f.flows.clear();
    f.flowsAt = f.t;
  }
}

function step(f, dt) {
  for (let left = dt; left > 1e-9 && !f.result; left -= FC.STEP_S) tick(f, Math.min(FC.STEP_S, left));
}

// --- What the pilots see ---------------------------------------------------------------------------------

function frame(f) {
  const ship = f.phase === 'ship' ? other(f.winner) : null;
  const left = f.phase === 'ground' ? GROUND_MAX_S - (f.t - f.phaseAt) : f.phase === 'boarding' ? BOARD_S - (f.t - f.phaseAt) : f.shipUntil - f.t;
  const out = {
    match: f.id,
    t: r1(f.t),
    phase: f.phase,
    map: ship ? `ship-${ship}` : 'ground',
    round: f.round,
    rounds: { ...f.rounds },
    score: { ...f.rounds },
    bars: { a: Math.floor(f.bars.a), d: Math.floor(f.bars.d) },
    left: Math.max(0, Math.round(left)),
    winner: f.winner,
    points: f.points.map((p) => [p.owner, Math.round(p.progress * 100)]),
    shuttles: f.shuttles,
    boarders: f.boarders,
    pilotsAboard: f.pilotsAboard || 0,
    breakables: f.breakables.map((br) => [br.kind, Math.round(br.hp), br.maxHp]),
    reinforcements: { a: 0, d: 0 },
    bodies: [...f.bodies.values()].filter((b) => b.present).map((b) => [b.id, b.name, b.side, r1(b.x), r1(b.z), r1(b.yaw), Math.round(b.hp + b.shield), b.alive, b.ai, b.kills, b.deaths, b.weapon === 'power' && b.power ? b.power.weapon : b.guns[b.weapon]?.weapon || '', b.elite ? 1 : 0, b.fodder ? 1 : 0]),
    doors: [],
    turrets: [],
    pickups: [...f.pickups.values()].map((u) => [u.id, u.weapon, u.x, u.z]),
    grenades: f.grenades.map((g) => [g.id, r1(g.x), r1(g.y), r1(g.z)]),
    active: f.active.map((a) => [a.kind, a.side, r1(a.x), r1(a.z), r1(Math.max(0, a.until - f.t))]),
    shots: f.shots,
    feed: f.feed,
    result: f.result,
  };
  f.shots = [];
  f.feed = [];
  return out;
}

function stateFor(f, fr, name) {
  const s = FC.stateFor(f, fr, name);
  s.type = 'supremacy_state';
  const b = f.bodies.get(name);
  if (s.me && b) Object.assign(s.me, { credits: Math.floor(b.credits || 0), eliteCost: ELITE_COST, wantElite: Boolean(b.wantElite), elite: Boolean(b.elite), hpMax: b.hpMax || FC.HP });
  return s;
}

function joined(f, name) {
  const b = f.bodies.get(name);
  return {
    type: 'supremacy_joined',
    match: f.id,
    planet: f.planet,
    planetName: f.planetName,
    side: b.side,
    factions: f.factions,
    rule: 'supremacy',
    ruleName: 'Supremacy',
    ruleText: 'Hold more of the control points to fill your bar, board the enemy ship, destroy its reactor. First to 2 rounds.',
    target: BAR_TARGET,
    size: GROUND_W,
    depth: GROUND_D,
    maps: { ground: f.ground, 'ship-a': f.shipMaps.a, 'ship-d': f.shipMaps.d },
    map: f.phase === 'ship' ? f.shipMaps[other(f.winner)] : f.ground,
    shipNames: f.shipNames,
    bonus: f.bonus ? { ...BONUSES[f.bonus], id: f.bonus, side: f.holderSide } : null,
    seconds: GROUND_MAX_S,
    hp: FC.HP,
    weapons: FC.WEAPONS,
    attachments: FC.ATTACHMENTS,
    perks: FC.PERKS,
    equipment: FC.EQUIPMENT,
    points: FC.POINTS,
    classes: FC.DEFAULT_CLASSES,
    customMax: FC.CUSTOM_MAX,
    streaks: f.bonus === 'streaks' ? Object.fromEntries(BONUSES.streaks.streaks.map((s) => [s, FC.STREAKS[s]])) : {},
    eliteCost: ELITE_COST,
    rounds: ROUNDS_TO_WIN,
    start: [b.x, b.z],
  };
}

// A pilot joins `side` (an AI trooper makes room) / leaves (one comes back).
function addPilot(f, name, side, loadouts = []) {
  let b = f.bodies.get(name);
  if (b) {
    b.present = true;
    b.loadouts = loadouts;
    return b;
  }
  b = FC.newBody(f, { id: name, name, side, loadouts });
  b.credits = 0;
  balance(f);
  return b;
}

function removePilot(f, name) {
  const b = f.bodies.get(name);
  if (!b) return;
  b.present = false;
  b.alive = false;
  b.respawnAt = Infinity;
  balance(f);
}

// --- The server's matches -----------------------------------------------------------------------------

// Supremacy matches a server runs: like createFacilities. `ships(planet, faction)` names a side's
// ship over the planet.
function createSupremacies({ now = Date.now, speed = 1, send, changed, loadouts = () => [], ships = () => null, onEnd = null }) {
  const matches = new Map();
  const conns = new Map();
  let nextId = 1;
  let ticks = 0;
  const timers = new Set();

  function start(planet, planetName, attacker, defender, opts = {}) {
    const n = nextId++;
    const f = newSupremacy({ id: `s${n}`, planet, planetName, attacker, defender, seed: (Date.now() ^ (n * 2654435761)) >>> 0, now: now(), speed, ships: { a: ships(planet, attacker), d: ships(planet, defender) }, ...opts });
    matches.set(f.id, f);
    conns.set(f.id, new Map());
    return f;
  }

  function enlist(me, f, side) {
    if (me.supremacy && me.supremacy !== f.id) leave(me);
    addPilot(f, me.name, side, loadouts(me.name));
    conns.get(f.id).set(me.name, me);
    me.supremacy = f.id;
    send(me, joined(f, me.name));
    changed();
    return { ok: true, match: f.id };
  }

  function leave(me) {
    const f = me.supremacy && matches.get(me.supremacy);
    me.supremacy = null;
    if (!f) return { ok: true };
    if (conns.get(f.id)?.get(me.name) === me) {
      conns.get(f.id).delete(me.name);
      removePilot(f, me.name);
      if (!f.result && ![...f.bodies.values()].some((b) => b.present && !b.ai)) [f.result, f.how] = ['draw', 'abandoned'];
      changed();
    }
    return { ok: true };
  }

  function handle(me, msg) {
    if (msg.type === 'supremacy_leave') return leave(me);
    const f = me.supremacy && matches.get(me.supremacy);
    if (!f || f.result || String(msg.match) !== f.id) return { ok: true, quiet: true };
    const t = Date.now();
    const key = msg.type === 'supremacy_move' ? 'moves' : 'shots';
    const cap = msg.type === 'supremacy_move' ? FC.MOVES_PER_S : FC.SHOTS_PER_S;
    me.supremacyWindow ||= {};
    if (t - (me.supremacyWindow[key + 'At'] || 0) >= 1000) [me.supremacyWindow[key + 'At'], me.supremacyWindow[key]] = [t, 0];
    if (++me.supremacyWindow[key] > cap) return { ok: true, quiet: true };
    const b = f.bodies.get(me.name);
    switch (msg.type) {
      case 'supremacy_move':
        return FC.move(f, me.name, msg);
      case 'supremacy_fire':
        return FC.fire(f, me.name, msg);
      case 'supremacy_reload':
        return FC.reload(f, me.name);
      case 'supremacy_switch':
        return FC.switchTo(f, me.name, msg);
      case 'supremacy_throw':
        return FC.throwFrag(f, me.name, msg);
      case 'supremacy_stim':
        return FC.stim(f, me.name);
      case 'supremacy_streak':
        return FC.useStreak(f, me.name, msg);
      case 'supremacy_use':
        return { ok: true, quiet: true };
      case 'supremacy_melee':
        return FC.melee(f, me.name);
      case 'supremacy_gear':
        return FC.useGear(f, me.name, msg);
      case 'supremacy_class':
        if (!b) return { ok: true, quiet: true };
        b.loadouts = loadouts(me.name);
        b.want = FC.classOf(msg.cls, b.loadouts).id;
        return { ok: true };
      case 'supremacy_elite':
        // Come back as an elite trooper next time (when the credits are there).
        if (!b) return { ok: true, quiet: true };
        if (msg.on && (b.credits || 0) < ELITE_COST) return fail(`an elite trooper costs ${ELITE_COST} battle credits`);
        b.wantElite = Boolean(msg.on);
        return { ok: true };
      default:
        return fail(`unknown message ${msg.type}`);
    }
  }

  function finish(f) {
    const winner = f.result === 'a' || f.result === 'd' ? f.factions[f.result] : null;
    const vsAi = !humans(f, 'a').length || !humans(f, 'd').length;
    const pts = winner && onEnd ? onEnd(f, winner, vsAi) : 0;
    const text = f.how === 'abandoned' ? 'The match ended: everyone left' : winner ? `${F.FACTIONS[winner].name} won the match ${f.rounds.a}–${f.rounds.d} in rounds: +${pts} campaign points on ${f.planetName}` : `A draw: no campaign points`;
    const fr = frame(f);
    for (const [name, c] of conns.get(f.id)) {
      send(c, stateFor(f, fr, name));
      send(c, { type: 'supremacy_end', match: f.id, winner: f.result, won: f.bodies.get(name)?.side === f.result, text });
    }
    changed();
    const timer = setTimeout(() => {
      timers.delete(timer);
      matches.delete(f.id);
      for (const c of conns.get(f.id)?.values() || []) if (c.supremacy === f.id) c.supremacy = null;
      conns.delete(f.id);
    }, FC.END_KEEP_MS);
    timers.add(timer);
  }

  function tickAll() {
    ticks++;
    const snap = ticks % Math.max(1, Math.round(FC.SNAPSHOT_MS / FC.TICK_MS)) === 0;
    for (const f of matches.values()) {
      if (f.ended) continue;
      if (!f.result) step(f, (FC.TICK_MS / 1000) * speed);
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
  const ticker = setInterval(TM.timed('supremacy', tickAll), FC.TICK_MS);

  function running(planet) {
    return [...matches.values()].filter((f) => !f.result && f.planet === planet);
  }

  function room(f, side) {
    return humans(f, side).length < TEAM_MAX;
  }

  function list() {
    return [...matches.values()]
      .filter((f) => !f.result)
      .map((f) => ({ id: f.id, planet: f.planet, attacker: f.factions.a, defender: f.factions.d, phase: f.phase, round: f.round, rounds: { ...f.rounds }, map: f.ground.name, pilots: [...f.bodies.values()].filter((b) => b.present && !b.ai).map((b) => b.name) }));
  }

  function close() {
    clearInterval(ticker);
    for (const t of timers) clearTimeout(t);
  }

  return { matches, start, enlist, leave, handle, running, room, list, tick: tickAll, close };
}

module.exports = {
  TEAM_MAX,
  FODDER,
  CREW,
  BAR_TARGET,
  BOARD_S,
  BOARD_BONUS_S,
  SHIP_S,
  ROUNDS_TO_WIN,
  REACTOR_HP,
  BLAST_DOOR_HP,
  ELITE_COST,
  ELITE,
  CREDITS,
  BONUSES,
  GROUND,
  SHIPS,
  bonusOf,
  groundMap,
  shipLayout,
  shipName,
  newSupremacy,
  addPilot,
  removePilot,
  startBoarding,
  step,
  frame,
  stateFor,
  joined,
  createSupremacies,
};
