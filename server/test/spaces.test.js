// Shared spaces: station pads and copies, walking together, carriers and their crews.

const test = require('node:test');
const assert = require('node:assert');
const WebSocket = require('ws');
const SP = require('../spaces');
const { startServer } = require('../server');

// Spaces over a made-up galaxy: stations at Cinder and Aster, a base to walk on Aster. Each pilot's
// `inbox` holds what they were sent.
function world() {
  const people = [];
  const sp = SP.createSpaces({
    isStation: (id) => ['cinder', 'aster'].includes(id),
    isSurface: (id) => id === 'aster',
    berthsOpen: (id) => (id === 'aster' ? world.berths : 0),
    factionOf: (name) => (name.startsWith('Ash') ? 'ashen' : 'compact'),
    people: () => people,
    send: (c, msg) => c.inbox.push(msg),
  });
  const pilot = (name) => {
    const c = { id: people.length + 1, name, role: 'explorer', inbox: [] };
    people.push(c);
    return c;
  };
  return { sp, pilot, people };
}

world.berths = 2; // open at Aster's Star Port

const last = (c, type) => c.inbox.filter((m) => m.type === type).at(-1);
const all = (c, type) => c.inbox.filter((m) => m.type === type);

test('pads: 32 to a copy, the lowest free one first, a new copy when all are taken', () => {
  const { sp, pilot } = world();
  const ps = Array.from({ length: 33 }, (_, i) => pilot(`P${i + 1}`));
  for (const p of ps) assert.ok(sp.dock(p, 'cinder').ok);
  assert.deepStrictEqual(last(ps[0], 'dock_granted'), { type: 'dock_granted', station: 'cinder', copy: 1, pad: 1 });
  assert.deepStrictEqual([ps[31].pad.copy, ps[31].pad.pad], [1, 32]);
  assert.deepStrictEqual([ps[32].pad.copy, ps[32].pad.pad], [2, 1], 'the 33rd opens copy 2');
  assert.strictEqual(sp.pads('cinder')[0].filter(Boolean).length, 32);

  // A freed pad is the next one given, in the lowest copy.
  sp.undock(ps[4]);
  assert.strictEqual(ps[4].pad, null);
  const late = pilot('Late');
  sp.dock(late, 'cinder');
  assert.deepStrictEqual(last(late, 'dock_granted'), { type: 'dock_granted', station: 'cinder', copy: 1, pad: 5 });

  // One pad each: asking again gives the same one; asking elsewhere gives up the old one.
  sp.dock(late, 'cinder');
  assert.deepStrictEqual([late.pad.copy, late.pad.pad], [1, 5]);
  sp.dock(late, 'aster');
  assert.deepStrictEqual(late.pad, { station: 'aster', copy: 1, pad: 1 });
  assert.strictEqual(sp.pads('cinder')[0][4], null);

  assert.deepStrictEqual(sp.dock(late, 'bastion'), { ok: false, reason: 'no such station' });
  assert.deepStrictEqual(late.pad, { station: 'aster', copy: 1, pad: 1 }, 'a refused request changes nothing');
});

