// Raids: Builders' facilities, and the Explorers who break into them.
// Pure state + functions, like galaxy.js: every rule takes `now` (ms) so tests can drive time.
//
// The server owns everything a raider could cheat with: the facility layout, what is in each
// container (sent only as the raider searches it), the inventory grids, Heat, the run timer and
// whether an extraction was allowed. The Explorer app simulates walking and shooting and reports
// what happened (noise, death, standing in an extract zone). Moving combat onto a dedicated
// game server is the spec's milestone 2; until then those reports are trusted.

// --- Items -------------------------------------------------------------------------------

// size: [cols, rows] in grid cells. secure: allowed in the Secure Case.
const ITEMS = {
  scrap: { name: 'Scrap', cat: 'salvage', size: [1, 1], stack: 10, value: 8, rarity: 'common' },
  circuit: { name: 'Circuit board', cat: 'salvage', size: [1, 2], stack: 1, value: 45, rarity: 'common' },
  alloy: { name: 'Alloy plate', cat: 'material', size: [1, 1], stack: 5, value: 40, rarity: 'common' },
  isotope: { name: 'Isotope cell', cat: 'material', size: [1, 1], stack: 3, value: 140, rarity: 'uncommon' },
  exotic: { name: 'Exotic matter', cat: 'material', size: [1, 1], stack: 1, value: 900, rarity: 'epic' },
  wafer: { name: 'Crypto-wafer', cat: 'valuable', size: [1, 1], stack: 3, value: 220, rarity: 'uncommon' },
  art: { name: 'Corporate art', cat: 'valuable', size: [2, 2], stack: 1, value: 700, rarity: 'rare' },
  shard: { name: 'Data shard', cat: 'intel', size: [1, 1], stack: 1, value: 300, rarity: 'uncommon' },
  dossier: { name: 'Security dossier', cat: 'intel', size: [1, 2], stack: 1, value: 650, rarity: 'rare' },
  drive: { name: 'Design drive', cat: 'plan', size: [1, 1], stack: 1, value: 1100, rarity: 'rare' },
  blueprint: { name: 'Blueprint case', cat: 'plan', size: [2, 3], stack: 1, value: 2600, rarity: 'epic', secure: false },
  keycard: { name: 'Access keycard', cat: 'access', size: [1, 1], stack: 1, value: 150, rarity: 'uncommon' },
  // War supplies from the outposts. Shipped home they go in stock like materials; Builders sell
  // them at the Carrier Dock, fill pilots' contracts with them, or donate them to the war.
  fuel: { name: 'Fuel cell', cat: 'supply', size: [1, 1], stack: 10, value: 12, rarity: 'common' },
  slugs: { name: 'Slug crate', cat: 'supply', size: [1, 1], stack: 5, value: 20, rarity: 'common' },
  shells: { name: 'Shell crate', cat: 'supply', size: [1, 2], stack: 2, value: 45, rarity: 'common' },
  missile: { name: 'Missile', cat: 'supply', size: [1, 2], stack: 2, value: 90, rarity: 'uncommon' },
  torpedo: { name: 'Torpedo', cat: 'supply', size: [1, 3], stack: 1, value: 160, rarity: 'uncommon' },
  warhead: { name: 'Strategic warhead', cat: 'supply', size: [2, 2], stack: 1, value: 1500, rarity: 'epic' },
  weapon: { name: 'Weapon system', cat: 'supply', size: [2, 2], stack: 1, value: 180, rarity: 'uncommon' },
  sensor: { name: 'Sensor module', cat: 'supply', size: [1, 1], stack: 2, value: 120, rarity: 'uncommon' },
  drone_frame: { name: 'Drone chassis', cat: 'supply', size: [2, 2], stack: 1, value: 260, rarity: 'rare' },
  lander_frame: { name: 'Lander chassis', cat: 'supply', size: [2, 3], stack: 1, value: 320, rarity: 'rare' },
  hauler: { name: 'Hauler hull', cat: 'supply', size: [3, 3], stack: 1, value: 600, rarity: 'rare' },
  // Healing goes in the pouch, not the backpack. pouch: the most it holds, how long one takes to
  // use, and what it restores (100 is a full bar).
  syringe: { name: 'Syringe', cat: 'medical', size: [1, 1], stack: 4, value: 30, rarity: 'common', pouch: { cap: 4, seconds: 5, health: 25 } },
  medkit: { name: 'Med kit', cat: 'medical', size: [1, 1], stack: 2, value: 90, rarity: 'uncommon', pouch: { cap: 2, seconds: 8, health: 100 } },
  cell: { name: 'Shield cell', cat: 'medical', size: [1, 1], stack: 4, value: 30, rarity: 'common', pouch: { cap: 4, seconds: 3, armor: 25 } },
  battery: { name: 'Shield battery', cat: 'medical', size: [1, 1], stack: 2, value: 90, rarity: 'uncommon', pouch: { cap: 2, seconds: 5, armor: 100 } },
  // Armour vests: worn, not carried, and only for the raid. vest: the armour it holds.
  vest50: { name: 'Armour vest', cat: 'armor', size: [2, 2], stack: 1, value: 0, rarity: 'common', vest: 50 },
  vest75: { name: 'Heavy vest', cat: 'armor', size: [2, 2], stack: 1, value: 0, rarity: 'rare', vest: 75 },
  vest100: { name: 'Assault vest', cat: 'armor', size: [2, 2], stack: 1, value: 0, rarity: 'epic', vest: 100 },
};

// What a raider brings when their pouch is empty (a new raider, or after losing it).
const STARTER_POUCH = { syringe: 2, medkit: 1, cell: 2, battery: 1 };
const STARTER_VEST = 'vest50';
const LAUNCHER_ROUNDS = 7; // grenades for the whole raid
const LAUNCHER_GAP_MS = 1000;
const GRENADE_HEAT = 4;

// Rarer items get more weight at higher security tiers (tier 1 = x1).
const RARITY_BOOST = { common: 0, uncommon: 0.25, rare: 0.6, epic: 1.0, legendary: 1.5 };

// --- Facilities --------------------------------------------------------------------------

// What each facility makes into its vault, every `every` galaxy ticks (5 s), up to `cap`.
// Every facility is an outpost (sites.js); `bias` doubles the odds of its kind of loot in a raid.
// The first three keep their old keys (refinery, lab, spire) so saves still load.
const FACILITIES = {
  refinery: {
    name: 'Extractor',
    bias: 'material',
    makes: [
      { item: 'alloy', every: 1, cap: 40 },
      { item: 'isotope', every: 6, cap: 10 },
      { item: 'exotic', every: 60, cap: 2 },
    ],
  },
  lab: {
    name: 'Armoury',
    bias: 'plan',
    makes: [
      { item: 'weapon', every: 6, cap: 8 },
      { item: 'drive', every: 12, cap: 4 },
      { item: 'blueprint', every: 36, cap: 2 },
    ],
  },
  spire: {
    name: 'Sensor Works',
    bias: 'intel',
    makes: [
      { item: 'sensor', every: 8, cap: 8 },
      { item: 'shard', every: 6, cap: 10 },
      { item: 'dossier', every: 24, cap: 4 },
    ],
  },
  fuel: { name: 'Fuel Depot', bias: 'supply', makes: [{ item: 'fuel', every: 1, cap: 60 }] },
  munitions: {
    name: 'Light Munitions Works',
    bias: 'supply',
    makes: [
      { item: 'slugs', every: 1, cap: 50 },
      { item: 'shells', every: 3, cap: 20 },
    ],
  },
  ordnance: {
    name: 'Heavy Munitions Works',
    bias: 'supply',
    makes: [
      { item: 'missile', every: 6, cap: 12 },
      { item: 'torpedo', every: 12, cap: 6 },
      { item: 'warhead', every: 60, cap: 1 },
    ],
  },
  drones: { name: 'Drone Yard', bias: 'supply', makes: [{ item: 'drone_frame', every: 12, cap: 6 }] },
  landers: { name: 'Lander Yard', bias: 'supply', makes: [{ item: 'lander_frame', every: 15, cap: 5 }] },
  haulers: { name: 'Hauler Yard', bias: 'supply', makes: [{ item: 'hauler', every: 30, cap: 3 }] },
};

