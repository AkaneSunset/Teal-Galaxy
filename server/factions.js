// The four factions of the war, War Merit ranks, and picking a side.
// Faction is per character: every Builder base and every pilot picks its own, once.
// A Builder's faction is on their economy (g.bases[name].faction), a pilot's on g.pilots[name].faction.
// Players pick from three; the Coma Conglomerate is played by server admins and the AI director
// (director.js).

const H = require('./heist');
const S = require('./sites');

// The four factions mirror Supreme Commander's: UEF, Cybran, Aeon and Seraphim. `playable`: open
// to players (the Coma Conglomerate is for admins only).
const FACTIONS = {
  compact: { name: 'Terran Compact', mirrors: 'UEF', color: '#4f8fe0', capital: 'fortitude',
    style: 'Durable and methodical: shields, artillery, heavy armour', bonus: 'Outpost defences are 25% tougher in raids', playable: true },
  ashen: { name: 'Ashen Collective', mirrors: 'Cybran', color: '#e0564f', capital: 'umbra',
    style: 'Fast and tricky: stealth, cloaking, hit and run', bonus: 'Raiders build Heat 25% faster inside your outposts', playable: true },
  luminar: { name: 'Luminar Accord', mirrors: 'Aeon', color: '#5fd99a', capital: 'aurelia',
    style: 'Hover units, precise and powerful strikes', bonus: 'Outposts produce 20% more', playable: true },
  coma: { name: 'Coma Conglomerate', mirrors: 'Seraphim', color: '#b07ae0', capital: 'comae',
    style: 'Alien tech, strong all-round units, the strategic missile', bonus: 'Outposts recover from raids twice as fast', playable: false },
};
const PLAYABLE = Object.keys(FACTIONS).filter((f) => FACTIONS[f].playable);

// The bonuses above as numbers, for the rules that apply them.
const PERKS = {
  compact: { hp: 1.25 }, // outpost pieces' hit points in a raid
  ashen: { heat: 1.25 }, // Heat a raider builds inside
  luminar: { production: 0.2 }, // extra vault production
  coma: { cooldown: 0.5 }, // raid cooldown
};

// War Merit, earned by donating to the faction's war supply. Each rank adds to outpost production.
const RANKS = [
  { name: 'Recruit', from: 0, bonus: 0 },
  { name: 'Supplier', from: 500, bonus: 0.02 },
  { name: 'Quartermaster', from: 2000, bonus: 0.04 },
  { name: 'Provisioner', from: 8000, bonus: 0.06 },
  { name: 'War Industrialist', from: 25000, bonus: 0.08 },
];

const ALERTS_MAX = 20;

function fail(reason) {
  return { ok: false, reason };
}

function rank(merit) {
  let out = RANKS[0];
  for (const r of RANKS) if ((merit || 0) >= r.from) out = r;
  return out;
}

function perk(faction, key, otherwise) {
  return PERKS[faction]?.[key] ?? otherwise;
}

// "the Terran Compact"
function the(faction) {
  return `the ${FACTIONS[faction].name}`;
}

// A message on a Builder's phone, shown once as a toast. Keeps the last ALERTS_MAX.
function alert(e, text, at = Date.now()) {
  e.alerts ||= [];
  e.alerts.push({ at, text });
  if (e.alerts.length > ALERTS_MAX) e.alerts.splice(0, e.alerts.length - ALERTS_MAX);
}

function log(g, text) {
  g.feed.push({ at: Date.now(), text });
  if (g.feed.length > 50) g.feed.shift();
}

// Sets a character's faction, once. `role` is 'builder' (a base, which must be claimed first)
// or 'explorer' (a pilot). Only an admin may pick a faction that isn't open to players. A
// Builder's outposts from before factions move to their side's ground.
function chooseFaction(g, role, name, faction, { admin = false } = {}) {
  // Own keys only, here and below: 'constructor' is no faction, and '__proto__' no character.
  if (!Object.hasOwn(FACTIONS, faction)) return fail('no such faction');
  if (!FACTIONS[faction].playable && !admin) return fail(`${the(faction)} isn't open to players`);
  let rec;
  if (role === 'builder') {
    rec = Object.hasOwn(g.bases || {}, name) ? g.bases[name] : null;
    if (!rec) return fail('claim a base first');
  } else if (role === 'explorer') {
    if (!Object.hasOwn(g.pilots, name)) g.pilots[name] = { credits: 0, reputation: 0, cargo: {} };
    rec = g.pilots[name];
    rec.hold ||= {};
  } else return fail('no such role');
  if (rec.faction) return fail('your faction is already set');
  rec.faction = faction;
  log(g, `${name} joined ${the(faction)}`);
  const moved = role === 'builder' ? relocate(g, name) : [];
  return { ok: true, faction, moved: moved.map((s) => s.id) };
}

// --- Outposts from before the war ----------------------------------------------------------

// The sector of a planet in the Builder's system, held by `faction` on a planet it holds, with the
// fewest outposts (all Builders'); the first such one on a tie. Null if there's nowhere with room.
function roomiest(g, faction) {
  let best = null;
  for (const wp of g.war?.planets || []) {
    if (wp.system !== g.system.id || wp.owner !== faction) continue;
    for (const sector of wp.sectors) {
      if (sector.owner !== faction) continue;
      const n = S.sectorSites(g, sector.id).length;
      if (n < S.PER_SECTOR && (!best || n < best.n)) best = { planet: wp, sector, n };
    }
  }
  return best;
}

// Outposts founded before factions have no sector. Once their Builder picks a faction, each one
// takes the faction and moves to the roomiest sector it holds in their system (a new place, name
// and parent planet). If the faction holds no planet there it stays put, dormant, until one does
// (war.js calls this again every tick). Returns the sites that moved.
function relocate(g, owner, now = Date.now()) {
  const e = g.bases?.[owner];
  if (!e?.faction) return [];
  const moved = [];
  for (const site of g.system.planets) {
    if (site.kind !== 'satellite' || site.owner !== owner || site.sector) continue;
    site.faction = e.faction;
    const spot = roomiest(g, e.faction);
    if (!spot) continue;
    const was = site.name;
    const type = site.buildings[0]?.type;
    S.settle(g, site, spot.planet, spot.sector, H.FACILITIES[type]?.name || 'Outpost');
    alert(e, `${was} moved to ${spot.sector.name}, held by ${the(e.faction)}`, now);
    log(g, `${was} moved to ${spot.sector.name}`);
    moved.push(site);
  }
  return moved;
}

module.exports = { FACTIONS, PLAYABLE, PERKS, RANKS, ALERTS_MAX, rank, perk, the, alert, chooseFaction, relocate };
