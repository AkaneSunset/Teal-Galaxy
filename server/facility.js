// Facility Battles: a campaign game mode, team against team on foot inside an outpost facility,
// about 10 minutes. The planet's holder defends; 4v4 to 8v8, empty slots filled with AI troopers of
// that side. Each match plays one of four rule sets, picked at random when it starts:
//   King of the Hill: score while your team alone holds the hill, which moves every 60 seconds.
//   Domination: hold 3 control points; held points score over time.
//   Team Deathmatch: first to the kill target, or the most kills when time runs out.
//   Capture the Flag: bring the enemy flag to your base 3 times, or lead on captures at the end.
// Each side shares a reinforcement count (12 per slot): every respawn costs one, and a side with
// none left and everyone down loses. Pilots fight with Pick 10 loadouts (classes built from 10 points of weapons,
// attachments, perks and equipment, kept on the pilot and shared with every mode that uses them)
// and earn kill streaks by kills without dying. The facility has doors that open for whoever comes
// near, defender turrets that defenders can repair, and a power plant attackers can hack to open
// locked shortcut doors. Power weapons come from front-supply drops.
//
// Simulated here on the server in 2D (x and z in metres over a SIZE x SIZE map, (0, 0) at a
// corner), like Sector Defense: pilots move on their own screens and report where they are and
// every shot (a ray from the eye); the server decides what each shot hits, with walls and closed
// doors stopping it, runs the AI, and keeps the score. In memory only.

const F = require('./factions');
const W = require('./war');

const SIZE = 80;
const TEAM_MIN = 4; // a side is filled with AI up to this many...
const TEAM_MAX = 8; // ...and no side has more than this
const TICK_MS = 100;
const STEP_S = 0.1;
const SNAPSHOT_MS = 100;
const END_KEEP_MS = 10_000;
const MATCH_S = 600;
const REINFORCEMENTS = 12; // per side for every slot on it (48 at 4v4, 96 at 8v8)...
const FORTRESS_EXTRA = 12; // ...and a fortress world's holder gets an extra wave of them
const RESPAWN_S = 5;
const HP = 100;
const SHIELD = 50;
const SHIELD_DELAY_S = 4;
const SHIELD_RATE = 25;
const RADIUS = 0.45; // a body's
const HEIGHT = 1.8;
const EYE = 1.6;
const HEAD_Y = 1.5; // hits above this are headshots
const HEADSHOT = 1.5;
const MOVES_PER_S = 30;
const SHOTS_PER_S = 20;
const USES_PER_S = 10;
const WALK = 7.5; // metres a second a pilot may move between reports (sprint, plus slack)
const DOOR_R = 2.5; // a door opens while someone stands this close
const USE_R = 2.5; // to repair a turret or hack the power plant
const USE_GAP_S = 0.6; // holding the use key: a gap this long and the progress is lost
const REPAIR_S = 4;
const HACK_S = 6;
const PICKUP_R = 1.6;
const FLAG_R = 1.6;
const FLAG_RETURN_S = 20;
const SPOT_S = 1.5; // firing without a suppressor shows you on the enemy's map this long
const CALL_S = 3; // an AI trooper calling a target shows it to its side this long
const SUPPLY_EVERY_S = 90; // front-supply drops with a power weapon, this often

// --- Rule sets ---------------------------------------------------------------------------------

const RULES = {
  koth: { name: 'King of the Hill', text: 'Hold the hill alone to score. It moves every 60 seconds.', target: 150, hillS: 60, hillR: 6 },
  domination: { name: 'Domination', text: 'Hold the 3 control points. Each held point scores 1 every 2 seconds.', target: 250, pointR: 5, captureS: 5, rate: 0.5 },
  tdm: { name: 'Team Deathmatch', text: 'First to 50 kills, or the most kills when time runs out.', target: 50 },
  ctf: { name: 'Capture the Flag', text: "Bring the enemy's flag to your base 3 times. Your own flag must be home.", target: 3 },
};
const RULE_IDS = Object.keys(RULES);

// --- Pick 10 ------------------------------------------------------------------------------------

// Every item costs one of a class's 10 points. `slot`: primary or secondary weapon, attachment
// (on the primary, up to 3), perk (up to 3), equipment.
const WEAPONS = {
  rifle: { name: 'Assault rifle', slot: 'primary', damage: 28, gap: 0.1, range: 90, mag: 30, reserve: 150, reload: 2.0 },
  smg: { name: 'SMG', slot: 'primary', damage: 20, gap: 0.07, range: 45, mag: 32, reserve: 160, reload: 1.7, speed: 1.05 },
  shotgun: { name: 'Shotgun', slot: 'primary', damage: 14, pellets: 8, spread: 0.06, gap: 0.8, range: 18, mag: 6, reserve: 30, reload: 2.6 },
  sniper: { name: 'Sniper rifle', slot: 'primary', damage: 95, gap: 1.2, range: 200, mag: 5, reserve: 25, reload: 2.8, speed: 0.92 },
  lmg: { name: 'LMG', slot: 'primary', damage: 26, gap: 0.09, range: 90, mag: 80, reserve: 160, reload: 4.0, speed: 0.88 },
  pistol: { name: 'Pistol', slot: 'secondary', damage: 24, gap: 0.22, range: 50, mag: 12, reserve: 48, reload: 1.4 },
  launcher: { name: 'Launcher', slot: 'secondary', damage: 150, splash: 4, gap: 1.2, range: 120, mag: 1, reserve: 2, reload: 2.5 },
  // Power weapons: only from supply drops, never in a class.
  railgun: { name: 'Railgun', slot: 'power', damage: 150, gap: 1.5, range: 200, mag: 4, reserve: 0, reload: 0, pierce: true },
  rockets: { name: 'Rocket launcher', slot: 'power', damage: 220, splash: 5, gap: 1.0, range: 150, mag: 3, reserve: 0, reload: 0 },
};
const ATTACHMENTS = {
  scope: { name: 'Scope', text: 'Zooms in; 50% more range' },
  extmag: { name: 'Extended mag', text: '50% bigger magazine' },
  fastmag: { name: 'Fast mag', text: 'Reloads 40% faster' },
  suppressor: { name: 'Suppressor', text: "Firing doesn't show you on the enemy's map" },
};
const PERKS = {
  lightweight: { name: 'Lightweight', text: 'Move 12% faster' },
  armor: { name: 'Armor', text: '25 more shield' },
  ghost: { name: 'Ghost', text: "Hidden from Sensor Arrays and AI troopers' calls" },
  scavenger: { name: 'Scavenger', text: 'Kills refill your ammo' },
  hardline: { name: 'Hardline', text: 'Kill streaks need one kill fewer' },
};
const EQUIPMENT = {
  frag: { name: 'Frag grenade', text: '2 grenades (G)', count: 2 },
  stim: { name: 'Stim', text: '2 stims: heal 60 at once (H)', count: 2 },
};
const POINTS = 10;

// The classes everyone has; pilots build up to CUSTOM_MAX more of their own.
const DEFAULT_CLASSES = {
  assault: { name: 'Assault', items: ['rifle', 'scope', 'extmag', 'fastmag', 'pistol', 'lightweight', 'armor', 'scavenger', 'frag', 'stim'] },
  cqb: { name: 'Close Quarters', items: ['smg', 'extmag', 'fastmag', 'suppressor', 'pistol', 'lightweight', 'ghost', 'hardline', 'frag', 'stim'] },
  marksman: { name: 'Marksman', items: ['sniper', 'scope', 'extmag', 'fastmag', 'pistol', 'armor', 'ghost', 'hardline', 'frag', 'stim'] },
  heavy: { name: 'Heavy', items: ['lmg', 'extmag', 'fastmag', 'launcher', 'armor', 'scavenger', 'hardline', 'frag', 'stim'] },
};
const CUSTOM_MAX = 3;

// --- Kill streaks -------------------------------------------------------------------------------

// Earned by kills without dying (kept until used, even after dying), used with the streak keys.
// `mark`: it needs a spot on the map (where the crosshair meets the ground).
const STREAKS = {
  sensor: { name: 'Sensor Array', kills: 3, text: "Shows every enemy on your side's map for 20 seconds", seconds: 20 },
  drop: { name: 'Supply Drop', kills: 4, text: 'A power weapon drops from orbit where you mark', mark: true, delay: 4 },
  barrage: { name: 'Orbital Barrage', kills: 5, text: 'Naval gunships shell the area you mark', mark: true, delay: 3, shells: 8, every: 0.5, spread: 6, radius: 3, damage: 90 },
  gunship: { name: 'Gunship', kills: 7, text: 'A gunship patrols the facility and guns down enemies for 30 seconds', seconds: 30, every: 1, damage: 30 },
  emp: { name: 'Localized EMP', kills: 10, text: "Scrambles the enemy's map for 30 seconds and destroys their active streaks", seconds: 30 },
  nuke: { name: 'Tactical Nuke', kills: 25, text: 'Ten seconds, then everyone dies and your side wins', delay: 10 },
};
const STREAK_IDS = Object.keys(STREAKS);

// --- Maps ---------------------------------------------------------------------------------------

