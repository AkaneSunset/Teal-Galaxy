// Outposts: founding them on ground your faction holds, dormancy when it's lost, who may raid
// them, the faction bonuses, and raids on every outpost type.

const test = require('node:test');
const assert = require('node:assert');
const G = require('../galaxy');
const H = require('../heist');
const W = require('../war');

// A galaxy where each named Builder has a base (stocked as in demo mode) and the given faction
// (picked as an admin, so the Coma Conglomerate can be one).
function galaxy(builders) {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity;
  for (const [name, faction] of Object.entries(builders)) {
    G.setCommandLevel(g, G.claimBase(g, name).id, 5); // room for every outpost
    G.demoTopUp(g.bases[name]);
    G.chooseFaction(g, 'builder', name, faction, 0, { admin: true });
  }
  return g;
}

function found(g, owner, type, planet, sector) {
  const r = G.foundSite(g, owner, type, planet, sector);
  assert.ok(r.ok, r.reason);
  return r.site;
}

// Puts `ships` from `owner`'s navy in orbit over Teal Prime.
function station(g, owner, ships, now = 0) {
  for (const [id, n] of Object.entries(ships)) g.bases[owner].navy[id] += n;
  const { fleet } = W.sendFleet(g, owner, 'teal-prime', ships, now);
  W.warTick(g, fleet.arriveAt);
  return fleet;
}

test('outposts need a faction, a planet it holds in Teal Prime, and a sector it holds', () => {
  const g = galaxy({});
  G.claimBase(g, 'Akane');
  G.demoTopUp(g.bases.Akane);
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'cinder', 'cinder-1').reason, 'choose a faction first');
  G.chooseFaction(g, 'builder', 'Akane', 'compact');
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'cinder', 'cinder-1').reason, 'upgrade your Command Centre to level 2 to found outposts');
  G.setCommandLevel(g, 'aster', 2);
  assert.strictEqual(G.foundSite(g, 'Akane', 'mine', 'cinder', 'cinder-1').reason, 'that is not an outpost');
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'vesper', 'vesper-1').reason, "the Terran Compact doesn't hold Vesper");
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'bastion', 'bastion-1').reason, 'outposts go on the contested planets of Teal Prime');
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'aster', 'aster-1').reason, 'outposts go on the contested planets of Teal Prime');
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'cinder', 'vesper-2').reason, 'pick a sector of Cinder');
  W.planet(g, 'cinder').sectors[5].owner = 'ashen';
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'cinder', 'cinder-6').reason, "the Terran Compact doesn't hold Cinder 6");
  assert.strictEqual(G.foundSite(g, 'Nobody', 'fuel', 'cinder', 'cinder-1').reason, 'you have no home planet');
  assert.match(G.build(g, 'aster', 0, 'fuel').reason, /outpost/);

  const e = g.bases.Akane;
  e.stock.metal = 10;
  assert.strictEqual(G.foundSite(g, 'Akane', 'fuel', 'cinder', 'cinder-7').reason, 'not enough metal');
  assert.strictEqual(g.system.planets.length, 1, 'nothing founded');
  e.stock.metal = 100;
  const site = found(g, 'Akane', 'fuel', 'cinder', 'cinder-7');
  assert.strictEqual(e.stock.metal, 70);
  assert.strictEqual(e.stock.ice, 190);
  const sector = W.planet(g, 'cinder').sectors[6];
  assert.deepStrictEqual(
    { id: site.id, name: site.name, kind: site.kind, owner: site.owner, parent: site.parent, sector: site.sector, faction: site.faction, dormant: site.dormant, surface: site.surface },
    { id: 'cinder-op-1', name: 'Cinder 7 Fuel Depot', kind: 'satellite', owner: 'Akane', parent: 'cinder', sector: 'cinder-7', faction: 'compact', dormant: false, surface: [sector.lat, sector.lon] });
  assert.ok(G.facility(g, site.id, 0).type === 'fuel');
  assert.ok(G.owns(g, 'Akane', site.id));
});

