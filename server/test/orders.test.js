// Faction orders: operations of three orders, what counts toward them, deadlines and rewards, the
// Coma offensive, the archive, and the Coma director's orders by hand.

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const G = require('../galaxy');
const O = require('../orders');
const W = require('../war');

// A demo-war galaxy with campaigns on, pilots and Builders in each faction, and a ledger of payments.
function setup() {
  W.setDemo(true);
  const g = G.newGalaxy();
  const t = O.DEMO_OP_MS * 1000; // the start of an operation
  C.tick(g, t);
  const people = { compact: ['Cora'], ashen: ['Ash', 'Ember'], luminar: ['Lumi'] };
  for (const [f, names] of Object.entries(people)) for (const n of names) Object.assign(G.pilot(g, n), { faction: f, credits: 0 });
  g.bases = { Rin: { faction: 'ashen', credits: 0, stock: {} }, Kai: { faction: 'compact', credits: 0, stock: {} } };
  const paid = {};
  const pay = (name, n) => {
    paid[name] = (paid[name] || 0) + n;
    if (g.pilots[name]) g.pilots[name].credits += n;
    else g.bases[name].credits += n;
  };
  return { g, t, paid, pay };
}
const ashenOrder = (g) => g.war.orders.op.factions.ashen.orders.at(-1);

test('an operation runs three orders, one slot at a time; each faction gets its own, in its own voice, with the targets explained', () => {
  const { g, t, pay } = setup();
  assert.ok(O.tick(g, pay, t));
  const op = g.war.orders.op;
  assert.match(op.name, /^Operation \w+ \w+$/);
  assert.strictEqual(op.endsAt - op.startsAt, O.DEMO_OP_MS);
  for (const f of O.PLAYER_FACTIONS) {
    const [o] = op.factions[f].orders;
    assert.strictEqual(o.issuer, O.VOICES[f].issuer);
    assert.ok(o.briefing.startsWith(O.VOICES[f].open));
    assert.match(o.briefing, /3 wins and 2 more for each of our \d+ pilot/, 'the scaling is said out loud');
    assert.ok(o.tasks.length >= 2);
    assert.strictEqual(o.endsAt, op.startsAt + O.DEMO_OP_MS / 3);
  }
  assert.ok(g.war.log.some((e) => /begins: three orders/.test(e.text)));
  // A faction with no Builders is never asked for donations it can't make.
  for (const slot of [0, 1, 2]) {
    g.war.orders.op.slot = slot; // each kind of order: offensive, hold, war effort
    const o = O.issue(g, { faction: 'luminar' }, t + slot).order;
    assert.ok(!o.tasks.some((x) => x.type === 'donate'), 'the Accord has no Builders');
    assert.ok(!/War Merit and 30/.test(o.briefing));
  }
  // The next slot opens a third of the way through (unless it's a Coma offensive).
  op.comaSlot = -1;
  op.slot = 0;
  O.tick(g, pay, t + O.DEMO_OP_MS / 3 + 1);
  assert.strictEqual(op.factions.ashen.orders.length, 2);
  assert.notStrictEqual(op.factions.ashen.orders[0].status, 'active', 'the first closed at its deadline');
});

test("wins count toward the winner's tasks that fit (mode, planet), crediting its players; Builders' donations count too", () => {
  const { g, t, pay } = setup();
  O.tick(g, pay, t);
  const o = ashenOrder(g);
  o.tasks = [
    { type: 'wins', mode: 'facility', need: 2, have: 0, done: false, label: '' },
    { type: 'wins', planet: 'cinder', need: 1, have: 0, done: false, label: '' },
    { type: 'donate', need: 50, have: 0, done: false, label: '' },
  ];
  O.matchWon(g, { planet: 'vesper', mode: 'facility', winner: 'ashen', loser: 'compact', names: ['Ash'] }, t + 1);
  O.matchWon(g, { planet: 'vesper', mode: 'facility', winner: 'compact', loser: 'ashen', names: ['Cora'] }, t + 2);
  assert.deepStrictEqual(o.tasks.map((x) => x.have), [1, 0, 0], "the Compact's win isn't the Collective's");
  O.matchWon(g, { planet: 'cinder', mode: 'facility', winner: 'ashen', loser: 'compact', names: ['Ash', 'Ember'] }, t + 3);
  assert.deepStrictEqual(o.tasks.map((x) => x.done), [true, true, false]);
  O.donated(g, 'ashen', 'Rin', 60, t + 4);
  assert.ok(o.tasks[2].done);
  assert.deepStrictEqual(o.contrib, { Ash: 3, Ember: 2, Rin: 6 });
});

