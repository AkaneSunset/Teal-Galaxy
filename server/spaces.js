// Shared spaces: the places pilots walk around on foot together, and the landing pads that decide
// who shares a station. In memory only (nothing here is saved): a server restart empties them all.
//
// A space is one of
//   station:<planet id>   an orbital station over a contested world, or a Builder planet's High Port
//   ship:<owner name>     inside a pilot's fleet carrier
//   surface:<planet id>   a Builder base, on foot
// and everyone in the same space and the same copy of it sees everyone else walk. A station's copy
// holds PADS ships; when every pad is taken a new copy opens, so the pads are what decide how many
// pilots a station holds. Ships and surfaces have one copy each.
//
// A Builder base has berths at its Star Port, as many as its level opens (berthsOpen). A pilot
// lands on one with their ship; when they're all taken, pilots docked at the base's High Port take
// the shuttle down on foot instead. Either way they may walk the base.
//
// People aboard someone's carrier are its crew: they stay aboard when its owner undocks and flies,
// and can only step off into a station the owner is docked at.
//
// The server makes one with createSpaces() and hands it the pilots' connection records (`me`);
// the space a pilot is in and the pad they hold are kept on that record.

const PADS = 32; // ships one copy of a station holds
const SHIP_MAX = 12; // people aboard one carrier, its owner included
const WALK_PER_S = 15; // walk updates per connection per second; more are dropped
const POS_MAX = 100_000; // |x|, |y|, |z| and |yaw| of a walk update
const ANIMS = ['idle', 'walk', 'run', 'sit'];
const ONE_COPY = 1; // the copy of a ship or a surface

function fail(reason) {
  return { ok: false, reason };
}

const finite = (v) => typeof v === 'number' && Number.isFinite(v) && Math.abs(v) < POS_MAX;

// A position [x, y, z] from a message, or null if it isn't one.
function position(pos) {
  return Array.isArray(pos) && pos.length === 3 && pos.every(finite) ? pos.slice() : null;
}