test('a station is shared by its copy: walkers come, move and go', () => {
  const { sp, pilot } = world();
  const a = pilot('Akane');
  const b = pilot('Ash Rin');
  const c = pilot('Cass');
  assert.strictEqual(sp.enter(a, 'station:cinder').reason, 'dock at that station first');
  for (const p of [a, b]) sp.dock(p, 'cinder');
  assert.ok(sp.enter(a, 'station:cinder', { pos: [1, 2, 3], yaw: 0.5 }).ok);
  assert.deepStrictEqual(last(a, 'space_joined'), { type: 'space_joined', space: 'station:cinder', copy: 1, others: [] });
  sp.enter(b, 'station:cinder');
  assert.deepStrictEqual(last(b, 'space_joined').others, [{ id: a.id, name: 'Akane', faction: 'compact', pos: [1, 2, 3], yaw: 0.5, anim: 'idle' }]);
  assert.deepStrictEqual(last(a, 'walker'), { type: 'walker', id: b.id, name: 'Ash Rin', faction: 'ashen', pos: [0, 0, 0], yaw: 0, anim: 'idle' });

  // Walking: relayed to the others in the space, not back.
  assert.ok(sp.walk(b, { pos: [4, 0, -2], yaw: 1, anim: 'walk' }, 1000));
  assert.deepStrictEqual(last(a, 'walker'), { type: 'walker', id: b.id, name: 'Ash Rin', faction: 'ashen', pos: [4, 0, -2], yaw: 1, anim: 'walk' });
  assert.strictEqual(all(b, 'walker').length, 0);
  // Malformed updates are dropped.
  for (const bad of [{ pos: [NaN, 0, 0] }, { pos: [1, 2] }, { pos: [100_000, 0, 0] }, { pos: [0, 0, 0], anim: 'dance' }, { pos: [0, 0, 0], yaw: Infinity }, { pos: '1,2,3' }])
    assert.strictEqual(sp.walk(b, bad, 1000), false, JSON.stringify(bad));
  // At most 15 a second.
  const before = all(a, 'walker').length;
  for (let i = 0; i < 30; i++) sp.walk(b, { pos: [i, 0, 0], yaw: 0, anim: 'run' }, 5000 + i);
  assert.strictEqual(all(a, 'walker').length - before, 15);
  sp.walk(b, { pos: [99, 0, 0], yaw: 0, anim: 'run' }, 6100);
  assert.deepStrictEqual(last(a, 'walker').pos, [99, 0, 0], 'a new second, a new allowance');

  // Someone who isn't in the space neither sees nor is seen.
  sp.walk(c, { pos: [0, 0, 0] }, 7000);
  assert.strictEqual(all(c, 'walker').length, 0);

  // Entering the space you're in again only tells you again who is there: nobody sees you leave or
  // arrive, and the new position goes out as a walk update would (so within the walk limit).
  const [lefts, walkers] = [all(a, 'walker_left').length, all(a, 'walker').length];
  for (let i = 0; i < 100; i++) assert.ok(sp.enter(b, 'station:cinder', { pos: [i, 0, 0] }).ok);
  assert.strictEqual(all(a, 'walker_left').length, lefts);
  assert.ok(all(a, 'walker').length - walkers <= 15, `${all(a, 'walker').length - walkers} walker updates`);
  assert.deepStrictEqual(last(b, 'space_joined').others.map((o) => o.name), ['Akane']);

  // Leaving, entering elsewhere, undocking and disconnecting all say walker_left.
  sp.leave(b);
  assert.deepStrictEqual(last(a, 'walker_left'), { type: 'walker_left', id: b.id });
  sp.enter(b, 'station:cinder');
  sp.enter(b, `ship:${b.name}`);
  assert.strictEqual(all(a, 'walker_left').length, 2);
  sp.enter(b, 'station:cinder');
  sp.undock(b);
  assert.strictEqual(all(a, 'walker_left').length, 3);
  assert.strictEqual(b.space, null);
  sp.dock(b, 'cinder');
  sp.enter(b, 'station:cinder');
  sp.drop(b);
  assert.strictEqual(all(a, 'walker_left').length, 4);
  assert.strictEqual(b.pad, null, 'the pad freed on disconnect');
  assert.strictEqual(sp.pads('cinder')[0][1], null);

  assert.strictEqual(sp.enter(c, 'surface:mars').reason, 'no such base');
  assert.strictEqual(sp.enter(c, 'nowhere').reason, 'no such space');
  assert.ok(sp.land(c, 'aster').ok && sp.enter(c, 'surface:aster').ok, 'a pilot who has landed may walk a base');
});

test("pilots in different copies of a station don't see each other", () => {
  const { sp, pilot } = world();
  const ps = Array.from({ length: 34 }, (_, i) => pilot(`P${i + 1}`));
  for (const p of ps) sp.dock(p, 'cinder');
  const [one, two, three] = [ps[0], ps[32], ps[33]];
  sp.enter(one, 'station:cinder');
  sp.enter(two, 'station:cinder');
  assert.deepStrictEqual(last(two, 'space_joined').others, []);
  assert.strictEqual(last(two, 'space_joined').copy, 2);
  sp.enter(three, 'station:cinder');
  assert.deepStrictEqual(last(three, 'space_joined').others.map((o) => o.name), ['P33']);
  assert.strictEqual(all(one, 'walker').length, 0);
});

