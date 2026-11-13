// Homeworld cities: admins lay them out piece by piece on the capital worlds.

const test = require('node:test');
const assert = require('node:assert');
const CI = require('../cities.ts');
const G = require('../galaxy');
const FR = require('../frontier.ts');

const ADMIN = { name: 'Admin', admin: true };

test('admins build on capital worlds only, inside the city, on free cells', () => {
  const g = G.newGalaxy();
  assert.strictEqual(CI.place(g, ADMIN, 'cinder', 'road', 0, 0, 0, 1).ok, false);
  const hall = CI.place(g, ADMIN, 'bastion', 'hall', -3, -3, 0, 1);
  assert.ok(hall.ok);
  assert.match(CI.place(g, ADMIN, 'bastion', 'road', 0, 0, 0, 1).reason, /Government Hall/);
  assert.ok(CI.place(g, ADMIN, 'bastion', 'road', 4, 0, 0, 1).ok);
  assert.strictEqual(CI.place(g, ADMIN, 'bastion', 'road', CI.HALF, 0, 0, 1).ok, false);
  assert.strictEqual(CI.place(g, ADMIN, 'bastion', 'nope', 10, 10, 0, 1).ok, false);
  assert.strictEqual(CI.place(g, ADMIN, 'bastion', 'road', 1.5, 10, 0, 1).ok, false);
  assert.strictEqual(g.cities.bastion.pieces.length, 2);
});

test('turning swaps a piece footprint, and moving keeps its id', () => {
  const g = G.newGalaxy();
  const wall = CI.place(g, ADMIN, 'shade', 'wall', 0, 0, 0, 1).piece; // 2 x 1
  assert.ok(CI.place(g, ADMIN, 'shade', 'turret', 0, 1, 0, 1).ok);
  assert.strictEqual(CI.move(g, ADMIN, 'shade', wall, 0, 0, 1, 2).ok, false); // turned, it would cover (0, 1)
  assert.ok(CI.move(g, ADMIN, 'shade', wall, 5, 5, 1, 2).ok);
  assert.deepStrictEqual(CI.size('wall', 1), [1, 2]);
  const p = g.cities.shade.pieces.find((q) => q.id === wall);
  assert.deepStrictEqual([p.x, p.z, p.rot], [5, 5, 1]);
  assert.ok(CI.remove(g, ADMIN, 'shade', wall, 3).ok);
  assert.strictEqual(CI.remove(g, ADMIN, 'shade', wall, 3).ok, false);
});

test('a city can be copied to another homeworld and cleared', () => {
  const g = G.newGalaxy();
  CI.place(g, ADMIN, 'radiance', 'spaceport', 0, 0, 0, 1);
  assert.ok(CI.copy(g, ADMIN, 'radiance', 'glimmer', 2).ok);
  assert.strictEqual(g.cities.glimmer.pieces.length, 1);
  assert.ok(CI.clear(g, ADMIN, 'radiance', 3).ok);
  assert.strictEqual(g.cities.radiance.pieces.length, 0);
  assert.strictEqual(g.cities.glimmer.pieces.length, 1);
});

test('players can not build on the homeworlds', () => {
  const g = G.newGalaxy();
  assert.match(CI.place(g, { name: 'Akane', admin: false }, 'bastion', 'road', 0, 0, 0, 1).reason, /admins/);
});

