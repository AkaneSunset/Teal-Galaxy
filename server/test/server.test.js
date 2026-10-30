// Plays the prototype's "done when" loop end to end: a builder and two pilots over real WebSockets.

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('crypto');
const WebSocket = require('ws');
const G = require('../galaxy');
const { startServer, adminCheck } = require('../server');

// An app's connection. `raw` keeps every message as it came over the wire.
function connect(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    const inbox = [];
    const waiters = [];
    const raw = [];
    ws.on('message', (data) => {
      raw.push(String(data));
      const msg = JSON.parse(data);
      const i = waiters.findIndex((w) => w.match(msg));
      if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
      else inbox.push(msg);
    });
    ws.on('open', () =>
      resolve({
        raw,
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

const isState = (pred) => (m) => m.type === 'state' && pred(m.state);

test('builder and two pilots complete the ice job', async () => {
  const port = 18080;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000 });
  try {
    const phone = await connect(port);
    const pc1 = await connect(port);
    const pc2 = await connect(port);
    phone.send({ type: 'hello', role: 'builder', name: 'Akane' });
    pc1.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    pc2.send({ type: 'hello', role: 'explorer', name: 'Pilot B' });
    await phone.next((m) => m.type === 'welcome');
    await pc1.next((m) => m.type === 'welcome');
    await pc2.next((m) => m.type === 'welcome');

    // Posting a job before a Spaceport exists is refused.
    phone.send({ type: 'post_job', resource: 'ice', amount: 10, reward: 100 });
    assert.match((await phone.next((m) => m.type === 'error')).reason, /Star Port/);

    // Phone builds a Spaceport; both PCs see it appear.
    phone.send({ type: 'build', planet: 'aster', slot: 0, building: 'spaceport' });
    const hasPort = (s) => s.system.planets[0].buildings.some((b) => b.type === 'spaceport');
    await pc1.next(isState(hasPort));
    await pc2.next(isState(hasPort));

    // Phone posts the ice job; pilots see it.
    phone.send({ type: 'post_job', resource: 'ice', amount: 10, reward: 100 });
    await pc1.next(isState((s) => s.jobs.length === 1));

    // Pilots see each other's ships.
    pc1.send({ type: 'ship', pos: [1, 2, 3], rot: [0, 0, 0] });
    const ship = await pc2.next((m) => m.type === 'ship');
    assert.deepStrictEqual(ship.pos, [1, 2, 3]);
    assert.strictEqual(ship.name, 'Pilot A');

    // Pilot A mines 6 ice, Pilot B mines 4, both deliver.
    for (let i = 0; i < 2; i++) pc1.send({ type: 'collect', resource: 'ice', amount: 3 });
    for (let i = 0; i < 2; i++) pc2.send({ type: 'collect', resource: 'ice', amount: 2 });
    await pc2.next(isState((s) => s.pilots['Pilot B']?.cargo.ice === 4));
    pc1.send({ type: 'deliver', job: 1 });
    await phone.next(isState((s) => s.jobs[0]?.delivered === 6));
    pc2.send({ type: 'deliver', job: 1 });

    // Phone sees the job complete, ice in stock, and Hydroponics unlocked.
    const done = await phone.next(isState((s) => s.jobs[0]?.status === 'done'));
    assert.strictEqual(done.state.stock.ice, 10);
    assert.ok(done.state.unlocked.includes('hydroponics'));
    assert.strictEqual(done.state.pilots['Pilot A'].credits, 60);
    assert.strictEqual(done.state.pilots['Pilot B'].credits, 40);

    for (const c of [phone, pc1, pc2]) c.close();
  } finally {
    await server.close();
  }
});

test('chat reaches every app, trimmed and rate-limited', async () => {
  const port = 18081;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000 });
  try {
    const phone = await connect(port);
    const pc = await connect(port);
    phone.send({ type: 'hello', role: 'builder', name: 'Akane' });
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await phone.next((m) => m.type === 'welcome');
    await pc.next((m) => m.type === 'welcome');

    pc.send({ type: 'chat', text: '  on my   way to the port  ' });
    const heard = await phone.next((m) => m.type === 'chat');
    assert.deepStrictEqual(heard, { type: 'chat', name: 'Pilot A', role: 'explorer', text: 'on my way to the port' });
    assert.strictEqual((await pc.next((m) => m.type === 'chat')).text, 'on my way to the port');

    pc.send({ type: 'chat', text: 'too fast' });
    assert.match((await pc.next((m) => m.type === 'error')).reason, /slow down/);

    for (const c of [phone, pc]) c.close();
  } finally {
    await server.close();
  }
});