// Security tiers the Builder buys. Tier sets guards, turrets, loot rarity and the run timer.
const SECURITY = {
  1: { guards: 3, turrets: 0, grid: [3, 3], minutes: 12, cost: null },
  2: { guards: 5, turrets: 1, grid: [4, 3], minutes: 16, cost: { alloy: 15, drive: 1, credits: 200 } },
  3: { guards: 7, turrets: 2, grid: [4, 4], minutes: 20, cost: { alloy: 30, isotope: 4, blueprint: 1, credits: 500 } },
};

const SHIP_COOLDOWN_MS = 60_000; // a freighter can take a facility's vault to HQ once a minute
const RAID_COOLDOWN_MS = 5 * 60_000; // a facility recovers this long after a raid ends
const VAULT_EXPOSED = 0.6; // share of each vault stack a raid can reach; the rest is in deep storage
const ALARM_COST = 50; // credits for the Builder to sound the alarm remotely
const ALARM_HEAT = 25;
const ALARM_COOLDOWN_MS = 60_000;

// --- Raid rules (starting values from the spec, scaled to a 9-16 room facility) ----------

const ROOM = 14; // metres per room
const HEAT_LEVELS = [
  { name: 'Quiet', from: 0 },
  { name: 'Suspicious', from: 20 },
  { name: 'Alerted', from: 40 },
  { name: 'Lockdown', from: 60 },
  { name: 'Purge', from: 80 },
];
// Heat a reported event adds, and the fewest ms between two of the same kind that count.
const HEAT_EVENTS = {
  gunshot: { heat: 3, gap: 1_000 },
  spotted: { heat: 10, gap: 10_000 },
  body: { heat: 8, gap: 5_000 },
  failed_hack: { heat: 6, gap: 5_000 },
};
const HEAT_PER_30S = 1;
const DRILL_SECONDS = 30;
const DRILL_HEAT_PER_5S = 2;
// The only way out is the ship the raider landed in.
const EXTRACTS = { ship: { name: 'Your ship', countdown: 3 } };
const BAIL_WINDOW_MS = 120_000;
const BACKPACK = [6, 4];
const SECURE_CASE = [2, 2];
const CONTAINER_GRIDS = { locker: [3, 3], crate: [4, 3], desk: [3, 2], rack: [3, 3], vault: [5, 4], medcab: [3, 2] };
const SEARCH_MS = { common: 400, uncommon: 600, rare: 900, epic: 1200, legendary: 1500 };
const FENCE_RATE = 0.5;

// Loot tables per container. [item, weight, qtyMin, qtyMax]
const TABLES = {
  locker: { rolls: [1, 3], none: 2, entries: [['scrap', 6, 1, 6], ['syringe', 1.5, 1, 2], ['cell', 1.5, 1, 2], ['circuit', 3, 1, 1], ['wafer', 1, 1, 1]] },
  crate: { rolls: [2, 4], none: 1, entries: [['scrap', 5, 2, 10], ['alloy', 4, 1, 4], ['circuit', 3, 1, 1], ['isotope', 1, 1, 2], ['medkit', 0.5, 1, 1], ['battery', 0.5, 1, 1], ['fuel', 1, 2, 8], ['slugs', 0.8, 1, 4], ['shells', 0.4, 1, 2]] },
  desk: { rolls: [1, 3], none: 2, entries: [['wafer', 3, 1, 2], ['shard', 2, 1, 1], ['circuit', 2, 1, 1], ['art', 0.6, 1, 1]] },
  rack: { rolls: [1, 3], none: 1, entries: [['shard', 4, 1, 1], ['circuit', 4, 1, 1], ['dossier', 1, 1, 1], ['drive', 0.5, 1, 1], ['sensor', 0.6, 1, 1]] },
  vault: { rolls: [1, 2], none: 0, entries: [['wafer', 3, 1, 3], ['art', 2, 1, 1], ['exotic', 0.6, 1, 1], ['drive', 0.6, 1, 1]] },
  // The wall med cabinet. Vests are rare and epic, so they turn up mostly on the deeper levels.
  medcab: { rolls: [2, 4], none: 0.5, entries: [['syringe', 4, 1, 2], ['cell', 4, 1, 2], ['medkit', 2, 1, 1], ['battery', 2, 1, 1], ['vest75', 0.5, 1, 1], ['vest100', 0.15, 1, 1]] },
};
const CONTAINERS_BY_RING = { perimeter: ['locker', 'crate'], interior: ['desk', 'rack', 'crate', 'locker'] };

// --- The three stages ------------------------------------------------------------------------
// 1. Breach: the raid map is the Builder's site, the same free grid they laid out. Turrets, guard
//    posts and walls stand where the Builder put them. The core's blast door stays sealed while a
//    power plant stands; with no power plant the core powers itself and only a vent gets you in.
// 2. Loot: one level below ground for each level of the facility, deeper ones with better loot and
//    more security. Every minute inside brings in more guards.
// 3. Extraction: the safe room on the deepest level holds the vault, sometimes with a boss. Opening
//    the vault starts the self-destruct; anyone not back aboard their ship when it ends dies with it.

const TILE = 4; // metres per site grid tile
const SITE_GRID = 12; // tiles per side when a site doesn't say
const CORE_TILES = 4; // the facility core, centred on the grid
const FLOOR_DEPTH = 10; // metres between levels
const MAX_FLOORS = 5;
const FLOOR_GRIDS = [[3, 3], [4, 3], [4, 4], [4, 4], [5, 4]];
// Site pieces the raid knows. hp 0: can't be destroyed (cover).
const SITE_PIECES = {
  turret: { w: 2, h: 2, hp: 250 },
  guardpost: { w: 2, h: 2, hp: 300 },
  power: { w: 2, h: 2, hp: 400 },
  wall: { w: 1, h: 1, hp: 0 },
  boulder: { w: 2, h: 2, hp: 0 },
  crystals: { w: 1, h: 1, hp: 0 },
  wreck: { w: 2, h: 1, hp: 0 },
};
const DESTROY_HEAT = 5; // an explosion outside
const VENT_SECONDS = 6; // cutting through a vent grate, quietly
const WAVE_MS = 60_000; // reinforcements arrive every minute inside...
const WAVE_MAX = 5; // ...one more each time, up to this many
const SELF_DESTRUCT_BASE_S = 70; // the self-destruct timer: this (the run out to the ship), plus...
const SELF_DESTRUCT_PER_FLOOR_S = 30;
// Landing: the raider picks a spot from overhead. Not on the site, not in any turret's reach, and
// not out past the flat ground round it.
const TURRET_REACH = 34; // metres a site turret fires at you
const LAND_MARGIN = 5; // the drop-off clears a turret's reach by this much
const LAND_OFF_SITE = 4; // and the site's edge by this much
const LAND_MAX = 120; // metres from the core
// Every outside defence that must go before the ship comes back for you.
const DEFENCE_TYPES = ['turret', 'guardpost', 'power']; // ...this for every level you have to climb back up

// --- Seeded random numbers ---------------------------------------------------------------

function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),
    pick: (arr) => arr[Math.floor(next() * arr.length)],
    weighted(weights) {
      const total = weights.reduce((s, w) => s + w, 0);
      let r = next() * total;
      for (let i = 0; i < weights.length; i++) {
        r -= weights[i];
        if (r < 0) return i;
      }
      return weights.length - 1;
    },
    shuffle(arr) {
      for (let i = arr.length - 1; i > 0; i--) {
        const j = Math.floor(next() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
      }
      return arr;
    },
  };
}

