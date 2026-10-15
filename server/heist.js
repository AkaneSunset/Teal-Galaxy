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
  medkit: { name: 'Trauma kit', cat: 'medical', size: [1, 1], stack: 2, value: 80, rarity: 'common' },
};

// Rarer items get more weight at higher security tiers (tier 1 = x1).
const RARITY_BOOST = { common: 0, uncommon: 0.25, rare: 0.6, epic: 1.0, legendary: 1.5 };

// --- Facilities --------------------------------------------------------------------------

// What each facility makes into its vault, every `every` galaxy ticks (5 s), up to `cap`.
const FACILITIES = {
  refinery: {
    name: 'Mining Refinery',
    bias: 'material',
    makes: [
      { item: 'alloy', every: 1, cap: 40 },
      { item: 'isotope', every: 6, cap: 10 },
      { item: 'exotic', every: 60, cap: 2 },
    ],
  },
  lab: {
    name: 'Research Outpost',
    bias: 'plan',
    makes: [
      { item: 'drive', every: 12, cap: 4 },
      { item: 'blueprint', every: 36, cap: 2 },
    ],
  },
  spire: {
    name: 'Data Spire',
    bias: 'intel',
    makes: [
      { item: 'shard', every: 6, cap: 10 },
      { item: 'dossier', every: 24, cap: 4 },
    ],
  },
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
const EXTRACTS = {
  shuttle: { name: 'Shuttle Pad', countdown: 20, loud: true },
  lift: { name: 'Service Lift', countdown: 8, needs: 'keycard' },
  pod: { name: 'Escape Pod', countdown: 5, loud: true, opensAfter: 3 * 60_000, oneUse: true },
};
const FREEZE_LEFT_MS = 5 * 60_000; // extract states freeze with this long left
const BAIL_WINDOW_MS = 120_000;
const BACKPACK = [6, 4];
const SECURE_CASE = [2, 2];
const CONTAINER_GRIDS = { locker: [3, 3], crate: [4, 3], desk: [3, 2], rack: [3, 3], vault: [5, 4] };
const SEARCH_MS = { common: 400, uncommon: 600, rare: 900, epic: 1200, legendary: 1500 };
const FENCE_RATE = 0.5;

// Loot tables per container. [item, weight, qtyMin, qtyMax]
const TABLES = {
  locker: { rolls: [1, 3], none: 2, entries: [['scrap', 6, 1, 6], ['medkit', 3, 1, 1], ['circuit', 3, 1, 1], ['wafer', 1, 1, 1]] },
  crate: { rolls: [2, 4], none: 1, entries: [['scrap', 5, 2, 10], ['alloy', 4, 1, 4], ['circuit', 3, 1, 1], ['isotope', 1, 1, 2], ['medkit', 1, 1, 1]] },
  desk: { rolls: [1, 3], none: 2, entries: [['wafer', 3, 1, 2], ['shard', 2, 1, 1], ['circuit', 2, 1, 1], ['art', 0.6, 1, 1]] },
  rack: { rolls: [1, 3], none: 1, entries: [['shard', 4, 1, 1], ['circuit', 4, 1, 1], ['dossier', 1, 1, 1], ['drive', 0.5, 1, 1]] },
  vault: { rolls: [1, 2], none: 0, entries: [['wafer', 3, 1, 3], ['art', 2, 1, 1], ['exotic', 0.6, 1, 1], ['drive', 0.6, 1, 1]] },
};
const CONTAINERS_BY_RING = { perimeter: ['locker', 'crate'], interior: ['desk', 'rack', 'crate', 'locker'] };

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

// A facility is a grid of rooms joined by doors. The entrance is on the south edge; the vault is
// the room furthest from it, behind a locked door. Every other room must be reachable without
// the vault, so the keycard that opens it can always be found; seeds that fail are re-rolled.
function generateLayout(seed, tier, type) {
  for (let attempt = 0; attempt < 50; attempt++) {
    const layout = tryLayout((seed + attempt * 7919) >>> 0, tier, type);
    if (layout) return layout;
  }
  throw new Error('no valid layout');
}

function tryLayout(seed, tier, type) {
  const r = rng(seed);
  const [W, H] = SECURITY[tier].grid;
  const id = (x, y) => y * W + x;
  const rooms = [];
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) rooms.push({ id: id(x, y), x, y, pos: [x * ROOM, y * ROOM] });
  const neighbours = (n) => {
    const { x, y } = rooms[n];
    return [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].filter(([a, b]) => a >= 0 && b >= 0 && a < W && b < H).map(([a, b]) => id(a, b));
  };
  const entrance = id(Math.floor(W / 2), H - 1);

  // Random spanning tree from the entrance, then a few loops so there is more than one way round.
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
  let vault = 0;
  for (const room of rooms) if (depth[room.id] > depth[vault] || (depth[room.id] === depth[vault] && room.id > vault)) vault = room.id;
  if (vault === entrance) return null;

  // Validation: everything but the vault reachable without going through it.
  const reach = bfs(entrance, (n) => (n === vault ? [] : adj(n, vault)));
  if (rooms.some((room) => room.id !== vault && reach[room.id] === undefined)) return null;

  for (const room of rooms) {
    room.depth = depth[room.id];
    room.ring = room.id === vault ? 'core' : room.depth <= 1 ? 'perimeter' : 'interior';
  }
  const doorList = edges.map(([a, b]) => ({ a, b, locked: a === vault || b === vault }));

  // Containers sit in room corners (doors are mid-wall, so corners never block one).
  const corners = [[-4.6, -4.6], [4.6, -4.6], [-4.6, 4.6], [4.6, 4.6]];
  const containers = [];
  for (const room of rooms) {
    if (room.id === entrance) continue;
    const spots = r.shuffle(corners.slice());
    const types = room.ring === 'core' ? ['vault', 'vault', 'vault'] : Array.from({ length: r.int(1, 2) }, () => r.pick(CONTAINERS_BY_RING[room.ring]));
    types.forEach((t, i) => containers.push({ id: `c${containers.length}`, room: room.id, type: t, pos: spots[i], grid: CONTAINER_GRIDS[t] }));
  }

  // Extracts: the Shuttle Pad outside the entrance airlock, a Service Lift in the far perimeter,
  // and an Escape Pod somewhere in the interior.
  const extracts = [{ id: 'shuttle', kind: 'shuttle', room: entrance, pos: [0, ROOM / 2 + 6] }];
  const far = rooms.filter((room) => room.id !== vault && room.id !== entrance && room.y <= 1).sort((a, b) => b.depth - a.depth || a.id - b.id);
  const liftRoom = far[0] || rooms.find((room) => room.id !== vault && room.id !== entrance);
  extracts.push({ id: 'lift', kind: 'lift', room: liftRoom.id, pos: [0, 0] });
  const podRooms = rooms.filter((room) => room.depth >= 2 && room.id !== vault && room.id !== liftRoom.id);
  if (podRooms.length) extracts.push({ id: 'pod', kind: 'pod', room: r.pick(podRooms).id, pos: [0, 0] });

  // Guards patrol short loops of rooms; turrets cover the vault.
  const guards = [];
  const guardRooms = rooms.filter((room) => room.id !== entrance && room.depth >= 1);
  for (let i = 0; i < SECURITY[tier].guards; i++) {
    let at = r.pick(guardRooms).id;
    const route = [at];
    for (let s = 0; s < 3; s++) {
      const next = adj(at, vault).filter((n) => n !== entrance);
      if (!next.length) break;
      at = r.pick(next);
      route.push(at);
    }
    guards.push({ id: `g${i}`, route });
  }
  const turrets = [];
  for (let i = 0; i < SECURITY[tier].turrets; i++) turrets.push({ id: `t${i}`, room: vault, pos: i === 0 ? [0, -5.5] : [5.5, 0] });

  return { seed, tier, type, room: ROOM, cols: W, rows: H, rooms, doors: doorList, entrance, vault, containers, extracts, guards, turrets };
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

// Starts a raid on a facility. `facility` is the building object in galaxy state; the exposed
// part of its vault moves into escrow so the Builder can't ship what raiders are stealing.
function startRun({ facility, facilityName, pilot, seed, now, lootSeed }) {
  const tier = facility.security || 1;
  const layout = generateLayout(seed, tier, facility.type);
  const def = FACILITIES[facility.type];
  const r = rng(lootSeed >>> 0);

  // Vault goods go into the vault room's containers; the rest of the loot is rolled.
  const escrow = {};
  for (const [item, qty] of Object.entries(facility.vault || {})) {
    const take = Math.ceil(qty * VAULT_EXPOSED);
    if (take > 0) escrow[item] = take;
  }
  const contents = {};
  for (const c of layout.containers) contents[c.id] = c.type === 'vault' ? [] : rollTable(TABLES[c.type], tier, def.bias, r).flatMap((s) => stacks(s.item, s.qty));
  const vaultBoxes = layout.containers.filter((c) => c.type === 'vault');
  let i = 0;
  for (const [item, qty] of Object.entries(escrow)) for (const s of stacks(item, qty)) contents[vaultBoxes[i++ % vaultBoxes.length].id].push({ ...s, vaultQty: s.qty });
  for (const c of vaultBoxes) contents[c.id].push(...rollTable(TABLES.vault, tier, def.bias, r).flatMap((s) => stacks(s.item, s.qty)));
  // One keycard, always somewhere outside the vault.
  const keyBox = r.pick(layout.containers.filter((c) => c.type !== 'vault'));
  contents[keyBox.id].push({ item: 'keycard', qty: 1 });

  // Lay each container's items into its grid; anything that doesn't fit isn't there.
  let uid = 1;
  const boxes = {};
  for (const c of layout.containers) {
    const grid = new Grid(c.grid[0], c.grid[1]);
    const items = [];
    const sorted = contents[c.id].sort((a, b) => ITEMS[b.item].size[0] * ITEMS[b.item].size[1] - ITEMS[a.item].size[0] * ITEMS[a.item].size[1]);
    for (const s of sorted) {
      const rect = grid.findFree(ITEMS[s.item].size);
      if (!rect) {
        if (s.vaultQty) escrow[s.item] -= s.vaultQty; // stays in deep storage
        continue;
      }
      // vaultQty: how many of these came from the Builder's vault (the rest is ordinary loot).
      const it = { uid: `i${uid++}`, item: s.item, qty: s.qty, vaultQty: s.vaultQty || 0 };
      grid.place(it.uid, rect);
      items.push(it);
    }
    boxes[c.id] = { grid, items, searchedAt: null, revealAt: {} };
  }
  for (const [item, qty] of Object.entries(escrow)) {
    if (qty <= 0) delete escrow[item];
    else facility.vault[item] -= qty;
  }
  facility.escrow = escrow;

  return {
    id: `run-${seed.toString(36)}`,
    pilot,
    facilityName,
    tier,
    layout,
    startedAt: now,
    endsAt: now + SECURITY[tier].minutes * 60_000,
    heat: 0,
    heatFrom: {}, // event -> last ms counted
    heatClock: now,
    drill: null,
    vaultOpen: false,
    open: null, // container being searched
    boxes,
    inv: { backpack: new Grid(...BACKPACK), secure: new Grid(...SECURE_CASE), items: {} },
    extract: null, // {id, since}
    usedExtracts: [],
    frozen: null,
    status: 'live',
  };
}

// The part of a run the raider's app is allowed to know at the start: no container contents.
function briefing(run, now) {
  return {
    id: run.id,
    facility: run.facilityName,
    tier: run.tier,
    layout: run.layout,
    remaining: Math.max(0, run.endsAt - now),
    heat: run.heat,
    level: heatLevel(run.heat),
    vaultOpen: run.vaultOpen,
    extracts: extractStates(run, now),
    inventory: inventoryView(run),
    backpack: BACKPACK,
    secure: SECURE_CASE,
  };
}

function inventoryView(run) {
  const out = [];
  for (const [gridName, grid] of [['backpack', run.inv.backpack], ['secure', run.inv.secure]])
    for (const [uid, rect] of Object.entries(grid.placed)) out.push({ ...run.inv.items[uid], grid: gridName, rect });
  return out;
}

function addHeat(run, amount) {
  const before = heatLevel(run.heat);
  run.heat = Math.min(100, run.heat + amount);
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
  const changed = gain > 0 && addHeat(run, gain);
  if (!run.frozen && run.endsAt - now <= FREEZE_LEFT_MS) run.frozen = extractStates(run, now);
  return changed;
}

function extractStates(run, now) {
  if (run.frozen) return run.frozen;
  const level = heatLevel(run.heat);
  const out = {};
  for (const ex of run.layout.extracts) {
    const def = EXTRACTS[ex.kind];
    let open = true;
    let why = '';
    if (def.oneUse && run.usedExtracts.includes(ex.id)) [open, why] = [false, 'used'];
    else if (def.opensAfter && now - run.startedAt < def.opensAfter) [open, why] = [false, `opens ${Math.ceil((def.opensAfter - (now - run.startedAt)) / 1000)} s`];
    else if (ex.kind === 'pod' && level >= 3) [open, why] = [false, 'sealed by Lockdown'];
    out[ex.id] = { open, why, countdown: def.countdown * (level >= 4 ? 2 : 1), needs: def.needs || null };
  }
  return out;
}

function findHeld(run, item) {
  return Object.values(run.inv.items).find((it) => it.item === item);
}

function openContainer(run, cid, now) {
  const box = run.boxes[cid];
  if (!box) return fail('no such container');
  const c = run.layout.containers.find((x) => x.id === cid);
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
  return { uid: it.uid, item: it.item, qty: it.qty, name: def.name, cat: def.cat, rarity: def.rarity, size: def.size, value: def.value };
}

function take(run, uid, to, now) {
  const box = run.open && run.boxes[run.open];
  if (!box) return fail('open a container first');
  const it = box.items.find((x) => x.uid === uid);
  if (!it) return fail('not in this container');
  if (!(box.revealAt[uid] <= now)) return fail('still searching');
  const def = ITEMS[it.item];
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

function use(run, uid) {
  const it = run.inv.items[uid];
  if (!it || ITEMS[it.item].cat !== 'medical') return fail('nothing to use');
  it.qty -= 1;
  if (it.qty <= 0) {
    run.inv.backpack.remove(uid);
    run.inv.secure.remove(uid);
    delete run.inv.items[uid];
  }
  return { ok: true, heal: 50 };
}

function useKeycard(run) {
  if (run.vaultOpen) return fail('the vault is already open');
  if (!findHeld(run, 'keycard')) return fail('you need an access keycard');
  run.vaultOpen = true;
  return { ok: true };
}

function drillStart(run, now) {
  if (run.vaultOpen) return fail('the vault is already open');
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
  run.vaultOpen = true;
  return { ok: true };
}

function extractStart(run, id, now) {
  const ex = run.layout.extracts.find((e) => e.id === id);
  if (!ex) return fail('no such extract');
  const st = extractStates(run, now)[id];
  if (!st.open) return fail(`${EXTRACTS[ex.kind].name} is closed (${st.why})`);
  if (st.needs && !findHeld(run, st.needs)) return fail(`${EXTRACTS[ex.kind].name} needs an access keycard`);
  if (!run.extract || run.extract.id !== id) run.extract = { id, since: now, countdown: st.countdown };
  return { ok: true, countdown: run.extract.countdown, loud: !!EXTRACTS[ex.kind].loud };
}

function extractStop(run) {
  run.extract = null;
  return { ok: true };
}

// The raider says the countdown ran out while they stood in the zone. The server checks the time.
function extractFinish(run, now) {
  if (!run.extract) return fail('not extracting');
  if (now - run.extract.since < run.extract.countdown * 1000 - 250) return fail('countdown not finished');
  const ex = run.layout.extracts.find((e) => e.id === run.extract.id);
  const def = EXTRACTS[ex.kind];
  if (def.needs) {
    // The lift eats one keycard.
    const card = findHeld(run, def.needs);
    if (!card) return fail(`${def.name} needs an access keycard`);
    card.qty -= 1;
    if (card.qty <= 0) {
      run.inv.backpack.remove(card.uid);
      run.inv.secure.remove(card.uid);
      delete run.inv.items[card.uid];
    }
  }
  if (def.oneUse) run.usedExtracts.push(ex.id);
  return { ok: true, via: def.name };
}

// Ends a run: what the pilot keeps, what the Builder gets back, and the record of it.
// outcome: extracted | killed | mia | bailed
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
    seconds: Math.round((now - run.startedAt) / 1000),
  };
}

module.exports = {
  ITEMS,
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
  openContainer,
  closeContainer,
  containerView,
  revealed,
  publicItem,
  take,
  drop,
  stow,
  use,
  useKeycard,
  drillStart,
  drillStop,
  drillFinish,
  extractStart,
  extractStop,
  extractFinish,
  finish,
};