test('the faction war over the wire: factions, outposts, fleets, the dock, contracts, donations, demo capture', async () => {
  const port = 18082;
  let clock = 1_000_000;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000, demo: true, now: () => clock });
  const W = require('../war');
  const isError = (re) => (m) => m.type === 'error' && re.test(m.reason);
  try {
    const akane = await connect(port);
    const rin = await connect(port);
    const pilotA = await connect(port);
    const pilotB = await connect(port);
    akane.send({ type: 'hello', role: 'builder', name: 'Akane' });
    const welcome = await akane.next((m) => m.type === 'welcome');
    rin.send({ type: 'hello', role: 'builder', name: 'Rin' });
    await rin.next((m) => m.type === 'welcome');
    pilotA.send({ type: 'hello', role: 'explorer', name: 'Pilot A' });
    await pilotA.next((m) => m.type === 'welcome');
    pilotB.send({ type: 'hello', role: 'explorer', name: 'Pilot B' });
    await pilotB.next((m) => m.type === 'welcome');
    for (const name of ['Akane', 'Rin']) G.setCommandLevel(server.galaxy, G.claimBase(server.galaxy, name).id, 5); // everything open

    // The catalog carries the war's rules; the old fleet attacks are gone.
    const cat = welcome.catalog;
    assert.deepStrictEqual(Object.keys(cat.factions), ['compact', 'ashen', 'luminar', 'coma']);
    assert.strictEqual(cat.factions.ashen.name, 'Ashen Collective');
    assert.deepStrictEqual(Object.values(cat.factions).map((f) => f.playable), [true, true, true, false], 'players pick from three');
    assert.deepStrictEqual(cat.director, { ms: 300_000, scaleMax: 2, patrolPower: 30, armadaCap: 600, activeMs: 24 * 3600_000 });
    assert.strictEqual(welcome.admin, false, 'no ADMIN_KEY: nobody is an admin');
    assert.strictEqual(welcome.state.director, undefined);
    assert.deepStrictEqual(cat.ranks.map((r) => r.name), ['Recruit', 'Supplier', 'Quartermaster', 'Provisioner', 'War Industrialist']);
    assert.deepStrictEqual(cat.outposts, { max: 5, perSector: 3 });
    assert.deepStrictEqual(cat.war, { lockMs: 7 * 24 * 3600_000, carrierShare: 0.25, battleMs: 120_000, upkeepMs: 600_000, upkeep: { corvette: 1, frigate: 2, destroyer: 4 }, fuelCredits: 20, planetShare: 0.75, sectorPilots: 32 });
    assert.ok(cat.contractItems.includes('fuel') && cat.contractItems.includes('metal') && !cat.contractItems.includes('drive'));
    assert.strictEqual(cat.meritValue.ice, 3);
    assert.strictEqual(cat.demo, true);
    assert.strictEqual(cat.attack, undefined);
    assert.strictEqual(cat.facilities.fuel.name, 'Fuel Depot');
    assert.strictEqual(cat.buildings.dock.name, 'Carrier Dock');
    assert.strictEqual(cat.sites.max, 5);
    assert.strictEqual(welcome.state.war.planets.find((p) => p.id === 'cinder').owner, 'compact');

    // Factions: once per character.
    akane.send({ type: 'found_site', facility: 'fuel', planet: 'cinder', sector: 'cinder-2' });
    await akane.next(isError(/choose a faction first/));
    akane.send({ type: 'choose_faction', faction: 'compact' });
    await pilotA.next(isState((s) => s.bases.Akane.faction === 'compact'));
    akane.send({ type: 'choose_faction', faction: 'ashen' });
    await akane.next(isError(/already set/));
    rin.send({ type: 'choose_faction', faction: 'ashen' });
    pilotA.send({ type: 'choose_faction', faction: 'compact' });
    pilotB.send({ type: 'choose_faction', faction: 'ashen' });
    await akane.next(isState((s) => s.bases.Rin.faction === 'ashen' && s.pilots['Pilot A']?.faction === 'compact' && s.pilots['Pilot B']?.faction === 'ashen'));

    // Outposts, Builders only.
    pilotA.send({ type: 'found_site', facility: 'fuel', planet: 'cinder', sector: 'cinder-2' });
    await pilotA.next(isError(/only Builders found outposts/));
    akane.send({ type: 'found_site', facility: 'fuel', planet: 'vesper', sector: 'vesper-2' });
    await akane.next(isError(/doesn't hold Vesper/));
    akane.send({ type: 'found_site', facility: 'fuel', planet: 'cinder', sector: 'cinder-2' });
    const founded = await pilotB.next(isState((s) => s.system.planets.some((p) => p.sector === 'cinder-2')));
    const outpost = founded.state.system.planets.find((p) => p.sector === 'cinder-2');
    assert.deepStrictEqual([outpost.id, outpost.parent, outpost.faction, outpost.dormant, outpost.name], ['cinder-op-1', 'cinder', 'compact', false, 'Cinder 2 Fuel Depot']);

    // The old attacks answer with where fleets go now.
    akane.send({ type: 'launch_attack', target: outpost.id });
    assert.strictEqual((await akane.next((m) => m.type === 'error')).reason, 'fleets fight for control of systems now: send them from the War map');

    // Fleets: send, recall.
    akane.send({ type: 'send_fleet', system: 'teal-prime' });
    await akane.next(isError(/no ships to send/));
    server.galaxy.bases.Akane.navy.corvette = 2;
    akane.send({ type: 'send_fleet', system: 'fortitude', ships: { corvette: 1 } });
    await akane.next(isError(/capital systems/));
    akane.send({ type: 'send_fleet', system: 'teal-prime', ships: { corvette: 1 } });
    const sent = await rin.next(isState((s) => s.war.fleets.length === 1));
    const fleet = sent.state.war.fleets[0];
    assert.deepStrictEqual([fleet.owner, fleet.faction, fleet.system, fleet.status, fleet.ships], ['Akane', 'compact', 'teal-prime', 'flying', { corvette: 1 }]);
    akane.send({ type: 'recall_fleet', fleet: fleet.id });
    await rin.next(isState((s) => s.war.fleets[0]?.status === 'returning'));
    pilotA.send({ type: 'send_fleet', system: 'teal-prime' });
    await pilotA.next(isError(/only Builders command fleets/));

    // Demo capture: a pilot takes a sector for their faction, with the war's rules.
    pilotB.send({ type: 'demo_capture', planet: 'cinder', sector: 'cinder-1' });
    await pilotB.next(isError(/25% orbital control of Teal Prime: you have 0%/));
    server.galaxy.bases.Rin.navy.frigate = 1;
    rin.send({ type: 'send_fleet', system: 'teal-prime' });
    await rin.next(isState((s) => s.war.fleets.some((f) => f.owner === 'Rin')));
    clock += 60_000;
    W.warTick(server.galaxy, clock); // as the server's tick would
    pilotB.send({ type: 'demo_capture', planet: 'cinder', sector: 'cinder-1' });
    const taken = await akane.next(isState((s) => s.war.planets.find((p) => p.id === 'cinder').sectors[0].owner === 'ashen'));
    assert.strictEqual(taken.state.war.planets.find((p) => p.id === 'cinder').owner, null);
    assert.strictEqual(taken.state.system.planets.find((p) => p.id === outpost.id).dormant, true);
    assert.match(taken.state.bases.Akane.alerts.at(-1).text, /Cinder 1 fell to the Ashen Collective/);
    akane.send({ type: 'demo_capture', planet: 'cinder', sector: 'cinder-1' });
    await akane.next(isError(/only pilots take sectors/));

    // The Carrier Dock market.
    akane.send({ type: 'set_price', item: 'fuel', price: 12 });
    await akane.next(isError(/build a Carrier Dock first/));
    akane.send({ type: 'build', planet: 'aster', slot: 0, building: 'spaceport' });
    akane.send({ type: 'build', planet: 'aster', slot: 7, building: 'dock' });
    await rin.next(isState((s) => s.system.planets[0].buildings.some((b) => b.type === 'dock')));
    server.galaxy.bases.Akane.stock.fuel = 30;
    akane.send({ type: 'set_price', item: 'fuel', price: 12 });
    await pilotA.next(isState((s) => s.bases.Akane.market?.fuel === 12));
    pilotB.send({ type: 'dock_buy', builder: 'Akane', item: 'fuel', qty: 5 });
    await pilotB.next(isError(/only trades with the Terran Compact/));
    server.galaxy.pilots['Pilot A'].credits = 500;
    pilotA.send({ type: 'dock_buy', builder: 'Akane', item: 'fuel', qty: 10 });
    const bought = await pilotA.next(isState((s) => s.pilots['Pilot A']?.hold?.fuel === 10));
    assert.strictEqual(bought.state.pilots['Pilot A'].credits, 380);
    assert.strictEqual(bought.state.bases.Akane.stock.fuel, 20);
    akane.send({ type: 'dock_buy', builder: 'Akane', item: 'fuel', qty: 1 });
    await akane.next(isError(/only pilots buy at a Carrier Dock/));

    // Supply contracts.
    pilotA.send({ type: 'post_contract', item: 'alloy', amount: 5, reward: 50 });
    const posted = await akane.next(isState((s) => s.contracts.length === 1));
    const contract = posted.state.contracts[0];
    assert.deepStrictEqual([contract.pilot, contract.faction, contract.item, contract.amount, contract.reward, contract.status], ['Pilot A', 'compact', 'alloy', 5, 50, 'open']);
    rin.send({ type: 'fill_contract', contract: contract.id, qty: 5 });
    await rin.next(isError(/that contract is for the Terran Compact/));
    akane.send({ type: 'fill_contract', contract: contract.id, qty: 5 });
    const filled = await pilotA.next(isState((s) => s.contracts[0]?.status === 'done'));
    assert.strictEqual(filled.state.pilots['Pilot A'].hold.alloy, 5);
    pilotA.send({ type: 'post_contract', item: 'fuel', amount: 10, reward: 30 });
    await pilotA.next(isState((s) => s.contracts.length === 2));
    pilotA.send({ type: 'cancel_contract', contract: 2 });
    const cancelled = await pilotA.next(isState((s) => s.contracts[1]?.status === 'cancelled'));
    assert.strictEqual(cancelled.state.pilots['Pilot A'].credits, 330, 'the reward came back');

    // Donations to the war supply.
    akane.send({ type: 'donate', item: 'metal', qty: 300 });
    const donated = await rin.next(isState((s) => s.war.supply['teal-prime'].compact.metal === 300));
    assert.strictEqual(donated.state.bases.Akane.merit, 600);

    for (const c of [akane, rin, pilotA, pilotB]) c.close();
  } finally {
    await server.close();
  }
});