// --- Inventory grid (the spec's InventoryGrid, also used by the Explorer app) -----------

class Grid {
  constructor(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    this.cells = new Array(cols * rows).fill('');
    this.placed = {}; // uid -> {x, y, w, h}
  }

  canPlace(uid, r) {
    if (r.x < 0 || r.y < 0 || r.x + r.w > this.cols || r.y + r.h > this.rows) return false;
    for (let y = r.y; y < r.y + r.h; y++)
      for (let x = r.x; x < r.x + r.w; x++) {
        const occ = this.cells[y * this.cols + x];
        if (occ !== '' && occ !== uid) return false;
      }
    return true;
  }

  place(uid, r) {
    if (!this.canPlace(uid, r)) return false;
    this.remove(uid);
    this.placed[uid] = r;
    for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) this.cells[y * this.cols + x] = uid;
    return true;
  }

  remove(uid) {
    const r = this.placed[uid];
    if (!r) return;
    for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) this.cells[y * this.cols + x] = '';
    delete this.placed[uid];
  }

  findFree([w, h], rotate = true) {
    const sizes = rotate && w !== h ? [[w, h], [h, w]] : [[w, h]];
    for (const [sw, sh] of sizes)
      for (let y = 0; y <= this.rows - sh; y++)
        for (let x = 0; x <= this.cols - sw; x++) {
          const r = { x, y, w: sw, h: sh };
          if (this.canPlace('', r)) return r;
        }
    return null;
  }
}

// --- Layout --------------------------------------------------------------------------------

// The whole raid map: the site outside (from the Builder's grid) and the levels below the core.
// Positions are in metres: x east, z south, with the core at the origin; level n sits at
// y = -FLOOR_DEPTH * n. `site` is the satellite site record, or null for a facility without one.
// `hpScale` multiplies the outside defences' hit points (a Terran Compact outpost's are tougher).
function generateLayout(seed, tier, type, { floors = tier, site = null, now = 0, hpScale = 1 } = {}) {
  floors = Math.max(1, Math.min(MAX_FLOORS, floors));
  for (let attempt = 0; attempt < 50; attempt++) {
    const layout = tryLayout((seed + attempt * 7919) >>> 0, tier, type, floors, site, now, hpScale);
    if (layout) return layout;
  }
  throw new Error('no valid layout');
}

function tryLayout(seed, tier, type, floorCount, site, now, hpScale) {
  const r = rng(seed);
  const outside = siteLayout(site, tier, r, now, hpScale);

  // Each level is a grid of rooms. Its lift up sits directly under the lift down of the level
  // above (level 1's under the lobby in the core); its lift down is the room furthest from there.
  // On the deepest level that room is the safe room instead, behind locked doors.
  const floors = [];
  const rooms = [];
  const doors = [];
  let shaft = [0, 0]; // where the lift from above comes down
  for (let n = 1; n <= floorCount; n++) {
    const [W, H] = FLOOR_GRIDS[n - 1];
    const last = n === floorCount;
    const entry = n === 1 ? [Math.floor(W / 2), Math.floor(H / 2)] : [r.int(0, W - 1), r.int(0, H - 1)];
    const f = tryFloor(r, W, H, entry[1] * W + entry[0], last);
    if (!f) return null;
    const base = n * 100; // room ids are unique across levels: level * 100 + index
    const origin = [shaft[0] - entry[0] * ROOM, shaft[1] - entry[1] * ROOM];
    for (const room of f.rooms) {
      room.id += base;
      room.floor = n;
      room.pos = [origin[0] + room.x * ROOM, origin[1] + room.y * ROOM];
      rooms.push(room);
    }
    for (const d of f.doors) doors.push({ a: d.a + base, b: d.b + base, locked: d.locked });
    const far = f.far + base;
    floors.push({ n, cols: W, rows: H, origin, y: -FLOOR_DEPTH * n, entrance: f.entrance + base, down: last ? -1 : far, safe: last ? far : -1 });
    shaft = rooms.find((room) => room.id === far).pos;
  }
  const deepest = floors[floors.length - 1];
  const vault = deepest.safe;

  // Containers sit in room corners (doors are mid-wall, so corners never block one). Deeper levels
  // have more of them, and the safe room has the vault boxes.
  const corners = [[-4.6, -4.6], [4.6, -4.6], [-4.6, 4.6], [4.6, 4.6]];
  const containers = [];
  for (const room of rooms) {
    const fl = floors[room.floor - 1];
    if (room.id === fl.entrance || room.id === fl.down) continue;
    const spots = r.shuffle(corners.slice());
    const count = Math.min(3, r.int(1, 2) + (room.floor >= 3 ? 1 : 0));
    const types = room.id === vault ? ['vault', 'vault', 'vault'] : Array.from({ length: count }, () => r.pick(CONTAINERS_BY_RING[room.ring]));
    types.forEach((t, i) => containers.push({ id: `c${containers.length}`, floor: room.floor, room: room.id, type: t, pos: spots[i], grid: CONTAINER_GRIDS[t] }));
  }

  // Health supplies, from their own random numbers so the rest of the layout stays as it was.
  // A wall med cabinet (the green cross) in about one room in three, more often deeper down; it
  // hangs beside the doorway, clear of the corner containers. Loose syringes and shield cells lie
  // on shelves and floors, and a vest now and then, better ones deeper in.
  const mr = rng((seed ^ 0x9e3779b9) >>> 0);
  const WALL_SPOTS = [[[-6.65, 3.2], 'west'], [[6.65, -3.2], 'east'], [[3.2, -6.65], 'north'], [[-3.2, 6.65], 'south']];
  for (const room of rooms) {
    if (room.id === vault || mr.next() >= 0.22 + 0.06 * room.floor) continue;
    const [pos, wall] = mr.pick(WALL_SPOTS);
    containers.push({ id: `c${containers.length}`, floor: room.floor, room: room.id, type: 'medcab', pos, wall, grid: CONTAINER_GRIDS.medcab });
  }
  const loose = [];
  const FLOOR_SPOTS = [[-2.6, -5.6], [2.6, 5.6], [5.6, -2.6], [-5.6, 2.6], [0, 4.2], [-4.2, 0]];
  const used = new Set();
  const lay = (floor, item, qty) => {
    const own = rooms.filter((room) => room.floor === floor && room.id !== vault);
    for (let tries = 0; tries < 10; tries++) {
      const room = mr.pick(own);
      const spot = mr.int(0, FLOOR_SPOTS.length - 1);
      if (used.has(`${room.id}:${spot}`)) continue;
      used.add(`${room.id}:${spot}`);
      loose.push({ id: `l${loose.length}`, floor, room: room.id, pos: FLOOR_SPOTS[spot], item, qty });
      return;
    }
  };
  for (const fl of floors) {
    for (let i = 0; i < 1 + Math.floor(fl.n / 2); i++) lay(fl.n, mr.next() < 0.5 ? 'syringe' : 'cell', mr.int(1, 2));
    if (mr.next() < (fl.n === 1 ? 0.1 : 0.35)) lay(fl.n, fl.n >= 3 && mr.next() < 0.5 ? 'vest100' : 'vest75', 1);
  }

  // Guards patrol short loops of rooms on their own level: more of them, the deeper you go.
  const guards = [];
  const turrets = [];
  for (const fl of floors) {
    const own = rooms.filter((room) => room.floor === fl.n);
    const adj = (id) => doors.filter((d) => !d.locked && (d.a === id || d.b === id)).map((d) => (d.a === id ? d.b : d.a));
    const posts = own.filter((room) => room.id !== fl.entrance && room.id !== vault);
    const count = 1 + fl.n + (tier - 1);
    for (let i = 0; i < count && posts.length; i++) {
      let at = r.pick(posts).id;
      const route = [at];
      for (let s = 0; s < 3; s++) {
        const next = adj(at).filter((x) => x !== fl.entrance);
        if (!next.length) break;
        at = r.pick(next);
        route.push(at);
      }
      guards.push({ id: `g${guards.length}`, floor: fl.n, route });
    }
    // Turrets watch the deeper levels' rooms, and the safe room.
    for (let i = 0; i < Math.min(2, fl.n - 1) && posts.length; i++) turrets.push({ id: `t${turrets.length}`, floor: fl.n, room: r.pick(posts).id, pos: [0, -5.5] });
  }
  for (let i = 0; i < SECURITY[tier].turrets; i++) turrets.push({ id: `t${turrets.length}`, floor: deepest.n, room: vault, pos: i === 0 ? [0, -5.5] : [5.5, 0] });

  // Sometimes a boss waits in the safe room; likelier the better the security.
  const boss = r.next() < 0.2 + 0.15 * tier ? { room: vault, health: 600 + 150 * floorCount } : null;

  // The way out: the ship, which comes back to a pad beside the blast door once the defences are down.
  const extracts = [{ id: 'ship', kind: 'ship', pos: outside.pad }];

  return {
    seed, tier, type, room: ROOM, tile: TILE, floorDepth: FLOOR_DEPTH,
    ...outside,
    floors, rooms, doors, vault, containers, loose, guards, turrets, boss, extracts,
  };
}

