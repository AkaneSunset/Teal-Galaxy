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

// Gives a galaxy (new or from an old save) its navy and fills in any Foundry's queue.
function ensure(g) {
  g.navy ||= {};
  for (const id of Object.keys(SHIPS)) g.navy[id] ||= 0;
  for (const p of g.system.planets) for (const b of p.buildings) if (b.type === 'foundry') b.queue ||= [];
}

function fleetSize(g) {
  return Object.values(g.navy).reduce((a, b) => a + b, 0);
}

function foundry(g, planetId, slot) {
  const p = g.system.planets.find((x) => x.id === planetId);
  const b = p && p.buildings.find((x) => x.slot === slot);
  return b && b.type === 'foundry' ? b : null;
}

// Adds a ship to a Foundry's queue. `pay` takes the cost or says what is short.
function queueShip(g, planetId, slot, shipId, now, pay) {
  ensure(g);
  const b = foundry(g, planetId, slot);
  const def = SHIPS[shipId];
  if (!b) return fail('no Ship Foundry there');
  if (!def) return fail('no such ship');
  if (b.queue.length >= QUEUE_MAX) return fail('the build queue is full');
  if (fleetSize(g) + b.queue.length >= HANGAR) return fail('the hangar is full');
  const err = pay(def.cost);
  if (err) return fail(err);
  b.queue.push({ ship: shipId, doneAt: b.queue.length ? null : now + def.seconds * 1000 });
  return { ok: true, name: def.name };
}

// Cancels the last ship in a Foundry's queue and refunds it in full.
function cancelShip(g, planetId, slot) {
  ensure(g);
  const b = foundry(g, planetId, slot);
  if (!b || !b.queue.length) return fail('nothing in the queue');
  const item = b.queue.pop();
  for (const [res, amount] of Object.entries(SHIPS[item.ship].cost)) {
    if (res === 'credits') g.credits += amount;
    else g.stock[res] = (g.stock[res] || 0) + amount;
  }
  return { ok: true, name: SHIPS[item.ship].name };
}

// Finishes ships whose time is up and starts the next in line. Returns the names launched.
function tick(g, now) {
  ensure(g);
  const launched = [];
  for (const p of g.system.planets)
    for (const b of p.buildings) {
      if (b.type !== 'foundry') continue;
      while (b.queue.length && b.queue[0].doneAt <= now) {
        const done = b.queue.shift();
        g.navy[done.ship] += 1;
        launched.push(SHIPS[done.ship].name);
        if (b.queue.length) b.queue[0].doneAt = done.doneAt + SHIPS[b.queue[0].ship].seconds * 1000;
      }
    }
  return launched;
}

module.exports = { SHIPS, HANGAR, QUEUE_MAX, ensure, fleetSize, queueShip, cancelShip, tick };
