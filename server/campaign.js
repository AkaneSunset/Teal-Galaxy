// Planet campaigns: every contested planet is fought over in week-long campaigns, Helldivers-style.
// Pilots of the factions in a planet's campaign queue for game modes there; every match their
// faction wins scores campaign points (by how long the mode takes), and when the week ends the
// faction with the most points holds the planet for the next one. A tie, or no points at all,
// leaves it with its holder. Sectors are notional now: each running match is shown as one.
//
// A week runs from Monday 12:00 US Eastern time to the next, with the last day (the final push)
// counting double. The demo war runs a campaign every DEMO_CYCLE_MS instead, so a whole one can be
// play-tested in a sitting. Entry: the holder, and every faction with CARRIER_SHARE of the
// system's orbit when the campaign starts.
//
// Pure state + functions taking `now`, like war.js; all of it is in the galaxy state as
// g.war.campaigns (planet id -> campaign). createMatchmaking() at the bottom holds the queues
// (in memory only) and starts matches through the battles of battle.js.

const F = require('./factions');
const W = require('./war');

const DAY = 24 * 3600_000;
const WEEK = 7 * DAY;
const DEMO_CYCLE_MS = 30 * 60_000; // the demo war's campaigns...
const DEMO_FINAL_MS = 5 * 60_000; // ...and their final push
const FINAL_MS = DAY; // the final push: wins count double
const ZONE = 'America/New_York';
const AI_SHARE = 0.5; // a win against AI only scores this much

// Game modes. `points`: about 1 per 2.5 minutes of a typical match. Only Sector Battles is built
// and Sector Defense so far; the others show on the Campaign screen as coming. `alwaysAi`: fought
// against AI troops only, so a win always scores half.
const MODES = {
  sector: { name: 'Sector Battles', kind: 'RTS conquest', points: 10, minutes: 25, sides: 8, open: true },
  supremacy: { name: 'Supremacy', kind: 'FPS control points, then a ship assault', points: 8, minutes: 20, sides: 16, open: false },
  space: { name: 'Space Battles', kind: 'Starfighter assault', points: 6, minutes: 15, sides: 12, open: false },
  facility: { name: 'Facility Battles', kind: 'FPS arena', points: 4, minutes: 10, sides: 8, open: false },
  defense: { name: 'Sector Defense', kind: 'FPS co-op waves against AI', points: 6, minutes: 15, sides: 4, open: true, alwaysAi: true },
};

// Each planet's built-in bonus for whoever holds it, in one mode.
const BONUSES = {
  mining: { name: 'Mining world', mode: 'sector', text: "The holder's commanders start Sector Battles with 15% more mass", mass: 1.15 },
  shipyard: { name: 'Shipyard world', mode: 'space', text: "The holder's fighters have 10% more hull in Space Battles" },
  fortress: { name: 'Fortress world', mode: 'defense', text: 'The holder gets an extra respawn wave in Sector Defense and Facility Battles' },
};
const BONUS_IDS = Object.keys(BONUSES);

function fail(reason) {
  return { ok: false, reason };
}

// The planet's bonus: the same planet always has the same one.
function bonusOf(planetId) {
  return BONUS_IDS[W.hash(`bonus/${planetId}`) % BONUS_IDS.length];
}

// Milliseconds US Eastern time is ahead of UTC at `t` (negative: -4 or -5 hours).
function zoneOffset(t) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', { timeZone: ZONE, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' })
      .formatToParts(new Date(t))
      .filter((p) => p.type !== 'literal')
      .map((p) => [p.type, Number(p.value)]),
  );
  const local = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return Math.round((local - Math.floor(t / 1000) * 1000) / 60_000) * 60_000;
}

// When the campaign running at `t` started: the last Monday 12:00 US Eastern (or demo cycle).
function weekStart(t, demo = W.isDemo()) {
  if (demo) return Math.floor(t / DEMO_CYCLE_MS) * DEMO_CYCLE_MS;
  const local = t + zoneOffset(t);
  const day = Math.floor(local / DAY) * DAY;
  const weekday = (new Date(day).getUTCDay() + 6) % 7; // Monday 0
  let start = day - weekday * DAY + 12 * 3600_000;
  if (start > local) start -= WEEK;
  // Back to UTC with the offset that held then (the clocks may have changed since).
  let utc = start - zoneOffset(start - zoneOffset(t));
  if (utc > t) utc -= WEEK;
  return utc;
}

