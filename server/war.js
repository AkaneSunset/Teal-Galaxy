// The galactic war: star systems joined by lanes, contested planets split into sectors, and the
// Builders' navies fighting for orbital control. Pure state + functions taking `now`, like
// galaxy.js; all of it is in the broadcast galaxy state as g.war.
//
// A planet is won by holding its capital sector and 75% of its sectors, and then it locks for a
// week. Fleets never take ground: they win orbital control, and a faction needs 25% of a system's
// before it can attack the planets there. capture() is the one way a sector changes hands, so
// the sector battles of phase 3 will call it.
//
// Fleets with `ai: true` are the Coma Conglomerate's armadas (director.js): they belong to no
// Builder, need no supplies, and stand down when they get home.

const F = require('./factions');
const N = require('./navy');
const S = require('./sites');

const LOCK_MS = 7 * 24 * 3600_000; // a planet that changes hands can't be attacked for a week
const CARRIER_SHARE = 0.25; // orbital control a faction needs before it can attack a system's planets
const PLANET_SHARE = 0.75; // sectors that win a planet, with its capital sector
const SECTOR_PILOTS = 32; // pilots in one sector battle (phase 3)
const BATTLE_MS = 2 * 60_000; // a round of fleet battle in a system this often
const UPKEEP_MS = 10 * 60_000; // a stationed fleet is supplied this often...
const UPKEEP = { corvette: 1, frigate: 2, destroyer: 4 }; // ...with this many fuel cells per ship
const FUEL_CREDITS = 20; // credits for each fuel cell short
const LOG_MAX = 30;
const HOME_JUMPS = 0.25; // a fleet crosses its own home system in a quarter of a jump
const DAY = 24 * 3600_000;

// The map: [id, name, pos, lanes, capital of, planets [id, name, initial owner]]. Teal Prime is the
// Builders' home system; each faction's capital system next to it is its own for good, and the two
// systems beyond start neutral.
const MAP = [
  ['teal-prime', 'Teal Prime', [0, 0], ['fortitude', 'umbra', 'aurelia', 'comae'], null,
    [['cinder', 'Cinder', 'compact'], ['vesper', 'Vesper', 'ashen'], ['halcyon', 'Halcyon', 'luminar'], ['morrow', 'Morrow', 'coma']]],
  ['fortitude', 'Fortitude', [-1, -1], ['teal-prime', 'marrow'], 'compact', [['bastion', 'Bastion', 'compact'], ['anvil', 'Anvil', 'compact']]],
  ['umbra', 'Umbra', [1, -1], ['teal-prime', 'marrow'], 'ashen', [['shade', 'Shade', 'ashen'], ['hollow', 'Hollow', 'ashen']]],
  ['aurelia', 'Aurelia', [-1, 1], ['teal-prime', 'drift'], 'luminar', [['radiance', 'Radiance', 'luminar'], ['glimmer', 'Glimmer', 'luminar']]],
  ['comae', 'Comae', [1, 1], ['teal-prime', 'drift'], 'coma', [['nadir', 'Nadir', 'coma'], ['zenith', 'Zenith', 'coma']]],
  ['marrow', 'Marrow Reach', [0, -2], ['fortitude', 'umbra'], null, [['scar', 'Scar', null], ['rift', 'Rift', null], ['cairn', 'Cairn', null]]],
  ['drift', 'The Drift', [0, 2], ['aurelia', 'comae'], null, [['eddy', 'Eddy', null], ['mire', 'Mire', null]]],
];
const HOME_SYSTEM = 'teal-prime';

function fail(reason) {
  return { ok: false, reason };
}

// FNV-1a: the same id always gives the same planet.
function hash(s) {
  let h = 0x811c9dc5;
  for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 0x01000193) >>> 0;
  return h;
}

// --- The map ---------------------------------------------------------------------------------