// `isStation(id)` and `isSurface(id)` say which planet ids have a station or a base to walk;
// `factionOf(name)` is a pilot's faction or null; `people()` lists the pilots' connection records;
// `send(me, msg)` sends one of them a message.
function createSpaces({ isStation, isSurface, berthsOpen = () => 0, factionOf, people, send }) {
  const stations = new Map(); // station id -> its copies, each an array of PADS holders (connection ids, or null)
  const bases = new Map(); // base (planet id) -> its Star Port's berths, connection ids or null

  // The connection of the pilot called `name`, if they're on.
  function pilot(name) {
    for (const c of people()) if (c.name === name) return c;
    return null;
  }

  function members(space, copy, except = null) {
    const out = [];
    for (const c of people()) if (c !== except && c.space === space && c.copy === copy) out.push(c);
    return out;
  }

  function walker(me) {
    const w = me.walk || { pos: [0, 0, 0], yaw: 0, anim: 'idle' };
    return { id: me.id, name: me.name, faction: factionOf(me.name), pos: w.pos, yaw: w.yaw, anim: w.anim };
  }

  // --- Pads ---------------------------------------------------------------------------------

  // A pad in the lowest-numbered copy of the station with one free (copies and pads count from 1).
  // A pilot holds one pad: asking again at the same station gives the same one back, and asking at
  // another gives up the old one.
  function dock(me, station) {
    station = String(station ?? '');
    if (!isStation(station)) return fail('no such station');
    if (me.pad?.station === station) return grant(me);
    if (me.pad) undock(me);
    unberth(me); // the ship has lifted off from a base to come up here
    if (!stations.has(station)) stations.set(station, []);
    const copies = stations.get(station);
    let copy = copies.findIndex((pads) => pads.includes(null));
    if (copy < 0) copy = copies.push(new Array(PADS).fill(null)) - 1;
    const pad = copies[copy].indexOf(null);
    copies[copy][pad] = me.id;
    me.pad = { station, copy: copy + 1, pad: pad + 1 };
    return grant(me);
  }

  function grant(me) {
    send(me, { type: 'dock_granted', ...me.pad });
    return { ok: true, ...me.pad };
  }

  // Gives up the pilot's pad, and walks them out of that station if they're in it.
  function undock(me) {
    if (!me.pad) return { ok: true };
    const { station, copy, pad } = me.pad;
    const pads = stations.get(station)?.[copy - 1];
    if (pads && pads[pad - 1] === me.id) pads[pad - 1] = null;
    me.pad = null;
    if (me.space === `station:${station}`) leave(me);
    return { ok: true, station };
  }

  // The ship lands at a base: on a free berth of its Star Port, or not at all (the pilot docks at
  // the High Port and shuttles down instead). Asking again at the same base gives the same berth.
  // Landing gives up the pilot's High Port pad: the ship has left it.
  function land(me, base) {
    base = String(base ?? '');
    if (!isSurface(base)) return fail('no such base');
    if (me.berth?.base === base) return granted(me);
    const open = berthsOpen(base);
    if (open < 1) return fail('there is no Star Port to land at');
    if (!bases.has(base)) bases.set(base, []);
    const berths = bases.get(base);
    const free = [...Array(open).keys()].find((i) => !berths[i]);
    if (free === undefined) return fail(`all ${open} berths at the Star Port are taken: take the shuttle down from the High Port`);
    unberth(me);
    if (me.pad) undock(me);
    berths[free] = me.id;
    me.berth = { base, berth: free };
    return granted(me);
  }

  function granted(me) {
    send(me, { type: 'berth_granted', ...me.berth });
    return { ok: true, ...me.berth };
  }

  // Gives up the pilot's berth, and walks them off the base if they were on it with their ship.
  function unberth(me) {
    if (!me.berth) return { ok: true };
    const { base, berth } = me.berth;
    const berths = bases.get(base);
    if (berths && berths[berth] === me.id) berths[berth] = null;
    me.berth = null;
    if (me.space === `surface:${base}` && me.pad?.station !== base) leave(me);
    return { ok: true, base };
  }

  // Who holds each berth at a base: [name or null, ...].
  function berths(base) {
    const byId = new Map([...people()].map((c) => [c.id, c.name]));
    return (bases.get(base) || []).map((id) => (id ? byId.get(id) ?? null : null));
  }

  // Who holds which pad in each copy of a station: [[name or null, ...], ...].
  function pads(station) {
    const byId = new Map([...people()].map((c) => [c.id, c.name]));
    return (stations.get(station) || []).map((p) => p.map((id) => (id === null ? null : byId.get(id) ?? null)));
  }

  // --- Spaces ---------------------------------------------------------------------------------

  // Which copy of `space` the pilot may enter, or why they may not.
  function admit(me, space) {
    const [kind, ...rest] = space.split(':');
    const id = rest.join(':');
    if (!id) return fail('no such space');
    if (kind === 'station') {
      if (!isStation(id)) return fail('no such station');
      // Crew step off only where their carrier is docked, into its copy.
      const ship = me.space?.startsWith('ship:') ? me.space.slice(5) : null;
      if (ship && ship !== me.name) {
        const owner = pilot(ship);
        if (owner?.pad?.station !== id) return fail(`${ship}'s carrier isn't docked there`);
        return { ok: true, copy: owner.pad.copy };
      }
      if (me.pad?.station !== id) return fail('dock at that station first');
      return { ok: true, copy: me.pad.copy };
    }
    if (kind === 'ship') {
      if (id === me.name) return { ok: true, copy: ONE_COPY };
      const owner = pilot(id);
      if (!owner) return fail(`${id} isn't on`);
      if (me.space !== space) {
        // Next to it: both docked in the same copy of a station, or walking in that copy.
        const at = owner.pad && `station:${owner.pad.station}`;
        const near =
          !!owner.pad &&
          ((me.pad?.station === owner.pad.station && me.pad.copy === owner.pad.copy) || (me.space === at && me.copy === owner.pad.copy));
        if (!near) return fail(`you aren't docked beside ${id}'s carrier`);
        if (owner.shipOpen === false) return fail(`${id} has closed their carrier`);
        if (members(space, ONE_COPY).length >= SHIP_MAX) return fail(`${id}'s carrier is full`);
      }
      return { ok: true, copy: ONE_COPY };
    }
    if (kind === 'surface') {
      if (!isSurface(id)) return fail('no such base');
      // Landed on a berth, or shuttled down from the High Port overhead.
      if (me.berth?.base !== id && me.pad?.station !== id) return fail('land at the Star Port or dock at the High Port first');
      return { ok: true, copy: ONE_COPY };
    }
    return fail('no such space');
  }

  // The pilot walks into a space (leaving the one they were in), starting at `start` {pos, yaw,
  // anim} if given. They hear who is there; those there see them arrive. Entering the space they're
  // already in only tells them again who is there (and moves them, as a walk update would).
  function enter(me, space, start = {}) {
    space = String(space ?? '');
    const can = admit(me, space);
    if (!can.ok) return can;
    if (me.space === space && me.copy === can.copy) {
      if (start.pos !== undefined) walk(me, start);
      send(me, { type: 'space_joined', space, copy: me.copy, others: members(space, me.copy, me).map(walker) });
      return { ok: true, space, copy: me.copy };
    }
    if (me.space) leave(me);
    me.space = space;
    me.copy = can.copy;
    me.walk = {
      pos: position(start.pos) || [0, 0, 0],
      yaw: finite(start.yaw) ? start.yaw : 0,
      anim: ANIMS.includes(start.anim) ? start.anim : 'idle',
    };
    const others = members(space, me.copy, me);
    send(me, { type: 'space_joined', space, copy: me.copy, others: others.map(walker) });
    const msg = { type: 'walker', ...walker(me) };
    for (const c of others) send(c, msg);
    return { ok: true, space, copy: me.copy };
  }

  function leave(me) {
    if (!me.space) return { ok: true };
    const others = members(me.space, me.copy, me);
    me.space = null;
    me.copy = null;
    for (const c of others) send(c, { type: 'walker_left', id: me.id });
    return { ok: true };
  }

  // A walk update, relayed to everyone else in the space. At most WALK_PER_S a second; anything
  // more, or anything malformed, is dropped without a word.
  function walk(me, msg, now = Date.now()) {
    if (!me.space) return false;
    if (now - (me.walkWindow || 0) >= 1000) [me.walkWindow, me.walkCount] = [now, 0];
    if (++me.walkCount > WALK_PER_S) return false;
    const pos = position(msg.pos);
    if (!pos || (msg.yaw !== undefined && !finite(msg.yaw))) return false;
    if (msg.anim !== undefined && !ANIMS.includes(msg.anim)) return false;
    me.walk = { pos, yaw: msg.yaw ?? me.walk?.yaw ?? 0, anim: msg.anim ?? me.walk?.anim ?? 'idle' };
    const out = { type: 'walker', ...walker(me) };
    for (const c of members(me.space, me.copy, me)) send(c, out);
    return true;
  }

  // The owner opens or closes their carrier to visitors (crew already aboard stay).
  function setOpen(me, open) {
    me.shipOpen = open !== false;
    return { ok: true };
  }

  // A pilot's app went away: their pad frees and they leave their space.
  function drop(me) {
    leave(me);
    undock(me);
    unberth(me);
  }

  return { dock, undock, pads, land, unberth, berths, enter, leave, walk, setOpen, drop, members, admit };
}

module.exports = { PADS, SHIP_MAX, WALK_PER_S, POS_MAX, ANIMS, createSpaces };
