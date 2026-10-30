// The war-supply ledger: every bit of war supply a faction gets on a front (a contested planet),
// with where it came from. Sources:
//
//   builder   Builders' donations of goods (ledger.perMerit war supply per War Merit of goods)
//   battle    campaign matches: Sector Battles, Supremacy, Space Battles, Sector Defense
//   arena     Facility Battles
//   frontier  the Frontier's output (nothing feeds it yet)
//
// Each match credits every pilot in it ledger.match.win or .loss (times .aiShare against AI only).
// There is no daily cap. Two sources may each be only so much of a faction's war supply on a
// front this campaign (ledger.shares: arena 15%, frontier 40%): what would take one past its
// share isn't credited, and the receipt says so. Every credit is multiplied by the faction's
// underdog multiplier first (ledger.underdog: 0.8 for the strongest to 1.3 for the weakest, from
// the Coma director's measure of strength), and it never touches anything but war supply.
// Faction orders pay credits and War Merit, never war supply.
//
// In the galaxy as g.war.ledger: fronts (planet -> this campaign's totals by faction, and the
// last few campaigns'), and receipts (character -> the last few credits to them; never sent to
// apps but their own).

const T = require('./tunables.ts');

const SOURCES = ['builder', 'battle', 'arena', 'frontier'] as const;
type Source = (typeof SOURCES)[number];
const SOURCE_NAMES: Record<Source, string> = { builder: 'Builder donations', battle: 'battles', arena: 'the arena', frontier: 'the Frontier' };
const HOUR = 3600_000;

interface Supply {
  total: number;
  sources: Record<Source, number>;
  capped: Record<Source, number>; // what the shares kept out
  recent: [number, number][]; // [when, amount] over the last hour, for the rate
}
interface Front {
  campaign: number; // the campaign's startsAt these totals are for
  factions: Record<string, Supply>;
  history: { campaign: number; factions: Record<string, { total: number; sources: Record<Source, number> }> }[];
}
interface Receipt {
  at: number;
  planet: string;
  faction: string;
  source: Source;
  base: number;
  multiplier: number;
  credited: number;
  capped: number;
  text: string;
}
interface Ledger {
  fronts: Record<string, Front>;
  receipts: Record<string, Receipt[]>;
}
interface Galaxy {
  war: {
    ledger?: Ledger;
    campaigns?: Record<string, { startsAt: number; endsAt: number; entrants: string[] }>;
    planets: { id: string; name: string; system: string }[];
  };
  director?: { strength?: Record<string, number> };
}

const round1 = (x: number) => Math.round(x * 10) / 10;
const round3 = (x: number) => Math.round(x * 1000) / 1000;
const clamp = (x: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, x));
const zeroes = () => Object.fromEntries(SOURCES.map((s) => [s, 0])) as Record<Source, number>;

function ensure(g: Galaxy): Ledger {
  const l = (g.war.ledger ||= { fronts: {}, receipts: {} });
  l.fronts ||= {};
  l.receipts ||= {};
  return l;
}

function supply(): Supply {
  return { total: 0, sources: zeroes(), capped: zeroes(), recent: [] };
}

// A front's ledger for the campaign running there now: a new campaign files the last one's totals
// in its history (ledger.historyKept of them) and starts again from nothing. Null: no campaign.
function front(g: Galaxy, planet: string): Front | null {
  const c = g.war.campaigns?.[planet];
  if (!c) return null;
  const l = ensure(g);
  let f = l.fronts[planet];
  if (!f) f = l.fronts[planet] = { campaign: c.startsAt, factions: {}, history: [] };
  if (f.campaign !== c.startsAt) {
    const totals = Object.fromEntries(Object.entries(f.factions).map(([k, s]) => [k, { total: s.total, sources: { ...s.sources } }]));
    if (Object.keys(totals).length) f.history.unshift({ campaign: f.campaign, factions: totals });
    f.history.length = Math.min(f.history.length, T.get().ledger.historyKept);
    f.campaign = c.startsAt;
    f.factions = {};
  }
  return f;
}

// A faction's underdog multiplier: 1 at the mean strength of the player factions, more below it
// and less above, within ledger.underdog's range. (Coma, and anyone the director doesn't weigh: 1.)
function multiplier(g: Galaxy, faction: string): number {
  const s = g.director?.strength || {};
  if (!Object.hasOwn(s, faction)) return 1;
  const all = Object.values(s);
  const mean = all.reduce((a, x) => a + x, 0) / (all.length || 1);
  if (!(mean > 0)) return 1;
  const { min, max, slope } = T.get().ledger.underdog;
  return round3(clamp(1 - slope * (s[faction] / mean - 1), min, max));
}