// One level: a random spanning tree of rooms from the entrance plus a few loops, with `far` the
// room furthest from the entrance. On the deepest level `far` is the safe room, so everything
// else must be reachable without going through it (the keycard that opens it has to be findable).
function tryFloor(r, W, H, entrance, last) {
  const id = (x, y) => y * W + x;
  const rooms = [];
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) rooms.push({ id: id(x, y), x, y });
  const neighbours = (n) => {
    const { x, y } = rooms[n];
    return [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].filter(([a, b]) => a >= 0 && b >= 0 && a < W && b < H).map(([a, b]) => id(a, b));
  };
  const doors = new Set();
  const key = (a, b) => (a < b ? `${a}-${b}` : `${b}-${a}`);
  const seen = new Set([entrance]);
  const stack = [entrance];
  while (stack.length) {
    const cur = stack[stack.length - 1];
    const open = neighbours(cur).filter((n) => !seen.has(n));
    if (!open.length) {
      stack.pop();
      continue;
    }
    const nxt = r.pick(open);
    doors.add(key(cur, nxt));
    seen.add(nxt);
    stack.push(nxt);
  }
  const extra = Math.max(1, Math.floor(W / 2));
  for (let i = 0; i < extra * 4 && doors.size < rooms.length - 1 + extra; i++) {
    const a = r.int(0, rooms.length - 1);
    doors.add(key(a, r.pick(neighbours(a))));
  }
  const edges = [...doors].map((k) => k.split('-').map(Number));
  const adj = (n, without = -1) => edges.filter((e) => e.includes(n)).map((e) => (e[0] === n ? e[1] : e[0])).filter((m) => m !== without);

  const depth = bfs(entrance, (n) => adj(n));
  let far = 0;
  for (const room of rooms) if (depth[room.id] > depth[far] || (depth[room.id] === depth[far] && room.id > far)) far = room.id;
  if (far === entrance || depth[far] < 2) return null;
  if (last) {
    const reach = bfs(entrance, (n) => (n === far ? [] : adj(n, far)));
    if (rooms.some((room) => room.id !== far && reach[room.id] === undefined)) return null;
  }
  for (const room of rooms) {
    room.depth = depth[room.id];
    room.ring = last && room.id === far ? 'core' : room.depth <= 1 ? 'perimeter' : 'interior';
  }
  return { rooms, doors: edges.map(([a, b]) => ({ a, b, locked: last && (a === far || b === far) })), entrance, far };
}

// The outside: the site's grid and what stands on it, in metres around the core.
// A satellite site is mirrored as the Builder laid it out (defences still being built aren't
// there yet); anything else gets defences set out from its security tier.
function siteLayout(site, tier, r, now, hpScale = 1) {
  const grid = site?.grid || SITE_GRID;
  const half = (grid * TILE) / 2;
  const coreAt = (grid - CORE_TILES) / 2;
  const satellite = site?.kind === 'satellite';
  const placed = satellite ? (site.pieces || []).filter((p) => !(p.readyAt && now < p.readyAt)) : defaultPieces(grid, coreAt, tier, r);
  const obstacles = satellite ? site.obstacles || [] : [];
  const list = [...placed.map((p) => ({ ...p, id: `p${p.id}` })), ...obstacles.map((o) => ({ ...o, id: `o${o.id}` }))];
  const pieces = list.map((p) => {
    const def = SITE_PIECES[p.type] || { w: p.w || 1, h: p.h || 1, hp: 0 };
    return {
      id: p.id,
      type: p.type,
      size: [def.w * TILE, def.h * TILE],
      pos: [(p.x + def.w / 2) * TILE - half, (p.y + def.h / 2) * TILE - half],
      hp: Math.round(def.hp * hpScale),
    };
  });
  // The turrets the security tier mounts round the core, where the Builder's view draws them.
  const ring = SECURITY[tier].turrets;
  for (let t = 0; t < ring; t++) {
    const ang = (2 * Math.PI * (t + 0.5)) / ring + 0.6;
    pieces.push({ id: `ct${t}`, type: 'turret', ring: true, size: [2, 2], pos: [Math.cos(ang) * 6.6, Math.sin(ang) * 6.6], hp: Math.round(SITE_PIECES.turret.hp * hpScale) });
  }
  const core = CORE_TILES * TILE;
  return {
    // The site as the Builder sees it, for the raider's app to draw with the same models.
    view: { id: site?.id || 'facility', grid, pieces: placed, obstacles },
    ringTurrets: ring,
    grid,
    half,
    core, // the core building's side, in metres
    pieces,
    powered: pieces.some((p) => p.type === 'power') ? 'plant' : 'core',
    door: [0, core / 2], // the blast door, on the south edge of the core's pad
    vents: [{ id: 'v0', pos: [-core / 2, 0], side: 'west' }, { id: 'v1', pos: [core / 2, 0], side: 'east' }, { id: 'v2', pos: [0, -core / 2], side: 'north' }],
    pad: returnPad(pieces, core, half), // where the ship comes back for you, beside the blast door
    landing: { reach: TURRET_REACH + LAND_MARGIN, offSite: half + LAND_OFF_SITE, max: LAND_MAX },
  };
}

// The first clear spot south of the blast door, between the site's pieces (anything left standing
// once the defences are down: walls, obstacles and wrecks). Off the site's south edge if none is.
function returnPad(pieces, core, half) {
  const clear = (x, z) => pieces.every((p) => Math.abs(x - p.pos[0]) > p.size[0] / 2 + 3 || Math.abs(z - p.pos[1]) > p.size[1] / 2 + 3);
  for (let z = core / 2 + 6; z <= half + 6; z += 1) for (const x of [0, -6, 6]) if (clear(x, z)) return [x, z];
  return [0, half + 8];
}

// Defences for a facility without a site of its own: a power plant, turrets and guard posts from
// the security tier, and walls for cover. The tiles round the core and the lane from its door to
// the pad stay clear.
function defaultPieces(grid, coreAt, tier, r) {
  const used = [];
  const blocked = (x, y, w, h) => {
    if (x < 0 || y < 0 || x + w > grid || y + h > grid) return true;
    const clear = { x: coreAt - 1, y: coreAt - 1, w: CORE_TILES + 2, h: CORE_TILES + 2 };
    const lane = { x: coreAt + 1, y: coreAt + CORE_TILES, w: 2, h: grid };
    const hit = (a) => x < a.x + a.w && a.x < x + w && y < a.y + a.h && a.y < y + h;
    return hit(clear) || hit(lane) || used.some(hit);
  };
  const out = [];
  const want = ['power', ...Array(tier).fill('turret'), ...Array(tier >= 2 ? 2 : 1).fill('guardpost'), ...Array(4 + tier * 2).fill('wall')];
  for (const type of want) {
    const { w, h } = SITE_PIECES[type];
    for (let tries = 0; tries < 60; tries++) {
      const x = r.int(0, grid - w);
      const y = r.int(0, grid - h);
      if (blocked(x, y, w, h)) continue;
      used.push({ x, y, w, h });
      out.push({ id: `d${out.length}`, type, x, y });
      break;
    }
  }
  return out;
}

