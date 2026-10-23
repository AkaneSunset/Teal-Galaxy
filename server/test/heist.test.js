// Raid rules: the site and its levels, the breach, loot, inventory, Heat, reinforcements, the
// self-destruct and extraction, plus full raids over WebSockets.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const H = require('../heist');
const G = require('../galaxy');
const { startServer } = require('../server');

// Akane's outpost on Cinder, held by her faction (the Terran Compact), and raiders from the Ashen
// Collective, who may break into it.
function outpost(g, type, owner = 'Akane') {
  G.setCommandLevel(g, G.claimBase(g, owner).id, 5); // room for every outpost
  if (!g.bases[owner].faction) G.chooseFaction(g, 'builder', owner, 'compact');
  for (const pilot of ['Pilot A', 'Pilot B']) if (!g.pilots[pilot]?.faction) G.chooseFaction(g, 'explorer', pilot, 'ashen');
  const r = G.foundSite(g, owner, type, 'cinder', 'cinder-1');
  assert.ok(r.ok, r.reason);
  return r;
}

test('every level connects, the lifts line up, and the safe room is locked on the deepest', () => {
  for (const tier of [1, 2, 3])
    for (let floors = 1; floors <= H.MAX_FLOORS; floors++)
      for (let seed = 1; seed <= 300; seed++) {
        const L = H.generateLayout(seed, tier, 'refinery', { floors });
        const at = (id) => L.rooms.find((r) => r.id === id);
        assert.strictEqual(L.floors.length, floors);
        assert.deepStrictEqual(at(L.floors[0].entrance).pos, [0, 0], 'level 1 lift is under the core');
        for (const fl of L.floors) {
          const own = L.rooms.filter((r) => r.floor === fl.n);
          const adj = (n) => L.doors.filter((d) => !d.locked && (d.a === n || d.b === n)).map((d) => (d.a === n ? d.b : d.a));
          const seen = new Set([fl.entrance]);
          const queue = [fl.entrance];
          while (queue.length) for (const n of adj(queue.shift())) if (!seen.has(n)) seen.add(n) && queue.push(n);
          const last = fl.n === floors;
          assert.strictEqual(seen.size, own.length - (last ? 1 : 0), `tier ${tier} floors ${floors} seed ${seed} level ${fl.n}`);
          assert.ok([...seen].every((id) => at(id).floor === fl.n), 'doors stay on their level');
          if (last) assert.ok(fl.safe === L.vault && !seen.has(L.vault), 'safe room locked');
          else assert.deepStrictEqual(at(L.floors[fl.n].entrance).pos, at(fl.down).pos, 'lift down lands under itself');
        }
        assert.ok(!L.containers.some((c) => c.type === 'vault' && c.room !== L.vault));
        assert.ok(L.guards.every((g) => g.route.every((id) => at(id).floor === g.floor)));
        assert.deepStrictEqual(L.extracts.map((e) => e.kind), ['ship']);
      }
});

test('the raid map mirrors the Builder\'s site', () => {
  const site = {
    kind: 'satellite',
    grid: 12,
    pieces: [
      { id: 1, type: 'turret', x: 0, y: 0 },
      { id: 2, type: 'power', x: 10, y: 10 },
      { id: 3, type: 'wall', x: 5, y: 2 },
      { id: 4, type: 'guardpost', x: 0, y: 10, readyAt: 5000 }, // still being built
    ],
    obstacles: [{ id: 5, type: 'boulder', x: 2, y: 4 }],
  };
  const L = H.generateLayout(7, 1, 'lab', { site, now: 1000 });
  assert.deepStrictEqual(L.pieces.map((p) => p.id), ['p1', 'p2', 'p3', 'o5']);
  assert.deepStrictEqual(L.view.pieces.map((p) => p.id), [1, 2, 3], 'the raider draws exactly what the Builder placed');
  const turret = L.pieces[0];
  assert.deepStrictEqual(turret.pos, [-20, -20], 'top-left 2x2 tile, in metres round the core');
  assert.deepStrictEqual(turret.size, [8, 8]);
  assert.strictEqual(L.powered, 'plant');
  assert.strictEqual(H.generateLayout(7, 1, 'lab', { site: { ...site, pieces: [] }, now: 1000 }).powered, 'core');
  // A facility without a site gets a power plant and defences from its tier.
  const d = H.generateLayout(7, 3, 'lab');
  assert.strictEqual(d.pieces.filter((p) => p.type === 'power').length, 1);
  assert.strictEqual(d.pieces.filter((p) => p.type === 'turret' && !p.ring).length, 3);
  assert.strictEqual(d.pieces.filter((p) => p.ring).length, H.SECURITY[3].turrets, 'and the turrets its tier mounts on the core');
});

test('the same seed builds the same facility', () => {
  assert.deepStrictEqual(H.generateLayout(42, 2, 'lab'), H.generateLayout(42, 2, 'lab'));
});

