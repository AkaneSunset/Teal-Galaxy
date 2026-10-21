// Galaxy rules for the prototype: one star system, one planet, a few buildings and jobs.
// Pure state + functions so the server and the tests share the same logic.
// Facilities and raids on them are in heist.js; this file hooks them into the galaxy.
// The faction war (factions, the war map, fleets, dormancy) is in factions.js and war.js, and the
// Coma Conglomerate's AI director in director.js.

const D = require('./director');
const F = require('./factions');
const H = require('./heist');
const N = require('./navy');
const S = require('./sites');
const W = require('./war');

// A home base is a Command Centre with eight nodes around it in a square, each for one building
// (NODES). The Command Centre's level decides which nodes can be built, how high they can level
// and what else the Builder has unlocked (COMMAND_LEVELS).
const BUILDINGS = {
  command: { name: 'Command Centre', cost: { metal: 60, ice: 10 } },
  spaceport: { name: 'Star Port', cost: { metal: 30 }, needs: null },
  extractor: { name: 'Extractor', cost: { metal: 15 }, needs: null },
  habitat: { name: 'Habitat', cost: { metal: 20 }, needs: null },
  hydroponics: { name: 'Hydroponics Lab', cost: { metal: 20, ice: 10 }, needs: 'ice' },
  warehouse: { name: 'Warehouse', cost: { metal: 40 } },
  power: { name: 'Power Plant', cost: { metal: 50, ice: 10 } },
  // Outposts: facilities that fill a vault with goods the Builder ships home, and Explorers can raid
  // them. Each is founded on its own site in a sector the Builder's faction holds (sites.js).
  refinery: { name: 'Extractor', cost: { metal: 40 }, facility: true },
  lab: { name: 'Armoury', cost: { metal: 30, ice: 10 }, facility: true },
  spire: { name: 'Sensor Works', cost: { metal: 50, credits: 150 }, facility: true },
  fuel: { name: 'Fuel Depot', cost: { metal: 30, ice: 10 }, facility: true },
  munitions: { name: 'Light Munitions Works', cost: { metal: 40 }, facility: true },
  ordnance: { name: 'Heavy Munitions Works', cost: { metal: 50, alloy: 10 }, facility: true },
  drones: { name: 'Drone Yard', cost: { metal: 50, alloy: 15 }, facility: true },
  landers: { name: 'Lander Yard', cost: { metal: 60, alloy: 15 }, facility: true },
  haulers: { name: 'Hauler Yard', cost: { metal: 70, alloy: 20 }, facility: true },
  // Builds warships for the Builder's navy (navy.js). One per base, after a Star Port.
  foundry: { name: 'Ship Foundry', cost: { metal: 60, ice: 10 }, needsBuilding: 'spaceport', limit: 1 },
  // Where carriers will dock (phase 4); for now it hosts the dock market. One per base.
  dock: { name: 'Carrier Dock', cost: { metal: 80, alloy: 10 }, needsBuilding: 'spaceport', limit: 1 },
};
const OUTPOSTS = Object.keys(BUILDINGS).filter((t) => BUILDINGS[t].facility);

// The home base's nodes, by slot: 0-7 around the Command Centre, which stands on COMMAND_SLOT.
const NODES = ['spaceport', 'extractor', 'habitat', 'hydroponics', 'warehouse', 'power', 'foundry', 'dock'];
const COMMAND_SLOT = 8;
// What each Command Centre level adds: the nodes it opens, how many outposts it allows in all, and
// what that means for the Builder, for the phone to show. Nodes can't level past the Command Centre.
const COMMAND_LEVELS = [
  null,
  { nodes: ['spaceport', 'extractor', 'habitat'], outposts: 0, about: ['Star Port, Extractor and Habitat', 'Pilots land at your Star Port and fly your jobs'] },
  { nodes: ['hydroponics', 'warehouse', 'power'], outposts: 1, about: ['Hydroponics Lab, Warehouse and Power Plant', 'Your first outpost, on a sector your faction holds'] },
  { nodes: ['foundry'], outposts: 2, about: ['Ship Foundry: build warships and send fleets to the war', 'A second outpost'] },
  { nodes: ['dock'], outposts: 3, about: ['Carrier Dock: the dock market, for carriers of your faction', 'A third outpost'] },
  { nodes: [], outposts: 5, about: ['Five outposts', 'Turrets on every stretch of the wall'] },
];
// The Warehouse: metal and ice stop coming in from the base's own buildings once stock reaches
// this (pilots' deliveries, freighters and loot still arrive).
const STORAGE_BASE = 500;
const STORAGE_PER_LEVEL = 750;
const POWER_BOOST = 0.1; // each Power Plant level: 10% more from the base's producing buildings

// Passive income, so a Builder progresses with no pilots online. A tick is 5 s.
// Pilots' ice jobs still pay off: one delivery is 10 ice, an Ice Extractor takes 30 s per ice.
const PRODUCES = {
  extractor: { metal: 1, ice: 1 / 6 }, // 12 metal and 2 ice a minute
  habitat: { credits: 1 }, // rent: 12 credits a minute
  hydroponics: { credits: 2 }, // sells food: 24 credits a minute
};
// Building takes time, and every building can be upgraded up to MAX_LEVEL. Each level costs and
// takes twice what the one before did, and produces more (see levelled effects in tick()).
// A building under construction or being upgraded does nothing until it's done.
const BUILD_S = {
  command: 120, extractor: 30, habitat: 40, spaceport: 60, hydroponics: 60, warehouse: 60, power: 90, foundry: 120, dock: 180,
  refinery: 90, lab: 120, spire: 150, fuel: 60, munitions: 90, ordnance: 120, drones: 150, landers: 150, haulers: 180,
};
const MAX_LEVEL = 5;
const LEVEL_GROWTH = 2; // cost and time multiply by this each level

// What it costs to take a building of `type` from `level` to the next one (level 0: building it).
function levelCost(type, level) {
  const out = {};
  for (const [res, n] of Object.entries(BUILDINGS[type].cost)) out[res] = Math.round(n * LEVEL_GROWTH ** level);
  return out;
}

function levelMs(g, type, level) {
  return (BUILD_S[type] * 1000 * LEVEL_GROWTH ** level) / (g.buildSpeed || 1);
}

// Sets building `b` working towards its next level, done after `ms` (at once when `ms` is 0,
// as with g.buildSpeed = Infinity in tests that aren't about build times).
function startWork(b, ms, now) {
  if (ms > 0) b.readyAt = now + ms;
  else b.level = (b.level ?? 0) + 1;
}