function bfs(start, next) {
  const depth = { [start]: 0 };
  const queue = [start];
  while (queue.length) {
    const cur = queue.shift();
    for (const n of next(cur)) {
      if (depth[n] === undefined) {
        depth[n] = depth[cur] + 1;
        queue.push(n);
      }
    }
  }
  return depth;
}

// --- Loot ------------------------------------------------------------------------------------

function rollTable(table, tier, bias, r) {
  const eligible = table.entries;
  const weights = eligible.map(([item, w]) => {
    const def = ITEMS[item];
    return w * (1 + (tier - 1) * RARITY_BOOST[def.rarity]) * (def.cat === bias ? 2 : 1);
  });
  weights.push(table.none);
  const out = [];
  const rolls = r.int(table.rolls[0], table.rolls[1]);
  for (let i = 0; i < rolls; i++) {
    const idx = r.weighted(weights);
    if (idx === eligible.length) continue;
    const [item, , lo, hi] = eligible[idx];
    out.push({ item, qty: Math.min(ITEMS[item].stack, r.int(lo, hi)) });
  }
  return out;
}

// Splits a quantity into stacks no bigger than the item allows.
function stacks(item, qty) {
  const out = [];
  for (let left = qty; left > 0; left -= ITEMS[item].stack) out.push({ item, qty: Math.min(left, ITEMS[item].stack) });
  return out;
}

// --- Runs ------------------------------------------------------------------------------------

function heatLevel(heat) {
  let level = 0;
  HEAT_LEVELS.forEach((l, i) => {
    if (heat >= l.from) level = i;
  });
  return level;
}

function value(items) {
  return items.reduce((s, it) => s + ITEMS[it.item].value * it.qty, 0);
}

function fail(reason) {
  return { ok: false, reason };
}

// How many levels a facility has: one per level of its core building (its security tier before
// buildings had levels).
function floorsOf(facility) {
  return Math.max(1, Math.min(MAX_FLOORS, facility.level ?? facility.security ?? 1));
}

function selfDestructSeconds(floors) {
  return SELF_DESTRUCT_BASE_S + SELF_DESTRUCT_PER_FLOOR_S * floors;
}

// Starts a raid on a facility. `facility` is the building object in galaxy state, `site` the
// satellite site it stands on (if any); the exposed part of its vault moves into escrow so the
// Builder can't ship what raiders are stealing. `hpScale` and `heatScale` are the outpost
// faction's bonuses: tougher defences, and Heat that builds faster.
function startRun({ facility, facilityName, pilot, seed, now, lootSeed, site = null, pouch = null, hpScale = 1, heatScale = 1 }) {
  const tier = facility.security || 1;
  const floors = floorsOf(facility);
  const layout = generateLayout(seed, tier, facility.type, { floors, site, now, hpScale });
  const def = FACILITIES[facility.type];
  const r = rng(lootSeed >>> 0);

  // Vault goods go into the vault room's containers; the rest of the loot is rolled.
  const escrow = {};
  for (const [item, qty] of Object.entries(facility.vault || {})) {
    const take = Math.ceil(qty * VAULT_EXPOSED);
    if (take > 0) escrow[item] = take;
  }
  const contents = {};
  // Each level down rolls as if security were a tier higher: better loot, deeper in.
  const lootTier = (c) => tier + c.floor - 1;
  for (const c of layout.containers) contents[c.id] = c.type === 'vault' ? [] : rollTable(TABLES[c.type], lootTier(c), def.bias, r).flatMap((s) => stacks(s.item, s.qty));
  const vaultBoxes = layout.containers.filter((c) => c.type === 'vault');
  for (const c of vaultBoxes) contents[c.id].push(...rollTable(TABLES.vault, lootTier(c), def.bias, r).flatMap((s) => stacks(s.item, s.qty)));
  // One keycard for the safe room, somewhere else on the deepest level.
  const plain = layout.containers.filter((c) => c.type !== 'vault' && c.type !== 'medcab');
  const deep = plain.filter((c) => c.floor === floors);
  const keyBox = r.pick(deep.length ? deep : plain);
  contents[keyBox.id].push({ item: 'keycard', qty: 1 });

  let uid = 1;
  const boxes = {};
  for (const c of layout.containers) boxes[c.id] = { grid: new Grid(c.grid[0], c.grid[1]), items: [], searchedAt: null, revealAt: {} };
  const area = (item) => ITEMS[item].size[0] * ITEMS[item].size[1];
  const put = (box, s, rect) => {
    // vaultQty: how many of these came from the Builder's vault (the rest is ordinary loot).
    const it = { uid: `i${uid++}`, item: s.item, qty: s.qty, vaultQty: s.vaultQty || 0 };
    if (ITEMS[s.item].vest) it.armor = ITEMS[s.item].vest;
    box.grid.place(it.uid, rect);
    box.items.push(it);
  };
  // Vault goods go in the safe room's boxes first: one stack of each kind in turn (the biggest kind
  // first), each in the next box with room, so every kind the facility makes is there to find.
  // What doesn't fit stays in deep storage.
  const piles = Object.keys(escrow).sort((a, b) => area(b) - area(a)).map((item) => stacks(item, escrow[item]));
  let next = 0;
  for (let round = 0; piles.some((p) => p.length > round); round++) {
    for (const pile of piles) {
      const s = pile[round];
      if (!s) continue;
      const box = [...vaultBoxes.keys()].map((k) => boxes[vaultBoxes[(next + k) % vaultBoxes.length].id]).find((b) => b.grid.findFree(ITEMS[s.item].size));
      next++;
      if (box) put(box, { ...s, vaultQty: s.qty }, box.grid.findFree(ITEMS[s.item].size));
      else escrow[s.item] -= s.qty;
    }
  }
  // Then everything else: the keycard, then the biggest first. Anything that doesn't fit isn't there.
  const order = (s) => (s.item === 'keycard' ? Infinity : area(s.item));
  for (const c of layout.containers) {
    const box = boxes[c.id];
    for (const s of contents[c.id].sort((a, b) => order(b) - order(a))) {
      const rect = box.grid.findFree(ITEMS[s.item].size);
      if (rect) put(box, s, rect);
    }
  }
  for (const [item, qty] of Object.entries(escrow)) {
    if (qty <= 0) delete escrow[item];
    else facility.vault[item] -= qty;
  }
  facility.escrow = escrow;
  const loose = {};
  for (const l of layout.loose) loose[l.id] = { ...l, ...(ITEMS[l.item].vest ? { armor: ITEMS[l.item].vest } : {}) };
  const carried = startingPouch(pouch);

  return {
    id: `run-${seed.toString(36)}`,
    pilot,
    facilityName,
    tier,
    floors,
    layout,
    startedAt: now,
    endsAt: now + (SECURITY[tier].minutes + 4 * floors) * 60_000,
    heat: 0,
    heatScale, // every Heat gain is multiplied by this
    heatFrom: {}, // event -> last ms counted
    heatClock: now,
    drill: null,
    vaultOpen: false,
    open: null, // container being searched
    boxes,
    inv: { backpack: new Grid(...BACKPACK), secure: new Grid(...SECURE_CASE), items: {} },
    extract: null, // {id, since}
    landing: null, // [x, z] where the ship dropped the raider off
    destroyed: [], // site pieces knocked out
    vent: null, // {id, since} while cutting a vent grate
    breached: null, // 'door' | 'vent' once inside the core
    breachedAt: null,
    wave: 0, // reinforcement waves sent so far
    selfDestructAt: null, // set when the vault opens
    pouch: carried, // item -> count; the server keeps the counts
    pouchStart: { ...carried },
    vest: { item: STARTER_VEST, armor: ITEMS[STARTER_VEST].vest }, // armour as of the last swap
    using: null, // {item, since} while a pouch item is being used
    loose, // id -> pickups lying in the facility
    looseUid: layout.loose.length,
    grenades: LAUNCHER_ROUNDS,
    grenadeAt: null,
    status: 'live',
  };
}

