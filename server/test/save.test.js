// Saves from before the war: satellite sites, fleet attacks in flight, no war map and no Coma director.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const D = require('../director');
const G = require('../galaxy');
const W = require('../war');
const { startServer } = require('../server');

// A galaxy as the server saved it before factions: Akane on Aster with two satellite sites, Rin on
// Brisa with fleets out attacking one of them, and no war.
function oldSave() {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  G.claimBase(g, 'Akane');
  G.claimBase(g, 'Rin');
  delete g.war;
  delete g.director;
  delete g.contracts;
  delete g.nextContractId;
  // Six pads around the command centre, any building on any pad: no Command Centre building.
  for (const p of g.system.planets) p.buildings = [];
  g.system.planets[0].buildings = [
    { slot: 0, type: 'mine', level: 2 },
    { slot: 1, type: 'spaceport', level: 1 },
    { slot: 3, type: 'mine', level: 1 },
  ];
  for (const e of Object.values(g.bases)) {
    for (const k of ['merit', 'market', 'alerts']) delete e[k];
    e.unlocked = ['mine', 'extractor', 'habitat', 'spaceport', 'refinery', 'lab', 'spire', 'foundry'];
  }
  const site = (n, type, name) => ({
    id: `aster-site-${n}`, name, kind: 'satellite', owner: 'Akane', parent: 'aster', orbit: n - 1, slots: 1, grid: 12,
    pieces: [{ id: 1, type: 'turret', x: 0, y: 0 }], obstacles: [], nextPiece: 2, surface: [-45, 210 + n * 60],
    buildings: [{ slot: 0, type, level: 1, security: 1, vault: { alloy: 5 }, made: 3, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: { alloy: 2 } }],
  });
  g.system.planets.push(site(1, 'refinery', 'Aster Mining Refinery'), site(2, 'lab', 'Aster Research Outpost'));
  g.bases.Rin.navy = { corvette: 1, frigate: 0, destroyer: 0 };
  g.attacks = [
    { id: 1, attacker: 'Rin', defender: 'Akane', target: 'aster-site-1', siteName: 'Aster Mining Refinery', ships: { frigate: 2 }, status: 'flying', arriveAt: 5, leg: 60_000 },
    { id: 2, attacker: 'Rin', defender: 'Akane', target: 'aster-site-2', siteName: 'Aster Research Outpost', ships: { corvette: 3 }, status: 'returning', returnAt: 9, leg: 40_000,
      survivors: { corvette: 2 }, lost: { corvette: 1 }, loot: { alloy: 4, shard: 1 }, won: true },
  ];
  g.attackLog = [{ at: 1, attacker: 'Rin', defender: 'Akane', site: 'Aster Research Outpost', won: true, lost: { corvette: 1 }, loot: { alloy: 4, shard: 1 } }];
  g.nextAttackId = 2;
  g.pilots['Pilot A'] = { credits: 10, reputation: 0, cargo: {} };
  return JSON.parse(JSON.stringify(g));
}