test('carriers: the owner, visitors from the same copy, closing, the 12-person limit, crew', () => {
  const { sp, pilot } = world();
  const owner = pilot('Akane');
  const guest = pilot('Rin');
  const far = pilot('Far');
  assert.ok(sp.enter(owner, 'ship:Akane').ok, 'the owner always may, docked or not');
  assert.strictEqual(last(owner, 'space_joined').copy, 1);
  assert.strictEqual(sp.enter(guest, 'ship:Akane').reason, "you aren't docked beside Akane's carrier");
  assert.strictEqual(sp.enter(guest, 'ship:Nobody').reason, "Nobody isn't on");

  for (const p of [owner, guest]) sp.dock(p, 'cinder');
  sp.enter(guest, 'station:cinder');
  assert.ok(sp.enter(guest, 'ship:Akane').ok, 'walking in the same copy');
  assert.deepStrictEqual(last(guest, 'space_joined').others.map((o) => o.name), ['Akane']);
  assert.strictEqual(last(owner, 'walker').name, 'Rin');

  // A pilot docked in another copy can't come aboard.
  const fillers = Array.from({ length: 30 }, (_, i) => pilot(`Filler${i}`));
  for (const p of fillers) sp.dock(p, 'cinder');
  sp.dock(far, 'cinder');
  assert.strictEqual(far.pad.copy, 2);
  assert.match(sp.enter(far, 'ship:Akane').reason, /aren't docked beside/);

  // Closed: no new visitors; those aboard stay.
  sp.setOpen(owner, false);
  assert.strictEqual(sp.enter(fillers[0], 'ship:Akane').reason, 'Akane has closed their carrier');
  assert.strictEqual(guest.space, 'ship:Akane', 'the guest stayed aboard');
  sp.setOpen(owner, true);

  // Twelve aboard at most, the owner included.
  for (const p of fillers.slice(0, 10)) assert.ok(sp.enter(p, 'ship:Akane').ok);
  assert.strictEqual(sp.members('ship:Akane', 1).length, 12);
  assert.strictEqual(sp.enter(fillers[10], 'ship:Akane').reason, "Akane's carrier is full");
  assert.ok(sp.enter(fillers[0], 'ship:Akane').ok, 'someone already aboard may enter again');
  sp.leave(fillers[0]);
  assert.ok(sp.enter(fillers[10], 'ship:Akane').ok, 'room again');
});

test('crew ride along when the owner undocks, and step off only where the carrier is docked', () => {
  const { sp, pilot } = world();
  const owner = pilot('Akane');
  const crew = pilot('Rin');
  sp.dock(owner, 'cinder');
  sp.dock(crew, 'cinder');
  sp.enter(owner, 'ship:Akane');
  sp.enter(crew, 'station:cinder');
  sp.enter(crew, 'ship:Akane');
  sp.undock(owner);
  assert.strictEqual(crew.space, 'ship:Akane', 'still aboard, flying');
  assert.strictEqual(owner.space, 'ship:Akane');
  assert.deepStrictEqual(crew.pad, { station: 'cinder', copy: 1, pad: 2 }, "the crew's own ship stays on its pad");
  assert.strictEqual(sp.enter(crew, 'station:cinder').reason, "Akane's carrier isn't docked there", 'even where they hold a pad');

  // The carrier docks at Aster: the crew steps off into Aster in the owner's copy, with no pad of their own there.
  sp.dock(owner, 'aster');
  assert.ok(sp.enter(crew, 'station:aster').ok);
  assert.strictEqual(crew.copy, owner.pad.copy);
  assert.strictEqual(crew.pad.station, 'cinder');
  // Off the carrier, they're an ordinary visitor again, and can go back aboard.
  assert.ok(sp.enter(crew, 'ship:Akane').ok);
});

// --- Over the wire ----------------------------------------------------------------------------

function connect(port) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    const inbox = [];
    const waiters = [];
    ws.on('message', (data) => {
      const msg = JSON.parse(data);
      const i = waiters.findIndex((w) => w.match(msg));
      if (i >= 0) waiters.splice(i, 1)[0].resolve(msg);
      else inbox.push(msg);
    });
    ws.on('open', () =>
      resolve({
        inbox,
        send: (msg) => ws.send(JSON.stringify(msg)),
        next(match) {
          const i = inbox.findIndex(match);
          if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
          return new Promise((res) => waiters.push({ match, resolve: res }));
        },
        close: () => ws.close(),
      })
    );
    ws.on('error', reject);
  });
}