test('demo capture is refused unless the server runs in demo mode', async () => {
  const port = 18083;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000 });
  try {
    const pc = await connect(port);
    pc.send({ type: 'hello', role: 'explorer', name: 'Pilot A', admin_key: '' });
    const welcome = await pc.next((m) => m.type === 'welcome');
    assert.strictEqual(welcome.catalog.demo, false);
    assert.strictEqual(welcome.admin, false);
    pc.send({ type: 'choose_faction', faction: 'ashen' });
    await pc.next(isState((s) => s.pilots['Pilot A']?.faction === 'ashen'));
    pc.send({ type: 'demo_capture', planet: 'cinder', sector: 'cinder-1' });
    assert.match((await pc.next((m) => m.type === 'error')).reason, /only for demo mode/);
    pc.close();
  } finally {
    await server.close();
  }
});

test('the admin key check: constant-time on equal lengths, any other length never matches, no key no admins', () => {
  const real = crypto.timingSafeEqual;
  let calls = 0;
  crypto.timingSafeEqual = (a, b) => {
    calls += 1;
    return real(a, b);
  };
  try {
    const check = adminCheck('sesame');
    assert.strictEqual(check('sesame'), true);
    assert.strictEqual(check('sesamf'), false);
    assert.strictEqual(calls, 2, 'keys of the right length are compared in constant time');
    for (const key of ['sesame!', 'ses', '', undefined, null, 42, ['sesame']]) assert.strictEqual(check(key), false, String(key));
    assert.strictEqual(calls, 2, 'anything else never gets that far');
    for (const unset of [null, undefined, '']) for (const key of ['', 'anything']) assert.strictEqual(adminCheck(unset)(key), false);
  } finally {
    crypto.timingSafeEqual = real;
  }
});

