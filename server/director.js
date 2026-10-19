// The Coma Conglomerate's AI director. Coma is nobody's faction to pick: server admins play it,
// and the rest of the time this director does, through armadas (AI fleets) that fight the
// Builders' navies for orbital control. Admins steer it from g.director: pause it, set a master
// scale, fix a faction's intensity, and tell it to push, hold or withdraw in each system. Pure
// state + functions taking `now`, like war.js. Only admins are sent g.director (server.js).
//
// Every DIRECTOR_MS it weighs each player faction's strength (its ground, its orbits, and how many
// of its players are about) and leans hardest on the strongest: intensity 1 for the strongest,
// down to 0.15 for the weakest and quietest. In each system it pushes in, it matches the strongest
// faction there by that faction's intensity, or keeps a patrol where no player fleet is.

const F = require('./factions');
const N = require('./navy');
const W = require('./war');

const DIRECTOR_MS = 5 * 60_000; // the director thinks this often
const ACTIVE_MS = 24 * 3600_000; // a character whose app spoke this recently is active
const SCALE_MAX = 2; // the master scale runs from 0 to this
const PATROL_POWER = 30; // armada power kept over a system no player fleet is in (times scale and mean intensity)
const ARMADA_CAP = 600; // all armadas together, at scale 1
const FLOOR = 0.15; // the automatic intensity of the weakest faction
const ARMADA_MIN = 10; // an admin's own armada, in power
const ARMADA_MAX = 400;
const POSTURES = ['push', 'hold', 'withdraw'];
const HOME = F.FACTIONS.coma.capital; // armadas form up at Comae, and stand down there
const PLAYERS = F.PLAYABLE; // the factions the director plays against

function fail(reason) {
  return { ok: false, reason };
}

const round3 = (x) => Math.round(x * 1000) / 1000;
const each = (fn) => Object.fromEntries(PLAYERS.map((f) => [f, fn(f)]));
const isObject = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
const live = (fl) => fl.status === 'stationed' || fl.status === 'flying';

// The systems that can be fought over: every one that isn't a faction's capital.
function contested(g) {
  return g.war.systems.filter((s) => !s.capitalOf);
}

// Gives a galaxy its director (new galaxies, and saves from before it), or fills in what an older
// one lacks. Every contested system starts at 'push', every faction on automatic.
function ensureDirector(g, now = Date.now()) {
  const fresh = !g.director;
  const d = (g.director ||= {});
  d.paused ??= false;
  d.scale ??= 1;
  d.overrides ||= {};
  d.posture ||= {};
  d.strength ||= {};
  d.auto ||= {};
  d.intensity ||= {};
  for (const f of PLAYERS) {
    d.overrides[f] ??= null;
    d.strength[f] ??= 0;
    d.auto[f] ??= FLOOR;
    d.intensity[f] ??= d.overrides[f] ?? d.auto[f];
  }
  for (const s of contested(g)) d.posture[s.id] ||= 'push';
  d.runAt ??= now + DIRECTOR_MS;
  if (fresh) assess(g, now);
  return d;
}

// --- How strong each player faction is ---------------------------------------------------

function active(g, faction, now) {
  const seen = (r) => r.faction === faction && r.seenAt !== undefined && now - r.seenAt < ACTIVE_MS;
  return Object.values(g.bases || {}).filter(seen).length + Object.values(g.pilots || {}).filter(seen).length;
}

// Each player faction's strength, 0..1: half its share of the sectors that can be fought over,
// three tenths its mean orbital share over the contested systems, and a fifth its share of the
// players active in the last day.
function strengths(g, now) {
  const ground = g.war.planets.filter((p) => !p.capital).flatMap((p) => p.sectors);
  const orbits = contested(g).map((s) => W.shares(g, s.id));
  const players = each((f) => active(g, f, now));
  const everyone = PLAYERS.reduce((a, f) => a + players[f], 0);
  return each((f) => {
    const sectors = ground.length ? ground.filter((s) => s.owner === f).length / ground.length : 0;
    const orbital = orbits.length ? orbits.reduce((a, sh) => a + sh[f], 0) / orbits.length : 0;
    return 0.5 * sectors + 0.3 * orbital + 0.2 * (everyone ? players[f] / everyone : 0);
  });
}

// Weighs the factions again: strength, the automatic intensity that follows from it (1 for the
// strongest, easing to 0.15), and the intensity in use (an admin's override, or the automatic one).
function assess(g, now = Date.now()) {
  const d = g.director;
  const s = strengths(g, now);
  const top = Math.max(...PLAYERS.map((f) => s[f]));
  for (const f of PLAYERS) {
    d.strength[f] = round3(s[f]);
    d.auto[f] = round3(top > 0 ? FLOOR + ((1 - FLOOR) * s[f]) / top : FLOOR);
    d.intensity[f] = d.overrides[f] ?? d.auto[f];
  }
}

// --- Armadas -----------------------------------------------------------------------------