test('rarer loot shows up more at higher security', () => {
  const r = H.rng(9);
  const rareShare = (tier) => {
    let rare = 0;
    let all = 0;
    for (let i = 0; i < 20000; i++)
      for (const s of H.rollTable({ rolls: [1, 1], none: 0, entries: [['scrap', 10, 1, 1], ['exotic', 1, 1, 1]] }, tier, 'plan', r)) {
        all++;
        if (s.item === 'exotic') rare++;
      }
    return rare / all;
  };
  assert.ok(rareShare(3) > rareShare(1) * 1.5);
});

test('inventory grid places, rotates and refuses overlaps', () => {
  const g = new H.Grid(3, 2);
  assert.deepStrictEqual(g.findFree([1, 3]), { x: 0, y: 0, w: 3, h: 1 }); // only fits rotated
  assert.ok(g.place('a', { x: 0, y: 0, w: 2, h: 2 }));
  assert.ok(!g.place('b', { x: 1, y: 0, w: 2, h: 1 }));
  assert.deepStrictEqual(g.findFree([1, 2]), { x: 2, y: 0, w: 1, h: 2 });
  g.remove('a');
  assert.ok(g.place('b', { x: 1, y: 0, w: 2, h: 1 }));
});

// A facility with a known vault, and a run on it at a fixed time.
// The site's defences: two turrets, a guard post, a wall and the power plant.
const DEFENCES = [
  { id: 1, type: 'turret', x: 0, y: 0 },
  { id: 2, type: 'guardpost', x: 9, y: 0 },
  { id: 3, type: 'wall', x: 5, y: 1 },
  { id: 4, type: 'power', x: 10, y: 10 },
  { id: 5, type: 'turret', x: 0, y: 9 },
];

function setup(vault = { alloy: 10, drive: 2 }, { security = 1, levels = 1, inside = true, pieces = DEFENCES } = {}) {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity; // instant buildings: build times are tested in levels.test.js
  g.stock.metal = 999;
  G.claimBase(g, 'Akane');
  const { site } = outpost(g, 'refinery');
  const fac = G.facility(g, site.id, 0);
  fac.vault = { ...vault };
  fac.security = security;
  fac.level = levels;
  if (pieces) site.pieces = pieces;
  const r = G.startRaid(g, 'Pilot A', site.id, 0, 0, 1234, 99);
  assert.ok(r.ok, r.reason);
  assert.ok(H.land(r.run, ...landSpot(r.run.layout), 0).ok);
  if (inside) {
    H.ventStart(r.run, 'v0', 0);
    assert.ok(H.ventFinish(r.run, 6000).ok);
  }
  return { g, fac, run: r.run };
}

// Somewhere the ship may drop you off.
function landSpot(layout) {
  for (let a = 0; a < 360; a += 5) {
    const spot = [Math.cos((a * Math.PI) / 180) * 100, Math.sin((a * Math.PI) / 180) * 100];
    if (!H.landingProblem(layout, ...spot)) return spot;
  }
  throw new Error('nowhere to land');
}

// Knocks out every outside defence, so the ship comes back.
function clearDefences(run) {
  for (const p of run.layout.pieces) if (H.DEFENCE_TYPES.includes(p.type)) H.destroy(run, p.id, 0);
}

function boxWith(run, item) {
  return Object.entries(run.boxes).find(([, b]) => b.items.some((it) => it.item === item))[0];
}

test('containers reveal over time and nothing can be taken early', () => {
  const { run } = setup();
  const cid = boxWith(run, 'keycard');
  assert.ok(H.openContainer(run, cid, 0).ok);
  const card = run.boxes[cid].items.find((it) => it.item === 'keycard');
  assert.match(H.take(run, card.uid, 'backpack', 0).reason, /searching/);
  const view = H.containerView(run, 0);
  assert.ok(view.slots.every((s) => !s.item), 'only placeholders at first');
  assert.ok(H.take(run, card.uid, 'secure', 60_000).ok);
  assert.strictEqual(H.inventoryView(run)[0].grid, 'secure');
});

test('the vault is locked until a keycard or the drill opens it', () => {
  const { run } = setup();
  const vaultBox = run.layout.containers.find((c) => c.type === 'vault').id;
  assert.match(H.openContainer(run, vaultBox, 0).reason, /locked/);
  assert.match(H.useKeycard(run, 0).reason, /keycard/);
  H.drillStart(run, 1000);
  assert.match(H.drillFinish(run, 20_000).reason, /not through/);
  assert.ok(H.drillFinish(run, 31_000).ok);
  assert.ok(run.heat >= 10, `drilling is loud: Heat ${run.heat}`);
  assert.ok(H.openContainer(run, vaultBox, 31_000).ok);
  assert.strictEqual(run.selfDestructAt, 31_000 + H.selfDestructSeconds(1) * 1000, 'opening the vault starts the self-destruct');
});

