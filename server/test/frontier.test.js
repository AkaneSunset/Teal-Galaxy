// Terraforming and the Frontier: leased star clusters, the Terraformer's voyage and the hunt for
// it, the three stages, the colony, and what it exports.

const test = require('node:test');
const assert = require('node:assert');
const FR = require('../frontier.ts');
const G = require('../galaxy');
const T = require('../tunables.ts');

const HOUR = 3600_000;
const t0 = 1_000_000;

// Akane (Terran Compact) is the Founder; Rin flies with her, Kite for the Ashen Collective.
function setup() {
  const g = G.newGalaxy();
  for (const [name, f] of [['Akane', 'compact'], ['Rin', 'compact'], ['Kite', 'ashen']]) {
    G.chooseFaction(g, 'explorer', name, f);
    g.pilots[name].credits = 5_000_000;
  }
  return g;
}

// A leased cluster with its first planet surveyed, and a Terraformer aimed at it.
function leased(g) {
  const cluster = FR.leaseCluster(g, 'Akane', t0).cluster;
  const c = g.frontier.clusters[cluster];
  const planet = c.systems[0].planets[0].id;
  for (const point of [0, 1, 2]) assert.ok(FR.survey(g, 'Rin', cluster, planet, point, t0).ok);
  const ship = FR.leaseShip(g, 'Akane', cluster, t0).ship;
  assert.ok(FR.setTarget(g, 'Akane', ship, planet).ok);
  return { cluster, c, planet, ship, s: g.frontier.ships[ship] };
}

// The shortest way from where the ship is to its target, one jump at a time, cooldowns waited out.
function fly(g, ship, from = t0) {
  const s = g.frontier.ships[ship];
  let t = from;
  while (s.at !== s.targetSystem) {
    const next = FR.neighbours(g, s.at).find((n) => FR.lanes(g, n, s.targetSystem) === FR.lanes(g, s.at, s.targetSystem) - 1);
    assert.ok(FR.jump(g, 'Akane', ship, next, t).ok, `jump to ${next}`);
    t += T.get().frontier.jumpCooldownHours * HOUR;
  }
  return t;
}

test('a star cluster is a one-off lease of 5 to 10 systems from the faction pool, and kept for good', () => {
  const g = setup();
  const price = T.get().frontier.clusterLease;
  const r = FR.leaseCluster(g, 'Akane', t0);
  assert.ok(r.ok);
  assert.strictEqual(r.cluster, 'compact-1');
  assert.strictEqual(g.pilots.Akane.credits, 5_000_000 - price);
  const c = g.frontier.clusters['compact-1'];
  assert.ok(c.systems.length >= 5 && c.systems.length <= 10);
  assert.strictEqual(FR.leaseCluster(g, 'Rin', t0).cluster, 'compact-2', 'nobody competes: the numbers count up');
  assert.strictEqual(FR.leaseCluster(g, 'Kite', t0).cluster, 'ashen-1');
  // Weeks later nothing has changed hands.
  FR.tick(g, t0 + 1000 * HOUR);
  assert.strictEqual(c.owner, 'Akane');
  assert.ok(FR.sellBack(g, 'Akane', 'compact-1').ok);
  assert.strictEqual(g.frontier.clusters['compact-1'], undefined);
});

test('three scans grade a planet; the faction sees the grades, enemies do not', () => {
  const g = setup();
  const cluster = FR.leaseCluster(g, 'Akane', t0).cluster;
  const planet = g.frontier.clusters[cluster].systems[0].planets[0].id;
  assert.match(FR.survey(g, 'Kite', cluster, planet, 0, t0).reason, /own faction/);
  assert.strictEqual(FR.survey(g, 'Rin', cluster, planet, 0, t0).points, 1);
  assert.strictEqual(FR.survey(g, 'Rin', cluster, planet, 0, t0).points, 1, 'the same point twice counts once');
  FR.survey(g, 'Rin', cluster, planet, 1, t0);
  const r = FR.survey(g, 'Rin', cluster, planet, 2, t0);
  assert.deepStrictEqual(r.grades, FR.gradesOf(planet));
  assert.strictEqual(g.frontier.clusters[cluster].surveys[planet].by, 'Rin', 'the Pathfinder');
  assert.ok(FR.view(g, 'compact', t0).clusters[cluster].surveys[planet]);
  assert.deepStrictEqual(FR.view(g, 'ashen', t0).clusters[cluster].surveys, {});
});