function busy(b, now) {
  return !!b.readyAt && now < b.readyAt;
}

const AUTO_SHIP_MS = 5 * 60_000; // a facility's freighter takes the vault home on its own this often
const POPULATION_PER_HABITAT = 50;

// Unlocked from the start: everything but Hydroponics, which the first ice unlocks.
// (The Command Centre's level decides the rest: COMMAND_LEVELS.)
const UNLOCKED = ['extractor', 'habitat', 'spaceport', 'warehouse', 'power', ...OUTPOSTS, 'foundry', 'dock'];

function newGalaxy() {
  const g = {
    system: {
      id: 'teal-prime',
      name: 'Teal Prime',
      planets: [{ id: 'aster', name: 'Aster', slots: NODES.length, buildings: [newCommand()] }],
    },
    stock: { metal: 60, ice: 0 },
    credits: 500,
    population: 0,
    unlocked: UNLOCKED.slice(),
    jobs: [],
    raids: [], // raids in progress, as everyone may see them (no container contents)
    raidLog: [],
    pilots: {},
    feed: [],
    navy: { corvette: 0, frigate: 0, destroyer: 0 },
    nextJobId: 1,
    contracts: [], // pilots' supply contracts, filled by Builders of their faction
    nextContractId: 1,
  };
  W.ensureWar(g);
  D.ensureDirector(g);
  return g;
}

// Each Builder owns a home planet and its own economy (stock, credits, population, unlocks, navy),
// kept in g.bases by Builder name. A planet nobody has claimed yet uses the galaxy's own top-level
// economy: that is how a fresh galaxy starts and how saves from before bases load.
const PLANET_NAMES = ['Brisa', 'Corvo', 'Delmar', 'Eskar', 'Fenn', 'Galen', 'Hesper', 'Iridia', 'Juno', 'Kestra', 'Lumen', 'Mirren'];

function newEconomy() {
  return {
    stock: { metal: 60, ice: 0 },
    credits: 500,
    population: 0,
    unlocked: UNLOCKED.slice(),
    navy: { corvette: 0, frigate: 0, destroyer: 0 },
    // The war: `faction` is set once by chooseFaction; merit comes from donations.
    merit: 0,
    market: {}, // the Carrier Dock's listings: item -> credits per unit
    alerts: [], // [{at, text}] for the phone's toasts, the last 20
  };
}

// Demo mode (DEMO=1 on the server): every base gets enough to try every building, defence,
// warship and security tier straight away. Tops each economy up to these amounts once.
const DEMO_STOCK = { metal: 2000, ice: 200, alloy: 200, isotope: 40, drive: 4, blueprint: 2 };
const DEMO_CREDITS = 5000;

function demoTopUp(e) {
  if (e.demo) return false;
  e.demo = true;
  for (const [res, n] of Object.entries(DEMO_STOCK)) e.stock[res] = Math.max(e.stock[res] || 0, n);
  e.credits = Math.max(e.credits, DEMO_CREDITS);
  if (!e.unlocked.includes('hydroponics')) e.unlocked.push('hydroponics');
  return true;
}

// The economy that pays for and receives everything on a planet.
function econ(g, planetId) {
  const p = planet(g, planetId);
  return (p && p.owner && g.bases?.[p.owner]) || g;
}

function owns(g, name, planetId) {
  const p = planet(g, planetId);
  return !!p && (!p.owner || p.owner === name);
}

// A Builder's home planet, claimed the first time they connect: Aster if nobody has it yet
// (taking over the starting economy), otherwise a new planet with a fresh one.
function claimBase(g, name) {
  g.bases ||= {};
  const mine = g.system.planets.find((p) => p.owner === name);
  if (mine) return mine;
  const aster = planet(g, 'aster');
  if (aster && !aster.owner) {
    aster.owner = name;
    g.bases[name] = {
      stock: g.stock,
      credits: g.credits,
      population: g.population,
      unlocked: g.unlocked,
      navy: g.navy || newEconomy().navy,
      merit: 0,
      market: {},
      alerts: [],
    };
    S.locate(g);
    log(g, `${name} took charge of ${aster.name}`);
    return aster;
  }
  const taken = new Set(g.system.planets.map((p) => p.name));
  const pname = PLANET_NAMES.find((n) => !taken.has(n)) || `Colony ${g.system.planets.length + 1}`;
  const p = { id: pname.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name: pname, owner: name, slots: NODES.length, buildings: [newCommand()] };
  g.system.planets.push(p);
  S.locate(g);
  g.bases[name] = newEconomy();
  log(g, `${name} founded a base on ${pname}`);
  return p;
}

// Every home base starts with its Command Centre at level 1.
function newCommand() {
  return { slot: COMMAND_SLOT, type: 'command', level: 1 };
}

// A home planet's Command Centre level (finished levels; 1 if it has none).
function commandLevel(p) {
  const b = p?.buildings.find((x) => x.type === 'command');
  return Math.max(1, b?.level ?? 1);
}

// Sets a home planet's Command Centre to `level` at once (tests, and admins trying things out).
function setCommandLevel(g, planetId, level) {
  const b = planet(g, planetId)?.buildings.find((x) => x.type === 'command');
  if (!b) return fail('no Command Centre there');
  b.level = Math.max(1, Math.min(MAX_LEVEL, level));
  delete b.readyAt;
  return { ok: true };
}

// The Command Centre level that opens a node.
function nodeLevel(type) {
  return COMMAND_LEVELS.findIndex((l) => l && l.nodes.includes(type));
}

// How many outposts a Builder's Command Centre allows.
function outpostsAllowed(g, owner) {
  const home = g.system.planets.find((p) => p.owner === owner && p.kind !== 'satellite');
  return COMMAND_LEVELS[commandLevel(home)].outposts;
}

// How much metal and ice a planet's economy holds before its own buildings stop adding more.
function storageCap(g, planetId) {
  const owner = planet(g, planetId)?.owner;
  let level = 0;
  for (const p of g.system.planets)
    if (p.owner === owner && p.kind !== 'satellite') for (const b of p.buildings) if (b.type === 'warehouse') level = Math.max(level, b.level ?? 1);
  return STORAGE_BASE + STORAGE_PER_LEVEL * level;
}

// The planet's Power Plant level (0 without one).
function powerLevel(p) {
  return p.buildings.reduce((n, b) => (b.type === 'power' ? Math.max(n, b.level ?? 1) : n), 0);
}

function fail(reason) {
  return { ok: false, reason };
}

