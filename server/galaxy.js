// Galaxy rules for the prototype: one star system, one planet, a few buildings and jobs.
// Pure state + functions so the server and the tests share the same logic.
// Facilities and raids on them are in heist.js; this file hooks them into the galaxy.

const H = require('./heist');

const BUILDINGS = {
  mine: { name: 'Mine', cost: { metal: 10 }, needs: null },
  habitat: { name: 'Habitat', cost: { metal: 20 }, needs: null },
  spaceport: { name: 'Spaceport', cost: { metal: 30 }, needs: null },
  hydroponics: { name: 'Hydroponics', cost: { metal: 20, ice: 10 }, needs: 'ice' },
  // Facilities: they fill a vault with goods the Builder ships home, and Explorers can raid them.
  refinery: { name: 'Mining Refinery', cost: { metal: 40 }, facility: true },
  lab: { name: 'Research Outpost', cost: { metal: 30, ice: 10 }, facility: true },
  spire: { name: 'Data Spire', cost: { metal: 50, credits: 150 }, facility: true },
};

const MINE_RATE = 1; // metal per mine per tick
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
    unlocked: ['mine', 'habitat', 'spaceport', 'refinery', 'lab', 'spire'],
    jobs: [],
    raids: [], // raids in progress, as everyone may see them (no container contents)
    raidLog: [],
    pilots: {},
    feed: [],
    nextJobId: 1,
  };
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

function hasBuilding(g, type) {
  return g.system.planets.some((p) => p.buildings.some((b) => b.type === type));
}

function build(g, planetId, slot, type) {
  const p = planet(g, planetId);
  const def = BUILDINGS[type];
  if (!p) return fail('no such planet');
  if (!def) return fail('no such building');
  if (!g.unlocked.includes(type)) return fail(`${def.name} is locked`);
  if (!Number.isInteger(slot) || slot < 0 || slot >= p.slots) return fail('bad slot');
  if (p.buildings.some((b) => b.slot === slot)) return fail('slot taken');
  const err = pay(g, def.cost);
  if (err) return fail(err);
  const b = { slot, type };
  if (def.facility) Object.assign(b, { security: 1, vault: {}, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} });
  p.buildings.push(b);
  if (type === 'habitat') g.population += POPULATION_PER_HABITAT;
  log(g, `${def.name} built on ${p.name}`);
  return { ok: true };
}

// Takes a cost ({resource: amount}, where `credits` means the wallet) or says what is short.
function pay(g, cost) {
  for (const [res, amount] of Object.entries(cost)) {
    const have = res === 'credits' ? g.credits : g.stock[res] || 0;
    if (have < amount) return `not enough ${res === 'credits' ? 'credits' : H.ITEMS[res]?.name || res}`;
  }
  for (const [res, amount] of Object.entries(cost)) {
    if (res === 'credits') g.credits -= amount;
    else g.stock[res] -= amount;
  }
  return null;
}

function postJob(g, resource, amount, reward) {
  if (!hasBuilding(g, 'spaceport')) return fail('build a Spaceport first');
  if (!(amount > 0) || !(reward > 0)) return fail('bad job');
  if (g.credits < reward) return fail('not enough credits');
  g.credits -= reward; // held until the job completes
  const job = {
    id: g.nextJobId++,
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
  g.stock[job.resource] = (g.stock[job.resource] || 0) + give;
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
  if (job.resource === 'ice' && !g.unlocked.includes('hydroponics')) {
    g.unlocked.push('hydroponics');
    log(g, 'Ice in stock: Hydroponics unlocked');
  }
}

function tick(g) {
  let changed = false;
  for (const p of g.system.planets) {
    for (const b of p.buildings) {
      if (b.type === 'mine') {
        g.stock.metal += MINE_RATE;
        changed = true;
      }
      const fac = H.FACILITIES[b.type];
      if (!fac) continue;
      b.made += 1;
      for (const m of fac.makes) {
        if (b.made % m.every === 0 && (b.vault[m.item] || 0) < m.cap) {
          b.vault[m.item] = (b.vault[m.item] || 0) + 1;
          changed = true;
        }
      }
    }
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
  return `${planet(g, planetId).name} ${H.FACILITIES[b.type].name} ${b.slot + 1}`;
}

// The Builder sends a freighter: the vault's goods go to HQ stock. Intel sells on arrival.
function ship(g, planetId, slot, now) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
  if (now < b.shipReadyAt) return fail(`freighter back in ${Math.ceil((b.shipReadyAt - now) / 1000)} s`);
  const goods = Object.entries(b.vault).filter(([, q]) => q > 0);
  if (!goods.length) return fail('the vault is empty');
  const parts = [];
  for (const [item, qty] of goods) {
    if (H.ITEMS[item].cat === 'intel') g.credits += H.ITEMS[item].value * qty;
    else g.stock[item] = (g.stock[item] || 0) + qty;
    parts.push(`${qty} ${H.ITEMS[item].name}`);
    b.vault[item] = 0;
  }
  b.shipReadyAt = now + H.SHIP_COOLDOWN_MS;
  log(g, `Freighter from ${facilityName(g, planetId, b)} delivered ${parts.join(', ')}`);
  return { ok: true };
}

// The Builder upgrades a facility's security: more guards, turrets, rarer loot, a longer clock.
function secure(g, planetId, slot) {
  const b = facility(g, planetId, slot);
  if (!b) return fail('no such facility');
  const next = H.SECURITY[b.security + 1];
  if (!next) return fail('security is already at the top tier');
  if (g.raids.some((r) => r.planet === planetId && r.slot === slot)) return fail('not during a raid');
  const err = pay(g, next.cost);
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
  const err = pay(g, { credits: H.ALARM_COST });
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
  for (const type of ['refinery', 'lab', 'spire']) if (!g.unlocked.includes(type)) g.unlocked.push(type);
  for (const p of g.system.planets)
    for (const b of p.buildings) {
      if (!b.escrow) continue;
      for (const [item, qty] of Object.entries(b.escrow)) b.vault[item] = (b.vault[item] || 0) + qty;
      b.escrow = {};
    }
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
};