// The power of one ship of a type.
function unit(id) {
  return W.power({ [id]: 1 });
}

// The ships of an armada of about `power`: as many destroyers as fit, then frigates, then enough
// corvettes to cover the rest (with `cover` false, only as many as fit, so it never goes over).
function compose(power, cover = true) {
  const types = Object.keys(N.SHIPS).sort((a, b) => unit(b) - unit(a));
  const ships = {};
  let left = power;
  types.forEach((id, i) => {
    const n = cover && i === types.length - 1 ? Math.ceil(left / unit(id) - 1e-9) : Math.floor(left / unit(id) + 1e-9);
    if (n <= 0) return;
    ships[id] = n;
    left -= n * unit(id);
  });
  return ships;
}

// "2 Destroyers and 3 Frigates"
function shipWords(ships) {
  const parts = W.shipList(ships).split(', ');
  return parts.length > 1 ? `${parts.slice(0, -1).join(', ')} and ${parts.at(-1)}` : parts[0];
}

// The armadas in, or on their way to, a system.
function armadas(g, systemId) {
  return g.war.fleets.filter((fl) => fl.ai && fl.system === systemId && live(fl));
}

function armadaPower(g, systemId) {
  return armadas(g, systemId).reduce((a, fl) => a + W.power(fl.ships), 0);
}

// A player faction's fleets in, or on their way to, a system.
function factionPower(g, systemId, faction) {
  return g.war.fleets.filter((fl) => !fl.ai && fl.faction === faction && fl.system === systemId && live(fl)).reduce((a, fl) => a + W.power(fl.ships), 0);
}

// A new armada forms at Comae and flies to a system, a jump per lane like any fleet. It belongs to
// no Builder: it needs no supplies, and it stands down when it gets home.
function spawn(g, systemId, ships, now, manual = false) {
  const to = W.system(g, systemId);
  const leg = N.travelMs(ships) * W.laneJumps(g, HOME, systemId);
  const fleet = { id: g.war.nextFleetId++, owner: null, faction: 'coma', system: to.id, ships, status: 'flying', arriveAt: now + leg, returnAt: 0, leg, taken: 0, upkeepAt: 0, ai: true };
  if (manual) fleet.manual = true; // an admin sent it: the director leaves it be unless it withdraws
  g.war.fleets.push(fleet);
  W.warLog(g, `A Coma armada of ${shipWords(ships)} is heading for ${to.name}`, now);
  return fleet;
}

// An armada turns round for Comae.
function withdraw(g, fl, now) {
  const where = W.system(g, fl.system).name;
  W.warLog(g, fl.status === 'flying' ? `The Coma armada heading for ${where} is turning back` : `The Coma armada over ${where} is withdrawing`, now);
  W.turnRound(fl, now);
}

// --- The director's turn -----------------------------------------------------------------

// One turn of the director. Withdraw: every armada in the system goes home. Hold: nothing new goes
// in and nothing comes out. Push: it aims for the strongest player faction's power there times that
// faction's intensity and the scale (or a patrol, if no player fleet is there); it sends a new
// armada when it's short by more than a corvette, and calls home its own smallest armadas while
// it has more than 1.25 times what it needs. All armadas together stay under the cap, and when the
// cap bites the systems where the strongest factions are come first. Always the same, given the
// same galaxy and `now`.
function run(g, now = Date.now()) {
  const d = ensureDirector(g, now);
  assess(g, now);
  d.runAt = now + DIRECTOR_MS;
  const mean = PLAYERS.reduce((a, f) => a + d.intensity[f], 0) / PLAYERS.length;
  const plans = [];
  for (const s of contested(g)) {
    if (d.posture[s.id] === 'withdraw') for (const fl of armadas(g, s.id)) withdraw(g, fl, now);
    if (d.posture[s.id] !== 'push') continue;
    const here = PLAYERS.filter((f) => factionPower(g, s.id, f) > 0);
    const target = here.length ? d.scale * Math.max(...here.map((f) => factionPower(g, s.id, f) * d.intensity[f])) : PATROL_POWER * d.scale * mean;
    plans.push({ s, target, lead: here.length ? Math.max(...here.map((f) => d.strength[f])) : -1 });
  }
  for (const { s, target } of plans) {
    let have = armadaPower(g, s.id);
    if (have <= 1.25 * target) continue;
    const spare = armadas(g, s.id).filter((fl) => !fl.manual).sort((a, b) => W.power(a.ships) - W.power(b.ships) || a.id - b.id);
    for (const fl of spare) {
      const p = W.power(fl.ships);
      if (have - p + 1e-9 < target) break;
      withdraw(g, fl, now);
      have -= p;
    }
  }
  let room = ARMADA_CAP * d.scale - g.war.fleets.filter((fl) => fl.ai && live(fl)).reduce((a, fl) => a + W.power(fl.ships), 0);
  plans.sort((a, b) => b.lead - a.lead); // stable, so map order on a tie
  for (const { s, target } of plans) {
    const gap = target - armadaPower(g, s.id);
    if (gap <= unit('corvette') + 1e-9) continue;
    let ships = compose(gap);
    if (W.power(ships) > room) ships = compose(room, false);
    if (!Object.keys(ships).length) continue;
    room -= W.power(ships);
    spawn(g, s.id, ships, now);
  }
  W.recompute(g, now);
  return true;
}