function log(g, text) {
  g.feed.push({ at: Date.now(), text });
  if (g.feed.length > 50) g.feed.shift();
}

function planet(g, planetId) {
  return g.system.planets.find((p) => p.id === planetId);
}

// Whether any planet has this building, or with `planetId`, whether that planet's owner does.
function hasBuilding(g, type, planetId = null) {
  const owner = planetId && planet(g, planetId)?.owner;
  return g.system.planets.some((p) => (!planetId || p.owner === owner) && p.buildings.some((b) => b.type === type && (b.level ?? 1) >= 1));
}

function build(g, planetId, slot, type, now = Date.now()) {
  const p = planet(g, planetId);
  const def = BUILDINGS[type];
  if (!p) return fail('no such planet');
  if (!def) return fail('no such building');
  const e = econ(g, planetId);
  if (type === 'command') return fail('the Command Centre is already there');
  if (!e.unlocked.includes(type)) return fail(`${def.name} is locked`);
  if (p.kind === 'satellite') return fail('an outpost holds one facility; place defences instead');
  if (def.facility) return fail(`the ${def.name} is an outpost: found it on a sector your faction holds`);
  if (!Number.isInteger(slot) || slot < 0 || slot >= NODES.length) return fail('bad slot');
  if (NODES[slot] !== type) return fail(`that node is for the ${BUILDINGS[NODES[slot]].name}`);
  if (p.buildings.some((b) => b.slot === slot)) return fail(`the ${def.name} is already there`);
  const needs = nodeLevel(type);
  if (needs > commandLevel(p)) return fail(`upgrade your Command Centre to level ${needs} for the ${def.name}`);
  if (def.needsBuilding && !hasBuilding(g, def.needsBuilding, planetId)) return fail(`build a ${BUILDINGS[def.needsBuilding].name} first`);
  if (def.limit && g.system.planets.reduce((n, q) => n + (q.owner === p.owner ? q.buildings.filter((x) => x.type === type).length : 0), 0) >= def.limit)
    return fail(`you already have a ${def.name}`);
  const err = pay(e, def.cost);
  if (err) return fail(err);
  const b = { slot, type, level: 0 };
  startWork(b, levelMs(g, type, 0), now);
  if (def.facility) Object.assign(b, { security: 1, vault: {}, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} });
  if (type === 'foundry') b.queue = [];
  if (type === 'habitat' && b.level === 1) e.population += POPULATION_PER_HABITAT;
  p.buildings.push(b);
  log(g, `${def.name} under construction on ${p.name}`);
  return { ok: true };
}

// Takes a cost ({resource: amount}, where `credits` means the wallet) from an economy,
// or says what is short.
function pay(e, cost) {
  for (const [res, amount] of Object.entries(cost)) {
    const have = res === 'credits' ? e.credits : e.stock[res] || 0;
    if (have < amount) return `not enough ${res === 'credits' ? 'credits' : H.ITEMS[res]?.name || res}`;
  }
  for (const [res, amount] of Object.entries(cost)) {
    if (res === 'credits') e.credits -= amount;
    else e.stock[res] -= amount;
  }
  return null;
}

// Starts upgrading a building to its next level, or says why not.
function upgradeBuilding(g, planetId, slot, now = Date.now()) {
  const p = planet(g, planetId);
  const b = p && p.buildings.find((x) => x.slot === slot);
  if (!b) return fail('nothing there');
  const def = BUILDINGS[b.type];
  if (!def) return fail('nothing to upgrade there');
  if (busy(b, now)) return fail(`the ${def.name} is still ${b.level ? 'upgrading' : 'being built'}`);
  if (b.level >= MAX_LEVEL) return fail(`the ${def.name} is at the top level`);
  if (p.kind !== 'satellite' && b.type !== 'command' && b.level >= commandLevel(p))
    return fail(`upgrade your Command Centre to level ${b.level + 1} first`);
  if (p.dormant) return fail('the outpost is dormant');
  if (g.raids.some((r) => r.planet === planetId && r.slot === slot)) return fail('not during a raid');
  const err = pay(econ(g, planetId), levelCost(b.type, b.level));
  if (err) return fail(err);
  startWork(b, levelMs(g, b.type, b.level), now);
  if (b.type === 'habitat' && !b.readyAt) econ(g, planetId).population += POPULATION_PER_HABITAT;
  log(g, `${def.name} on ${p.name} upgrading to level ${b.level + 1}`);
  return { ok: true };
}

function postJob(g, resource, amount, reward, planetId = g.system.planets[0].id) {
  if (!hasBuilding(g, 'spaceport', planetId)) return fail('build a Star Port first');
  if (!(amount > 0) || !(reward > 0)) return fail('bad job');
  const e = econ(g, planetId);
  if (e.credits < reward) return fail('not enough credits');
  e.credits -= reward; // held until the job completes
  const job = {
    id: g.nextJobId++,
    planet: planetId,
    resource,
    amount,
    reward,
    delivered: 0,
    contributions: {},
    status: 'open',
  };
  g.jobs.push(job);
  log(g, `Job posted: deliver ${amount} ${resource} for ${reward} credits`);
  return { ok: true, job };
}

function pilot(g, name) {
  if (!Object.hasOwn(g.pilots, name)) g.pilots[name] = { credits: 0, reputation: 0, cargo: {} };
  const p = g.pilots[name];
  p.stash ||= []; // loot extracted from raids: [{item, qty, fih}]
  p.raids ||= { runs: 0, extracted: 0 };
  p.pouch ||= {}; // healing extracted with last raid: item -> count (empty: the starter kit)
  p.hold ||= {}; // war goods bought at Carrier Docks or from contracts: item -> qty (they load into a carrier in phase 4)
  return p;
}

function collect(g, name, resource, amount) {
  const p = pilot(g, name);
  if (!(amount > 0) || amount > 5) return fail('bad amount');
  p.cargo[resource] = (p.cargo[resource] || 0) + amount;
  return { ok: true };
}

function deliver(g, name, jobId) {
  const job = g.jobs.find((j) => j.id === jobId);
  if (!job || job.status !== 'open') return fail('no open job');
  const p = pilot(g, name);
  const have = p.cargo[job.resource] || 0;
  const give = Math.min(have, job.amount - job.delivered);
  if (give <= 0) return fail(`no ${job.resource} in cargo`);
  p.cargo[job.resource] = have - give;
  job.delivered += give;
  job.contributions[name] = (job.contributions[name] || 0) + give;
  const e = econ(g, job.planet || g.system.planets[0].id);
  e.stock[job.resource] = (e.stock[job.resource] || 0) + give;
  log(g, `${name} delivered ${give} ${job.resource}`);
  if (job.delivered >= job.amount) completeJob(g, job);
  return { ok: true, given: give };
}

