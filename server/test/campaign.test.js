// Planet campaigns: the week, entry, points, the result, and matchmaking into Sector Battles.

const test = require('node:test');
const assert = require('node:assert');
const B = require('../battle');
const C = require('../campaign');
const G = require('../galaxy');
const W = require('../war');

test('a week runs from Monday 12:00 US Eastern, in winter and in summer', () => {
  W.setDemo(false);
  // Wednesday 22 October 2026, 15:00 UTC (11:00 EDT): the week began Monday 20 October, 16:00 UTC.
  assert.strictEqual(new Date(C.weekStart(Date.UTC(2026, 9, 22, 15))).toISOString(), '2026-10-19T16:00:00.000Z');
  // Monday 19 October 2026, 15:59 UTC is still the week before.
  assert.strictEqual(new Date(C.weekStart(Date.UTC(2026, 9, 19, 15, 59))).toISOString(), '2026-10-12T16:00:00.000Z');
  // In winter (EST) noon is 17:00 UTC: Sunday 13 December 2026 is in the week of Monday 7 December.
  assert.strictEqual(new Date(C.weekStart(Date.UTC(2026, 11, 13, 20))).toISOString(), '2026-12-07T17:00:00.000Z');
  W.setDemo(true);
  assert.strictEqual(C.weekStart(C.DEMO_CYCLE_MS * 7 + 5), C.DEMO_CYCLE_MS * 7, 'demo campaigns run back to back');
  W.setDemo(false);
});

test('campaigns: who enters, points by mode (half against AI, double in the final push) and the result', () => {
  W.setDemo(true); // every faction holds 25% of every contested system
  const g = G.newGalaxy();
  const t = C.DEMO_CYCLE_MS * 100;
  assert.ok(C.tick(g, t));
  const c = g.war.campaigns.cinder;
  assert.ok(c, 'every contested planet has a campaign');
  assert.ok(!g.war.campaigns.bastion, 'capital worlds have none');
  assert.deepStrictEqual(c.entrants.slice().sort(), ['ashen', 'coma', 'compact', 'luminar']);
  assert.ok(C.BONUSES[c.bonus]);
  assert.strictEqual(c.holder, 'compact');
  assert.strictEqual(C.score(g, 'cinder', 'sector', 'ashen', false, t + 1000), 10);
  assert.strictEqual(C.score(g, 'cinder', 'sector', 'ashen', true, t + 2000), 5, 'half against AI');
  assert.strictEqual(C.score(g, 'cinder', 'sector', 'compact', false, c.finalAt + 1), 20, 'double in the final push');
  assert.deepStrictEqual([c.points.ashen, c.points.compact, c.wins.ashen, c.matches], [15, 20, 2, 3]);
  assert.ok(!C.tick(g, t + 60_000), 'nothing changes mid-campaign');
  // The holder had the most: it keeps the planet, and a new campaign starts.
  assert.ok(C.tick(g, c.endsAt));
  assert.strictEqual(W.planet(g, 'cinder').owner, 'compact');
  assert.strictEqual(g.war.campaigns.cinder.points.ashen, 0);
  // Ashen wins the next week: Cinder and all its sectors are Ashen's.
  const c2 = g.war.campaigns.cinder;
  C.score(g, 'cinder', 'sector', 'ashen', false, c2.startsAt + 1);
  C.tick(g, c2.endsAt);
  const wp = W.planet(g, 'cinder');
  assert.strictEqual(wp.owner, 'ashen');
  assert.ok(wp.sectors.every((s) => s.owner === 'ashen'));
  assert.ok(g.war.log.some((e) => /Ashen Collective won the campaign for Cinder/.test(e.text)));
  // A tie leaves the planet with its holder.
  const c3 = g.war.campaigns.cinder;
  C.score(g, 'cinder', 'sector', 'compact', false, c3.startsAt + 1);
  C.score(g, 'cinder', 'sector', 'ashen', false, c3.startsAt + 2);
  C.tick(g, c3.endsAt);
  assert.strictEqual(W.planet(g, 'cinder').owner, 'ashen');
  W.setDemo(false);
});