function length(demo = W.isDemo()) {
  return demo ? DEMO_CYCLE_MS : WEEK;
}

function finalMs(demo = W.isDemo()) {
  return demo ? DEMO_FINAL_MS : FINAL_MS;
}

// The planets campaigns are fought over: every contested planet that isn't a capital world.
function contested(g) {
  return g.war.planets.filter((wp) => !wp.capital);
}

// Who enters a planet's campaign: its holder, and every faction with CARRIER_SHARE of its orbit.
function entrants(g, wp) {
  const share = W.shares(g, wp.system);
  const out = Object.keys(F.FACTIONS).filter((f) => share[f] + 1e-9 >= W.CARRIER_SHARE);
  if (wp.owner && !out.includes(wp.owner)) out.unshift(wp.owner);
  return out;
}

function newCampaign(g, wp, now) {
  const start = weekStart(now);
  const who = entrants(g, wp);
  return {
    planet: wp.id,
    startsAt: start,
    endsAt: start + length(),
    finalAt: start + length() - finalMs(),
    holder: wp.owner ?? null,
    entrants: who,
    points: Object.fromEntries(who.map((f) => [f, 0])),
    wins: Object.fromEntries(who.map((f) => [f, 0])),
    matches: 0,
    bonus: bonusOf(wp.id),
  };
}

// The week is over: the faction with the most points takes the planet (all its sectors). A tie at
// the top, or no points, leaves it with its holder.
function resolve(g, c, now) {
  const wp = W.planet(g, c.planet);
  if (!wp) return null;
  const best = Math.max(0, ...Object.values(c.points));
  const top = Object.keys(c.points).filter((f) => c.points[f] === best);
  const winner = best > 0 && top.length === 1 ? top[0] : wp.owner ?? null;
  const name = wp.name;
  if (winner && winner !== wp.owner) {
    const lost = wp.owner;
    for (const s of wp.sectors) s.owner = winner;
    wp.owner = winner;
    W.warLog(g, `${F.FACTIONS[winner].name} won the campaign for ${name}${lost ? `, taking it from ${F.the(lost)}` : ''} (${best} points)`, now);
  } else if (winner) W.warLog(g, `${F.FACTIONS[winner].name} held ${name} through its campaign`, now);
  else W.warLog(g, `Nobody won the campaign for ${name}`, now);
  return winner;
}

// Starts and ends campaigns as the weeks turn. Returns whether anything changed.
function tick(g, now = Date.now()) {
  g.war.campaigns ||= {};
  let changed = false;
  for (const wp of contested(g)) {
    const c = g.war.campaigns[wp.id];
    if (c && now < c.endsAt && c.endsAt - c.startsAt === length()) continue;
    if (c && now >= c.endsAt) resolve(g, c, now);
    g.war.campaigns[wp.id] = newCampaign(g, wp, now);
    changed = true;
  }
  return changed;
}

// What a won match scores: the mode's points, half against AI only, double in the final push.
function worth(c, mode, vsAi, now) {
  return MODES[mode].points * (vsAi || MODES[mode].alwaysAi ? AI_SHARE : 1) * (now >= c.finalAt ? 2 : 1);
}

// A match on a planet ended: its winner scores for the campaign (if it's in it). Returns the points.
// `extra`: points on top of the mode's (Sector Defense's bonus round), doubled in the final push too.
function score(g, planetId, mode, winner, vsAi, now = Date.now(), extra = 0) {
  const c = g.war.campaigns?.[planetId];
  if (!c || !winner || !c.entrants.includes(winner) || now >= c.endsAt) return 0;
  const pts = worth(c, mode, vsAi, now) + extra * (now >= c.finalAt ? 2 : 1);
  c.points[winner] += pts;
  c.wins[winner] += 1;
  c.matches += 1;
  return pts;
}

// --- Matchmaking ----------------------------------------------------------------------------

const QUEUE_WAIT_MS = 60_000; // a lone faction's pilots wait this long for opponents, then fight AI...
const DEMO_QUEUE_WAIT_MS = 10_000; // ...or this long in the demo war
const FILL_MS = 1000;

