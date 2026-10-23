// Faction orders: each faction's High Command issues orders, as Helldivers 2's Major Orders, in
// two-week operations of three orders (the demo war: an hour of three). An order has a briefing in
// the faction's own voice, a task list, a deadline and a reward; win two of an operation's three and
// the operation's reward is the faction's too. Now and then one slot is a Coma offensive: a single
// order shared by all three player factions against the Coma Conglomerate.
//
// Normal play is the contribution: winning campaign matches, leading or holding planets' campaigns,
// Builders' donations to war supply. Targets scale with how many players a faction has, and the
// briefing says how (no hidden maths). Progress is public, and each player's share is kept, for a
// receipt and for the rewards. The Coma director (an admin) can issue an order by hand.
//
// State in g.war.orders: { op: the operation running, archive: past ones }. Pure functions of the
// galaxy and `now`, like campaign.js.

const C = require('./campaign');
const F = require('./factions');
const W = require('./war');

const DAY = 24 * 3600_000;
const OP_SLOTS = 3;
const DEMO_OP_MS = 2 * C.DEMO_CYCLE_MS; // the demo war: three 20-minute orders
const ARCHIVE_MAX = 12;
const PLAYER_FACTIONS = ['compact', 'ashen', 'luminar'];
const REWARD = { order: 250, member: 50, operation: 750 }; // credits: to a won order's contributors, to every member, for a won operation
const COMA_CHANCE = 0.5; // an operation has a Coma offensive in one of its slots this often

// Each faction's High Command, its voice for briefings and outcomes.
const VOICES = {
  compact: { issuer: 'Terran High Command', open: 'By order of Terran High Command:', won: 'Compact discipline prevails. Well done, citizens.', lost: 'A tactical repositioning. The Compact endures, and so will you.' },
  ashen: { issuer: "The Collective's Choir", open: 'The Choir sings a new verse:', won: 'The ash settles on the fallen. The Collective is pleased.', lost: 'Every defeat feeds the fire. Burn brighter.' },
  luminar: { issuer: 'The Accord Council', open: 'The Accord Council has reached consensus:', won: 'Light finds the way. The Council gives thanks.', lost: 'Even the brightest star dims before it rises again.' },
  coma: { issuer: 'Allied Command', open: 'WARNING: a Coma Conglomerate offensive has been detected. All factions:', won: "The Coma's advance is broken, for now.", lost: 'The Coma tightens its grip on the lanes.' },
};
const ADJ = ['Iron', 'Silent', 'Burning', 'Pale', 'Distant', 'Steadfast', 'Hollow', 'Bright', 'Crimson', 'Frozen', 'Final', 'Patient'];
const NOUN = ['Anvil', 'Tide', 'Lantern', 'Harvest', 'Meridian', 'Vigil', 'Spear', 'Covenant', 'Ember', 'Bastion', 'Horizon', 'Requiem'];

const TASK_TYPES = ['lead', 'hold', 'wins', 'donate', 'coma_wins'];

function fail(reason) {
  return { ok: false, reason };
}

// When the operation running at `now` began, and how long it runs: two campaign weeks from a Monday
// noon (US Eastern), or an hour in the demo war.
function opWindow(now) {
  if (W.isDemo()) {
    const start = Math.floor(now / DEMO_OP_MS) * DEMO_OP_MS;
    return { start, end: start + DEMO_OP_MS };
  }
  const ws = C.weekStart(now);
  const start = Math.round(ws / (7 * DAY)) % 2 === 0 ? ws : C.weekStart(ws - 1);
  return { start, end: C.weekStart(start + 14 * DAY + 12 * 3600_000) };
}

function slotWindow(op, i) {
  const len = (op.endsAt - op.startsAt) / OP_SLOTS;
  return { start: op.startsAt + Math.round(i * len), end: op.startsAt + Math.round((i + 1) * len) };
}

// How many of a faction's players there are, the way targets scale with them.
function members(g, faction) {
  const pilots = Object.values(g.pilots || {}).filter((p) => p.faction === faction).length;
  const builders = Object.values(g.bases || {}).filter((b) => b.faction === faction).length;
  return { pilots, builders };
}

const rnd = (seed) => () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

const pick = (r, list) => list[Math.floor(r() * list.length) % list.length];

// --- Making orders ------------------------------------------------------------------------------