test('an old save with satellite sites, attacks in flight and no war loads and plays on', () => {
  const g = oldSave();
  const credits = g.bases.Rin.credits;
  G.recoverRaids(g);
  // The war map arrives with its starting owners, and the Coma director with it.
  assert.strictEqual(W.planet(g, 'cinder').owner, 'compact');
  assert.strictEqual(g.war.planets.length, 17);
  assert.deepStrictEqual(g.contracts, []);
  assert.deepStrictEqual([g.director.paused, g.director.scale], [false, 1]);
  assert.deepStrictEqual(g.director.posture, { 'teal-prime': 'push', marrow: 'push', drift: 'push' });
  assert.deepStrictEqual(g.director.overrides, { compact: null, ashen: null, luminar: null });
  assert.strictEqual(g.director.auto.luminar, 1);
  // Fleets that were out come home with what they carried, and the attacks are gone.
  assert.deepStrictEqual(g.attacks, []);
  assert.deepStrictEqual(g.bases.Rin.navy, { corvette: 3, frigate: 2, destroyer: 0 });
  assert.strictEqual(g.bases.Rin.stock.alloy, 4);
  assert.strictEqual(g.bases.Rin.credits, credits + 300, 'intel sells as it lands');
  // Every base has its new unlocks and war records; pilots their hold.
  for (const e of Object.values(g.bases)) {
    for (const type of G.OUTPOSTS.concat('dock')) assert.ok(e.unlocked.includes(type), type);
    assert.deepStrictEqual([e.merit, e.market, e.alerts], [0, {}, []]);
  }
  assert.deepStrictEqual(g.pilots['Pilot A'].hold, {});
  // The old pads move onto the nodes: one Extractor (the best Mine), the Star Port, and a Command
  // Centre at the level that keeps both outposts.
  const aster = g.system.planets.find((p) => p.id === 'aster');
  assert.deepStrictEqual(aster.buildings.map((b) => [b.slot, b.type, b.level]), [[1, 'extractor', 2], [0, 'spaceport', 1], [8, 'command', 3]]);
  assert.deepStrictEqual(g.system.planets.find((p) => p.owner === 'Rin').buildings.map((b) => [b.slot, b.type, b.level]), [[8, 'command', 1]]);
  // The old sites keep working where they are, never dormant, open to any raider.
  const [a, b] = g.system.planets.filter((p) => p.kind === 'satellite');
  assert.strictEqual(a.dormant, false);
  assert.deepStrictEqual(a.buildings[0].vault, { alloy: 7 }, 'escrow back in the vault');
  assert.deepStrictEqual(a.surface, [-45, 270]);
  assert.ok(G.startRaid(g, 'Pilot A', a.id, 0, 0, 1, 2).ok);
  G.tick(g, 1000);
  // Akane picks a side, and her sites move to its ground.
  assert.deepStrictEqual(G.chooseFaction(g, 'builder', 'Akane', 'ashen').moved, [a.id, b.id]);
  assert.deepStrictEqual([a.parent, a.sector, b.sector], ['vesper', 'vesper-1', 'vesper-2']);
  assert.strictEqual(a.name, 'Vesper 1 Extractor');
  assert.match(G.foundSite(g, 'Akane', 'munitions', 'vesper', 'vesper-1').reason, /allows 2 outposts/);
  G.setCommandLevel(g, 'aster', 5);
  assert.ok(G.foundSite(g, 'Akane', 'munitions', 'vesper', 'vesper-1').ok);
  assert.match(G.foundSite(g, 'Akane', 'fuel', 'cinder', 'cinder-1').reason, /doesn't hold Cinder/);
  G.tick(g, 2000);
  // Its director takes its first turn when due, like any other.
  g.director.runAt = 3000;
  assert.ok(G.tick(g, 3000));
  assert.ok(g.war.fleets.some((fl) => fl.ai));
});

test('a director saved by an older build is filled in, and keeps what it has', () => {
  const g = G.newGalaxy();
  g.director = { paused: true, scale: 1.5, overrides: { ashen: 0.25 }, posture: { marrow: 'hold' }, runAt: 42 };
  G.recoverRaids(g);
  const d = g.director;
  assert.deepStrictEqual([d.paused, d.scale, d.runAt], [true, 1.5, 42]);
  assert.deepStrictEqual(d.overrides, { ashen: 0.25, compact: null, luminar: null });
  assert.deepStrictEqual(d.posture, { marrow: 'hold', 'teal-prime': 'push', drift: 'push' });
  assert.strictEqual(d.intensity.ashen, 0.25);
  assert.ok(D.set(g, {}, 1000).ok, 'and works');
});

test('loading again never changes a war that is already there', () => {
  const g = G.newGalaxy();
  const cinder = W.planet(g, 'cinder');
  cinder.sectors[3].owner = 'ashen';
  cinder.lockedUntil = 12345;
  W.planet(g, 'scar').owner = 'compact';
  g.war.nextFleetId = 7;
  const before = JSON.stringify(g.war.planets);
  G.recoverRaids(JSON.parse(JSON.stringify(g)));
  const again = JSON.parse(JSON.stringify(g));
  G.recoverRaids(again);
  assert.strictEqual(JSON.stringify(again.war.planets.map((p) => ({ ...p, contenders: [] }))), JSON.stringify(JSON.parse(before).map((p) => ({ ...p, contenders: [] }))));
  assert.strictEqual(again.war.nextFleetId, 7);
  // A war saved from a smaller map gets the planets it lacks, leaving the rest alone.
  const small = JSON.parse(JSON.stringify(g));
  small.war.planets = small.war.planets.filter((p) => p.id !== 'mire');
  W.ensureWar(small);
  assert.ok(W.planet(small, 'mire'));
  assert.strictEqual(W.planet(small, 'cinder').sectors[3].owner, 'ashen');
});

test('the server loads an old save file and broadcasts the war', async () => {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'teal-')), 'galaxy.json');
  fs.writeFileSync(file, JSON.stringify(oldSave()));
  const server = startServer({ port: 18095, saveFile: file, buildSpeed: Infinity, tickMs: 60000 });
  try {
    assert.ok(server.galaxy.war);
    assert.ok(server.galaxy.director);
    assert.deepStrictEqual(server.galaxy.attacks, []);
    assert.strictEqual(server.galaxy.bases.Rin.navy.frigate, 2);
  } finally {
    await server.close();
    fs.rmSync(path.dirname(file), { recursive: true, force: true });
  }
});

test('buildings from other versions load: an Ice Well becomes an Ice Extractor, unknown ones go', () => {
  const g = G.newGalaxy();
  const aster = g.system.planets.find((p) => p.id === 'aster');
  aster.buildings.push({ slot: 4, type: 'icewell', level: 1 }, { slot: 5, type: 'teleporter', level: 1 });
  G.recoverRaids(g);
  assert.strictEqual(aster.buildings.find((b) => b.slot === 4).type, 'extractor');
  assert.ok(!aster.buildings.some((b) => b.slot === 5));
  assert.ok(G.upgradeBuilding(g, 'aster', 4).ok !== undefined); // no crash
});