function completeJob(g, job) {
  job.status = 'done';
  for (const [name, share] of Object.entries(job.contributions)) {
    const p = pilot(g, name);
    p.credits += Math.round((job.reward * share) / job.amount);
    p.reputation += 1;
  }
  log(g, `Job ${job.id} complete`);
  const e = econ(g, job.planet || g.system.planets[0].id);
  if (job.resource === 'ice' && !e.unlocked.includes('hydroponics')) {
    e.unlocked.push('hydroponics');
    log(g, 'Ice in stock: Hydroponics unlocked');
  }
}

function tick(g, now = Date.now()) {
  let changed = W.warTick(g, now); // first, so outposts that just went dormant stop this tick
  if (D.tick(g, now)) changed = true; // the Coma director's turn, every few minutes

  for (const p of g.system.planets)
    for (const b of p.buildings)
      if (b.readyAt && now >= b.readyAt) {
        delete b.readyAt;
        b.level = (b.level ?? 0) + 1;
        if (b.type === 'habitat') econ(g, p.id).population += POPULATION_PER_HABITAT;
        log(g, b.level === 1 ? `${BUILDINGS[b.type].name} finished on ${p.name}` : `${BUILDINGS[b.type].name} on ${p.name} reached level ${b.level}`);
        changed = true;
      }
  for (const p of g.system.planets)
    for (const b of p.buildings)
      if (b.type === 'foundry' && !busy(b, now))
        for (const name of N.tick(econ(g, p.id), b, now, g.buildSpeed || 1)) {
          log(g, `${name} launched from the Ship Foundry on ${p.name}`);
          changed = true;
        }
  for (const p of g.system.planets) {
    for (const b of p.buildings) {
      if (busy(b, now)) continue; // nothing works while it's being built or upgraded
      const level = b.level ?? 1;
      const makes = PRODUCES[b.type];
      if (makes) {
        const e = econ(g, p.id);
        const boost = 1 + POWER_BOOST * powerLevel(p);
        const cap = storageCap(g, p.id);
        b.carry = typeof b.carry === 'object' ? b.carry : {}; // per resource
        for (const [res, rate] of Object.entries(makes)) {
          if (res !== 'credits' && (e.stock[res] || 0) >= cap) continue; // the Warehouse is full
          // Fractional rates build up in b.carry and pay out whole units.
          b.carry[res] = (b.carry[res] || 0) + rate * level * boost; // each level adds the base rate again
          const whole = Math.floor(b.carry[res] + 1e-9);
          if (whole < 1) continue;
          b.carry[res] -= whole;
          if (res === 'credits') e.credits += whole;
          else e.stock[res] = Math.min(cap, (e.stock[res] || 0) + whole);
        }
        changed = true;
      }
      const fac = H.FACILITIES[b.type];
      if (!fac || p.dormant) continue; // a dormant outpost makes and ships nothing
      // The automatic freighter: goods sit in the vault (and can be raided) until it comes.
      b.autoShipAt ||= now + autoShipMs(g, p.id);
      if (now >= b.autoShipAt) {
        b.autoShipAt = now + autoShipMs(g, p.id);
        if (!g.raids.some((r) => r.planet === p.id && r.slot === b.slot) && ship(g, p.id, b.slot, now, true).ok) changed = true;
      }
      b.made += 1;
      const more = production(g, p);
      for (const m of fac.makes) {
        // Each level makes one more of every item per batch and holds that much more in the vault.
        // Bonuses (Luminar, War Merit rank) build up in b.makeCarry and pay out whole items.
        const cap = m.cap * level;
        if (b.made % m.every !== 0 || (b.vault[m.item] || 0) >= cap) continue;
        let due = level * more;
        if (more !== 1) due += (b.makeCarry ||= {})[m.item] || 0;
        const whole = Math.floor(due + 1e-9);
        if (more !== 1) b.makeCarry[m.item] = Math.round((due - whole) * 1000) / 1000;
        if (whole < 1) continue;
        b.vault[m.item] = Math.min(cap, (b.vault[m.item] || 0) + whole);
        changed = true;
      }
    }
  }
  // However ice arrived (an Ice Extractor, a pilot's delivery, loot), it unlocks Hydroponics.
  for (const e of [g, ...Object.values(g.bases || {})])
    if (e.stock.ice > 0 && !e.unlocked.includes('hydroponics')) {
      e.unlocked.push('hydroponics');
      log(g, 'Ice in stock: Hydroponics unlocked');
      changed = true;
    }
  return changed;
}

// How much an outpost makes, as a multiple: Luminar outposts 20% more, plus the owner's War Merit rank bonus.
function production(g, site) {
  return 1 + F.perk(site.faction, 'production', 0) + F.rank(econ(g, site.id).merit).bonus;
}

// --- Facilities and raids ------------------------------------------------------------------

function facility(g, planetId, slot) {
  const p = planet(g, planetId);
  const b = p && p.buildings.find((x) => x.slot === slot);
  return b && H.FACILITIES[b.type] ? b : null;
}

function facilityName(g, planetId, b) {
  const p = planet(g, planetId);
  return p.kind === 'satellite' ? p.name : `${p.name} ${H.FACILITIES[b.type].name} ${b.slot + 1}`;
}

// --- Outposts (sites.js) -------------------------------------------------------------------

// A Builder founds an outpost of `type` in a sector of a contested planet in their system that
// their faction holds (war.js): the planet must be theirs, and so must the sector.
function foundSite(g, owner, type, planetId, sectorId, now = Date.now()) {
  const def = BUILDINGS[type];
  if (!def || !def.facility) return fail('that is not an outpost');
  const home = g.system.planets.find((p) => p.owner === owner && p.kind !== 'satellite');
  if (!home) return fail('you have no home planet');
  const e = econ(g, home.id);
  if (!e.faction) return fail('choose a faction first');
  if (!e.unlocked.includes(type)) return fail(`${def.name} is locked`);
  const allowed = outpostsAllowed(g, owner);
  if (!allowed) return fail('upgrade your Command Centre to level 2 to found outposts');
  if (g.system.planets.filter((p) => p.owner === owner && p.kind === 'satellite').length >= allowed)
    return fail(`your Command Centre allows ${allowed} outpost${allowed === 1 ? '' : 's'}: upgrade it for more`);
  const wp = W.planet(g, planetId);
  if (!wp || wp.system !== g.system.id) return fail(`outposts go on the contested planets of ${g.system.name}`);
  if (wp.owner !== e.faction) return fail(`${F.the(e.faction)} doesn't hold ${wp.name}`);
  const sector = wp.sectors.find((x) => x.id === sectorId);
  if (!sector) return fail(`pick a sector of ${wp.name}`);
  if (sector.owner !== e.faction) return fail(`${F.the(e.faction)} doesn't hold ${sector.name}`);
  const r = S.newSite(g, owner, wp, sector, e.faction, H.FACILITIES[type].name);
  if (!r.ok) return r;
  const err = pay(e, def.cost);
  if (err) return fail(err);
  const b = { slot: 0, type, level: 0, security: 1, vault: {}, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} };
  startWork(b, levelMs(g, type, 0), now);
  r.site.buildings.push(b);
  S.scatter(r.site);
  g.system.planets.push(r.site);
  S.locate(g);
  log(g, `${owner} founded ${r.site.name}`);
  return { ok: true, site: r.site };
}