test('breach: the blast door opens only when the power plant is down; vents take time', () => {
  const { run } = setup({}, { inside: false });
  const cid = run.layout.containers[0].id;
  assert.match(H.openContainer(run, cid, 0).reason, /inside/);
  assert.match(H.enterDoor(run, 0).reason, /power plant/);
  const turret = run.layout.pieces.find((p) => p.type === 'turret' || p.type === 'guardpost');
  assert.ok(H.destroy(run, turret.id, 0).changed);
  assert.ok(!H.destroy(run, turret.id, 0).changed, 'only counts once');
  assert.strictEqual(run.heat, 5, 'explosions are loud');
  const wall = run.layout.pieces.find((p) => p.type === 'wall');
  assert.match(H.destroy(run, wall.id, 0).reason, /can't/);
  const power = run.layout.pieces.find((p) => p.type === 'power');
  assert.ok(H.destroy(run, power.id, 0).doorOpened);
  assert.ok(H.enterDoor(run, 1000).ok);
  assert.strictEqual(H.stage(run, 1000).stage, 'loot');

  const quiet = setup({}, { inside: false }).run;
  H.ventStart(quiet, 'v1', 0);
  assert.match(H.ventFinish(quiet, 3000).reason, /not cut/);
  assert.ok(H.ventFinish(quiet, 6000).ok);
  assert.strictEqual(quiet.breached, 'vent');
  assert.strictEqual(quiet.heat, 0, 'a vent is silent');
});

test('every minute inside brings a bigger wave', () => {
  const { run } = setup(); // inside at 6 s
  assert.strictEqual(H.waveTick(run, 60_000), null);
  assert.deepStrictEqual(H.waveTick(run, 66_000), { wave: 1, count: 1 });
  assert.strictEqual(H.waveTick(run, 70_000), null, 'once per minute');
  assert.deepStrictEqual(H.waveTick(run, 126_000), { wave: 2, count: 2 });
  run.selfDestructAt = 999_999;
  assert.deepStrictEqual(H.waveTick(run, 10 * 60_000), { wave: 9, count: 7 }, 'capped, plus two in the self-destruct');
});

test('each level of the facility adds a level of better loot below', () => {
  const { run } = setup({}, { security: 3, levels: 3 });
  assert.strictEqual(run.floors, 3);
  assert.strictEqual(run.layout.rooms.filter((r) => r.floor === 3).length, 16);
  const key = run.layout.containers.find((c) => run.boxes[c.id].items.some((it) => it.item === 'keycard'));
  assert.strictEqual(key.floor, 3, 'the keycard is on the deepest level');
  assert.ok(H.reachFloor(run, 2).ok);
  assert.match(H.reachFloor(run, 4).reason, /level/);
  assert.strictEqual(H.selfDestructSeconds(3), 160);
});

test('Heat rises with time and reported noise, rate-limited per kind', () => {
  const { run } = setup();
  H.report(run, 'gunshot', 0);
  H.report(run, 'gunshot', 100); // too soon: ignored
  H.report(run, 'spotted', 200);
  assert.strictEqual(run.heat, 13);
  H.heatTick(run, 60_000);
  assert.strictEqual(run.heat, 15);
  H.addHeat(run, 50);
  assert.strictEqual(H.HEAT_LEVELS[H.heatLevel(run.heat)].name, 'Lockdown');
});

test('boarding the ship needs the full countdown, before the self-destruct ends', () => {
  const { run } = setup();
  clearDefences(run);
  assert.ok(H.extractStart(run, 'ship', 0).ok);
  assert.match(H.extractFinish(run, 1000).reason, /countdown/);
  assert.ok(H.extractFinish(run, 3000).ok);
  run.selfDestructAt = 2000;
  assert.match(H.extractFinish(run, 3000).reason, /too late/);
});

test('the Builder loses only what a raider carries out; the rest goes back in the vault', () => {
  const { g, fac, run } = setup({ alloy: 10, drive: 2 });
  assert.deepStrictEqual(fac.escrow, { alloy: 6, drive: 2 }, '60% of each stack is exposed');
  assert.deepStrictEqual(fac.vault, { alloy: 4, drive: 0 });
  run.vaultOpen = true;
  const box = run.layout.containers.find((c) => c.type === 'vault' && run.boxes[c.id].items.some((it) => it.item === 'drive')).id;
  H.openContainer(run, box, 0);
  const drive = run.boxes[box].items.find((it) => it.item === 'drive');
  assert.ok(H.take(run, drive.uid, 'backpack', 60_000).ok);
  clearDefences(run);
  H.extractStart(run, 'ship', 300_000);
  assert.ok(H.extractFinish(run, 320_000).ok);
  const result = G.endRaid(g, run, 'extracted', 320_000);
  assert.deepStrictEqual(result.stolen, { drive: 1 });
  assert.deepStrictEqual(fac.vault, { alloy: 10, drive: 1 });
  assert.deepStrictEqual(g.pilots['Pilot A'].stash, [{ item: 'drive', qty: 1, fih: true }]);
  assert.ok(fac.cooldownUntil > 320_000, 'facility recovers before the next raid');
  assert.match(G.startRaid(g, 'Pilot B', run.planet, 0, 330_000, 1, 1).reason, /alert/);
});

test('dying keeps only the Secure Case', () => {
  const { g, run } = setup({ drive: 2 });
  run.vaultOpen = true;
  const box = run.layout.containers.find((c) => c.type === 'vault' && run.boxes[c.id].items.some((it) => it.item === 'drive')).id;
  H.openContainer(run, box, 0);
  const [d1, d2] = run.boxes[box].items.filter((it) => it.item === 'drive');
  H.take(run, d1.uid, 'secure', 60_000);
  if (d2) H.take(run, d2.uid, 'backpack', 60_000);
  const result = G.endRaid(g, run, 'killed', 70_000);
  assert.deepStrictEqual(result.kept.map((k) => k.item), ['drive']);
  assert.strictEqual(result.kept[0].fih, false);
  assert.deepStrictEqual(H.finish(run, 'destroyed', 70_000).kept.map((k) => k.item), ['drive'], 'same when the self-destruct gets you');
});

test('blueprint cases are too big to protect', () => {
  const { run } = setup({ blueprint: 1 });
  run.vaultOpen = true;
  const box = boxWith(run, 'blueprint');
  H.openContainer(run, box, 0);
  const bp = run.boxes[box].items.find((it) => it.item === 'blueprint');
  assert.match(H.take(run, bp.uid, 'secure', 60_000).reason, /Secure Case/);
  assert.ok(H.take(run, bp.uid, 'backpack', 60_000).ok);
});

test('facilities fill their vaults, ship to HQ and buy security', () => {
  const g = G.newGalaxy();
  g.buildSpeed = Infinity; // instant buildings: build times are tested in levels.test.js
  g.stock.metal = 999;
  g.credits = 5000;
  G.claimBase(g, 'Akane');
  const id = outpost(g, 'refinery').site.id;
  for (let i = 0; i < 15; i++) G.tick(g);
  const fac = G.facility(g, id, 0);
  assert.deepStrictEqual(fac.vault, { alloy: 15, isotope: 2 });
  assert.ok(G.ship(g, id, 0, 0).ok);
  assert.strictEqual(g.bases.Akane.stock.alloy, 15);
  assert.match(G.ship(g, id, 0, 1000).reason, /freighter/);
  assert.match(G.secure(g, id, 0).reason, /Design drive/);
  g.bases.Akane.stock.drive = 1;
  assert.ok(G.secure(g, id, 0).ok);
  assert.strictEqual(fac.security, 2);
});

// --- Combat: the landing pad, armour, the pouch, supplies and the launcher ----------------------

test('you pick where the ship drops you: off the site, out of turret reach, not too far out', () => {
  const { g } = setup({}, { inside: false });
  const run = G.startRaid(g, 'Pilot B', g.system.planets[1].id, 0, 0, 1, 1); // someone is inside already
  assert.match(run.reason, /already inside/);
  const L = H.generateLayout(3, 3, 'lab');
  const turret = L.pieces.find((p) => p.type === 'turret');
  assert.match(H.landingProblem(L, 0, 0), /site itself/);
  const near = [turret.pos[0] > 0 ? L.half + 6 : -L.half - 6, turret.pos[1]]; // just off the site, beside a turret
  assert.match(H.landingProblem(L, ...near), /turret/);
  assert.match(H.landingProblem(L, 200, 0), /too far/);
  const spot = landSpot(L);
  assert.strictEqual(H.landingProblem(L, ...spot), '');
  for (const p of L.pieces.filter((x) => x.type === 'turret')) assert.ok(Math.hypot(spot[0] - p.pos[0], spot[1] - p.pos[1]) >= H.TURRET_REACH + 5);
});

test('the ship leaves after the drop and comes back only when every outside defence is down', () => {
  const { run } = setup({}, { inside: false, security: 2 });
  assert.match(H.land(run, 50, 50, 0).reason, /already landed/);
  assert.strictEqual(H.stage(run, 0).ship, 'away');
  const defences = run.layout.pieces.filter((p) => H.DEFENCE_TYPES.includes(p.type));
  assert.ok(defences.some((p) => p.type === 'power') && defences.some((p) => p.type === 'guardpost') && defences.some((p) => p.ring), 'plants, guard posts and the core\'s turrets all count');
  assert.strictEqual(H.defencesLeft(run), defences.length);
  // Sneaking in by a vent doesn't bring the ship.
  H.ventStart(run, 'v0', 0);
  assert.ok(H.ventFinish(run, 6000).ok);
  assert.match(H.extractStart(run, 'ship', 7000).reason, /away.*defences/);
  assert.strictEqual(H.extractStates(run, 7000).ship.open, false);
  for (const p of defences.slice(1)) H.destroy(run, p.id, 8000);
  assert.strictEqual(H.defencesLeft(run), 1);
  assert.ok(!H.extractStart(run, 'ship', 8000).ok, 'one left is still too many');
  H.destroy(run, defences[0].id, 9000);
  assert.strictEqual(H.stage(run, 9000).ship, 'back');
  assert.ok(H.extractStart(run, 'ship', 9000).ok);
  assert.ok(H.extractFinish(run, 12_000).ok);
  // It comes back to a clear spot just south of the blast door.
  const [x, z] = run.layout.pad;
  assert.ok(z > run.layout.core / 2 && z <= run.layout.half + 8);
  for (const p of run.layout.pieces) assert.ok(Math.abs(x - p.pos[0]) > p.size[0] / 2 + 3 || Math.abs(z - p.pos[1]) > p.size[1] / 2 + 3, `pad on ${p.id}`);
  assert.deepStrictEqual(run.layout.extracts[0].pos, run.layout.pad);
  assert.strictEqual(H.selfDestructSeconds(1), 100);
});

test('every raid starts in a 50 vest; a found vest swaps on and keeps what armour it has', () => {
  const { run } = setup();
  assert.deepStrictEqual(run.vest, { item: 'vest50', armor: 50 });
  run.loose.lx = { id: 'lx', floor: 1, room: 100, pos: [0, 4.2], item: 'vest75', qty: 1, armor: 75 };
  assert.ok(H.pickUp(run, 'lx', 30).ok);
  assert.deepStrictEqual(run.vest, { item: 'vest75', armor: 75 });
  assert.deepStrictEqual([run.loose.lx.item, run.loose.lx.armor], ['vest50', 30], 'the old vest is left where the new one lay');
  assert.ok(H.pickUp(run, 'lx', 999).ok, 'swap back');
  assert.deepStrictEqual(run.vest, { item: 'vest50', armor: 30 });
  assert.deepStrictEqual([run.loose.lx.item, run.loose.lx.armor], ['vest75', 75], 'reported armour is capped at the vest');
  // From a cabinet: the old vest goes into the cabinet in its place.
  const c = run.layout.containers.find((x) => x.type !== 'vault');
  const box = run.boxes[c.id];
  box.items = [];
  box.grid = new H.Grid(3, 2);
  box.grid.place('v1', { x: 0, y: 0, w: 2, h: 2 });
  box.items.push({ uid: 'v1', item: 'vest100', qty: 1, vaultQty: 0, armor: 100 });
  H.openContainer(run, c.id, 0);
  assert.ok(H.take(run, 'v1', 'backpack', 10_000, 12).ok);
  assert.deepStrictEqual(run.vest, { item: 'vest100', armor: 100 });
  assert.deepStrictEqual(box.items.map((it) => [it.item, it.armor]), [['vest50', 12]]);
  assert.strictEqual(H.inventoryView(run).length, 0, 'vests are worn, never carried');
  assert.strictEqual(H.finish(run, 'extracted', 300_000).kept.length, 0, 'and they stay behind');
});

test('pouch items take their time, cancel for free, and never go past the cap', () => {
  const { run } = setup();
  assert.deepStrictEqual(run.pouch, H.STARTER_POUCH);
  assert.deepStrictEqual(H.STARTER_POUCH, { syringe: 2, medkit: 1, cell: 2, battery: 1 });
  const caps = Object.fromEntries(['syringe', 'medkit', 'cell', 'battery'].map((k) => [k, H.ITEMS[k].pouch.cap]));
  assert.deepStrictEqual(caps, { syringe: 4, medkit: 2, cell: 4, battery: 2 });
  assert.deepStrictEqual(['syringe', 'medkit', 'cell', 'battery'].map((k) => H.ITEMS[k].pouch.seconds), [5, 8, 3, 5]);

  assert.strictEqual(H.useStart(run, 'syringe', 10_000).seconds, 5);
  assert.match(H.useFinish(run, 12_000).reason, /not done/);
  H.useStop(run); // fired, sprinted or swapped
  assert.match(H.useFinish(run, 20_000).reason, /not using/);
  assert.strictEqual(run.pouch.syringe, 2, 'cancelling uses nothing');
  H.useStart(run, 'syringe', 20_000);
  assert.deepStrictEqual(H.useFinish(run, 25_000), { ok: true, item: 'syringe', health: 25, armor: 0 });
  assert.strictEqual(run.pouch.syringe, 1);
  H.useStart(run, 'battery', 30_000);
  assert.strictEqual(H.useFinish(run, 35_000).armor, 100);
  assert.strictEqual(run.pouch.battery, undefined);
  assert.match(H.useStart(run, 'battery', 40_000).reason, /no shield batter/);
  assert.match(H.useStart(run, 'scrap', 40_000).reason, /nothing/);

  // Found supplies fill the pouch up to the cap; the rest stays where it was.
  const c = run.layout.containers.find((x) => x.type !== 'vault');
  const box = run.boxes[c.id];
  box.items = [];
  box.grid = new H.Grid(3, 3);
  box.grid.place('s1', { x: 0, y: 0, w: 1, h: 1 });
  box.items.push({ uid: 's1', item: 'cell', qty: 4, vaultQty: 0 });
  H.openContainer(run, c.id, 0);
  assert.deepStrictEqual(H.take(run, 's1', 'backpack', 10_000), { ok: true, pouch: true, partial: true });
  assert.strictEqual(run.pouch.cell, 4);
  assert.strictEqual(box.items[0].qty, 2, 'two left in the container');
  assert.match(H.take(run, 's1', 'backpack', 10_000).reason, /no room in your pouch/);
  assert.strictEqual(H.inventoryView(run).length, 0, 'none of it went in the backpack');
  run.loose.ly = { id: 'ly', floor: 1, room: 100, pos: [0, 4.2], item: 'syringe', qty: 2 };
  assert.ok(H.pickUp(run, 'ly', 0).ok);
  assert.strictEqual(run.pouch.syringe, 3);
  assert.strictEqual(run.loose.ly, undefined);
});

test('you extract with your pouch and bring it next time; die and it is gone', () => {
  const { g, run } = setup();
  run.pouch = { syringe: 4, cell: 1 };
  G.endRaid(g, run, 'extracted', 300_000);
  assert.deepStrictEqual(g.pilots['Pilot A'].pouch, { syringe: 4, cell: 1 });
  const fac = G.facility(g, run.planet, 0);
  fac.cooldownUntil = 0;
  const next = G.startRaid(g, 'Pilot A', run.planet, 0, 400_000, 77, 78).run;
  assert.deepStrictEqual(next.pouch, { syringe: 4, cell: 1 }, 'saved with the account');
  G.endRaid(g, next, 'killed', 500_000);
  assert.deepStrictEqual(g.pilots['Pilot A'].pouch, {});
  fac.cooldownUntil = 0;
  assert.deepStrictEqual(G.startRaid(g, 'Pilot A', run.planet, 0, 600_000, 79, 80).run.pouch, H.STARTER_POUCH, 'an empty pouch gets the starter kit');
  assert.deepStrictEqual(H.startingPouch({ syringe: 9, medkit: 0.5, scrap: 3 }), { syringe: 4 }, 'saved counts are kept within the caps');
});

test('med cabinets in about one room in three, more on deeper levels, with supplies on the floors', () => {
  const byFloor = {};
  let vests = { 1: 0, deep: 0 };
  for (let seed = 1; seed <= 200; seed++) {
    const L = H.generateLayout(seed, 1, 'refinery', { floors: 4 });
    for (const fl of L.floors) {
      const rooms = L.rooms.filter((r) => r.floor === fl.n && r.id !== L.vault).length;
      const cabs = L.containers.filter((c) => c.type === 'medcab' && c.floor === fl.n);
      byFloor[fl.n] ||= { rooms: 0, cabs: 0 };
      byFloor[fl.n].rooms += rooms;
      byFloor[fl.n].cabs += cabs.length;
      assert.ok(cabs.every((c) => c.room !== L.vault && c.wall && Math.max(Math.abs(c.pos[0]), Math.abs(c.pos[1])) > 6.5), 'on a wall, never in the safe room');
      const loose = L.loose.filter((l) => l.floor === fl.n);
      assert.ok(loose.filter((l) => ['syringe', 'cell'].includes(l.item)).length >= 1, 'loose syringes or shield cells on every level');
      assert.ok(loose.every((l) => ['syringe', 'cell', 'vest75', 'vest100'].includes(l.item) && l.room !== L.vault));
      for (const l of loose) if (l.item.startsWith('vest')) vests[fl.n === 1 ? 1 : 'deep']++;
    }
  }
  const share = (n) => byFloor[n].cabs / byFloor[n].rooms;
  assert.ok(share(1) > 0.22 && share(1) < 0.4, `level 1: ${share(1)}`);
  assert.ok(share(4) > share(1) + 0.1, `deeper levels have more: ${share(4)} vs ${share(1)}`);
  assert.ok(vests.deep / 3 > vests[1] * 2, 'vests turn up mostly on the deeper levels');

  // What a cabinet holds: healing and sometimes a vest, never the keycard.
  const { run } = setup({}, { levels: 3, security: 2 });
  const cabs = run.layout.containers.filter((c) => c.type === 'medcab');
  assert.ok(cabs.length > 0);
  for (const c of cabs) assert.ok(run.boxes[c.id].items.every((it) => ['syringe', 'medkit', 'cell', 'battery', 'vest75', 'vest100'].includes(it.item)));
  let seen = new Set();
  const r = H.rng(5);
  for (let i = 0; i < 4000; i++) for (const s of H.rollTable({ rolls: [3, 3], none: 0.5, entries: [['syringe', 4, 1, 2], ['cell', 4, 1, 2], ['medkit', 2, 1, 1], ['battery', 2, 1, 1], ['vest75', 0.5, 1, 1], ['vest100', 0.15, 1, 1]] }, 3, 'material', r)) seen.add(s.item);
  assert.ok(seen.has('vest75') && seen.has('vest100'));
});

test('the grenade launcher has seven rounds for the whole raid, a second apart', () => {
  const { run } = setup();
  assert.strictEqual(run.grenades, 7);
  let t = 10_000;
  for (let i = 6; i >= 0; i--) {
    assert.deepStrictEqual([H.fireGrenade(run, t).ok, run.grenades], [true, i]);
    if (i === 6) assert.match(H.fireGrenade(run, t + 300).reason, /cycling/);
    t += 1000;
  }
  assert.match(H.fireGrenade(run, t).reason, /empty/);
  assert.strictEqual(run.heat, 7 * H.GRENADE_HEAT, 'every burst is loud');
});

// --- Over the wire ---------------------------------------------------------------------------

function connect(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    const inbox = [];
    const waiters = [];
    ws.on('message', (data) => {
      const msg = JSON.parse(data);
      const i = waiters.findIndex((w) => w.match(msg));
      if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
      else inbox.push(msg);
    });
    ws.on('open', () =>
      resolve({
        send: (msg) => ws.send(JSON.stringify(msg)),
        next(match) {
          const i = inbox.findIndex(match);
          if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
          return new Promise((res) => waiters.push({ match, resolve: res }));
        },
        close: () => ws.close(),
      })
    );
    ws.on('error', reject);
  });
}

