// Galaxy rules for the prototype: one star system, one planet, a few buildings and jobs.
// Pure state + functions so the server and the tests share the same logic.
// Facilities and raids on them are in heist.js; this file hooks them into the galaxy.

const H = require('./heist');
const N = require('./navy');
const S = require('./sites');

const BUILDINGS = {
  mine: { name: 'Mine', cost: { metal: 10 }, needs: null },
  extractor: { name: 'Ice Extractor', cost: { metal: 15 }, needs: null },
  habitat: { name: 'Habitat', cost: { metal: 20 }, needs: null },
  spaceport: { name: 'Spaceport', cost: { metal: 30 }, needs: null },
  hydroponics: { name: 'Hydroponics', cost: { metal: 20, ice: 10 }, needs: 'ice' },
  // Facilities: they fill a vault with goods the Builder ships home, and Explorers can raid them.
  refinery: { name: 'Mining Refinery', cost: { metal: 40 }, facility: true },
  lab: { name: 'Research Outpost', cost: { metal: 30, ice: 10 }, facility: true },
  spire: { name: 'Data Spire', cost: { metal: 50, credits: 150 }, facility: true },
  // Builds warships for the Builder's navy (navy.js). One per base, after a Spaceport.
  foundry: { name: 'Ship Foundry', cost: { metal: 60, ice: 10 }, needsBuilding: 'spaceport', limit: 1 },
};

// Passive income, so a Builder progresses with no pilots online. A tick is 5 s.
// Pilots' ice jobs still pay off: one delivery is 10 ice, an Extractor takes 30 s per ice.
const PRODUCES = {
  mine: { metal: 1 }, // 12 metal a minute
  extractor: { ice: 1 / 6 }, // 2 ice a minute
  habitat: { credits: 1 }, // rent: 12 credits a minute
  hydroponics: { credits: 2 }, // sells food: 24 credits a minute
};
const AUTO_SHIP_MS = 5 * 60_000; // a facility's freighter takes the vault home on its own this often
const POPULATION_PER_HABITAT = 50;

function newGalaxy() {
  return {
    system: {
      id: 'teal-prime',
      name: 'Teal Prime',
      planets: [{ id: 'aster', name: 'Aster', slots: 6, buildings: [] }],
    },
    stock: { metal: 60, ice: 0 },
    credits: 500,
    population: 0,
    unlocked: ['mine', 'extractor', 'habitat', 'spaceport', 'refinery', 'lab', 'spire', 'foundry'],
    jobs: [],
    raids: [], // raids in progress, as everyone may see them (no container contents)
    raidLog: [],
    attacks: [], // fleets on their way to or back from a satellite site
    attackLog: [],
    pilots: {},
    feed: [],
    navy: { corvette: 0, frigate: 0, destroyer: 0 },
    nextJobId: 1,
  };
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
    unlocked: ['mine', 'extractor', 'habitat', 'spaceport', 'refinery', 'lab', 'spire', 'foundry'],
    navy: { corvette: 0, frigate: 0, destroyer: 0 },
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
    };
    log(g, `${name} took charge of ${aster.name}`);
    return aster;
  }
  const taken = new Set(g.system.planets.map((p) => p.name));
  const pname = PLANET_NAMES.find((n) => !taken.has(n)) || `Colony ${g.system.planets.length + 1}`;
  const p = { id: pname.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name: pname, owner: name, slots: 6, buildings: [] };
  g.system.planets.push(p);
  g.bases[name] = newEconomy();
  log(g, `${name} founded a base on ${pname}`);
  return p;
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
  return g.system.planets.some((p) => (!planetId || p.owner === owner) && p.buildings.some((b) => b.type === type));
}

function build(g, planetId, slot, type) {
  const p = planet(g, planetId);
  const def = BUILDINGS[type];
  if (!p) return fail('no such planet');
  if (!def) return fail('no such building');
  const e = econ(g, planetId);
  if (!e.unlocked.includes(type)) return fail(`${def.name} is locked`);
  if (p.kind === 'satellite') return fail('satellite sites hold one facility; place defences instead');
  if (def.facility) return fail(`${def.name} goes on a satellite site: found one from the Build menu`);
  if (!Number.isInteger(slot) || slot < 0 || slot >= p.slots) return fail('bad slot');
  if (p.buildings.some((b) => b.slot === slot)) return fail('slot taken');
  if (def.needsBuilding && !hasBuilding(g, def.needsBuilding, planetId)) return fail(`build a ${BUILDINGS[def.needsBuilding].name} first`);
  if (def.limit && g.system.planets.reduce((n, q) => n + (q.owner === p.owner ? q.buildings.filter((x) => x.type === type).length : 0), 0) >= def.limit)
    return fail(`you already have a ${def.name}`);
  const err = pay(e, def.cost);
  if (err) return fail(err);
  const b = { slot, type };
  if (def.facility) Object.assign(b, { security: 1, vault: {}, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} });
  if (type === 'foundry') b.queue = [];
  p.buildings.push(b);
  if (type === 'habitat') e.population += POPULATION_PER_HABITAT;
  log(g, `${def.name} built on ${p.name}`);
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