function site(g, siteId) {
  const p = planet(g, siteId);
  return p && p.kind === 'satellite' ? p : null;
}

// Why an outpost can't be built on right now, or null.
function siteBusy(g, st) {
  if (st.dormant) return 'the outpost is dormant';
  if (g.raids.some((r) => r.planet === st.id)) return 'not during a raid';
  return null;
}

function placePiece(g, siteId, type, x, y) {
  const st = site(g, siteId);
  if (!st) return fail('no such outpost');
  const why = siteBusy(g, st);
  if (why) return fail(why);
  const e = econ(g, siteId);
  const r = S.place(st, type, x, y, (cost) => pay(e, cost), Date.now(), g.buildSpeed || 1);
  if (r.ok) log(g, `${r.name} built at ${st.name}`);
  return r;
}

function clearObstacle(g, siteId, obstacleId) {
  const st = site(g, siteId);
  if (!st) return fail('no such outpost');
  const why = siteBusy(g, st);
  if (why) return fail(why);
  const r = S.clear(st, obstacleId, econ(g, siteId));
  if (r.ok) log(g, `${r.name} cleared at ${st.name}`);
  return r;
}

function removePiece(g, siteId, pieceId) {
  const st = site(g, siteId);
  if (!st) return fail('no such outpost');
  const why = siteBusy(g, st);
  if (why) return fail(why);
  return S.remove(st, pieceId, econ(g, siteId));
}

// The automatic freighter comes more often the higher the owner's Star Port level: every
// AUTO_SHIP_MS at level 1 (or with no Star Port), divided by the level.
function autoShipMs(g, planetId) {
  const owner = planet(g, planetId)?.owner;
  let level = 1;
  for (const p of g.system.planets)
    if (p.owner === owner) for (const b of p.buildings) if (b.type === 'spaceport') level = Math.max(level, b.level ?? 1);
  return AUTO_SHIP_MS / level;
}

// The Builder sends a freighter: the vault's goods go to HQ stock. Intel sells on arrival.
function ship(g, planetId, slot, now, auto = false) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
  if (planet(g, planetId).dormant) return fail('the outpost is dormant');
  if (!auto && now < b.shipReadyAt) return fail(`freighter back in ${Math.ceil((b.shipReadyAt - now) / 1000)} s`);
  const goods = Object.entries(b.vault).filter(([, q]) => q > 0);
  if (!goods.length) return fail('the vault is empty');
  const parts = [];
  for (const [item, qty] of goods) {
    const e = econ(g, planetId);
    if (H.ITEMS[item].cat === 'intel') e.credits += H.ITEMS[item].value * qty;
    else e.stock[item] = (e.stock[item] || 0) + qty;
    parts.push(`${qty} ${H.ITEMS[item].name}`);
    b.vault[item] = 0;
  }
  b.shipReadyAt = now + H.SHIP_COOLDOWN_MS;
  b.autoShipAt = now + autoShipMs(g, planetId);
  log(g, `${auto ? 'Scheduled freighter' : 'Freighter'} from ${facilityName(g, planetId, b)} delivered ${parts.join(', ')}`);
  return { ok: true };
}

// The Builder upgrades a facility's security: more guards, turrets, rarer loot, a longer clock.
function secure(g, planetId, slot) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
  const next = H.SECURITY[b.security + 1];
  if (!next) return fail('security is already at the top tier');
  if (planet(g, planetId).dormant) return fail('the outpost is dormant');
  if (g.raids.some((r) => r.planet === planetId && r.slot === slot)) return fail('not during a raid');
  const err = pay(econ(g, planetId), next.cost);
  if (err) return fail(err);
  b.security += 1;
  log(g, `${facilityName(g, planetId, b)} security raised to tier ${b.security}`);
  return { ok: true };
}

// An Explorer boards a facility. `run` (from heist.js) stays on the server; galaxy state only
// carries a public summary so the Builder can watch.
function startRaid(g, name, planetId, slot, now, seed, lootSeed) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
  const site = g.system.planets.find((p) => p.id === planetId);
  // An outpost with a faction can only be raided by a pilot of another one (and never by its
  // Builder's own pilot); one from before the war, by anyone.
  if (site.faction) {
    const pf = pilot(g, name).faction;
    if (!pf) return fail('choose a faction first');
    if (pf === site.faction) return fail('that outpost belongs to your own faction');
    if (site.owner === name) return fail("you can't raid your own outpost");
  }
  if (g.raids.some((r) => r.pilot === name)) return fail('you are already raiding');
  if (g.raids.some((r) => r.planet === planetId && r.slot === slot)) return fail('someone is already inside');
  if (now < b.cooldownUntil) return fail(`security is on alert for another ${Math.ceil((b.cooldownUntil - now) / 1000)} s`);
  const fname = facilityName(g, planetId, b);
  const run = H.startRun({
    facility: b, facilityName: fname, pilot: name, seed, lootSeed, now, site, pouch: pilot(g, name).pouch,
    hpScale: F.perk(site.faction, 'hp', 1), heatScale: F.perk(site.faction, 'heat', 1),
  });
  run.planet = planetId;
  run.slot = slot;
  pilot(g, name).raids.runs += 1;
  g.raids.push({ id: run.id, pilot: name, planet: planetId, slot, facility: fname, heat: 0, level: 0, endsAt: run.endsAt, vaultOpen: false, floors: run.floors, stage: 'breach', floor: 0, selfDestructAt: null });
  log(g, `Intruder alert: ${name} has boarded ${fname}`);
  return { ok: true, run };
}