test('the Terraformer: one week to establish it in orbit, then a renewal fee every week it is not', () => {
  const g = setup();
  const { ship, s } = leased(g);
  assert.strictEqual(s.at, 'fortitude', "it leaves from the faction's shipyard");
  const before = g.pilots.Akane.credits;
  const fee = T.get().frontier.renewalFee;
  FR.tick(g, t0 + 167 * HOUR);
  assert.strictEqual(g.pilots.Akane.credits, before);
  FR.tick(g, t0 + 168 * HOUR);
  assert.strictEqual(g.pilots.Akane.credits, before - fee);
  FR.tick(g, t0 + 2 * 168 * HOUR);
  assert.strictEqual(s.renewals, 2);
  // Established, the fees stop.
  const t = fly(g, ship, t0 + 2 * 168 * HOUR);
  assert.ok(FR.establish(g, 'Akane', ship, t).ok);
  const paid = g.pilots.Akane.credits;
  FR.tick(g, t + 10 * 168 * HOUR);
  assert.strictEqual(g.pilots.Akane.credits, paid);
  assert.strictEqual(s.state, 'orbit');
});

test("a Founder who can't pay the renewal fee loses the Terraformer lease", () => {
  const g = setup();
  const { s } = leased(g);
  g.pilots.Akane.credits = 0;
  FR.tick(g, t0 + 168 * HOUR);
  assert.strictEqual(s.state, 'lapsed');
});

test('the voyage: one lane at a time with a cooldown, out of the war map into the region and the cluster', () => {
  const g = setup();
  const { ship, s } = leased(g);
  const route = FR.lanes(g, s.at, s.targetSystem);
  assert.ok(route >= 7, `fortitude, marrow, the gate, ${4} deep levels, the cluster (${route})`);
  assert.match(FR.jump(g, 'Akane', ship, s.targetSystem, t0).reason, /one lane at a time/);
  assert.ok(FR.jump(g, 'Akane', ship, 'marrow', t0).ok);
  assert.match(FR.jump(g, 'Akane', ship, 'fr-compact-gate', t0 + HOUR).reason, /cooling down/);
  assert.match(FR.establish(g, 'Akane', ship, t0).reason, /target world first/);
  fly(g, ship, t0 + 6 * HOUR);
  assert.ok(FR.establish(g, 'Akane', ship, t0 + 100 * HOUR).ok);
  assert.strictEqual(s.state, 'orbit');
});

test('the hunt: kept quiet, decoded from a data shard, tracked by its traces, found, intercepted and destroyed', () => {
  const g = setup();
  const { ship, s } = leased(g);
  assert.deepStrictEqual(FR.view(g, 'ashen', t0).ships, {}, 'never announced');
  assert.ok(FR.view(g, 'compact', t0).ships[ship], 'its own faction sees it');
  // A data shard from a raid tells the Collective that Akane has one, not where it is.
  assert.match(FR.decode(g, 'Kite', 'compact').reason, /Data shard/);
  g.pilots.Kite.stash.push({ item: 'shard', qty: 1 });
  const lead = FR.decode(g, 'Kite', 'compact');
  assert.deepStrictEqual(lead.leads, [{ ship, owner: 'Akane', cluster: 'compact-1', underway: false }]);
  assert.strictEqual(g.pilots.Kite.stash.length, 0, 'the shard is spent');
  // It jumps from Fortitude to Marrow Reach to the gate; the trace in Marrow points the way on.
  FR.jump(g, 'Akane', ship, 'marrow', t0);
  FR.jump(g, 'Akane', ship, 'fr-compact-gate', t0 + 6 * HOUR);
  const traces = FR.scan(g, 'Kite', 'marrow', t0 + 7 * HOUR);
  assert.deepStrictEqual(traces.traces.map((x) => x.to), ['fr-compact-gate']);
  assert.deepStrictEqual(FR.scan(g, 'Kite', 'marrow', t0 + 6 * HOUR + 13 * HOUR).traces, [], 'traces fade');
  // Kite can't intercept what the Collective hasn't found.
  assert.match(FR.intercept(g, 'Kite', ship, 'fr-compact-gate', t0 + 7 * HOUR).reason, /find it first/);
  assert.deepStrictEqual(FR.scan(g, 'Kite', 'fr-compact-gate', t0 + 7 * HOUR).found, [ship]);
  assert.strictEqual(FR.view(g, 'ashen', t0 + 7 * HOUR).ships[ship].at, 'fr-compact-gate', 'found, the Collective sees it');
  assert.ok(FR.intercept(g, 'Kite', ship, 'fr-compact-gate', t0 + 7 * HOUR).ok);
  assert.match(FR.jump(g, 'Akane', ship, 'fr-compact-d1-0', t0 + 13 * HOUR).reason, /under attack/);
  assert.ok(FR.interceptResult(g, ship, true, t0 + 8 * HOUR).destroyed);
  assert.strictEqual(s.state, 'destroyed', 'one lost interception destroys it');
});

