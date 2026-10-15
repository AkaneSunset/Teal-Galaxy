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
function queueShip(e, b, shipId, now, pay) {
  ensure(e);
  b.queue ||= [];
  const def = SHIPS[shipId];
  if (!def) return fail('no such ship');
  if (b.queue.length >= QUEUE_MAX) return fail('the build queue is full');
  if (fleetSize(e) + b.queue.length >= HANGAR) return fail('the hangar is full');
  const err = pay(def.cost);
  if (err) return fail(err);
  b.queue.push({ ship: shipId, doneAt: b.queue.length ? null : now + def.seconds * 1000 });
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
    if (b.queue.length) b.queue[0].doneAt = done.doneAt + SHIPS[b.queue[0].ship].seconds * 1000;
  }
  return launched;
}

module.exports = { SHIPS, HANGAR, QUEUE_MAX, ensure, fleetSize, queueShip, cancelShip, tick };
