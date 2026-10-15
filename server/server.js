// Galaxy server: holds the shared galaxy, applies actions from the apps,
// and tells every connected app when something changes.
//
//   node server.js            (listens on port 8080, saves to galaxy.json)
//   PORT=9000 SAVE_FILE=x.json node server.js

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');
const G = require('./galaxy');
const H = require('./heist');

const TICK_MS = 5000;
const CHAT_MAX = 200;
const CHAT_GAP_MS = 500; // at most two chat lines a second per player
const RAID_TICK_MS = 200; // reveals, Heat and the run clock
const RAID_MSGS_PER_S = 30; // per raider; more than this is dropped

function startServer({ port = 8080, saveFile = null, tickMs = TICK_MS, now = Date.now } = {}) {
  let galaxy = G.newGalaxy();
  if (saveFile && fs.existsSync(saveFile)) {
    galaxy = JSON.parse(fs.readFileSync(saveFile, 'utf8'));
    G.recoverRaids(galaxy);
    console.log(`Loaded galaxy from ${saveFile}`);
  }
  const runs = new Map(); // pilot name -> live raid run (server only: holds container contents)

  const wss = new WebSocketServer({ port });
  const clients = new Map(); // ws -> { id, role, name }
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

  function broadcast(msg, except = null) {
    for (const ws of clients.keys()) if (ws !== except) send(ws, msg);
  }

  function changed() {
    broadcast({ type: 'state', state: galaxy });
    save();
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
    toRaider(run, { ev: 'inventory', items: H.inventoryView(run).map((it) => ({ ...H.publicItem(it), grid: it.grid, rect: it.rect })) });
  }

  function sendHeat(run) {
    const t = now();
    toRaider(run, { ev: 'heat', heat: run.heat, level: H.heatLevel(run.heat), remaining: run.endsAt - t, extracts: H.extractStates(run, t), vaultOpen: run.vaultOpen });
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
        r = H.take(run, String(msg.uid), msg.to === 'secure' ? 'secure' : 'backpack', t);
        break;
      case 'raid_drop':
        r = H.drop(run, String(msg.uid), t);
        break;
      case 'raid_stow':
        r = H.stow(run, String(msg.uid), msg.to === 'secure' ? 'secure' : 'backpack');
        break;
      case 'raid_use':
        r = H.use(run, String(msg.uid));
        if (r.ok) send(ws, { type: 'raid', ev: 'heal', amount: r.heal });
        break;
      case 'raid_noise':
        r = H.report(run, String(msg.kind), t);
        if (r.ok && r.changed) {
          G.raidChanged(galaxy, run);
          changed();
        }
        return { ...r, quiet: true };
      case 'raid_keycard':
        r = H.useKeycard(run);
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
      me.role = msg.role === 'builder' ? 'builder' : 'explorer';
      me.name = String(msg.name || `Pilot ${me.id}`).slice(0, 24);
      send(ws, { type: 'welcome', id: me.id, name: me.name, state: galaxy });
      // Back after a dropped connection mid-raid: pick up where the run is.
      const run = me.role === 'explorer' && runs.get(me.name);
      if (run) {
        H.closeContainer(run, now());
        send(ws, { type: 'raid', ev: 'begin', run: H.briefing(run, now()) });
      }
      return;
    }
    if (!me.role) return send(ws, { type: 'error', reason: 'say hello first' });

    let result = null;
    switch (msg.type) {
      case 'build':
        result = G.build(galaxy, msg.planet, msg.slot, msg.building);
        break;
      case 'post_job':
        result = G.postJob(galaxy, msg.resource, msg.amount, msg.reward);
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
        // Ship positions are relayed, not saved.
        broadcast({ type: 'ship', id: me.id, name: me.name, pos: msg.pos, rot: msg.rot }, ws);
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
    const me = { id: nextClientId++, role: null, name: null };
    clients.set(ws, me);
    ws.on('message', (data) => {
      let msg;
      try {
        msg = JSON.parse(data);
      } catch {
        return send(ws, { type: 'error', reason: 'bad json' });
      }
      handle(ws, me, msg);
    });
    ws.on('close', () => {
      clients.delete(ws);
      if (me.role === 'explorer') broadcast({ type: 'left', id: me.id });
    });
  });

  const ticker = setInterval(() => {
    if (G.tick(galaxy)) changed();
  }, tickMs);
  const raidTicker = setInterval(raidTick, RAID_TICK_MS);

  return {
    wss,
    get galaxy() {
      return galaxy;
    },
    runs,
    close() {
      clearInterval(ticker);
      clearInterval(raidTicker);
      clearTimeout(saveTimer);
      for (const ws of clients.keys()) ws.terminate();
      return new Promise((resolve) => wss.close(resolve));
    },
  };
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 8080;
  const saveFile = process.env.SAVE_FILE || path.join(__dirname, 'galaxy.json');
  startServer({ port, saveFile });
  console.log(`Galaxy server listening on ws://0.0.0.0:${port}`);
}

module.exports = { startServer };