test('an interception fought off: the attackers have to find it again', () => {
  const g = setup();
  const { ship, s } = leased(g);
  FR.jump(g, 'Akane', ship, 'marrow', t0);
  FR.scan(g, 'Kite', 'marrow', t0 + HOUR);
  FR.intercept(g, 'Kite', ship, 'marrow', t0 + HOUR);
  assert.ok(FR.escort(g, 'Rin', ship, true).ok);
  assert.match(FR.escort(g, 'Kite', ship, true).reason, /own faction/);
  assert.strictEqual(FR.interceptResult(g, ship, false, t0 + 2 * HOUR).destroyed, false);
  assert.strictEqual(s.state, 'voyage');
  assert.match(FR.intercept(g, 'Kite', ship, 'marrow', t0 + 2 * HOUR).reason, /find it first/);
});

// A Terraformer established in orbit, with Akane and Rin holding what its stages need.
function inOrbit(g) {
  const L = leased(g);
  const t = fly(g, L.ship);
  assert.ok(FR.establish(g, 'Akane', L.ship, t).ok);
  for (const name of ['Akane', 'Rin']) Object.assign(g.pilots[name].cargo, { fuel: 1000, isotope: 100, ice: 5000, alloy: 1000, exotic: 50 });
  return { ...L, t };
}

test('the stages: engines fitted, bars filled by pilots the Founder pays, each with a minimum time', () => {
  const g = setup();
  const { ship, s, t } = inOrbit(g);
  const need = FR.needs(g, s);
  assert.ok(need.fuel > 0 && need.isotope > 0);
  const akane = g.pilots.Akane.credits;
  const r = FR.deliver(g, 'Rin', ship, 'fuel', need.fuel, t);
  assert.strictEqual(r.paid, Math.round(need.fuel * 12 * T.get().frontier.deliveryPay));
  assert.strictEqual(g.pilots.Akane.credits, akane - r.paid);
  assert.strictEqual(FR.deliver(g, 'Akane', ship, 'isotope', 1000, t).delivered, need.isotope, 'only what the bar needs; the Founder delivers unpaid');
  assert.strictEqual(s.stage, 0, 'the bar is full but the stage takes 3 days');
  FR.tick(g, t + 72 * HOUR);
  assert.strictEqual(s.stage, 1);
  assert.match(FR.deliver(g, 'Rin', ship, 'ice', 10, t + 72 * HOUR).reason, /Hydro Seeder first/);
  assert.ok(FR.buyEngine(g, 'Akane', ship, 'water').ok);
  assert.strictEqual(FR.deliver(g, 'Akane', ship, 'engine_water', 1, t + 72 * HOUR).fitted, 'water');
  FR.deliver(g, 'Rin', ship, 'ice', 5000, t + 72 * HOUR);
  // An enemy assault on the engine sets the stage back a quarter.
  const ice = s.bars.ice;
  FR.stageSetback(g, ship);
  assert.strictEqual(s.bars.ice, Math.floor(ice * 0.75));
  FR.deliver(g, 'Rin', ship, 'ice', 5000, t + 72 * HOUR);
  FR.tick(g, t + 144 * HOUR);
  assert.strictEqual(s.stage, 2);
  FR.buyEngine(g, 'Akane', ship, 'biosphere');
  FR.deliver(g, 'Akane', ship, 'engine_biosphere', 1, t + 144 * HOUR);
  FR.deliver(g, 'Rin', ship, 'alloy', 1000, t + 144 * HOUR);
  FR.deliver(g, 'Rin', ship, 'exotic', 50, t + 144 * HOUR);
  FR.tick(g, t + 240 * HOUR);
  assert.strictEqual(s.state, 'world', 'about 10 days from orbit to a living world');
  assert.strictEqual(g.frontier.clusters['compact-1'].colony.pop, T.get().frontier.colony.startPop);
  assert.ok(s.contributors.Rin > 0);
});