function postJob(g, resource, amount, reward, planetId = g.system.planets[0].id) {
  if (!hasBuilding(g, 'spaceport', planetId)) return fail('build a Spaceport first');
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
  if (!g.pilots[name]) g.pilots[name] = { credits: 0, reputation: 0, cargo: {} };
  const p = g.pilots[name];
  p.stash ||= []; // loot extracted from raids: [{item, qty, fih}]
  p.raids ||= { runs: 0, extracted: 0 };
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
  let changed = attackTick(g, now);
  for (const p of g.system.planets)
    for (const b of p.buildings)
      if (b.type === 'foundry')
        for (const name of N.tick(econ(g, p.id), b, now)) {
          log(g, `${name} launched from the Ship Foundry on ${p.name}`);
          changed = true;
        }
  for (const p of g.system.planets) {
    for (const b of p.buildings) {
      const makes = PRODUCES[b.type];
      if (makes) {
        const e = econ(g, p.id);
        for (const [res, rate] of Object.entries(makes)) {
          // Fractional rates build up in b.carry and pay out whole units.
          b.carry = (b.carry || 0) + rate;
          const whole = Math.floor(b.carry + 1e-9);
          if (whole < 1) continue;
          b.carry -= whole;
          if (res === 'credits') e.credits += whole;
          else e.stock[res] = (e.stock[res] || 0) + whole;
        }
        changed = true;
      }
      const fac = H.FACILITIES[b.type];
      if (!fac) continue;
      // The automatic freighter: goods sit in the vault (and can be raided) until it comes.
      b.autoShipAt ||= now + AUTO_SHIP_MS;
      if (now >= b.autoShipAt) {
        b.autoShipAt = now + AUTO_SHIP_MS;
        if (!g.raids.some((r) => r.planet === p.id && r.slot === b.slot) && ship(g, p.id, b.slot, now, true).ok) changed = true;
      }
      b.made += 1;
      for (const m of fac.makes) {
        if (b.made % m.every === 0 && (b.vault[m.item] || 0) < m.cap) {
          b.vault[m.item] = (b.vault[m.item] || 0) + 1;
          changed = true;
        }
      }
    }
  }
  // However ice arrived (an Extractor, a pilot's delivery, loot), it unlocks Hydroponics.
  for (const e of [g, ...Object.values(g.bases || {})])
    if (e.stock.ice > 0 && !e.unlocked.includes('hydroponics')) {
      e.unlocked.push('hydroponics');
      log(g, 'Ice in stock: Hydroponics unlocked');
      changed = true;
    }
  return changed;
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

// --- Satellite sites (sites.js) ------------------------------------------------------------

// A Builder founds a satellite site off their home planet for a new facility.
function foundSite(g, owner, type) {
  const def = BUILDINGS[type];
  if (!def || !def.facility) return fail('only facilities go on satellite sites');
  const home = g.system.planets.find((p) => p.owner === owner && p.kind !== 'satellite');
  if (!home) return fail('you have no home planet');
  const e = econ(g, home.id);
  if (!e.unlocked.includes(type)) return fail(`${def.name} is locked`);
  const r = S.newSite(g, owner, home, H.FACILITIES[type].name);
  if (!r.ok) return r;
  const err = pay(e, def.cost);
  if (err) return fail(err);
  r.site.buildings.push({ slot: 0, type, security: 1, vault: {}, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} });
  g.system.planets.push(r.site);
  log(g, `${owner} founded ${r.site.name}`);
  return { ok: true, site: r.site };
}

function site(g, siteId) {
  const p = planet(g, siteId);
  return p && p.kind === 'satellite' ? p : null;
}

function placePiece(g, siteId, type, x, y) {
  const st = site(g, siteId);
  if (!st) return fail('no such satellite site');
  if (g.raids.some((r) => r.planet === siteId)) return fail('not during a raid');
  const e = econ(g, siteId);
  const r = S.place(st, type, x, y, (cost) => pay(e, cost));
  if (r.ok) log(g, `${r.name} built at ${st.name}`);
  return r;
}