// The pouch a raider brings: what they extracted with last time, or the starter kit if that's empty.
function startingPouch(saved) {
  const out = {};
  for (const [item, n] of Object.entries(saved || {})) {
    const cap = ITEMS[item]?.pouch?.cap;
    if (cap && n >= 1) out[item] = Math.min(cap, Math.floor(n));
  }
  return Object.keys(out).length ? out : { ...STARTER_POUCH };
}

// The part of a run the raider's app is allowed to know at the start: no container contents.
function briefing(run, now) {
  return {
    id: run.id,
    facility: run.facilityName,
    tier: run.tier,
    floors: run.floors,
    layout: run.layout,
    remaining: Math.max(0, run.endsAt - now),
    landing: run.landing,
    ...stage(run, now),
    heat: run.heat,
    level: heatLevel(run.heat),
    vaultOpen: run.vaultOpen,
    extracts: extractStates(run, now),
    inventory: inventoryView(run),
    pouch: run.pouch,
    vest: run.vest,
    loose: looseView(run),
    grenades: run.grenades,
    backpack: BACKPACK,
    secure: SECURE_CASE,
  };
}

// What the raider carries, with names and values for the app to show.
function inventoryView(run) {
  const out = [];
  for (const [gridName, grid] of [['backpack', run.inv.backpack], ['secure', run.inv.secure]])
    for (const [uid, rect] of Object.entries(grid.placed)) out.push({ ...publicItem(run.inv.items[uid]), grid: gridName, rect });
  return out;
}

function looseView(run) {
  return Object.values(run.loose).map((l) => ({ ...l, name: ITEMS[l.item].name }));
}

function addHeat(run, amount) {
  const before = heatLevel(run.heat);
  run.heat = Math.min(100, run.heat + amount * (run.heatScale || 1));
  return heatLevel(run.heat) !== before;
}

// A noise the Explorer reports: gunfire, being spotted, a body found. Rate-limited per kind.
function report(run, kind, now) {
  const ev = HEAT_EVENTS[kind];
  if (!ev) return fail('unknown event');
  if (now - (run.heatFrom[kind] ?? -Infinity) < ev.gap) return { ok: true, changed: false };
  run.heatFrom[kind] = now;
  return { ok: true, changed: addHeat(run, ev.heat) };
}

// Heat from time and from a running drill. Call often; it works from elapsed time.
function heatTick(run, now) {
  let gain = 0;
  while (now - run.heatClock >= 30_000) {
    run.heatClock += 30_000;
    gain += HEAT_PER_30S;
  }
  if (run.drill) {
    while (now - run.drill.heatClock >= 5_000) {
      run.drill.heatClock += 5_000;
      gain += DRILL_HEAT_PER_5S;
    }
  }
  return gain > 0 && addHeat(run, gain);
}

function extractStates(run, now) {
  const left = defencesLeft(run);
  const why = !run.landing ? 'pick a landing spot' : left ? `your ship is away until the outside defences are down (${left} left)` : '';
  return { ship: { open: shipBack(run), why, countdown: EXTRACTS.ship.countdown, needs: null } };
}

// --- Landing and the ship ----------------------------------------------------------------------

// Why a landing spot isn't allowed, or '' if it is.
function landingProblem(layout, x, z) {
  const L = layout.landing;
  if (!Number.isFinite(x) || !Number.isFinite(z)) return 'pick a spot on the ground';
  if (Math.hypot(x, z) > L.max) return 'too far out: land nearer the site';
  if (Math.abs(x) < L.offSite && Math.abs(z) < L.offSite) return "you can't land on the site itself";
  for (const p of layout.pieces) if (p.type === 'turret' && Math.hypot(x - p.pos[0], z - p.pos[1]) < L.reach) return 'inside a turret\'s reach: land further out';
  return '';
}

// The ship drops the raider off at a spot they picked, then leaves.
function land(run, x, z, now) {
  if (run.landing) return fail('you have already landed');
  const why = landingProblem(run.layout, Number(x), Number(z));
  if (why) return fail(why);
  run.landing = [Number(x), Number(z)];
  run.landedAt = now;
  return { ok: true, landing: run.landing };
}

// Outside defences still standing: turrets (the core's too), guard posts and power plants.
function defencesLeft(run) {
  return run.layout.pieces.filter((p) => DEFENCE_TYPES.includes(p.type) && p.hp > 0 && !run.destroyed.includes(p.id)).length;
}

// The ship comes back to its pad by the blast door once nothing outside can shoot it down.
function shipBack(run) {
  return !!run.landing && defencesLeft(run) === 0;
}

// Where the raid is up to, for the raider's app and the Builder's watch.
function stage(run, now) {
  return {
    stage: run.selfDestructAt ? 'escape' : run.breached ? 'loot' : 'breach',
    breached: run.breached,
    destroyed: run.destroyed,
    doorOpen: doorOpen(run),
    wave: run.wave,
    floor: run.floor ?? 0,
    selfDestruct: run.selfDestructAt ? Math.max(0, run.selfDestructAt - now) : null,
    defencesLeft: defencesLeft(run),
    ship: !run.landing ? 'carrying' : shipBack(run) ? 'back' : 'away',
  };
}

// --- Stage 1: the breach ---------------------------------------------------------------------

// The blast door opens once every power plant on the site is down. A site without one powers
// the core itself, and the door never opens.
function doorOpen(run) {
  const plants = run.layout.pieces.filter((p) => p.type === 'power');
  return plants.length > 0 && plants.every((p) => run.destroyed.includes(p.id));
}

// The raider's app says it destroyed a piece of the site's defences.
function destroy(run, pieceId, now) {
  const p = run.layout.pieces.find((x) => x.id === pieceId);
  if (!p) return fail('nothing there');
  if (!p.hp) return fail("that can't be destroyed");
  if (run.destroyed.includes(p.id)) return { ok: true, changed: false };
  const wasOpen = doorOpen(run);
  run.destroyed.push(p.id);
  addHeat(run, DESTROY_HEAT);
  return { ok: true, changed: true, type: p.type, doorOpened: !wasOpen && doorOpen(run), at: now };
}

function enter(run, via, now) {
  if (!run.breached) {
    run.breached = via;
    run.breachedAt = now;
  }
  return { ok: true, via };
}

// Walking in through the blast door, once it's open.
function enterDoor(run, now) {
  if (!doorOpen(run)) return fail(run.layout.powered === 'core' ? 'the blast door is sealed: find a vent' : 'the blast door is sealed: knock out the power plant or find a vent');
  return enter(run, 'door', now);
}

function ventStart(run, ventId, now) {
  if (!run.layout.vents.some((v) => v.id === ventId)) return fail('no vent there');
  if (!run.vent || run.vent.id !== ventId) run.vent = { id: ventId, since: now };
  return { ok: true, seconds: VENT_SECONDS };
}

function ventStop(run) {
  run.vent = null;
  return { ok: true };
}

function ventFinish(run, now) {
  if (!run.vent) return fail('not cutting a vent');
  if (now - run.vent.since < VENT_SECONDS * 1000 - 250) return fail('the grate is not cut through yet');
  run.vent = null;
  return enter(run, 'vent', now);
}

// The raider's app says which level they've reached, for the Builder's watch.
function reachFloor(run, n) {
  if (!run.breached) return fail('get inside the facility first');
  if (!Number.isInteger(n) || n < 0 || n > run.floors) return fail('no such level');
  run.floor = n;
  run.deepest = Math.max(run.deepest || 0, n);
  return { ok: true };
}