// A matchmaking harness: real battles (never ticking on their own), pilots as plain records, and
// a clock the test moves.
function harness() {
  W.setDemo(true);
  const g = G.newGalaxy();
  let clock = C.DEMO_CYCLE_MS * 200;
  C.tick(g, clock);
  const sent = [];
  const battles = B.createBattles({ galaxy: () => g, now: () => clock, send: (c, msg) => sent.push([c.name, msg]), changed: () => {},
    onCampaignEnd: (b, winner, vsAi) => C.score(g, b.planet, 'sector', winner, vsAi, clock) });
  battles.close(); // the test steps battles itself
  const pilot = (name, faction, over) => ({ name, faction, over, battle: null });
  const mm = C.createMatchmaking({ galaxy: () => g, now: () => clock, battles, where: (me) => ({ over: me.over }), factionOf: (me) => me.faction,
    send: (c, msg) => sent.push([c.name, msg]), changed: () => {}, wait: 10_000 });
  mm.close();
  return { g, battles, mm, sent, pilot, advance: (ms) => (clock += ms), now: () => clock };
}

test('queueing: rules, then two factions are matched at once; a lone faction fights AI after the wait', () => {
  const h = harness();
  const ash = h.pilot('Ash', 'ashen', 'cinder');
  assert.match(h.mm.join(h.pilot('Nobody', null, 'cinder'), 'cinder', 'sector').reason, /faction/);
  assert.match(h.mm.join(h.pilot('Far', 'ashen', null), 'cinder', 'sector').reason, /naval zone over Cinder/);
  assert.match(h.mm.join(ash, 'cinder', 'tag').reason, /no such game mode/);
  assert.match(h.mm.join(ash, 'bastion', 'sector').reason, /no campaign/);
  assert.ok(h.mm.join(ash, 'cinder', 'sector').ok);
  assert.deepStrictEqual(h.mm.list(), { cinder: { sector: { ashen: 1 } } });
  assert.strictEqual(h.battles.campaignMatches('cinder').length, 0, 'alone, Ash waits for opponents');
  // A Compact pilot queues: a match at once, the holder (Compact) defending.
  const cmp = h.pilot('Cmp', 'compact', 'cinder');
  assert.ok(h.mm.join(cmp, 'cinder', 'sector').ok);
  const [b] = h.battles.campaignMatches('cinder');
  assert.ok(b?.campaign);
  assert.deepStrictEqual([b.attacker, b.defender, ash.battle, cmp.battle], ['ashen', 'compact', b.id, b.id]);
  assert.deepStrictEqual(h.mm.list(), {});
  assert.ok(h.sent.some(([n, m]) => n === 'Ash' && m.type === 'battle_joined' && m.side === 'a'));
  assert.ok(h.sent.some(([n, m]) => n === 'Cmp' && m.type === 'battle_joined' && m.side === 'd'));
  // Another Ashen pilot backfills that match.
  const ash2 = h.pilot('Ash2', 'ashen', 'cinder');
  h.mm.join(ash2, 'cinder', 'sector');
  assert.strictEqual(ash2.battle, b.id);
  // Elsewhere, a lone Luminar pilot fights the holder's AI once the wait is over.
  const lum = h.pilot('Lum', 'luminar', 'vesper');
  h.mm.join(lum, 'vesper', 'sector');
  h.advance(9_000);
  h.mm.fill();
  assert.strictEqual(lum.battle, null);
  h.advance(2_000);
  h.mm.fill();
  const [v] = h.battles.campaignMatches('vesper');
  assert.deepStrictEqual([v.attacker, v.defender, lum.battle], ['luminar', 'ashen', v.id]);
  W.setDemo(false);
});