// A planet's sectors: 10 to 25 of them spread evenly over the globe (a Fibonacci sphere), each
// linked to its three nearest (and to any sector that counts it among its own three). Sector 1,
// near the north pole, is the capital sector.
function sectorsFor(id, name, owner) {
  const n = 10 + (hash(id) % 16);
  const golden = Math.PI * (3 - Math.sqrt(5));
  const round = (x) => Math.round(x * 10) / 10;
  const sectors = [];
  for (let i = 0; i < n; i++) {
    const y = 1 - (2 * (i + 0.5)) / n;
    const lat = round((Math.asin(y) * 180) / Math.PI);
    const lon = round(((i * golden * 180) / Math.PI) % 360);
    sectors.push({ id: `${id}-${i + 1}`, name: `${name} ${i + 1}`, lat, lon, owner, capital: i === 0, links: [] });
  }
  const links = sectors.map(() => new Set());
  sectors.forEach((a, i) => {
    const near = sectors
      .map((b, j) => [S.angleBetween([a.lat, a.lon], [b.lat, b.lon]), j])
      .filter(([, j]) => j !== i)
      .sort((x, y) => x[0] - y[0] || x[1] - y[1])
      .slice(0, 3);
    for (const [, j] of near) {
      links[i].add(j);
      links[j].add(i);
    }
  });
  sectors.forEach((s, i) => (s.links = [...links[i]].sort((a, b) => a - b).map((j) => sectors[j].id)));
  return sectors;
}

function newWar() {
  const war = {
    systems: MAP.map(([id, name, pos, lanes, capitalOf]) => ({ id, name, pos, lanes, capitalOf, home: id === HOME_SYSTEM })),
    planets: MAP.flatMap(([system, , , , capitalOf, planets]) =>
      planets.map(([id, name, owner]) => ({ id, name, system, capital: !!capitalOf, owner, lockedUntil: 0, sectors: sectorsFor(id, name, owner), contenders: [] }))),
    orbital: {},
    fleets: [],
    supply: {},
    log: [],
    nextFleetId: 1,
    battleAt: {}, // system id -> when its next battle round is due, while 2+ factions are there
  };
  return war;
}

// Gives a galaxy its war (new galaxies, and saves from before it). An existing war keeps every
// owner and lock it has; systems or planets missing from an older map are added.
function ensureWar(g) {
  const fresh = newWar();
  if (!g.war) g.war = fresh;
  for (const [k, v] of Object.entries(fresh)) g.war[k] ??= v;
  for (const s of fresh.systems) if (!g.war.systems.some((x) => x.id === s.id)) g.war.systems.push(s);
  for (const p of fresh.planets) if (!g.war.planets.some((x) => x.id === p.id)) g.war.planets.push(p);
  for (const s of g.war.systems) {
    g.war.supply[s.id] ||= {};
    for (const f of Object.keys(F.FACTIONS)) g.war.supply[s.id][f] ||= {};
  }
  for (const fl of g.war.fleets) fl.taken ??= 0;
  recompute(g, Date.now());
  return g.war;
}

function system(g, id) {
  return g.war.systems.find((s) => s.id === id);
}

// How many lanes apart two systems are (through any system, capitals too), or null if no lanes
// join them.
function laneJumps(g, from, to) {
  const seen = new Map([[from, 0]]);
  const queue = [from];
  while (queue.length) {
    const id = queue.shift();
    if (id === to) return seen.get(id);
    for (const next of system(g, id)?.lanes || []) {
      if (seen.has(next)) continue;
      seen.set(next, seen.get(id) + 1);
      queue.push(next);
    }
  }
  return null;
}

function planet(g, id) {
  return g.war.planets.find((p) => p.id === id);
}

// The faction holding a planet's capital sector and at least 75% of its sectors, or null.
function planetOwner(wp) {
  const f = wp.sectors.find((s) => s.capital)?.owner;
  if (!f) return null;
  return wp.sectors.filter((s) => s.owner === f).length >= PLANET_SHARE * wp.sectors.length ? f : null;
}