// Keeps the public summary in step with the run.
function raidChanged(g, run) {
  const r = g.raids.find((x) => x.id === run.id);
  if (r) Object.assign(r, { heat: run.heat, level: H.heatLevel(run.heat), vaultOpen: run.vaultOpen, stage: H.stage(run, 0).stage, floor: run.floor ?? 0, selfDestructAt: run.selfDestructAt });
}

// The Builder sounds the alarm from the phone: Heat jumps for the raider inside.
function alarm(g, planetId, slot, run, now) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
  if (!run) return fail('nobody is inside');
  if (now < b.alarmReadyAt) return fail(`alarm ready in ${Math.ceil((b.alarmReadyAt - now) / 1000)} s`);
  const err = pay(econ(g, planetId), { credits: H.ALARM_COST });
  if (err) return fail(err);
  b.alarmReadyAt = now + H.ALARM_COOLDOWN_MS;
  H.addHeat(run, H.ALARM_HEAT);
  raidChanged(g, run);
  log(g, `Alarm sounded at ${run.facilityName}`);
  return { ok: true };
}

// A raid is over. Extracted vault goods are gone from the Builder for good; the rest returns.
function endRaid(g, run, outcome, now) {
  const result = H.finish(run, outcome, now);
  const b = facility(g, run.planet, run.slot);
  if (b) {
    for (const [item, qty] of Object.entries(b.escrow || {})) {
      const back = qty - (result.stolen[item] || 0);
      if (back > 0) b.vault[item] = (b.vault[item] || 0) + back;
    }
    b.escrow = {};
    b.cooldownUntil = now + H.RAID_COOLDOWN_MS * F.perk(planet(g, run.planet)?.faction, 'cooldown', 1);
  }
  const p = pilot(g, run.pilot);
  for (const k of result.kept) p.stash.push(k);
  p.pouch = result.pouch;
  if (outcome === 'extracted') p.raids.extracted += 1;
  g.raids = g.raids.filter((r) => r.id !== run.id);
  const words = { extracted: 'escaped from', killed: 'was killed in', destroyed: 'went down with the self-destruct of', mia: 'was caught when the clock ran out in', bailed: 'bailed out of' };
  const haul = result.kept.length ? ` with ${result.value} credits of loot` : '';
  log(g, `${run.pilot} ${words[outcome]} ${run.facilityName}${haul}`);
  g.raidLog.push({ at: now, pilot: run.pilot, facility: run.facilityName, outcome, value: result.value, stolen: result.stolen });
  if (g.raidLog.length > 20) g.raidLog.shift();
  return result;
}

// After a server restart nothing is inside any facility, so escrowed goods go home.
// Also brings saves from before facilities, levels and the war up to date.
function recoverRaids(g) {
  g.raids = [];
  g.raidLog ||= [];
  g.bases ||= {};
  g.pilots ||= {};
  g.feed ||= [];
  g.contracts ||= [];
  g.nextContractId ||= 1;
  for (const e of [g, ...Object.values(g.bases)]) {
    N.ensure(e);
    for (const type of ['extractor', 'warehouse', 'power', ...OUTPOSTS, 'foundry', 'dock']) if (!e.unlocked.includes(type)) e.unlocked.push(type);
  }
  for (const e of Object.values(g.bases)) {
    e.merit ||= 0;
    e.market ||= {};
    e.alerts ||= [];
  }
  for (const name of Object.keys(g.pilots)) pilot(g, name);
  // Buildings from other versions of the game: the Ice Well is an Extractor here, anything else
  // this version doesn't know is dropped rather than left to break whoever taps it.
  for (const p of g.system.planets) {
    for (const b of p.buildings) if (b.type === 'icewell') b.type = 'extractor';
    if (p.kind !== 'satellite') layOutBase(g, p);
    p.buildings = p.buildings.filter((b) => BUILDINGS[b.type]);
  }
  for (const p of g.system.planets) for (const b of p.buildings) if (b.type === 'foundry') b.queue ||= [];
  for (const p of g.system.planets) if (p.kind === 'satellite' && !p.obstacles) S.scatter(p);
  for (const p of g.system.planets) for (const b of p.buildings) b.level ??= 1; // built before levels // sites from before obstacles
  for (const p of g.system.planets)
    for (const b of p.buildings) {
      if (!b.escrow) continue;
      for (const [item, qty] of Object.entries(b.escrow)) b.vault[item] = (b.vault[item] || 0) + qty;
      b.escrow = {};
    }
  returnAttacks(g);
  W.ensureWar(g); // the war map for saves from before it; outposts' dormancy either way
  D.ensureDirector(g); // and the Coma director for saves from before it
}

// A home base from before the Command Centre (six pads, any building on any pad) moves onto the
// nodes: each type to its own node, keeping the highest level when there were two (a Mine becomes
// the Extractor, which digs metal now). The Command Centre comes in at the level that keeps
// everything already built, outposts included.
function layOutBase(g, p) {
  if (p.buildings.some((b) => b.type === 'command')) return;
  const best = {};
  for (const b of p.buildings) {
    if (b.type === 'mine') b.type = 'extractor';
    if (!NODES.includes(b.type)) continue;
    const have = best[b.type];
    if (!have || (b.level ?? 1) > (have.level ?? 1)) best[b.type] = b;
  }
  const sites = g.system.planets.filter((q) => q.kind === 'satellite' && p.owner && q.owner === p.owner).length;
  let level = sites ? COMMAND_LEVELS.findIndex((l) => l && l.outposts >= sites) : 1;
  if (level < 0) level = MAX_LEVEL;
  p.buildings = Object.values(best).map((b) => {
    b.slot = NODES.indexOf(b.type);
    level = Math.max(level, nodeLevel(b.type), b.level ?? 1);
    return b;
  });
  p.buildings.push({ ...newCommand(), level: Math.min(MAX_LEVEL, level) });
  p.slots = NODES.length;
}

// Fleet attacks on satellite sites are retired: fleets still out when a save from before the war
// loads come home at once, with anything they carried off.
function returnAttacks(g) {
  for (const a of g.attacks || []) {
    if (a.status !== 'flying' && a.status !== 'returning') continue;
    const home = g.system.planets.find((p) => p.owner === a.attacker && p.kind !== 'satellite');
    if (!home) continue;
    const e = econ(g, home.id);
    N.ensure(e);
    for (const [id, n] of Object.entries((a.status === 'flying' ? a.ships : a.survivors) || {})) if (N.SHIPS[id]) e.navy[id] += n;
    for (const [item, qty] of Object.entries((a.status === 'returning' && a.loot) || {})) {
      if (!H.ITEMS[item]) continue;
      if (H.ITEMS[item].cat === 'intel') e.credits += H.ITEMS[item].value * qty;
      else e.stock[item] = (e.stock[item] || 0) + qty;
    }
    log(g, `${a.attacker}'s fleet is back from ${a.siteName}`);
  }
  g.attacks = [];
}