function multipliers(g: Galaxy): Record<string, number> {
  return Object.fromEntries(Object.keys(g.director?.strength || {}).map((f) => [f, multiplier(g, f)]));
}

// The most `source` may add to a supply now without going past its share (Infinity: no share).
// With A of it in a total T, crediting c keeps (A + c) / (T + c) <= share.
function room(s: Supply, source: Source): number {
  const share = (T.get().ledger.shares as Record<string, number>)[source];
  if (share === undefined) return Infinity;
  if (share >= 1) return Infinity;
  return Math.max(0, (share * s.total - s.sources[source]) / (1 - share));
}

const pct = (x: number) => `${Math.round(x * 100)}%`;

// War supply for `faction` on front `planet` from `source`: `base`, times the underdog multiplier,
// as much of it as the source's share leaves room for. `who` ('role/name', or null) gets the
// receipt; `factionName` and the planet's name word it. Returns the receipt (null: no campaign on
// that planet, or nothing to credit).
function credit(g: Galaxy, { planet, faction, source, base, who = null, factionName = (f: string) => f }: { planet: string; faction: string; source: Source; base: number; who?: string | null; factionName?: (f: string) => string }, now = Date.now()): Receipt | null {
  if (!SOURCES.includes(source) || !(base > 0)) return null;
  const f = front(g, planet);
  const c = g.war.campaigns?.[planet];
  if (!f || !c || now >= c.endsAt || !c.entrants.includes(faction)) return null;
  const s = (f.factions[faction] ||= supply());
  const m = multiplier(g, faction);
  const raw = round1(base * m);
  const credited = round1(Math.min(raw, room(s, source)));
  const capped = round1(raw - credited);
  s.total = round1(s.total + credited);
  s.sources[source] = round1(s.sources[source] + credited);
  s.capped[source] = round1(s.capped[source] + capped);
  s.recent = s.recent.filter(([at]) => now - at < HOUR);
  if (credited > 0) s.recent.push([now, credited]);
  const where = g.war.planets.find((p) => p.id === planet)?.name || planet;
  const times = m !== 1 ? ` (${round1(base)} x${m} ${m > 1 ? 'underdog' : 'leading-side'} multiplier)` : '';
  let text = `+${credited} war supply for the ${factionName(faction)} on ${where} from ${SOURCE_NAMES[source]}${times}`;
  if (capped > 0) {
    const share = (T.get().ledger.shares as Record<string, number>)[source];
    text = `+${credited} of ${raw} war supply for the ${factionName(faction)} on ${where}: ${SOURCE_NAMES[source]} may be at most ${pct(share)} of a faction's war supply on a front, and ${capped} would have gone past it`;
  }
  const r: Receipt = { at: now, planet, faction, source, base: round1(base), multiplier: m, credited, capped, text };
  if (who) {
    const l = ensure(g);
    const list = (l.receipts[who] ||= []);
    list.unshift(r);
    list.length = Math.min(list.length, T.get().ledger.receiptsKept);
  }
  return r;
}

// Everyone's view of a front: this campaign's totals by faction (with what the shares kept out
// and the rate over the last hour), the last campaigns', and the multipliers in force.
function frontView(g: Galaxy, planet: string, now = Date.now()) {
  const f = front(g, planet);
  if (!f) return null;
  const factions: Record<string, { total: number; sources: Record<Source, number>; capped: Record<Source, number>; perHour: number }> = {};
  for (const [k, s] of Object.entries(f.factions)) {
    const perHour = round1(s.recent.filter(([at]) => now - at < HOUR).reduce((a, [, n]) => a + n, 0));
    factions[k] = { total: s.total, sources: { ...s.sources }, capped: { ...s.capped }, perHour };
  }
  return { campaign: f.campaign, factions, history: f.history, multipliers: multipliers(g) };
}

// Every front's view, for the galaxy state.
function view(g: Galaxy, now = Date.now()) {
  const out: Record<string, ReturnType<typeof frontView>> = {};
  for (const planet of Object.keys(g.war.campaigns || {})) out[planet] = frontView(g, planet, now);
  return { fronts: out, shares: { ...T.get().ledger.shares }, multipliers: multipliers(g) };
}

function receipts(g: Galaxy, who: string): Receipt[] {
  const l = ensure(g);
  return Object.hasOwn(l.receipts, who) ? l.receipts[who].slice() : [];
}

module.exports = { SOURCES, SOURCE_NAMES, ensure, front, multiplier, multipliers, room, credit, frontView, view, receipts };