test('five outposts a Builder, three a sector between all Builders', () => {
  const g = galaxy({ Akane: 'compact', Rin: 'compact' });
  found(g, 'Akane', 'refinery', 'cinder', 'cinder-1');
  found(g, 'Akane', 'lab', 'cinder', 'cinder-1');
  found(g, 'Rin', 'spire', 'cinder', 'cinder-1');
  assert.strictEqual(G.foundSite(g, 'Rin', 'fuel', 'cinder', 'cinder-1').reason, 'Cinder 1 already has 3 outposts');
  assert.deepStrictEqual(g.system.planets.filter((p) => p.sector === 'cinder-1').map((p) => p.id), ['cinder-op-1', 'cinder-op-2', 'cinder-op-3']);
  for (const type of ['fuel', 'munitions', 'ordnance']) found(g, 'Akane', type, 'cinder', 'cinder-2');
  assert.strictEqual(G.foundSite(g, 'Akane', 'drones', 'cinder', 'cinder-3').reason, 'your Command Centre allows 5 outposts: upgrade it for more');
  found(g, 'Rin', 'drones', 'cinder', 'cinder-3');
});

test('outposts go dormant when their planet falls, and wake as they were when it is retaken', () => {
  const g = galaxy({ Akane: 'compact', Rin: 'ashen' });
  const site = found(g, 'Akane', 'refinery', 'cinder', 'cinder-5');
  const fac = site.buildings[0];
  G.tick(g, 1000);
  G.tick(g, 2000);
  fac.vault = { alloy: 7, isotope: 1 };
  const kept = JSON.stringify(site);
  const rin = station(g, 'Rin', { corvette: 1 });

  // The Ashen Collective takes Cinder's capital sector: the Compact no longer holds Cinder.
  assert.ok(W.capture(g, 'cinder', 'cinder-1', 'ashen', 20_000).ok);
  assert.strictEqual(site.dormant, true);
  assert.strictEqual(g.bases.Akane.alerts.at(-1).text, 'Cinder 1 fell to the Ashen Collective: your outposts on Cinder are at risk');
  assert.ok(g.war.log.some((l) => l.text === "Akane's outposts on Cinder went dormant"));
  assert.ok(!g.bases.Rin.alerts.some((a) => /at risk/.test(a.text)), 'only Builders with outposts there hear of it');

  // Asleep: nothing made or shipped, nothing built or upgraded.
  for (let t = 25_000; t < 25_000 + G.AUTO_SHIP_MS + 10_000; t += 5000) G.tick(g, t);
  assert.deepStrictEqual(fac.vault, { alloy: 7, isotope: 1 });
  assert.strictEqual(g.bases.Akane.stock.alloy, 200, 'no freighter came');
  assert.strictEqual(G.ship(g, site.id, 0, 400_000).reason, 'the outpost is dormant');
  assert.strictEqual(G.placePiece(g, site.id, 'wall', 0, 0).reason, 'the outpost is dormant');
  assert.strictEqual(G.removePiece(g, site.id, 1).reason, 'the outpost is dormant');
  assert.strictEqual(G.clearObstacle(g, site.id, site.obstacles[0].id).reason, 'the outpost is dormant');
  assert.strictEqual(G.secure(g, site.id, 0).reason, 'the outpost is dormant');
  assert.strictEqual(G.upgradeBuilding(g, site.id, 0, 400_000).reason, 'the outpost is dormant');
  // Raiders can still break in.
  G.chooseFaction(g, 'explorer', 'Pilot A', 'ashen');
  const raid = G.startRaid(g, 'Pilot A', site.id, 0, 400_000, 5, 6);
  assert.ok(raid.ok, raid.reason);
  G.endRaid(g, raid.run, 'bailed', 401_000);
  fac.cooldownUntil = 0;
  assert.deepStrictEqual(fac.vault, { alloy: 7, isotope: 1 }, 'a raider who bails takes nothing');

  // The Ashen fleet goes home and the Compact takes the capital sector back: Cinder is theirs again
  // and locks, and the outpost wakes.
  assert.match(W.capture(g, 'cinder', 'cinder-1', 'compact', 480_000).reason, /orbital control/);
  assert.ok(W.recallFleet(g, 'Rin', rin.id, 480_000).ok);
  station(g, 'Akane', { corvette: 1 }, 480_000);
  assert.ok(W.capture(g, 'cinder', 'cinder-1', 'compact', 500_000).ok);
  assert.strictEqual(W.planet(g, 'cinder').owner, 'compact');
  assert.strictEqual(W.planet(g, 'cinder').lockedUntil, 500_000 + W.LOCK_MS);
  assert.strictEqual(site.dormant, false);
  assert.ok(g.war.log.some((l) => l.text === "Akane's outposts on Cinder woke up"));
  const now = JSON.parse(JSON.stringify(site));
  for (const k of ['autoShipAt', 'made', 'cooldownUntil']) delete now.buildings[0][k];
  const was = JSON.parse(kept);
  for (const k of ['autoShipAt', 'made', 'cooldownUntil']) delete was.buildings[0][k];
  assert.deepStrictEqual(now, was, 'exactly as it was');
  G.tick(g, 600_000);
  assert.strictEqual(g.bases.Akane.stock.alloy, 207, 'the overdue freighter comes as it wakes...');
  assert.strictEqual(fac.vault.alloy, 1, '...and the vault fills again');
});