// The queues of every planet: pilots wait for a mode's match there, and when one can start (two
// factions queued, or one that has waited long enough to fight AI) they go in together; a pilot
// whose side of a running match has room joins it at once. Sector Defense squads are one faction:
// they go in when four are queued, or after the wait with however many there are.
// `battles` is battle.js createBattles(), `defenses` defense.js createDefenses();
// `where(me)` says where a pilot is (the planet their carrier is over); `factionOf(me)` their side.
function createMatchmaking({ galaxy, now = Date.now, battles, defenses = null, where, factionOf, send, changed, wait = null }) {
  const queues = new Map(); // planet id -> [{ me, faction, mode, since }]

  function waitMs() {
    return wait ?? (W.isDemo() ? DEMO_QUEUE_WAIT_MS : QUEUE_WAIT_MS);
  }

  function entryOf(me) {
    for (const [planet, q] of queues) {
      const e = q.find((x) => x.me === me);
      if (e) return { planet, e };
    }
    return null;
  }

  function tell(me) {
    const on = entryOf(me);
    send(me, on ? { type: 'campaign_queued', planet: on.planet, mode: on.e.mode, since: on.e.since } : { type: 'campaign_queued', planet: null });
  }

  // campaign_queue: a pilot aboard a carrier over the planet, of a faction in its campaign, waits
  // for one of its open modes. One queue at a time.
  function join(me, planetId, mode) {
    const g = galaxy();
    const faction = factionOf(me);
    if (!faction) return fail('choose a faction first');
    const wp = W.planet(g, String(planetId));
    const c = wp && g.war.campaigns?.[wp.id];
    if (!c) return fail('no campaign on that planet');
    if (!MODES[mode]) return fail('no such game mode');
    if (!MODES[mode].open) return fail(`${MODES[mode].name} isn't in the game yet`);
    if (!c.entrants.includes(faction)) return fail(`${F.the(faction)} isn't in the campaign for ${wp.name}: it needs ${Math.round(W.CARRIER_SHARE * 100)}% of the orbit when the week starts`);
    if (where(me).over !== wp.id) return fail(`bring your carrier into ${F.the(faction)}'s naval zone over ${wp.name} to queue`);
    if (me.battle || me.defense) return fail("you're in a match already");
    if (mode === 'defense' && !defenses) return fail('Sector Defense is off on this server');
    leave(me, true);
    if (!queues.has(wp.id)) queues.set(wp.id, []);
    queues.get(wp.id).push({ me, faction, mode, since: now() });
    tell(me);
    changed();
    fill();
    return { ok: true };
  }

  // campaign_unqueue, or the pilot went away or into a match.
  function leave(me, quiet = false) {
    let was = false;
    for (const [planet, q] of queues) {
      const left = q.filter((x) => x.me !== me);
      if (left.length !== q.length) was = true;
      if (left.length) queues.set(planet, left);
      else queues.delete(planet);
    }
    if (was && !quiet) {
      tell(me);
      changed();
    }
    return { ok: true };
  }

  // Into a match: out of the queue, into the battle on their side (or the defense squad).
  function place(e, b, side) {
    leave(e.me, true);
    const r = side === 'squad' ? defenses.enlist(e.me, b) : battles.enlistCampaign(e.me, b, side, e.faction);
    tell(e.me);
    return r;
  }

  // Sector Defense on a planet: backfill a squad of the same faction with room, else start a squad
  // of up to four once four are queued or the first has waited long enough.
  function fillDefense(g, wp, c, t) {
    const queued = (queues.get(wp.id) || []).filter((e) => e.mode === 'defense').sort((x, y) => x.since - y.since);
    for (const e of queued) {
      const d = defenses.running(wp.id).find((m) => m.faction === e.faction && m.phase === 'break' && defenses.room(m));
      if (d) place(e, d, 'squad');
    }
    const by = new Map();
    for (const e of (queues.get(wp.id) || []).filter((x) => x.mode === 'defense').sort((x, y) => x.since - y.since)) {
      if (!by.has(e.faction)) by.set(e.faction, []);
      by.get(e.faction).push(e);
    }
    for (const [faction, list] of by) {
      if (list.length < MODES.defense.sides && t - list[0].since < waitMs()) continue;
      // The enemy: the holder's troops, or (for the holder's own squads) another faction's in the campaign.
      const enemy = wp.owner && wp.owner !== faction ? wp.owner : c.entrants.find((f) => f !== faction) ?? null;
      const d = defenses.start(wp.id, wp.name, faction, enemy);
      for (const e of list.slice(0, MODES.defense.sides)) place(e, d, 'squad');
      W.warLog(g, `A ${F.FACTIONS[faction].name} squad is holding a sector of ${wp.name} against ${enemy ? F.the(enemy) : 'the militia'}`, t);
      changed();
    }
  }

  // Every FILL_MS: backfill running matches, then start new ones.
  function fill() {
    const g = galaxy();
    const t = now();
    for (const [planetId, q] of [...queues]) {
      const c = g.war.campaigns?.[planetId];
      const wp = W.planet(g, planetId);
      // Pilots who are no longer where they queued, or whose faction left, drop out.
      for (const e of q.slice()) if (!c || where(e.me).over !== planetId || factionOf(e.me) !== e.faction || e.me.battle || e.me.defense) leave(e.me);
      if (c && wp && defenses) fillDefense(g, wp, c, t);
      const queued = (queues.get(planetId) || []).filter((e) => e.mode === 'sector');
      if (!c || !wp || !queued.length) continue;
      // Backfill: a running match here with room on this pilot's side.
      for (const e of queued) {
        const b = battles.campaignMatches(planetId).find((m) => (m.attacker === e.faction || m.defender === e.faction) && battles.room(m, m.attacker === e.faction ? 'a' : 'd'));
        if (b) place(e, b, b.attacker === e.faction ? 'a' : 'd');
      }
      const left = (queues.get(planetId) || []).filter((e) => e.mode === 'sector');
      if (!left.length) continue;
      // By faction, longest waiting first.
      const by = new Map();
      for (const e of left.sort((x, y) => x.since - y.since)) {
        if (!by.has(e.faction)) by.set(e.faction, []);
        by.get(e.faction).push(e);
      }
      const factions = [...by.keys()];
      let attacker;
      let defender;
      if (factions.length >= 2) {
        // Two factions queued: the holder defends if it's one of them.
        defender = factions.includes(wp.owner) ? wp.owner : factions[1];
        attacker = factions.find((f) => f !== defender);
      } else if (t - by.get(factions[0])[0].since >= waitMs()) {
        // Nobody to fight: the AI of the holder (or of another faction in the campaign) defends.
        attacker = factions[0];
        defender = wp.owner && wp.owner !== attacker ? wp.owner : c.entrants.find((f) => f !== attacker) ?? null;
      } else continue;
      const b = battles.startCampaign(wp, attacker, defender);
      for (const e of (by.get(attacker) || []).slice(0, MODES.sector.sides)) place(e, b, 'a');
      for (const e of (by.get(defender) || []).slice(0, MODES.sector.sides)) place(e, b, 'd');
      W.warLog(g, `A Sector Battle on ${wp.name}: ${F.FACTIONS[attacker].name} against ${defender ? F.the(defender) : 'the militia'}`, t);
      changed();
    }
  }
  const filler = setInterval(fill, FILL_MS);

  // What everyone sees of the queues: per planet and mode, how many of each faction wait.
  function list() {
    const out = {};
    for (const [planet, q] of queues) {
      out[planet] ||= {};
      for (const e of q) {
        out[planet][e.mode] ||= {};
        out[planet][e.mode][e.faction] = (out[planet][e.mode][e.faction] || 0) + 1;
      }
    }
    return out;
  }

  function close() {
    clearInterval(filler);
  }

  return { join, leave, fill, list, close, queues };
}

module.exports = {
  MODES,
  BONUSES,
  DEMO_CYCLE_MS,
  DEMO_FINAL_MS,
  AI_SHARE,
  QUEUE_WAIT_MS,
  DEMO_QUEUE_WAIT_MS,
  bonusOf,
  zoneOffset,
  weekStart,
  entrants,
  newCampaign,
  resolve,
  tick,
  worth,
  score,
  createMatchmaking,
};