test('a raid over the wire: board, search, steal from the vault, alarm, extract', async () => {
  const port = 18090;
  let clock = 1_000_000;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000, now: () => clock });
  try {
    const phone = await connect(port);
    const pc = await connect(port);
    phone.send({ type: 'hello', role: 'builder', name: 'Akane' });
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await phone.next((m) => m.type === 'welcome');
    await pc.next((m) => m.type === 'welcome');

    phone.send({ type: 'choose_faction', faction: 'compact' });
    pc.send({ type: 'choose_faction', faction: 'ashen' });
    await phone.next((m) => m.type === 'state' && m.state.pilots['Pilot A']?.faction === 'ashen' && m.state.bases.Akane.faction === 'compact');
    G.setCommandLevel(server.galaxy, 'aster', 2); // outposts open at level 2
    phone.send({ type: 'found_site', facility: 'refinery', planet: 'cinder', sector: 'cinder-1' });
    await phone.next((m) => m.type === 'state' && m.state.system.planets.length === 2);
    const site = server.galaxy.system.planets[1].id;
    server.galaxy.system.planets[1].buildings[0].vault = { isotope: 5 };
    server.galaxy.system.planets[1].pieces = DEFENCES.map((p) => ({ ...p })); // as if the Builder placed them

    pc.send({ type: 'raid_start', planet: site, slot: 0 });
    const begin = await pc.next((m) => m.type === 'raid' && m.ev === 'begin');
    assert.ok(begin.run.layout.rooms.length >= 9);
    assert.ok(!JSON.stringify(begin).includes('"isotope"'), 'no container contents in the briefing');
    assert.strictEqual(begin.run.stage, 'breach');
    assert.strictEqual(begin.run.ship, 'carrying');
    await phone.next((m) => m.type === 'state' && m.state.raids.length === 1);
    pc.send({ type: 'raid_land', x: 0, z: 0 });
    await pc.next((m) => m.type === 'error' && /site itself/.test(m.reason));
    pc.send({ type: 'raid_land', x: landSpot(begin.run.layout)[0], z: landSpot(begin.run.layout)[1] });
    await pc.next((m) => m.type === 'raid' && m.ev === 'landed');

    // Stage 1: knock out the power plant and walk in through the blast door.
    pc.send({ type: 'raid_enter' });
    await pc.next((m) => m.type === 'error' && /sealed/.test(m.reason));
    const power = begin.run.layout.pieces.find((p) => p.type === 'power');
    pc.send({ type: 'raid_destroy', piece: power.id });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.doorOpen);
    pc.send({ type: 'raid_enter' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.stage === 'loot');
    clock += 61_000;
    const wave = await pc.next((m) => m.type === 'raid' && m.ev === 'wave');
    assert.strictEqual(wave.count, 1);

    // Find the keycard the way a player would: open containers until one shows it.
    const run = server.runs.get('Pilot A');
    const cid = Object.entries(run.boxes).find(([, b]) => b.items.some((it) => it.item === 'keycard'))[0];
    pc.send({ type: 'raid_open', container: cid });
    const view = await pc.next((m) => m.type === 'raid' && m.ev === 'container');
    assert.ok(view.slots.every((s) => !s.item), 'placeholders only');
    clock += 30_000;
    const card = await pc.next((m) => m.type === 'raid' && m.ev === 'reveal' && m.item.item === 'keycard');
    pc.send({ type: 'raid_take', uid: card.item.uid, to: 'backpack' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'inventory' && m.items.length === 1);

    pc.send({ type: 'raid_keycard' });
    const opened = await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.vaultOpen);
    assert.strictEqual(opened.stage, 'escape');
    assert.ok(opened.selfDestruct > 60_000, 'the self-destruct is counting down');
    const vault = run.layout.containers.find((c) => c.type === 'vault' && run.boxes[c.id].items.some((it) => it.item === 'isotope')).id;
    pc.send({ type: 'raid_open', container: vault });
    await pc.next((m) => m.type === 'raid' && m.ev === 'container' && m.container === vault);
    clock += 30_000;
    const iso = await pc.next((m) => m.type === 'raid' && m.ev === 'reveal' && m.item.item === 'isotope');
    pc.send({ type: 'raid_take', uid: iso.item.uid, to: 'backpack' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'inventory' && m.items.length === 2);

    // The Builder hears about it and sounds the alarm from the phone.
    phone.send({ type: 'sound_alarm', planet: site, slot: 0 });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.heat >= 25);
    await phone.next((m) => m.type === 'state' && m.state.raids[0]?.heat >= 25);

    clock += 10_000;
    pc.send({ type: 'raid_extract_start', extract: 'ship' });
    await pc.next((m) => m.type === 'error' && /away/.test(m.reason));
    for (const p of begin.run.layout.pieces) if (H.DEFENCE_TYPES.includes(p.type) && p.id !== power.id) pc.send({ type: 'raid_destroy', piece: p.id });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.ship === 'back' && m.extracts.ship.open);
    pc.send({ type: 'raid_extract_start', extract: 'ship' });
    const ex = await pc.next((m) => m.type === 'raid' && m.ev === 'extracting');
    clock += ex.countdown * 1000;
    pc.send({ type: 'raid_extract_finish' });
    const end = await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.strictEqual(end.result.outcome, 'extracted');
    assert.ok(end.result.kept.some((k) => k.item === 'isotope'));

    const after = await phone.next((m) => m.type === 'state' && m.state.raids.length === 0 && m.state.raidLog.length > 0);
    const fac = after.state.system.planets[1].buildings[0];
    assert.ok(fac.vault.isotope < 5, 'the Builder lost what was carried out');
    assert.strictEqual(after.state.raidLog[0].outcome, 'extracted');

    server.galaxy.bases.Akane.stock.metal = 100;
    phone.send({ type: 'build', planet: 'aster', slot: 0, building: 'spaceport' });
    await pc.next((m) => m.type === 'state' && m.state.system.planets[0].buildings.length === 1);
    pc.send({ type: 'sell' });
    const sold = await pc.next((m) => m.type === 'state' && m.state.pilots['Pilot A']?.credits > 0);
    assert.strictEqual(sold.state.pilots['Pilot A'].stash.length, 0);

    for (const c of [phone, pc]) c.close();
  } finally {
    await server.close();
  }
});