function planetsWithCampaigns(g) {
  return g.war.planets.filter((wp) => g.war.campaigns?.[wp.id]);
}

// An order for `faction` in slot `slot` of the operation, from the war as it stands: the slots go
// offensive (lead a planet's campaign and win matches there), hold the line (keep your planets'
// campaigns), and war effort (matches in one mode, and the Builders' donations).
function makeOrder(g, op, faction, slot, now) {
  const r = rnd(W.hash(`${op.id}/${faction}/${slot}`));
  const m = members(g, faction);
  const wins = 3 + 2 * Math.min(12, m.pilots); // the published formula: 3, and 2 for each pilot (up to 12)
  const donate = 60 + 30 * Math.min(10, m.builders); // 60 War Merit, and 30 for each Builder (up to 10)
  const camps = planetsWithCampaigns(g).filter((wp) => g.war.campaigns[wp.id].entrants.includes(faction));
  const mine = camps.filter((wp) => wp.owner === faction);
  const theirs = camps.filter((wp) => wp.owner !== faction);
  const kind = ['offensive', 'hold', 'effort'][(slot + (W.hash(op.id) % 3)) % 3];
  const tasks = [];
  let title;
  let why;
  if (kind === 'offensive' && theirs.length) {
    const wp = pick(r, theirs);
    title = `Take ${wp.name}`;
    why = `${wp.name} is held by ${wp.owner ? F.the(wp.owner) : 'nobody'}. Lead its campaign when this order ends, and win battles there.`;
    tasks.push({ type: 'lead', planet: wp.id, label: `Lead the campaign for ${wp.name} at the deadline` });
    tasks.push({ type: 'wins', planet: wp.id, need: Math.ceil(wins / 2), label: `Win ${Math.ceil(wins / 2)} matches on ${wp.name}` });
  } else if (kind === 'hold' && mine.length) {
    const keep = mine.slice().sort(() => r() - 0.5).slice(0, 2);
    title = `Hold ${keep.map((wp) => wp.name).join(' and ')}`;
    why = `The enemy is massing against our worlds. No other faction may outscore us in their campaigns.`;
    for (const wp of keep) tasks.push({ type: 'hold', planet: wp.id, label: `Keep the lead (or a tie) in ${wp.name}'s campaign at the deadline` });
    tasks.push({ type: 'donate', need: donate, label: `Builders: donate ${donate} War Merit of goods to war supply` });
  } else {
    const mode = pick(r, Object.keys(C.MODES).filter((k) => C.MODES[k].open));
    title = `${C.MODES[mode].name} drive`;
    why = `The front needs pressure everywhere. Every win counts, and every crate our Builders send.`;
    tasks.push({ type: 'wins', mode, need: wins, label: `Win ${wins} ${C.MODES[mode].name} matches, anywhere` });
    tasks.push({ type: 'donate', need: donate, label: `Builders: donate ${donate} War Merit of goods to war supply` });
  }
  // No Builders to donate: the pilots' wins stand in for it (an order must be winnable).
  for (let i = 0; i < tasks.length; i++) {
    if (tasks[i].type === 'donate' && m.builders === 0 && !tasks.some((t) => t.type === 'wins' && !t.planet && !t.mode)) tasks[i] = { type: 'wins', need: wins, label: `Win ${wins} matches, any kind, anywhere` };
  }
  const scale = [`3 wins and 2 more for each of our ${m.pilots} pilot${m.pilots === 1 ? '' : 's'}`];
  if (tasks.some((t) => t.type === 'donate')) scale.push(`60 War Merit and 30 for each of our ${m.builders} Builder${m.builders === 1 ? '' : 's'}`);
  const w = slotWindow(op, slot);
  return {
    id: `${op.id}-${faction}-${slot + 1}`,
    slot,
    faction,
    kind: 'faction',
    issuer: VOICES[faction].issuer,
    title,
    briefing: `${VOICES[faction].open} ${why} Targets: ${scale.join('; ')}.`,
    tasks: tasks.map((t) => ({ ...t, have: 0, done: false })),
    startsAt: Math.max(w.start, Math.min(now, w.end)),
    endsAt: w.end,
    status: 'active',
    reward: REWARD.order,
    contrib: {},
    outcome: null,
  };
}