// How much of a system a faction holds: its share of the contested planets there. A capital system
// is wholly its faction's.
function systemShare(g, systemId, faction) {
  const s = system(g, systemId);
  if (!s) return 0;
  if (s.capitalOf) return s.capitalOf === faction ? 1 : 0;
  const planets = g.war.planets.filter((p) => p.system === systemId);
  return planets.length ? planets.filter((p) => p.owner === faction).length / planets.length : 0;
}

// A faction can only reach a planet it has a foothold near: a sector of it, another planet in the
// same system, or half of a system one lane away.
function foothold(g, faction, wp) {
  if (wp.sectors.some((s) => s.owner === faction)) return true;
  if (g.war.planets.some((p) => p !== wp && p.system === wp.system && p.owner === faction)) return true;
  return (system(g, wp.system)?.lanes || []).some((id) => systemShare(g, id, faction) >= 0.5);
}

function timeLeft(ms) {
  if (ms >= DAY) {
    const days = Math.ceil(ms / DAY);
    return `${days} more day${days === 1 ? '' : 's'}`;
  }
  const hours = Math.max(1, Math.ceil(ms / 3600_000));
  return `${hours} more hour${hours === 1 ? '' : 's'}`;
}

// Whether `faction` may attack a planet now, or why not. `lock: false` ignores a planet's lock
// (for who contends it).
function canAttack(g, faction, planetId, now = Date.now(), { lock = true } = {}) {
  if (!F.FACTIONS[faction]) return fail('no such faction');
  const wp = planet(g, planetId);
  if (!wp) return fail('no such planet');
  if (wp.capital) return fail("capital worlds can't be attacked");
  if (lock && wp.lockedUntil > now) return fail(`${wp.name} is locked for ${timeLeft(wp.lockedUntil - now)}`);
  if (!foothold(g, faction, wp)) return fail(`${F.the(faction)} has no foothold near ${wp.name}`);
  const share = shares(g, wp.system)[faction];
  if (share + 1e-9 < CARRIER_SHARE)
    return fail(`you need ${Math.round(CARRIER_SHARE * 100)}% orbital control of ${system(g, wp.system).name}: you have ${Math.floor(share * 100 + 1e-9)}%`);
  return { ok: true, planet: wp };
}

// The factions that can fight over a planet (lock aside), and its owner.
function contenders(g, wp, now) {
  return Object.keys(F.FACTIONS).filter((f) => f === wp.owner || canAttack(g, f, wp.id, now, { lock: false }).ok);
}

// Flips one sector to `faction`, with every rule of canAttack, if it's next to one the faction
// already holds there (a faction with none there may take any). The planet changes hands when its
// capital sector and 75% are held, and then locks for a week. Builders whose outposts are on the
// planet hear when one of their faction's sectors falls.
function capture(g, planetId, sectorId, faction, now = Date.now()) {
  const can = canAttack(g, faction, planetId, now);
  if (!can.ok) return can;
  const wp = can.planet;
  const sector = wp.sectors.find((s) => s.id === sectorId);
  if (!sector) return fail('no such sector');
  if (sector.owner === faction) return fail(`${F.the(faction)} already holds ${sector.name}`);
  const held = new Set(wp.sectors.filter((s) => s.owner === faction).map((s) => s.id));
  if (held.size && !sector.links.some((id) => held.has(id))) return fail(`${sector.name} isn't next to a sector you hold`);
  const lost = sector.owner;
  sector.owner = faction;
  warLog(g, `${F.FACTIONS[faction].name} took ${sector.name}${lost ? ` from ${F.the(lost)}` : ''}`, now);
  const before = wp.owner;
  wp.owner = planetOwner(wp);
  if (wp.owner !== before) {
    if (wp.owner) {
      wp.lockedUntil = now + LOCK_MS;
      warLog(g, `${wp.name} fell to ${F.the(wp.owner)}: it is locked for ${Math.round(LOCK_MS / DAY)} days`, now);
    } else warLog(g, `${F.FACTIONS[before].name} lost control of ${wp.name}`, now);
  }
  if (lost) {
    for (const [name, e] of Object.entries(g.bases || {})) {
      if (e.faction !== lost) continue;
      if (!g.system.planets.some((p) => p.kind === 'satellite' && p.owner === name && p.parent === wp.id)) continue;
      F.alert(e, `${sector.name} fell to ${F.the(faction)}: your outposts on ${wp.name} are at risk`, now);
    }
  }
  recompute(g, now);
  return { ok: true, planet: wp.id, sector: sector.id, owner: wp.owner, lockedUntil: wp.lockedUntil };
}

