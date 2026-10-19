// Picking a faction, once per character, and what happens to a Builder's sites from before the war.

const test = require('node:test');
const assert = require('node:assert');
const F = require('../factions');
const G = require('../galaxy');
const W = require('../war');

// A satellite site as saves from before the war have them: off the home planet, with no sector
// or faction.
function oldSite(g, owner, type, n) {
  const home = g.system.planets.find((p) => p.owner === owner && p.kind !== 'satellite');
  const site = {
    id: `${home.id}-site-${n}`, name: `${home.name} ${type}`, kind: 'satellite', owner, parent: home.id, orbit: n - 1,
    slots: 1, grid: 12, pieces: [{ id: 1, type: 'wall', x: 0, y: 0 }], obstacles: [], nextPiece: 2,
    buildings: [{ slot: 0, type, level: 2, security: 1, vault: { alloy: 3 }, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} }],
  };
  g.system.planets.push(site);
  return site;
}

test('the four factions and the War Merit ranks', () => {
  assert.deepStrictEqual(Object.keys(F.FACTIONS), ['compact', 'ashen', 'luminar', 'coma']);
  assert.deepStrictEqual(Object.values(F.FACTIONS).map((f) => f.mirrors), ['UEF', 'Cybran', 'Aeon', 'Seraphim']);
  assert.deepStrictEqual(Object.values(F.FACTIONS).map((f) => f.capital), ['fortitude', 'umbra', 'aurelia', 'comae']);
  for (const f of Object.values(F.FACTIONS)) assert.ok(f.name && /^#[0-9a-f]{6}$/.test(f.color) && f.style && f.bonus);
  assert.strictEqual(F.rank(0).name, 'Recruit');
  assert.strictEqual(F.rank(499).name, 'Recruit');
  assert.strictEqual(F.rank(500).name, 'Supplier');
  assert.strictEqual(F.rank(2000).bonus, 0.04);
  assert.strictEqual(F.rank(1e9).name, 'War Industrialist');
});

test('every character picks a faction once: a Builder and a pilot of the same name pick their own', () => {
  const g = G.newGalaxy();
  assert.match(G.chooseFaction(g, 'builder', 'Akane', 'compact').reason, /claim a base first/);
  G.claimBase(g, 'Akane');
  assert.match(G.chooseFaction(g, 'builder', 'Akane', 'pirates').reason, /no such faction/);
  assert.ok(G.chooseFaction(g, 'builder', 'Akane', 'compact').ok);
  assert.strictEqual(g.bases.Akane.faction, 'compact');
  assert.strictEqual(G.chooseFaction(g, 'builder', 'Akane', 'ashen').reason, 'your faction is already set');
  assert.ok(G.chooseFaction(g, 'explorer', 'Akane', 'ashen').ok, 'her pilot is someone else');
  assert.strictEqual(g.pilots.Akane.faction, 'ashen');
  assert.deepStrictEqual(g.pilots.Akane.hold, {});
  assert.strictEqual(g.bases.Akane.faction, 'compact');
  assert.strictEqual(G.chooseFaction(g, 'explorer', 'Akane', 'luminar').reason, 'your faction is already set');
  assert.ok(g.feed.some((f) => f.text === 'Akane joined the Terran Compact'));
});

test('players pick from three factions; only an admin may play the Coma Conglomerate', () => {
  const g = G.newGalaxy();
  assert.deepStrictEqual(F.PLAYABLE, ['compact', 'ashen', 'luminar']);
  assert.deepStrictEqual(Object.values(F.FACTIONS).map((f) => f.playable), [true, true, true, false]);
  G.claimBase(g, 'Akane');
  assert.strictEqual(G.chooseFaction(g, 'builder', 'Akane', 'coma').reason, "the Coma Conglomerate isn't open to players");
  assert.strictEqual(G.chooseFaction(g, 'explorer', 'Rin', 'coma').reason, "the Coma Conglomerate isn't open to players");
  assert.strictEqual(g.bases.Akane.faction, undefined);
  assert.strictEqual(g.pilots.Rin, undefined, 'a refused pick leaves no record');
  assert.ok(G.chooseFaction(g, 'builder', 'Akane', 'coma', 0, { admin: true }).ok);
  assert.strictEqual(G.chooseFaction(g, 'builder', 'Akane', 'compact', 0, { admin: true }).reason, 'your faction is already set', 'once, admin or not');
  assert.ok(G.chooseFaction(g, 'explorer', 'Rin', 'luminar', 0, { admin: true }).ok, 'admins may pick any faction');
});

test('factions and characters are looked up as the galaxy\'s own keys, never ones every object has', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  for (const f of ['constructor', 'toString', '__proto__']) assert.strictEqual(G.chooseFaction(g, 'builder', 'Akane', f, 0, { admin: true }).reason, 'no such faction', f);
  assert.strictEqual(G.chooseFaction(g, 'builder', 'constructor', 'compact').reason, 'claim a base first');
  G.chooseFaction(g, 'explorer', '__proto__', 'ashen');
  assert.deepStrictEqual([{}.faction, {}.hold], [undefined, undefined], 'nothing leaks into every object');
  assert.ok(G.chooseFaction(g, 'builder', 'Akane', 'compact').ok, 'and everyone else still picks their own');
  assert.ok(G.chooseFaction(g, 'explorer', 'Rin', 'luminar').ok);
});

