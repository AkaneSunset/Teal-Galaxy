// Galaxy server: holds the shared galaxy, applies actions from the apps,
// and tells every connected app when something changes.
//
//   node server.js            (listens on port 8080, saves to galaxy.json)
//   PORT=9000 SAVE_FILE=x.json node server.js

const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const G = require('./galaxy');

const TICK_MS = 5000;
const CHAT_MAX = 200;
const CHAT_GAP_MS = 500; // at most two chat lines a second per player

function startServer({ port = 8080, saveFile = null, tickMs = TICK_MS } = {}) {
  let galaxy = G.newGalaxy();
  if (saveFile && fs.existsSync(saveFile)) {
    galaxy = JSON.parse(fs.readFileSync(saveFile, 'utf8'));
    console.log(`Loaded galaxy from ${saveFile}`);
  }

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

  function handle(ws, me, msg) {
    if (msg.type === 'hello') {
      me.role = msg.role === 'builder' ? 'builder' : 'explorer';
      me.name = String(msg.name || `Pilot ${me.id}`).slice(0, 24);
      send(ws, { type: 'welcome', id: me.id, name: me.name, state: galaxy });
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

  return {
    wss,
    get galaxy() {
      return galaxy;
    },
    close() {
      clearInterval(ticker);
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