test('admins over the wire: the key, Coma characters, the director and armadas, and what players see', async () => {
  const port = 18084;
  const KEY = 'teal-sesame-42';
  let clock = 1_000_000;
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000, now: () => clock, adminKey: KEY });
  const W = require('../war');
  const error = (c) => c.next((m) => m.type === 'error').then((m) => m.reason);
  try {
    const admin = await connect(port);
    const wrong = await connect(port);
    const short = await connect(port);
    const none = await connect(port);
    admin.send({ type: 'hello', role: 'builder', name: 'Akane', admin_key: KEY });
    wrong.send({ type: 'hello', role: 'builder', name: 'Rin', admin_key: 'teal-sesame-43' });
    short.send({ type: 'hello', role: 'explorer', name: 'Pilot A', admin_key: 'teal' });
    none.send({ type: 'hello', role: 'explorer', name: 'Pilot B' });
    const welcomes = await Promise.all([admin, wrong, short, none].map((c) => c.next((m) => m.type === 'welcome')));
    assert.deepStrictEqual(welcomes.map((w) => w.admin), [true, false, false, false], 'the right key, a wrong one, a short one, none');
    assert.deepStrictEqual(Object.keys(welcomes[0].state.director), ['paused', 'scale', 'overrides', 'posture', 'strength', 'auto', 'intensity', 'runAt']);
    for (const w of welcomes.slice(1)) assert.strictEqual(w.state.director, undefined, 'the director is for admins only');
    assert.strictEqual(server.galaxy.bases.Akane.seenAt, clock, 'seen on hello');

    // Admin messages from players.
    const asks = [['director_set', { scale: 2 }], ['admin_armada', { system: 'teal-prime', power: 50 }], ['admin_recall', { fleet: 1 }], ['admin_capture', { planet: 'cinder', sector: 'cinder-1' }]];
    for (const [type, fields] of asks) {
      for (const c of [wrong, none]) {
        c.send({ type, ...fields });
        assert.strictEqual(await error(c), 'admins only', type);
      }
    }
    assert.strictEqual(server.galaxy.director.scale, 1);
    assert.ok(!server.galaxy.war.fleets.length);

    // The Coma Conglomerate: not for players; admins may play it, as Builder or pilot.
    none.send({ type: 'choose_faction', faction: 'coma' });
    assert.strictEqual(await error(none), "the Coma Conglomerate isn't open to players");
    clock += 1000;
    admin.send({ type: 'choose_faction', faction: 'coma' });
    await wrong.next(isState((s) => s.bases.Akane.faction === 'coma'));
    assert.strictEqual(server.galaxy.bases.Akane.seenAt, clock, 'seen on every message');
    const kuro = await connect(port);
    kuro.send({ type: 'hello', role: 'explorer', name: 'Kuro', admin_key: KEY });
    await kuro.next((m) => m.type === 'welcome');
    kuro.send({ type: 'choose_faction', faction: 'coma' });
    await none.next(isState((s) => s.pilots.Kuro?.faction === 'coma'));
    // Names are not passwords: those characters need the key.
    const thief = await connect(port);
    for (const [role, name] of [['builder', 'Akane'], ['explorer', 'Kuro']]) {
      for (const key of [undefined, 'teal-sesame-43']) {
        thief.send({ type: 'hello', role, name, admin_key: key });
        assert.strictEqual(await error(thief), 'that character plays for the Coma Conglomerate: admins only');
      }
    }
    thief.send({ type: 'send_fleet', system: 'teal-prime' });
    assert.strictEqual(await error(thief), 'say hello first', 'a refused hello gives no role');
    thief.send({ type: 'hello', role: 'explorer', name: 'Akane' });
    assert.strictEqual((await thief.next((m) => m.type === 'welcome')).admin, false, "Akane's pilot is someone else");

    // director_set: checked, applied, and the director takes its turn at once.
    admin.send({ type: 'director_set', scale: 5 });
    assert.strictEqual(await error(admin), 'the scale runs from 0 to 2');
    admin.send({ type: 'director_set', posture: { fortitude: 'hold' } });
    assert.strictEqual(await error(admin), "capital systems can't be contested");
    admin.send({ type: 'director_set', posture: { drift: 'hold' }, overrides: { ashen: 0.5 } });
    const set = await admin.next(isState((s) => s.director.posture.drift === 'hold'));
    assert.strictEqual(set.state.director.intensity.ashen, 0.5);
    assert.strictEqual(set.state.director.runAt, clock + 300_000);
    const patrols = set.state.war.fleets.filter((f) => f.ai);
    assert.deepStrictEqual(patrols.map((f) => f.system), ['teal-prime', 'marrow'], 'patrols, but none to The Drift on hold');
    const seen = await none.next(isState((s) => s.war.fleets.length === patrols.length));
    assert.strictEqual(seen.state.director, undefined);
    assert.deepStrictEqual(seen.state.war.fleets, patrols, 'players see the armadas like any fleet');
    assert.ok(seen.state.war.log.some((l) => /^A Coma armada of .* is heading for Teal Prime$/.test(l.text)));

    // An admin's own armada: players see it, but not that an admin sent it.
    admin.send({ type: 'admin_armada', system: 'marrow', power: 5 });
    assert.strictEqual(await error(admin), "an armada's power is 10 to 400");
    admin.send({ type: 'admin_armada', system: 'marrow', power: 50 });
    const sent = await admin.next(isState((s) => s.war.fleets.some((f) => f.manual)));
    const manual = sent.state.war.fleets.find((f) => f.manual);
    assert.deepStrictEqual([manual.ai, manual.owner, manual.faction, manual.ships], [true, null, 'coma', { destroyer: 1, frigate: 2, corvette: 1 }]);
    const theirs = (await none.next(isState((s) => s.war.fleets.some((f) => f.id === manual.id)))).state.war.fleets.find((f) => f.id === manual.id);
    assert.ok(!('manual' in theirs));
    assert.deepStrictEqual(theirs, Object.fromEntries(Object.entries(manual).filter(([k]) => k !== 'manual')), 'the rest of it, as it is');
    assert.strictEqual(server.galaxy.war.fleets.find((f) => f.id === manual.id).manual, true, 'the galaxy itself keeps it');
    const kuroSaw = await kuro.next(isState((s) => s.war.fleets.some((f) => f.id === manual.id)));
    assert.ok(kuroSaw.state.director && kuroSaw.state.war.fleets.find((f) => f.id === manual.id).manual, 'an admin pilot sees it all too');

    // admin_recall.
    admin.send({ type: 'admin_recall', fleet: manual.id });
    await none.next(isState((s) => s.war.fleets.find((f) => f.id === manual.id)?.status === 'returning'));
    admin.send({ type: 'admin_recall', fleet: manual.id });
    assert.strictEqual(await error(admin), 'that armada is already on its way home');

    // admin_capture: every rule of the war, and no demo mode needed.
    admin.send({ type: 'admin_capture', planet: 'bastion', sector: 'bastion-1' });
    assert.strictEqual(await error(admin), "capital worlds can't be attacked");
    admin.send({ type: 'admin_capture', planet: 'cinder', sector: 'cinder-1' });
    assert.strictEqual(await error(admin), 'you need 25% orbital control of Teal Prime: you have 0%', 'the patrol is still on its way');
    clock += 200_000;
    W.warTick(server.galaxy, clock); // as the server's tick would: the patrol is in orbit
    admin.send({ type: 'admin_capture', planet: 'cinder', sector: 'cinder-1' });
    const taken = await none.next(isState((s) => s.war.planets.find((p) => p.id === 'cinder').sectors[0].owner === 'coma'));
    assert.strictEqual(taken.state.war.planets.find((p) => p.id === 'cinder').owner, null);
    assert.ok(taken.state.war.log.some((l) => l.text === 'Coma Conglomerate took Cinder 1 from the Terran Compact'));
    admin.send({ type: 'admin_capture', planet: 'cinder', sector: 'cinder-1' });
    assert.strictEqual(await error(admin), 'the Coma Conglomerate already holds Cinder 1');
    none.send({ type: 'demo_capture', planet: 'cinder', sector: 'cinder-2' });
    assert.match(await error(none), /only for demo mode/, 'pilots still need demo mode');

    // The key never went out to anyone, not even the admins.
    for (const c of [admin, wrong, short, none, kuro, thief]) assert.ok(!c.raw.some((r) => r.includes(KEY)));
    for (const c of [admin, wrong, short, none, kuro, thief]) c.close();
  } finally {
    await server.close();
  }
});