// Hand-made layouts on a SIZE x SIZE map. Attackers come in from the south (low z), the defenders
// hold the north. Boxes are [x, z, width, depth, height], centred on (x, z).
//   walls: walls (3 m) and low cover (1.2 m); doors: [x, z, width, depth, locked] (a locked door is
//   a shortcut the power plant opens); turrets: the defenders'; plant: the power plant;
//   spawns: per side; hills: King of the Hill's, in order; points: Domination's A, B, C;
//   flags: each side's base; holds: where defending AI troopers hold the choke points;
//   drops: where front-supply drops land.
const SPAWNS_A = [[34, 4], [40, 4], [46, 4], [37, 7], [43, 7], [31, 7], [49, 7], [40, 9]];
const SPAWNS_D = SPAWNS_A.map(([x, z]) => [x, SIZE - z]);
const LAYOUTS = {
  compound: {
    name: 'Compound',
    walls: [
      [34.25, 36, 8.5, 1, 3], [45.75, 36, 8.5, 1, 3], [34.25, 52, 8.5, 1, 3], [45.75, 52, 8.5, 1, 3],
      [30, 44, 1, 16, 3], [50, 39.5, 1, 7, 3], [50, 48.5, 1, 7, 3], [40, 40, 4, 1, 1.2], [40, 48, 4, 1, 1.2],
      [20, 30, 6, 1, 1.2], [60, 30, 6, 1, 1.2], [20, 58, 6, 1, 1.2], [60, 58, 6, 1, 1.2],
      [15, 44, 3, 3, 3], [65, 44, 3, 3, 3], [40, 20, 10, 1, 1.2], [40, 66, 10, 1, 1.2],
      [28, 12, 1, 8, 3], [52, 12, 1, 8, 3], [28, 70, 1, 8, 3], [52, 70, 1, 8, 3],
    ],
    doors: [[40, 36, 3, 1, false], [40, 52, 3, 1, false], [50, 44, 1, 2, true]],
    turrets: [[30, 62], [50, 62]],
    plant: [62, 50],
    hills: [[40, 44], [20, 44], [60, 44], [40, 26], [40, 60]],
    points: [[20, 44], [40, 44], [60, 44]],
    flags: { a: [40, 10], d: [40, 70] },
    holds: [[40, 56], [35, 58], [45, 58], [40, 38]],
    drops: [[25, 44], [55, 44]],
  },
  foundry: {
    name: 'Foundry',
    walls: [
      [10, 40, 1, 20, 3], [24, 34.25, 1, 8.5, 3], [24, 45.75, 1, 8.5, 3], [12.75, 30, 5.5, 1, 3], [21.25, 30, 5.5, 1, 3], [12.75, 50, 5.5, 1, 3], [21.25, 50, 5.5, 1, 3],
      [70, 40, 1, 20, 3], [56, 34.25, 1, 8.5, 3], [56, 45.75, 1, 8.5, 3], [67.25, 30, 5.5, 1, 3], [58.75, 30, 5.5, 1, 3], [67.25, 50, 5.5, 1, 3], [58.75, 50, 5.5, 1, 3],
      [34, 40, 3, 3, 3], [46, 40, 3, 3, 3], [32, 28, 4, 1, 1.2], [48, 28, 4, 1, 1.2], [32, 52, 4, 1, 1.2], [48, 52, 4, 1, 1.2],
      [40, 18, 8, 1, 1.2], [40, 62, 8, 1, 1.2],
    ],
    doors: [[24, 40, 1, 3, false], [17, 30, 3, 1, false], [17, 50, 3, 1, false], [56, 40, 1, 3, false], [63, 30, 3, 1, false], [63, 50, 3, 1, true]],
    turrets: [[33, 66], [47, 66]],
    plant: [63, 40],
    hills: [[40, 40], [17, 40], [63, 40], [40, 24], [40, 56]],
    points: [[17, 40], [40, 40], [63, 40]],
    flags: { a: [40, 8], d: [40, 72] },
    holds: [[17, 54], [63, 54], [40, 58], [40, 46]],
    drops: [[40, 30], [40, 50]],
  },
  reactor: {
    name: 'Reactor',
    walls: [
      [40, 40, 8, 8, 3],
      [28, 26, 8, 1, 3], [24, 30, 1, 8, 3], [52, 26, 8, 1, 3], [56, 30, 1, 8, 3],
      [28, 54, 8, 1, 3], [24, 50, 1, 8, 3], [52, 54, 8, 1, 3], [56, 50, 1, 8, 3],
      [40, 26, 6, 1, 1.2],
      [32.75, 66, 11.5, 1, 3], [47.25, 66, 11.5, 1, 3], [27, 73, 1, 14, 3], [53, 68.75, 1, 5.5, 3], [53, 77.25, 1, 5.5, 3],
      [16, 20, 4, 4, 3], [64, 20, 4, 4, 3], [12, 56, 3, 6, 1.2], [68, 56, 3, 6, 1.2],
    ],
    doors: [[40, 66, 3, 1, false], [53, 73, 1, 3, true]],
    turrets: [[35, 61], [45, 61]],
    plant: [62, 70],
    hills: [[40, 30], [40, 50], [30, 40], [50, 40], [40, 58]],
    points: [[16, 40], [40, 49], [64, 40]],
    flags: { a: [40, 8], d: [40, 72] },
    holds: [[40, 62], [36, 58], [44, 58], [40, 52]],
    drops: [[16, 30], [64, 30]],
  },
  proving: {
    name: 'Proving Grounds',
    generic: true,
    walls: [
      [20, 20, 4, 4, 3], [60, 20, 4, 4, 3], [20, 60, 4, 4, 3], [60, 60, 4, 4, 3], [40, 40, 6, 6, 3],
      [40, 24, 10, 1, 1.2], [40, 56, 10, 1, 1.2], [24, 40, 1, 10, 1.2], [56, 40, 1, 10, 1.2],
      [30, 32, 3, 3, 3], [50, 32, 3, 3, 3], [30, 48, 3, 3, 3], [50, 48, 3, 3, 3],
    ],
    doors: [],
    turrets: [],
    plant: null,
    hills: [[40, 32], [40, 48], [24, 26], [56, 54], [16, 40], [64, 40]],
    points: [[16, 40], [40, 50], [64, 40]],
    flags: { a: [40, 8], d: [40, 72] },
    holds: [[40, 62], [30, 64], [50, 64]],
    drops: [[40, 32], [40, 48]],
  },
};
const FACTION_LAYOUTS = Object.keys(LAYOUTS).filter((k) => !LAYOUTS[k].generic);
const GENERIC_LAYOUTS = Object.keys(LAYOUTS).filter((k) => LAYOUTS[k].generic);

// A layout, mirrored east to west when `mirror`, as a map: [x, z] spots and boxes flipped.
function buildMap(layoutId, mirror = false, name = null) {
  const L = LAYOUTS[layoutId];
  const fx = (x) => (mirror ? SIZE - x : x);
  const spot = (p) => (p ? [fx(p[0]), p[1]] : null);
  return {
    id: `${layoutId}${mirror ? '-m' : ''}`,
    layout: layoutId,
    name: name || L.name,
    walls: L.walls.map(([x, z, w, d, h]) => [fx(x), z, w, d, h]),
    doors: L.doors.map(([x, z, w, d, locked]) => [fx(x), z, w, d, locked]),
    turrets: L.turrets.map(spot),
    plant: spot(L.plant),
    spawns: { a: SPAWNS_A.map(spot), d: SPAWNS_D.map(spot) },
    hills: L.hills.map(spot),
    points: L.points.map(spot),
    flags: { a: spot(L.flags.a), d: spot(L.flags.d) },
    holds: L.holds.map(spot),
    drops: L.drops.map(spot),
  };
}

// A planet's map rotation for its defending faction: three maps of that faction (its own takes on
// the layouts, the same every match on that planet) and the generic maps.
function rotation(planetId, defender) {
  const h = W.hash(`facility/${planetId}/${defender || 'militia'}`);
  const word = defender && F.FACTIONS[defender] ? F.FACTIONS[defender].name.split(' ')[0] : 'Militia';
  const own = FACTION_LAYOUTS.map((id, i) => buildMap(id, Boolean((h >>> i) & 1), `${word} ${LAYOUTS[id].name}`));
  return [...own, ...GENERIC_LAYOUTS.map((id) => buildMap(id))];
}

function fail(reason) {
  return { ok: false, reason };
}

const r1 = (x) => Math.round(x * 10) / 10;
const clamp = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
const num = (v) => typeof v === 'number' && Number.isFinite(v);
const other = (side) => (side === 'a' ? 'd' : 'a');

