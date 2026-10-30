// Sector battles: real-time battles over one sector of a contested planet, in the spirit of
// Supreme Commander. Pilots command units from their carrier in orbit (or drive one themselves),
// with mass and energy as resources; the defending side is played by an AI (plus any of the
// defender's pilots who join). Simulated here on the server in 2D: x and z on the ground in
// metres, over a square map SIZE across with (0, 0) at a corner. Clients draw the terrain from
// `seed`; the server ignores height.
//
// In memory only: a server restart ends every battle with no result. The attacker takes the
// sector (W.capture) by destroying the defender's Command Node; the defender wins by holding out
// until the battle's time is up, when the attackers have had nothing on the field for a minute
// (or no pilot in the battle for five), or when the war rules no longer let the attack take it.
//
// The pure part (newBattle, step, order, ...) takes a battle and its pilots' names and works in
// simulated seconds; createBattles() at the bottom is what server.js uses: it holds the running
// battles, checks who may start or join one, runs the clock and sends the snapshots.

const D = require('./director');
const F = require('./factions');
const TM = require('./telemetry.ts');
const W = require('./war');

const SIZE = 1600; // the map is SIZE x SIZE metres
const PILOTS_MAX = W.SECTOR_PILOTS; // 32 pilots in one battle
const TICK_MS = 100; // the simulation steps this often (real time)...
const STEP_S = 0.1; // ...and never more than this much simulated time in one step
const SNAPSHOT_MS = 200; // battle_state to every pilot this often
const BATTLE_S = 30 * 60; // a battle lasts this long, then the defender has held
const ABANDON_S = 60; // the attackers lose after this long with nothing on the field...
const LEADERLESS_S = 300; // ...or this long with none of their pilots in the battle
const END_KEEP_MS = 10_000; // a finished battle is forgotten this long after
const RECHECK_MS = 1000; // running battles check the war rules (a lock, the 25% share) this often
const AI_S = 2; // the defender AI thinks this often
const DROP_S = 6; // drop pods land this long after they're bought
const LZ_R = 120; // landing zones' radius
const MASS_START = 400;
const MASS_CAP = 5000;
// Energy: everything costs mass and energy. A pilot's carrier gives a little, Power Generators the
// rest. The defender AI's economy stays mass only.
const ENERGY_START = 4000;
const ENERGY_CAP = 25000;
const CARRIER_ENERGY = 10; // energy a second from each pilot's carrier...
const GENERATOR_POWER = 20; // ...and from each tier 1 Power Generator they own
// Units a factory makes on the planet cost this much of their price; drop pods from the carrier
// cost it all, and bring tier 1 units only.
const FACTORY_DISCOUNT = 0.5;
// Factories upgrade to tier 2 and 3 (paid like production, the factory idle meanwhile); each tier
// makes the higher-tier units: bigger, faster and stronger, and dearer.
const FACTORY_TIERS = 3;
const FACTORY_UPGRADE = { 2: { cost: 400, energy: 2500 }, 3: { cost: 900, energy: 6000 } };
// The economy's tiers: Mass Extractors and Power Generators upgrade like factories. An extractor
// uses as much energy as EXTRACTOR_DRAIN Power Generators of its tier make, and stops while its
// owner has no energy left.
const EXTRACTOR_MASS = [0, 3, 7, 16]; // mass a second by tier
const GENERATOR_POWER_T = [0, 20, 60, 160]; // energy a second by tier
const EXTRACTOR_DRAIN = 5;
const EXTRACTOR_UPGRADE = { 2: { cost: 300, energy: 1500 }, 3: { cost: 900, energy: 6000 } };
const GENERATOR_UPGRADE = { 2: { cost: 200, energy: 0 }, 3: { cost: 600, energy: 0 } };
const STORAGE = { massstorage: { mass: 1500 }, energystorage: { energy: 8000 } };
// Veterancy: a unit earns a star at each of these kill scores (a kill scores the victim's tier;
// an ACU 10, a Command Node 5, any other structure 1). Each star restores a quarter of its health
// and adds a tenth to it, and it mends VET_REGEN hit points a second per star.
const VET_STARS = [3, 8, 15, 25, 40];
const VET_REGEN = 1.5;
const TIERED = ['striker', 'tank', 'artillery', 'aa', 'fighter', 'bomber', 'gunship'];
const TIER_SCALE = { hp: 1.8, damage: 1.6, speed: 1.15, range: 1.1, radius: 1.25, cost: 2.2, energy: 2.5 }; // per tier above 1
const CARRIER_INCOME = 2; // mass a second from each pilot's carrier...
const EXTRACTOR_INCOME = 3; // ...and from each extractor they own
const BUILD_RATE = 15; // mass a second an engineer puts into what it builds
const FACTORY_RATE = 20; // mass a second a factory puts into what it makes
const REPAIR_RATE = 5; // hit points a second an idle engineer gives back
const UNIT_CAP = 120; // units (not structures) per pilot...
const SIDE_CAP = PILOTS_MAX * UNIT_CAP; // ...and per side, counting pilots who have left
const ORDERS_MAX = 32; // orders one unit may have queued
const JOBS_MAX = 10; // jobs one factory may have queued
const COUNT_MAX = 10; // units in one drop or production order
const SPLASH_EDGE = 0.25; // an artillery shell's damage at the edge of its splash, of the full
const DRIVE_BONUS = 1.25; // a unit a pilot drives hits this much harder
const AIM_RADIUS = 6; // a driven unit's shot hits an enemy this close to the aim point
const SNAP_M = 8; // an extractor goes on a mass point this close
const ORDERS_PER_S = 20; // orders a pilot may give a second; more are dropped
const DRIVES_PER_S = 30; // battle_drive messages a second
const MASS_POINTS = [10, 14]; // how many mass points a map has
const MASS_GAP = 80; // metres between mass points at least
const AI_START = 1500; // the defender AI's mass at the start
const AI_INCOME = 6; // its mass a second (times k), plus EXTRACTOR_INCOME per extractor
const AI_CAP = 2000; // the most mass it keeps (so it can't bank a war chest)
const AI_UNITS = 150; // the most units it fields
const AI_ENGINEERS = 3;
const AI_ARMY = 300; // the AI fields an army worth this much (in mass, times k), plus AI_MATCH of
const AI_MATCH = 0.35; // what the attackers field: enough to fight back, not so much that it can't be beaten
const AI_DEFENCE = 0.4; // share of its army (by value) kept defending the base
const AI_WAVE = 600; // its army outside the defence group attacks once worth this much, or
const AI_WAVE_SHARE = 0.4; // this much of what it may field, if that's less (a small army sends small waves)
const AI_FIRST_WAVE_S = 300; // the attackers get this long to land and dig in before the first wave
const AI_HOME = 400; // a wave with nothing left to fight further than this from the Command Node goes back
const AI_MIX = ['striker', 'tank', 'striker', 'aa', 'tank', 'artillery', 'striker', 'tank'];
const MILITIA_K = 0.6; // an unclaimed sector's militia earns this much of a faction's AI
const CELL = 40; // metres per cell of the grid used to find what's near
// Command: every attacking commander lands an Armoured Command Unit (ACU) and is out of the battle
// when it falls; the defender gets a Command Node (and a drop zone by it) for every attacking
// commander, and a defending pilot who joins commands one of them. The attackers win when every
// Node is down, the defenders when every ACU is (or the clock runs out). A side resigns when
// RESIGN_SHARE of its commanders still in the fight vote to.
const RESIGN_SHARE = 0.66;
const NODE_GAP = 300; // metres between the defender's Command Nodes, across their end of the map
const OUT = "your ACU was destroyed: you're out of this battle";
const CAMPAIGN_SIDE = 8; // commanders a side in a campaign match
const CAMPAIGN_BONUS = { mining: { mass: 1.15 } }; // planet bonuses that touch sector battles (campaign.js BONUSES)