test('over the wire: two pilots dock at Cinder Orbital, walk together, and one boards the other', async () => {
  const port = 9152;
  const server = startServer({ port, tickMs: 60000 });
  const type = (t) => (m) => m.type === t;
  try {
    const a = await connect(port);
    const b = await connect(port);
    const phone = await connect(port);
    a.send({ type: 'hello', role: 'explorer', name: 'Akane' });
    b.send({ type: 'hello', role: 'explorer', name: 'Rin' });
    phone.send({ type: 'hello', role: 'builder', name: 'Builder' });
    const wa = await a.next(type('welcome'));
    const wb = await b.next(type('welcome'));
    await phone.next(type('welcome'));

    phone.send({ type: 'dock_request', station: 'cinder' });
    assert.strictEqual((await phone.next(type('error'))).reason, 'only pilots dock at stations');
    a.send({ type: 'dock_request', station: 'fortitude' });
    assert.strictEqual((await a.next(type('error'))).reason, 'no such station');
    a.send({ type: 'dock_request', station: 'bastion' });
    assert.strictEqual((await a.next(type('error'))).reason, 'no such station', "capital worlds have no orbital station");

    a.send({ type: 'dock_request', station: 'cinder' });
    assert.deepStrictEqual(await a.next(type('dock_granted')), { type: 'dock_granted', station: 'cinder', copy: 1, pad: 1 });
    b.send({ type: 'dock_request', station: 'cinder' });
    assert.deepStrictEqual(await b.next(type('dock_granted')), { type: 'dock_granted', station: 'cinder', copy: 1, pad: 2 });

    a.send({ type: 'enter_space', space: 'station:cinder', pos: [0, 1, 0] });
    assert.deepStrictEqual(await a.next(type('space_joined')), { type: 'space_joined', space: 'station:cinder', copy: 1, others: [] });
    b.send({ type: 'enter_space', space: 'station:cinder' });
    const joined = await b.next(type('space_joined'));
    assert.deepStrictEqual(joined.others, [{ id: wa.id, name: 'Akane', faction: null, pos: [0, 1, 0], yaw: 0, anim: 'idle' }]);
    assert.strictEqual((await a.next(type('walker'))).name, 'Rin');

    b.send({ type: 'walk', pos: [3, 1, 4], yaw: 1.5, anim: 'walk' });
    assert.deepStrictEqual(await a.next(type('walker')), { type: 'walker', id: wb.id, name: 'Rin', faction: null, pos: [3, 1, 4], yaw: 1.5, anim: 'walk' });
    a.send({ type: 'walk', pos: [5, 1, 4], yaw: 0, anim: 'run' });
    assert.deepStrictEqual((await b.next(type('walker'))).pos, [5, 1, 4]);

    // Akane goes aboard her carrier; Rin follows her in.
    a.send({ type: 'enter_space', space: 'ship:Akane' });
    await a.next(type('space_joined'));
    assert.deepStrictEqual(await b.next(type('walker_left')), { type: 'walker_left', id: wa.id });
    b.send({ type: 'enter_space', space: 'ship:Akane' });
    assert.deepStrictEqual((await b.next(type('space_joined'))).others.map((o) => o.name), ['Akane']);
    assert.strictEqual((await a.next(type('walker'))).name, 'Rin');

    // While docked, her `ship` messages say which berth she holds (so others can tell copies apart).
    a.send({ type: 'ship', pos: [1, 2, 3], rot: [0, 0, 0], over: 'cinder' });
    assert.deepStrictEqual((await b.next(type('ship'))).berth, { station: 'cinder', copy: 1, pad: 1 });

    // She undocks and flies with Rin aboard: her `ship` messages carry the planet she's over.
    a.send({ type: 'undock' });
    a.send({ type: 'ship', pos: [1, 2, 3], rot: [0, 0, 0], over: 'cinder' });
    const ship = await b.next(type('ship'));
    assert.deepStrictEqual([ship.name, ship.over, ship.berth], ['Akane', 'cinder', undefined]);
    a.send({ type: 'ship', pos: [1, 2, 3], rot: [0, 0, 0], over: 'nowhere' });
    assert.strictEqual((await b.next(type('ship'))).over, undefined, 'only war planets');
    b.send({ type: 'enter_space', space: 'station:cinder' });
    assert.strictEqual((await b.next(type('error'))).reason, "Akane's carrier isn't docked there");
    b.send({ type: 'walk', pos: [0, 0, 0], yaw: 0, anim: 'sit' });
    assert.strictEqual((await a.next(type('walker'))).anim, 'sit', 'still aboard together');

    // Rin's app goes away: Akane sees her leave, and her pad frees.
    b.close();
    assert.deepStrictEqual(await a.next(type('walker_left')), { type: 'walker_left', id: wb.id });
    assert.deepStrictEqual(server.spaces.pads('cinder'), [new Array(32).fill(null)]);

    for (const c of [a, phone]) c.close();
  } finally {
    await server.close();
  }
});