// The director's turn, when it's due and not paused. Called from galaxy.tick(); returns whether
// it ran.
function tick(g, now = Date.now()) {
  const d = g.director || ensureDirector(g, now);
  if (d.paused || now < d.runAt) return false;
  return run(g, now);
}

// --- What admins can do ------------------------------------------------------------------

// director_set: any of `paused` (true/false), `scale` (0..2), `overrides` ({faction: 0..1, or null
// for automatic}) and `posture` ({system id: 'push' | 'hold' | 'withdraw'}). Everything is checked
// before anything changes. Then the director takes its turn at once (while paused, it only weighs
// the factions again and carries out any withdrawal).
function set(g, { paused, scale, overrides, posture } = {}, now = Date.now()) {
  const d = ensureDirector(g, now);
  if (paused != null && typeof paused !== 'boolean') return fail('paused is true or false');
  if (scale != null && !(typeof scale === 'number' && scale >= 0 && scale <= SCALE_MAX)) return fail(`the scale runs from 0 to ${SCALE_MAX}`);
  if (overrides != null) {
    if (!isObject(overrides)) return fail('overrides are a level for each faction');
    for (const [f, v] of Object.entries(overrides)) {
      if (!PLAYERS.includes(f)) return fail(F.FACTIONS[f] ? `${F.the(f)} is the director's own faction` : 'no such faction');
      if (v !== null && !(typeof v === 'number' && v >= 0 && v <= 1)) return fail('an override is a level from 0 to 1, or null for automatic');
    }
  }
  if (posture != null) {
    if (!isObject(posture)) return fail('posture is push, hold or withdraw for each system');
    for (const [id, v] of Object.entries(posture)) {
      const s = W.system(g, id);
      if (!s) return fail('no such system');
      if (s.capitalOf) return fail("capital systems can't be contested");
      if (!POSTURES.includes(v)) return fail('a posture is push, hold or withdraw');
    }
  }
  if (paused != null) d.paused = paused;
  if (scale != null) d.scale = scale;
  if (overrides != null) Object.assign(d.overrides, overrides);
  if (posture != null) Object.assign(d.posture, posture);
  if (!d.paused) run(g, now);
  else {
    assess(g, now);
    for (const s of contested(g)) if (d.posture[s.id] === 'withdraw') for (const fl of armadas(g, s.id)) withdraw(g, fl, now);
    W.recompute(g, now);
  }
  return { ok: true, director: d };
}

// admin_armada: an admin sends an armada of about `power` from Comae. The director never calls it
// home unless the system's posture turns to withdraw. The cap doesn't stop an admin, though the
// director counts their armadas towards it.
function armada(g, systemId, power, now = Date.now()) {
  const d = ensureDirector(g, now);
  const to = W.system(g, systemId);
  if (!to) return fail('no such system');
  if (to.capitalOf) return fail("capital systems can't be contested");
  if (typeof power !== 'number' || !(power >= ARMADA_MIN && power <= ARMADA_MAX)) return fail(`an armada's power is ${ARMADA_MIN} to ${ARMADA_MAX}`);
  if (d.posture[to.id] === 'withdraw') return fail(`the director is withdrawing from ${to.name}: set it to push or hold first`);
  const fleet = spawn(g, to.id, compose(power), now, true);
  W.recompute(g, now);
  return { ok: true, fleet };
}

// admin_recall: an admin calls an armada home, whoever sent it.
function recall(g, fleetId, now = Date.now()) {
  const fl = g.war.fleets.find((x) => x.ai && x.id === Number(fleetId));
  if (!fl) return fail('no such armada');
  if (fl.status === 'returning') return fail('that armada is already on its way home');
  withdraw(g, fl, now);
  W.recompute(g, now);
  return { ok: true, fleet: fl };
}

// The seam for phase 3's sector battles: how hard Coma's ground forces fight `faction`, as the
// scale times that faction's intensity (0..2). 0 while the director is paused, and for any faction
// that isn't a player faction.
function intensityFor(g, faction) {
  const d = g.director;
  if (!d || d.paused || !PLAYERS.includes(faction)) return 0;
  return d.scale * d.intensity[faction];
}

module.exports = {
  DIRECTOR_MS,
  ACTIVE_MS,
  SCALE_MAX,
  PATROL_POWER,
  ARMADA_CAP,
  FLOOR,
  ARMADA_MIN,
  ARMADA_MAX,
  POSTURES,
  HOME,
  PLAYERS,
  ensureDirector,
  strengths,
  assess,
  compose,
  armadas,
  armadaPower,
  factionPower,
  run,
  tick,
  set,
  armada,
  recall,
  intensityFor,
};