// Every unit and structure. `hits`: what it can shoot (land, air, structure). Both sides use one
// roster; it goes to the clients in battle_joined.
const LAND = ['land', 'structure'];
const CATALOG = {
  engineer: { name: 'Engineer', kind: 'land', hp: 150, speed: 9, damage: 0, reload: 0, range: 12, cost: 50, energy: 250, radius: 3, vision: 80, hits: [], builds: ['extractor', 'generator', 'turret', 'aaturret', 'factory', 'airfactory', 'shield', 'massstorage', 'energystorage'] },
  // One per attacking commander, landed when they join, never built: tougher than a handful of tier
  // 1 units, builds what an engineer does, and goes up in a blast that wrecks what's round it.
  acu: { name: 'Armoured Command Unit', kind: 'land', hp: 4000, speed: 7, damage: 60, reload: 1, range: 45, cost: 0, energy: 0, radius: 5, vision: 140, hits: ['land', 'structure', 'air'], builds: ['extractor', 'generator', 'turret', 'aaturret', 'factory', 'airfactory', 'massstorage', 'energystorage'], acu: true, blast: { radius: 45, damage: 3000 } },
  scout: { name: 'Scout', kind: 'land', hp: 90, speed: 22, damage: 5, reload: 1, range: 30, cost: 25, energy: 100, radius: 3, vision: 160, hits: LAND },
  striker: { name: 'Striker', kind: 'land', hp: 280, speed: 12, damage: 18, reload: 1, range: 40, cost: 55, energy: 275, radius: 3, vision: 80, hits: LAND },
  tank: { name: 'Tank', kind: 'land', hp: 750, speed: 9, damage: 50, reload: 1.5, range: 55, cost: 130, energy: 650, radius: 4, vision: 80, hits: LAND },
  artillery: { name: 'Artillery', kind: 'land', hp: 220, speed: 7, damage: 120, reload: 4, range: 160, cost: 170, energy: 850, radius: 3, vision: 80, hits: LAND, minRange: 30, splash: 14, shell: 160 },
  aa: { name: 'AA', kind: 'land', hp: 320, speed: 10, damage: 30, reload: 0.5, range: 80, cost: 90, energy: 450, radius: 3, vision: 100, hits: ['air'] },
  fighter: { name: 'Fighter', kind: 'air', hp: 260, speed: 30, damage: 22, reload: 0.6, range: 40, cost: 70, energy: 500, radius: 3, vision: 120, hits: ['air'] },
  bomber: { name: 'Bomber', kind: 'air', hp: 520, speed: 18, damage: 260, reload: 5, range: 14, cost: 160, energy: 1100, radius: 3.5, vision: 100, hits: ['land', 'structure'], splash: 12, shell: 60 },
  gunship: { name: 'Gunship', kind: 'air', hp: 420, speed: 24, damage: 26, reload: 1, range: 45, cost: 230, energy: 1400, radius: 3, vision: 100, hits: ['land', 'structure', 'air'] },
  extractor: { name: 'Mass Extractor', kind: 'structure', hp: 600, damage: 0, cost: 60, energy: 200, radius: 8, hits: [], income: EXTRACTOR_INCOME, tiers: 3, upgrade: EXTRACTOR_UPGRADE, mass: EXTRACTOR_MASS, drain: GENERATOR_POWER_T.map((p) => p * EXTRACTOR_DRAIN) },
  generator: { name: 'Power Generator', kind: 'structure', hp: 500, damage: 0, cost: 20, energy: 0, radius: 7, hits: [], power: GENERATOR_POWER, tiers: 3, upgrade: GENERATOR_UPGRADE, powers: GENERATOR_POWER_T },
  aaturret: { name: 'AA Turret', kind: 'structure', hp: 900, damage: 26, reload: 0.5, range: 90, cost: 110, energy: 500, radius: 6, hits: ['air'] },
  shield: { name: 'Shield Generator', kind: 'structure', hp: 800, damage: 0, cost: 180, energy: 1200, radius: 6, hits: [], shield: { radius: 32, hp: 4000, regen: 40, drain: 50 } },
  massstorage: { name: 'Mass Storage', kind: 'structure', hp: 600, damage: 0, cost: 80, energy: 200, radius: 6, hits: [], storage: STORAGE.massstorage },
  energystorage: { name: 'Energy Storage', kind: 'structure', hp: 600, damage: 0, cost: 60, energy: 0, radius: 6, hits: [], storage: STORAGE.energystorage },
  turret: { name: 'Turret', kind: 'structure', hp: 1300, damage: 32, reload: 1, range: 65, cost: 160, energy: 800, radius: 8, hits: ['land', 'air'] },
  factory: { name: 'Land Factory', kind: 'structure', hp: 2600, damage: 0, cost: 320, energy: 1200, radius: 12, hits: [], produces: ['engineer', 'scout', 'striker', 'tank', 'artillery', 'aa'], tiers: FACTORY_TIERS, upgrade: FACTORY_UPGRADE },
  airfactory: { name: 'Air Factory', kind: 'structure', hp: 2200, damage: 0, cost: 280, energy: 1500, radius: 12, hits: [], produces: ['fighter', 'bomber', 'gunship'], tiers: FACTORY_TIERS, upgrade: FACTORY_UPGRADE },
  outpost: { name: 'Outpost', kind: 'structure', hp: 2000, damage: 0, cost: 0, energy: 0, radius: 12, hits: [] },
  node: { name: 'Command Node', kind: 'structure', hp: 5000, damage: 20, reload: 1, range: 50, cost: 0, energy: 0, radius: 14, hits: ['land', 'air'] },
};
// The higher tiers of the combat units ("tank_t2" is a Tank Mk II), made by upgraded factories.
for (const base of TIERED)
  for (let t = 2; t <= FACTORY_TIERS; t++) {
    const c = CATALOG[base];
    const k = (f) => TIER_SCALE[f] ** (t - 1);
    CATALOG[`${base}_t${t}`] = {
      ...c,
      name: `${c.name} Mk ${'I'.repeat(t)}`,
      base,
      tier: t,
      hp: Math.round(c.hp * k('hp')),
      damage: Math.round(c.damage * k('damage')),
      speed: Math.round(c.speed * k('speed') * 10) / 10,
      range: Math.round(c.range * k('range')),
      radius: Math.round(c.radius * k('radius') * 10) / 10,
      vision: Math.round(c.vision * k('range')),
      cost: Math.round(c.cost * k('cost')),
      energy: Math.round(c.energy * k('energy')),
    };
    CATALOG[c.kind === 'air' ? 'airfactory' : 'factory'].produces.push(`${base}_t${t}`);
  }
const tierOf = (type) => CATALOG[type]?.tier || 1;
// Energy prices are halved from what they were before extractors used energy: with every extractor
// needing five generators' worth to run, units at the old prices starved the economy.
const ENERGY_PRICE = 0.5;
for (const c of Object.values(CATALOG)) if (c.energy) c.energy = Math.round(c.energy * ENERGY_PRICE);
const DROPPABLE = Object.keys(CATALOG).filter((id) => CATALOG[id].kind !== 'structure' && tierOf(id) === 1 && !CATALOG[id].acu);
const builds = (u) => !!CATALOG[u.type].builds; // engineers and ACUs
const makes = (u) => !!CATALOG[u.type].produces; // land and air factories
const upgradable = (u) => !!CATALOG[u.type].upgrade; // factories, extractors, generators
const BUILDABLE = CATALOG.engineer.builds;
const RADIUS_MAX = Math.max(...Object.values(CATALOG).map((c) => c.radius));

function fail(reason) {
  return { ok: false, reason };
}

const r1 = (x) => Math.round(x * 10) / 10;
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const num = (v) => typeof v === 'number' && Number.isFinite(v);
const dist = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
const isStructure = (u) => CATALOG[u.type].kind === 'structure';
const mobile = (u) => !isStructure(u);