// --- Stage 2: reinforcements ------------------------------------------------------------------

// Every minute inside sends in another wave, one guard bigger than the last. Call often; returns
// the new wave when one is due. The self-destruct brings two extra.
function waveTick(run, now) {
  if (!run.breached) return null;
  const due = Math.floor((now - run.breachedAt) / WAVE_MS);
  if (due <= run.wave) return null;
  run.wave = due;
  return { wave: due, count: Math.min(WAVE_MAX, due) + (run.selfDestructAt ? 2 : 0) };
}

function findHeld(run, item) {
  return Object.values(run.inv.items).find((it) => it.item === item);
}

function openContainer(run, cid, now) {
  const box = run.boxes[cid];
  if (!box) return fail('no such container');
  const c = run.layout.containers.find((x) => x.id === cid);
  if (!run.breached) return fail('get inside the facility first');
  if (c.type === 'vault' && !run.vaultOpen) return fail('the vault is locked');
  if (run.open !== cid) closeContainer(run, now);
  run.open = cid;
  // Items reveal one at a time, carrying on from where an earlier search stopped.
  let t = now;
  for (const it of box.items) if (box.revealAt[it.uid] !== undefined) t = Math.max(t, box.revealAt[it.uid]);
  for (const it of box.items) {
    if (box.revealAt[it.uid] !== undefined) continue;
    t += SEARCH_MS[ITEMS[it.item].rarity];
    box.revealAt[it.uid] = t;
  }
  return { ok: true };
}

// Leaving a container stops the search; anything not yet revealed has to be searched again.
function closeContainer(run, now) {
  const box = run.open && run.boxes[run.open];
  if (box) for (const uid of Object.keys(box.revealAt)) if (box.revealAt[uid] > now) delete box.revealAt[uid];
  run.open = null;
  return { ok: true };
}

// The open container as the raider sees it: revealed items, and dark placeholders for the rest.
function containerView(run, now) {
  const box = run.open && run.boxes[run.open];
  if (!box) return { container: null };
  const c = run.layout.containers.find((x) => x.id === run.open);
  const slots = box.items.map((it) => {
    const rect = box.grid.placed[it.uid];
    const at = box.revealAt[it.uid];
    return at <= now ? { ...publicItem(it), rect } : { uid: it.uid, rect, revealIn: at - now };
  });
  return { container: run.open, kind: c.type, grid: c.grid, slots };
}

// Items whose search finished by `now`.
function revealed(run, now) {
  const box = run.open && run.boxes[run.open];
  if (!box) return [];
  return box.items.filter((it) => box.revealAt[it.uid] <= now).map((it) => ({ ...publicItem(it), rect: box.grid.placed[it.uid] }));
}

function publicItem(it) {
  const def = ITEMS[it.item];
  const out = { uid: it.uid, item: it.item, qty: it.qty, name: def.name, cat: def.cat, rarity: def.rarity, size: def.size, value: def.value };
  if (def.vest) Object.assign(out, { armor: it.armor ?? def.vest, vest: def.vest });
  return out;
}

// `armor`: what's left on the vest the raider is wearing, for when they swap it for one in here.
function take(run, uid, to, now, armor = 0) {
  const box = run.open && run.boxes[run.open];
  if (!box) return fail('open a container first');
  const it = box.items.find((x) => x.uid === uid);
  if (!it) return fail('not in this container');
  if (!(box.revealAt[uid] <= now)) return fail('still searching');
  const def = ITEMS[it.item];
  const gone = () => {
    box.grid.remove(uid);
    box.items = box.items.filter((x) => x.uid !== uid);
    delete box.revealAt[uid];
  };
  if (def.pouch) {
    const n = pouchAdd(run, it.item, it.qty);
    if (!n) return fail(`no room in your pouch for another ${def.name.toLowerCase()}`);
    it.qty -= n;
    if (it.qty <= 0) gone();
    return { ok: true, pouch: true, partial: it.qty > 0 };
  }
  if (def.vest) {
    // Put it on; the old vest goes where this one was (every vest is the same size).
    const rect = box.grid.placed[uid];
    const old = wearVest(run, it.item, it.armor ?? def.vest, armor);
    gone();
    const back = { uid: `${uid}w${run.looseUid++}`, item: old.item, qty: 1, vaultQty: 0, armor: old.armor };
    box.grid.place(back.uid, rect);
    box.items.push(back);
    box.revealAt[back.uid] = now;
    return { ok: true, vest: run.vest };
  }
  if (to === 'secure' && def.secure === false) return fail(`${def.name} won't fit the Secure Case`);
  const grid = to === 'secure' ? run.inv.secure : run.inv.backpack;
  const before = it.qty;

  // Top up a matching stack first; vault units move first, so the Builder's share stays exact.
  const move = (dest, n) => {
    const v = Math.min(n, it.vaultQty);
    it.vaultQty -= v;
    it.qty -= n;
    dest.qty += n;
    dest.vaultQty += v;
  };
  for (const held of Object.values(run.inv.items)) {
    if (it.qty <= 0) break;
    if (held.item !== it.item || held.qty >= def.stack || !grid.placed[held.uid]) continue;
    move(held, Math.min(it.qty, def.stack - held.qty));
  }
  if (it.qty > 0) {
    const rect = grid.findFree(def.size);
    if (!rect) {
      const full = to === 'secure' ? 'Secure Case is full' : 'Backpack is full';
      return it.qty < before ? { ok: true, partial: true } : fail(full); // a top-up still counts
    }
    grid.place(it.uid, rect);
    run.inv.items[it.uid] = { uid: it.uid, item: it.item, qty: it.qty, vaultQty: it.vaultQty };
  }
  box.grid.remove(uid);
  box.items = box.items.filter((x) => x.uid !== uid);
  delete box.revealAt[uid];
  return { ok: true };
}

// Puts a carried item back into the open container.
function drop(run, uid, now) {
  const box = run.open && run.boxes[run.open];
  const it = run.inv.items[uid];
  if (!it) return fail('not carrying that');
  if (!box) return fail('open a container to drop into');
  const rect = box.grid.findFree(ITEMS[it.item].size);
  if (!rect) return fail('no room in there');
  run.inv.backpack.remove(uid);
  run.inv.secure.remove(uid);
  delete run.inv.items[uid];
  box.grid.place(uid, rect);
  box.items.push({ uid, item: it.item, qty: it.qty, vaultQty: it.vaultQty });
  box.revealAt[uid] = now;
  return { ok: true };
}

// Moves a carried item between the backpack and the Secure Case.
function stow(run, uid, to) {
  const it = run.inv.items[uid];
  if (!it) return fail('not carrying that');
  const def = ITEMS[it.item];
  if (to === 'secure' && def.secure === false) return fail(`${def.name} won't fit the Secure Case`);
  const [from, dest] = to === 'secure' ? [run.inv.backpack, run.inv.secure] : [run.inv.secure, run.inv.backpack];
  if (!from.placed[uid]) return fail('already there');
  const rect = dest.findFree(def.size);
  if (!rect) return fail(to === 'secure' ? 'Secure Case is full' : 'Backpack is full');
  from.remove(uid);
  dest.place(uid, rect);
  return { ok: true };
}

// --- The pouch, vests and the grenade launcher ----------------------------------------------

// Adds up to `qty` of a pouch item, as far as its cap allows. Returns how many went in.
function pouchAdd(run, item, qty) {
  const n = Math.max(0, Math.min(qty, ITEMS[item].pouch.cap - (run.pouch[item] || 0)));
  if (n > 0) run.pouch[item] = (run.pouch[item] || 0) + n;
  return n;
}