test("a Builder's old satellite sites move to the roomiest sectors their faction holds", () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const sites = ['refinery', 'lab', 'spire'].map((type, i) => oldSite(g, 'Akane', type, i + 1));
  const r = G.chooseFaction(g, 'builder', 'Akane', 'luminar', 5000);
  assert.deepStrictEqual(r.moved, sites.map((s) => s.id));
  const halcyon = W.planet(g, 'halcyon');
  assert.deepStrictEqual(sites.map((s) => s.sector), ['halcyon-1', 'halcyon-2', 'halcyon-3'], 'each to the sector with the fewest outposts');
  for (const [i, s] of sites.entries()) {
    assert.strictEqual(s.parent, 'halcyon');
    assert.strictEqual(s.faction, 'luminar');
    assert.strictEqual(s.dormant, false);
    const sector = halcyon.sectors[i];
    assert.deepStrictEqual(s.surface, [sector.lat, sector.lon]);
    assert.strictEqual(s.id, `aster-site-${i + 1}`, 'the id stays, so raids and saves still find it');
  }
  assert.deepStrictEqual(sites.map((s) => s.name), ['Halcyon 1 Extractor', 'Halcyon 2 Armoury', 'Halcyon 3 Sensor Works']);
  assert.strictEqual(sites[0].buildings[0].level, 2, 'everything on it is kept');
  assert.strictEqual(sites[0].pieces.length, 1);
  assert.strictEqual(g.bases.Akane.alerts.length, 3);
  assert.match(g.bases.Akane.alerts[0].text, /moved to Halcyon 1/);
});

test('if their faction holds no planet in the system, old sites wait, dormant, and move once it does', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const site = oldSite(g, 'Akane', 'refinery', 1);
  const morrow = W.planet(g, 'morrow');
  morrow.owner = null; // as if the Conglomerate had lost it
  morrow.sectors[0].owner = 'ashen';
  assert.deepStrictEqual(G.chooseFaction(g, 'builder', 'Akane', 'coma', 0, { admin: true }).moved, []);
  assert.strictEqual(site.faction, 'coma');
  assert.strictEqual(site.sector, undefined);
  assert.strictEqual(site.parent, 'aster', 'it stays where it is...');
  assert.strictEqual(site.dormant, true, '...asleep');
  assert.ok(g.war.log.some((l) => l.text === "Akane's outposts on Aster went dormant"));
  const before = g.system.planets.filter((p) => p.kind === 'satellite').length;
  morrow.sectors[0].owner = 'coma';
  morrow.owner = 'coma';
  assert.ok(G.tick(g, 10_000));
  assert.strictEqual(site.parent, 'morrow');
  assert.strictEqual(site.sector, 'morrow-1');
  assert.strictEqual(site.dormant, false);
  assert.strictEqual(g.system.planets.filter((p) => p.kind === 'satellite').length, before);
  assert.ok(g.war.log.some((l) => l.text === "Akane's outposts on Morrow woke up"));
});

test('sites of a Builder with no faction never sleep', () => {
  const g = G.newGalaxy();
  G.claimBase(g, 'Akane');
  const site = oldSite(g, 'Akane', 'refinery', 1);
  G.recoverRaids(g);
  assert.strictEqual(site.dormant, false);
  W.planet(g, 'cinder').owner = null;
  G.tick(g, 5000);
  assert.strictEqual(site.dormant, false);
});