test('a Founder builds their colony city with the colony buildings', () => {
  const g = G.newGalaxy();
  for (const [name, f] of [['Akane', 'compact'], ['Kite', 'ashen']]) {
    G.chooseFaction(g, 'explorer', name, f);
    g.pilots[name].credits = 5_000_000;
  }
  const cluster = FR.leaseCluster(g, 'Akane', 1).cluster;
  const c = g.frontier.clusters[cluster];
  const planet = c.systems[0].planets[0].id;
  assert.match(CI.place(g, { name: 'Akane', admin: false }, planet, 'road', 0, 0, 0, 1).reason, /terraformed/);
  c.colony = { planet, pop: 500, tier: 0, buildings: { habitat: 1, precinct: 1, clinic: 1, power: 1 }, stock: {}, carry: {}, boost: 0, collapseAt: null, updatedAt: 1 };
  const akane = { name: 'Akane', admin: false };
  assert.match(CI.place(g, { name: 'Kite', admin: false }, planet, 'road', 0, 0, 0, 1).reason, /Founder/);
  // The colony's first habitat is in store: placing it is free; the second is built and paid for.
  const before = g.pilots.Akane.credits;
  assert.deepStrictEqual(CI.place(g, akane, planet, 'habitat', 0, 0, 0, 1).built, false);
  assert.strictEqual(g.pilots.Akane.credits, before);
  assert.deepStrictEqual(CI.place(g, akane, planet, 'habitat', 10, 0, 0, 1).built, true);
  assert.strictEqual(c.colony.buildings.habitat, 2);
  assert.ok(g.pilots.Akane.credits < before);
  // Locked by tier, homeworld-only pieces refused, free scenery fine.
  assert.match(CI.place(g, akane, planet, 'reactor', 20, 0, 0, 1).reason, /tier/);
  assert.match(CI.place(g, akane, planet, 'hall', 20, 0, 0, 1).reason, /homeworlds/);
  assert.ok(CI.place(g, akane, planet, 'road', 30, 0, 0, 1).ok);
  // Taken up, a habitat goes back in store: placing it again is free.
  const id = g.cities[planet].pieces[0].id;
  assert.ok(CI.remove(g, akane, planet, id, 2).ok);
  assert.strictEqual(CI.place(g, akane, planet, 'habitat', -20, -20, 0, 2).built, false);
  assert.strictEqual(c.colony.buildings.habitat, 2);
});

test('states carry each city stamp, and a city is fetched whole', () => {
  const g = G.newGalaxy();
  assert.deepStrictEqual(CI.view(g, 'anvil'), { planet: 'anvil', pieces: [], updated: 0 });
  assert.strictEqual(g.cities?.anvil, undefined); // looking builds nothing
  CI.place(g, ADMIN, 'anvil', 'road', 0, 0, 0, 7);
  assert.deepStrictEqual(CI.stamps(g), { anvil: 7 });
  assert.strictEqual(CI.view(g, 'anvil').pieces.length, 1);
});

test('a full city of roads lays out within the server budget', () => {
  const g = G.newGalaxy();
  const t0 = process.hrtime.bigint();
  let n = 0;
  for (let x = -CI.HALF; x < CI.HALF && n < 4000; x += 2)
    for (let z = -CI.HALF; z < CI.HALF && n < 4000; z++) if (CI.place(g, ADMIN, 'bastion', 'road', x, z, 0, 1).ok) n++;
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  assert.strictEqual(n, 4000);
  assert.strictEqual(CI.place(g, ADMIN, 'bastion', 'road', 1, 1, 0, 1).ok, false); // full
  assert.ok(ms < 1500, `4,000 placements took ${ms.toFixed(0)} ms`);
});

test('housing zones are lots anyone may lay, on homeworlds and colonies', () => {
  const g = G.newGalaxy();
  assert.deepStrictEqual(CI.size('zone_low', 0), [2, 2]);
  assert.deepStrictEqual(CI.size('zone_high', 1), [3, 3]);
  assert.strictEqual(CI.PIECES.zone_low.where, 'any');
  const a = CI.place(g, ADMIN, 'bastion', 'zone_low', 0, 0, 0, 1);
  const b = CI.place(g, ADMIN, 'bastion', 'zone_low', 2, 0, 0, 1); // the next lot along the street
  assert.ok(a.ok && b.ok && a.piece !== b.piece);
  assert.match(CI.place(g, ADMIN, 'bastion', 'zone_high', 1, 1, 0, 1).reason, /Low-density housing is in the way/);
  assert.ok(CI.place(g, ADMIN, 'bastion', 'zone_high', 4, 0, 0, 1).ok);
});

// A street along z = 0 from x = `from` to x = `to`, for the tier tests.
function street(g, from, to) {
  for (let x = from; x <= to; x++) assert.ok(CI.place(g, ADMIN, 'bastion', 'road', x, 0, 0, 1).ok);
}
const HOUR = FR.hourMs();
const lotOf = (g, id) => CI.view(g, 'bastion').pieces.find((p) => p.id === id);