function random(state) {
  state.s = (state.s + 0x6d2b79f5) >>> 0;
  let t = state.s;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// --- Classes --------------------------------------------------------------------------------------

// Whether `items` make a class: known items, one primary and one secondary at most, attachments only
// with a primary, at most 3 attachments and 3 perks, nothing twice, at most POINTS in all, and a weapon.
function checkClass(items) {
  if (!Array.isArray(items)) return fail('a class is a list of items');
  if (new Set(items).size !== items.length) return fail('each item can only be taken once');
  if (items.length > POINTS) return fail(`a class has ${POINTS} points`);
  const kind = (i) => (WEAPONS[i] && WEAPONS[i].slot !== 'power' ? WEAPONS[i].slot : ATTACHMENTS[i] ? 'attachment' : PERKS[i] ? 'perk' : EQUIPMENT[i] ? 'equipment' : null);
  const bad = items.find((i) => !kind(i));
  if (bad !== undefined) return fail(`no such item: ${bad}`);
  const count = (k) => items.filter((i) => kind(i) === k).length;
  if (count('primary') > 1) return fail('one primary weapon at most');
  if (count('secondary') > 1) return fail('one secondary weapon at most');
  if (count('primary') + count('secondary') === 0) return fail('a class needs a weapon');
  if (count('attachment') && !count('primary')) return fail('attachments go on a primary weapon');
  if (count('attachment') > 3) return fail('three attachments at most');
  if (count('perk') > 3) return fail('three perks at most');
  return { ok: true };
}

// A pilot's custom classes, kept on their record (G.pilot): loadout_save puts one in slot 0-2.
function saveClass(rec, slot, name, items) {
  if (!Number.isInteger(slot) || slot < 0 || slot >= CUSTOM_MAX) return fail('no such class slot');
  const ok = checkClass(items);
  if (!ok.ok) return ok;
  rec.loadouts ||= [];
  rec.loadouts[slot] = { name: String(name || `Custom ${slot + 1}`).slice(0, 24), items: items.slice() };
  return { ok: true };
}

// --- Geometry -------------------------------------------------------------------------------------

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

// What stops shots and bodies: the walls and the closed doors (3 m tall).
// What stops shots and bodies: the walls, the closed doors (3 m tall), and whatever breakables
// (blast doors, a reactor: { box, hp, side }) still stand.
function blockers(f) {
  const out = f.map.walls.slice();
  f.map.doors.forEach(([x, z, w, d], i) => {
    if (!f.doors[i]) out.push([x, z, w, d, 3]);
  });
  for (const br of f.breakables || []) if (br.hp > 0) out.push(br.box);
  return out;
}

// A breakable the shot from `o` to `end` stops on at `wall` metres (of `range`), if it's the other side's.
function breakableAt(f, b, o, end, range, wall) {
  for (const br of f.breakables || []) {
    if (br.hp <= 0 || br.side === b.side) continue;
    const t = segBox(o, end, br.box);
    if (t !== null && Math.abs(t * range - wall) < 1e-6) return br;
  }
  return null;
}

// Damage to a breakable; destroyed, it stops blocking (and f.onBreak hears of it).
function hurtBreakable(f, br, damage, by) {
  if (br.hp <= 0 || f.result) return;
  br.hp = Math.max(0, br.hp - damage);
  if (br.hp > 0) return;
  f.blockers = blockers(f);
  f.nav = navGrid(f);
  f.flows.clear();
  f.onBreak?.(f, br, by);
}

function blocked(f, a, b) {
  let t = 1;
  for (const box of f.blockers) {
    const h = segBox(a, b, box);
    if (h !== null && h < t) t = h;
  }
  return t;
}

function clear(f, a, b) {
  return blocked(f, a, b) >= 1;
}

function boxNear(box, x, z) {
  const [cx, cz, w, dd] = box;
  const qx = clamp(x, cx - w / 2, cx + w / 2);
  const qz = clamp(z, cz - dd / 2, cz + dd / 2);
  return { r: Math.hypot(x - qx, z - qz), x: qx, z: qz };
}

function pushOut(f, x, z, r = RADIUS) {
  for (const box of f.blockers) {
    const q = boxNear(box, x, z);
    if (q.r >= r) continue;
    if (q.r > 1e-6) {
      x = q.x + ((x - q.x) / q.r) * r;
      z = q.z + ((z - q.z) / q.r) * r;
      continue;
    }
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
  return [clamp(x, 0.5, f.w - 0.5), clamp(z, 0.5, f.d - 0.5)];
}

// Where the ray (o, dir) passes a body (a standing capsule): the distance along it and the height
// it meets it at, or null.
function rayBody(o, dir, b, range) {
  const len2 = dir.x * dir.x + dir.z * dir.z;
  if (len2 < 1e-9) return null;
  const t = ((b.x - o.x) * dir.x + (b.z - o.z) * dir.z) / len2;
  if (t < 0) return null;
  const miss = Math.hypot(o.x + dir.x * t - b.x, o.z + dir.z * t - b.z);
  if (miss > RADIUS + 0.2) return null;
  const y = o.y + dir.y * t;
  if (y < -0.1 || y > HEIGHT + 0.15) return null;
  const along = t * Math.sqrt(len2 + dir.y * dir.y);
  return along <= range ? { along, y } : null;
}

// --- The navigation grid (AI troopers) -------------------------------------------------------------

// 1 m cells; a cell is open if a body can stand at its centre. Doors that aren't locked shut count
// as open (they open for whoever comes near).
function navGrid(f) {
  const open = new Uint8Array(f.w * f.d);
  const boxes = f.map.walls.concat(f.map.doors.filter((d, i) => d[4] && !f.doors[i]).map(([x, z, w, d]) => [x, z, w, d, 3]), (f.breakables || []).filter((br) => br.hp > 0).map((br) => br.box));
  for (let j = 0; j < f.d; j++) {
    for (let i = 0; i < f.w; i++) {
      const x = i + 0.5;
      const z = j + 0.5;
      open[j * f.w + i] = boxes.every((b) => boxNear(b, x, z).r >= RADIUS + 0.05) ? 1 : 0;
    }
  }
  return open;
}

// The grid cell at (x, z) on a map `w` wide and `d` deep.
const cellOf = (x, z, w = SIZE, d = SIZE) => clamp(Math.floor(z), 0, d - 1) * w + clamp(Math.floor(x), 0, w - 1);

// Steps from every cell to the goal cell (8 neighbours, no corner cutting); -1 where it can't reach.
function flowTo(f, goal) {
  const GW = f.w;
  const GD = f.d;
  const key = goal;
  const hit = f.flows.get(key);
  if (hit) return hit;
  const dist = new Int32Array(GW * GD).fill(-1);
  const q = new Int32Array(GW * GD);
  let head = 0;
  let tail = 0;
  // From the nearest open cell to the goal.
  let g = goal;
  if (!f.nav[g]) {
    let best = -1;
    let bd = Infinity;
    const gx = g % GW;
    const gz = Math.floor(g / GW);
    for (let dz = -3; dz <= 3; dz++)
      for (let dx = -3; dx <= 3; dx++) {
        const x = gx + dx;
        const z = gz + dz;
        if (x < 0 || z < 0 || x >= GW || z >= GD || !f.nav[z * GW + x]) continue;
        if (dx * dx + dz * dz < bd) [best, bd] = [z * GW + x, dx * dx + dz * dz];
      }
    if (best < 0) return dist;
    g = best;
  }
  dist[g] = 0;
  q[tail++] = g;
  while (head < tail) {
    const c = q[head++];
    const cx = c % GW;
    const cz = Math.floor(c / GW);
    for (let dz = -1; dz <= 1; dz++)
      for (let dx = -1; dx <= 1; dx++) {
        if (!dx && !dz) continue;
        const x = cx + dx;
        const z = cz + dz;
        if (x < 0 || z < 0 || x >= GW || z >= GD) continue;
        const n = z * GW + x;
        if (!f.nav[n] || dist[n] >= 0) continue;
        if (dx && dz && (!f.nav[cz * GW + x] || !f.nav[z * GW + cx])) continue;
        dist[n] = dist[c] + 1;
        q[tail++] = n;
      }
  }
  f.flows.set(key, dist);
  return dist;
}

// --- A match ---------------------------------------------------------------------------------------

// A new match on `planet` (planetName) between `attacker` and `defender` (factions; null: the
// militia). `rule` and `map` (an index into rotation()) are picked from `seed` unless given.
// `fortress`: the defender holds a fortress world (an extra wave of reinforcements).
function newFacility({ id = 'f1', planet, planetName = '', attacker, defender = null, seed = 1, rule = null, map = null, fortress = false, now = Date.now(), speed = 1 }) {
  const rng = { s: seed >>> 0 };
  const maps = rotation(planet, defender);
  const m = map !== null && maps[map] ? maps[map] : maps[Math.floor(random(rng) * maps.length) % maps.length];
  const r = RULES[rule] ? rule : RULE_IDS[Math.floor(random(rng) * RULE_IDS.length) % RULE_IDS.length];
  const f = {
    id,
    planet,
    planetName,
    factions: { a: attacker, d: defender },
    seed,
    rng,
    speed,
    rule: r,
    map: m,
    w: SIZE,
    d: SIZE,
    startedAt: now,
    t: 0,
    nextId: 1,
    bodies: new Map(), // id -> body (pilots by name, AI troopers by 'ai<n>')
    size: 0, // slots a side: reinforcements come with each
    reinforcements: { a: 0, d: fortress ? FORTRESS_EXTRA : 0 },
    score: { a: 0, d: 0 },
    kills: { a: 0, d: 0 },
    doors: m.doors.map(() => false), // open?
    hacked: false,
    plant: { progress: 0, by: null, at: -100 },
    turrets: m.turrets.map(([x, z]) => ({ x, z, hp: 400, maxHp: 400, cd: 0, repair: 0, by: null, at: -100 })),
    hill: 0,
    points: m.points.map(([x, z]) => ({ x, z, owner: null, progress: 0 })), // progress: -1 (attackers') .. 1 (defenders')
    flags: { a: { home: m.flags.a, x: m.flags.a[0], z: m.flags.a[1], carrier: null, droppedAt: null }, d: { home: m.flags.d, x: m.flags.d[0], z: m.flags.d[1], carrier: null, droppedAt: null } },
    pickups: new Map(),
    nextSupply: SUPPLY_EVERY_S / 2,
    active: [], // streaks running: { kind, side, by, until, x, z, next, left }
    spotted: { a: new Map(), d: new Map() }, // what each side's map shows: body id -> until
    grenades: [],
    shots: [],
    feed: [],
    result: null, // 'a', 'd', or 'draw'
    how: null,
  };
  f.blockers = blockers(f);
  f.nav = navGrid(f);
  f.flows = new Map();
  balance(f); // AI troopers on both sides until pilots come
  return f;
}

// The class a body fights with: a default class id, or 'custom:<slot>' from `loadouts`.
function classOf(id, loadouts = []) {
  if (DEFAULT_CLASSES[id]) return { id, ...DEFAULT_CLASSES[id] };
  const m = /^custom:(\d)$/.exec(String(id));
  const c = m && loadouts?.[Number(m[1])];
  return c && checkClass(c.items).ok ? { id, name: c.name, items: c.items } : { id: 'assault', ...DEFAULT_CLASSES.assault };
}

// A body's weapons and kit from its class (and a fresh magazine for each).
function equip(b, cls) {
  const has = (i) => cls.items.includes(i);
  b.cls = cls.id;
  b.className = cls.name;
  b.items = cls.items.slice();
  b.guns = {};
  for (const w of cls.items.filter((i) => WEAPONS[i])) {
    const def = WEAPONS[w];
    const primary = def.slot === 'primary';
    const mag = Math.round(def.mag * (primary && has('extmag') ? 1.5 : 1));
    b.guns[def.slot] = { weapon: w, mag, magMax: mag, reserve: def.reserve, reloadS: def.reload * (primary && has('fastmag') ? 0.6 : 1), range: def.range * (primary && has('scope') ? 1.5 : 1), suppressed: primary && has('suppressor') };
  }
  b.weapon = b.guns.primary ? 'primary' : 'secondary';
  b.frags = has('frag') ? EQUIPMENT.frag.count : 0;
  b.stims = has('stim') ? EQUIPMENT.stim.count : 0;
  b.shieldMax = SHIELD + (has('armor') ? 25 : 0);
  b.speed = (has('lightweight') ? 1.12 : 1) * (WEAPONS[b.guns.primary?.weapon]?.speed || 1);
}

function newBody(f, { id, name, side, ai = false, cls = 'assault', loadouts = [], fodder = false }) {
  const b = { id, name, side, ai, fodder, present: true, x: 0, z: 0, yaw: 0, hp: HP, shield: SHIELD, hitAt: -100, alive: false, respawnAt: 0, kills: 0, deaths: 0, caps: 0, streak: 0, earned: [], moveT: 0, lastShot: -100, reloadUntil: 0, want: cls, loadouts, cd: 0, path: null };
  equip(b, classOf(cls, loadouts));
  f.bodies.set(id, b);
  spawn(f, b);
  return b;
}

// Back in at one of the side's spawns (the one furthest from the enemy), with the class it chose.
// A mode can choose the spawns (f.spawnSpots) and change the body as it comes in (f.onSpawn: an
// elite trooper, a fodder bot).
function spawn(f, b) {
  const enemies = [...f.bodies.values()].filter((o) => o.alive && o.side !== b.side);
  let best = null;
  let bd = -1;
  for (const [x, z] of f.spawnSpots ? f.spawnSpots(f, b) : f.map.spawns[b.side]) {
    const near = enemies.reduce((m, o) => Math.min(m, Math.hypot(o.x - x, o.z - z)), 999) + random(f.rng) * 4;
    if (near > bd) [best, bd] = [[x, z], near];
  }
  equip(b, classOf(b.want, b.loadouts));
  Object.assign(b, { alive: true, x: best[0], z: best[1], hp: HP, hpMax: HP, shield: b.shieldMax, hitAt: -100, streak: 0, reloadUntil: 0, moveT: f.t, path: null, power: null, damageMul: 1, elite: false });
  b.yaw = b.side === 'd' ? 0 : Math.PI; // facing the other side's end
  f.onSpawn?.(f, b);
}

// A pilot joins `side`; an AI trooper of that side makes room if the side is full.
function addPilot(f, name, side, loadouts = [], cls = 'assault') {
  let b = f.bodies.get(name);
  if (b) {
    b.present = true;
    b.loadouts = loadouts;
    return b;
  }
  b = newBody(f, { id: name, name, side, cls, loadouts });
  balance(f);
  return b;
}

function removePilot(f, name) {
  const b = f.bodies.get(name);
  if (!b) return;
  b.present = false;
  dropFlag(f, b);
  b.alive = false;
  b.respawnAt = Infinity;
  balance(f);
}

const team = (f, side) => [...f.bodies.values()].filter((b) => b.present && b.side === side && !b.fodder);
const humans = (f, side) => team(f, side).filter((b) => !b.ai);

// Both sides at the same size: the bigger human side's, between TEAM_MIN and TEAM_MAX, AI troopers
// making up the rest. Troopers leave (the dead first) when pilots join.
function balance(f) {
  const size = clamp(Math.max(humans(f, 'a').length, humans(f, 'd').length), TEAM_MIN, TEAM_MAX);
  if (size > f.size) {
    for (const side of ['a', 'd']) f.reinforcements[side] += (size - f.size) * REINFORCEMENTS;
    f.size = size;
  }
  for (const side of ['a', 'd']) {
    let t = team(f, side);
    while (t.length < size) {
      const n = f.nextId++;
      newBody(f, { id: `ai${n}`, name: `Trooper ${n}`, side, ai: true, cls: ['assault', 'heavy', 'cqb'][n % 3] });
      t = team(f, side);
    }
    const ais = t.filter((b) => b.ai).sort((x, y) => Number(x.alive) - Number(y.alive));
    while (t.length > size && ais.length) {
      const b = ais.shift();
      dropFlag(f, b);
      f.bodies.delete(b.id);
      t = team(f, side);
    }
  }
}

// --- Moving and fighting ----------------------------------------------------------------------------

function move(f, name, msg) {
  const b = f.bodies.get(name);
  if (!b?.present || !b.alive || b.ai || !num(msg.x) || !num(msg.z)) return { ok: true, quiet: true };
  const dt = Math.max(0.05, f.t - b.moveT);
  const dx = msg.x - b.x;
  const dz = msg.z - b.z;
  const far = Math.hypot(dx, dz);
  const most = WALK * b.speed * dt + 1;
  const k = far > most ? most / far : 1;
  [b.x, b.z] = pushOut(f, b.x + dx * k, b.z + dz * k);
  if (num(msg.yaw)) b.yaw = msg.yaw;
  b.moveT = f.t;
  touch(f, b);
  return { ok: true };
}

// What a body takes by walking over it: power weapons, and flags.
function touch(f, b) {
  for (const u of [...f.pickups.values()]) {
    if (b.ai || Math.hypot(u.x - b.x, u.z - b.z) > PICKUP_R) continue;
    f.pickups.delete(u.id);
    const def = WEAPONS[u.weapon];
    b.power = { weapon: u.weapon, mag: def.mag, magMax: def.mag, reserve: 0, reloadS: 0, range: def.range };
    if (!b.ai) b.weapon = 'power';
    f.feed.push({ text: `${b.name} took the ${def.name}`, side: b.side });
  }
  if (f.rule !== 'ctf') return;
  const own = f.flags[b.side];
  const theirs = f.flags[other(b.side)];
  if (!theirs.carrier && Math.hypot(theirs.x - b.x, theirs.z - b.z) <= FLAG_R) {
    theirs.carrier = b.id;
    theirs.droppedAt = null;
    f.feed.push({ text: `${b.name} has the ${sideName(f, other(b.side))} flag` });
  }
  const home = own.x === own.home[0] && own.z === own.home[1] && !own.carrier;
  if (!own.carrier && !home && own.droppedAt !== null && Math.hypot(own.x - b.x, own.z - b.z) <= FLAG_R) {
    [own.x, own.z, own.droppedAt] = [own.home[0], own.home[1], null];
    f.feed.push({ text: `${b.name} returned the ${sideName(f, b.side)} flag` });
  }
  if (theirs.carrier === b.id && home && Math.hypot(own.home[0] - b.x, own.home[1] - b.z) <= FLAG_R + 0.5) {
    theirs.carrier = null;
    [theirs.x, theirs.z] = theirs.home;
    f.score[b.side] += 1;
    b.caps += 1;
    f.feed.push({ text: `${b.name} captured the flag: ${f.score[b.side]} of ${RULES.ctf.target}` });
  }
}

function dropFlag(f, b) {
  for (const s of ['a', 'd']) {
    const fl = f.flags[s];
    if (fl.carrier !== b.id) continue;
    fl.carrier = null;
    [fl.x, fl.z] = [r1(b.x), r1(b.z)];
    fl.droppedAt = f.t;
    f.feed.push({ text: `${b.name} dropped the ${sideName(f, s)} flag` });
  }
}

function sideName(f, side) {
  const fac = f.factions[side];
  return fac && F.FACTIONS[fac] ? F.FACTIONS[fac].name : 'militia';
}

function gunOf(b) {
  return b.weapon === 'power' ? b.power : b.guns[b.weapon];
}

// facility_switch: primary, secondary or the power weapon.
function switchTo(f, name, msg) {
  const b = f.bodies.get(name);
  if (!b?.alive) return { ok: true, quiet: true };
  const w = String(msg.weapon);
  if (w === 'power' ? !b.power : !b.guns[w]) return fail(`no ${w} weapon`);
  b.weapon = w;
  b.reloadUntil = 0;
  return { ok: true };
}

// facility_reload: the magazine refills from the reserve after the weapon's reload time.
function reload(f, name) {
  const b = f.bodies.get(name);
  const g = b?.alive && gunOf(b);
  if (!g || g.mag >= g.magMax || g.reserve <= 0 || b.reloadUntil > f.t) return { ok: true, quiet: true };
  b.reloadUntil = f.t + g.reloadS;
  b.reloading = g;
  return { ok: true };
}

function finishReload(f, b) {
  if (!b.reloading || f.t < b.reloadUntil) return;
  const g = b.reloading;
  const n = Math.min(g.magMax - g.mag, g.reserve);
  g.mag += n;
  g.reserve -= n;
  b.reloading = null;
}

// The first thing the ray hits: a body of the other side or a turret, before `wall` metres.
function firstHit(f, b, o, dir, range, wall, skip = new Set()) {
  let best = null;
  let at = Math.min(range, wall);
  for (const t of f.bodies.values()) {
    if (!t.alive || t.side === b.side || skip.has(t)) continue;
    const h = rayBody(o, dir, t, range);
    if (h && h.along < at) [best, at] = [{ body: t, y: h.y }, h.along];
  }
  if (b.side === 'a') {
    for (const tu of f.turrets) {
      if (tu.hp <= 0 || skip.has(tu)) continue;
      const h = rayBody(o, dir, { x: tu.x, z: tu.z }, range);
      if (h && h.y <= 1.5 && h.along < at) [best, at] = [{ turret: tu }, h.along];
    }
  }
  return { best, at };
}

// facility_fire: a shot along (dx, dy, dz) from the pilot's eye (or `y`, jumping). The server
// checks the weapon's rate and magazine, and what's in the way.
function fire(f, name, msg) {
  const b = f.bodies.get(name);
  if (!b?.present || !b.alive || f.result || b.ai) return { ok: true, quiet: true };
  if (![msg.dx, msg.dy, msg.dz].every(num)) return { ok: true, quiet: true };
  const n = Math.hypot(msg.dx, msg.dy, msg.dz) || 1;
  const dir = { x: msg.dx / n, y: msg.dy / n, z: msg.dz / n };
  const o = { x: b.x, y: num(msg.y) ? clamp(msg.y, 0, 3.5) : EYE, z: b.z };
  return shoot(f, b, o, dir);
}

function shoot(f, b, o, dir) {
  const g = gunOf(b);
  if (!g) return fail('no weapon');
  const def = WEAPONS[g.weapon];
  if (b.reloadUntil > f.t) return { ok: true, quiet: true, reason: 'reloading' };
  if (f.t - b.lastShot < def.gap * 0.8) return { ok: true, quiet: true };
  if (g.mag <= 0) return fail('empty: reload (R)');
  g.mag -= 1;
  b.lastShot = f.t;
  if (!g.suppressed) spot(f, b, SPOT_S);
  if (b.weapon === 'power' && g.mag <= 0) {
    b.power = null;
    b.weapon = b.guns.primary ? 'primary' : 'secondary';
  }
  let hits = 0;
  const pellets = def.pellets || 1;
  for (let k = 0; k < pellets; k++) {
    // Shotgun pellets spread in a fixed ring round the aim.
    let d = dir;
    if (pellets > 1) {
      const a = (k / pellets) * Math.PI * 2;
      const s = k === 0 ? 0 : def.spread;
      const side = { x: -dir.z, y: 0, z: dir.x };
      d = { x: dir.x + side.x * Math.cos(a) * s, y: dir.y + Math.sin(a) * s, z: dir.z + side.z * Math.cos(a) * s };
      const dn = Math.hypot(d.x, d.y, d.z);
      d = { x: d.x / dn, y: d.y / dn, z: d.z / dn };
    }
    const end = { x: o.x + d.x * g.range, y: o.y + d.y * g.range, z: o.z + d.z * g.range };
    const wall = blocked(f, o, end) * g.range;
    if (def.pierce) {
      // The railgun goes through everyone in its way (not walls).
      const skip = new Set();
      for (let i = 0; i < 6; i++) {
        const { best } = firstHit(f, b, o, d, g.range, wall, skip);
        if (!best) break;
        skip.add(best.body || best.turret);
        hits += hurtTarget(f, best, def.damage * b.damageMul, b, g.weapon);
      }
      const br = breakableAt(f, b, o, end, g.range, wall);
      if (br) hurtBreakable(f, br, def.damage * b.damageMul, b);
      f.shots.push([b.id, r1(o.x), r1(o.z), r1(o.x + d.x * wall), r1(o.z + d.z * wall), g.weapon]);
      continue;
    }
    const { best, at } = firstHit(f, b, o, d, g.range, wall);
    const hx = o.x + d.x * at;
    const hz = o.z + d.z * at;
    if (k === 0) f.shots.push([b.id, r1(o.x), r1(o.z), r1(hx), r1(hz), g.weapon]);
    if (def.splash) {
      const back = Math.max(0, at - 0.3);
      blast(f, { x: o.x + d.x * back, y: o.y + d.y * back, z: o.z + d.z * back }, def.splash, def.damage * b.damageMul, b, g.weapon, false);
      hits += best ? 1 : 0;
    } else if (best) hits += hurtTarget(f, best, def.damage * b.damageMul * (best.y > HEAD_Y ? HEADSHOT : 1), b, g.weapon);
    else if (at < g.range) {
      const br = breakableAt(f, b, o, end, g.range, at);
      if (br) hurtBreakable(f, br, def.damage * b.damageMul, b);
    }
  }
  return { ok: true, hits };
}

function hurtTarget(f, t, damage, by, weapon) {
  if (t.turret) {
    hurtTurret(f, t.turret, damage, by);
    return 1;
  }
  hurt(f, t.body, damage, by, weapon);
  return 1;
}

// An explosion at `at`: everyone of the other side within `r` it can reach (cover stops it unless
// `fromAbove`), and the attackers' blasts hit turrets too.
function blast(f, at, r, damage, by, weapon, fromAbove) {
  for (const t of [...f.bodies.values()]) {
    if (!t.alive || t.side === by.side) continue;
    const d = Math.hypot(t.x - at.x, t.z - at.z);
    if (d > r + RADIUS) continue;
    if (!fromAbove && !clear(f, at, { x: t.x, y: 1.0, z: t.z })) continue;
    hurt(f, t, damage * (d < 1 ? 1 : Math.max(0.2, 1 - (0.8 * d) / r)), by, weapon);
  }
  if (by.side === 'a') for (const tu of f.turrets) if (tu.hp > 0 && Math.hypot(tu.x - at.x, tu.z - at.z) <= r + 0.6) hurtTurret(f, tu, damage * 0.6, by);
  // Explosives are what breaks blast doors best: double damage to them.
  for (const br of f.breakables || []) if (br.hp > 0 && br.side !== by.side && boxNear(br.box, at.x, at.z).r <= r) hurtBreakable(f, br, damage * 2, by);
}

function hurtTurret(f, tu, damage, by) {
  if (tu.hp <= 0) return;
  tu.hp = Math.max(0, tu.hp - damage);
  if (tu.hp <= 0) f.feed.push({ text: `${by ? by.name : 'The attackers'} destroyed a defence turret` });
}

function hurt(f, t, damage, by, weapon = null) {
  if (!t.alive || f.result) return;
  t.hitAt = f.t;
  const s = Math.min(t.shield, damage);
  t.shield -= s;
  t.hp -= damage - s;
  if (t.hp > 0) return;
  kill(f, t, by, weapon);
}

function kill(f, t, by, weapon) {
  t.alive = false;
  t.hp = 0;
  t.deaths += 1;
  t.streak = 0;
  t.reloading = null;
  dropFlag(f, t);
  if (f.unlimited || f.reinforcements[t.side] > 0) {
    if (!f.unlimited) f.reinforcements[t.side] -= 1;
    t.respawnAt = f.t + (f.respawnS ?? RESPAWN_S);
  } else t.respawnAt = Infinity;
  if (by && by.side !== t.side) {
    by.kills += 1;
    f.kills[by.side] += 1;
    if (f.rule === 'tdm') f.score[by.side] += 1;
    if (by.alive) {
      by.streak += 1;
      const less = by.items.includes('hardline') ? 1 : 0;
      // A mode may give streaks to only some (f.streaksFor) or only some streaks (f.streakIds).
      const ids = !f.streaksFor || f.streaksFor(f, by) ? f.streakIds || STREAK_IDS : [];
      for (const s of ids) if (by.streak === STREAKS[s].kills - less) {
        by.earned.push(s);
        f.feed.push({ name: by.name, earned: s, text: `${by.name} earned a ${STREAKS[s].name}` });
      }
      if (by.items.includes('scavenger')) for (const g of Object.values(by.guns)) g.reserve = WEAPONS[g.weapon].reserve;
    }
  }
  f.onKill?.(f, t, by);
  if (!t.fodder) f.feed.push({ kill: [by ? by.name : null, t.name, weapon], text: by ? `${by.name} killed ${t.name}` : `${t.name} died` });
}

// Shows `b` on the other side's map for `s` seconds (Ghost hides it from calls, not from firing).
function spot(f, b, s) {
  const m = f.spotted[other(b.side)];
  m.set(b.id, Math.max(m.get(b.id) || 0, f.t + s));
}

// facility_throw: a frag grenade along (dx, dy, dz). It flies, stops at a wall or the ground, and
// bursts 2.2 seconds after the throw.
function throwFrag(f, name, msg) {
  const b = f.bodies.get(name);
  if (!b?.alive || ![msg.dx, msg.dy, msg.dz].every(num)) return { ok: true, quiet: true };
  if (b.frags <= 0) return fail('no grenades left');
  b.frags -= 1;
  const n = Math.hypot(msg.dx, msg.dy, msg.dz) || 1;
  f.grenades.push({ id: f.nextId++, by: b.id, side: b.side, x: b.x, y: EYE, z: b.z, vx: (msg.dx / n) * 16, vy: (msg.dy / n) * 16 + 2, vz: (msg.dz / n) * 16, fuse: 2.2, rest: false });
  return { ok: true };
}

// facility_stim: heal 60 at once.
function stim(f, name) {
  const b = f.bodies.get(name);
  if (!b?.alive) return { ok: true, quiet: true };
  if (b.stims <= 0) return fail('no stims left');
  b.stims -= 1;
  b.hp = Math.min(b.hpMax || HP, b.hp + 60);
  return { ok: true };
}

// facility_use, sent while the use key is held: defenders repair a destroyed turret, attackers hack
// the power plant (which opens the locked shortcut doors for good).
function use(f, name) {
  const b = f.bodies.get(name);
  if (!b?.alive) return { ok: true, quiet: true };
  return useBy(f, b, 0);
}

function useBy(f, b, dt) {
  if (b.side === 'd') {
    const tu = f.turrets.find((x) => x.hp < x.maxHp && Math.hypot(x.x - b.x, x.z - b.z) <= USE_R);
    if (!tu) return { ok: true, quiet: true };
    const gap = f.t - tu.at;
    if (tu.by !== b.id || gap > USE_GAP_S) tu.repair = 0;
    else tu.repair += dt || gap;
    tu.by = b.id;
    tu.at = f.t;
    if (tu.repair >= REPAIR_S) {
      [tu.hp, tu.repair] = [tu.maxHp, 0];
      f.feed.push({ text: `${b.name} repaired a turret` });
    }
    return { ok: true, repair: tu.repair / REPAIR_S };
  }
  const p = f.map.plant;
  if (!p || f.hacked || Math.hypot(p[0] - b.x, p[1] - b.z) > USE_R) return { ok: true, quiet: true };
  const pl = f.plant;
  const gap = f.t - pl.at;
  if (pl.by !== b.id || gap > USE_GAP_S) pl.progress = 0;
  else pl.progress += dt || gap;
  pl.by = b.id;
  pl.at = f.t;
  if (pl.progress >= HACK_S) {
    f.hacked = true;
    f.map.doors.forEach((d, i) => {
      if (d[4]) f.doors[i] = true;
    });
    f.blockers = blockers(f);
    f.nav = navGrid(f);
    f.flows.clear();
    f.feed.push({ text: `${b.name} hacked the power plant: the shortcut doors are open` });
  }
  return { ok: true, hack: pl.progress / HACK_S };
}

// facility_streak: use an earned kill streak (with a marked spot where it needs one).
function useStreak(f, name, msg) {
  const b = f.bodies.get(name);
  const s = String(msg.streak);
  if (!b || !STREAKS[s]) return fail('no such kill streak');
  const i = b.earned.indexOf(s);
  if (i < 0) return fail(`you haven't earned a ${STREAKS[s].name}`);
  const def = STREAKS[s];
  if (def.mark && !(num(msg.x) && num(msg.z))) return fail('mark a spot for it');
  b.earned.splice(i, 1);
  const x = clamp(num(msg.x) ? msg.x : b.x, 1, f.w - 1);
  const z = clamp(num(msg.z) ? msg.z : b.z, 1, f.d - 1);
  const side = b.side;
  if (s === 'emp') {
    f.active = f.active.filter((a) => a.side === side || a.kind === 'nuke' || a.kind === 'drop' || a.kind === 'barrage');
  }
  f.active.push({ kind: s, side, by: b.id, until: f.t + (def.seconds || def.delay || 0) + (def.shells ? def.shells * def.every : 0), x, z, next: f.t + (def.delay || 0), left: def.shells || 0 });
  f.feed.push({ text: `${b.name} called in a ${def.name}`, streak: s, side });
  return { ok: true };
}

function streaksStep(f) {
  for (const a of f.active) {
    const def = STREAKS[a.kind];
    const by = f.bodies.get(a.by) || { name: 'Orbital support', side: a.side, items: [] };
    if (a.kind === 'sensor') for (const t of f.bodies.values()) if (t.side !== a.side && t.alive && !t.items.includes('ghost')) spot(f, t, 0.5);
    if (a.kind === 'drop' && f.t >= a.next) {
      a.next = Infinity;
      const u = { id: f.nextId++, weapon: random(f.rng) < 0.5 ? 'railgun' : 'rockets', x: r1(a.x), z: r1(a.z) };
      [u.x, u.z] = pushOut(f, u.x, u.z, 0.6).map(r1);
      f.pickups.set(u.id, u);
      a.until = f.t;
    }
    if (a.kind === 'barrage' && f.t >= a.next && a.left > 0) {
      a.left -= 1;
      a.next = f.t + def.every;
      const r = random(f.rng) * def.spread;
      const ang = random(f.rng) * Math.PI * 2;
      const at = { x: a.x + Math.cos(ang) * r, y: 0.5, z: a.z + Math.sin(ang) * r };
      f.shots.push(['orbit', r1(at.x), r1(at.z), r1(at.x), r1(at.z), 'shell']);
      blast(f, at, def.radius, def.damage, by, 'barrage', true);
    }
    if (a.kind === 'gunship' && f.t >= a.next) {
      a.next = f.t + def.every;
      const targets = [...f.bodies.values()].filter((t) => t.alive && t.side !== a.side);
      if (targets.length) {
        const t = targets[Math.floor(random(f.rng) * targets.length) % targets.length];
        const hit = random(f.rng) < 0.5;
        f.shots.push(['gunship', r1(f.w / 2), r1(f.d / 2), r1(t.x), r1(t.z), hit ? 'hit' : 'miss']);
        if (hit) hurt(f, t, def.damage, by, 'gunship');
      }
    }
    if (a.kind === 'nuke' && f.t >= a.next && !f.result) {
      for (const t of f.bodies.values()) if (t.alive) [t.alive, t.hp] = [false, 0];
      f.feed.push({ text: 'Tactical Nuke' });
      [f.result, f.how] = [a.side, 'nuke'];
    }
  }
  f.active = f.active.filter((a) => f.t < a.until || (a.kind === 'barrage' && a.left > 0));
}

function grenadesStep(f, dt) {
  for (const gr of f.grenades) {
    gr.fuse -= dt;
    if (!gr.rest) {
      const from = { x: gr.x, y: gr.y, z: gr.z };
      gr.vy -= 9.8 * dt;
      const to = { x: gr.x + gr.vx * dt, y: gr.y + gr.vy * dt, z: gr.z + gr.vz * dt };
      const t = blocked(f, from, to);
      if (t < 1 || to.y <= 0.1) {
        const k = to.y <= 0.1 ? Math.min(t, (from.y - 0.1) / Math.max(1e-6, from.y - to.y)) : t;
        gr.x = from.x + (to.x - from.x) * Math.max(0, k - 0.05);
        gr.y = Math.max(0.1, from.y + (to.y - from.y) * Math.max(0, k - 0.05));
        gr.z = from.z + (to.z - from.z) * Math.max(0, k - 0.05);
        gr.rest = true;
      } else Object.assign(gr, to);
    }
    if (gr.fuse <= 0) {
      const by = f.bodies.get(gr.by) || { name: 'A grenade', side: gr.side, items: [] };
      f.shots.push([gr.by, r1(gr.x), r1(gr.z), r1(gr.x), r1(gr.z), 'frag']);
      blast(f, { x: gr.x, y: Math.max(0.3, gr.y), z: gr.z }, 5, 110, by, 'frag', false);
    }
  }
  f.grenades = f.grenades.filter((gr) => gr.fuse > 0);
}

// --- The AI troopers ---------------------------------------------------------------------------------

const AI = { damage: 14, reload: 0.35, range: 45, speed: 4.2 };
const FODDER_DAMAGE = 5;

// A body's yaw (as the game's cameras turn: 0 looks down -z) facing along (dx, dz).
const yawTo = (dx, dz) => Math.atan2(-dx, -dz);

// Where a trooper heads: attackers push the objective, defenders hold choke points (and go for
// what the rule needs them to).
function aiGoal(f, b) {
  const idx = Number(String(b.id).slice(2)) || 0;
  if (f.rule === 'koth') return f.map.hills[f.hill];
  if (f.rule === 'domination') {
    const mine = b.side === 'a' ? -1 : 1;
    const want = f.points.filter((p) => p.owner !== b.side);
    if (b.side === 'd' && idx % 2 === 0) {
      const held = f.points.filter((p) => p.owner === 'd');
      if (held.length) return [held[idx % held.length].x, held[idx % held.length].z];
    }
    const list = want.length ? want : f.points;
    const p = list.slice().sort((x, y) => Math.hypot(x.x - b.x, x.z - b.z) - Math.hypot(y.x - b.x, y.z - b.z) + (x.progress * mine - y.progress * mine))[0];
    return [p.x, p.z];
  }
  if (f.rule === 'ctf') {
    const theirs = f.flags[other(b.side)];
    const own = f.flags[b.side];
    if (theirs.carrier === b.id) return own.home;
    if (own.carrier || own.droppedAt !== null) {
      const c = own.carrier && f.bodies.get(own.carrier);
      return c ? [c.x, c.z] : [own.x, own.z];
    }
    if (b.side === 'd' && idx % 2 === 0) return f.map.holds[idx % f.map.holds.length];
    return [theirs.x, theirs.z];
  }
  // Team Deathmatch: defenders hold the choke points, attackers hunt the nearest enemy.
  if (b.side === 'd') return f.map.holds[idx % f.map.holds.length];
  const enemies = [...f.bodies.values()].filter((t) => t.alive && t.side !== b.side);
  const e = enemies.sort((x, y) => Math.hypot(x.x - b.x, x.z - b.z) - Math.hypot(y.x - b.x, y.z - b.z))[0];
  return e ? [e.x, e.z] : f.map.holds[0];
}

function aiStep(f, b, dt) {
  b.cd = Math.max(0, b.cd - dt);
  finishReload(f, b);
  // A visible enemy within range: call it for the side, and fire.
  const eye = { x: b.x, y: EYE, z: b.z };
  let target = null;
  let td = Infinity;
  for (const t of f.bodies.values()) {
    if (!t.alive || t.side === b.side) continue;
    const d = Math.hypot(t.x - b.x, t.z - b.z);
    if (d > AI.range || d >= td) continue;
    if (!clear(f, eye, { x: t.x, y: 1.2, z: t.z }) && !clear(f, eye, { x: t.x, y: EYE, z: t.z })) continue;
    [target, td] = [t, d];
  }
  // A mode can have troopers go for breakables first (boarders and a reactor in sight).
  const broke = f.breakFirst?.(f, b) && b.cd <= 0 && !b.fodder && shootBreakable(f, b, eye);
  if (target) {
    if (!target.items.includes('ghost')) spot(f, target, CALL_S);
    if (!broke) b.yaw = yawTo(target.x - b.x, target.z - b.z);
    if (b.cd <= 0) {
      b.cd = AI.reload;
      // Fodder bots are poor shots and hit softly.
      const hit = random(f.rng) < (0.45 - (0.25 * td) / AI.range) * (b.fodder ? 0.5 : 1);
      f.shots.push([b.id, r1(b.x), r1(b.z), r1(target.x), r1(target.z), hit ? 'hit' : 'miss']);
      spot(f, b, SPOT_S);
      if (hit) hurt(f, target, (b.fodder ? FODDER_DAMAGE : AI.damage) * b.damageMul, b, 'rifle');
    }
  }
  // Attackers' troopers shoot turrets that are in their way, and anyone's shoot the other side's
  // blast doors and reactor when they can see them.
  if (!target && b.cd <= 0 && !b.fodder) {
    const tu = b.side === 'a' && f.turrets.find((x) => x.hp > 0 && Math.hypot(x.x - b.x, x.z - b.z) < 30 && clear(f, eye, { x: x.x, y: 1.0, z: x.z }));
    if (tu) {
      b.cd = AI.reload;
      f.shots.push([b.id, r1(b.x), r1(b.z), r1(tu.x), r1(tu.z), 'hit']);
      hurtTurret(f, tu, AI.damage, b);
    }
    if (!tu) shootBreakable(f, b, eye);
  }
  // Defenders' troopers repair turrets on their way; attackers' hack the plant when they're at it.
  useBy(f, b, dt);
  // Move: along the flow field to the goal (holding still in a fight close to it).
  const goal = f.aiGoal ? f.aiGoal(f, b) : aiGoal(f, b);
  if (!goal) return;
  const gd = Math.hypot(goal[0] - b.x, goal[1] - b.z);
  const holding = gd < 3 && (f.holding ? f.holding(f, b) : b.side === 'd');
  if (target && (td < 15 || holding)) return;
  if (gd < 1.2) return;
  const flow = flowTo(f, cellOf(goal[0], goal[1], f.w, f.d));
  const c = cellOf(b.x, b.z, f.w, f.d);
  let next = null;
  let nd = flow[c] >= 0 ? flow[c] : Infinity;
  const cx = c % f.w;
  const cz = Math.floor(c / f.w);
  for (let dz = -1; dz <= 1; dz++)
    for (let dx = -1; dx <= 1; dx++) {
      const x = cx + dx;
      const z = cz + dz;
      if (x < 0 || z < 0 || x >= f.w || z >= f.d) continue;
      const v = flow[z * f.w + x];
      if (v >= 0 && v < nd) [next, nd] = [[x + 0.5, z + 0.5], v];
    }
  const to = next || goal;
  const h = Math.atan2(to[0] - b.x, to[1] - b.z);
  const step = Math.min(AI.speed * b.speed * dt, Math.hypot(to[0] - b.x, to[1] - b.z) + 0.2);
  [b.x, b.z] = pushOut(f, b.x + Math.sin(h) * step, b.z + Math.cos(h) * step);
  if (!target) b.yaw = yawTo(Math.sin(h), Math.cos(h));
  touch(f, b);
}

// A trooper fires at the nearest of the other side's breakables it can see within 30 m (the
// reactor first). True if it did.
function shootBreakable(f, b, eye) {
  const list = (f.breakables || []).filter((br) => br.hp > 0 && br.side !== b.side).sort((x, y) => (y.kind === 'reactor') - (x.kind === 'reactor'));
  for (const br of list) {
    const q = boxNear(br.box, b.x, b.z);
    if (q.r > 30) continue;
    // Aim a little short of its face, so the shot isn't stopped by the box itself.
    const k = Math.max(0, (q.r - 0.3) / Math.max(q.r, 1e-6));
    if (!clear(f, eye, { x: b.x + (q.x - b.x) * k, y: 1.0, z: b.z + (q.z - b.z) * k })) continue;
    b.cd = AI.reload;
    b.yaw = yawTo(q.x - b.x, q.z - b.z);
    f.shots.push([b.id, r1(b.x), r1(b.z), r1(q.x), r1(q.z), 'hit']);
    hurtBreakable(f, br, AI.damage * b.damageMul, b);
    return true;
  }
  return false;
}

// --- The simulation -------------------------------------------------------------------------------

function turretsStep(f, dt) {
  for (const tu of f.turrets) {
    tu.cd = Math.max(0, tu.cd - dt);
    if (tu.hp <= 0 || tu.cd > 0) continue;
    const at = { x: tu.x, y: 1.3, z: tu.z };
    let target = null;
    let td = 30;
    for (const t of f.bodies.values()) {
      if (!t.alive || t.side !== 'a') continue;
      const d = Math.hypot(t.x - tu.x, t.z - tu.z);
      if (d < td && clear(f, at, { x: t.x, y: 1.1, z: t.z })) [target, td] = [t, d];
    }
    if (!target) continue;
    tu.cd = 0.3;
    const hit = random(f.rng) < 0.6;
    f.shots.push(['turret', r1(tu.x), r1(tu.z), r1(target.x), r1(target.z), hit ? 'hit' : 'miss']);
    if (hit) hurt(f, target, 6, { name: 'A defence turret', side: 'd', items: [], alive: false }, 'turret');
  }
}

function doorsStep(f) {
  let changed = false;
  f.map.doors.forEach(([x, z, w, d, locked], i) => {
    if (locked && !f.hacked) return;
    const open = (locked && f.hacked) || [...f.bodies.values()].some((b) => b.alive && boxNear([x, z, w, d], b.x, b.z).r <= DOOR_R);
    if (open !== f.doors[i]) [f.doors[i], changed] = [open, true];
  });
  if (changed) f.blockers = blockers(f);
}

function objectivesStep(f, dt) {
  const inside = (x, z, r) => {
    const s = { a: 0, d: 0 };
    for (const b of f.bodies.values()) if (b.alive && Math.hypot(b.x - x, b.z - z) <= r) s[b.side] += 1;
    return s;
  };
  if (f.rule === 'koth') {
    const hill = Math.floor(f.t / RULES.koth.hillS) % f.map.hills.length;
    if (hill !== f.hill) {
      f.hill = hill;
      f.feed.push({ text: 'The hill has moved' });
    }
    const [x, z] = f.map.hills[f.hill];
    const s = inside(x, z, RULES.koth.hillR);
    if (s.a && !s.d) f.score.a += dt;
    if (s.d && !s.a) f.score.d += dt;
  }
  if (f.rule === 'domination') {
    for (const p of f.points) {
      const s = inside(p.x, p.z, RULES.domination.pointR);
      const push = s.a && !s.d ? -1 : s.d && !s.a ? 1 : 0;
      if (push) {
        p.progress = clamp(p.progress + (push * dt) / RULES.domination.captureS, -1, 1);
        const owner = p.progress <= -1 ? 'a' : p.progress >= 1 ? 'd' : p.owner && Math.sign(p.progress) === (p.owner === 'a' ? -1 : 1) ? p.owner : null;
        if (owner !== p.owner) {
          p.owner = owner;
          const name = 'ABC'[f.points.indexOf(p)];
          f.feed.push({ text: owner ? `${sideName(f, owner)} took point ${name}` : `Point ${name} is neutral` });
        }
      }
      if (p.owner) f.score[p.owner] += dt * RULES.domination.rate;
    }
  }
  if (f.rule === 'ctf') {
    for (const s of ['a', 'd']) {
      const fl = f.flags[s];
      const c = fl.carrier && f.bodies.get(fl.carrier);
      if (c) [fl.x, fl.z] = [r1(c.x), r1(c.z)];
      if (fl.droppedAt !== null && f.t - fl.droppedAt >= FLAG_RETURN_S) {
        [fl.x, fl.z, fl.droppedAt] = [fl.home[0], fl.home[1], null];
        f.feed.push({ text: `The ${sideName(f, s)} flag went back to its base` });
      }
    }
  }
}

function supplyStep(f) {
  if (f.t < f.nextSupply || !f.map.drops.length) return;
  f.nextSupply = f.t + SUPPLY_EVERY_S;
  const [x, z] = f.map.drops[Math.floor(random(f.rng) * f.map.drops.length) % f.map.drops.length];
  const u = { id: f.nextId++, weapon: random(f.rng) < 0.5 ? 'railgun' : 'rockets', x, z };
  f.pickups.set(u.id, u);
  f.feed.push({ text: `Front supply drop: a ${WEAPONS[u.weapon].name}` });
}

function decide(f) {
  if (f.result) return;
  const target = RULES[f.rule].target;
  for (const s of ['a', 'd']) {
    if (f.score[s] >= target) {
      [f.result, f.how] = [s, 'score'];
      return;
    }
  }
  // A side with no reinforcements left and nobody standing loses.
  for (const s of ['a', 'd']) {
    const t = team(f, s);
    if (t.length && f.reinforcements[s] <= 0 && t.every((b) => !b.alive)) {
      [f.result, f.how] = [other(s), 'wiped'];
      return;
    }
  }
  if (f.t >= MATCH_S) {
    const a = Math.floor(f.score.a);
    const d = Math.floor(f.score.d);
    [f.result, f.how] = [a > d ? 'a' : d > a ? 'd' : 'draw', 'time'];
  }
}

function tick(f, dt) {
  f.t += dt;
  for (const b of f.bodies.values()) {
    if (!b.present) continue;
    if (!b.alive && f.t >= b.respawnAt) spawn(f, b);
    if (!b.alive) continue;
    finishReload(f, b);
    if (b.shield < b.shieldMax && f.t - b.hitAt >= SHIELD_DELAY_S) b.shield = Math.min(b.shieldMax, b.shield + SHIELD_RATE * dt);
  }
  doorsStep(f);
  for (const b of [...f.bodies.values()]) if (b.ai && b.alive && !f.result) aiStep(f, b, dt);
  turretsStep(f, dt);
  grenadesStep(f, dt);
  streaksStep(f);
  objectivesStep(f, dt);
  supplyStep(f);
  for (const s of ['a', 'd']) for (const [id, until] of f.spotted[s]) if (until < f.t) f.spotted[s].delete(id);
  if (f.t - (f.flowsAt || 0) > 2) {
    f.flows.clear(); // the field to a moving target goes stale
    f.flowsAt = f.t;
  }
  decide(f);
}

function step(f, dt) {
  for (let left = dt; left > 1e-9 && !f.result; left -= STEP_S) tick(f, Math.min(STEP_S, left));
}

// --- What the pilots see ----------------------------------------------------------------------------

function frame(f) {
  const out = {
    match: f.id,
    t: r1(f.t),
    left: Math.max(0, Math.round(MATCH_S - f.t)),
    score: { a: Math.floor(f.score.a), d: Math.floor(f.score.d) },
    reinforcements: { ...f.reinforcements },
    bodies: [...f.bodies.values()].filter((b) => b.present).map((b) => [b.id, b.name, b.side, r1(b.x), r1(b.z), r1(b.yaw), Math.round(b.hp + b.shield), b.alive, b.ai, b.kills, b.deaths, b.weapon === 'power' && b.power ? b.power.weapon : b.guns[b.weapon]?.weapon || '', b.elite ? 1 : 0, b.fodder ? 1 : 0]),
    doors: f.doors.slice(),
    hacked: f.hacked,
    plant: f.map.plant ? Math.round((100 * f.plant.progress) / HACK_S) : null,
    turrets: f.turrets.map((t) => [Math.round(t.hp), Math.round((100 * t.repair) / REPAIR_S)]),
    hill: f.rule === 'koth' ? f.hill : null,
    points: f.rule === 'domination' ? f.points.map((p) => [p.owner, Math.round(p.progress * 100)]) : null,
    flags: f.rule === 'ctf' ? { a: [f.flags.a.x, f.flags.a.z, f.flags.a.carrier], d: [f.flags.d.x, f.flags.d.z, f.flags.d.carrier] } : null,
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

// One pilot's view of a frame: their own state, and their side's map (who it shows, and EMP).
function stateFor(f, fr, name) {
  const b = f.bodies.get(name);
  const side = b?.side || 'a';
  const emp = f.active.some((a) => a.kind === 'emp' && a.side !== side);
  const g = b && gunOf(b);
  return {
    type: 'facility_state',
    ...fr,
    spotted: emp ? [] : [...f.spotted[side].keys()],
    emp,
    me: b
      ? {
          side,
          hp: Math.round(b.hp),
          shield: Math.round(b.shield),
          shieldMax: b.shieldMax,
          alive: b.alive,
          respawnIn: b.alive || b.respawnAt === Infinity ? 0 : r1(b.respawnAt - f.t),
          out: !b.alive && b.respawnAt === Infinity,
          cls: b.cls,
          want: b.want,
          className: b.className,
          weapon: b.weapon,
          gun: g ? g.weapon : null,
          mag: g ? g.mag : 0,
          reserve: g ? g.reserve : 0,
          reloading: b.reloadUntil > f.t,
          guns: Object.fromEntries(Object.entries(b.guns).map(([k, v]) => [k, v.weapon])),
          power: b.power ? b.power.weapon : null,
          frags: b.frags,
          stims: b.stims,
          streak: b.streak,
          earned: b.earned.slice(),
          speed: b.speed,
          scope: b.items.includes('scope'),
          x: r1(b.x),
          z: r1(b.z),
        }
      : null,
  };
}

function joined(f, name) {
  const b = f.bodies.get(name);
  return {
    type: 'facility_joined',
    match: f.id,
    planet: f.planet,
    planetName: f.planetName,
    side: b.side,
    factions: f.factions,
    rule: f.rule,
    ruleName: RULES[f.rule].name,
    ruleText: RULES[f.rule].text,
    target: RULES[f.rule].target,
    size: f.w,
    depth: f.d,
    map: f.map,
    seconds: MATCH_S,
    hp: HP,
    weapons: WEAPONS,
    attachments: ATTACHMENTS,
    perks: PERKS,
    equipment: EQUIPMENT,
    points: POINTS,
    classes: DEFAULT_CLASSES,
    customMax: CUSTOM_MAX,
    streaks: STREAKS,
    start: [b.x, b.z],
  };
}

// --- The server's matches ------------------------------------------------------------------------------

// Facility Battles a server runs. `loadouts(name)`: a pilot's custom classes; `onEnd(f, winner,
// vsAi)` scores the result for the campaign and returns the points.
function createFacilities({ now = Date.now, speed = 1, send, changed, loadouts = () => [], onEnd = null }) {
  const matches = new Map();
  const conns = new Map();
  let nextId = 1;
  let ticks = 0;
  const timers = new Set();

  function start(planet, planetName, attacker, defender, opts = {}) {
    const n = nextId++;
    const f = newFacility({ id: `f${n}`, planet, planetName, attacker, defender, seed: (Date.now() ^ (n * 2654435761)) >>> 0, now: now(), speed, ...opts });
    matches.set(f.id, f);
    conns.set(f.id, new Map());
    return f;
  }

  function enlist(me, f, side) {
    if (me.facility && me.facility !== f.id) leave(me);
    addPilot(f, me.name, side, loadouts(me.name));
    conns.get(f.id).set(me.name, me);
    me.facility = f.id;
    send(me, joined(f, me.name));
    changed();
    return { ok: true, match: f.id };
  }

  function leave(me) {
    const f = me.facility && matches.get(me.facility);
    me.facility = null;
    if (!f) return { ok: true };
    if (conns.get(f.id)?.get(me.name) === me) {
      conns.get(f.id).delete(me.name);
      removePilot(f, me.name);
      // Nobody left: the match ends with no result.
      if (!f.result && ![...f.bodies.values()].some((b) => b.present && !b.ai)) [f.result, f.how] = ['draw', 'abandoned'];
      changed();
    }
    return { ok: true };
  }

  function handle(me, msg) {
    if (msg.type === 'facility_leave') return leave(me);
    const f = me.facility && matches.get(me.facility);
    if (!f || f.result || String(msg.match) !== f.id) return { ok: true, quiet: true };
    const t = Date.now();
    const key = msg.type === 'facility_move' ? 'moves' : msg.type === 'facility_use' ? 'uses' : 'shots';
    const cap = msg.type === 'facility_move' ? MOVES_PER_S : msg.type === 'facility_use' ? USES_PER_S : SHOTS_PER_S;
    me.facilityWindow ||= {};
    if (t - (me.facilityWindow[key + 'At'] || 0) >= 1000) [me.facilityWindow[key + 'At'], me.facilityWindow[key]] = [t, 0];
    if (++me.facilityWindow[key] > cap) return { ok: true, quiet: true };
    switch (msg.type) {
      case 'facility_move':
        return move(f, me.name, msg);
      case 'facility_fire':
        return fire(f, me.name, msg);
      case 'facility_reload':
        return reload(f, me.name);
      case 'facility_switch':
        return switchTo(f, me.name, msg);
      case 'facility_throw':
        return throwFrag(f, me.name, msg);
      case 'facility_stim':
        return stim(f, me.name);
      case 'facility_use':
        return use(f, me.name);
      case 'facility_streak':
        return useStreak(f, me.name, msg);
      case 'facility_class': {
        // The class to come back with (and at once, before the first spawn's been used).
        const b = f.bodies.get(me.name);
        if (!b) return { ok: true, quiet: true };
        b.loadouts = loadouts(me.name);
        b.want = classOf(msg.cls, b.loadouts).id;
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
    const how = { score: RULES[f.rule].name, wiped: 'no reinforcements left', time: 'time ran out', nuke: 'Tactical Nuke', abandoned: 'everyone left' }[f.how] || '';
    const text = f.how === 'abandoned' ? 'The match ended: everyone left' : winner ? `${F.FACTIONS[winner].name} won the match (${how}), ${Math.floor(f.score.a)} to ${Math.floor(f.score.d)}: +${pts} campaign points on ${f.planetName}` : `A draw (${how}), ${Math.floor(f.score.a)} to ${Math.floor(f.score.d)}: no campaign points`;
    const fr = frame(f);
    for (const [name, c] of conns.get(f.id)) {
      send(c, stateFor(f, fr, name));
      send(c, { type: 'facility_end', match: f.id, winner: f.result, won: f.bodies.get(name)?.side === f.result, text });
    }
    changed();
    const timer = setTimeout(() => {
      timers.delete(timer);
      matches.delete(f.id);
      for (const c of conns.get(f.id)?.values() || []) if (c.facility === f.id) c.facility = null;
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
  const ticker = setInterval(tickAll, TICK_MS);

  function running(planet) {
    return [...matches.values()].filter((f) => !f.result && f.planet === planet);
  }

  function room(f, side) {
    return humans(f, side).length < TEAM_MAX;
  }

  function list() {
    return [...matches.values()]
      .filter((f) => !f.result)
      .map((f) => ({ id: f.id, planet: f.planet, attacker: f.factions.a, defender: f.factions.d, rule: f.rule, map: f.map.name, score: { a: Math.floor(f.score.a), d: Math.floor(f.score.d) }, pilots: [...f.bodies.values()].filter((b) => b.present && !b.ai).map((b) => b.name) }));
  }

  function close() {
    clearInterval(ticker);
    for (const t of timers) clearTimeout(t);
  }

  return { matches, start, enlist, leave, handle, running, room, list, tick: tickAll, close };
}

module.exports = {
  SIZE,
  TEAM_MIN,
  TEAM_MAX,
  MATCH_S,
  REINFORCEMENTS,
  FORTRESS_EXTRA,
  RESPAWN_S,
  HP,
  SHIELD,
  HACK_S,
  REPAIR_S,
  RULES,
  WEAPONS,
  ATTACHMENTS,
  PERKS,
  EQUIPMENT,
  POINTS,
  DEFAULT_CLASSES,
  CUSTOM_MAX,
  STREAKS,
  LAYOUTS,
  RADIUS,
  EYE,
  SHOTS_PER_S,
  MOVES_PER_S,
  USES_PER_S,
  END_KEEP_MS,
  TICK_MS,
  SNAPSHOT_MS,
  STEP_S,
  SUPPLY_EVERY_S,
  buildMap,
  rotation,
  random,
  blockers,
  pushOut,
  boxNear,
  newBody,
  spawn,
  team,
  humans,
  gunOf,
  aiStep,
  grenadesStep,
  streaksStep,
  finishReload,
  hurtBreakable,
  touch,
  checkClass,
  saveClass,
  classOf,
  newFacility,
  addPilot,
  removePilot,
  move,
  fire,
  reload,
  switchTo,
  throwFrag,
  stim,
  use,
  useStreak,
  hurt,
  blocked,
  navGrid,
  flowTo,
  cellOf,
  step,
  frame,
  stateFor,
  joined,
  createFacilities,
};
