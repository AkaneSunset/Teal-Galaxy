// Titles: each pilot of the winning side is credited a campaign match's points by mode, and when
// the campaign ends the pilots of the faction that won the planet with enough points in a mode earn
// its title ("Ghost of Cinder").

const test = require('node:test');
const assert = require('node:assert');
const C = require('../campaign');
const G = require('../galaxy');
const TI = require('../titles.ts');
const T = require('../tunables.ts');
const W = require('../war');

test('titles: points credited per pilot and mode, awarded to the planet winner at 500, fresh each campaign', () => {
  W.setDemo(true);
  const g = G.newGalaxy();
  const t = C.DEMO_CYCLE_MS * 100;
  C.tick(g, t);
  for (const n of ['Vex', 'Rook', 'Ash']) G.pilot(g, n);
  const c = g.war.campaigns.cinder;
  assert.strictEqual(T.get().titles.points, 500);
  // 84 Space Battle wins (6 points each) for Ashen with Vex and Rook flying; Rook flies 10 more for
  // Compact, which starts their Compact count afresh, and Ash wins Sector Battles for Ashen.
  for (let i = 0; i < 84; i++) C.score(g, 'cinder', 'space', 'ashen', false, t + 1000 + i, 0, ['Vex', 'Rook', 'Vex']);
  assert.deepStrictEqual(TI.progress(g, 'Vex'), [{ planet: 'cinder', mode: 'space', points: 504, title: 'Ghost of Cinder', need: 500 }]);
  for (let i = 0; i < 10; i++) C.score(g, 'cinder', 'space', 'compact', false, t + 2000 + i, 0, ['Rook']);
  assert.strictEqual(TI.progress(g, 'Rook')[0].points, 60, 'points count for one side');
  C.score(g, 'cinder', 'sector', 'ashen', false, t + 3000, 0, ['Ash']);
  assert.deepStrictEqual(TI.progress(g, 'Ash').map((p) => [p.mode, p.points, p.title]), [['sector', 10, 'Warlord of Cinder']]);
  assert.deepStrictEqual(TI.progress(g, 'Nobody'), []);
  assert.strictEqual(c.points.ashen, 84 * 6 + 10);
  // Ashen wins Cinder: Vex has 504 in Space Battles and earns Ghost of Cinder; Rook's points went
  // to Compact, and Ash's 10 are short.
  C.tick(g, c.endsAt);
  assert.strictEqual(W.planet(g, 'cinder').owner, 'ashen');
  assert.deepStrictEqual(g.pilots.Vex.titles, ['Ghost of Cinder']);
  assert.strictEqual(g.pilots.Rook.titles, undefined);
  assert.strictEqual(g.pilots.Ash.titles, undefined);
  assert.ok(g.war.log.some((e) => e.text === 'Vex earned the title Ghost of Cinder: 504 points won for Cinder in Space Battles'));
  // The next campaign starts everyone at nothing; a planet the losing side's pilots fought for
  // gives them nothing, however many points they had.
  assert.deepStrictEqual(TI.progress(g, 'Vex'), []);
  const c2 = g.war.campaigns.cinder;
  for (let i = 0; i < 90; i++) C.score(g, 'cinder', 'space', 'compact', false, c2.startsAt + 1 + i, 0, ['Rook']);
  for (let i = 0; i < 100; i++) C.score(g, 'cinder', 'sector', 'ashen', false, c2.startsAt + 1000 + i, 0, ['Ash']);
  C.tick(g, c2.endsAt);
  assert.strictEqual(W.planet(g, 'cinder').owner, 'ashen');
  assert.strictEqual(g.pilots.Rook.titles, undefined, 'Compact lost Cinder');
  assert.deepStrictEqual(g.pilots.Ash.titles, ['Warlord of Cinder']);
  // A title is kept once: Vex earning it again doesn't repeat it.
  const c3 = g.war.campaigns.cinder;
  for (let i = 0; i < 84; i++) C.score(g, 'cinder', 'space', 'ashen', false, c3.startsAt + 1 + i, 0, ['Vex']);
  C.tick(g, c3.endsAt);
  assert.deepStrictEqual(g.pilots.Vex.titles, ['Ghost of Cinder']);
  assert.ok(!g.titles.credit.cinder || g.titles.credit.cinder.campaign !== c3.startsAt, 'the ended campaign\'s credit is cleared');
  W.setDemo(false);
});

test('titles: nothing credited without a campaign, a winner or points; every mode has a title', () => {
  W.setDemo(true);
  const g = G.newGalaxy();
  assert.deepStrictEqual(TI.credit(g, { planet: 'cinder', mode: 'space', faction: 'ashen', names: ['Vex'], points: 6 }), {}, 'no campaign yet');
  C.tick(g, C.DEMO_CYCLE_MS * 100);
  assert.deepStrictEqual(TI.credit(g, { planet: 'cinder', mode: 'space', faction: 'ashen', names: ['Vex'], points: 0 }), {});
  assert.deepStrictEqual(TI.credit(g, { planet: 'cinder', mode: 'space', faction: 'ashen', names: ['Vex'], points: 6 }), { Vex: 6 });
  assert.deepStrictEqual(TI.award(g, 'cinder', null), [], 'nobody won');
  assert.deepStrictEqual(Object.keys(C.MODES).map((m) => TI.titleFor(m, 'Cinder')), ['Warlord of Cinder', 'Lion of Cinder', 'Ghost of Cinder', 'Champion of Cinder', 'Bulwark of Cinder']);
  W.setDemo(false);
});