test('a campaign match scores for its winner instead of taking a sector; the mining world bonus', () => {
  const h = harness();
  const ash = h.pilot('Ash', 'ashen', 'cinder');
  h.mm.join(ash, 'cinder', 'sector');
  h.advance(11_000);
  h.mm.fill();
  const [b] = h.battles.campaignMatches('cinder');
  assert.strictEqual(b.defender, 'compact', "the holder's AI defends");
  const sectors = W.planet(h.g, 'cinder').sectors.map((s) => s.owner);
  b.units.get(b.nodeId).hp = 0;
  h.battles.tick(); // the battle steps, the Command Node falls, and the match ends
  assert.strictEqual(b.result, 'a');
  assert.strictEqual(h.g.war.campaigns.cinder.points.ashen, 5, 'a win against AI scores half of 10');
  assert.deepStrictEqual(W.planet(h.g, 'cinder').sectors.map((s) => s.owner), sectors, 'no sector changed hands');
  const end = h.sent.find(([n, m]) => n === 'Ash' && m.type === 'battle_end');
  assert.match(end[1].text, /Ashen Collective won the match \(every Command Node fell\): \+5 campaign points on Cinder/);
  // On a mining world the holder's commanders start with 15% more mass.
  const mining = h.g.war.planets.find((wp) => !wp.capital && wp.owner && h.g.war.campaigns[wp.id].bonus === 'mining');
  assert.ok(mining, 'some planet is a mining world');
  const holder = h.pilot('Holder', mining.owner, mining.id);
  const m = h.battles.startCampaign(mining, 'coma' === mining.owner ? 'ashen' : 'coma', mining.owner);
  h.battles.enlistCampaign(holder, m, 'd', mining.owner);
  assert.ok(Math.abs(m.pilots.get('Holder').mass - B.MASS_START * 1.15) < 1e-6);
  W.setDemo(false);
});

test('side locks: checked when a pilot queues and as they go in, taken as they go in', () => {
  const h = harness();
  const A = require('../accounts.ts');
  A.reset();
  const g = h.g;
  const key = A.signIn(g, { name: 'Akane', password: 'secret1' }).key;
  const names = { planetName: 'Cinder', factionName: (f) => f };
  const sides = {
    check: (me, planet, faction) => A.checkSide(g, me.account, planet, faction, h.now(), names),
    take: (me, planet, faction) => A.takeSide(g, me.account, planet, faction, g.war.campaigns[planet].endsAt, `explorer/${me.name}`, h.now()),
  };
  const mm = C.createMatchmaking({ galaxy: () => g, now: h.now, battles: h.battles, where: (me) => ({ over: me.over }), factionOf: (me) => me.faction,
    send: (c, msg) => h.sent.push([c.name, msg]), changed: () => {}, wait: 10_000, sides });
  mm.close();
  // Two of Akane's pilots queue for Cinder on opposite sides before either has fought there: the
  // match starts with both factions, Kite (attacking) goes in first and takes the Ashen side for
  // the account, and Rook stays out.
  const kite = { ...h.pilot('Kite', 'ashen', 'cinder'), account: key };
  const rook = { ...h.pilot('Rook', 'compact', 'cinder'), account: key };
  assert.ok(mm.join(kite, 'cinder', 'sector').ok);
  assert.ok(mm.join(rook, 'cinder', 'sector').ok, 'nobody has taken a side yet');
  const [b] = h.battles.campaignMatches('cinder');
  assert.deepStrictEqual([b.attacker, b.defender, kite.battle, rook.battle], ['ashen', 'compact', b.id, null]);
  assert.strictEqual(A.lockOn(g, key, 'cinder', h.now()).faction, 'ashen');
  const refused = h.sent.find(([n, m]) => n === 'Rook' && m.type === 'error');
  assert.match(refused[1].reason, /^your account took the ashen's side on Cinder this campaign \(Kite\)/);
  assert.deepStrictEqual(mm.list(), {}, 'and out of the queue');
  assert.match(mm.join(rook, 'cinder', 'sector').reason, /took the ashen's side on Cinder/, 'queueing again is refused at once');
  assert.ok(mm.join({ ...h.pilot('Guest', 'compact', 'cinder'), account: null }, 'cinder', 'sector').ok, 'other players are free');
  W.setDemo(false);
});