test('over the wire: entering spaces is limited to 10 a second per pilot', async () => {
  const port = 9154;
  const server = startServer({ port, tickMs: 60000 });
  const type = (t) => (m) => m.type === t;
  try {
    const a = await connect(port);
    const b = await connect(port);
    a.send({ type: 'hello', role: 'explorer', name: 'Akane' });
    b.send({ type: 'hello', role: 'explorer', name: 'Rin' });
    await a.next(type('welcome'));
    await b.next(type('welcome'));
    for (const c of [a, b]) {
      c.send({ type: 'dock_request', station: 'cinder' });
      await c.next(type('dock_granted'));
      c.send({ type: 'enter_space', space: 'station:cinder' });
      await c.next(type('space_joined'));
    }
    // Akane hops between the station and her carrier as fast as she can: Rin hears a few.
    for (let i = 0; i < 200; i++) a.send({ type: 'enter_space', space: i % 2 ? 'station:cinder' : 'ship:Akane' });
    a.send({ type: 'chat', text: 'done' });
    await b.next(type('chat'));
    const heard = b.inbox.filter((m) => m.type === 'walker' || m.type === 'walker_left').length;
    assert.ok(heard <= 2 * 10, `Rin heard ${heard}`);
    for (const c of [a, b]) c.close();
  } finally {
    await server.close();
  }
});

test("berths: the Star Port's open berths, one a ship; full, pilots shuttle down from the High Port", () => {
  const { sp, pilot } = world();
  world.berths = 2;
  const [a, b, c] = ['Akane', 'Bo', 'Cy'].map(pilot);
  assert.strictEqual(sp.enter(a, 'surface:aster').reason, 'land at the Star Port or dock at the High Port first');
  sp.dock(a, 'aster'); // up at the High Port first
  assert.deepStrictEqual(sp.land(a, 'aster'), { ok: true, base: 'aster', berth: 0 });
  assert.deepStrictEqual(last(a, 'berth_granted'), { type: 'berth_granted', base: 'aster', berth: 0 });
  assert.strictEqual(a.pad, null, 'the ship left its High Port pad');
  assert.deepStrictEqual(sp.land(a, 'aster'), { ok: true, base: 'aster', berth: 0 }, 'asking again: the same berth');
  assert.strictEqual(sp.land(b, 'aster').berth, 1);
  assert.match(sp.land(c, 'aster').reason, /all 2 berths .* taken: take the shuttle down from the High Port/);
  assert.ok(sp.enter(a, 'surface:aster').ok, 'landed: walk the base');
  sp.dock(c, 'aster');
  assert.ok(sp.enter(c, 'surface:aster').ok, 'shuttled down from the High Port');
  assert.deepStrictEqual(sp.berths('aster'), ['Akane', 'Bo']);
  // Flying back up frees the berth and takes you off the base; so does going away.
  sp.dock(a, 'aster');
  assert.strictEqual(a.berth, null);
  assert.strictEqual(a.space, null);
  assert.strictEqual(sp.land(c, 'aster').berth, 0);
  sp.drop(b);
  assert.deepStrictEqual(sp.berths('aster'), ['Cy', null]);
  assert.deepStrictEqual(sp.allBerths(), { aster: ['Cy', null] });
  // A carrier's lander takes a berth, and the carrier keeps its pad up at the High Port.
  const d = pilot('Di');
  sp.dock(d, 'aster');
  assert.strictEqual(sp.land(d, 'aster', true).berth, 1);
  assert.strictEqual(d.pad.station, 'aster');
  world.berths = 0;
  assert.strictEqual(sp.land(b, 'aster').reason, 'there is no Star Port to land at');
  world.berths = 2;
});