// --- Fleets and orbital control ------------------------------------------------------------

// How much a fleet counts for: attack plus a fifth of hull, per ship (corvette 4, frigate 11, destroyer 26).
function power(ships) {
  let p = 0;
  for (const [id, n] of Object.entries(ships || {})) if (N.SHIPS[id]) p += n * (N.SHIPS[id].attack + N.SHIPS[id].hull / 5);
  return p;
}

// Each faction's share of orbital control over a system: its stationed fleets' power over everyone's.
// A fleet that arrived where another faction is in orbit (`joining`) has no say until it has fought
// a round there, so a fleet called home before every round never wins any control.
function shares(g, systemId) {
  const out = Object.fromEntries(Object.keys(F.FACTIONS).map((f) => [f, 0]));
  let total = 0;
  for (const fl of g.war.fleets) {
    if (fl.system !== systemId || fl.status !== 'stationed' || fl.joining || !Object.hasOwn(out, fl.faction)) continue;
    const p = power(fl.ships);
    out[fl.faction] += p;
    total += p;
  }
  if (total > 0) for (const f of Object.keys(out)) out[f] /= total;
  return out;
}

function shipList(ships) {
  return Object.entries(ships)
    .filter(([, n]) => n > 0)
    .map(([id, n]) => `${n} ${N.SHIPS[id].name}${n === 1 ? '' : 's'}`)
    .join(', ');
}

// A Builder sends ships from their navy (`ships` {id: count}, or null for all of them) to hold a
// system's orbit: any system that isn't a faction's capital. They fly a jump per lane from the
// Builder's home system, through capital systems on the way but never stopping in one (a quarter
// of a jump to stay in the home system itself).
function sendFleet(g, owner, systemId, ships, now = Date.now()) {
  const e = g.bases?.[owner];
  if (!e) return fail('you have no home planet');
  if (!e.faction) return fail('choose a faction first');
  const to = system(g, systemId);
  if (!to) return fail('no such system');
  if (to.capitalOf) return fail("capital systems can't be contested");
  const home = system(g, g.system.id) || system(g, HOME_SYSTEM);
  const jumps = to.id === home.id ? HOME_JUMPS : laneJumps(g, home.id, to.id);
  if (!jumps) return fail(`no lane reaches ${to.name}`);
  N.ensure(e);
  const send = {};
  for (const id of Object.keys(N.SHIPS)) {
    const n = ships ? Math.min(Math.max(0, Math.floor(Number(ships[id]) || 0)), e.navy[id]) : e.navy[id];
    if (n > 0) send[id] = n;
  }
  if (!Object.keys(send).length) return fail('you have no ships to send');
  for (const [id, n] of Object.entries(send)) e.navy[id] -= n;
  const leg = N.travelMs(send) * jumps;
  const fleet = { id: g.war.nextFleetId++, owner, faction: e.faction, system: to.id, ships: send, status: 'flying', arriveAt: now + leg, returnAt: 0, leg, taken: 0, upkeepAt: 0 };
  g.war.fleets.push(fleet);
  warLog(g, `${owner}'s fleet (${shipList(send)}) is heading for ${to.name}`, now);
  return { ok: true, fleet };
}

