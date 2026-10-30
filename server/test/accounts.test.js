// Accounts: signing in, claiming characters, and one side per front per account.

const test = require('node:test');
const assert = require('node:assert');
const A = require('../accounts.ts');
const T = require('../tunables.ts');

const DAY = 24 * 3600_000;

test('the first sign-in opens an account; later ones need its password, or the token', () => {
  A.reset();
  const g = {};
  const t = 1_000_000;
  assert.match(A.signIn(g, { name: '', password: 'secret1' }, t).reason, /account name/);
  assert.match(A.signIn(g, { name: 'Akane', password: 'abc' }, t).reason, /at least 6 characters/);
  const first = A.signIn(g, { name: 'Akane', password: 'secret1' }, t);
  assert.ok(first.ok && first.created && first.key === 'akane' && first.token);
  const acct = g.accounts.akane;
  assert.strictEqual(acct.name, 'Akane');
  assert.ok(!JSON.stringify(acct).includes('secret1'), 'the password is never kept');
  assert.match(acct.hash, /^[0-9a-f]{64}$/);
  const again = A.signIn(g, { name: 'AKANE', password: 'secret1' }, t + 1);
  assert.ok(again.ok && !again.created && again.key === 'akane', 'names are the same however they are capitalized');
  assert.match(A.signIn(g, { name: 'akane', password: 'wrong' }, t + 2).reason, /wrong password for the account Akane/);
  assert.ok(A.signIn(g, { name: 'akane', token: first.token }, t + 3).ok, 'the token signs in without the password');
  assert.match(A.signIn(g, { name: 'someone', token: first.token }, t + 3).reason, /password/, "a token is only good for its own account");
  assert.match(A.signIn(g, { name: 'constructor', password: 'secret1' }, t).reason, /can't be an account name/);
});

test('wrong passwords are throttled per account', () => {
  A.reset();
  const g = {};
  const t = 5_000_000;
  assert.ok(A.signIn(g, { name: 'Vesper', password: 'goodpass' }, t).ok);
  const max = T.get().accounts.attemptsPerMinute;
  for (let i = 0; i < max; i++) assert.match(A.signIn(g, { name: 'Vesper', password: `bad${i}` }, t + i).reason, /wrong password/);
  assert.match(A.signIn(g, { name: 'Vesper', password: 'goodpass' }, t + 10).reason, /too many sign-in attempts/, 'even the right one, for a minute');
  assert.ok(A.signIn(g, { name: 'Vesper', password: 'goodpass' }, t + 61_000).ok);
});

test('characters belong to the account that claims them; guests play only unclaimed ones', () => {
  A.reset();
  const g = {};
  const a = A.signIn(g, { name: 'Akane', password: 'secret1' }).key;
  const b = A.signIn(g, { name: 'Other', password: 'secret2' }).key;
  assert.ok(A.claim(g, a, 'explorer', 'Kite').claimed);
  assert.ok(A.claim(g, a, 'explorer', 'Kite').ok && !A.claim(g, a, 'explorer', 'Kite').claimed, 'its own: fine');
  assert.match(A.claim(g, b, 'explorer', 'Kite').reason, /belongs to another account/);
  assert.match(A.claim(g, null, 'explorer', 'Kite').reason, /belongs to an account: sign in/);
  assert.ok(A.claim(g, null, 'explorer', 'Drifter').ok, 'a guest may play one nobody owns');
  assert.ok(A.claim(g, b, 'builder', 'Kite').claimed, 'a Builder and a pilot of one name are two characters');
  assert.strictEqual(A.ownerOf(g, 'builder', 'Kite'), 'other');
  T.override({ accounts: { charactersMax: 2 } });
  try {
    assert.ok(A.claim(g, a, 'builder', 'Akane').claimed);
    assert.match(A.claim(g, a, 'explorer', 'Third').reason, /2 characters at most/);
  } finally {
    T.reset();
  }
  assert.deepStrictEqual(A.view(g, a).characters, ['explorer/Kite', 'builder/Akane']);
});

test('one side per front per account, until the campaign there ends', () => {
  A.reset();
  const g = {};
  const a = A.signIn(g, { name: 'Akane', password: 'secret1' }).key;
  const t = 10 * DAY;
  const ends = t + 3 * DAY + 4 * 3600_000;
  const names = { planetName: 'Cinder', factionName: (f) => ({ compact: 'Terran Compact', ashen: 'Ashen Collective' })[f] };
  assert.ok(A.checkSide(g, a, 'cinder', 'ashen', t).ok, 'no side taken yet');
  assert.strictEqual(A.takeSide(g, a, 'cinder', 'compact', ends, 'explorer/Kite', t).faction, 'compact');
  assert.ok(A.checkSide(g, a, 'cinder', 'compact', t + 1).ok, 'the same side: fine');
  const no = A.checkSide(g, a, 'cinder', 'ashen', t + 1, names);
  assert.strictEqual(no.reason, "your account took the Terran Compact's side on Cinder this campaign (Kite): it can fight for nobody else there until the campaign ends, in 3d 4h");
  assert.ok(A.checkSide(g, a, 'vesper', 'ashen', t + 1).ok, 'other fronts are free');
  assert.strictEqual(A.takeSide(g, a, 'cinder', 'ashen', ends, 'builder/Akane', t + 2).faction, 'compact', 'a side taken stays');
  assert.ok(A.checkSide(g, a, 'cinder', 'ashen', ends).ok, 'free again once the campaign ends');
  assert.ok(A.checkSide(g, null, 'cinder', 'ashen', t).ok, 'guests have one faction for good, so no lock');
  assert.strictEqual(A.takeSide(g, null, 'cinder', 'ashen', ends, 'explorer/Guest', t), null);
  T.override({ sideLock: { on: false } });
  try {
    assert.ok(A.checkSide(g, a, 'cinder', 'ashen', t + 1).ok, 'side locks can be turned off');
  } finally {
    T.reset();
  }
  assert.deepStrictEqual([A.timeLeft(59_000), A.timeLeft(2 * 3600_000 + 5 * 60_000), A.timeLeft(DAY + 3600_000)], ['1m', '2h 05m', '1d 1h']);
});