// The Builder queues a warship at the Ship Foundry.
function queueShip(g, planetId, slot, shipId, now) {
  const p = planet(g, planetId);
  const b = p && p.buildings.find((x) => x.slot === slot && x.type === 'foundry');
  if (!b) return fail('no Ship Foundry there');
  if ((b.level ?? 1) < 1) return fail('the Ship Foundry is still being built');
  const e = econ(g, planetId);
  // Ships out with the Builder's fleets keep their berths: fleets can hold an orbit for good.
  let away = 0;
  for (const fl of g.war.fleets) if (p.owner && !fl.ai && fl.owner === p.owner) for (const n of Object.values(fl.ships)) away += n;
  const r = N.queueShip(e, b, shipId, now, (cost) => pay(e, cost), away, g.buildSpeed || 1);
  if (r.ok) log(g, `${r.name} queued at the Ship Foundry`);
  return r;
}

function cancelShip(g, planetId, slot) {
  const p = planet(g, planetId);
  const b = p && p.buildings.find((x) => x.slot === slot && x.type === 'foundry');
  if (!b) return fail('nothing in the queue');
  const r = N.cancelShip(econ(g, planetId), b);
  if (r.ok) log(g, `${r.name} cancelled and refunded`);
  return r;
}

// --- Factions, the Carrier Dock market, supply contracts and war supply ----------------------

// A character picks their faction (factions.js); what follows from it (a Builder's old sites
// moving, dormancy, contenders) is settled straight away. `admin`: the player is a server admin,
// who may also pick the Coma Conglomerate.
function chooseFaction(g, role, name, faction, now = Date.now(), { admin = false } = {}) {
  const r = F.chooseFaction(g, role, name, faction, { admin });
  if (!r.ok) return r;
  if (role === 'explorer') pilot(g, name); // the rest of a new pilot's record
  W.recompute(g, now);
  return r;
}

// Demo mode only (the server checks): a pilot takes a sector for their faction, with every rule
// of the war, so it can be played before sector battles exist.
function demoCapture(g, name, planetId, sectorId, now = Date.now()) {
  const faction = pilot(g, name).faction;
  if (!faction) return fail('choose a faction first');
  return W.capture(g, planetId, sectorId, faction, now);
}

const PRICE_MAX = 100_000; // credits per unit at a dock
const CONTRACT_MAX = 1000; // units one contract can ask for
const OPEN_CONTRACTS = 5; // open contracts per pilot
const CLOSED_KEPT = 20; // finished and cancelled contracts kept for the record
// What pilots can contract Builders for: raw materials and war supplies.
const CONTRACT_ITEMS = ['metal', 'ice', ...Object.keys(H.ITEMS).filter((k) => ['material', 'supply'].includes(H.ITEMS[k].cat))];
// War Merit per unit donated: an item's value, metal 2 and ice 3.
const MERIT_VALUE = { metal: 2, ice: 3, ...Object.fromEntries(Object.entries(H.ITEMS).map(([k, d]) => [k, d.value])) };

// Anything a Builder's stock can hold: metal, ice and the items.
function stockable(item) {
  return item === 'metal' || item === 'ice' || Object.hasOwn(H.ITEMS, item);
}

// "20 Fuel cells", "1 Missile", "40 metal".
function amountOf(item, n) {
  const name = H.ITEMS[item]?.name || item;
  return `${n} ${n === 1 || !H.ITEMS[item] || /(s|matter)$/.test(name) ? name : `${name}s`}`;
}

function homeOf(g, builder) {
  return g.system.planets.find((p) => p.owner === builder && p.kind !== 'satellite');
}

// The Builder lists something from their stock at their Carrier Dock, at `price` credits a unit
// (0 or null takes it off the market).
function setPrice(g, builder, item, price) {
  const home = homeOf(g, builder);
  if (!home) return fail('you have no home planet');
  if (!hasBuilding(g, 'dock', home.id)) return fail('build a Carrier Dock first');
  if (!stockable(item)) return fail('no such item');
  const e = econ(g, home.id);
  e.market ||= {};
  if (price === 0 || price === null || price === undefined) {
    delete e.market[item];
    return { ok: true, price: 0 };
  }
  if (!Number.isInteger(price) || price < 1 || price > PRICE_MAX) return fail(`a price is a whole number of credits from 1 to ${PRICE_MAX}`);
  e.market[item] = price;
  return { ok: true, price };
}

// A pilot of the same faction buys from a Builder's Carrier Dock. The goods go in the pilot's
// war goods hold, for their carrier (phase 4).
function dockBuy(g, name, builder, item, qty) {
  const home = homeOf(g, builder);
  if (!home) return fail('no such Builder');
  if (!hasBuilding(g, 'dock', home.id)) return fail(`${builder} has no Carrier Dock`);
  const e = econ(g, home.id);
  const p = pilot(g, name);
  if (!p.faction) return fail('choose a faction first');
  if (!e.faction) return fail(`${builder}'s dock isn't trading yet`);
  if (p.faction !== e.faction) return fail(`this dock only trades with ${F.the(e.faction)}`);
  // Only a real listing: a key like 'constructor' would find a function on any object.
  const price = stockable(item) && Object.hasOwn(e.market || {}, item) ? e.market[item] : 0;
  if (!Number.isInteger(price) || price < 1) return fail('that is not for sale here');
  if (!Number.isInteger(qty) || qty < 1) return fail('bad amount');
  const have = e.stock[item] || 0;
  if (qty > have) return fail(have ? `only ${have} in stock` : 'sold out');
  const cost = price * qty;
  if (p.credits < cost) return fail('not enough credits');
  p.credits -= cost;
  e.credits += cost;
  e.stock[item] = have - qty;
  p.hold[item] = (p.hold[item] || 0) + qty;
  log(g, `${name} bought ${amountOf(item, qty)} at ${builder}'s Carrier Dock`);
  F.alert(e, `${name} bought ${amountOf(item, qty)} at your Carrier Dock for ${cost} credits`);
  return { ok: true, cost };
}