test('raids: only pilots of another faction, never the Builder\'s own pilot; old sites, anyone', () => {
  const g = galaxy({ Akane: 'compact' });
  const site = found(g, 'Akane', 'spire', 'cinder', 'cinder-1');
  assert.strictEqual(G.startRaid(g, 'Pilot A', site.id, 0, 0, 1, 1).reason, 'choose a faction first');
  G.chooseFaction(g, 'explorer', 'Pilot A', 'compact');
  assert.strictEqual(G.startRaid(g, 'Pilot A', site.id, 0, 0, 1, 1).reason, 'that outpost belongs to your own faction');
  G.chooseFaction(g, 'explorer', 'Akane', 'luminar');
  assert.strictEqual(G.startRaid(g, 'Akane', site.id, 0, 0, 1, 1).reason, "you can't raid your own outpost");
  G.chooseFaction(g, 'explorer', 'Pilot B', 'coma', 0, { admin: true });
  assert.ok(G.startRaid(g, 'Pilot B', site.id, 0, 0, 1, 1).ok);
  // A site from before the war, of a Builder with no faction, is open to anyone.
  G.claimBase(g, 'Old');
  G.demoTopUp(g.bases.Old);
  const old = { id: 'brisa-site-1', name: 'Brisa Mining Refinery', kind: 'satellite', owner: 'Old', parent: 'brisa', slots: 1, grid: 12, pieces: [], obstacles: [], nextPiece: 1,
    buildings: [{ slot: 0, type: 'refinery', level: 1, security: 1, vault: {}, made: 0, shipReadyAt: 0, cooldownUntil: 0, alarmReadyAt: 0, escrow: {} }] };
  g.system.planets.push(old);
  assert.ok(G.startRaid(g, 'Nobody', old.id, 0, 0, 1, 1).ok);
});

test('faction bonuses: tough Compact defences, hot Ashen raids, Luminar production, Coma recovery', () => {
  const g = galaxy({ Cara: 'compact', Ash: 'ashen', Lumi: 'luminar', Co: 'coma' });
  for (const [pilot, f] of [['Pilot C', 'compact'], ['Pilot A', 'ashen']]) G.chooseFaction(g, 'explorer', pilot, f);
  const compact = found(g, 'Cara', 'refinery', 'cinder', 'cinder-1');
  compact.pieces = [{ id: 1, type: 'turret', x: 0, y: 0 }, { id: 2, type: 'power', x: 10, y: 10 }];
  compact.obstacles = [];
  compact.buildings[0].security = 2;
  const run = G.startRaid(g, 'Pilot A', compact.id, 0, 0, 3, 4).run;
  assert.deepStrictEqual(run.layout.pieces.map((p) => [p.type, p.hp]), [['turret', 313], ['power', 500], ['turret', 313]], '25% more hit points, the core\'s turret too');
  assert.strictEqual(run.heatScale, 1);

  const ashen = found(g, 'Ash', 'fuel', 'vesper', 'vesper-1');
  const hot = G.startRaid(g, 'Pilot C', ashen.id, 0, 0, 3, 4).run;
  assert.strictEqual(hot.heatScale, 1.25);
  H.report(hot, 'gunshot', 0);
  H.report(hot, 'spotted', 0);
  assert.strictEqual(hot.heat, 16.25, 'Heat builds 25% faster');
  assert.ok(hot.layout.pieces.filter((p) => p.hp > 0).every((p) => p.hp === H.SITE_PIECES[p.type].hp), 'only the Compact\'s are tougher');

  G.endRaid(g, run, 'bailed', 10_000);
  assert.strictEqual(compact.buildings[0].cooldownUntil, 10_000 + H.RAID_COOLDOWN_MS);
  const coma = found(g, 'Co', 'drones', 'morrow', 'morrow-1');
  const r = G.startRaid(g, 'Pilot A', coma.id, 0, 0, 3, 4);
  G.endRaid(g, r.run, 'bailed', 10_000);
  assert.strictEqual(coma.buildings[0].cooldownUntil, 10_000 + H.RAID_COOLDOWN_MS / 2, 'recovers twice as fast');

  // Luminar outposts make 20% more, paid in whole items; War Merit ranks add to it.
  const lumi = found(g, 'Lumi', 'refinery', 'halcyon', 'halcyon-1');
  const fac = lumi.buildings[0];
  for (let t = 1; t <= 5; t++) G.tick(g, t * 1000);
  assert.strictEqual(fac.vault.alloy, 6, '1.2 a tick for 5 ticks');
  const plain = found(g, 'Cara', 'refinery', 'cinder', 'cinder-2');
  for (let t = 6; t <= 10; t++) G.tick(g, t * 1000);
  assert.strictEqual(plain.buildings[0].vault.alloy, 5);
  fac.vault = {};
  fac.makeCarry = {};
  g.bases.Lumi.merit = 2000; // Quartermaster: +4%
  for (let t = 11; t <= 35; t++) G.tick(g, t * 1000);
  assert.strictEqual(fac.vault.alloy, 31, '1.24 a tick for 25 ticks');
  for (let t = 36; t <= 80; t++) G.tick(g, t * 1000);
  assert.strictEqual(fac.vault.alloy, 40, 'never past the cap');
});