// Swaps the worn vest for `item` (with `armor` on it). `left` is what the raider's app says is
// left on the old one. Returns the old vest, to lie where the new one was.
function wearVest(run, item, armor, left) {
  const old = run.vest;
  const cap = ITEMS[old.item].vest;
  run.vest = { item, armor: Math.max(0, Math.min(ITEMS[item].vest, Number(armor) || 0)) };
  return { item: old.item, armor: Math.max(0, Math.min(cap, Math.round(Number(left) || 0))) };
}

// Using a pouch item takes time: start, then finish once it's done. Stopping (firing, sprinting,
// swapping weapons) uses nothing.
function useStart(run, item, now) {
  const def = ITEMS[item]?.pouch;
  if (!def) return fail('nothing to use');
  if (!(run.pouch[item] > 0)) return fail(`no ${ITEMS[item].name.toLowerCase()}s left`);
  run.using = { item, since: now };
  return { ok: true, item, seconds: def.seconds };
}

function useStop(run) {
  run.using = null;
  return { ok: true };
}

function useFinish(run, now) {
  if (!run.using) return fail('not using anything');
  const { item, since } = run.using;
  const def = ITEMS[item].pouch;
  if (now - since < def.seconds * 1000 - 250) return fail('not done yet');
  run.using = null;
  run.pouch[item] -= 1;
  if (run.pouch[item] <= 0) delete run.pouch[item];
  return { ok: true, item, health: def.health || 0, armor: def.armor || 0 };
}

// Picking up something lying in the facility: into the pouch (what fits; the rest stays), or a
// vest to wear, leaving the old one in its place.
function pickUp(run, id, armor) {
  const l = run.loose[id];
  if (!l) return fail('nothing there');
  if (!run.breached) return fail('get inside the facility first');
  const def = ITEMS[l.item];
  if (def.vest) {
    const old = wearVest(run, l.item, l.armor ?? def.vest, armor);
    Object.assign(l, old);
    return { ok: true, vest: run.vest };
  }
  const n = pouchAdd(run, l.item, l.qty);
  if (!n) return fail(`no room in your pouch for another ${def.name.toLowerCase()}`);
  l.qty -= n;
  if (l.qty <= 0) delete run.loose[id];
  return { ok: true, taken: n };
}

// A grenade leaves the launcher. The server counts the rounds; a burst is loud.
function fireGrenade(run, now) {
  if (run.grenades <= 0) return fail('the launcher is empty');
  if (run.grenadeAt !== null && now - run.grenadeAt < LAUNCHER_GAP_MS - 150) return fail('the launcher is still cycling');
  run.grenades -= 1;
  run.grenadeAt = now;
  return { ok: true, left: run.grenades, changed: addHeat(run, GRENADE_HEAT) };
}

// --- Stage 3: the safe room and the self-destruct --------------------------------------------

function openVault(run, now) {
  run.vaultOpen = true;
  run.selfDestructAt = now + selfDestructSeconds(run.floors) * 1000;
}

function useKeycard(run, now) {
  if (run.vaultOpen) return fail('the vault is already open');
  if (!findHeld(run, 'keycard')) return fail('you need an access keycard');
  openVault(run, now);
  return { ok: true };
}

function drillStart(run, now) {
  if (run.vaultOpen) return fail('the vault is already open');
  if (!run.breached) return fail('get inside the facility first');
  if (!run.drill) run.drill = { since: now, heatClock: now };
  return { ok: true, seconds: DRILL_SECONDS };
}

function drillStop(run) {
  run.drill = null;
  return { ok: true };
}

function drillFinish(run, now) {
  if (!run.drill) return fail('the drill is not running');
  if (now - run.drill.since < DRILL_SECONDS * 1000 - 250) return fail('the drill is not through yet');
  heatTick(run, now);
  run.drill = null;
  openVault(run, now);
  return { ok: true };
}

// Boarding the ship: stand on the pad for the countdown.
function extractStart(run, id, now) {
  const ex = run.layout.extracts.find((e) => e.id === id);
  if (!ex) return fail('no such extract');
  if (!shipBack(run)) return fail(extractStates(run, now).ship.why);
  if (!run.extract || run.extract.id !== id) run.extract = { id, since: now, countdown: EXTRACTS[ex.kind].countdown };
  return { ok: true, countdown: run.extract.countdown, loud: false };
}

function extractStop(run) {
  run.extract = null;
  return { ok: true };
}

// The raider says the countdown ran out while they stood on the pad. The server checks the time.
function extractFinish(run, now) {
  if (!run.extract) return fail('not extracting');
  if (now - run.extract.since < run.extract.countdown * 1000 - 250) return fail('countdown not finished');
  if (run.selfDestructAt && now >= run.selfDestructAt) return fail('too late');
  return { ok: true, via: EXTRACTS.ship.name };
}

// Ends a run: what the pilot keeps, what the Builder gets back, and the record of it.
// outcome: extracted | killed | destroyed (the self-destruct) | mia | bailed
function finish(run, outcome, now) {
  run.status = outcome;
  const items = Object.values(run.inv.items);
  let kept;
  if (outcome === 'extracted') kept = items;
  else if (outcome === 'bailed') kept = [];
  else kept = items.filter((it) => run.inv.secure.placed[it.uid]);
  const stolen = {};
  for (const it of kept) if (it.vaultQty > 0) stolen[it.item] = (stolen[it.item] || 0) + it.vaultQty;
  const minutes = (now - run.startedAt) / 60_000;
  return {
    outcome,
    kept: kept.map((it) => ({ item: it.item, qty: it.qty, fih: outcome === 'extracted' && minutes >= 4 && it.item !== 'keycard' })),
    lost: items.filter((it) => !kept.includes(it)).map((it) => ({ item: it.item, qty: it.qty })),
    stolen, // vault goods the Builder loses for good
    value: value(kept),
    heatPeak: run.heat,
    destroyed: run.destroyed.length,
    // The pouch goes home with you; die and it's lost. Bailing out early keeps what you brought.
    pouch: outcome === 'extracted' ? { ...run.pouch } : outcome === 'bailed' ? { ...run.pouchStart } : {},
    deepest: run.deepest || (run.breached ? 1 : 0),
    seconds: Math.round((now - run.startedAt) / 1000),
  };
}

module.exports = {
  ITEMS,
  STARTER_POUCH,
  STARTER_VEST,
  LAUNCHER_ROUNDS,
  LAUNCHER_GAP_MS,
  GRENADE_HEAT,
  TURRET_REACH,
  LAND_MAX,
  DEFENCE_TYPES,
  FACILITIES,
  SECURITY,
  EXTRACTS,
  HEAT_LEVELS,
  HEAT_EVENTS,
  SHIP_COOLDOWN_MS,
  RAID_COOLDOWN_MS,
  VAULT_EXPOSED,
  ALARM_COST,
  ALARM_HEAT,
  ALARM_COOLDOWN_MS,
  DRILL_SECONDS,
  BAIL_WINDOW_MS,
  FENCE_RATE,
  ROOM,
  TILE,
  FLOOR_DEPTH,
  MAX_FLOORS,
  SITE_PIECES,
  VENT_SECONDS,
  WAVE_MS,
  rng,
  Grid,
  generateLayout,
  rollTable,
  heatLevel,
  value,
  startRun,
  briefing,
  inventoryView,
  addHeat,
  report,
  heatTick,
  extractStates,
  landingProblem,
  land,
  defencesLeft,
  shipBack,
  floorsOf,
  selfDestructSeconds,
  stage,
  doorOpen,
  destroy,
  enterDoor,
  ventStart,
  ventStop,
  ventFinish,
  waveTick,
  reachFloor,
  openContainer,
  closeContainer,
  containerView,
  revealed,
  publicItem,
  take,
  drop,
  stow,
  pouchAdd,
  startingPouch,
  looseView,
  wearVest,
  useStart,
  useStop,
  useFinish,
  pickUp,
  fireGrenade,
  useKeycard,
  drillStart,
  drillStop,
  drillFinish,
  extractStart,
  extractStop,
  extractFinish,
  finish,
};
