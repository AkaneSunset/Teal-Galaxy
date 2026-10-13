// Galaxy rules for the prototype: one star system, one planet, a few buildings and jobs.
// Pure state + functions so the server and the tests share the same logic.

const BUILDINGS = {
  mine: { name: 'Mine', cost: { metal: 10 }, needs: null },
  habitat: { name: 'Habitat', cost: { metal: 20 }, needs: null },
  spaceport: { name: 'Spaceport', cost: { metal: 30 }, needs: null },
  hydroponics: { name: 'Hydroponics', cost: { metal: 20, ice: 10 }, needs: 'ice' },
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
    unlocked: ['mine', 'habitat', 'spaceport'],
    jobs: [],
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
  for (const [res, amount] of Object.entries(def.cost)) {
    if ((g.stock[res] || 0) < amount) return fail(`not enough ${res}`);
  }
  for (const [res, amount] of Object.entries(def.cost)) g.stock[res] -= amount;
  p.buildings.push({ slot, type });
  if (type === 'habitat') g.population += POPULATION_PER_HABITAT;
  log(g, `${def.name} built on ${p.name}`);
  return { ok: true };
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
  return g.pilots[name];
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
  let mines = 0;
  for (const p of g.system.planets) mines += p.buildings.filter((b) => b.type === 'mine').length;
  g.stock.metal += mines * MINE_RATE;
  return mines > 0;
}

module.exports = { BUILDINGS, newGalaxy, build, postJob, collect, deliver, tick };