test('the run clock ends a raid as missing in action', async () => {
  const port = 18091;
  let clock = 0;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000, now: () => clock });
  try {
    const pc = await connect(port);
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await pc.next((m) => m.type === 'welcome');
    server.galaxy.stock.metal = 999;
    G.claimBase(server.galaxy, 'Akane');
    const { site } = outpost(server.galaxy, 'spire');
    pc.send({ type: 'raid_start', planet: site.id, slot: 0 });
    await pc.next((m) => m.type === 'raid' && m.ev === 'begin');
    clock += 17 * 60_000;
    const end = await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.strictEqual(end.result.outcome, 'mia');
    pc.close();
  } finally {
    await server.close();
  }
});

test('the self-destruct kills a raider still inside when it ends', async () => {
  const port = 18092;
  let clock = 0;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000, now: () => clock });
  try {
    const pc = await connect(port);
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await pc.next((m) => m.type === 'welcome');
    G.claimBase(server.galaxy, 'Akane');
    const { site } = outpost(server.galaxy, 'refinery');
    pc.send({ type: 'raid_start', planet: site.id, slot: 0 });
    await pc.next((m) => m.type === 'raid' && m.ev === 'begin');
    pc.send({ type: 'raid_vent_start', vent: 'v2' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'vent');
    clock += 6000;
    pc.send({ type: 'raid_vent_finish' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.breached === 'vent');
    pc.send({ type: 'raid_drill_start' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'drill');
    clock += 30_000;
    pc.send({ type: 'raid_drill_finish' });
    const open = await pc.next((m) => m.type === 'raid' && m.ev === 'heat' && m.vaultOpen);
    clock += open.selfDestruct;
    const end = await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.strictEqual(end.result.outcome, 'destroyed');
    assert.match(server.galaxy.feed.at(-1).text, /self-destruct/);
    pc.close();
  } finally {
    await server.close();
  }
});

test('healing over the wire: the server counts, the app waits for the timer', async () => {
  const port = 18093;
  let clock = 0;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000, now: () => clock });
  try {
    const pc = await connect(port);
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await pc.next((m) => m.type === 'welcome');
    G.claimBase(server.galaxy, 'Akane');
    const { site } = outpost(server.galaxy, 'refinery');
    pc.send({ type: 'raid_start', planet: site.id, slot: 0 });
    const begin = await pc.next((m) => m.type === 'raid' && m.ev === 'begin');
    assert.deepStrictEqual(begin.run.pouch, H.STARTER_POUCH, 'a new raider gets the starter kit');
    assert.deepStrictEqual(begin.run.vest, { item: 'vest50', armor: 50 });
    assert.strictEqual(begin.run.grenades, 7);
    assert.ok(Array.isArray(begin.run.loose) && begin.run.loose.length > 0);

    pc.send({ type: 'raid_use_start', item: 'cell' });
    const using = await pc.next((m) => m.type === 'raid' && m.ev === 'using');
    assert.strictEqual(using.seconds, 3);
    clock += 1000;
    pc.send({ type: 'raid_use_finish' });
    await pc.next((m) => m.type === 'error' && /not done/.test(m.reason));
    clock += 2000;
    pc.send({ type: 'raid_use_finish' });
    const used = await pc.next((m) => m.type === 'raid' && m.ev === 'used');
    assert.deepStrictEqual([used.item, used.armor], ['cell', 25]);
    const pouch = await pc.next((m) => m.type === 'raid' && m.ev === 'pouch');
    assert.strictEqual(pouch.pouch.cell, 1);

    pc.send({ type: 'raid_grenade' });
    const after = await pc.next((m) => m.type === 'raid' && m.ev === 'pouch' && m.grenades === 6);
    assert.ok(after);
    pc.send({ type: 'raid_died' });
    await pc.next((m) => m.type === 'raid' && m.ev === 'end');
    assert.deepStrictEqual(server.galaxy.pilots['Pilot A'].pouch, {}, 'dying loses the pouch');
    pc.close();
  } finally {
    await server.close();
  }
});
