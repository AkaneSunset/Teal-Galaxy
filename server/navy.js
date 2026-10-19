// The Ship Foundry and the Builder's navy: warships built over time from metal and facility goods.
// Pure state + functions, like galaxy.js. Ships wait in the hangar until the Builder sends them to
// fight for orbital control of a system (war.js).

const SHIPS = {
  corvette: { name: 'Corvette', cost: { metal: 25 }, seconds: 60, attack: 2, hull: 10, speed: 3 },
  frigate: { name: 'Frigate', cost: { metal: 50, alloy: 10 }, seconds: 180, attack: 5, hull: 30, speed: 2 },
  destroyer: { name: 'Destroyer', cost: { metal: 100, alloy: 25, isotope: 3 }, seconds: 480, attack: 12, hull: 70, speed: 1 },
};

const HANGAR = 10; // ships a Foundry can hold, counting the ones still in its queue and those out with fleets
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

// `away`: the Builder's ships out with fleets (war.js), which still have their berths.
function queueShip(e, b, shipId, now, pay, away = 0) {
  ensure(e);
  b.queue ||= [];
  const def = SHIPS[shipId];
  if (!def) return fail('no such ship');
  if (b.queue.length >= QUEUE_MAX) return fail('the build queue is full');
  if (fleetSize(e) + away + b.queue.length >= HANGAR) return fail(away ? `the hangar is full: ${away} of its ships are out with your fleets` : 'the hangar is full');
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

// --- Fleets -------------------------------------------------------------------------

const TRAVEL_S = 120; // seconds for one jump at speed 1; a fleet flies at its slowest ship's speed
const DAMAGE = 3; // damage per point of attack per battle round

function travelMs(ships) {
  const speeds = Object.entries(ships).filter(([, n]) => n > 0).map(([id]) => SHIPS[id].speed);
  return (TRAVEL_S / Math.min(...speeds)) * 1000;
}

module.exports = { SHIPS, HANGAR, QUEUE_MAX, TRAVEL_S, DAMAGE, ensure, fleetSize, queueShip, cancelShip, tick, travelMs };
