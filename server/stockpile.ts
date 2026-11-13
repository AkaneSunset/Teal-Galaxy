// Front stockpiles and war chests: what Builders' outposts make, used in the big battles.
//
// Each faction keeps a stockpile of finished war goods on each front (a contested planet with a
// campaign running). Builders send goods to it from the War screen's Supply tab; only finished war
// goods go (WAR_GOODS: no metal, ice, ores or intermediate materials). Every lot remembers the
// Builder who sent it, so a missile in a match is "a missile from Akane".
//
// A match that uses war goods (Supremacy, Sector Defense) takes a war chest from its side's
// stockpile for each pilot who joins: up to warChest.perPilot of each good (times the faction's
// underdog multiplier), and warChest.warheadsPerMatch strategic warheads a side at most. Sector
// Defense, always against AI, draws warChest.defenseShare of that. AI never draws. The match
// spends from the chest; when it ends, what wasn't used goes back to the stockpile at
// warChest.returnShare (rounded up), the rest lost in transit.
//
// A stockpile empties when its front's weekly campaign ends: every campaign starts from nothing.
//
// In the galaxy as g.war.stockpiles: planet -> { campaign: its startsAt, factions: faction ->
// item -> lots [{ from, qty }] }, oldest lot first.

const T = require('./tunables.ts');
const L = require('./ledger.ts');

const WAR_GOODS = ['lander_frame', 'hauler', 'drone_frame', 'weapon', 'fuel', 'missile', 'torpedo', 'warhead', 'sensor', 'shells', 'slugs'] as const;
type Good = (typeof WAR_GOODS)[number];

interface Lot {
  from: string;
  qty: number;
}
type Goods = Partial<Record<Good, Lot[]>>;
interface Front {
  campaign: number;
  factions: Record<string, Goods>;
}
interface Galaxy {
  war: {
    stockpiles?: Record<string, Front>;
    campaigns?: Record<string, { startsAt: number; endsAt: number; entrants: string[] }>;
  };
  director?: { strength?: Record<string, number> };
}
// A match's chest for one side.
interface Chest {
  planet: string;
  faction: string;
  campaign: number;
  goods: Goods;
  drawn: Record<string, number>; // what was taken, by good
  used: { item: Good; from: string; at: number }[];
}

const isGood = (item: string): item is Good => (WAR_GOODS as readonly string[]).includes(item);
const count = (lots: Lot[] | undefined) => (lots || []).reduce((a, l) => a + l.qty, 0);

// A front's stockpiles for the campaign running there now; a new campaign starts them from
// nothing. Null: no campaign on that planet.
function front(g: Galaxy, planet: string): Front | null {
  const c = g.war.campaigns?.[planet];
  if (!c) return null;
  const all = (g.war.stockpiles ||= {});
  let f = all[planet];
  if (!f || f.campaign !== c.startsAt) f = all[planet] = { campaign: c.startsAt, factions: {} };
  return f;
}

// Lots onto the end of a pile, merged with the last when it's from the same Builder.
function put(lots: Lot[], from: string, qty: number) {
  const last = lots[lots.length - 1];
  if (last && last.from === from) last.qty += qty;
  else lots.push({ from, qty });
}

// Up to `qty` off the front of a pile, as lots.
function take(lots: Lot[], qty: number): Lot[] {
  const out: Lot[] = [];
  while (qty > 0 && lots.length) {
    const l = lots[0];
    const n = Math.min(qty, l.qty);
    put(out, l.from, n);
    l.qty -= n;
    qty -= n;
    if (l.qty <= 0) lots.shift();
  }
  return out;
}

// A Builder's goods onto their faction's stockpile on a front.
function add(g: Galaxy, planet: string, faction: string, item: string, qty: number, from: string): { ok: true } | { ok: false; reason: string } {
  if (!isGood(item)) return { ok: false, reason: 'only finished war goods go to the front' };
  if (!Number.isInteger(qty) || qty < 1) return { ok: false, reason: 'bad amount' };
  const f = front(g, planet);
  if (!f) return { ok: false, reason: 'no campaign on that planet' };
  put(((f.factions[faction] ||= {})[item] ||= []), from, qty);
  return { ok: true };
}

