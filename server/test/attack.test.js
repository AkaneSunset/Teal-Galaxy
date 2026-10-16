// Fleets attacking other Builders' satellite sites.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const N = require('../navy');

function twoBuilders() {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  G.claimBase(g, 'Rin');
  g.bases.Rin.stock.metal = 500;
  g.bases.Rin.stock.alloy = 50;
  const { site } = G.foundSite(g, 'Rin', 'refinery');
  site.obstacles = []; // a clear site, so defences go where the test puts them
  site.buildings[0].vault = { alloy: 10, isotope: 3 };
  return { g, site };
}

test('battles are decided by attack and hull, lightest ships sink first', () => {
  const easy = N.battle({ frigate: 2 }, { attack: 3, hull: 40 });
  assert.ok(easy.won);
  assert.deepStrictEqual(easy.lost, {});
  const hard = N.battle({ corvette: 3 }, { attack: 20, hull: 500 });
  assert.ok(!hard.won);
  assert.deepStrictEqual(hard.survivors, {});
  assert.deepStrictEqual(hard.lost, { corvette: 3 });
  const mixed = N.battle({ corvette: 2, destroyer: 1 }, { attack: 8, hull: 120 });
  assert.ok(mixed.won);
  assert.ok(mixed.lost.corvette >= 1 && !mixed.lost.destroyer, JSON.stringify(mixed));
});

test('a winning fleet loots the vault, shields the site, and brings the loot home', () => {
  const { g, site } = twoBuilders();
  g.bases.Akane.navy.frigate = 3;
  assert.match(G.launchAttack(g, 'Rin', site.id, 0).reason, /your own site/);
  const r = G.launchAttack(g, 'Akane', site.id, 0);
  assert.ok(r.ok, r.reason);
  assert.strictEqual(g.bases.Akane.navy.frigate, 0, 'ships leave the hangar');
  assert.strictEqual(r.attack.arriveAt, 60_000, 'frigates fly at speed 2');

  G.tick(g, 59_000);
  assert.strictEqual(g.attackLog.length, 0, 'still flying');
  site.buildings[0].vault = { alloy: 10, isotope: 3 }; // the facility keeps producing as ticks pass
  G.tick(g, 60_000);
  assert.deepStrictEqual(g.attackLog[0].loot, { alloy: 4, isotope: 1 });
  assert.ok(site.shieldUntil > 60_000);
  assert.strictEqual(g.attackLog[0].won, true);
  assert.match(G.launchAttack(g, 'Akane', site.id, 61_000).reason, /no ships|shielded/);

  G.tick(g, 120_000);
  assert.strictEqual(g.bases.Akane.navy.frigate, 3);
  assert.strictEqual(g.bases.Akane.stock.alloy, 4);
  assert.strictEqual(g.bases.Akane.stock.isotope, 1);
  assert.strictEqual(g.attacks.length, 0);
});

test('placed defences can drive a fleet off', () => {
  const { g, site } = twoBuilders();
  for (const [x, y] of [[0, 0], [2, 0], [0, 2], [10, 0], [10, 2]]) assert.ok(G.placePiece(g, site.id, 'turret', x, y).ok);
  g.bases.Akane.navy.corvette = 3;
  G.launchAttack(g, 'Akane', site.id, 0);
  G.tick(g, 40_000);
  assert.strictEqual(g.attackLog[0].won, false);
  assert.deepStrictEqual(g.attackLog[0].loot, {});
  assert.ok(!site.shieldUntil);
  G.tick(g, 80_000);
  assert.strictEqual(g.bases.Akane.navy.corvette, 0, 'all three were sunk');
});

test('you need ships, and only Builders who own a home can attack', () => {
  const { g, site } = twoBuilders();
  assert.match(G.launchAttack(g, 'Akane', site.id, 0).reason, /no ships/);
  assert.match(G.launchAttack(g, 'Nobody', site.id, 0).reason, /no home/);
});
