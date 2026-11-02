// Accounts over the wire: signing in, characters, side locks, war-supply receipts, and what no app
// ever sees.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const A = require('../accounts.ts');
const TM = require('../telemetry.ts');
const W = require('../war');
const { startServer } = require('../server');

// An app's connection.
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

const welcome = (m) => m.type === 'welcome';
const error = (m) => m.type === 'error';

test('a server that requires sign-in: accounts, their characters, tokens', async () => {
  A.reset();
  const port = 18190;
  const server = startServer({ port, tickMs: 60000, signIn: 'required' });
  try {
    const app = await connect(port);
    app.send({ type: 'hello', role: 'explorer', name: 'Kite' });
    assert.strictEqual((await app.next(error)).reason, 'sign in with an account to play on this server');
    app.send({ type: 'chat', text: 'hi' });
    assert.strictEqual((await app.next(error)).reason, 'say hello first', 'nothing a guest sends is acted on');

    app.send({ type: 'hello', role: 'explorer', name: 'Kite', account: 'Akane', password: 'secret1' });
    const w = await app.next(welcome);
    assert.strictEqual(w.account.name, 'Akane');
    assert.deepStrictEqual(w.account.characters, ['explorer/Kite']);
    assert.ok(w.account.token);
    assert.strictEqual(w.catalog.accounts.signIn, 'required');
    assert.strictEqual(w.catalog.ledger.shares.arena, 0.15);
    assert.deepStrictEqual(w.receipts, []);

    // Another account can't play Kite; Akane's token signs in again without the password.
    const thief = await connect(port);
    thief.send({ type: 'hello', role: 'explorer', name: 'Kite', account: 'Other', password: 'secret2' });
    assert.match((await thief.next(error)).reason, /the pilot Kite belongs to another account/);
    thief.send({ type: 'hello', role: 'explorer', name: 'Kite', account: 'Akane', password: 'nope' });
    assert.match((await thief.next(error)).reason, /wrong password for the account Akane/);
    const back = await connect(port);
    back.send({ type: 'hello', role: 'builder', name: 'Akane', account: 'akane', token: w.account.token });
    const wb = await back.next(welcome);
    assert.deepStrictEqual(wb.account.characters, ['explorer/Kite', 'builder/Akane'], 'a second character on the same account');
    assert.ok(wb.home, 'the Builder has a base');

    // Nothing about accounts goes to any app.
    for (const msg of [...app.raw, ...back.raw]) {
      assert.ok(!msg.includes('"salt"') && !msg.includes('"hash"'), 'no password hashes on the wire');
      assert.ok(!msg.includes('"owners"') && !msg.includes('"receipts":{'), 'nor who owns what, nor anyone else\'s receipts');
    }
    const events = TM.recent('sign_in_refused').map((e) => e.reason);
    assert.ok(events.includes('sign in with an account to play on this server'));
    for (const c of [app, thief, back]) c.close();
  } finally {
    await server.close();
  }
});

test('one side per front: a donation takes the side, another character is refused; receipts and the dashboard', async () => {
  A.reset();
  TM.reset();
  const port = 18191;
  const server = startServer({ port, tickMs: 60000, demo: true, demoWar: true, adminKey: 'k3y' });
  try {
    const builder = await connect(port);
    builder.send({ type: 'hello', role: 'builder', name: 'Akane', account: 'Akane', password: 'secret1' });
    await builder.next(welcome);
    builder.send({ type: 'choose_faction', faction: 'compact' });
    await builder.next((m) => m.type === 'state' && m.state.bases.Akane?.faction === 'compact');
    builder.send({ type: 'donate', item: 'metal', qty: 100, planet: 'cinder' });
    const { receipt } = await builder.next((m) => m.type === 'war_receipt');
    assert.strictEqual(receipt.planet, 'cinder');
    assert.strictEqual(receipt.source, 'builder');
    assert.strictEqual(receipt.base, 10, '100 metal is 200 War Merit, 10 war supply');
    const st = await builder.next((m) => m.type === 'state' && m.state.war.ledger.fronts.cinder?.factions.compact);
    assert.ok(st.state.war.ledger.fronts.cinder.factions.compact.sources.builder > 0, 'everyone sees the front\'s war supply');
    assert.strictEqual(st.state.accounts, undefined);
    assert.strictEqual(st.state.war.ledger.receipts, undefined);
    builder.send({ type: 'donate', item: 'metal', qty: 1, planet: 'bastion' });
    assert.match((await builder.next(error)).reason, /isn't in a campaign on that planet/);

    // The same account's pilot, for another faction, can't fight on Cinder this campaign.
    const pilot = await connect(port);
    pilot.send({ type: 'hello', role: 'explorer', name: 'Kite', account: 'Akane', password: 'secret1' });
    await pilot.next(welcome);
    pilot.send({ type: 'choose_faction', faction: 'ashen' });
    await pilot.next((m) => m.type === 'state' && m.state.pilots.Kite?.faction === 'ashen');
    pilot.send({ type: 'campaign_queue', planet: 'cinder', mode: 'sector' });
    assert.match((await pilot.next(error)).reason, /^your account took the Terran Compact's side on Cinder this campaign \(Akane\): it can fight for nobody else there until the campaign ends, in \d+m$/);
    pilot.send({ type: 'campaign_queue', planet: 'vesper', mode: 'sector' });
    assert.match((await pilot.next(error)).reason, /bring your carrier/, 'Vesper is free: only the carrier is missing');
    await new Promise((r) => setTimeout(r, 1100)); // two battle messages a second at most
    pilot.send({ type: 'battle_start', planet: 'cinder', sector: 'cinder-2' });
    assert.match((await pilot.next(error)).reason, /took the Terran Compact's side on Cinder/, 'sector battles too');
    // Another account's pilot is free to fight for anyone.
    const other = await connect(port);
    other.send({ type: 'hello', role: 'explorer', name: 'Rook', account: 'Rook', password: 'secret3' });
    await other.next(welcome);
    other.send({ type: 'choose_faction', faction: 'ashen' });
    await other.next((m) => m.type === 'state' && m.state.pilots.Rook?.faction === 'ashen');
    other.send({ type: 'campaign_queue', planet: 'cinder', mode: 'sector' });
    assert.match((await other.next(error)).reason, /bring your carrier/);

    // The dashboard: admins only.
    pilot.send({ type: 'admin_dashboard' });
    assert.strictEqual((await pilot.next(error)).reason, 'admins only');
    const admin = await connect(port);
    admin.send({ type: 'hello', role: 'explorer', name: 'Ops', admin_key: 'k3y' });
    await admin.next(welcome);
    admin.send({ type: 'admin_dashboard' });
    const d = await admin.next((m) => m.type === 'dashboard');
    const cinder = d.fronts.find((f) => f.planet === 'cinder');
    assert.ok(cinder.supply.factions.compact.total > 0);
    assert.strictEqual(cinder.supply.factions.compact.perHour, cinder.supply.factions.compact.total);
    assert.deepStrictEqual({ builders: d.online.builders, pilots: d.online.pilots, accounts: d.online.accounts, guests: d.online.guests }, { builders: 1, pilots: 3, accounts: 2, guests: 1 });
    assert.strictEqual(d.signIn, 'optional', 'the demo lets guests play');
    assert.ok(d.telemetry.counters.sign_in >= 4 && d.telemetry.counters.side_refused >= 2);
    assert.ok(d.telemetry.events.some((e) => e.kind === 'war_supply' && e.planet === 'cinder'));
    for (const c of [builder, pilot, other, admin]) c.close();
  } finally {
    await server.close();
    W.setDemo(false);
  }
});
