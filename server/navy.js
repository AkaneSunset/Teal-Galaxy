// The Ship Foundry and the Builder's navy: warships built over time from metal and facility goods.
// Pure state + functions, like galaxy.js. Ships wait in the hangar; attacking other Builders comes later.

const SHIPS = {
  corvette: { name: 'Corvette', cost: { metal: 25 }, seconds: 60, attack: 2, hull: 10, speed: 3 },
  frigate: { name: 'Frigate', cost: { metal: 50, alloy: 10 }, seconds: 180, attack: 5, hull: 30, speed: 2 },
  destroyer: { name: 'Destroyer', cost: { metal: 100, alloy: 25, isotope: 3 }, seconds: 480, attack: 12, hull: 70, speed: 1 },
};

const HANGAR = 10; // ships a Foundry can hold, counting the ones still in its queue
const QUEUE_MAX = 5;

function fail(reason) {
  return { ok: false, reason };
}

// Gives an economy (a Builder's, or the galaxy's own from an old save) its navy.
function ensure(e) {
  e.navy ||= {};
  for (const id of Object.keys(SHIPS)) e.navy[id] ||= 0;
}

function fleetSize(e) {
  return Object.values(e.navy).reduce((a, b) => a + b, 0);
}

// Adds a ship to Foundry `b`'s queue, paid from economy `e`. `pay` takes the cost or says what is short.
// How long a Foundry takes over a ship: each Foundry level above 1 builds 25% faster.
function shipMs(b, shipId) {
  return (SHIPS[shipId].seconds * 1000) / (1 + 0.25 * ((b.level ?? 1) - 1));
}

function queueShip(e, b, shipId, now, pay) {
  ensure(e);
  b.queue ||= [];
  const def = SHIPS[shipId];
  if (!def) return fail('no such ship');
  if (b.queue.length >= QUEUE_MAX) return fail('the build queue is full');
  if (fleetSize(e) + b.queue.length >= HANGAR) return fail('the hangar is full');
  const err = pay(def.cost);
  if (err) return fail(err);
  b.queue.push({ ship: shipId, doneAt: b.queue.length ? null : now + shipMs(b, shipId) });
  return { ok: true, name: def.name };
}

// Cancels the last ship in Foundry `b`'s queue and refunds it in full to economy `e`.
function cancelShip(e, b) {
  if (!b.queue?.length) return fail('nothing in the queue');
  const item = b.queue.pop();
  for (const [res, amount] of Object.entries(SHIPS[item.ship].cost)) {
    if (res === 'credits') e.credits += amount;
    else e.stock[res] = (e.stock[res] || 0) + amount;
  }
  return { ok: true, name: SHIPS[item.ship].name };
}

// Finishes Foundry `b`'s ships whose time is up into economy `e`'s navy and starts the next
// in line. Returns the names launched.
function tick(e, b, now) {
  ensure(e);
  const launched = [];
  while (b.queue?.length && b.queue[0].doneAt <= now) {
    const done = b.queue.shift();
    e.navy[done.ship] += 1;
    launched.push(SHIPS[done.ship].name);
    if (b.queue.length) b.queue[0].doneAt = done.doneAt + shipMs(b, b.queue[0].ship);
  }
  return launched;
}

// --- Attacks on satellite sites ------------------------------------------------------

const TRAVEL_S = 120; // seconds to reach a site at speed 1; a fleet flies at its slowest ship's speed
const ROUNDS = 6; // a battle the fleet can't win in this many rounds ends in retreat
const DAMAGE = 3; // damage per point of attack per round
const LOOT_SHARE = 0.4; // share of each vault stack a winning fleet carries off
const SHIELD_MS = 10 * 60_000; // a site that was looted can't be attacked again for this long

function travelMs(ships) {
  const speeds = Object.entries(ships).filter(([, n]) => n > 0).map(([id]) => SHIPS[id].speed);
  return (TRAVEL_S / Math.min(...speeds)) * 1000;
}

// Fights a fleet ({ship id: count}) against a site's defence ({attack, hull}). Each round the
// fleet hits the defence, then the defence hits the fleet; damage to the fleet sinks its
// lightest ships first. Pure: the same fight always ends the same way.
function battle(ships, defence) {
  const fleet = [];
  for (const id of Object.keys(SHIPS).sort((a, b) => SHIPS[a].hull - SHIPS[b].hull))
    for (let i = 0; i < (ships[id] || 0); i++) fleet.push(id);
  let defHull = defence.hull;
  let taken = 0; // damage not yet enough to sink the next ship
  let rounds = 0;
  while (fleet.length && rounds < ROUNDS) {
    rounds += 1;
    defHull -= fleet.reduce((a, id) => a + SHIPS[id].attack, 0) * DAMAGE;
    if (defHull <= 0) break;
    taken += defence.attack * DAMAGE;
    while (fleet.length && taken >= SHIPS[fleet[0]].hull) taken -= SHIPS[fleet.shift()].hull;
  }
  const survivors = {};
  for (const id of fleet) survivors[id] = (survivors[id] || 0) + 1;
  const lost = {};
  for (const [id, n] of Object.entries(ships)) if (n - (survivors[id] || 0) > 0) lost[id] = n - (survivors[id] || 0);
  return { won: defHull <= 0, rounds, survivors, lost };
}

module.exports = { SHIPS, HANGAR, QUEUE_MAX, TRAVEL_S, LOOT_SHARE, SHIELD_MS, ensure, fleetSize, queueShip, cancelShip, tick, travelMs, battle };