// Turns a fleet round: one on its way back as far as it came, one in orbit the whole way.
function turnRound(fl, now) {
  fl.returnAt = fl.status === 'flying' ? now + Math.max(0, fl.leg - (fl.arriveAt - now)) : now + fl.leg;
  fl.status = 'returning';
}

// The Builder calls a fleet home; on arrival its ships rejoin the navy.
function recallFleet(g, owner, fleetId, now = Date.now()) {
  const fl = g.war.fleets.find((f) => f.id === Number(fleetId) && f.owner === owner);
  if (!fl) return fail('no such fleet');
  if (fl.status === 'returning') return fail('that fleet is already on its way home');
  turnRound(fl, now);
  warLog(g, `${owner}'s fleet over ${system(g, fl.system).name} is coming home`, now);
  return { ok: true, fleet: fl };
}

// Damage sinks a side's lightest ships first, across its fleets (oldest fleet first). What's left
// over stays on the fleet whose ship is next in line, as `taken`. Returns {ship id: lost}.
function sink(fleets, damage) {
  const lost = {};
  const types = Object.keys(N.SHIPS).sort((a, b) => N.SHIPS[a].hull - N.SHIPS[b].hull);
  let pool = damage;
  for (const id of types)
    for (const fl of fleets) {
      const hull = N.SHIPS[id].hull;
      while ((fl.ships[id] || 0) > 0) {
        if (pool + fl.taken < hull) {
          fl.taken = Math.round((fl.taken + pool) * 100) / 100;
          return lost;
        }
        pool -= hull - fl.taken;
        fl.taken = 0;
        fl.ships[id] -= 1;
        if (!fl.ships[id]) delete fl.ships[id];
        lost[id] = (lost[id] || 0) + 1;
      }
    }
  return lost;
}

function short(faction) {
  return faction[0].toUpperCase() + faction.slice(1);
}

// "Akane's fleet", or "The Coma armada".
function fleetName(fl) {
  return fl.ai ? `The ${short(fl.faction)} armada` : `${fl.owner}'s fleet`;
}

// One round of battle between the factions stationed over a system. Each deals its fleets' attack
// (times N.DAMAGE) to the others, split by their power; all of it lands at once. The same fleets
// always fight the same way.
function battleRound(g, s, now) {
  const here = g.war.fleets.filter((f) => f.system === s.id && f.status === 'stationed').sort((a, b) => a.id - b.id);
  const sides = Object.keys(F.FACTIONS).filter((f) => here.some((fl) => fl.faction === f));
  const pw = {};
  const hit = {};
  for (const f of sides) {
    pw[f] = here.filter((fl) => fl.faction === f).reduce((a, fl) => a + power(fl.ships), 0);
    hit[f] = 0;
  }
  for (const f of sides) {
    const attack = here.filter((fl) => fl.faction === f).reduce((a, fl) => a + Object.entries(fl.ships).reduce((b, [id, n]) => b + N.SHIPS[id].attack * n, 0), 0);
    const foes = sides.filter((x) => x !== f);
    const total = foes.reduce((a, x) => a + pw[x], 0);
    for (const x of foes) hit[x] += (attack * N.DAMAGE * pw[x]) / total;
  }
  const parts = [];
  for (const f of sides) {
    const lost = sink(here.filter((fl) => fl.faction === f), Math.round(hit[f] * 100) / 100);
    if (Object.keys(lost).length) parts.push(`${short(f)} lost ${shipList(lost)}`);
  }
  warLog(g, `Battle over ${s.name}: ${parts.length ? parts.join(', ') : 'no ships lost'}`, now);
  for (const fl of here) {
    delete fl.joining; // it has fought for the orbit: now it counts
    if (power(fl.ships) > 0) continue;
    g.war.fleets = g.war.fleets.filter((x) => x !== fl);
    const e = !fl.ai && g.bases?.[fl.owner];
    if (e) F.alert(e, `Your fleet over ${s.name} was destroyed`, now);
    warLog(g, `${fleetName(fl)} over ${s.name} was destroyed`, now);
  }
}