// The Coma offensive: one order for all three player factions, against the Coma.
function makeComaOrder(g, op, slot, now) {
  const pilots = PLAYER_FACTIONS.reduce((n, f) => n + members(g, f).pilots, 0);
  const need = 5 + 2 * Math.min(30, pilots);
  const held = planetsWithCampaigns(g).filter((wp) => wp.owner === 'coma');
  const w = slotWindow(op, slot);
  const tasks = [{ type: 'coma_wins', need, label: `All factions: win ${need} matches against the Coma` }];
  if (held.length) tasks.push({ type: 'lead', planet: held[0].id, any: true, label: `Any player faction leads the campaign for ${held[0].name} at the deadline` });
  return {
    id: `${op.id}-coma-${slot + 1}`,
    slot,
    faction: null,
    kind: 'coma',
    issuer: VOICES.coma.issuer,
    title: 'Break the Coma offensive',
    briefing: `${VOICES.coma.open} Coma armadas are pushing on every front. Set your war aside and turn your guns on them. Target: 5 wins and 2 more for each of the ${pilots} player-faction pilots.`,
    tasks: tasks.map((t) => ({ ...t, have: 0, done: false })),
    startsAt: Math.max(w.start, Math.min(now, w.end)),
    endsAt: w.end,
    status: 'active',
    reward: REWARD.order,
    contrib: {},
    outcome: null,
  };
}

function newOperation(g, now) {
  const { start, end } = opWindow(now);
  const id = `op${Math.floor(start / 60_000)}`;
  const r = rnd(W.hash(id));
  const hasComa = (planetsWithCampaigns(g).some((wp) => wp.owner === 'coma') || r() < 0.2) && r() < COMA_CHANCE;
  return {
    id,
    name: `Operation ${pick(r, ADJ)} ${pick(r, NOUN)}`,
    startsAt: start,
    endsAt: end,
    comaSlot: hasComa ? 1 + Math.floor(r() * 2) : -1, // the second or third order, if any
    slot: -1,
    factions: Object.fromEntries(PLAYER_FACTIONS.map((f) => [f, { orders: [], won: 0, lost: 0, status: 'active' }])),
    coma: [], // Coma offensive orders (shared)
  };
}

// The orders a faction has in an operation, its own and any Coma offensive, in slot order.
function ordersOf(op, faction) {
  return [...op.factions[faction].orders, ...op.coma].sort((a, b) => a.slot - b.slot);
}

function active(g) {
  const op = g.war.orders?.op;
  if (!op) return [];
  const out = op.coma.filter((o) => o.status === 'active');
  for (const f of PLAYER_FACTIONS) for (const o of op.factions[f].orders) if (o.status === 'active') out.push(o);
  return out;
}

// --- Progress -----------------------------------------------------------------------------------

function credit(o, name, n) {
  if (name) o.contrib[name] = (o.contrib[name] || 0) + n;
}

// A match was won. `winner`/`loser`: factions (null for the militia); `names`: the winning side's
// players, credited for the orders it counts toward.
function matchWon(g, { planet, mode, winner, loser = null, names = [] }, now = Date.now()) {
  let changed = false;
  for (const o of active(g)) {
    if (now >= o.endsAt) continue;
    for (const t of o.tasks) {
      const counts =
        (t.type === 'wins' && o.faction === winner && (!t.mode || t.mode === mode) && (!t.planet || t.planet === planet)) ||
        (t.type === 'coma_wins' && PLAYER_FACTIONS.includes(winner) && loser === 'coma');
      if (!counts || t.done) continue;
      t.have += 1;
      if (t.have >= t.need) t.done = true;
      for (const n of names) credit(o, n, 1);
      changed = true;
    }
  }
  return changed;
}

// A Builder of `faction` donated goods worth `merit` War Merit to war supply.
function donated(g, faction, builder, merit, now = Date.now()) {
  let changed = false;
  for (const o of active(g)) {
    if (now >= o.endsAt || o.faction !== faction) continue;
    for (const t of o.tasks) {
      if (t.type !== 'donate' || t.done) continue;
      t.have += merit;
      if (t.have >= t.need) t.done = true;
      credit(o, builder, Math.max(1, Math.round(merit / 10)));
      changed = true;
    }
  }
  return changed;
}