// mulberry32: a small seeded generator, so the same seed always gives the same map and the AI the
// same choices. `state` is {s}; returns [0, 1).
function random(state) {
  state.s = (state.s + 0x6d2b79f5) >>> 0;
  let t = state.s;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// The seed of a sector's map: the same planet and sector always give the same battlefield.
function seedFor(planetId, sectorId) {
  return W.hash(`${planetId}/${sectorId}`);
}

// --- The map --------------------------------------------------------------------------------

// The landing zone near one edge, the defender's base near the other, its structures, and 10 to
// 14 mass points at least MASS_GAP apart: three by the Command Node (the defender's extractors go
// on them), two by the landing zone, the rest anywhere.
function layout(seed, outposts = []) {
  const rng = { s: seed };
  const r = () => random(rng);
  const lz = { x: r1(400 + r() * 800), z: 170, r: LZ_R };
  const node = { x: r1(400 + r() * 800), z: 1430 };
  const base = [
    { type: 'node', x: node.x, z: node.z },
    { type: 'turret', x: node.x - 45, z: node.z - 42 },
    { type: 'turret', x: node.x + 45, z: node.z - 42 },
  ];
  outposts.slice(0, 4).forEach((o, i) => {
    const a = Math.PI * (0.15 + 0.7 * ((i + 0.5) / Math.min(4, outposts.length))) + Math.PI; // on the far side of the node
    base.push({ type: 'outpost', name: o.name, x: r1(node.x + 85 * Math.cos(a)), z: r1(node.z - 85 * Math.sin(a)) });
  });
  const points = [];
  const free = (x, z, gap) =>
    x > 60 && x < SIZE - 60 && z > 60 && z < SIZE - 60 &&
    points.every((p) => Math.hypot(p.x - x, p.z - z) >= gap) &&
    base.every((s) => Math.hypot(s.x - x, s.z - z) >= CATALOG[s.type].radius + 22) &&
    Math.hypot(lz.x - x, lz.z - z) >= LZ_R + 15;
  const place = (near, from, to) => {
    for (let gap = MASS_GAP, tries = 0; ; tries++) {
      if (tries > 0 && tries % 300 === 0) gap *= 0.85; // a crowded map takes points a little closer
      if (tries === 1500) near = null; // and anywhere will do in the end
      const a = r() * 2 * Math.PI;
      const d = from + r() * (to - from);
      const x = near ? near.x + d * Math.cos(a) : 80 + r() * (SIZE - 160);
      const z = near ? near.z + d * Math.sin(a) : 80 + r() * (SIZE - 160);
      if (free(x, z, gap)) return points.push({ id: points.length + 1, x: r1(x), z: r1(z) });
    }
  };
  const count = MASS_POINTS[0] + Math.floor(r() * (MASS_POINTS[1] - MASS_POINTS[0] + 1));
  for (let i = 0; i < 3; i++) place(node, 70, 120);
  for (let i = 0; i < 2; i++) place(lz, LZ_R + 30, LZ_R + 90);
  while (points.length < count) place(null);
  return { lz, enemyLz: { x: node.x, z: node.z, r: LZ_R }, node, base, massPoints: points };
}

// A new battle over `sector` of war planet `wp`. `attacker` is a faction; `defender` the sector's
// owner, or null for an unclaimed sector's militia; `outposts` the defender's outposts there
// ({name}); `k` the AI's income factor (aiRate). `now` and `speed` set when its time is up.
function newBattle({ id = 'b1', wp, sector, attacker, defender = null, outposts = [], k = 1, now = Date.now(), speed = 1 }) {
  const seed = seedFor(wp.id, sector.id);
  const map = layout(seed, outposts);
  const b = {
    id,
    planet: wp.id,
    planetName: wp.name,
    sector: sector.id,
    sectorName: sector.name,
    attacker,
    defender,
    seed,
    ...map,
    startedAt: now,
    endsAt: now + (BATTLE_S * 1000) / speed,
    speed,
    t: 0, // simulated seconds since the start
    units: new Map(), // id -> unit or structure, in the order they came
    nextId: 1,
    pilots: new Map(), // name -> {name, side, faction, mass, present, drive}
    ai: { mass: AI_START, k, patrol: 0, mix: 0, waves: 0 },
    aiAt: 0,
    rng: { s: (seed ^ 0x9e3779b9) >>> 0 },
    shells: [], // artillery shells in the air
    dropCount: { a: 0, d: 0 },
    emptySince: null, // when the attackers last had nothing on the field
    leaderless: null, // when the last of the attackers' pilots left
    result: null, // 'a' or 'd' once it's decided, and `how`
    // Since the last snapshot:
    dead: [],
    shots: [],
    feed: [],
  };
  for (const s of map.base) {
    const st = spawn(b, s.type, 'd', '', s.x, s.z);
    if (s.name) st.name = s.name;
    if (s.type === 'node') [b.nodeId, b.nodes] = [st.id, [st.id]];
  }
  const near = map.massPoints.slice().sort((p, q) => Math.hypot(p.x - map.node.x, p.z - map.node.z) - Math.hypot(q.x - map.node.x, q.z - map.node.z));
  for (const p of near.slice(0, 3)) spawn(b, 'extractor', 'd', '', p.x, p.z).point = p.id;
  return b;
}

// The defender AI's income factor: 1 for a faction, the Coma director's intensity against the
// attacker (doubled, at least 0.5) for Coma, MILITIA_K for an unclaimed sector.
// --- The defender's Command Nodes -------------------------------------------------------------

// Where the defender's `i`th Command Node stands: the first is the map's, the rest spread either
// side of it across the defender's end.
function nodeSpot(b, i) {
  if (i === 0) return { x: b.node.x, z: b.node.z };
  const side = i % 2 ? 1 : -1;
  let x = b.node.x + side * Math.ceil(i / 2) * NODE_GAP;
  if (x < 120 || x > SIZE - 120) x = b.node.x - side * (Math.ceil(i / 2) + 1) * NODE_GAP; // off the map: the other side
  return { x: clamp(x, 120, SIZE - 120), z: b.node.z - (i % 2) * 60 };
}

// Another Command Node for the defender, with two turrets by it (one for each attacking commander).
function addNode(b) {
  const at = nodeSpot(b, b.nodes.length);
  const n = spawn(b, 'node', 'd', '', at.x, at.z);
  spawn(b, 'turret', 'd', '', at.x - 45, at.z - 42);
  spawn(b, 'turret', 'd', '', at.x + 45, at.z - 42);
  b.nodes.push(n.id);
  b.feed.push('The defenders raised another Command Node');
  return n;
}

function aliveNodes(b) {
  return b.nodes.map((id) => b.units.get(id)).filter((n) => n && n.hp > 0);
}

// The Node the defender AI plans round: its first one still standing.
function aiNode(b) {
  return aliveNodes(b).find((n) => !n.commander) || aliveNodes(b)[0] || b.node;
}

function aiRate(g, attacker, defender) {
  if (!defender) return MILITIA_K;
  if (defender === 'coma') return Math.max(0.5, D.intensityFor(g, attacker) * 2);
  return 1;
}

function spawn(b, type, side, owner, x, z, { built = true, dropAt = 0 } = {}) {
  const c = CATALOG[type];
  const u = { id: b.nextId++, type, side, owner, x: clamp(x, 0, SIZE), z: clamp(z, 0, SIZE), hp: c.hp, heading: side === 'a' ? 0 : Math.PI, orders: [], target: null, cd: 0, state: 'idle', dropAt, searchAt: 0 };
  if (isStructure(u)) {
    u.heading = 0;
    u.built = built;
    u.progress = built ? 1 : 0;
    u.paid = built ? c.cost : 0;
    if (!built) u.hp = c.hp * 0.1;
    if (c.produces) u.queue = [];
    if (c.upgrade) u.tier = 1;
    if (c.shield) u.shieldHp = 0;
  }
  u.maxHp = c.hp;
  if (!isStructure(u)) {
    u.vet = 0;
    u.kills = 0;
  }
  if (dropAt) u.state = 'drop';
  b.units.set(u.id, u);
  return u;
}

// --- Pilots and their mass ------------------------------------------------------------------

// A new attacking commander lands their ACU (and the defender gets another Command Node once there
// are more commanders than Nodes); a new defending one takes command of a Node nobody commands.
function addPilot(b, name, side, faction) {
  let p = b.pilots.get(name);
  const fresh = !p;
  if (!p) b.pilots.set(name, (p = { name, side, faction, mass: MASS_START, energy: ENERGY_START, drive: null, out: false, resign: false }));
  p.side = side;
  p.present = true;
  if (fresh && side === 'a') {
    const commanders = [...b.pilots.values()].filter((q) => q.side === 'a').length;
    while (b.nodes.length < commanders) addNode(b);
    p.acu = dropUnits(b, 'a', name, 'acu', 1)[0].id;
  }
  if (fresh && side === 'd') {
    const free = aliveNodes(b).find((n) => !n.commander);
    if (free) [free.commander, p.node] = [name, free.id];
  }
  return p;
}

// A pilot who may give orders: in the battle, and (attacking) with their ACU still standing.
function commander(b, name) {
  const p = b.pilots.get(name);
  if (!p?.present) return fail('not in that battle');
  if (p.out) return fail(OUT);
  return p;
}

// battle_resign: a commander votes to resign (or takes the vote back). When RESIGN_SHARE of their
// side's commanders still in the fight have voted, the side gives up the battle.
function resign(b, name, yes = true) {
  const p = commander(b, name);
  if (p.ok === false) return p;
  p.resign = !!yes;
  const voters = present(b, p.side).filter((q) => !q.out);
  const votes = voters.filter((q) => q.resign).length;
  b.feed.push(`${name} ${yes ? 'votes to resign' : 'takes back their resign vote'} (${votes} of ${voters.length})`);
  if (!b.result && votes >= RESIGN_SHARE * voters.length - 1e-9) {
    [b.result, b.how] = [p.side === 'a' ? 'd' : 'a', 'resign'];
    b.feed.push(`${p.side === 'a' ? 'The attackers' : 'The defenders'} resigned`);
  }
  return { ok: true, votes, voters: voters.length };
}

// A pilot leaves: whatever they drive goes back to them, and their units stand where they are.
function removePilot(b, name) {
  const p = b.pilots.get(name);
  if (!p) return;
  release(b, name);
  p.present = false;
  for (const u of b.units.values()) if (u.owner === name && mobile(u)) [u.orders, u.target] = [[], null];
}

function present(b, side = null) {
  return [...b.pilots.values()].filter((p) => p.present && (!side || p.side === side));
}

// The purse that pays for `owner`'s things: their own, or the AI's ('').
function purse(b, owner) {
  return owner ? b.pilots.get(owner) : b.ai;
}

function extractors(b, owner, side) {
  return extractorCounts(b).get(`${side}|${owner}`) || 0;
}

// Finished extractors by owner: 'side|name' -> how many.
function extractorCounts(b) {
  const out = new Map();
  for (const u of b.units.values()) if (u.type === 'extractor' && u.built) out.set(`${u.side}|${u.owner}`, (out.get(`${u.side}|${u.owner}`) || 0) + 1);
  return out;
}

// Everyone's economy at once: 'side|name' -> { mass, power, drain, massCap, energyCap } a second
// from their finished extractors, generators, shields and storage (the carrier's share not in it).
function economies(b) {
  const out = new Map();
  for (const u of b.units.values()) {
    if (!isStructure(u) || !u.built) continue;
    const c = CATALOG[u.type];
    if (u.type !== 'extractor' && u.type !== 'generator' && !c.shield && !c.storage) continue;
    const k = `${u.side}|${u.owner}`;
    if (!out.has(k)) out.set(k, { mass: 0, power: 0, drain: 0, massCap: 0, energyCap: 0 });
    const e = out.get(k);
    const t = u.tier || 1;
    if (u.type === 'extractor') [e.mass, e.drain] = [e.mass + c.mass[t], e.drain + c.drain[t]];
    if (u.type === 'generator') e.power += c.powers[t];
    if (c.shield) e.drain += c.shield.drain;
    if (c.storage) [e.massCap, e.energyCap] = [e.massCap + (c.storage.mass || 0), e.energyCap + (c.storage.energy || 0)];
  }
  return out;
}

const NO_ECONOMY = { mass: 0, power: 0, drain: 0, massCap: 0, energyCap: 0 };

// Mass a second for a pilot (or the AI, ''): the carrier's, and their extractors' unless they've
// run out of energy (the AI's extractors need none).
function income(b, owner) {
  if (!owner) return AI_INCOME * b.ai.k + [...b.units.values()].filter((u) => u.type === 'extractor' && u.built && u.side === 'd' && !u.owner).reduce((a, u) => a + EXTRACTOR_MASS[u.tier || 1], 0);
  const p = b.pilots.get(owner);
  if (!p) return 0;
  const e = economies(b).get(`${p.side}|${owner}`) || NO_ECONOMY;
  return CARRIER_INCOME + (p.stalled ? 0 : e.mass);
}

// Energy a second for a pilot, net: the carrier's and their generators', less what their
// extractors and shields use (the AI has none: it pays mass only). Below zero with none stored,
// their extractors stop (`stalled`).
function energyIncome(b, owner) {
  const p = owner && b.pilots.get(owner);
  if (!p) return 0;
  const e = economies(b).get(`${p.side}|${owner}`) || NO_ECONOMY;
  return CARRIER_ENERGY + e.power - e.drain;
}

// How much of something costing `mass` and `energy` a purse can pay for now, as a share of it
// (the AI's purse has no energy: it never runs short of it).
function affordable(pay, mass, energy) {
  if (!pay) return 0;
  let share = mass > 0 ? pay.mass / mass : Infinity;
  if (energy > 0 && pay.energy !== undefined) share = Math.min(share, pay.energy / energy);
  return Math.max(0, share);
}

function charge(pay, mass, energy) {
  pay.mass -= mass;
  if (pay.energy !== undefined) pay.energy -= energy;
}

const priceText = (mass, energy) => `${Math.round(mass)} mass${energy ? ` and ${Math.round(energy)} energy` : ''}`;

// A pilot's units in the field or on the way down (structures don't count).
function unitCount(b, owner, side) {
  let n = 0;
  for (const u of b.units.values()) if (u.owner === owner && u.side === side && mobile(u) && !CATALOG[u.type].acu) n++;
  return n;
}

// Every unit a side has in the field or on the way down, whoever owns it.
function sideCount(b, side) {
  let n = 0;
  for (const u of b.units.values()) if (u.side === side && mobile(u) && !CATALOG[u.type].acu) n++;
  return n;
}

// --- Buying units ---------------------------------------------------------------------------

// Where a side's drop pods come down: the landing zone, or by the Command Node.
// Where a side's drop pods come down: the attackers' landing zone; by a defending commander's own
// Command Node; the AI's in turn by each of the Nodes nobody commands.
function dropSpot(b, side, owner = '') {
  if (side === 'a') return b.lz;
  const mine = owner && b.pilots.get(owner)?.node;
  let node = mine && b.units.get(mine);
  if (!node || node.hp <= 0) {
    const ai = aliveNodes(b).filter((n) => !n.commander);
    const all = ai.length ? ai : aliveNodes(b);
    node = all.length ? all[b.dropCount.d % all.length] : b.node;
  }
  return { x: node.x, z: node.z - 60 };
}

// `count` units of `type` for `owner` (a pilot, or '' for the AI), landing DROP_S from now in a
// small ring round the side's drop spot.
function dropUnits(b, side, owner, type, count) {
  const at = dropSpot(b, side, owner);
  const out = [];
  for (let i = 0; i < count; i++) {
    const n = b.dropCount[side]++ % 40;
    const a = n * 2.39996;
    const d = 10 + 6 * Math.sqrt(n);
    out.push(spawn(b, type, side, owner, at.x + d * Math.cos(a), at.z + d * Math.sin(a), { dropAt: b.t + DROP_S }));
  }
  return out;
}

// battle_drop: a pilot buys units, paid for now, landing by drop pod.
function drop(b, name, type, count) {
  const p = commander(b, name);
  if (p.ok === false) return p;
  if (CATALOG[type] && CATALOG[type].kind !== 'structure' && tierOf(type) > 1) return fail('your carrier drops tier 1 units only: build a factory and upgrade it for higher tiers');
  if (!DROPPABLE.includes(type)) return fail('no such unit');
  const n = Math.floor(Number(count));
  if (!(n >= 1 && n <= COUNT_MAX)) return fail(`drop 1 to ${COUNT_MAX} at a time`);
  const cost = CATALOG[type].cost * n;
  const energy = CATALOG[type].energy * n;
  if (p.mass + 1e-9 < cost || p.energy + 1e-9 < energy) return fail(`not enough ${p.mass + 1e-9 < cost ? 'mass' : 'energy'}: ${n} ${CATALOG[type].name}${n === 1 ? '' : 's'} cost ${priceText(cost, energy)}`);
  if (unitCount(b, name, p.side) + n > UNIT_CAP) return fail(`you can field ${UNIT_CAP} units`);
  if (sideCount(b, p.side) + n > SIDE_CAP) return fail(`your side has ${SIDE_CAP} units in the field`);
  charge(p, cost, energy);
  return { ok: true, units: dropUnits(b, p.side, name, type, n).map((u) => u.id) };
}

// battle_produce: a pilot's finished factory makes land units, paying as it goes.
function produce(b, name, factoryId, type, count) {
  const p = commander(b, name);
  if (p.ok === false) return p;
  const f = b.units.get(Number(factoryId));
  if (!f || !makes(f) || f.owner !== name) return { ok: true, quiet: true };
  if (!f.built) return fail('that factory is still being built');
  if (!CATALOG[f.type].produces.includes(type)) return fail(f.type === 'factory' ? 'a factory makes land units only' : 'an air factory makes air units only');
  if (tierOf(type) > (f.tier || 1)) return fail(`a tier ${f.tier || 1} factory can't make the ${CATALOG[type].name}: upgrade it to tier ${tierOf(type)}`);
  const n = Math.floor(Number(count));
  if (!(n >= 1 && n <= COUNT_MAX)) return fail(`make 1 to ${COUNT_MAX} at a time`);
  if (f.queue.length >= JOBS_MAX) return fail(`a factory queues ${JOBS_MAX} orders`);
  f.queue.push({ unit: type, left: n, done: 0 });
  return { ok: true };
}

// battle_upgrade: a pilot's finished factory upgrades to its next tier, paid as it goes (it makes
// nothing meanwhile, and picks its queue up again after).
function upgradeFactory(b, name, factoryId) {
  const p = commander(b, name);
  if (p.ok === false) return p;
  const f = b.units.get(Number(factoryId));
  if (!f || !upgradable(f) || f.owner !== name) return { ok: true, quiet: true };
  const what = f.type === 'factory' ? 'factory' : CATALOG[f.type].name;
  if (!f.built) return fail(`that ${what} is still being built`);
  if (f.upgrade) return fail(`that ${what} is already upgrading`);
  if ((f.tier || 1) >= CATALOG[f.type].tiers) return fail(`that ${what} is at tier ${CATALOG[f.type].tiers}, the top`);
  f.upgrade = { to: (f.tier || 1) + 1, done: 0 };
  return { ok: true };
}

// --- Orders ---------------------------------------------------------------------------------

// The structure that stands in the way of building `type` at (x, z), if any.
function blocked(b, type, x, z, except = null) {
  const r = CATALOG[type].radius;
  for (const u of b.units.values()) if (u !== except && isStructure(u) && Math.hypot(u.x - x, u.z - z) < r + CATALOG[u.type].radius) return u;
  return null;
}

// The free mass point within SNAP_M of (x, z), if any. An unfinished extractor of `side` on it
// doesn't count as taking it (engineers can help build it).
function massPointAt(b, x, z, side) {
  const p = b.massPoints.filter((m) => Math.hypot(m.x - x, m.z - z) <= SNAP_M).sort((m, n) => Math.hypot(m.x - x, m.z - z) - Math.hypot(n.x - x, n.z - z))[0];
  if (!p) return null;
  const on = [...b.units.values()].find((u) => u.type === 'extractor' && u.point === p.id);
  return !on || (!on.built && on.side === side) ? p : null;
}

// Where a group's units go when sent to (x, z): each keeps its place round the group's middle,
// the whole shape pulled in so the group stays loose but together.
function formation(units, x, z) {
  if (units.length < 2) return units.map(() => [x, z]);
  const cx = units.reduce((a, u) => a + u.x, 0) / units.length;
  const cz = units.reduce((a, u) => a + u.z, 0) / units.length;
  const cap = 8 + 4 * Math.sqrt(units.length);
  const widest = Math.max(...units.map((u) => Math.hypot(u.x - cx, u.z - cz)));
  const k = widest > cap ? cap / widest : 1; // the whole shape shrinks, so it keeps its order
  return units.map((u) => [clamp(x + (u.x - cx) * k, 0, SIZE), clamp(z + (u.z - cz) * k, 0, SIZE)]);
}

// battle_order from a pilot (or the AI, ''): move, amove, attack, stop or build, for their own
// units; `queue` adds it to each unit's queue (up to ORDERS_MAX) instead of replacing it. Units
// that aren't theirs, and unknown ids, are left out without a word.
function order(b, name, msg) {
  if (name && !b.pilots.get(name)?.present) return fail('not in that battle');
  if (name && b.pilots.get(name).out) return fail(OUT);
  const ids = Array.isArray(msg.units) ? msg.units.slice(0, 400) : [];
  const units = [...new Set(ids.map(Number))].map((id) => b.units.get(id)).filter((u) => u && u.owner === name && (name || u.side === 'd') && mobile(u) && !u.driven);
  if (!units.length) return { ok: true, quiet: true };
  const queue = msg.queue === true;
  const give = (u, o) => {
    if (queue) {
      if (u.orders.length < ORDERS_MAX) u.orders.push(o);
    } else [u.orders, u.target] = [[o], null];
  };
  switch (msg.order) {
    case 'stop':
      for (const u of units) [u.orders, u.target] = [[], null];
      return { ok: true };
    case 'move':
    case 'amove': {
      if (!num(msg.x) || !num(msg.z)) return { ok: true, quiet: true };
      const spots = formation(units, clamp(msg.x, 0, SIZE), clamp(msg.z, 0, SIZE));
      units.forEach((u, i) => give(u, { order: msg.order, x: spots[i][0], z: spots[i][1] }));
      return { ok: true };
    }
    case 'attack': {
      const t = b.units.get(Number(msg.target));
      if (!t || t.side === units[0].side) return { ok: true, quiet: true };
      // Units that can't shoot it (engineers; strikers at a gunship) go on with what they were doing.
      for (const u of units) if (CATALOG[u.type].hits.includes(CATALOG[t.type].kind)) give(u, { order: 'attack', target: t.id });
      return { ok: true };
    }
    case 'build': {
      const engineers = units.filter(builds); // engineers and ACUs
      if (!engineers.length) return { ok: true, quiet: true };
      if (!engineers.some((u) => CATALOG[u.type].builds.includes(msg.structure))) return fail('engineers build extractors, generators, turrets and factories');
      if (!num(msg.x) || !num(msg.z)) return { ok: true, quiet: true };
      const r = CATALOG[msg.structure].radius;
      let [x, z] = [clamp(msg.x, r, SIZE - r), clamp(msg.z, r, SIZE - r)];
      if (msg.structure === 'extractor') {
        const p = massPointAt(b, x, z, engineers[0].side);
        if (!p) return fail('extractors go on a free mass point');
        [x, z] = [p.x, p.z];
      } else {
        const there = blocked(b, msg.structure, x, z);
        if (there && !(there.type === msg.structure && !there.built && there.side === engineers[0].side && Math.hypot(there.x - x, there.z - z) < 4))
          return fail('something is already built there');
      }
      for (const u of engineers) give(u, { order: 'build', structure: msg.structure, x, z });
      return { ok: true };
    }
    default:
      return { ok: true, quiet: true };
  }
}

// --- Driving a unit -------------------------------------------------------------------------

// battle_possess: the pilot takes direct control of one of their own landed units (one at a time).
function possess(b, name, unitId) {
  const p = commander(b, name);
  if (p.ok === false) return p;
  const u = b.units.get(Number(unitId));
  if (!u || u.owner !== name) return { ok: true, quiet: true };
  if (!mobile(u)) return fail('you can only drive land and air units');
  if (u.dropAt) return fail('that unit is still coming down');
  if (p.drive && p.drive !== u.id) release(b, name);
  [u.orders, u.target] = [[], null];
  u.driven = { mx: 0, mz: 0, ax: u.x, az: u.z, fire: false, t: b.t };
  p.drive = u.id;
  return { ok: true, unit: u.id };
}

// battle_drive: where the driven unit goes (`move`, a direction no longer than 1), where it aims
// and whether it fires.
function drive(b, name, msg) {
  const p = b.pilots.get(name);
  const u = p?.drive && b.units.get(p.drive);
  if (!u?.driven) return { ok: true, quiet: true };
  const move = Array.isArray(msg.move) && msg.move.length === 2 && msg.move.every(num) ? msg.move : [0, 0];
  const len = Math.hypot(move[0], move[1]);
  const [mx, mz] = len > 1 ? [move[0] / len, move[1] / len] : move;
  const aim = Array.isArray(msg.aim) && msg.aim.length === 2 && msg.aim.every(num) ? msg.aim : [u.driven.ax, u.driven.az];
  u.driven = { mx, mz, ax: clamp(aim[0], 0, SIZE), az: clamp(aim[1], 0, SIZE), fire: msg.fire === true, t: b.t };
  return { ok: true };
}

// battle_release: the driven unit goes back to taking orders, standing where it is.
function release(b, name) {
  const p = b.pilots.get(name);
  if (!p?.drive) return { ok: true };
  const u = b.units.get(p.drive);
  if (u) u.driven = null;
  p.drive = null;
  return { ok: true };
}

// --- The simulation -------------------------------------------------------------------------

function buildGrid(b) {
  b.grid = new Map();
  for (const u of b.units.values()) {
    if (u.dropAt || u.hp <= 0) continue;
    const k = Math.floor(u.x / CELL) * 1024 + Math.floor(u.z / CELL);
    if (!b.grid.has(k)) b.grid.set(k, []);
    b.grid.get(k).push(u);
  }
}

// Calls fn(u, d) for everything within `r` of (x, z), d its distance.
function near(b, x, z, r, fn) {
  const [x0, x1, z0, z1] = [Math.floor((x - r) / CELL), Math.floor((x + r) / CELL), Math.floor((z - r) / CELL), Math.floor((z + r) / CELL)];
  for (let cx = x0; cx <= x1; cx++)
    for (let cz = z0; cz <= z1; cz++) {
      const cell = b.grid.get(cx * 1024 + cz);
      if (!cell) continue;
      for (const u of cell) {
        const d = Math.hypot(u.x - x, u.z - z);
        if (d <= r) fn(u, d);
      }
    }
}

// How far `t` is from `u` for shooting: to its edge.
function reach(u, t) {
  return Math.max(0, dist(u, t) - CATALOG[t.type].radius);
}

// Whether `u` can shoot `t` (an enemy of a kind it hits, landed and alive), range aside.
function canHit(u, t) {
  return t.side !== u.side && t.hp > 0 && !t.dropAt && CATALOG[u.type].hits.includes(CATALOG[t.type].kind);
}

function inRange(u, t, extra = 0) {
  const c = CATALOG[u.type];
  const d = reach(u, t);
  return d <= c.range + extra && !(c.minRange && d < c.minRange);
}

// The nearest enemy `u` can shoot within its range (plus `extra`): its current target while that
// still holds, else a fresh look every few tenths of a second.
function acquire(b, u, extra = 0) {
  if (u.target) {
    const t = b.units.get(u.target);
    if (t && canHit(u, t) && inRange(u, t, extra)) return t;
    u.target = null;
  }
  if (b.t < u.searchAt) return null;
  u.searchAt = b.t + 0.3 + (u.id % 7) * 0.02;
  const c = CATALOG[u.type];
  let best = null;
  let bestD = Infinity;
  near(b, u.x, u.z, c.range + extra + RADIUS_MAX, (t) => {
    if (!canHit(u, t) || !inRange(u, t, extra)) return;
    const d = reach(u, t);
    if (d < bestD || (d === bestD && t.id < best.id)) [best, bestD] = [t, d];
  });
  if (best) u.target = best.id;
  return best;
}

// `t` takes damage from `from` (a unit's id). An idle unit that can shoot back goes after whoever
// hit it, as units do.
function hurt(b, t, damage, from = null) {
  if (t.hp <= 0) return;
  const dome = CATALOG[t.type].shield ? null : shieldOver(b, t);
  if (dome) {
    // The dome takes it first; what's left gets through.
    const soak = Math.min(dome.shieldHp, damage);
    dome.shieldHp -= soak;
    damage -= soak;
    if (damage <= 0) return;
  }
  t.hp -= damage;
  if (from) t.lastHit = from;
  const by = from && b.units.get(from);
  if (by && mobile(t) && !t.orders.length && !t.driven && CATALOG[t.type].damage && canHit(t, by)) t.orders = [{ order: 'attack', target: by.id }];
}

// `u` fires at `t` (or, driven, at a spot) if it has reloaded.
function fire(b, u, x, z, t = null) {
  const c = CATALOG[u.type];
  if (u.cd > 0 || !c.damage) return false;
  u.cd = c.reload;
  const damage = c.damage * (u.driven ? DRIVE_BONUS : 1);
  if (mobile(u) && !u.driven) u.heading = Math.atan2(x - u.x, z - u.z);
  if (c.shell) b.shells.push({ x, z, at: b.t + Math.hypot(x - u.x, z - u.z) / c.shell, damage, side: u.side, from: u.id });
  else if (t) hurt(b, t, damage, u.id);
  b.shots.push([u.id, r1(x), r1(z), u.type]);
  return true;
}

// A shell lands: everything of the enemy's on the ground within the splash takes the damage, in
// full where it lands and SPLASH_EDGE of it at the edge.
function land(b, s) {
  const r = CATALOG.artillery.splash;
  near(b, s.x, s.z, r + RADIUS_MAX, (t) => {
    if (t.side === s.side || t.hp <= 0 || CATALOG[t.type].kind === 'air') return;
    const d = Math.max(0, Math.hypot(t.x - s.x, t.z - s.z) - CATALOG[t.type].radius);
    if (d <= r) hurt(b, t, s.damage * (1 - (1 - SPLASH_EDGE) * (d / r)), s.from);
  });
}

// Moves `u` toward (x, z); true once it's within `arrive` of it.
function moveToward(b, u, x, z, dt, arrive = 2) {
  const dx = x - u.x;
  const dz = z - u.z;
  const d = Math.hypot(dx, dz);
  if (d <= arrive) return true;
  const step = Math.min(CATALOG[u.type].speed * dt, d);
  u.x = clamp(u.x + (dx / d) * step, 0, SIZE);
  u.z = clamp(u.z + (dz / d) * step, 0, SIZE);
  u.heading = Math.atan2(dx, dz);
  u.state = 'move';
  return d - step <= arrive;
}

// An engineer's build order: walk to the site, start it (or join the one there), and put mass in.
function build(b, u, o, dt) {
  let site = o.site && b.units.get(o.site);
  if (o.site && (!site || site.hp <= 0 || site.built)) return true;
  const c = CATALOG[o.structure];
  if (Math.hypot(u.x - o.x, u.z - o.z) > CATALOG.engineer.range + c.radius - 1) {
    moveToward(b, u, o.x, o.z, dt, CATALOG.engineer.range + c.radius - 2);
    return false;
  }
  if (!site) {
    const there = blocked(b, o.structure, o.x, o.z);
    if (there && there.type === o.structure && !there.built && there.side === u.side && Math.hypot(there.x - o.x, there.z - o.z) < 4) site = there;
    else if (there) return true; // something else took the spot
    else {
      const p = o.structure === 'extractor' ? massPointAt(b, o.x, o.z, u.side) : null;
      if (o.structure === 'extractor' && !p) return true;
      site = spawn(b, o.structure, u.side, u.owner, o.x, o.z, { built: false });
      if (p) site.point = p.id;
    }
    o.site = site.id;
  }
  u.heading = Math.atan2(site.x - u.x, site.z - u.z);
  u.state = 'build';
  const pay = purse(b, site.owner) || purse(b, u.owner);
  const amount = Math.max(0, Math.min(BUILD_RATE * dt, c.cost - site.paid, affordable(pay, 1, c.energy / c.cost)));
  if (pay) charge(pay, amount, (amount * c.energy) / c.cost);
  site.paid += amount;
  site.hp = Math.min(c.hp, site.hp + (c.hp * 0.9 * amount) / c.cost);
  site.progress = Math.min(1, site.paid / c.cost);
  if (site.paid >= c.cost - 1e-6) {
    site.built = true;
    site.progress = 1;
    site.state = 'idle';
    b.feed.push(`${site.owner || 'The defenders'} built ${c.name === 'AA' ? 'an AA' : /^[AEIOU]/.test(c.name) ? `an ${c.name}` : `a ${c.name}`}`);
    return true;
  }
  return false;
}

// An idle engineer mends the nearest damaged friend within reach.
function repair(b, u, dt) {
  let best = null;
  near(b, u.x, u.z, CATALOG.engineer.range + RADIUS_MAX, (t) => {
    if (t === u || t.side !== u.side || t.hp >= (t.maxHp || CATALOG[t.type].hp) || (isStructure(t) && !t.built)) return;
    if (reach(u, t) <= CATALOG.engineer.range && (!best || t.id < best.id)) best = t;
  });
  if (!best) return;
  best.hp = Math.min(best.maxHp || CATALOG[best.type].hp, best.hp + REPAIR_RATE * dt);
  u.state = 'build';
}

// A factory puts mass into the first thing in its queue and rolls it out when paid for.
// A structure's upgrade to its next tier, paid in full at FACTORY_RATE; true once it's done or
// while there's none (an extractor or generator works on at its old tier meanwhile).
function upgradeStep(b, f, dt) {
  const pay = purse(b, f.owner);
  if (!f.upgrade || !pay) return !f.upgrade;
  const up = CATALOG[f.type].upgrade[f.upgrade.to];
  const share = Math.max(0, Math.min((FACTORY_RATE * dt) / up.cost, 1 - f.upgrade.done, affordable(pay, up.cost, up.energy)));
  charge(pay, share * up.cost, share * up.energy);
  f.upgrade.done += share;
  if (f.upgrade.done >= 1 - 1e-6) {
    f.tier = f.upgrade.to;
    delete f.upgrade;
    b.feed.push(`${f.owner || 'The defenders'}'s ${CATALOG[f.type].name} reached tier ${f.tier}`);
  }
  return false;
}

// A shield dome charges up while its owner has energy, and soaks the damage done to what's under it.
function shieldStep(b, u, dt) {
  const sh = CATALOG[u.type].shield;
  const p = u.owner && b.pilots.get(u.owner);
  if (p && p.energy <= 0) return;
  u.shieldHp = Math.min(sh.hp, (u.shieldHp || 0) + sh.regen * dt);
}

// The friendly shield dome up over `t`, if any.
function shieldOver(b, t) {
  for (const s of b.units.values()) {
    const sh = CATALOG[s.type].shield;
    if (!sh || !s.built || s.side !== t.side || s.shieldHp <= 0 || s.hp <= 0) continue;
    if (Math.hypot(s.x - t.x, s.z - t.z) <= sh.radius) return s;
  }
  return null;
}

// It works at FACTORY_RATE of the full price (so the discount saves mass and energy, not time),
// paying FACTORY_DISCOUNT of it. An upgrade comes first, paid in full.
function factoryStep(b, f, dt) {
  const pay = purse(b, f.owner);
  if (!pay) return;
  if (f.upgrade) return upgradeStep(b, f, dt);
  const job = f.queue[0];
  if (!job) return;
  const c = CATALOG[job.unit];
  const [mass, energy] = [c.cost * FACTORY_DISCOUNT, c.energy * FACTORY_DISCOUNT];
  if (job.done < 1) {
    const share = Math.max(0, Math.min((FACTORY_RATE * dt) / c.cost, 1 - job.done, affordable(pay, mass, energy)));
    charge(pay, share * mass, share * energy);
    job.done += share;
  }
  if (job.done < 1 - 1e-6 || (f.owner && unitCount(b, f.owner, f.side) >= UNIT_CAP) || sideCount(b, f.side) >= SIDE_CAP) return;
  const out = f.side === 'a' ? 1 : -1;
  const n = b.dropCount[f.side]++ % 8;
  spawn(b, job.unit, f.side, f.owner, f.x + (n - 3.5) * 5, f.z + out * (CATALOG.factory.radius + 6));
  job.done = 0;
  if (--job.left <= 0) f.queue.shift();
}

// A driven unit: moves as told, fires at its aim point. A pilot who stops sending loses the throttle.
function driveStep(b, u, dt) {
  const d = u.driven;
  const c = CATALOG[u.type];
  u.state = 'driven';
  if (b.t - d.t > Math.max(1, b.speed) + 1e-6) [d.mx, d.mz, d.fire] = [0, 0, false];
  if (d.mx || d.mz) {
    u.x = clamp(u.x + d.mx * c.speed * dt, 0, SIZE);
    u.z = clamp(u.z + d.mz * c.speed * dt, 0, SIZE);
    u.heading = Math.atan2(d.mx, d.mz);
  }
  if (!d.fire || !c.damage || u.cd > 0) return;
  // The shot goes to the aim point, no further than the unit's range (nor nearer than artillery's least).
  let [x, z] = [d.ax, d.az];
  const far = Math.hypot(x - u.x, z - u.z);
  const want = clamp(far, c.minRange || 0, c.range);
  if (far > 0 && want !== far) [x, z] = [u.x + ((x - u.x) / far) * want, u.z + ((z - u.z) / far) * want];
  let hit = null;
  let bestD = Infinity;
  if (!c.shell)
    near(b, x, z, AIM_RADIUS + RADIUS_MAX, (t) => {
      const e = Math.max(0, Math.hypot(t.x - x, t.z - z) - CATALOG[t.type].radius);
      if (e <= AIM_RADIUS && canHit(u, t) && inRange(u, t, AIM_RADIUS) && (e < bestD || (e === bestD && t.id < hit.id))) [hit, bestD] = [t, e];
    });
  fire(b, u, hit ? hit.x : x, hit ? hit.z : z, hit);
}

// One unit following its orders: move (shooting on the way), amove (stopping to fight anything
// met), attack (chasing its target, or backing off to artillery's least range), build, or idle
// (shooting whatever comes in range).
function unitStep(b, u, dt) {
  const c = CATALOG[u.type];
  u.state = 'idle';
  const o = u.orders[0];
  if (!o) {
    const t = c.damage ? acquire(b, u) : null;
    if (t) {
      u.state = 'fight';
      fire(b, u, t.x, t.z, t);
    } else if (u.type === 'engineer') repair(b, u, dt);
    return;
  }
  if (o.order === 'build') {
    if (build(b, u, o, dt)) u.orders.shift();
    return;
  }
  if (o.order === 'attack') {
    const t = b.units.get(o.target);
    if (!t || t.hp <= 0 || !c.hits.includes(CATALOG[t.type].kind)) return u.orders.shift();
    if (canHit(u, t) && inRange(u, t)) {
      u.state = 'fight';
      fire(b, u, t.x, t.z, t);
    } else if (c.minRange && reach(u, t) < c.minRange) {
      const d = dist(u, t);
      const [nx, nz] = d > 1e-6 ? [(u.x - t.x) / d, (u.z - t.z) / d] : [Math.sin(u.heading), Math.cos(u.heading)];
      const back = c.minRange + CATALOG[t.type].radius + 10;
      moveToward(b, u, t.x + nx * back, t.z + nz * back, dt);
    } else moveToward(b, u, t.x, t.z, dt, Math.max(2, c.range * 0.8 + CATALOG[t.type].radius));
    return;
  }
  if (o.order === 'amove' && c.damage) {
    const t = acquire(b, u, 25);
    if (t) {
      if (inRange(u, t)) {
        u.state = 'fight';
        fire(b, u, t.x, t.z, t);
      } else moveToward(b, u, t.x, t.z, dt, c.range * 0.8 + CATALOG[t.type].radius);
      return;
    }
  }
  if (o.order === 'move' && c.damage) {
    const t = acquire(b, u);
    if (t) fire(b, u, t.x, t.z, t);
  }
  if (moveToward(b, u, o.x, o.z, dt)) u.orders.shift();
}

const moving = (u) => u.state === 'move' || (!!u.driven && !!(u.driven.mx || u.driven.mz));

// Units keep a little apart: land from land and from structures, air from air. A unit on the move
// has the right of way: one standing still steps aside for it.
function separate(b) {
  for (const u of b.units.values()) {
    if (u.dropAt || !mobile(u)) continue;
    const air = CATALOG[u.type].kind === 'air';
    const ru = CATALOG[u.type].radius;
    near(b, u.x, u.z, ru + RADIUS_MAX, (v, d) => {
      if (v === u || v.dropAt || (CATALOG[v.type].kind === 'air') !== air) return;
      const min = ru + CATALOG[v.type].radius;
      if (d >= min) return;
      let [nx, nz] = d > 1e-6 ? [(u.x - v.x) / d, (u.z - v.z) / d] : [Math.cos(u.id), Math.sin(u.id)];
      let push = (min - d) / 2;
      if (isStructure(v)) push = min - d;
      else if (moving(u) && !moving(v)) push = 0;
      else if (moving(v) && !moving(u)) {
        // Aside, not ahead: away from the mover and across its path.
        push = min - d;
        let [px, pz] = [Math.cos(v.heading), -Math.sin(v.heading)];
        if (px * nx + pz * nz < 0) [px, pz] = [-px, -pz];
        const [sx, sz] = [nx + 1.5 * px, nz + 1.5 * pz];
        const sl = Math.hypot(sx, sz) || 1;
        [nx, nz] = [sx / sl, sz / sl];
      }
      u.x = clamp(u.x + nx * push, 0, SIZE);
      u.z = clamp(u.z + nz * push, 0, SIZE);
    });
  }
}

// Removes the dead (reported once, in the next snapshot); the Command Node's fall decides the battle.
// Removes the dead (reported once, in the next snapshot). An ACU goes up in a blast that can kill
// more (buried in the same pass), and puts its commander out. The last Command Node's fall wins the
// battle for the attackers; the last ACU's, for the defenders.
function bury(b) {
  for (let again = true; again; ) {
    again = false;
    for (const u of [...b.units.values()]) {
      if (u.hp > 0) continue;
      b.units.delete(u.id);
      b.dead.push(u.id);
      for (const p of b.pilots.values()) if (p.drive === u.id) p.drive = null;
      if (isStructure(u)) b.feed.push(`${u.name || CATALOG[u.type].name}${u.owner ? ` (${u.owner})` : u.commander ? ` (${u.commander})` : ''} was destroyed`);
      const killer = u.lastHit && b.units.get(u.lastHit);
      if (killer && killer.hp > 0 && killer.vet !== undefined) veteran(b, killer, u);
      if (CATALOG[u.type].acu) {
        again = true;
        acuDown(b, u);
      }
    }
  }
  if (b.result) return;
  if (b.nodes && !aliveNodes(b).length) [b.result, b.how] = ['a', 'node'];
  const attackers = [...b.pilots.values()].filter((p) => p.side === 'a');
  if (!b.result && attackers.length && attackers.every((p) => p.out)) [b.result, b.how] = ['d', 'acus'];
}

// A kill scores the victim's worth toward the killer's next veterancy star.
function veteran(b, k, victim) {
  const c = CATALOG[victim.type];
  k.kills += c.acu ? 10 : victim.type === 'node' ? 5 : isStructure(victim) ? 1 : tierOf(victim.type);
  while (k.vet < VET_STARS.length && k.kills >= VET_STARS[k.vet]) {
    k.vet += 1;
    k.maxHp *= 1.1;
    k.hp = Math.min(k.maxHp, k.hp + k.maxHp * 0.25);
  }
}

// An ACU falls: its blast hurts everything near (friend and foe, less further out) and its
// commander is out of the battle; their units stand where they are.
function acuDown(b, u) {
  const blast = CATALOG[u.type].blast;
  b.shots.push([u.id, r1(u.x), r1(u.z), r1(u.x), r1(u.z), 'blast']);
  near(b, u.x, u.z, blast.radius + RADIUS_MAX, (t) => {
    const d = Math.max(0, Math.hypot(t.x - u.x, t.z - u.z) - CATALOG[t.type].radius);
    if (t !== u && t.hp > 0 && d <= blast.radius) t.hp -= blast.damage * (1 - (0.75 * d) / blast.radius);
  });
  const p = u.owner && b.pilots.get(u.owner);
  if (p) {
    p.out = true;
    p.resign = false;
    release(b, p.name);
    for (const v of b.units.values()) if (v.owner === p.name && mobile(v)) [v.orders, v.target] = [[], null];
  }
  b.feed.push(`${u.owner || 'An'}${u.owner ? "'s" : ''} ACU was destroyed${p ? `: ${p.name} is out` : ''}`);
}

// Advances the battle by `dt` simulated seconds (STEP_S or less at a time).
function step(b, dt) {
  if (b.result) return;
  for (let left = dt; left > 1e-9; left -= STEP_S) tick(b, Math.min(STEP_S, left));
}

function tick(b, dt) {
  b.t += dt;
  // Pilots' economies: energy first (an extractor with no energy to run on stops: `stalled`), then mass.
  const eco = economies(b);
  for (const p of b.pilots.values()) {
    const e = eco.get(`${p.side}|${p.name}`) || NO_ECONOMY;
    const energyCap = ENERGY_CAP + e.energyCap;
    const net = CARRIER_ENERGY + e.power - e.drain;
    p.energy = (p.energy ?? ENERGY_START) + net * dt;
    p.stalled = p.energy <= 0 && net < 0;
    if (p.stalled) p.energy = 0;
    p.energy = Math.min(energyCap, p.energy);
    p.mass = Math.min(MASS_CAP + e.massCap, p.mass + (CARRIER_INCOME + (p.stalled ? 0 : e.mass)) * dt);
  }
  b.ai.mass = Math.min(AI_CAP, b.ai.mass + income(b, '') * dt);
  for (const u of b.units.values()) if (u.dropAt && b.t >= u.dropAt) [u.dropAt, u.state] = [0, 'idle'];
  if (b.t >= b.aiAt) {
    b.aiAt += AI_S;
    think(b);
  }
  buildGrid(b);
  for (const u of b.units.values()) {
    if (u.dropAt || u.hp <= 0) continue;
    u.cd = Math.max(0, u.cd - dt);
    if (isStructure(u)) {
      u.state = u.built ? 'idle' : 'build';
      if (!u.built) continue;
      if (u.upgrade && !makes(u)) upgradeStep(b, u, dt);
      if (makes(u)) factoryStep(b, u, dt);
      else if (CATALOG[u.type].shield) shieldStep(b, u, dt);
      else if (CATALOG[u.type].damage) {
        const t = acquire(b, u);
        if (t) fire(b, u, t.x, t.z, t);
      }
    } else {
      if (u.vet) u.hp = Math.min(u.maxHp, u.hp + VET_REGEN * u.vet * dt);
      if (u.driven) driveStep(b, u, dt);
      else unitStep(b, u, dt);
    }
  }
  buildGrid(b);
  for (const s of b.shells.filter((s) => b.t >= s.at)) land(b, s);
  b.shells = b.shells.filter((s) => b.t < s.at);
  separate(b);
  bury(b);
  // The attackers have nothing left on the field and nobody to send more; or nobody commands
  // what they left there.
  const pilots = present(b, 'a').length;
  const any = pilots || [...b.units.values()].some((u) => u.side === 'a');
  if (any) b.emptySince = null;
  else b.emptySince ??= b.t;
  if (pilots) b.leaderless = null;
  else b.leaderless ??= b.t;
  if (!b.result && ((b.emptySince !== null && b.t - b.emptySince >= ABANDON_S) || (b.leaderless !== null && b.t - b.leaderless >= LEADERLESS_S))) [b.result, b.how] = ['d', 'abandoned'];
}

// The defender holds once the battle's time is up.
function check(b, now) {
  if (!b.result && now >= b.endsAt) [b.result, b.how] = ['d', 'time'];
  return b.result;
}

// --- The defender AI ------------------------------------------------------------------------

// Every AI_S: engineers (up to AI_ENGINEERS) take the free mass points on its half of the map; a
// defence group (AI_DEFENCE of the army by value) patrols the base; the rest gathers and, once worth
// AI_WAVE (or AI_WAVE_SHARE of what it may field, if less) and from AI_FIRST_WAVE_S on, attacks the
// strongest knot of attackers (or their landing zone), coming home when it has nothing left to fight. Mass goes on a mix of drops, up to an army worth AI_ARMY (times k) plus
// AI_MATCH of the attackers' army; what it loses it buys again. The same state always makes the
// same choices.
function think(b) {
  const ai = b.ai;
  const mine = [...b.units.values()].filter((u) => u.side === 'd' && u.owner === '' && mobile(u));
  const engineers = mine.filter((u) => u.type === 'engineer');
  const army = mine.filter((u) => u.type !== 'engineer');
  const node = aiNode(b);

  // Engineers: one more if there's room, and idle ones off to the nearest free mass point.
  if (engineers.length < AI_ENGINEERS && ai.mass >= CATALOG.engineer.cost && mine.length < AI_UNITS) {
    ai.mass -= CATALOG.engineer.cost;
    dropUnits(b, 'd', '', 'engineer', 1);
  }
  const claimed = new Set(engineers.flatMap((e) => e.orders.filter((o) => o.order === 'build').map((o) => `${o.x},${o.z}`)));
  for (const e of engineers) {
    if (e.dropAt || e.orders.length) continue;
    const ours = (p) => Math.hypot(p.x - node.x, p.z - node.z) < Math.hypot(p.x - b.lz.x, p.z - b.lz.z); // its own half of the map
    const free = b.massPoints.filter((p) => ours(p) && !claimed.has(`${p.x},${p.z}`) && massPointAt(b, p.x, p.z, 'd') && !blocked(b, 'extractor', p.x, p.z));
    const p = free.sort((m, n) => Math.hypot(m.x - e.x, m.z - e.z) - Math.hypot(n.x - e.x, n.z - e.z) || m.id - n.id)[0];
    if (!p) continue;
    claimed.add(`${p.x},${p.z}`);
    e.orders = [{ order: 'build', structure: 'extractor', x: p.x, z: p.z }];
  }

  // New units join the defence group until it holds its share, the rest the attack group.
  const value = (us) => us.reduce((a, u) => a + CATALOG[u.type].cost, 0);
  const total = value(army);
  let defence = value(army.filter((u) => u.role === 'defence'));
  for (const u of army) {
    if (u.role) continue;
    u.role = defence < AI_DEFENCE * total ? 'defence' : 'attack';
    if (u.role === 'defence') defence += CATALOG[u.type].cost;
  }
  // The defence group patrols round the Command Node and the outposts.
  const posts = [...b.units.values()].filter((u) => u.side === 'd' && u.type === 'outpost');
  const patrol = [0, 1, 2, 3, 4, 5].map((i) => ({ x: node.x + 110 * Math.cos((i * Math.PI) / 3), z: node.z + 110 * Math.sin((i * Math.PI) / 3) })).concat(posts.map((p) => ({ x: p.x, z: p.z - 30 })));
  for (const u of army) {
    if (u.role !== 'defence' || u.dropAt || u.orders.length) continue;
    const p = patrol[ai.patrol++ % patrol.length];
    const jitter = () => (random(b.rng) - 0.5) * 30;
    u.orders = [{ order: 'amove', x: clamp(p.x + jitter(), 0, SIZE), z: clamp(p.z + jitter(), 0, SIZE) }];
  }
  // What its army may be worth: more for a richer AI, and more against a bigger attack.
  const attackers = value([...b.units.values()].filter((u) => u.side === 'a' && mobile(u)));
  const allowed = ai.k * AI_ARMY + AI_MATCH * attackers;
  // A wave that has nothing left to fight where it went comes home to gather for the next one
  // (rather than sit on the attackers' landing zone).
  for (const u of army) {
    if (u.role !== 'attack' || u.dropAt || u.orders.length || u.target || Math.hypot(u.x - node.x, u.z - node.z) < AI_HOME) continue;
    const jitter = () => (random(b.rng) - 0.5) * 40;
    u.orders = [{ order: 'amove', x: clamp(node.x + jitter(), 0, SIZE), z: clamp(node.z + (b.lz.z < node.z ? -1 : 1) * 150 + jitter(), 0, SIZE) }];
  }
  // The attack group goes once it's worth enough.
  // (Units already standing where the wave would go hold there.)
  const at = strongest(b);
  const ready = army.filter((u) => u.role === 'attack' && !u.dropAt && !u.orders.length && Math.hypot(u.x - at.x, u.z - at.z) > 150);
  if (b.t >= AI_FIRST_WAVE_S && ready.length && value(ready) >= Math.min(AI_WAVE, AI_WAVE_SHARE * allowed)) {
    const spots = formation(ready, at.x, at.z);
    ready.forEach((u, i) => (u.orders = [{ order: 'amove', x: spots[i][0], z: spots[i][1] }]));
    ai.waves++;
    b.feed.push(`Enemy wave incoming: ${ready.length} units`);
  }

  // Spend: drops from the mix, keeping enough back for an engineer, while its army is worth less
  // than it may field.
  const reserve = engineers.length < AI_ENGINEERS ? CATALOG.engineer.cost : 0;
  let worth = total;
  for (let i = 0, units = mine.length; i < 6 && units < AI_UNITS && worth < allowed; i++) {
    const type = AI_MIX[ai.mix % AI_MIX.length];
    const cost = CATALOG[type].cost;
    const n = Math.min(2, Math.floor((ai.mass - reserve) / cost), AI_UNITS - units);
    if (n < 1) break;
    ai.mass -= cost * n;
    ai.mix++;
    units += n;
    worth += cost * n;
    dropUnits(b, 'd', '', type, n);
  }
}

// Where the attackers are thickest (by unit value, in 200 m squares), or their landing zone.
function strongest(b) {
  const cells = new Map();
  for (const u of b.units.values()) {
    if (u.side !== 'a' || u.dropAt) continue;
    const k = Math.floor(u.x / 200) * 100 + Math.floor(u.z / 200);
    const c = cells.get(k) || { v: 0, x: 0, z: 0, n: 0, k };
    c.v += CATALOG[u.type].cost || 100;
    c.x += u.x;
    c.z += u.z;
    c.n++;
    cells.set(k, c);
  }
  const best = [...cells.values()].sort((p, q) => q.v - p.v || p.k - q.k)[0];
  return best ? { x: best.x / best.n, z: best.z / best.n } : { x: b.lz.x, z: b.lz.z };
}

// --- What the pilots see ----------------------------------------------------------------------

// What every pilot's snapshot shares; takes what happened since the last one.
function frame(b) {
  const units = [];
  const build = [];
  for (const u of b.units.values()) {
    units.push([u.id, u.type, u.side, u.owner, r1(u.x), r1(u.z), r1(Math.max(0, u.hp)), r1(u.heading), u.state, u.vet || 0, u.shieldHp !== undefined ? Math.round(u.shieldHp) : null, u.tier || 1]);
    if (isStructure(u) && !u.built) build.push([u.id, Math.round(u.progress * 100) / 100]);
  }
  const out = {
    battle: b.id,
    t: r1(b.t),
    units,
    dead: b.dead,
    shots: b.shots,
    build,
    pilots: present(b).map((p) => ({ name: p.name, side: p.side, out: !!p.out, resign: !!p.resign })),
    endsAt: b.endsAt,
    feed: b.feed,
  };
  b.dead = [];
  b.shots = [];
  b.feed = [];
  return out;
}

// One pilot's battle_state from a frame: theirs is the mass (and income).
function stateFor(b, f, name) {
  const p = b.pilots.get(name);
  const factories = [];
  for (const u of b.units.values())
    if (upgradable(u) && u.owner === name && u.built) factories.push([u.id, u.tier || 1, u.upgrade ? [u.upgrade.to, Math.round(u.upgrade.done * 100) / 100] : null, (u.queue || []).reduce((a, j) => a + j.left, 0)]);
  const e = (p && economies(b).get(`${p.side}|${name}`)) || NO_ECONOMY;
  return { type: 'battle_state', ...f, mass: r1(p?.mass ?? 0), income: r1(income(b, name)), energy: r1(p?.energy ?? 0), energyIncome: r1(energyIncome(b, name)), massCap: MASS_CAP + e.massCap, energyCap: ENERGY_CAP + e.energyCap, stalled: !!p?.stalled, factories };
}

// battle_joined, for a pilot on `side`.
function joined(b, name) {
  const p = b.pilots.get(name);
  const names = {};
  for (const u of b.units.values()) if (u.name) names[u.id] = u.name;
  return {
    type: 'battle_joined',
    battle: b.id,
    planet: b.planet,
    sector: b.sector,
    sectorName: b.sectorName,
    planetName: b.planetName,
    size: SIZE,
    seed: b.seed,
    attacker: b.attacker,
    defender: b.defender,
    side: p.side,
    lz: p.side === 'a' ? b.lz : b.enemyLz,
    enemyLz: p.side === 'a' ? b.enemyLz : b.lz,
    massPoints: b.massPoints,
    units: CATALOG,
    economy: { energyCap: ENERGY_CAP, massCap: MASS_CAP, factoryDiscount: FACTORY_DISCOUNT, droppable: DROPPABLE },
    endsAt: b.endsAt,
    mass: r1(p.mass),
    energy: r1(p.energy ?? 0),
    names,
  };
}

// --- The server's battles -------------------------------------------------------------------

// How a battle was decided, for the end banner.
const HOW = { acus: 'every attacking ACU was destroyed', resign: 'a side resigned', abandoned: 'the attackers abandoned it', time: 'the clock ran out', node: 'every Command Node fell' };

function sideName(f) {
  return f ? F.the(f) : 'the militia';
}

// The battles a server runs. `galaxy()` is its galaxy; `send(me, msg)` sends one connection a
// message; `changed()` is called when the galaxy changed (a sector taken, the war log, who
// fights where); `speed` is BATTLE_SPEED. A pilot's connection record (`me`) notes their battle.
// Campaign matches (`b.campaign`, started by matchmaking in campaign.js) are fought on a notional
// sector: the winner scores campaign points through `onCampaignEnd(b, winner, vsAi)` instead of
// taking the sector, and the war rules (locks, shares) don't call them off.
function createBattles({ galaxy, now = Date.now, speed = 1, send, changed, onCampaignEnd = null }) {
  const battles = new Map(); // id -> battle
  const conns = new Map(); // battle id -> Map(name -> connection)
  let nextId = 1;
  let ticks = 0;
  const timers = new Set();

  function running(planetId, sectorId) {
    for (const b of battles.values()) if (!b.result && b.planet === planetId && b.sector === sectorId) return b;
    return null;
  }

  // battle_start: an attack on a sector, with every rule of W.capture, by a pilot aboard a
  // carrier over that planet (`where.over`). If one already runs there, the pilot joins it. A pilot
  // leads one attack at a time: starting another gives up the last one unless others fight it.
  function start(me, faction, planetId, sectorId, where) {
    const g = galaxy();
    if (!faction) return fail('choose a faction first');
    const wp = W.planet(g, String(planetId));
    if (!wp) return fail('no such planet');
    const sector = wp.sectors.find((s) => s.id === sectorId);
    if (!sector) return fail('no such sector');
    const already = running(wp.id, sector.id);
    if (already) return join(me, faction, already.id, where);
    const can = W.canAttack(g, faction, wp.id, now());
    if (!can.ok) return can;
    if (sector.owner === faction) return fail(`${F.the(faction)} already holds ${sector.name}`);
    const held = new Set(wp.sectors.filter((s) => s.owner === faction).map((s) => s.id));
    if (held.size && !sector.links.some((id) => held.has(id))) return fail(`${sector.name} isn't next to a sector you hold`);
    if (where.over !== wp.id) return fail(`you need to be aboard a carrier over ${wp.name}`);
    const defender = sector.owner;
    const outposts = defender ? g.system.planets.filter((p) => p.kind === 'satellite' && p.sector === sector.id && p.faction === defender) : [];
    if (me.battle) leave(me);
    for (const old of battles.values())
      if (!old.result && old.leader === me.name && !present(old, 'a').length) end(old, 'abandoned');
    const b = newBattle({ id: `b${nextId++}`, wp, sector, attacker: faction, defender, outposts, k: aiRate(g, faction, defender), now: now(), speed });
    b.leader = me.name;
    battles.set(b.id, b);
    conns.set(b.id, new Map());
    W.warLog(g, `${F.FACTIONS[faction].name} attacked ${sector.name}${defender ? `, held by ${F.the(defender)}` : ''}`, now());
    return enlist(me, b, 'a', faction);
  }

  // battle_join: into a running battle, on the side of the pilot's faction. Attackers come from a
  // carrier over the planet; defenders from one, or from the planet's station.
  function join(me, faction, battleId, where) {
    const b = battles.get(String(battleId));
    if (!b || b.result) return fail('no such battle');
    const side = faction && faction === b.attacker ? 'a' : faction && faction === b.defender ? 'd' : null;
    if (!side) return fail(`a battle between ${sideName(b.attacker)} and ${sideName(b.defender)} is already on there`);
    if (side === 'a' && !b.campaign) {
      const can = W.canAttack(galaxy(), faction, b.planet, now());
      if (!can.ok) return can;
    }
    const wp = W.planet(galaxy(), b.planet);
    if (where.over !== b.planet && !(side === 'd' && where.station === b.planet))
      return fail(side === 'a' ? `you need to be aboard a carrier over ${wp.name}` : `you need to be at ${wp.name}'s station or aboard a carrier over it`);
    if (!b.pilots.get(me.name)?.present && present(b).length >= PILOTS_MAX) return fail(`that battle is full: ${PILOTS_MAX} pilots`);
    return enlist(me, b, side, faction);
  }

  // (Joining again a battle the pilot is already in only says battle_joined again.)
  function enlist(me, b, side, faction) {
    if (me.battle && me.battle !== b.id) leave(me);
    const again = me.battle === b.id && conns.get(b.id).get(me.name) === me && b.pilots.get(me.name)?.present && b.pilots.get(me.name).side === side;
    addPilot(b, me.name, side, faction);
    conns.get(b.id).set(me.name, me);
    me.battle = b.id;
    send(me, joined(b, me.name));
    if (!again) changed();
    return { ok: true, battle: b.id, side };
  }

  // A pilot leaves their battle (battle_leave, or their app went away). Their units stay.
  function leave(me) {
    const b = me.battle && battles.get(me.battle);
    me.battle = null;
    if (!b) return { ok: true };
    if (conns.get(b.id)?.get(me.name) === me) {
      conns.get(b.id).delete(me.name);
      removePilot(b, me.name);
      if (!b.result) changed();
    }
    return { ok: true };
  }

  // Everything else a pilot says in a battle. Orders are rate-limited; anything for another battle,
  // or after the battle is decided, is dropped.
  function handle(me, msg) {
    if (msg.type === 'battle_leave') return leave(me);
    const b = me.battle && battles.get(me.battle);
    if (!b || b.result || String(msg.battle) !== b.id) return { ok: true, quiet: true };
    const t = Date.now();
    if (msg.type === 'battle_drive') {
      if (t - (me.driveWindow || 0) >= 1000) [me.driveWindow, me.driveCount] = [t, 0];
      if (++me.driveCount > DRIVES_PER_S) return { ok: true, quiet: true };
      return drive(b, me.name, msg);
    }
    if (t - (me.orderWindow || 0) >= 1000) [me.orderWindow, me.orderCount] = [t, 0];
    if (++me.orderCount > ORDERS_PER_S) return { ok: true, quiet: true };
    switch (msg.type) {
      case 'battle_order':
        return order(b, me.name, msg);
      case 'battle_drop':
        return drop(b, me.name, msg.unit, msg.count ?? 1);
      case 'battle_produce':
        return produce(b, me.name, msg.factory, msg.unit, msg.count ?? 1);
      case 'battle_upgrade':
        return upgradeFactory(b, me.name, msg.factory);
      case 'battle_resign':
        return resign(b, me.name, msg.yes !== false);
      case 'battle_possess':
        return possess(b, me.name, msg.unit);
      case 'battle_release':
        return release(b, me.name);
      default:
        return fail(`unknown message ${msg.type}`);
    }
  }

  // The battle is decided: the sector changes hands if the attackers won (a campaign match scores
  // for its winner instead), everyone hears, and the battle is forgotten END_KEEP_MS later.
  function finish(b) {
    const g = galaxy();
    let text;
    if (b.campaign) {
      const winner = b.result === 'a' ? b.attacker : b.defender;
      const loser = b.result === 'a' ? 'd' : 'a';
      const vsAi = ![...b.pilots.values()].some((p) => p.side === loser);
      const pts = winner && onCampaignEnd ? onCampaignEnd(b, winner, vsAi) : 0;
      text = winner
        ? `${F.FACTIONS[winner].name} won the match${HOW[b.how] ? ` (${HOW[b.how]})` : ''}: +${pts} campaign points on ${b.planetName}`
        : `The militia held: no campaign points`;
      W.warLog(g, `${winner ? F.FACTIONS[winner].name : 'The militia'} won a Sector Battle on ${b.planetName}${pts ? ` (+${pts})` : ''}`, now());
    } else if (b.result === 'a') {
      const r = W.capture(g, b.planet, b.sector, b.attacker, now());
      text = r.ok ? `Sector taken: ${b.sectorName} falls to ${F.the(b.attacker)}` : `The Command Node fell, but ${b.sectorName} can't be taken: ${r.reason}`;
    } else if (b.how === 'void') {
      text = `Attack called off: ${b.reason}`;
      W.warLog(g, `${F.FACTIONS[b.attacker].name}'s attack on ${b.sectorName} was called off`, now());
    } else {
      text =
        b.how === 'abandoned'
          ? `Attack failed: the attackers abandoned ${b.sectorName}`
          : `Attack failed: ${sideName(b.defender)} held ${b.sectorName}${HOW[b.how] ? ` (${HOW[b.how]})` : ''}`;
      W.warLog(g, `${F.FACTIONS[b.attacker].name}'s attack on ${b.sectorName} failed`, now());
    }
    const winner = b.result === 'a' ? b.attacker : b.defender;
    const f = frame(b);
    for (const [name, c] of conns.get(b.id)) {
      send(c, stateFor(b, f, name));
      send(c, { type: 'battle_end', battle: b.id, winner, side: b.result, text });
    }
    changed();
    const timer = setTimeout(() => {
      timers.delete(timer);
      battles.delete(b.id);
      for (const c of conns.get(b.id)?.values() || []) if (c.battle === b.id) c.battle = null;
      conns.delete(b.id);
    }, END_KEEP_MS);
    timers.add(timer);
  }

  // Decides a battle for the defender now ('abandoned', or 'void' with the reason) and ends it.
  function end(b, how, reason = null) {
    [b.result, b.how, b.reason] = ['d', how, reason];
    finish(b);
  }

  // Every TICK_MS: each battle runs TICK_MS of its time (times BATTLE_SPEED), and every
  // SNAPSHOT_MS its pilots hear how it stands.
  function tickAll() {
    ticks++;
    const snap = ticks % Math.round(SNAPSHOT_MS / TICK_MS) === 0;
    const recheck = ticks % Math.round(RECHECK_MS / TICK_MS) === 0;
    for (const b of battles.values()) {
      if (b.result) continue;
      // The planet locked (another sector's battle took it) or the attackers lost their share:
      // this attack can't take anything any more.
      const can = recheck && !b.campaign ? W.canAttack(galaxy(), b.attacker, b.planet, now()) : { ok: true };
      if (!can.ok) {
        end(b, 'void', can.reason);
        continue;
      }
      step(b, (TICK_MS / 1000) * speed);
      if (check(b, now())) {
        finish(b);
        continue;
      }
      if (!snap) continue;
      const f = frame(b);
      for (const [name, c] of conns.get(b.id)) send(c, stateFor(b, f, name));
    }
  }
  const ticker = setInterval(TM.timed('sector', tickAll), TICK_MS);

  // The running battles, as everyone may see them in the galaxy state.
  function list() {
    return [...battles.values()]
      .filter((b) => !b.result)
      .map((b) => ({ id: b.id, planet: b.planet, sector: b.sector, sectorName: b.sectorName, attacker: b.attacker, defender: b.defender, pilots: present(b).map((p) => ({ name: p.name, side: p.side })), endsAt: b.endsAt, campaign: b.campaign || undefined }));
  }

  // --- Campaign matches (campaign.js) ---

  // A new match on planet `wp` between `attacker` and `defender` (null: the militia), on one of its
  // sectors' maps in turn. Matchmaking puts the pilots in.
  function startCampaign(wp, attacker, defender) {
    const n = nextId++;
    const sector = wp.sectors[n % wp.sectors.length];
    const b = newBattle({ id: `b${n}`, wp, sector, attacker, defender, k: aiRate(galaxy(), attacker, defender), now: now(), speed });
    b.campaign = true;
    b.sectorName = `${wp.name} match ${n}`;
    battles.set(b.id, b);
    conns.set(b.id, new Map());
    return b;
  }

  // A pilot into a campaign match on `side`. The planet's holder starts with the planet's bonus
  // (a mining world's extra mass).
  function enlistCampaign(me, b, side, faction) {
    const first = !b.pilots.has(me.name);
    const r = enlist(me, b, side, faction);
    const c = galaxy().war.campaigns?.[b.planet];
    const bonus = c && CAMPAIGN_BONUS[c.bonus];
    if (first && bonus?.mass && faction === W.planet(galaxy(), b.planet)?.owner) b.pilots.get(me.name).mass *= bonus.mass;
    return r;
  }

  function campaignMatches(planetId) {
    return [...battles.values()].filter((b) => b.campaign && !b.result && b.planet === planetId);
  }

  // Whether a side of a match has room for another commander.
  function room(b, side) {
    return present(b, side).length < CAMPAIGN_SIDE && present(b).length < PILOTS_MAX;
  }

  function close() {
    clearInterval(ticker);
    for (const t of timers) clearTimeout(t);
  }

  return { battles, start, join, leave, handle, list, tick: tickAll, close, startCampaign, enlistCampaign, campaignMatches, room };
}

module.exports = {
  SIZE,
  PILOTS_MAX,
  TICK_MS,
  SNAPSHOT_MS,
  BATTLE_S,
  ABANDON_S,
  END_KEEP_MS,
  AI_S,
  DROP_S,
  LZ_R,
  MASS_START,
  MASS_CAP,
  ENERGY_START,
  ENERGY_CAP,
  CARRIER_ENERGY,
  GENERATOR_POWER,
  FACTORY_DISCOUNT,
  FACTORY_UPGRADE,
  EXTRACTOR_MASS,
  GENERATOR_POWER_T,
  EXTRACTOR_DRAIN,
  VET_STARS,
  DROPPABLE,
  UNIT_CAP,
  BUILD_RATE,
  FACTORY_RATE,
  DRIVE_BONUS,
  AI_START,
  AI_WAVE,
  CATALOG,
  random,
  seedFor,
  layout,
  newBattle,
  aiRate,
  spawn,
  addPilot,
  removePilot,
  income,
  energyIncome,
  resign,
  aliveNodes,
  dropUnits,
  RESIGN_SHARE,
  drop,
  produce,
  upgradeFactory,
  order,
  possess,
  drive,
  release,
  step,
  check,
  think,
  frame,
  stateFor,
  joined,
  createBattles,
};
