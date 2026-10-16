// Every Builder owns a home planet with its own economy.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');

test('the first Builder takes Aster and its starting economy; the next founds a new planet', () => {
  const g = G.newGalaxy();
  g.stock.metal = 77;
  const a = G.claimBase(g, 'Akane');
  assert.strictEqual(a.id, 'aster');
  assert.strictEqual(g.bases.Akane.stock.metal, 77);
  const b = G.claimBase(g, 'Rin');
  assert.notStrictEqual(b.id, 'aster');
  assert.strictEqual(b.owner, 'Rin');
  assert.strictEqual(g.bases.Rin.stock.metal, 60);
  assert.strictEqual(G.claimBase(g, 'Rin'), b, 'claiming again returns the same planet');
  assert.strictEqual(g.system.planets.length, 2);
});

test('each base pays for, builds and earns on its own planet only', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const rin = G.claimBase(g, 'Rin');
  assert.ok(G.owns(g, 'Rin', rin.id));
  assert.ok(!G.owns(g, 'Rin', 'aster'));

  assert.ok(G.build(g, rin.id, 0, 'mine').ok);
  assert.strictEqual(g.bases.Rin.stock.metal, 50);
  assert.strictEqual(g.bases.Akane.stock.metal, 60);
  G.tick(g);
  assert.strictEqual(g.bases.Rin.stock.metal, 51);
  assert.strictEqual(g.bases.Akane.stock.metal, 60);

  // A Spaceport on Aster doesn't let Rin build a Foundry or post jobs.
  assert.ok(G.build(g, 'aster', 0, 'spaceport').ok);
  assert.match(G.build(g, rin.id, 1, 'foundry').reason, /Spaceport first/);
  assert.match(G.postJob(g, 'ice', 10, 100, rin.id).reason, /Spaceport first/);
});

test('deliveries land in the stock of the base that posted the job', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const rin = G.claimBase(g, 'Rin');
  g.bases.Rin.stock.metal = 100;
  G.build(g, rin.id, 0, 'spaceport');
  const { job } = G.postJob(g, 'ice', 10, 100, rin.id);
  assert.strictEqual(g.bases.Rin.credits, 400);
  for (let i = 0; i < 2; i++) G.collect(g, 'Pilot A', 'ice', 5);
  assert.ok(G.deliver(g, 'Pilot A', job.id).ok);
  assert.strictEqual(g.bases.Rin.stock.ice, 10);
  assert.strictEqual(g.bases.Akane.stock.ice, 0);
  assert.ok(g.bases.Rin.unlocked.includes('hydroponics'));
  assert.ok(!g.bases.Akane.unlocked.includes('hydroponics'));
});

test('facilities go on satellite sites with a free grid of defences', () => {
  const S = require('../sites');
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  e.stock.metal = 500;
  e.stock.alloy = 20;
  e.stock.ice = 20;
  assert.match(G.build(g, 'aster', 0, 'refinery').reason, /satellite site/);
  const { site } = G.foundSite(g, 'Akane', 'refinery');
  assert.ok(site.obstacles.length > 0, 'a new site comes with obstacles');
  site.obstacles = []; // a clear site, so defences go where the test puts them
  assert.strictEqual(site.parent, 'aster');
  assert.strictEqual(site.name, 'Aster Mining Refinery');
  assert.strictEqual(e.stock.metal, 460);
  assert.ok(G.facility(g, site.id, 0));

  assert.ok(G.placePiece(g, site.id, 'turret', 0, 0).ok);
  assert.strictEqual(e.stock.alloy, 15);
  assert.match(G.placePiece(g, site.id, 'wall', 1, 1).reason, /already there/);
  assert.match(G.placePiece(g, site.id, 'wall', 5, 5).reason, /facility is there/);
  assert.match(G.placePiece(g, site.id, 'turret', 11, 0).reason, /edge/);
  assert.ok(G.placePiece(g, site.id, 'wall', 2, 0).ok);
  assert.deepStrictEqual(S.defence(site), { attack: 4, hull: 30 });

  const metal = e.stock.metal;
  assert.ok(G.removePiece(g, site.id, site.pieces[0].id).ok);
  assert.strictEqual(e.stock.metal, metal + 10, 'half the cost back');

  assert.ok(G.foundSite(g, 'Akane', 'lab').ok);
  assert.ok(G.foundSite(g, 'Akane', 'spire').ok);
  assert.match(G.foundSite(g, 'Akane', 'refinery').reason, /already have 3/);
  // Someone else can't touch Akane's site.
  G.claimBase(g, 'Rin');
  assert.ok(!G.owns(g, 'Rin', site.id));
});

test('obstacles block defences until cleared for credits, and some leave salvage', () => {
  const S = require('../sites');
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const e = g.bases.Akane;
  e.stock.metal = 500;
  const { site } = G.foundSite(g, 'Akane', 'refinery');
  const again = { id: site.id, pieces: [], nextPiece: 1 };
  S.scatter(again);
  assert.deepStrictEqual(again.obstacles, site.obstacles, 'the same site id always gets the same obstacles');
  const boulder = site.obstacles.find((o) => o.type === 'boulder');
  assert.ok(boulder);
  assert.match(G.placePiece(g, site.id, 'wall', boulder.x, boulder.y).reason, /already there/);
  e.credits = 100;
  assert.match(G.clearObstacle(g, site.id, boulder.id).reason, /costs 120 credits/);
  e.credits = 500;
  const metal = e.stock.metal;
  assert.ok(G.clearObstacle(g, site.id, boulder.id).ok);
  assert.strictEqual(e.credits, 380);
  assert.strictEqual(e.stock.metal, metal + 10, 'salvage');
  assert.ok(G.placePiece(g, site.id, 'wall', boulder.x, boulder.y).ok);
  // Sites from older saves get obstacles when the server loads them.
  delete site.obstacles;
  G.recoverRaids(g);
  assert.ok(site.obstacles.length > 0);
});