// A pilot asks Builders of their faction for goods. The reward is held from their credits and
// paid out as the contract fills.
function postContract(g, name, item, amount, reward) {
  const p = pilot(g, name);
  if (!p.faction) return fail('choose a faction first');
  if (!CONTRACT_ITEMS.includes(item)) return fail('contracts are for materials and supplies');
  if (!Number.isInteger(amount) || amount < 1 || amount > CONTRACT_MAX) return fail(`ask for 1 to ${CONTRACT_MAX}`);
  if (!Number.isInteger(reward) || reward < 1) return fail('the reward must be at least 1 credit');
  if (g.contracts.filter((c) => c.pilot === name && c.status === 'open').length >= OPEN_CONTRACTS) return fail(`you already have ${OPEN_CONTRACTS} open contracts`);
  if (p.credits < reward) return fail('not enough credits');
  p.credits -= reward;
  const contract = { id: g.nextContractId++, pilot: name, faction: p.faction, item, amount, reward, filled: 0, paid: 0, contributions: {}, status: 'open' };
  const closed = g.contracts.filter((c) => c.status !== 'open');
  if (closed.length >= CLOSED_KEPT) {
    const drop = new Set(closed.slice(0, closed.length - CLOSED_KEPT + 1));
    g.contracts = g.contracts.filter((c) => !drop.has(c));
  }
  g.contracts.push(contract);
  log(g, `${name} posted a contract: ${amountOf(item, amount)} for ${reward} credits`);
  return { ok: true, contract };
}

// A Builder of the contract's faction fills some of it from stock and is paid their share of the
// reward; the last fill gets what's left, so the total paid is exactly the reward.
function fillContract(g, builder, id, qty) {
  const c = g.contracts.find((x) => x.id === Number(id) && x.status === 'open');
  if (!c) return fail('no open contract');
  const home = homeOf(g, builder);
  if (!home) return fail('you have no home planet');
  const e = econ(g, home.id);
  if (!e.faction) return fail('choose a faction first');
  if (e.faction !== c.faction) return fail(`that contract is for ${F.the(c.faction)}`);
  if (!Number.isInteger(qty) || qty < 1) return fail('bad amount');
  const left = c.amount - c.filled;
  if (qty > left) return fail(`only ${left} more needed`);
  if ((e.stock[c.item] || 0) < qty) return fail(`not enough ${H.ITEMS[c.item]?.name || c.item}`);
  const last = qty === left;
  const paid = last ? c.reward - c.paid : Math.min(c.reward - c.paid, Math.round((c.reward * qty) / c.amount));
  e.stock[c.item] -= qty;
  e.credits += paid;
  const p = pilot(g, c.pilot);
  p.hold[c.item] = (p.hold[c.item] || 0) + qty;
  c.filled += qty;
  c.paid += paid;
  c.contributions[builder] = (c.contributions[builder] || 0) + qty;
  log(g, `${builder} supplied ${amountOf(c.item, qty)} to ${c.pilot} for ${paid} credits`);
  if (last) {
    c.status = 'done';
    log(g, `${c.pilot}'s contract for ${amountOf(c.item, c.amount)} is filled`);
  }
  return { ok: true, paid };
}

// The pilot calls off a contract and gets back whatever of the reward hasn't been paid out.
function cancelContract(g, name, id) {
  const c = g.contracts.find((x) => x.id === Number(id) && x.status === 'open' && x.pilot === name);
  if (!c) return fail('no open contract of yours');
  const refund = c.reward - c.paid;
  pilot(g, name).credits += refund;
  c.status = 'cancelled';
  log(g, `${name} cancelled their contract for ${amountOf(c.item, c.amount)}`);
  return { ok: true, refunded: refund };
}

// A Builder gives goods from stock to their faction's war supply in their system, for the sector
// battles of phase 3, and earns War Merit by their value.
function donate(g, builder, item, qty) {
  const home = homeOf(g, builder);
  if (!home) return fail('you have no home planet');
  const e = econ(g, home.id);
  if (!e.faction) return fail('choose a faction first');
  if (!stockable(item)) return fail('no such item');
  if (!Number.isInteger(qty) || qty < 1) return fail('bad amount');
  if ((e.stock[item] || 0) < qty) return fail(`not enough ${H.ITEMS[item]?.name || item}`);
  e.stock[item] -= qty;
  const supply = ((g.war.supply[g.system.id] ||= {})[e.faction] ||= {});
  supply[item] = (supply[item] || 0) + qty;
  const before = F.rank(e.merit);
  e.merit = (e.merit || 0) + qty * MERIT_VALUE[item];
  const after = F.rank(e.merit);
  log(g, `${builder} donated ${amountOf(item, qty)} to ${F.the(e.faction)}`);
  if (after !== before) {
    F.alert(e, `${e.merit} War Merit: you are now a ${after.name}`);
    log(g, `${builder} is now a ${after.name} of ${F.the(e.faction)}`);
  }
  return { ok: true, merit: e.merit, rank: after.name };
}

// The Fence at the Star Port buys everything in a pilot's stash.
function sell(g, name) {
  if (!hasBuilding(g, 'spaceport')) return fail('no Star Port to sell at');
  const p = pilot(g, name);
  if (!p.stash.length) return fail('nothing to sell');
  const total = Math.round(H.value(p.stash) * H.FENCE_RATE);
  p.credits += total;
  log(g, `${name} sold ${p.stash.length} items to the Fence for ${total} credits`);
  p.stash = [];
  return { ok: true, credits: total };
}

module.exports = {
  BUILDINGS,
  NODES,
  COMMAND_SLOT,
  COMMAND_LEVELS,
  STORAGE_BASE,
  STORAGE_PER_LEVEL,
  POWER_BOOST,
  commandLevel,
  setCommandLevel,
  storageCap,
  BUILD_S,
  MAX_LEVEL,
  LEVEL_GROWTH,
  levelCost,
  upgradeBuilding,
  PRODUCES,
  demoTopUp,
  AUTO_SHIP_MS,
  newGalaxy,
  build,
  postJob,
  collect,
  deliver,
  tick,
  facility,
  ship,
  secure,
  startRaid,
  raidChanged,
  alarm,
  endRaid,
  recoverRaids,
  sell,
  queueShip,
  cancelShip,
  claimBase,
  OUTPOSTS,
  CONTRACT_ITEMS,
  MERIT_VALUE,
  PRICE_MAX,
  CONTRACT_MAX,
  OPEN_CONTRACTS,
  chooseFaction,
  demoCapture,
  setPrice,
  dockBuy,
  postContract,
  fillContract,
  cancelContract,
  donate,
  pilot,
  foundSite,
  placePiece,
  removePiece,
  clearObstacle,
  econ,
  owns,
};