test('only apps the server welcomed hear the galaxy; a Coma character is the key\'s on every message, and nobody plays another role\'s character', async () => {
  const port = 18085;
  const KEY = 'teal-sesame-42';
  const LOCKED = 'that character plays for the Coma Conglomerate: admins only';
  const server = startServer({ port, buildSpeed: Infinity, tickMs: 60000, adminKey: KEY });
  const error = (c) => c.next((m) => m.type === 'error').then((m) => m.reason);
  const hello = async (role, name, admin_key) => {
    const c = await connect(port);
    c.send({ type: 'hello', role, name, admin_key });
    await c.next((m) => m.type === 'welcome');
    return c;
  };
  try {
    const lurker = await connect(port); // never says hello
    // Names every object already has would reach into the galaxy's books: refused, no role.
    const odd = await connect(port);
    for (const name of ['__proto__', 'constructor', 'toString']) {
      odd.send({ type: 'hello', role: 'explorer', name });
      assert.strictEqual(await error(odd), `"${name}" can't be a name: pick another`);
    }
    odd.send({ type: 'choose_faction', faction: 'ashen' });
    assert.strictEqual(await error(odd), 'say hello first');
    assert.deepStrictEqual([{}.faction, {}.hold], [undefined, undefined]);

    // Mio's base and Zed's pilot are open on apps without the key when an admin takes them into Coma.
    const mio = await hello('builder', 'Mio');
    const mioAdmin = await hello('builder', 'Mio', KEY);
    const zed = await hello('explorer', 'Zed');
    const zedAdmin = await hello('explorer', 'Zed', KEY);
    mioAdmin.send({ type: 'choose_faction', faction: 'coma' });
    assert.strictEqual(await error(mio), LOCKED, 'turned away at once');
    zedAdmin.send({ type: 'choose_faction', faction: 'coma' });
    assert.strictEqual(await error(zed), LOCKED);
    mio.send({ type: 'found_site', facility: 'fuel', planet: 'morrow', sector: 'morrow-1' });
    assert.strictEqual(await error(mio), 'say hello first', 'and has no role left');
    zed.send({ type: 'post_contract', item: 'metal', amount: 1, reward: 1 });
    assert.strictEqual(await error(zed), 'say hello first');
    // However a character came to play for Coma, the next message from an app without the key is refused.
    const kai = await hello('builder', 'Kai');
    server.galaxy.bases.Kai.faction = 'coma';
    kai.send({ type: 'donate', item: 'metal', qty: 1 });
    assert.strictEqual(await error(kai), LOCKED);
    kai.send({ type: 'donate', item: 'metal', qty: 1 });
    assert.strictEqual(await error(kai), 'say hello first');
    assert.strictEqual(server.galaxy.bases.Kai.stock.metal, 60, 'nothing given');

    // Mio's pilot and Zed's Builder are other characters: they can't run Mio's base or Zed's cargo.
    const aster = server.galaxy.system.planets.find((p) => p.owner === 'Mio');
    const mioPilot = await hello('explorer', 'Mio');
    for (const [type, fields] of [['build', { slot: 1, building: 'extractor' }], ['post_job', { resource: 'ice', amount: 1, reward: 1 }], ['queue_ship', { slot: 0, ship: 'corvette' }], ['upgrade_building', { slot: 0 }], ['remove_piece', { piece: 1 }], ['clear_obstacle', { obstacle: 1 }]]) {
      mioPilot.send({ type, planet: aster.id, ...fields });
      assert.strictEqual(await error(mioPilot), 'only Builders run a base', type);
    }
    assert.deepStrictEqual(aster.buildings.map((b) => b.type), ['command'], 'nothing built');
    server.galaxy.pilots.Zed.stash.push({ item: 'drive', qty: 1, fih: false });
    const zedBuilder = await hello('builder', 'Zed');
    for (const [type, fields, reason] of [['collect', { resource: 'ice', amount: 5 }, 'only pilots carry cargo'], ['deliver', { job: 1 }, 'only pilots carry cargo'], ['sell', {}, 'only pilots sell to the Fence']]) {
      zedBuilder.send({ type, ...fields });
      assert.strictEqual(await error(zedBuilder), reason, type);
    }
    assert.deepStrictEqual([server.galaxy.pilots.Zed.cargo, server.galaxy.pilots.Zed.stash.length, server.galaxy.pilots.Zed.credits], [{}, 1, 0]);

    // State, chat and ships went only to welcomed apps: never to one that didn't say hello, or was
    // turned away (after that).
    zedAdmin.send({ type: 'chat', text: 'anyone there?' });
    await mioAdmin.next((m) => m.type === 'chat');
    zedAdmin.send({ type: 'ship', pos: [1, 2, 3], rot: [0, 0, 0] });
    await mioAdmin.next((m) => m.type === 'ship');
    for (const c of [lurker, odd, mio, zed, kai]) {
      c.send({ type: 'ping' }); // its answer comes after anything sent to it before
      assert.strictEqual(await error(c), 'say hello first');
    }
    const heard = (c) => c.raw.map((r) => JSON.parse(r)).filter((m) => ['state', 'welcome', 'chat', 'ship'].includes(m.type));
    assert.deepStrictEqual([heard(lurker), heard(odd)], [[], []], 'nothing of the galaxy');
    for (const c of [mio, zed, kai]) {
      const all = c.raw.map((r) => JSON.parse(r));
      const away = all.findIndex((m) => m.type === 'error' && m.reason === LOCKED);
      assert.ok(away > 0);
      assert.ok(!all.slice(away).some((m) => ['state', 'chat', 'ship'].includes(m.type)), 'nothing after it was turned away');
    }
    for (const c of [lurker, odd, mio, mioAdmin, zed, zedAdmin, kai, mioPilot, zedBuilder]) c.close();
  } finally {
    await server.close();
  }
});