// A round every BATTLE_MS while 2+ factions are stationed in a system, the first BATTLE_MS after
// they meet (time to call a fleet home). Catches up rounds missed between ticks. A faction alone in
// orbit holds it: its fleets that came to join a fight count at once.
function battles(g, s, now) {
  let changed = false;
  for (;;) {
    const here = g.war.fleets.filter((f) => f.system === s.id && f.status === 'stationed');
    if (new Set(here.map((f) => f.faction)).size < 2) {
      for (const fl of here.filter((f) => f.joining)) {
        delete fl.joining;
        changed = true;
      }
      if (g.war.battleAt[s.id]) {
        delete g.war.battleAt[s.id];
        changed = true;
      }
      return changed;
    }
    if (!g.war.battleAt[s.id]) {
      g.war.battleAt[s.id] = now + BATTLE_MS;
      const sides = Object.keys(F.FACTIONS).filter((f) => here.some((fl) => fl.faction === f));
      warLog(g, `Fleets of ${sides.map(F.the).join(' and ')} met over ${s.name}: battle in ${BATTLE_MS / 60_000} minutes`, now);
      return true;
    }
    if (now < g.war.battleAt[s.id]) return changed;
    g.war.battleAt[s.id] += BATTLE_MS;
    battleRound(g, s, now);
    changed = true;
  }
}

// A stationed fleet's supplies: fuel cells from the owner's stock, credits for any short. A fleet
// that can't be supplied comes home. Returns whether it was.
function upkeep(g, fl, now) {
  const e = g.bases?.[fl.owner];
  const cells = Object.entries(fl.ships).reduce((a, [id, n]) => a + (UPKEEP[id] || 0) * n, 0);
  const fuel = Math.min(cells, e?.stock.fuel || 0);
  const credits = (cells - fuel) * FUEL_CREDITS;
  const where = system(g, fl.system).name;
  if (!e || e.credits < credits) {
    turnRound(fl, now);
    if (e) F.alert(e, `Your fleet over ${where} ran out of supplies and is coming home`, now);
    warLog(g, `${fl.owner}'s fleet over ${where} ran out of supplies`, now);
    return false;
  }
  if (fuel > 0) e.stock.fuel -= fuel;
  e.credits -= credits;
  return true;
}

// Ships back from a fleet rejoin their owner's navy. An armada stands down instead: its ships were
// nobody's.
function dock(g, fl, now) {
  const from = system(g, fl.system)?.name || fl.system;
  if (fl.ai) {
    warLog(g, `${fleetName(fl)} from ${from} is back at ${system(g, F.FACTIONS[fl.faction].capital).name}`, now);
    return;
  }
  const e = g.bases?.[fl.owner];
  if (e) {
    N.ensure(e);
    for (const [id, n] of Object.entries(fl.ships)) if (N.SHIPS[id]) e.navy[id] += n;
  }
  warLog(g, `${fleetName(fl)} is back from ${from}`, now);
}