test('every outpost type can be raided: its layout, its vault goods and the 5x4 vault', () => {
  for (const [id, def] of Object.entries(H.ITEMS)) assert.ok(new H.Grid(5, 4).findFree(def.size), `${id} fits the vault`);
  assert.deepStrictEqual(G.OUTPOSTS, ['refinery', 'lab', 'spire', 'fuel', 'munitions', 'ordnance', 'drones', 'landers', 'haulers']);
  const g = galaxy({ One: 'luminar', Two: 'luminar' });
  G.chooseFaction(g, 'explorer', 'Pilot A', 'coma', 0, { admin: true });
  const sites = G.OUTPOSTS.map((type, i) => found(g, i < 5 ? 'One' : 'Two', type, 'halcyon', `halcyon-${1 + Math.floor(i / 3)}`));
  let seed = 1;
  for (const site of sites) {
    const fac = site.buildings[0];
    const def = H.FACILITIES[fac.type];
    assert.ok(def && G.BUILDINGS[fac.type].facility && G.BUILD_S[fac.type] > 0, fac.type);
    for (const level of [1, 3, 5]) {
      fac.level = level;
      fac.cooldownUntil = 0;
      fac.vault = Object.fromEntries(def.makes.map((m) => [m.item, m.cap * level]));
      const full = { ...fac.vault };
      const r = G.startRaid(g, 'Pilot A', site.id, 0, 0, seed++, seed++);
      assert.ok(r.ok, `${fac.type} level ${level}: ${r.reason}`);
      const run = r.run;
      assert.strictEqual(run.layout.floors.length, level);
      const boxes = run.layout.containers.filter((c) => c.type === 'vault');
      for (const m of def.makes) {
        assert.ok(fac.escrow[m.item] > 0, `${fac.type} level ${level}: some ${m.item} is in the vault`);
        const inVault = boxes.reduce((n, c) => n + run.boxes[c.id].items.filter((it) => it.item === m.item).reduce((a, it) => a + it.vaultQty, 0), 0);
        assert.strictEqual(inVault, fac.escrow[m.item], 'what left the vault is exactly what lies in the vault boxes');
      }
      for (const c of run.layout.containers) {
        for (const it of run.boxes[c.id].items) assert.ok(run.boxes[c.id].grid.placed[it.uid], 'every item has its place in the grid');
      }
      assert.ok(Object.values(run.boxes).some((b) => b.items.some((it) => it.item === 'keycard')));
      G.endRaid(g, run, 'bailed', 1000);
      assert.deepStrictEqual(fac.vault, full, 'bailing out leaves the vault as it was');
    }
  }
  // Supply outposts' raids turn up war supplies more often.
  const share = (bias) => {
    const r = H.rng(11);
    let fuel = 0;
    for (let i = 0; i < 5000; i++) for (const s of H.rollTable({ rolls: [1, 1], none: 0, entries: [['scrap', 1, 1, 1], ['fuel', 1, 1, 1]] }, 1, bias, r)) if (s.item === 'fuel') fuel++;
    return fuel / 5000;
  };
  assert.ok(share('supply') > 0.6 && share('material') < 0.55, `${share('supply')} vs ${share('material')}`);
  // And shipping the vault home puts war supplies in stock like materials.
  const fuel = sites[3];
  fuel.buildings[0].vault = { fuel: 12 };
  const before = g.bases.One.stock.fuel || 0;
  assert.ok(G.ship(g, fuel.id, 0, 10_000_000).ok);
  assert.strictEqual(g.bases.One.stock.fuel, before + 12);
});
