// Tunables: the file passes its own check, bad files are refused, and reloads reach the rules.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const C = require('../campaign');
const O = require('../orders');
const T = require('../tunables.ts');

test('tunables.json passes the check, and the check names what is wrong', () => {
  const raw = JSON.parse(fs.readFileSync(T.FILE, 'utf8'));
  assert.deepStrictEqual(T.check(raw), []);
  const bad = structuredClone(raw);
  delete bad.ledger.shares.arena;
  bad.ledger.shares.frontier = 1.5;
  bad.accounts.charactersMax = 2.5;
  bad.sideLock.on = 'yes';
  bad.campaign.modes.sector.typo = 3;
  bad.extra = {};
  assert.deepStrictEqual(T.check(bad).sort(), [
    'accounts.charactersMax: must be a whole number from 1 to 100',
    'campaign.modes.sector.typo: not a tunable',
    'extra: not a tunable',
    'ledger.shares.arena: missing',
    'ledger.shares.frontier: must be a number from 0 to 1',
    'sideLock.on: must be true or false',
  ]);
});

test('a change reaches the rules that use it, and reset() puts the file back', () => {
  const values = T.get();
  const ledger = values.ledger;
  try {
    assert.ok(T.override({ campaign: { modes: { sector: { points: 12 } }, aiShare: 0.25, finalMultiplier: 3 }, orders: { reward: { order: 300 } }, ledger: { shares: { arena: 0.2 } } }).ok);
    assert.strictEqual(T.get(), values, 'always the same object');
    assert.strictEqual(T.get().ledger, ledger, 'sections stay the same objects too');
    assert.strictEqual(ledger.shares.arena, 0.2);
    assert.strictEqual(C.MODES.sector.points, 12, 'campaign.js keeps MODES up to date');
    assert.strictEqual(C.AI_SHARE, 0.25);
    assert.strictEqual(O.REWARD.order, 300, 'and orders.js its rewards');
    const c = { finalAt: 1000 };
    assert.strictEqual(C.worth(c, 'sector', true, 0), 3);
    assert.strictEqual(C.worth(c, 'sector', false, 2000), 36);
    const refused = T.override({ ledger: { shares: { arena: 2 } } });
    assert.ok(!refused.ok);
    assert.match(refused.errors[0], /ledger.shares.arena/);
    assert.strictEqual(ledger.shares.arena, 0.2, 'a refused change changes nothing');
  } finally {
    assert.ok(T.reset().ok);
  }
  assert.strictEqual(C.MODES.sector.points, 10);
  assert.strictEqual(C.AI_SHARE, 0.5);
  assert.strictEqual(O.REWARD.order, 250);
  assert.strictEqual(ledger.shares.arena, 0.15);
});

test('watch() reloads the file when it changes, and refuses a bad one', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tunables-'));
  const file = path.join(dir, 'tunables.json');
  const raw = JSON.parse(fs.readFileSync(T.FILE, 'utf8'));
  fs.writeFileSync(file, JSON.stringify(raw));
  const seen = [];
  const stop = T.watch(file, (r) => seen.push(r), 20);
  // Touches the file, a later mtime each time, until the watcher reports (its first look at the
  // file may not have happened yet when it changes, on a busy machine), and returns the report.
  let bump = 0;
  const changed = async () => {
    const n = seen.length;
    for (let i = 0; i < 100 && seen.length === n; i++) {
      bump += 2000;
      fs.utimesSync(file, new Date(), new Date(Date.now() + bump));
      await new Promise((r) => setTimeout(r, 100));
    }
    return seen[seen.length - 1];
  };
  try {
    raw.campaign.modes.space.points = 9;
    fs.writeFileSync(file, JSON.stringify(raw));
    assert.deepStrictEqual(await changed(), { ok: true, errors: [] });
    assert.strictEqual(C.MODES.space.points, 9);
    fs.writeFileSync(file, '{ "campaign": ');
    assert.strictEqual((await changed()).ok, false);
    assert.strictEqual(C.MODES.space.points, 9, 'a bad file leaves the numbers in use');
  } finally {
    stop();
    assert.ok(T.load(T.FILE).ok);
    fs.rmSync(dir, { recursive: true, force: true });
  }
  assert.strictEqual(C.MODES.space.points, 6);
});