// How many of each good a faction has on a front.
function totals(g: Galaxy, planet: string, faction: string): Record<string, number> {
  const goods = front(g, planet)?.factions[faction] || {};
  return Object.fromEntries(WAR_GOODS.map((k) => [k, count(goods[k])]));
}

// Every front's stockpiles, by faction and good (for the galaxy state).
function view(g: Galaxy) {
  const out: Record<string, Record<string, Record<string, number>>> = {};
  for (const planet of Object.keys(g.war.campaigns || {})) {
    const f = front(g, planet);
    if (!f) continue;
    out[planet] = {};
    for (const faction of Object.keys(f.factions)) out[planet][faction] = totals(g, planet, faction);
  }
  return out;
}

function newChest(g: Galaxy, planet: string, faction: string): Chest | null {
  const f = front(g, planet);
  if (!f || !faction) return null;
  return { planet, faction, campaign: f.campaign, goods: {}, drawn: {}, used: [] };
}

// One more pilot's share into a side's chest: up to warChest.perPilot of each of `goods` (the ones
// the match's mode uses; times the faction's underdog multiplier, times `share`), the warheads up to
// warheadsPerMatch for the match.
// Returns what came, by good.
function draw(g: Galaxy, chest: Chest | null, share = 1, goods: readonly string[] = WAR_GOODS): Record<string, number> {
  const got: Record<string, number> = {};
  if (!chest) return got;
  const f = front(g, chest.planet);
  if (!f || f.campaign !== chest.campaign) return got;
  const pile = f.factions[chest.faction];
  if (!pile) return got;
  const wc = T.get().warChest;
  const k = L.multiplier(g, chest.faction) * share;
  for (const item of WAR_GOODS) {
    if (!goods.includes(item)) continue;
    let want = Math.round(wc.perPilot[item] * k);
    if (item === 'warhead') want = wc.perPilot.warhead > 0 ? wc.warheadsPerMatch - (chest.drawn.warhead || 0) : 0;
    if (want <= 0 || !pile[item]?.length) continue;
    const lots = take(pile[item]!, want);
    const n = count(lots);
    if (!n) continue;
    for (const l of lots) put((chest.goods[item] ||= []), l.from, l.qty);
    chest.drawn[item] = (chest.drawn[item] || 0) + n;
    got[item] = n;
  }
  return got;
}

// How many of a good the chest holds.
function has(chest: Chest | null, item: Good): number {
  return chest ? count(chest.goods[item]) : 0;
}

// Spends `qty` of a good from the chest (at match time `t`); returns the Builders it came from
// (the first is the one to name), or null when the chest hasn't that many.
function use(chest: Chest | null, item: Good, qty = 1, t = 0): string[] | null {
  if (!chest || has(chest, item) < qty) return null;
  const lots = take(chest.goods[item]!, qty);
  for (const l of lots) chest.used.push({ item, from: l.from, at: t });
  return lots.map((l) => l.from);
}

// The match is over: what wasn't used goes back to the stockpile at warChest.returnShare, rounded
// up, unless the campaign it came from has ended. Returns what went back, by good.
function settle(g: Galaxy, chest: Chest | null): Record<string, number> {
  const back: Record<string, number> = {};
  if (!chest) return back;
  const f = front(g, chest.planet);
  const share = T.get().warChest.returnShare;
  for (const item of WAR_GOODS) {
    const lots = chest.goods[item] || [];
    const left = count(lots);
    if (!left) continue;
    const n = Math.min(left, Math.ceil(left * share));
    const kept = take(lots, n);
    if (f && f.campaign === chest.campaign) for (const l of kept) put(((f.factions[chest.faction] ||= {})[item] ||= []), l.from, l.qty);
    back[item] = n;
  }
  chest.goods = {};
  return back;
}

// What a chest holds, by good (for the apps).
function chestView(chest: Chest | null): Record<string, number> {
  if (!chest) return {};
  return Object.fromEntries(WAR_GOODS.filter((k) => has(chest, k) > 0).map((k) => [k, has(chest, k)]));
}

module.exports = { WAR_GOODS, isGood, front, add, totals, view, newChest, draw, has, use, settle, chestView };
