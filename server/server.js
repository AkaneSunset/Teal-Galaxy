// Galaxy server: holds the shared galaxy, applies actions from the apps,
// and tells every connected app when something changes.
//
//   node server.js            (listens on port 8080, saves to galaxy.json)
//   PORT=9000 SAVE_FILE=x.json node server.js
//   DEMO=1 node server.js     (every base starts with enough to build everything, and builds 10x faster;
//                              pilots can take sectors with demo_capture to play-test the war; the demo
//                              war: every faction holds 25% of every system, so anyone may attack
//                              anywhere, captures lock for 5 minutes, and every pilot flies a carrier)
//   BATTLE_SPEED=10 node server.js   (sector battles run 10x faster, for the game tests)
//   BUILD_SPEED=0 node server.js   (buildings finish instantly, for the game smoke tests)
//   ADMIN_KEY=<secret> node server.js   (apps that say hello with this admin_key are admins: they can
//                                        play the Coma Conglomerate and steer its AI director)

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');
const B = require('./battle');
const D = require('./director');
const F = require('./factions');
const G = require('./galaxy');
const H = require('./heist');
const N = require('./navy');
const S = require('./sites');
const SP = require('./spaces');
const W = require('./war');

const TICK_MS = 5000;
const CHAT_MAX = 200;
const CHAT_GAP_MS = 500; // at most two chat lines a second per player
const RAID_TICK_MS = 200; // reveals, Heat and the run clock
const RAID_MSGS_PER_S = 30; // per raider; more than this is dropped
const SPACE_MSGS_PER_S = 10; // dock_request, enter_space, leave_space and ship_open, per pilot
const BATTLE_JOINS_PER_S = 2; // battle_start and battle_join, per pilot
// Whether a connection has sent more than `perS` messages of one kind (`key`) this second.
function tooFast(me, key, perS, t = Date.now()) {
  const w = ((me.limits ??= {})[key] ??= { at: 0, n: 0 });
  if (t - w.at >= 1000) [w.at, w.n] = [t, 0];
  return ++w.n > perS;
}

// Messages only a Builder (phone) or only a pilot (PC) sends, and what the other gets told. A
// Builder and a pilot of the same name are different characters, so neither may play the other's.
const BASE = 'only Builders run a base';
const BUILDER_ONLY = {
  build: BASE, post_job: BASE, ship_cargo: BASE, upgrade_security: BASE, sound_alarm: BASE, queue_ship: BASE, cancel_ship: BASE,
  place_piece: BASE, remove_piece: BASE, clear_obstacle: BASE, upgrade_building: BASE,
  found_site: 'only Builders found outposts', send_fleet: 'only Builders command fleets', recall_fleet: 'only Builders command fleets', set_price: 'only Builders run a Carrier Dock', set_bid: 'only Builders run a Star Port', fill_contract: 'only Builders fill contracts', donate: 'only Builders donate to the war',
};
const PILOT_ONLY = {
  collect: 'only pilots carry cargo', deliver: 'only pilots carry cargo', sell: 'only pilots sell to the Fence',
  dock_buy: 'only pilots buy at a Carrier Dock', post_contract: 'only pilots post contracts', cancel_contract: 'only pilots post contracts', demo_capture: 'only pilots take sectors',
  dock_request: 'only pilots dock at stations', undock: 'only pilots dock at stations', land_request: 'only pilots land at a Star Port',
  sell_to_builder: 'only pilots sell at a Star Port',
  enter_space: 'only pilots walk around', leave_space: 'only pilots walk around', walk: 'only pilots walk around', ship_open: 'only pilots have carriers',
  battle_start: 'only pilots fight sector battles', battle_join: 'only pilots fight sector battles', battle_leave: 'only pilots fight sector battles',
  battle_drop: 'only pilots fight sector battles', battle_order: 'only pilots fight sector battles', battle_produce: 'only pilots fight sector battles',
  battle_possess: 'only pilots fight sector battles', battle_drive: 'only pilots fight sector battles', battle_release: 'only pilots fight sector battles',
};
// Messages only an admin's app may send: steering the Coma director and playing Coma by hand.
const ADMIN_ONLY = ['director_set', 'admin_armada', 'admin_recall', 'admin_capture'];