function removePiece(g, siteId, pieceId) {
  const st = site(g, siteId);
  if (!st) return fail('no such satellite site');
  if (g.raids.some((r) => r.planet === siteId)) return fail('not during a raid');
  return S.remove(st, pieceId, econ(g, siteId));
}

// The Builder sends a freighter: the vault's goods go to HQ stock. Intel sells on arrival.
function ship(g, planetId, slot, now, auto = false) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
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
  b.autoShipAt = now + AUTO_SHIP_MS;
  log(g, `${auto ? 'Scheduled freighter' : 'Freighter'} from ${facilityName(g, planetId, b)} delivered ${parts.join(', ')}`);
  return { ok: true };
}

// The Builder upgrades a facility's security: more guards, turrets, rarer loot, a longer clock.
function secure(g, planetId, slot) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
  const next = H.SECURITY[b.security + 1];
  if (!next) return fail('security is already at the top tier');
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
  if (g.raids.some((r) => r.pilot === name)) return fail('you are already raiding');
  if (g.raids.some((r) => r.planet === planetId && r.slot === slot)) return fail('someone is already inside');
  if (now < b.cooldownUntil) return fail(`security is on alert for another ${Math.ceil((b.cooldownUntil - now) / 1000)} s`);
  const fname = facilityName(g, planetId, b);
  const run = H.startRun({ facility: b, facilityName: fname, pilot: name, seed, lootSeed, now });
  run.planet = planetId;
  run.slot = slot;
  pilot(g, name).raids.runs += 1;
  g.raids.push({ id: run.id, pilot: name, planet: planetId, slot, facility: fname, heat: 0, level: 0, endsAt: run.endsAt, vaultOpen: false });
  log(g, `Intruder alert: ${name} has boarded ${fname}`);
  return { ok: true, run };
}

// Keeps the public summary in step with the run.
function raidChanged(g, run) {
  const r = g.raids.find((x) => x.id === run.id);
  if (r) Object.assign(r, { heat: run.heat, level: H.heatLevel(run.heat), vaultOpen: run.vaultOpen });
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
    b.cooldownUntil = now + H.RAID_COOLDOWN_MS;
  }
  const p = pilot(g, run.pilot);
  for (const k of result.kept) p.stash.push(k);
  if (outcome === 'extracted') p.raids.extracted += 1;
  g.raids = g.raids.filter((r) => r.id !== run.id);
  const words = { extracted: 'escaped from', killed: 'was killed in', mia: 'was caught when the clock ran out in', bailed: 'bailed out of' };
  const haul = result.kept.length ? ` with ${result.value} credits of loot` : '';
  log(g, `${run.pilot} ${words[outcome]} ${run.facilityName}${haul}`);
  g.raidLog.push({ at: now, pilot: run.pilot, facility: run.facilityName, outcome, value: result.value, stolen: result.stolen });
  if (g.raidLog.length > 20) g.raidLog.shift();
  return result;
}

// After a server restart nothing is inside any facility, so escrowed goods go home.
// Also brings saves from before facilities existed up to date.
function recoverRaids(g) {
  g.raids = [];
  g.raidLog ||= [];
  g.bases ||= {};
  g.attacks ||= [];
  g.attackLog ||= [];
  for (const e of [g, ...Object.values(g.bases)]) {
    N.ensure(e);
    for (const type of ['extractor', 'refinery', 'lab', 'spire', 'foundry']) if (!e.unlocked.includes(type)) e.unlocked.push(type);
  }
  for (const p of g.system.planets) for (const b of p.buildings) if (b.type === 'foundry') b.queue ||= [];
  for (const p of g.system.planets)
    for (const b of p.buildings) {
      if (!b.escrow) continue;
      for (const [item, qty] of Object.entries(b.escrow)) b.vault[item] = (b.vault[item] || 0) + qty;
      b.escrow = {};
    }
}

