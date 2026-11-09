// War goods at the front: stockpiles per front that reset with each campaign, war chests drawn per
// pilot and settled at half, and what the goods do in Supremacy and Sector Defense.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const DF = require('../defense');
const FC = require('../facility');
const G = require('../galaxy');
const S = require('../supremacy');
const T = require('../tunables.ts');
const W = require('../war');
const WC = require('../stockpile.ts');

// A demo-war galaxy (every faction in every campaign), the player factions equally strong.
function setup() {
  W.setDemo(true);
  const g = G.newGalaxy();
  const t = C.DEMO_CYCLE_MS * 100;
  C.tick(g, t);
  g.director.strength = { compact: 0.3, ashen: 0.3, luminar: 0.3 };
  return { g, t };
}
test.after(() => W.setDemo(false));

const fill = (g, faction, goods, from = 'Akane', planet = 'cinder') => {
  for (const [k, n] of Object.entries(goods)) assert.ok(WC.add(g, planet, faction, k, n, from).ok, k);
};

test('only finished war goods, only to a front with a campaign; each lot keeps its Builder', () => {
  const { g } = setup();
  assert.match(WC.add(g, 'cinder', 'ashen', 'alloy', 5, 'Akane').reason, /only finished war goods/);
  assert.match(WC.add(g, 'cinder', 'ashen', 'metal', 5, 'Akane').reason, /only finished war goods/);
  assert.match(WC.add(g, 'bastion', 'ashen', 'fuel', 5, 'Akane').reason, /no campaign/);
  fill(g, 'ashen', { missile: 2 }, 'Akane');
  fill(g, 'ashen', { missile: 1 }, 'Rin');
  assert.strictEqual(WC.totals(g, 'cinder', 'ashen').missile, 3);
  assert.deepStrictEqual(WC.view(g).cinder.ashen.missile, 3);
  const chest = WC.newChest(g, 'cinder', 'ashen');
  assert.deepStrictEqual(WC.draw(g, chest).missile, 2, 'warChest.perPilot.missile a pilot');
  assert.deepStrictEqual(WC.use(chest, 'missile', 1), ['Akane'], 'oldest first, named for whoever sent it');
});

test('a chest takes per pilot, scaled by the underdog multiplier; one warhead a match; Sector Defense half', () => {
  const { g } = setup();
  fill(g, 'ashen', { fuel: 100, warhead: 3, lander_frame: 5 });
  const chest = WC.newChest(g, 'cinder', 'ashen');
  assert.deepStrictEqual(WC.draw(g, chest), { lander_frame: 1, fuel: 20, warhead: 1 });
  assert.deepStrictEqual(WC.draw(g, chest), { lander_frame: 1, fuel: 20 }, 'the second pilot brings no second warhead');
  g.director.strength = { compact: 0.6, ashen: 0.1, luminar: 0.3 }; // the Collective far behind: more per pilot
  const more = WC.draw(g, chest);
  assert.ok(more.fuel > 20, `the underdog brings more (${more.fuel})`);
  const half = WC.newChest(g, 'cinder', 'ashen');
  g.director.strength = { compact: 0.3, ashen: 0.3, luminar: 0.3 };
  assert.strictEqual(WC.draw(g, half, T.get().warChest.defenseShare).fuel, 10);
  // A mode takes only the goods it uses: Sector Defense has no use for fuel.
  assert.deepStrictEqual(WC.draw(g, WC.newChest(g, 'cinder', 'ashen'), 0.5, DF.CHEST_GOODS), { lander_frame: 1, warhead: 1 });
});

test('what a match did not use comes back at half, rounded up; a new campaign starts every stockpile from nothing', () => {
  const { g, t } = setup();
  fill(g, 'ashen', { fuel: 20, missile: 2, sensor: 1 });
  const chest = WC.newChest(g, 'cinder', 'ashen');
  WC.draw(g, chest);
  WC.use(chest, 'missile', 1);
  assert.deepStrictEqual(WC.settle(g, chest), { fuel: 10, missile: 1, sensor: 1 });
  assert.deepStrictEqual([WC.totals(g, 'cinder', 'ashen').fuel, WC.totals(g, 'cinder', 'ashen').missile, WC.totals(g, 'cinder', 'ashen').sensor], [10, 1, 1]);
  // The weekly campaign rolls over (the demo's every half hour): the pile empties, and a chest
  // from the last campaign returns nothing to the new one.
  const old = WC.newChest(g, 'cinder', 'ashen');
  WC.draw(g, old);
  C.tick(g, t + C.DEMO_CYCLE_MS + 1);
  assert.strictEqual(WC.totals(g, 'cinder', 'ashen').fuel, 0, 'every campaign starts from nothing');
  WC.settle(g, old);
  assert.strictEqual(WC.totals(g, 'cinder', 'ashen').fuel, 0);
});

// --- Supremacy -----------------------------------------------------------------------------------