// The state tasks (leading or holding a planet's campaign) as they stand now.
function standings(g, o) {
  for (const t of o.tasks) {
    if (t.type !== 'lead' && t.type !== 'hold') continue;
    const c = g.war.campaigns?.[t.planet];
    if (!c) {
      t.done = false;
      continue;
    }
    const pts = c.points || {};
    const best = Math.max(0, ...Object.values(pts));
    const leaders = Object.keys(pts).filter((f) => pts[f] === best && best > 0);
    if (t.type === 'lead') {
      const who = t.any ? PLAYER_FACTIONS : [o.faction];
      t.done = leaders.length === 1 && who.includes(leaders[0]);
      t.standing = leaders.length === 1 ? leaders[0] : null;
    } else {
      // Hold: nobody outscores us (a tie keeps the holder's planet).
      t.done = (pts[o.faction] || 0) >= best;
      t.standing = leaders.length === 1 ? leaders[0] : null;
    }
  }
}

// --- The operation's clock ----------------------------------------------------------------------

function voice(o) {
  return VOICES[o.kind === 'coma' ? 'coma' : o.faction];
}

// An order's deadline: won if every task is done, else failed; contributors are paid, and the
// faction hears the outcome in its High Command's voice.
function close(g, op, o, pay, now) {
  standings(g, o);
  const won = o.tasks.every((t) => t.done);
  o.status = won ? 'won' : 'failed';
  o.outcome = won ? voice(o).won : voice(o).lost;
  const factions = o.kind === 'coma' ? PLAYER_FACTIONS : [o.faction];
  for (const f of factions) {
    const rec = op.factions[f];
    if (won) rec.won += 1;
    else rec.lost += 1;
  }
  if (won) {
    for (const name of Object.keys(o.contrib)) pay(name, REWARD.order, `${o.title}: order won`);
    for (const f of factions) payFaction(g, f, REWARD.member, pay, `${o.title}: order won`);
  }
  const who = o.kind === 'coma' ? 'All factions' : F.FACTIONS[o.faction].name;
  W.warLog(g, `${o.issuer}: "${o.title}" ${won ? 'accomplished' : 'failed'}. ${o.outcome}${won ? ` ${who}: +${REWARD.member} credits to every member, +${REWARD.order} more to the ${Object.keys(o.contrib).length} who fought for it.` : ''}`, now);
}

function payFaction(g, faction, credits, pay, why) {
  for (const [name, p] of Object.entries(g.pilots || {})) if (p.faction === faction) pay(name, credits, why);
  for (const [name, b] of Object.entries(g.bases || {})) if (b.faction === faction) pay(name, credits, why);
}

// The operation is over: a faction that won most of its orders earns its reward and a commendation.
function finishOperation(g, op, pay, now) {
  const archive = { id: op.id, name: op.name, startsAt: op.startsAt, endsAt: op.endsAt, factions: {} };
  for (const f of PLAYER_FACTIONS) {
    const rec = op.factions[f];
    rec.status = rec.won >= 2 ? 'won' : 'failed';
    if (rec.status === 'won') {
      payFaction(g, f, REWARD.operation, pay, `${op.name} won`);
      for (const p of [...Object.values(g.pilots || {}), ...Object.values(g.bases || {})]) {
        if (p.faction !== f) continue;
        p.commendations ||= [];
        p.commendations.push(op.name);
      }
    }
    W.warLog(g, `${VOICES[f].issuer}: ${op.name} ${rec.status === 'won' ? `won, ${rec.won} of 3 orders. +${REWARD.operation} credits and a commendation to every member.` : `ended with ${rec.won} of 3 orders won. No reward this time.`}`, now);
    archive.factions[f] = { won: rec.won, status: rec.status, orders: ordersOf(op, f).map((o) => ({ title: o.title, kind: o.kind, status: o.status, outcome: o.outcome, contributors: Object.keys(o.contrib).length })) };
  }
  g.war.orders.archive.unshift(archive);
  g.war.orders.archive.length = Math.min(g.war.orders.archive.length, ARCHIVE_MAX);
}