test("leading and holding read the planet's campaign; at the deadline a won order pays its fighters and every member, a failed one nothing", () => {
  const { g, t, paid, pay } = setup();
  O.tick(g, pay, t);
  const o = ashenOrder(g);
  const camp = g.war.campaigns.cinder;
  o.tasks = [{ type: 'lead', planet: 'cinder', have: 0, done: false, label: '' }];
  camp.points.ashen = 10;
  camp.points.compact = 10;
  O.tick(g, pay, t + 1);
  assert.strictEqual(o.tasks[0].done, false, 'a tie is no lead');
  camp.points.ashen = 12;
  O.tick(g, pay, t + 2);
  assert.strictEqual(o.tasks[0].done, true);
  o.contrib = { Ash: 2 };
  g.war.orders.op.comaSlot = -1;
  O.tick(g, pay, o.endsAt);
  assert.strictEqual(o.status, 'won');
  assert.strictEqual(paid.Ash, O.REWARD.order + O.REWARD.member);
  assert.strictEqual(paid.Ember, O.REWARD.member);
  assert.strictEqual(paid.Rin, O.REWARD.member, 'Builders are members too');
  assert.strictEqual(paid.Cora, undefined);
  assert.ok(g.war.log.some((e) => e.text.includes(O.VOICES.ashen.won)));
  // Hold: nobody may outscore us; the next order fails when someone does.
  const h = ashenOrder(g);
  h.tasks = [{ type: 'hold', planet: 'cinder', have: 0, done: false, label: '' }];
  camp.points.compact = 30;
  O.tick(g, pay, h.endsAt);
  assert.strictEqual(h.status, 'failed');
  assert.ok(g.war.log.some((e) => e.text.includes(O.VOICES.ashen.lost)));
});

test('win two of three and the operation is won: a bigger reward, a commendation, and the archive', () => {
  const { g, t, paid, pay } = setup();
  O.tick(g, pay, t);
  const op = g.war.orders.op;
  op.comaSlot = -1;
  for (let slot = 0; slot < 3; slot++) {
    for (const f of O.PLAYER_FACTIONS) {
      const o = op.factions[f].orders.at(-1);
      // The Collective wins its first two orders; the others none.
      o.tasks = [{ type: 'wins', need: 1, have: f === 'ashen' && slot < 2 ? 1 : 0, done: f === 'ashen' && slot < 2, label: '' }];
    }
    O.tick(g, pay, op.startsAt + Math.round(((slot + 1) * O.DEMO_OP_MS) / 3));
  }
  assert.strictEqual(g.war.orders.op.id === op.id, false, 'a new operation began');
  const [arch] = g.war.orders.archive;
  assert.strictEqual(arch.name, op.name);
  assert.deepStrictEqual([arch.factions.ashen.status, arch.factions.ashen.won], ['won', 2]);
  assert.strictEqual(arch.factions.compact.status, 'failed');
  assert.strictEqual(paid.Ember, 2 * O.REWARD.member + O.REWARD.operation);
  assert.deepStrictEqual(g.pilots.Ash.commendations, [op.name]);
  assert.strictEqual(g.pilots.Cora.commendations, undefined);
});

test("a Coma offensive is one order for all three factions: any player faction's wins over the Coma count, and all share the outcome", () => {
  const { g, t, pay } = setup();
  O.tick(g, pay, t);
  const op = g.war.orders.op;
  op.comaSlot = 1;
  O.tick(g, pay, t + O.DEMO_OP_MS / 3 + 1);
  const [c] = op.coma;
  assert.strictEqual(c.kind, 'coma');
  assert.strictEqual(c.issuer, O.VOICES.coma.issuer);
  assert.strictEqual(op.factions.ashen.orders.length, 1, 'no faction order in that slot');
  const task = c.tasks.find((x) => x.type === 'coma_wins');
  task.need = 2;
  c.tasks = [task];
  O.matchWon(g, { planet: 'morrow', mode: 'sector', winner: 'ashen', loser: 'compact', names: ['Ash'] }, t + O.DEMO_OP_MS / 3 + 2);
  assert.strictEqual(task.have, 0, 'only wins over the Coma');
  O.matchWon(g, { planet: 'morrow', mode: 'sector', winner: 'ashen', loser: 'coma', names: ['Ash'] }, t + O.DEMO_OP_MS / 3 + 3);
  O.matchWon(g, { planet: 'morrow', mode: 'space', winner: 'luminar', loser: 'coma', names: ['Lumi'] }, t + O.DEMO_OP_MS / 3 + 4);
  assert.ok(task.done);
  O.tick(g, pay, c.endsAt);
  assert.strictEqual(c.status, 'won');
  for (const f of O.PLAYER_FACTIONS) assert.strictEqual(op.factions[f].won, 1);
  assert.deepStrictEqual(O.ordersOf(op, 'compact').map((o) => o.kind), ['faction', 'coma', 'faction'], 'and the third slot opened');
});

test('the Coma director issues orders by hand, for a faction or all of them; bad tasks are refused', () => {
  const { g, t, pay } = setup();
  assert.match(O.issue(g, { faction: 'ashen' }, t).reason, /no operation/);
  O.tick(g, pay, t);
  assert.match(O.issue(g, { faction: 'nobody' }, t).reason, /no such faction/);
  assert.match(O.issue(g, { faction: 'ashen', tasks: [{ type: 'dance' }] }, t).reason, /no such task type/);
  const r = O.issue(g, { faction: 'ashen', title: 'Hold Vesper at all costs', tasks: [{ type: 'hold', planet: 'vesper', label: 'Hold Vesper' }, { type: 'wins', need: 4, label: 'Win 4' }] }, t + 5);
  assert.ok(r.ok);
  const live = g.war.orders.op.factions.ashen.orders.filter((o) => o.status === 'active');
  assert.deepStrictEqual(live.map((o) => o.title), ['Hold Vesper at all costs'], 'it replaces the running order');
  assert.deepStrictEqual(live[0].tasks.map((x) => [x.type, x.need]), [['hold', undefined], ['wins', 4]]);
  assert.ok(O.issue(g, { faction: 'all' }, t + 6).ok, 'a Coma offensive for everyone');
  assert.strictEqual(g.war.orders.op.coma.length, 1);
  W.setDemo(false);
});