function supremacy(g, goods) {
  fill(g, 'ashen', goods);
  const f = S.newSupremacy({ planet: 'cinder', planetName: 'Cinder', attacker: 'ashen', defender: 'compact', holder: 'compact', seed: 5, map: 'highlands' });
  S.addPilot(f, 'Kite', 'a');
  f.chests.a = WC.newChest(g, 'cinder', 'ashen');
  S.chestJoined(f, 'a', 'Kite', WC.draw(g, f.chests.a, 1, S.CHEST_GOODS));
  return f;
}
const feed = (f) => f.feed.map((x) => x.text).join(' | ');

test('Supremacy: drone chassis add fodder bots, shell crates are Orbital Barrages, sensors sweep each ground phase', () => {
  const { g } = setup();
  const f = supremacy(g, { drone_frame: 1, shells: 2, sensor: 2 });
  assert.strictEqual([...f.bodies.values()].filter((b) => b.fodder && b.side === 'a').length, S.FODDER + 4);
  assert.deepStrictEqual(f.bodies.get('Kite').earned, ['barrage', 'barrage']);
  assert.match(feed(f), /4 more Skitters fight for the Ashen Collective, built on drone chassis from Akane/);
  S.step(f, 0.2);
  assert.ok(f.active.some((a) => a.kind === 'sensor' && a.side === 'a'), 'a sweep at the start of the ground');
  assert.match(feed(f), /swept the field with a sensor module from Akane/);
  assert.strictEqual(WC.has(f.chests.a, 'sensor'), 0, 'one sensor a pilot');
});

test('Supremacy: missiles and weapon systems drop power weapons at the side\'s drop ship; a lander lands a forward drop ship', () => {
  const { g } = setup();
  const f = supremacy(g, { missile: 2, lander_frame: 1 });
  f.nextSupply = 0;
  S.step(f, 0.2);
  const mine = [...f.pickups.values()].filter((u) => Math.hypot(u.x - f.map.drop.a[0], u.z - f.map.drop.a[1]) < 10);
  assert.deepStrictEqual(mine.map((u) => u.weapon), ['rockets']);
  assert.match(feed(f), /supply drop: a .* from Akane/);
  S.step(f, 46);
  assert.ok(f.forward.a, 'the forward drop ship landed');
  const spots = f.spawnSpots(f, f.bodies.get('Kite'));
  assert.ok(spots.some(([x, z]) => Math.hypot(x - f.forward.a[0], z - f.forward.a[1]) < 6), 'pilots can come back there');
});

test('Supremacy: fuel lengthens the boarding window, a hauler adds a shuttle, a warhead breaches a blast door', () => {
  const { g } = setup();
  const f = supremacy(g, { fuel: 20, hauler: 1, warhead: 1 });
  const shuttles = f.points.filter((p) => p.owner === 'a').length + 1;
  S.startBoarding(f, 'a');
  assert.strictEqual(f.boardS, S.BOARD_S + 10, '20 fuel cells: 10 seconds more');
  assert.strictEqual(f.shuttles.length, shuttles + 1);
  f.t += f.boardS;
  S.step(f, 0.2);
  assert.strictEqual(f.phase, 'ship');
  assert.strictEqual(f.breakables.filter((br) => br.kind === 'door' && br.hp <= 0).length, 1);
  assert.match(feed(f), /A breaching charge from Akane breached a blast door/);
});

// --- Sector Defense --------------------------------------------------------------------------------

function defense(g, goods) {
  fill(g, 'ashen', goods);
  const d = DF.newDefense({ planet: 'cinder', planetName: 'Cinder', faction: 'ashen', enemy: 'compact', seed: 7, map: 'outpost' });
  DF.addPilot(d, 'A');
  d.chests.a = WC.newChest(g, 'cinder', 'ashen');
  WC.draw(g, d.chests.a, 1, DF.CHEST_GOODS);
  DF.chestJoined(d);
  return d;
}

test('Sector Defense: landers are lives, shell crates shell each wave, a drone is a sentry for the set', () => {
  const { g } = setup();
  const d = defense(g, { lander_frame: 1, shells: 2, drone_frame: 1 });
  assert.strictEqual(d.lives, DF.LIVES + 1);
  DF.step(d, DF.FIRST_BREAK_S + 0.5);
  assert.strictEqual(d.wave, 1);
  assert.ok([...d.enemies.values()].every((e) => e.hp <= e.maxHp - 80 || e.hp <= 0), 'the wave was shelled as it landed');
  assert.ok(d.sentry, 'a sentry drone over the middle');
  const kills = d.kills;
  DF.step(d, 20);
  assert.ok(d.kills > kills || d.shots.some((s) => s[0] === 'sentry'), 'the sentry fights');
});

test('Sector Defense: missiles make sure of a rocket launcher, slugs add ammo, a sensor scouts the next wave', () => {
  const { g } = setup();
  const d = defense(g, { missile: 1, slugs: 3, sensor: 1 });
  d.phase = 'wave';
  d.wave = 1;
  d.enemies.clear();
  DF.step(d, 0.2);
  const kinds = [...d.pickups.values()].map((u) => u.kind);
  assert.ok(kinds.includes('rocket'));
  assert.ok(kinds.filter((k) => k === 'ammo').length >= 2);
  const fr = DF.frame(d);
  assert.ok(fr.nextWave && fr.nextWave.length, 'the next wave is shown');
  assert.match(fr.feed.map((x) => x.text).join(' | '), /scouts set 1's waves/);
});