test('a lot needs a road, then power, safety, care and leisure to carry it up the tiers', () => {
  const g = G.newGalaxy();
  const lot = CI.place(g, ADMIN, 'bastion', 'zone_low', -58, 1, 0, 1).piece;
  assert.deepStrictEqual(lotOf(g, lot).needs, [0, 0, 0, 0, 0]);
  assert.strictEqual(lotOf(g, lot).target, 1);
  street(g, -58, 10);
  assert.ok(CI.place(g, ADMIN, 'bastion', 'power', -54, 1, 0, 1).ok);
  assert.deepStrictEqual(lotOf(g, lot).needs, [1, 1, 0, 0, 0]);
  assert.strictEqual(lotOf(g, lot).target, 2);
  assert.ok(CI.place(g, ADMIN, 'bastion', 'precinct', -50, 1, 0, 1).ok);
  const far = CI.place(g, ADMIN, 'bastion', 'clinic', 2, 1, 0, 1).piece; // 59 cells off by road: out of reach
  assert.ok(far);
  assert.strictEqual(lotOf(g, lot).target, 2);
  assert.ok(CI.move(g, ADMIN, 'bastion', far, -18, 1, 0, 2).ok); // 39 cells: in reach, but weak
  assert.ok(lotOf(g, lot).needs[3] > 0 && lotOf(g, lot).needs[3] < 0.5);
  assert.strictEqual(lotOf(g, lot).target, 3);
  assert.ok(CI.move(g, ADMIN, 'bastion', far, -46, 1, 0, 3).ok);
  assert.strictEqual(lotOf(g, lot).target, 3); // strong services, but nothing to do
  assert.ok(CI.place(g, ADMIN, 'bastion', 'park', -58, 3, 0, 4).ok); // next door
  assert.deepStrictEqual(lotOf(g, lot).needs, [1, 1, 1, 1, 1]);
  assert.strictEqual(lotOf(g, lot).target, 5);
});

test('services reach along the roads, not through the air', () => {
  const g = G.newGalaxy();
  const lot = CI.place(g, ADMIN, 'bastion', 'zone_high', 0, 1, 0, 1).piece;
  CI.place(g, ADMIN, 'bastion', 'road', 0, 0, 0, 1);
  CI.place(g, ADMIN, 'bastion', 'power', 3, 1, 0, 1); // right beside the lot, on no road
  assert.strictEqual(lotOf(g, lot).needs[1], 0);
  for (let x = 1; x <= 4; x++) CI.place(g, ADMIN, 'bastion', 'road', x, 0, 0, 1);
  assert.strictEqual(lotOf(g, lot).needs[1], 1);
});

test('lots climb a tier at a time while their needs are met, and slip back when they are not', () => {
  const g = G.newGalaxy();
  street(g, 0, 12);
  const lot = CI.place(g, ADMIN, 'bastion', 'zone_low', 0, 1, 0, 1).piece;
  const plant = CI.place(g, ADMIN, 'bastion', 'power', 3, 1, 0, 1).piece;
  CI.place(g, ADMIN, 'bastion', 'precinct', 8, 1, 0, 1);
  CI.place(g, ADMIN, 'bastion', 'clinic', 0, -3, 0, 1);
  let now = 1000;
  assert.strictEqual(CI.tick(g, now), false); // the first tick only starts the clock
  now += (CI.GROW_HOURS / 2) * HOUR;
  assert.strictEqual(CI.tick(g, now), false);
  assert.strictEqual(lotOf(g, lot).tier, 1);
  assert.strictEqual(lotOf(g, lot).grow, 0.5);
  now += (CI.GROW_HOURS / 2) * HOUR;
  assert.strictEqual(CI.tick(g, now), true);
  assert.strictEqual(lotOf(g, lot).tier, 2);
  assert.strictEqual(g.cities.bastion.updated, now); // the apps fetch the city again
  now += CI.GROW_HOURS * HOUR;
  CI.tick(g, now);
  assert.strictEqual(lotOf(g, lot).tier, 3);
  now += CI.GROW_HOURS * HOUR;
  CI.tick(g, now);
  assert.strictEqual(lotOf(g, lot).tier, 3); // no park: tier 3 is as far as these needs carry it
  CI.remove(g, ADMIN, 'bastion', plant, now); // the power goes
  assert.strictEqual(lotOf(g, lot).target, 1);
  for (let i = 0; i < 4; i++) {
    now += (CI.DECLINE_HOURS / 2) * HOUR;
    CI.tick(g, now);
  }
  assert.strictEqual(lotOf(g, lot).tier, 1);
});