// A finished world.
function world(g) {
  const L = inOrbit(g);
  const { ship, s, t } = L;
  let at = t;
  for (const stage of FR.STAGES) {
    if (!s.engines.includes(stage)) {
      FR.buyEngine(g, 'Akane', ship, stage);
      FR.deliver(g, 'Akane', ship, `engine_${stage}`, 1, at);
    }
    for (const item of Object.keys(FR.needs(g, s))) FR.deliver(g, 'Akane', ship, item, 100_000, at);
    at += T.get().frontier.stageHours[stage] * HOUR;
    FR.tick(g, at);
  }
  assert.strictEqual(s.state, 'world');
  return { ...L, t: at, col: L.c.colony };
}

test('the colony grows in tiers while its needs are covered, unlocking buildings as it goes', () => {
  const g = setup();
  const { cluster, col, t } = world(g);
  assert.match(FR.buildIn(g, 'Akane', cluster, 'foundry').reason, /tier 1/);
  assert.match(FR.buildIn(g, 'Rin', cluster, 'habitat').reason, /your own colony/);
  for (const b of ['habitat', 'habitat', 'precinct', 'clinic', 'mine']) assert.ok(FR.buildIn(g, 'Akane', cluster, b).ok, b);
  FR.tick(g, t + 100 * HOUR);
  assert.ok(col.pop >= 2000, `grew to ${col.pop}`);
  assert.strictEqual(col.tier, 1);
  assert.ok(col.stock.copper > 0, 'the mine works');
  assert.ok(FR.buildIn(g, 'Akane', cluster, 'foundry').ok);
});

test('neglected, the population shrinks; at zero a week to resettle, or auction and ruins', () => {
  const g = setup();
  const { cluster, c, col, t } = world(g);
  col.pop = 5000; // far past what one precinct and one clinic cover
  FR.tick(g, t + 10 * HOUR);
  assert.ok(col.pop < 5000, 'losing control');
  FR.tick(g, t + 1000 * HOUR);
  assert.strictEqual(col.pop, 0);
  assert.ok(col.collapseAt);
  // Resettled in time, it carries on.
  assert.ok(FR.resettle(g, 'Akane', cluster, t + 1001 * HOUR).ok);
  assert.strictEqual(col.pop, T.get().frontier.colony.resettlePop);
  // Collapsed again and left: the cluster goes to auction, the buildings to ruins.
  col.pop = 5000;
  col.buildings = { habitat: 2 };
  FR.tick(g, t + 1002 * HOUR);
  FR.tick(g, t + 3000 * HOUR);
  assert.ok(c.colony.collapseAt);
  FR.tick(g, t + 3000 * HOUR + 168 * HOUR);
  assert.strictEqual(c.owner, null);
  assert.strictEqual(c.colony, null);
  assert.deepStrictEqual(c.ruins.map((r) => r.buildings), [{ habitat: 2 }]);
  assert.match(FR.buyAtAuction(g, 'Kite', cluster, t).reason, /own pilots/);
  assert.ok(FR.buyAtAuction(g, 'Rin', cluster, t).ok);
  assert.strictEqual(c.owner, 'Rin');
});

test('exports: bought at the source, sold to the galactic market, hauled to other stations for a boost', () => {
  const g = setup();
  const { cluster, col } = world(g);
  col.stock.alloy = 100;
  const akane = g.pilots.Akane.credits;
  assert.strictEqual(FR.buy(g, 'Kite', cluster, 'alloy', 10).cost, 400, 'anyone who flies there can buy');
  assert.strictEqual(g.pilots.Akane.credits, akane + 400);
  assert.strictEqual(g.pilots.Kite.cargo.alloy, 10);
  const plain = FR.exportGoods(g, 'Akane', cluster, 'alloy', 10).paid;
  assert.strictEqual(plain, 240);
  // A Hauler mission to Cinder's orbital station.
  assert.match(FR.takeHaul(g, 'Rin', cluster, 'alloy', 10, 'bastion', t0).reason, /contested world/);
  const m = FR.takeHaul(g, 'Rin', cluster, 'alloy', 20, 'cinder', t0).mission;
  assert.match(FR.deliverHaul(g, 'Rin', m, 'vesper').reason, /Cinder/);
  const rin = g.pilots.Rin.credits;
  assert.strictEqual(FR.deliverHaul(g, 'Rin', m, 'cinder').paid, 400);
  assert.strictEqual(g.pilots.Rin.credits, rin + 400);
  assert.strictEqual(col.boost, T.get().frontier.exports.boostPerMission);
  assert.ok(FR.exportGoods(g, 'Akane', cluster, 'alloy', 10).paid > plain, 'the boost raises export profits');
});