// Fleets flying and coming home, upkeep, battles, then orbital control, contenders and dormancy.
// Called from galaxy.tick(); returns whether anything changed.
function warTick(g, now = Date.now()) {
  if (!g.war) ensureWar(g);
  let changed = false;
  for (const fl of g.war.fleets.slice()) {
    if (fl.status === 'flying' && now >= fl.arriveAt) {
      fl.status = 'stationed';
      fl.joining = true; // until battles() finds it alone with its faction, or it has fought a round
      if (!fl.ai) fl.upkeepAt = fl.arriveAt; // supplied as it takes station, then every UPKEEP_MS; armadas need none
      warLog(g, `${fleetName(fl)} arrived over ${system(g, fl.system).name}`, now);
      changed = true;
    } else if (fl.status === 'returning' && now >= fl.returnAt) {
      g.war.fleets = g.war.fleets.filter((x) => x !== fl);
      dock(g, fl, now);
      changed = true;
    }
  }
  // A fleet that can't be supplied heads home before it can join a battle.
  for (const fl of g.war.fleets) {
    while (!fl.ai && fl.status === 'stationed' && now >= fl.upkeepAt) {
      changed = true;
      if (!upkeep(g, fl, now)) break;
      fl.upkeepAt += UPKEEP_MS;
    }
  }
  for (const s of g.war.systems) if (battles(g, s, now)) changed = true;
  return recompute(g, now) || changed;
}

// Recomputes what follows from fleets and sectors: orbital shares, contenders and dormancy.
// Returns whether any of it changed.
function recompute(g, now = Date.now()) {
  const before = JSON.stringify([g.war.orbital, g.war.planets.map((p) => p.contenders)]);
  for (const s of g.war.systems) g.war.orbital[s.id] = shares(g, s.id);
  for (const wp of g.war.planets) wp.contenders = contenders(g, wp, now);
  const changed = JSON.stringify([g.war.orbital, g.war.planets.map((p) => p.contenders)]) !== before;
  return updateDormancy(g, now) || changed;
}

// An outpost sleeps while its faction doesn't hold the planet it's on: no production, no freighter,
// no building, though raiders can still break in. It wakes as it was when the faction retakes it.
// Outposts from before the war follow their Builder's faction (factions.relocate) and sleep until
// it holds a planet here; those of a Builder with no faction never sleep.
function updateDormancy(g, now = Date.now()) {
  let changed = false;
  const waiting = new Set(g.system.planets.filter((p) => p.kind === 'satellite' && !p.sector && g.bases?.[p.owner]?.faction).map((p) => p.owner));
  for (const owner of waiting) if (F.relocate(g, owner, now).length) changed = true;
  const flips = new Map();
  for (const site of g.system.planets) {
    if (site.kind !== 'satellite') continue;
    const dormant = !!site.faction && (!site.sector || planet(g, site.parent)?.owner !== site.faction);
    if (site.dormant === dormant) continue;
    const was = site.dormant;
    site.dormant = dormant;
    if (was === undefined && !dormant) continue; // first look at an old site: nothing to say
    changed = true;
    const where = planet(g, site.parent)?.name || g.system.planets.find((p) => p.id === site.parent)?.name || site.parent;
    flips.set(`${site.owner}|${where}|${dormant}`, `${site.owner}'s outposts on ${where} ${dormant ? 'went dormant' : 'woke up'}`);
  }
  for (const text of flips.values()) warLog(g, text, now);
  return changed;
}

// War events go in the war log and the galaxy feed.
function warLog(g, text, now) {
  g.war.log.push({ at: now, text });
  if (g.war.log.length > LOG_MAX) g.war.log.splice(0, g.war.log.length - LOG_MAX);
  g.feed.push({ at: Date.now(), text });
  if (g.feed.length > 50) g.feed.shift();
}

module.exports = {
  LOCK_MS,
  CARRIER_SHARE,
  PLANET_SHARE,
  SECTOR_PILOTS,
  BATTLE_MS,
  UPKEEP_MS,
  UPKEEP,
  FUEL_CREDITS,
  HOME_SYSTEM,
  HOME_JUMPS,
  MAP,
  hash,
  newWar,
  ensureWar,
  system,
  laneJumps,
  planet,
  planetOwner,
  systemShare,
  foothold,
  canAttack,
  contenders,
  capture,
  power,
  shares,
  shipList,
  sendFleet,
  recallFleet,
  turnRound,
  warTick,
  recompute,
  updateDormancy,
  warLog,
};