// Whether a hello's admin_key is the server's ADMIN_KEY (none set: nobody is an admin). The bytes
// are compared in constant time, so the key can't be found a character at a time; a key of another
// length never matches. The key is never echoed or logged.
function adminCheck(secret) {
  const want = secret ? Buffer.from(String(secret)) : null;
  return (key) => {
    if (!want || typeof key !== 'string') return false;
    const got = Buffer.from(key);
    return got.length === want.length && crypto.timingSafeEqual(got, want);
  };
}

// `demoWar` turns the demo war (war.js setDemo) on or off for the whole process; left out, it stays
// as it is. `battleSpeed` is BATTLE_SPEED.
function startServer({ port = 8080, saveFile = null, tickMs = TICK_MS, now = Date.now, demo = false, demoWar, buildSpeed = null, adminKey = null, battleSpeed = 1 } = {}) {
  if (demoWar !== undefined) W.setDemo(demoWar);
  let galaxy = G.newGalaxy();
  if (saveFile && fs.existsSync(saveFile)) {
    galaxy = JSON.parse(fs.readFileSync(saveFile, 'utf8'));
    G.recoverRaids(galaxy);
    S.locate(galaxy); // sites founded before they had a place on their planet get one
    console.log(`Loaded galaxy from ${saveFile}`);
  }
  // Demo mode builds 10 times faster; tests can pass Infinity for instant buildings.
  galaxy.buildSpeed = buildSpeed ?? (demo ? 10 : 1);
  const runs = new Map(); // pilot name -> live raid run (server only: holds container contents)
  const isAdmin = adminCheck(adminKey);

  const wss = new WebSocketServer({ port });
  wss.on('error', (err) => {
    if (err.code !== 'EADDRINUSE') throw err;
    console.error(`Port ${port} is already in use: a galaxy server is probably running already.`);
    console.error(`Use that one, stop it (Linux/Mac: fuser -k ${port}/tcp), or start this one with PORT=<another port>.`);
    process.exit(1);
  });
  const clients = new Map(); // ws -> { id, role, name, admin, ws, and a pilot's space, pad, over, battle }
  let nextClientId = 1;
  let saveTimer = null;

  function save() {
    if (!saveFile || saveTimer) return;
    saveTimer = setTimeout(() => {
      saveTimer = null;
      fs.writeFileSync(saveFile, JSON.stringify(galaxy, null, 2));
    }, 500);
  }

  function send(ws, msg) {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg));
  }

  // Everything about the galaxy goes only to apps it has welcomed: not to one that hasn't said
  // hello yet, or was turned away.
  function broadcast(msg, except = null) {
    for (const [ws, c] of clients) if (ws !== except && c.role) send(ws, msg);
  }

  // The galaxy as a player may see it: the Coma director's settings are for admins only, and so is
  // which armadas an admin sent by hand (players see every armada, as ships in space). It is only
  // ever written out as JSON, which leaves the undefined fields out. Both views carry the sector
  // battles running now (`battles`), which are never saved.
  function playerView() {
    const fleets = galaxy.war.fleets.map((fl) => (fl.manual ? { ...fl, manual: undefined } : fl));
    return { ...galaxy, director: undefined, war: { ...galaxy.war, fleets }, battles: battles.list(), berths: spaces.allBerths() };
  }

  function adminView() {
    return { ...galaxy, battles: battles.list(), berths: spaces.allBerths() };
  }

  function stateFor(me) {
    return me.admin ? adminView() : playerView();
  }

  // The state to every welcomed app: admins get all of it, everyone else the player view (each
  // written once).
  function broadcastState(except = null) {
    let all = null;
    let open = null;
    for (const [ws, c] of clients) {
      if (ws === except || !c.role || ws.readyState !== ws.OPEN) continue;
      if (c.admin) ws.send((all ??= JSON.stringify({ type: 'state', state: adminView() })));
      else ws.send((open ??= JSON.stringify({ type: 'state', state: playerView() })));
    }
  }

  function changed() {
    broadcastState();
    save();
  }

  // --- Shared spaces and sector battles ----------------------------------------------------

  function pilots() {
    return [...clients.values()].filter((c) => c.role === 'explorer');
  }

  // Stations: every contested world's orbital (not the capitals'), and every Builder planet's High Port.
  const spaces = SP.createSpaces({
    isStation: (id) => {
      const wp = W.planet(galaxy, id);
      if (wp) return !wp.capital;
      return galaxy.system.planets.some((p) => p.id === id && p.kind !== 'satellite');
    },
    isSurface: (id) => galaxy.system.planets.some((p) => p.id === id),
    berthsOpen: (id) => G.berthsOpen(galaxy, id),
    factionOf: (name) => (Object.hasOwn(galaxy.pilots, name) ? galaxy.pilots[name].faction ?? null : null),
    people: pilots,
    send: (c, msg) => send(c.ws, msg),
  });

  const battles = B.createBattles({ galaxy: () => galaxy, now, speed: battleSpeed, send: (c, msg) => send(c.ws, msg), changed });

  // Where a pilot is, for the battle rules: the planet the carrier they're aboard is over (its
  // owner flying in that orbit, or docked at that planet's station), and the station they're at.
  function where(me) {
    const ship = me.space?.startsWith('ship:') ? me.space.slice(5) : null;
    const owner = ship && pilots().find((c) => c.name === ship);
    const docked = owner?.pad && W.planet(galaxy, owner.pad.station) ? owner.pad.station : null;
    const station = me.space?.startsWith('station:') ? me.space.slice(8) : me.pad?.station ?? null;
    return { over: owner ? docked || owner.over || null : null, station };
  }

  // dock_request, enter_space, leave_space and ship_open.
  function space(ws, me, msg) {
    let result = { ok: true };
    if (msg.type === 'dock_request') result = spaces.dock(me, msg.station);
    else if (msg.type === 'land_request') result = spaces.land(me, msg.base, msg.lander === true);
    else if (msg.type === 'enter_space') result = spaces.enter(me, msg.space, msg);
    else if (msg.type === 'leave_space') spaces.leave(me);
    else spaces.setOpen(me, msg.open);
    if (!result.ok) send(ws, { type: 'error', reason: result.reason });
    else if (msg.type === 'land_request' || msg.type === 'dock_request') broadcastState(); // the berths changed
  }

  function pilotFaction(me) {
    return Object.hasOwn(galaxy.pilots, me.name) ? galaxy.pilots[me.name].faction ?? null : null;
  }

  // A character's record notes when its app last spoke: the director counts who is active.
  function seen(me) {
    const book = me.role === 'builder' ? galaxy.bases : me.role === 'explorer' ? galaxy.pilots : null;
    if (book && Object.hasOwn(book, me.name)) book[me.name].seenAt = now();
  }

  // The admins-only faction (the Coma Conglomerate) a character plays for, or null. Names are not
  // passwords, so such a character needs the key: at hello, and again with every message, in case
  // an admin took it into Coma while another app was playing it.
  function adminsOnly(role, name) {
    const book = role === 'builder' ? galaxy.bases || {} : galaxy.pilots;
    const f = Object.hasOwn(book, name) ? book[name].faction : null;
    return Object.hasOwn(F.FACTIONS, f) && !F.FACTIONS[f].playable ? F.FACTIONS[f] : null;
  }

  // Turns an app away from a character: with no role, nothing it sends is acted on and it hears
  // nothing more of the galaxy.
  function turnAway(ws, me, faction) {
    me.role = me.name = null;
    send(ws, { type: 'error', reason: `that character plays for the ${faction.name}: admins only` });
  }

  // --- Raids ---------------------------------------------------------------------------

  function toRaider(run, msg) {
    for (const [ws, c] of clients) if (c.role === 'explorer' && c.name === run.pilot) send(ws, { ...msg, type: 'raid' });
  }

  function sendContainer(run) {
    const t = now();
    run.sent = new Set(H.revealed(run, t).map((it) => it.uid));
    toRaider(run, { ev: 'container', ...H.containerView(run, t) });
  }

  function sendInventory(run) {
    toRaider(run, { ev: 'inventory', items: H.inventoryView(run) });
    toRaider(run, { ev: 'pouch', pouch: run.pouch, vest: run.vest, grenades: run.grenades });
  }

  function sendHeat(run) {
    const t = now();
    toRaider(run, { ev: 'heat', heat: run.heat, level: H.heatLevel(run.heat), remaining: run.endsAt - t, extracts: H.extractStates(run, t), vaultOpen: run.vaultOpen, ...H.stage(run, t) });
  }

  function endRun(run, outcome) {
    runs.delete(run.pilot);
    const result = G.endRaid(galaxy, run, outcome, now());
    toRaider(run, { ev: 'end', result });
    changed();
  }

  function raidTick() {
    const t = now();
    for (const run of runs.values()) {
      if (run.selfDestructAt && t >= run.selfDestructAt) {
        endRun(run, 'destroyed');
        continue;
      }
      const wave = H.waveTick(run, t);
      if (wave) toRaider(run, { ev: 'wave', ...wave });
      if (t >= run.endsAt) {
        endRun(run, 'mia');
        continue;
      }
      // Items reveal as the search reaches them; nothing is sent before then.
      if (run.open) {
        for (const it of H.revealed(run, t)) {
          if (run.sent.has(it.uid)) continue;
          run.sent.add(it.uid);
          toRaider(run, { ev: 'reveal', container: run.open, item: it });
        }
      }
      const before = H.heatLevel(run.heat);
      const heatBefore = run.heat;
      H.heatTick(run, t);
      if (run.heat !== heatBefore || t - (run.heatSentAt || 0) > 5000) {
        run.heatSentAt = t;
        sendHeat(run);
        G.raidChanged(galaxy, run);
        if (H.heatLevel(run.heat) !== before) changed();
      }
    }
  }

  // Raid messages from the raider's app. Returns a result like the galaxy rules do.
  function raid(ws, me, msg) {
    const t = now();
    if (msg.type === 'raid_start') {
      const r = G.startRaid(galaxy, me.name, msg.planet, msg.slot, t, crypto.randomInt(2 ** 31), crypto.randomInt(2 ** 31));
      if (!r.ok) return r;
      runs.set(me.name, r.run);
      send(ws, { type: 'raid', ev: 'begin', run: H.briefing(r.run, t) });
      return r;
    }
    const run = runs.get(me.name);
    if (!run) return { ok: false, reason: 'not in a raid' };
    let r;
    switch (msg.type) {
      case 'raid_open':
        r = H.openContainer(run, String(msg.container), t);
        if (r.ok) sendContainer(run);
        return { ...r, quiet: true };
      case 'raid_close':
        H.closeContainer(run, t);
        sendContainer(run);
        return { ok: true, quiet: true };
      case 'raid_take':
        r = H.take(run, String(msg.uid), msg.to === 'secure' ? 'secure' : 'backpack', t, Number(msg.armor) || 0);
        break;
      case 'raid_drop':
        r = H.drop(run, String(msg.uid), t);
        break;
      case 'raid_stow':
        r = H.stow(run, String(msg.uid), msg.to === 'secure' ? 'secure' : 'backpack');
        break;
      case 'raid_use_start':
        r = H.useStart(run, String(msg.item), t);
        if (r.ok) send(ws, { type: 'raid', ev: 'using', item: r.item, seconds: r.seconds });
        return { ...r, quiet: true };
      case 'raid_use_stop':
        return { ...H.useStop(run), quiet: true };
      case 'raid_use_finish':
        r = H.useFinish(run, t);
        if (r.ok) send(ws, { type: 'raid', ev: 'used', item: r.item, health: r.health, armor: r.armor });
        break;
      case 'raid_pickup':
        r = H.pickUp(run, String(msg.id), Number(msg.armor) || 0);
        if (r.ok) toRaider(run, { ev: 'loose', loose: H.looseView(run) });
        break;
      case 'raid_grenade':
        r = H.fireGrenade(run, t);
        if (r.ok && r.changed) changed();
        break;
      case 'raid_noise':
        r = H.report(run, String(msg.kind), t);
        if (r.ok && r.changed) {
          G.raidChanged(galaxy, run);
          changed();
        }
        return { ...r, quiet: true };
      case 'raid_keycard':
        r = H.useKeycard(run, t);
        break;
      case 'raid_drill_start':
        r = H.drillStart(run, t);
        if (r.ok) send(ws, { type: 'raid', ev: 'drill', seconds: r.seconds });
        return { ...r, quiet: true };
      case 'raid_drill_stop':
        return { ...H.drillStop(run), quiet: true };
      case 'raid_drill_finish':
        r = H.drillFinish(run, t);
        break;
      case 'raid_destroy':
        r = H.destroy(run, String(msg.piece), t);
        if (r.ok && r.changed) changed();
        break;
      case 'raid_enter':
        r = H.enterDoor(run, t);
        break;
      case 'raid_vent_start':
        r = H.ventStart(run, String(msg.vent), t);
        if (r.ok) send(ws, { type: 'raid', ev: 'vent', vent: msg.vent, seconds: r.seconds });
        break;
      case 'raid_vent_stop':
        return { ...H.ventStop(run), quiet: true };
      case 'raid_vent_finish':
        r = H.ventFinish(run, t);
        break;
      case 'raid_floor':
        r = H.reachFloor(run, Number(msg.floor));
        break;
      case 'raid_land':
        r = H.land(run, msg.x, msg.z, t);
        if (r.ok) send(ws, { type: 'raid', ev: 'landed', landing: r.landing });
        break;
      case 'raid_extract_start':
        r = H.extractStart(run, String(msg.extract), t);
        if (r.ok) send(ws, { type: 'raid', ev: 'extracting', extract: msg.extract, countdown: r.countdown, loud: r.loud });
        return { ...r, quiet: true };
      case 'raid_extract_stop':
        return { ...H.extractStop(run), quiet: true };
      case 'raid_extract_finish':
        r = H.extractFinish(run, t);
        if (r.ok) endRun(run, 'extracted');
        return { ...r, quiet: true };
      case 'raid_died':
        endRun(run, 'killed');
        return { ok: true, quiet: true };
      case 'raid_bail':
        if (t - run.startedAt > H.BAIL_WINDOW_MS) return { ok: false, reason: 'too late to bail: find an extract' };
        endRun(run, 'bailed');
        return { ok: true, quiet: true };
      default:
        return { ok: false, reason: `unknown message ${msg.type}` };
    }
    if (r.ok) {
      sendInventory(run);
      if (run.open) sendContainer(run);
      sendHeat(run);
      G.raidChanged(galaxy, run);
    }
    return { ...r, quiet: true };
  }

  function handle(ws, me, msg) {
    if (msg.type === 'hello') {
      const role = msg.role === 'builder' ? 'builder' : 'explorer';
      const name = String(msg.name || `Pilot ${me.id}`).slice(0, 24);
      me.admin = isAdmin(msg.admin_key);
      // Names key the galaxy's books of characters, so none may be one every object already has.
      if (name in Object.prototype) {
        me.role = me.name = null;
        return send(ws, { type: 'error', reason: `"${name}" can't be a name: pick another` });
      }
      const locked = !me.admin && adminsOnly(role, name);
      if (locked) return turnAway(ws, me, locked);
      me.role = role;
      me.name = name;
      const catalog = {
        sites: { grid: S.GRID, core: S.CORE, max: S.MAX_SITES, pieces: S.PIECES, obstacles: S.OBSTACLES },
        ships: N.SHIPS, hangar: N.HANGAR, shipQueueMax: N.QUEUE_MAX,
        items: H.ITEMS, facilities: H.FACILITIES, security: H.SECURITY, heatLevels: H.HEAT_LEVELS, alarmCost: H.ALARM_COST, fenceRate: H.FENCE_RATE,
        buildings: G.BUILDINGS, nodes: G.NODES, commandSlot: G.COMMAND_SLOT, commandLevels: G.COMMAND_LEVELS,
        storage: { base: G.STORAGE_BASE, perLevel: G.STORAGE_PER_LEVEL }, powerBoost: G.POWER_BOOST, produces: G.PRODUCES,
        berthsPerLevel: G.BERTHS_PER_LEVEL, berthsMax: G.BERTHS_MAX, tariff: G.TARIFF, wantMax: G.WANT_MAX, autoShipMs: G.AUTO_SHIP_MS, buildTimes: G.BUILD_S, maxLevel: G.MAX_LEVEL, levelGrowth: G.LEVEL_GROWTH,
        buildSpeed: Number.isFinite(galaxy.buildSpeed) ? galaxy.buildSpeed : 0,
        // The faction war
        factions: F.FACTIONS,
        ranks: F.RANKS,
        outposts: { max: S.MAX_SITES, perSector: S.PER_SECTOR },
        war: {
          lockMs: W.lockMs(), carrierShare: W.CARRIER_SHARE, battleMs: W.BATTLE_MS, upkeepMs: W.UPKEEP_MS, upkeep: W.UPKEEP,
          fuelCredits: W.FUEL_CREDITS, planetShare: W.PLANET_SHARE, sectorPilots: W.SECTOR_PILOTS,
        },
        contractItems: G.CONTRACT_ITEMS,
        meritValue: G.MERIT_VALUE,
        demo,
        carrier: W.isDemo(), // the demo war: every pilot flies a fleet carrier
        director: { ms: D.DIRECTOR_MS, scaleMax: D.SCALE_MAX, patrolPower: D.PATROL_POWER, armadaCap: D.ARMADA_CAP, activeMs: D.ACTIVE_MS },
      };
      // A Builder gets their own home planet the first time they connect.
      const home = me.role === 'builder' ? G.claimBase(galaxy, me.name).id : null;
      if (demo && home) G.demoTopUp(G.econ(galaxy, home));
      send(ws, { type: 'welcome', id: me.id, name: me.name, home, admin: me.admin, state: stateFor(me), catalog });
      if (home) {
        broadcastState(ws); // the new Builder already has it
        save();
      }
      // Back after a dropped connection mid-raid: pick up where the run is.
      const run = me.role === 'explorer' && runs.get(me.name);
      if (run) {
        H.closeContainer(run, now());
        send(ws, { type: 'raid', ev: 'begin', run: H.briefing(run, now()) });
      }
      return;
    }
    if (!me.role) return send(ws, { type: 'error', reason: 'say hello first' });
    const locked = !me.admin && adminsOnly(me.role, me.name);
    if (locked) return turnAway(ws, me, locked);

    if (Object.hasOwn(BUILDER_ONLY, msg.type) && me.role !== 'builder') return send(ws, { type: 'error', reason: BUILDER_ONLY[msg.type] });
    if (Object.hasOwn(PILOT_ONLY, msg.type) && me.role !== 'explorer') return send(ws, { type: 'error', reason: PILOT_ONLY[msg.type] });
    if (ADMIN_ONLY.includes(msg.type) && !me.admin) return send(ws, { type: 'error', reason: 'admins only' });

    // Builders can only manage their own planets.
    const MANAGE = ['build', 'post_job', 'ship_cargo', 'upgrade_security', 'sound_alarm', 'queue_ship', 'cancel_ship', 'place_piece', 'remove_piece', 'clear_obstacle', 'upgrade_building'];
    if (MANAGE.includes(msg.type)) {
      if (msg.type === 'post_job' && !msg.planet) msg.planet = galaxy.system.planets.find((p) => p.owner === me.name)?.id || 'aster';
      if (!G.owns(galaxy, me.name, msg.planet)) return send(ws, { type: 'error', reason: 'that is not your planet' });
    }

    let result = null;
    switch (msg.type) {
      case 'build':
        result = G.build(galaxy, msg.planet, msg.slot, msg.building, now());
        break;
      case 'post_job':
        result = G.postJob(galaxy, msg.resource, msg.amount, msg.reward, msg.planet);
        break;
      case 'collect':
        result = G.collect(galaxy, me.name, msg.resource, msg.amount);
        break;
      case 'deliver':
        result = G.deliver(galaxy, me.name, msg.job);
        break;
      case 'ship_cargo':
        result = G.ship(galaxy, msg.planet, msg.slot, now());
        break;
      case 'upgrade_security':
        result = G.secure(galaxy, msg.planet, msg.slot);
        break;
      case 'sound_alarm': {
        const run = [...runs.values()].find((r) => r.planet === msg.planet && r.slot === msg.slot);
        result = G.alarm(galaxy, msg.planet, msg.slot, run, now());
        if (result.ok) sendHeat(run);
        break;
      }
      case 'sell':
        result = G.sell(galaxy, me.name);
        break;
      case 'found_site':
        result = G.foundSite(galaxy, me.name, msg.facility, msg.planet, msg.sector, now());
        break;
      case 'launch_attack':
        result = { ok: false, reason: 'fleets fight for control of systems now: send them from the War map' };
        break;
      // --- The faction war ---
      case 'choose_faction':
        result = G.chooseFaction(galaxy, me.role, me.name, msg.faction, now(), { admin: me.admin });
        // An admin took this character into Coma: any other app playing it without the key is turned away.
        if (result.ok && adminsOnly(me.role, me.name))
          for (const [other, c] of clients) if (other !== ws && !c.admin && c.role === me.role && c.name === me.name) turnAway(other, c, F.FACTIONS[result.faction]);
        break;
      case 'send_fleet':
        result = W.sendFleet(galaxy, me.name, msg.system, msg.ships && typeof msg.ships === 'object' ? msg.ships : null, now());
        break;
      case 'recall_fleet':
        result = W.recallFleet(galaxy, me.name, msg.fleet, now());
        break;
      case 'set_price':
        result = G.setPrice(galaxy, me.name, msg.item, msg.price);
        break;
      case 'fill_contract':
        result = G.fillContract(galaxy, me.name, msg.contract, msg.qty);
        break;
      case 'donate':
        result = G.donate(galaxy, me.name, msg.item, msg.qty);
        break;
      case 'dock_buy':
        result = G.dockBuy(galaxy, me.name, msg.builder, msg.item, msg.qty);
        break;
      case 'set_bid':
        result = G.setBid(galaxy, me.name, msg.item, msg.price, msg.want);
        break;
      case 'sell_to_builder': {
        // From a berth at the Builder's Star Port, at full price; from their High Port, less the tariff.
        const home = galaxy.system.planets.find((p) => p.owner === msg.builder && p.kind !== 'satellite');
        if (home && me.berth?.base === home.id) result = G.sellToBuilder(galaxy, me.name, msg.builder, msg.item, msg.qty, false);
        else if (home && me.pad?.station === home.id) result = G.sellToBuilder(galaxy, me.name, msg.builder, msg.item, msg.qty, true);
        else result = { ok: false, reason: `land at ${msg.builder}'s Star Port or dock at their High Port to trade` };
        break;
      }
      case 'post_contract':
        result = G.postContract(galaxy, me.name, msg.item, msg.amount, msg.reward);
        break;
      case 'cancel_contract':
        result = G.cancelContract(galaxy, me.name, msg.contract);
        break;
      case 'demo_capture':
        result = demo ? G.demoCapture(galaxy, me.name, msg.planet, msg.sector, now()) : { ok: false, reason: 'taking sectors by hand is only for demo mode' };
        break;
      // --- Admins: the Coma Conglomerate and its director ---
      case 'director_set':
        result = D.set(galaxy, { paused: msg.paused, scale: msg.scale, overrides: msg.overrides, posture: msg.posture }, now());
        break;
      case 'admin_armada':
        result = D.armada(galaxy, msg.system, msg.power, now());
        break;
      case 'admin_recall':
        result = D.recall(galaxy, msg.fleet, now());
        break;
      case 'admin_capture':
        result = W.capture(galaxy, msg.planet, msg.sector, 'coma', now());
        break;
      case 'place_piece':
        result = G.placePiece(galaxy, msg.planet, msg.piece, msg.x, msg.y);
        break;
      case 'remove_piece':
        result = G.removePiece(galaxy, msg.planet, msg.piece);
        break;
      case 'upgrade_building':
        result = G.upgradeBuilding(galaxy, msg.planet, msg.slot, now());
        break;
      case 'clear_obstacle':
        result = G.clearObstacle(galaxy, msg.planet, msg.obstacle);
        break;
      case 'queue_ship':
        result = G.queueShip(galaxy, msg.planet, msg.slot, msg.ship, now());
        break;
      case 'cancel_ship':
        result = G.cancelShip(galaxy, msg.planet, msg.slot);
        break;
      case 'chat': {
        // Chat is relayed to everyone (sender included, so all apps show the same order), not saved.
        const text = String(msg.text || '').replace(/\s+/g, ' ').trim().slice(0, CHAT_MAX);
        if (!text) return;
        const now = Date.now();
        if (now - (me.lastChat || 0) < CHAT_GAP_MS) return send(ws, { type: 'error', reason: 'chat: slow down' });
        me.lastChat = now;
        broadcast({ type: 'chat', name: me.name, role: me.role, text });
        return;
      }
      case 'ship':
        // Ship positions are relayed, not saved. `over`: the war planet whose orbit the ship is in;
        // `berth`: the pad it holds ({station, copy, pad}), so the others can tell station copies apart.
        me.over = typeof msg.over === 'string' && W.planet(galaxy, msg.over) ? msg.over : null;
        broadcast({ type: 'ship', id: me.id, name: me.name, pos: msg.pos, rot: msg.rot, over: me.over ?? undefined, berth: me.pad ?? undefined }, ws);
        return;
      // --- Shared spaces: stations, carriers and bases on foot ---
      // (Too many of these in a second are dropped without a word; walk has its own limit, and
      // undock is never dropped.)
      case 'undock':
        spaces.undock(me);
        return;
      case 'dock_request':
      case 'land_request':
      case 'enter_space':
      case 'leave_space':
      case 'ship_open':
        if (tooFast(me, 'space', SPACE_MSGS_PER_S)) return;
        return space(ws, me, msg);
      case 'walk':
        spaces.walk(me, msg, Date.now());
        return;
      // --- Sector battles ---
      case 'battle_start':
      case 'battle_join':
        if (tooFast(me, 'battle', BATTLE_JOINS_PER_S)) return;
        result = msg.type === 'battle_start' ? battles.start(me, pilotFaction(me), msg.planet, msg.sector, where(me)) : battles.join(me, pilotFaction(me), msg.battle, where(me));
        if (!result.ok) send(ws, { type: 'error', reason: result.reason });
        return;
      case 'battle_leave':
      case 'battle_drop':
      case 'battle_order':
      case 'battle_produce':
      case 'battle_possess':
      case 'battle_drive':
      case 'battle_release':
        result = battles.handle(me, msg);
        if (!result.ok) send(ws, { type: 'error', reason: result.reason });
        return;
      default:
        if (typeof msg.type === 'string' && msg.type.startsWith('raid_') && me.role === 'explorer') {
          const t = now();
          if (t - (me.raidWindow || 0) >= 1000) [me.raidWindow, me.raidCount] = [t, 0];
          if (++me.raidCount > RAID_MSGS_PER_S) return;
          result = raid(ws, me, msg);
          if (result.ok && !result.quiet) changed();
          else if (!result.ok) send(ws, { type: 'error', reason: result.reason });
          return;
        }
        return send(ws, { type: 'error', reason: `unknown message ${msg.type}` });
    }
    if (result.ok) changed();
    else send(ws, { type: 'error', reason: result.reason });
  }

  wss.on('connection', (ws) => {
    const me = { id: nextClientId++, role: null, name: null, admin: false, ws };
    clients.set(ws, me);
    ws.on('message', (data) => {
      let msg;
      try {
        msg = JSON.parse(data);
      } catch {
        return send(ws, { type: 'error', reason: 'bad json' });
      }
      try {
        handle(ws, me, msg);
      } catch (err) {
        // One bad request mustn't take the whole galaxy down with it.
        console.error(`error handling ${msg?.type}:`, err);
        return send(ws, { type: 'error', reason: 'the server hit an error' });
      }
      seen(me);
    });
    ws.on('close', () => {
      const berthed = Boolean(me.berth);
      spaces.drop(me);
      battles.leave(me);
      clients.delete(ws);
      if (me.role === 'explorer') broadcast({ type: 'left', id: me.id });
      if (berthed) broadcastState(); // a Star Port berth came free
    });
  });

  const ticker = setInterval(() => {
    try {
      if (G.tick(galaxy, now())) changed();
    } catch (err) {
      console.error('error in the galaxy tick:', err);
    }
  }, tickMs);
  const raidTicker = setInterval(raidTick, RAID_TICK_MS);

  return {
    wss,
    get galaxy() {
      return galaxy;
    },
    runs,
    spaces,
    battles,
    close() {
      clearInterval(ticker);
      clearInterval(raidTicker);
      battles.close();
      clearTimeout(saveTimer);
      for (const ws of clients.keys()) ws.terminate();
      return new Promise((resolve) => wss.close(resolve));
    },
  };
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 8080;
  const saveFile = process.env.SAVE_FILE || path.join(__dirname, 'galaxy.json');
  const demo = process.env.DEMO === '1';
  // BUILD_SPEED=0 builds instantly (the game smoke tests use it); any other number divides build times.
  const speed = process.env.BUILD_SPEED;
  const buildSpeed = speed === undefined ? null : Number(speed) === 0 ? Infinity : Number(speed);
  // ADMIN_KEY: unset or empty, nobody is an admin.
  const adminKey = process.env.ADMIN_KEY || null;
  // BATTLE_SPEED: sector battles run this many times faster (default 1).
  const battleSpeed = Number(process.env.BATTLE_SPEED) > 0 ? Number(process.env.BATTLE_SPEED) : 1;
  const { wss } = startServer({ port, saveFile, demo, demoWar: demo, buildSpeed, adminKey, battleSpeed });
  wss.on('listening', () => {
    console.log(
      `Galaxy server listening on ws://0.0.0.0:${port}${demo ? ' (demo mode: bases start rich, the demo war is on)' : ''}${battleSpeed !== 1 ? ` (battles at ${battleSpeed}x)` : ''}${adminKey ? ' (admin key set)' : ''}`
    );
    // The addresses to type on a phone on the same Wi-Fi.
    for (const list of Object.values(os.networkInterfaces())) {
      for (const a of list || []) {
        if (a.family === 'IPv4' && !a.internal) console.log(`  Phone: ws://${a.address}:${port}`);
      }
    }
  });
}

module.exports = { startServer, adminCheck };