// Runs the operations: starts one, issues each slot's orders when it opens, keeps the standings,
// closes orders at their deadlines and the operation at its end. `pay(name, credits, why)` pays a
// player (a pilot or a Builder). Returns whether anything changed.
function tick(g, pay = () => {}, now = Date.now()) {
  g.war.orders ||= { op: null, archive: [] };
  let changed = false;
  let op = g.war.orders.op;
  if (op && now >= op.endsAt) {
    for (const o of [...op.coma, ...PLAYER_FACTIONS.flatMap((f) => op.factions[f].orders)]) if (o.status === 'active') close(g, op, o, pay, now);
    finishOperation(g, op, pay, now);
    op = g.war.orders.op = null;
    changed = true;
  }
  if (!op) {
    op = g.war.orders.op = newOperation(g, now);
    W.warLog(g, `${op.name} begins: three orders over ${W.isDemo() ? 'the hour' : 'two weeks'}. Win two to win the operation.`, now);
    changed = true;
  }
  // Close the orders whose time is up, then open the slot now running.
  for (const o of [...op.coma, ...PLAYER_FACTIONS.flatMap((f) => op.factions[f].orders)]) {
    if (o.status === 'active' && now >= o.endsAt) {
      close(g, op, o, pay, now);
      changed = true;
    }
  }
  const slot = Math.min(OP_SLOTS - 1, Math.floor(((now - op.startsAt) * OP_SLOTS) / (op.endsAt - op.startsAt)));
  if (slot > op.slot) {
    op.slot = slot;
    if (slot === op.comaSlot) {
      const o = makeComaOrder(g, op, slot, now);
      op.coma.push(o);
      W.warLog(g, `${o.issuer}: "${o.title}". ${o.briefing}`, now);
    } else {
      for (const f of PLAYER_FACTIONS) {
        const o = makeOrder(g, op, f, slot, now);
        op.factions[f].orders.push(o);
        W.warLog(g, `${o.issuer} issues "${o.title}"`, now);
      }
    }
    changed = true;
  }
  for (const o of active(g)) {
    const before = JSON.stringify(o.tasks);
    standings(g, o);
    if (JSON.stringify(o.tasks) !== before) changed = true;
  }
  return changed;
}

// The Coma director (an admin) issues an order by hand: for one faction (or 'all', a Coma
// offensive), replacing the one running now. `tasks`: [{type, need?, planet?, mode?, label?}], or
// none for one made the usual way.
function issue(g, { faction, title, briefing, tasks }, now = Date.now()) {
  const op = g.war.orders?.op;
  if (!op || op.slot < 0) return fail('no operation is running yet');
  const all = faction === 'all';
  if (!all && !PLAYER_FACTIONS.includes(faction)) return fail('no such faction');
  let o = all ? makeComaOrder(g, op, op.slot, now) : makeOrder(g, op, faction, op.slot, now);
  if (Array.isArray(tasks) && tasks.length) {
    const clean = [];
    for (const t of tasks.slice(0, 4)) {
      if (!TASK_TYPES.includes(t?.type)) return fail(`no such task type: ${t?.type}`);
      if ((t.type === 'lead' || t.type === 'hold') && !W.planet(g, String(t.planet))) return fail('no such planet');
      if (t.mode && !C.MODES[t.mode]) return fail('no such mode');
      const need = ['wins', 'donate', 'coma_wins'].includes(t.type) ? Math.max(1, Math.min(10_000, Math.floor(Number(t.need) || 1))) : undefined;
      clean.push({ type: t.type, planet: t.planet ? String(t.planet) : undefined, mode: t.mode || undefined, need, any: all || undefined, label: String(t.label || t.type).slice(0, 120), have: 0, done: false });
    }
    o.tasks = clean;
  }
  if (title) o.title = String(title).slice(0, 80);
  if (briefing) o.briefing = String(briefing).slice(0, 600);
  o.id += `-gm${now % 100000}`;
  o.byHand = true;
  // It replaces what's running in this slot for those it's for.
  const lists = all ? [op.coma, ...PLAYER_FACTIONS.map((f) => op.factions[f].orders)] : [op.factions[faction].orders];
  for (const list of lists) {
    for (let i = list.length - 1; i >= 0; i--) if (list[i].status === 'active') list.splice(i, 1);
  }
  (all ? op.coma : op.factions[faction].orders).push(o);
  W.warLog(g, `${o.issuer} issues new orders: "${o.title}"`, now);
  return { ok: true, order: o };
}

module.exports = { REWARD, VOICES, PLAYER_FACTIONS, DEMO_OP_MS, opWindow, ordersOf, active, matchWon, donated, tick, issue };