// The Builder queues a warship at the Ship Foundry.
function queueShip(g, planetId, slot, shipId, now) {
  const p = planet(g, planetId);
  const b = p && p.buildings.find((x) => x.slot === slot && x.type === 'foundry');
  if (!b) return fail('no Ship Foundry there');
  const e = econ(g, planetId);
  const r = N.queueShip(e, b, shipId, now, (cost) => pay(e, cost));
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

// --- Fleet attacks on satellite sites ------------------------------------------------------

// A site's whole defence: its placed defences, the turrets its security tier adds, and the core
// (guards add attack, the tier adds hull).
function siteDefence(g, siteId) {
  const st = site(g, siteId);
  const b = st.buildings[0];
  const tier = H.SECURITY[b.security];
  const d = S.defence(st);
  return { attack: d.attack + tier.turrets * S.PIECES.turret.attack + tier.guards, hull: d.hull + tier.turrets * S.PIECES.turret.hull + 40 * b.security };
}

// A Builder sends every ship in their navy (or `ships`, {id: count}) at another Builder's site.
function launchAttack(g, owner, siteId, now, ships = null) {
  const st = site(g, siteId);
  if (!st) return fail('no such satellite site');
  if (st.owner === owner) return fail('that is your own site');
  if (!st.owner) return fail('nobody owns that site');
  if ((st.shieldUntil || 0) > now) return fail(`${st.name} is shielded for ${Math.ceil((st.shieldUntil - now) / 60000)} more min`);
  const home = g.system.planets.find((p) => p.owner === owner && p.kind !== 'satellite');
  if (!home) return fail('you have no home planet');
  const e = econ(g, home.id);
  N.ensure(e);
  const send = {};
  for (const id of Object.keys(N.SHIPS)) {
    const n = ships ? Math.min(Math.max(0, Math.floor(ships[id] || 0)), e.navy[id]) : e.navy[id];
    if (n > 0) send[id] = n;
  }
  if (!Object.keys(send).length) return fail('you have no ships to send');
  if ((g.attacks ||= []).some((a) => a.attacker === owner && a.target === siteId && a.status === 'flying'))
    return fail('your fleet is already on its way there');
  for (const [id, n] of Object.entries(send)) e.navy[id] -= n;
  const leg = N.travelMs(send);
  const attack = { id: (g.nextAttackId = (g.nextAttackId || 0) + 1), attacker: owner, defender: st.owner, target: siteId, siteName: st.name, ships: send, status: 'flying', arriveAt: now + leg, leg };
  g.attacks.push(attack);
  log(g, `${owner}'s fleet is heading for ${st.name}`);
  return { ok: true, attack };
}

// Fleets that reach their target fight; survivors fly home with any loot and rejoin the navy.
function attackTick(g, now) {
  let changed = false;
  for (const a of g.attacks || []) {
    if (a.status === 'flying' && now >= a.arriveAt) {
      changed = true;
      const st = site(g, a.target);
      const b = st && st.buildings[0];
      if (!b) {
        Object.assign(a, { status: 'returning', returnAt: now + a.leg, survivors: a.ships, lost: {}, loot: {}, won: false });
        continue;
      }
      const fight = N.battle(a.ships, siteDefence(g, a.target));
      const loot = {};
      if (fight.won && Object.keys(fight.survivors).length) {
        for (const [item, qty] of Object.entries(b.vault)) {
          if (!H.ITEMS[item]) continue;
          const take = qty > 0 ? Math.max(1, Math.floor(qty * N.LOOT_SHARE)) : 0;
          if (take > 0) {
            b.vault[item] -= take;
            loot[item] = take;
          }
        }
        st.shieldUntil = now + N.SHIELD_MS;
      }
      Object.assign(a, { status: 'returning', returnAt: now + a.leg, survivors: fight.survivors, lost: fight.lost, loot, won: fight.won });
      const haul = Object.entries(loot).map(([item, q]) => `${q} ${H.ITEMS[item].name}`).join(', ');
      log(g, fight.won
        ? `${a.attacker}'s fleet broke the defences of ${a.siteName}${haul ? ` and took ${haul}` : ''}`
        : `${a.siteName} drove off ${a.attacker}'s fleet`);
      (g.attackLog ||= []).push({ at: now, attacker: a.attacker, defender: a.defender, site: a.siteName, won: fight.won, lost: fight.lost, loot });
      if (g.attackLog.length > 20) g.attackLog.shift();
    } else if (a.status === 'returning' && now >= a.returnAt) {
      changed = true;
      a.status = 'home';
      const home = g.system.planets.find((p) => p.owner === a.attacker && p.kind !== 'satellite');
      if (!home) continue;
      const e = econ(g, home.id);
      for (const [id, n] of Object.entries(a.survivors)) e.navy[id] += n;
      for (const [item, qty] of Object.entries(a.loot)) {
        if (H.ITEMS[item].cat === 'intel') e.credits += H.ITEMS[item].value * qty;
        else e.stock[item] = (e.stock[item] || 0) + qty;
      }
      log(g, `${a.attacker}'s fleet is back from ${a.siteName}`);
    }
  }
  if (changed) g.attacks = (g.attacks || []).filter((a) => a.status !== 'home');
  return changed;
}

// The Fence at the Spaceport buys everything in a pilot's stash.
function sell(g, name) {
  if (!hasBuilding(g, 'spaceport')) return fail('no Spaceport to sell at');
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
  launchAttack,
  siteDefence,
  foundSite,
  placePiece,
  removePiece,
  econ,
  owns,
};
