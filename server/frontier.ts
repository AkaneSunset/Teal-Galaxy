// Terraforming and the Frontier: a PC loop of its own, outside the conquest game.
//
// Each faction claims a region of Frontier space past Marrow Reach or The Drift, and its pilots
// lease star clusters (5 to 10 star systems) from that pool. A lease is a one-off purchase and the
// cluster is the pilot's for good, unless their account is deleted, they sell it back to the
// faction, or its colony collapses. With hundreds of billions of systems in the pools, nobody
// competes for one: the cluster numbers just count up.
//
// The loop, for the pilot who leases (the Founder):
//   1. Lease a cluster and a Terraformer (both from the faction).
//   2. Survey a barren planet in the cluster: three scans from around its orbit grade it.
//   3. Fly the Terraformer there, one lane at a time with a cooldown between jumps. Until it is
//      established in orbit, every week costs a renewal fee. Its build is never announced:
//      enemies learn of it from data shards, track it by the traces its jumps leave, and once a
//      pilot of theirs finds it they can intercept it. A lost interception destroys it.
//   4. Established in orbit, it's the system's permanent orbital hub. Three stages (atmosphere,
//      water, biosphere), each with a minimum time and a delivery bar pilots fill, make the world.
//   5. The world is a colony that grows in tiers: population milestones unlock economic and civic
//      buildings; civic ones keep crime, services and power in hand, or the population shrinks.
//      At zero the Founder has a week to resettle it, or the cluster goes to auction and the
//      buildings become ruins.
//   6. What the colony makes is the link to the rest of the game: pilots buy it at the source,
//      the Founder exports it to the galactic market, and Hauler missions carry it to other
//      systems' stations, each one finished boosting the Founder's export profits.
//
// Time runs 336 times faster in the demo war (a week in half an hour), like the campaigns.
// In the galaxy as g.frontier; FR.view() is what each faction may see of it.

const T = require('./tunables.ts');
const W = require('./war');
const H = require('./heist');
const F = require('./factions');

type Faction = string;
type Stage = 'atmosphere' | 'water' | 'biosphere';
const STAGES: Stage[] = ['atmosphere', 'water', 'biosphere'];
const ENGINES: Record<Stage, string> = { atmosphere: 'Atmosphere Processor', water: 'Hydro Seeder', biosphere: 'Biosphere Vault' };

// Where each faction's region opens off the war map.
const EXIT: Record<Faction, string> = { compact: 'marrow', ashen: 'marrow', luminar: 'drift', coma: 'drift' };
const DEPTH = 4; // levels of deep space between a region's gate and its clusters
const WIDTH = 3; // systems on each level
const POOL = 13_000_000_000; // clusters in each faction's region: about 400 billion systems in all

interface Planet { id: string; name: string; kind: string }
interface StarSystem { id: string; name: string; planets: Planet[] }
interface Grades { size: number; core: number; ice: number; atmosphere: number }
interface Colony {
  planet: string;
  pop: number;
  tier: number;
  buildings: Record<string, number>;
  stock: Record<string, number>;
  carry: Record<string, number>;
  boost: number; // export profit boost from Hauler missions
  collapseAt: number | null;
  updatedAt: number;
}
interface Cluster {
  id: string;
  faction: Faction;
  owner: string | null;
  leasedAt: number;
  systems: StarSystem[];
  scans: Record<string, { by: string; points: number[] }>;
  surveys: Record<string, { by: string; grades: Grades; at: number }>;
  colony: Colony | null;
  ruins: { planet: string; buildings: Record<string, number>; at: number }[];
  auction: { price: number; since: number } | null;
}
interface Ship {
  id: number;
  owner: string;
  faction: Faction;
  cluster: string;
  state: 'leased' | 'voyage' | 'orbit' | 'world' | 'destroyed' | 'lapsed';
  leasedAt: number;
  dueAt: number;
  renewals: number;
  target: string | null;
  targetSystem: string | null;
  at: string;
  jumpReadyAt: number;
  engines: Stage[];
  stage: number;
  stageStartedAt: number;
  bars: Record<string, number>;
  contributors: Record<string, number>;
  foundBy: Record<Faction, number>;
  escorts: string[];
  interception: { faction: Faction; at: number } | null;
  establishedAt: number | null;
}
interface Trace { system: string; to: string; faction: Faction; at: number }
interface Mission { id: number; pilot: string; cluster: string; item: string; qty: number; to: string; takenAt: number }
interface Frontier {
  next: Record<Faction, number>;
  clusters: Record<string, Cluster>;
  ships: Record<string, Ship>;
  traces: Trace[];
  missions: Mission[];
  nextId: number;
}
type Result = { ok: true; [k: string]: unknown } | { ok: false; reason: string };

const fail = (reason: string): Result => ({ ok: false, reason });

// --- Time -------------------------------------------------------------------------------------

function hourMs(): number {
  return W.isDemo() ? 3600_000 / 336 : 3600_000;
}

// --- Geography: the regions, and the clusters in them -------------------------------------------

// FNV-1a: the same id always rolls the same.
function hash(s: string): number {
  let h = 0x811c9dc5;
  for (const c of s) h = Math.imul(h ^ c.charCodeAt(0), 0x01000193) >>> 0;
  return h;
}
const roll = (s: string, n: number) => hash(s) % n;

const SYL = ['ka', 'ren', 'vos', 'li', 'tor', 'mae', 'qu', 'zan', 'el', 'dra', 'nis', 'oth', 'sa', 'vel', 'ir', 'kor'];
function nameFor(id: string): string {
  const n = 2 + roll(id + ':n', 2);
  let s = '';
  for (let i = 0; i < n; i++) s += SYL[roll(`${id}:${i}`, SYL.length)];
  return s[0].toUpperCase() + s.slice(1);
}

const gateOf = (faction: Faction) => `fr-${faction}-gate`;
const deepOf = (faction: Faction, level: number, i: number) => `fr-${faction}-d${level}-${i}`;

// The deep-space systems of a faction's region: its gate off the war map, then DEPTH levels of
// WIDTH systems, each linked to its neighbours on the next level, so a voyage has routes to pick.
function regionLinks(faction: Faction): Record<string, string[]> {
  const links: Record<string, string[]> = {};
  const link = (a: string, b: string) => {
    (links[a] ||= []).push(b);
    (links[b] ||= []).push(a);
  };
  link(EXIT[faction], gateOf(faction));
  for (let i = 0; i < WIDTH; i++) link(gateOf(faction), deepOf(faction, 1, i));
  for (let l = 1; l < DEPTH; l++)
    for (let i = 0; i < WIDTH; i++)
      for (let j = Math.max(0, i - 1); j <= Math.min(WIDTH - 1, i + 1); j++) link(deepOf(faction, l, i), deepOf(faction, l + 1, j));
  return links;
}

// A cluster's systems, rolled from its id: 5 to 10 of them, each with 1 to 3 barren planets.
function systemsOf(clusterId: string): StarSystem[] {
  const n = 5 + roll(clusterId, 6);
  const kinds = ['bare rock', 'ice ball', 'moon of a gas giant'];
  return Array.from({ length: n }, (_, k) => {
    const id = `fr-${clusterId}-s${k + 1}`;
    const planets = Array.from({ length: 1 + roll(id + ':p', 3) }, (_, j) => {
      const pid = `${id}-p${j + 1}`;
      return { id: pid, name: `${nameFor(id)} ${['I', 'II', 'III'][j]}`, kind: kinds[roll(pid, 3)] };
    });
    return { id, name: nameFor(id), planets };
  });
}

// What a survey finds: 1 to 5 for each grade, hidden until the planet is surveyed.
function gradesOf(planetId: string): Grades {
  const g = (k: string) => 1 + roll(`${planetId}:${k}`, 5);
  return { size: g('size'), core: g('core'), ice: g('ice'), atmosphere: g('atmosphere') };
}

function clusterOfSystem(fr: Frontier, systemId: string): Cluster | null {
  const m = /^fr-(.+)-s\d+$/.exec(systemId);
  return (m && fr.clusters[m[1]]) || null;
}

// The deep-space system a leased cluster's first system hangs off.
function anchorOf(c: Cluster): string {
  return deepOf(c.faction, DEPTH, roll(c.id, WIDTH));
}

// The systems one jump from `id`: war-map lanes, the region links, and a leased cluster's chain
// (its first system off the deepest level, the rest one after another).
function neighbours(g: any, id: string): string[] {
  const fr = frontier(g);
  const out = new Set<string>(W.system(g, id)?.lanes || []);
  for (const faction of Object.keys(EXIT)) for (const n of regionLinks(faction)[id] || []) out.add(n);
  for (const c of Object.values(fr.clusters)) {
    const ids = c.systems.map((s) => s.id);
    const anchor = anchorOf(c);
    if (id === anchor) out.add(ids[0]);
    const k = ids.indexOf(id);
    if (k === 0) out.add(anchor);
    if (k > 0) out.add(ids[k - 1]);
    if (k >= 0 && k < ids.length - 1) out.add(ids[k + 1]);
  }
  return [...out];
}

// How many jumps apart two systems are, war map and Frontier together, or null.
function lanes(g: any, from: string, to: string): number | null {
  const seen = new Map([[from, 0]]);
  const queue = [from];
  while (queue.length) {
    const id = queue.shift()!;
    if (id === to) return seen.get(id)!;
    if (seen.get(id)! > 40) continue;
    for (const n of neighbours(g, id)) {
      if (seen.has(n)) continue;
      seen.set(n, seen.get(id)! + 1);
      queue.push(n);
    }
  }
  return null;
}

function isFrontierSystem(g: any, id: string): boolean {
  return id.startsWith('fr-') && neighbours(g, id).length > 0;
}

// --- State ------------------------------------------------------------------------------------

function frontier(g: any): Frontier {
  g.frontier ||= {};
  const fr = g.frontier;
  fr.next ||= {};
  fr.clusters ||= {};
  fr.ships ||= {};
  fr.traces ||= [];
  fr.missions ||= [];
  fr.nextId ||= 1;
  return fr;
}

function pilotOf(g: any, name: string) {
  return Object.hasOwn(g.pilots || {}, name) ? g.pilots[name] : null;
}

function note(g: any, name: string, text: string, now: number) {
  const p = pilotOf(g, name);
  if (p) F.alert(p, text, now);
}

function shipOf(fr: Frontier, id: unknown): Ship | null {
  return Object.hasOwn(fr.ships, String(id)) ? fr.ships[String(id)] : null;
}

function clusterOf(fr: Frontier, id: unknown): Cluster | null {
  return Object.hasOwn(fr.clusters, String(id)) ? fr.clusters[String(id)] : null;
}

function planetIn(c: Cluster, planetId: string): { system: StarSystem; planet: Planet } | null {
  for (const system of c.systems) for (const planet of system.planets) if (planet.id === planetId) return { system, planet };
  return null;
}

// The faction's shipyard: its capital system on the war map.
function shipyard(g: any, faction: Faction): string {
  return g.war.systems.find((s: any) => s.capitalOf === faction)?.id || W.HOME_SYSTEM;
}

function take(p: any, item: string, qty: number): boolean {
  const have = (p.cargo?.[item] || 0) + (p.hold?.[item] || 0);
  if (have < qty) return false;
  const fromCargo = Math.min(qty, p.cargo?.[item] || 0);
  if (fromCargo) p.cargo[item] -= fromCargo;
  if (qty > fromCargo) p.hold[item] -= qty - fromCargo;
  return true;
}

const value = (item: string): number => (item === 'ice' ? 3 : item === 'metal' ? 2 : H.ITEMS[item]?.value || 0);

// --- Leases -----------------------------------------------------------------------------------

// A pilot leases the next star cluster from their faction's pool: a one-off purchase, theirs for good.
function leaseCluster(g: any, name: string, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  if (!p?.faction) return fail('choose a faction first');
  if (!EXIT[p.faction]) return fail('your faction claims no Frontier space');
  const price = T.get().frontier.clusterLease;
  if (p.credits < price) return fail(`a star cluster costs ${price} credits`);
  const n = (fr.next[p.faction] || 0) + 1;
  if (n > POOL) return fail("your faction's Frontier is fully leased");
  fr.next[p.faction] = n;
  const id = `${p.faction}-${n}`;
  p.credits -= price;
  fr.clusters[id] = { id, faction: p.faction, owner: name, leasedAt: now, systems: systemsOf(id), scans: {}, surveys: {}, colony: null, ruins: [], auction: null };
  return { ok: true, cluster: id };
}

// Sells a cluster back to the faction: nothing paid back, and it's free to lease again by number.
function sellBack(g: any, name: string, clusterId: string): Result {
  const fr = frontier(g);
  const c = clusterOf(fr, clusterId);
  if (!c || c.owner !== name) return fail('that is not your cluster');
  if (Object.values(fr.ships).some((s) => s.cluster === c.id && ['leased', 'voyage', 'orbit'].includes(s.state))) return fail('a Terraformer is still working there');
  delete fr.clusters[c.id];
  return { ok: true };
}

// The Terraformer for one of the pilot's clusters. The first engine, the Atmosphere Processor,
// comes on board; the Founder has startWindowHours to get it established in orbit.
function leaseShip(g: any, name: string, clusterId: string, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c || c.owner !== name) return fail('lease a star cluster first');
  if (c.colony) return fail('that cluster already has a world');
  if (Object.values(fr.ships).some((s) => s.owner === name && ['leased', 'voyage'].includes(s.state))) return fail('you already have a Terraformer on its way');
  const t = T.get().frontier;
  if (p.credits < t.shipLease) return fail(`a Terraformer costs ${t.shipLease} credits`);
  p.credits -= t.shipLease;
  const id = fr.nextId++;
  fr.ships[id] = {
    id, owner: name, faction: c.faction, cluster: c.id, state: 'leased', leasedAt: now, dueAt: now + t.startWindowHours * hourMs(), renewals: 0,
    target: null, targetSystem: null, at: shipyard(g, c.faction), jumpReadyAt: now, engines: ['atmosphere'], stage: 0, stageStartedAt: 0,
    bars: {}, contributors: {}, foundBy: {}, escorts: [], interception: null, establishedAt: null,
  };
  return { ok: true, ship: id };
}

// --- Surveys ----------------------------------------------------------------------------------

// One of the three scans from around a planet's orbit (point 0, 1 or 2). The Founder or any pilot
// of their faction (hired through the job board) can do it; the pilot who completes the third is
// the world's Pathfinder.
function survey(g: any, name: string, clusterId: string, planetId: string, point: number, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c) return fail('no such cluster');
  if (p.faction !== c.faction) return fail("only your own faction's pilots survey here");
  if (!planetIn(c, planetId)) return fail('no such planet in that cluster');
  if (c.surveys[planetId]) return fail('already surveyed');
  if (![0, 1, 2].includes(point)) return fail('scan from point 1, 2 or 3 around the orbit');
  const s = (c.scans[planetId] ||= { by: name, points: [] });
  if (!s.points.includes(point)) s.points.push(point);
  if (s.points.length < 3) return { ok: true, points: s.points.length };
  c.surveys[planetId] = { by: name, grades: gradesOf(planetId), at: now };
  delete c.scans[planetId];
  if (c.owner && c.owner !== name) note(g, c.owner, `${name} surveyed ${planetIn(c, planetId)!.planet.name}`, now);
  return { ok: true, grades: c.surveys[planetId].grades };
}

// --- The voyage -------------------------------------------------------------------------------

function setTarget(g: any, name: string, shipId: number, planetId: string): Result {
  const fr = frontier(g);
  const s = shipOf(fr, shipId);
  if (!s || s.owner !== name) return fail('that is not your Terraformer');
  if (s.state !== 'leased' && s.state !== 'voyage') return fail('it has already set to work');
  const c = fr.clusters[s.cluster];
  const found = c && planetIn(c, planetId);
  if (!found) return fail('pick a planet in your cluster');
  if (!c.surveys[planetId]) return fail('survey it first');
  s.target = planetId;
  s.targetSystem = found.system.id;
  return { ok: true };
}

// One lane at a time, jumpCooldownHours apart. Each jump leaves a trace in the system it left,
// which shows the lane it took to whoever scans it before it fades.
function jump(g: any, name: string, shipId: number, to: string, now: number): Result {
  const fr = frontier(g);
  const s = shipOf(fr, shipId);
  if (!s || s.owner !== name) return fail('that is not your Terraformer');
  if (s.state !== 'leased' && s.state !== 'voyage') return fail('it is not travelling');
  if (!s.target) return fail('choose its target world first');
  if (s.interception) return fail('it is under attack');
  if (now < s.jumpReadyAt) return fail('the jump drive is still cooling down');
  if (!neighbours(g, s.at).includes(to)) return fail('it jumps one lane at a time');
  fr.traces.push({ system: s.at, to, faction: s.faction, at: now });
  s.at = to;
  s.state = 'voyage';
  s.jumpReadyAt = now + T.get().frontier.jumpCooldownHours * hourMs();
  s.escorts = [];
  return { ok: true, at: to, arrived: to === s.targetSystem };
}

// The start point: in orbit around its target, it becomes the system's permanent orbital hub,
// the renewal fees stop, and the first stage begins.
function establish(g: any, name: string, shipId: number, now: number): Result {
  const fr = frontier(g);
  const s = shipOf(fr, shipId);
  if (!s || s.owner !== name) return fail('that is not your Terraformer');
  if (s.state !== 'voyage' || s.at !== s.targetSystem) return fail('fly it to its target world first');
  if (s.interception) return fail('it is under attack');
  s.state = 'orbit';
  s.establishedAt = now;
  s.stageStartedAt = now;
  s.stage = 0;
  s.bars = {};
  return { ok: true };
}

// Pilots of the faction flying alongside it; each adds to its defence in an interception.
function escort(g: any, name: string, shipId: number, on: boolean): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const s = shipOf(fr, shipId);
  if (!p || !s || p.faction !== s.faction) return fail("escort your own faction's Terraformers");
  s.escorts = s.escorts.filter((n) => n !== name);
  if (on) s.escorts.push(name);
  return { ok: true, escorts: s.escorts.length };
}

// --- Hunting a Terraformer ----------------------------------------------------------------------

// A data shard or security dossier from the pilot's raid stash, decoded: which Terraformers a
// faction has leased, whose, for which cluster, and whether they have set off. Never where they are.
function decode(g: any, name: string, faction: Faction): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  if (!p?.faction) return fail('choose a faction first');
  if (faction === p.faction) return fail("decode intel on another faction's Terraformers");
  const k = (p.stash || []).findIndex((x: any) => x.item === 'shard' || x.item === 'dossier');
  if (k < 0) return fail('you need a Data shard or Security dossier from a raid');
  const it = p.stash[k];
  if ((it.qty || 1) > 1) it.qty -= 1;
  else p.stash.splice(k, 1);
  const leads = Object.values(fr.ships)
    .filter((s) => s.faction === faction && ['leased', 'voyage'].includes(s.state))
    .map((s) => ({ ship: s.id, owner: s.owner, cluster: s.cluster, underway: s.state === 'voyage' }));
  return { ok: true, leads };
}

// A pilot scans the system they're in: the traces of enemy jumps that haven't faded (and the
// lane each took), and any enemy Terraformer there, which their faction has now found.
function scan(g: any, name: string, system: string, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  if (!p?.faction) return fail('choose a faction first');
  const fade = T.get().frontier.traceHours * hourMs();
  const traces = fr.traces.filter((t) => t.system === system && t.faction !== p.faction && now - t.at < fade).map((t) => ({ to: t.to, age: now - t.at }));
  const found = [];
  for (const s of Object.values(fr.ships)) {
    if (s.faction === p.faction || s.at !== system || !['leased', 'voyage'].includes(s.state)) continue;
    s.foundBy[p.faction] = now;
    found.push(s.id);
  }
  return { ok: true, traces, found };
}

// Pilots of a faction that has found a travelling Terraformer, in its system, start an
// interception (the Intercept match decides it: interceptResult).
function intercept(g: any, name: string, shipId: number, system: string, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const s = shipOf(fr, shipId);
  if (!p?.faction || !s || s.faction === p.faction) return fail('no such enemy Terraformer');
  if (!['leased', 'voyage'].includes(s.state) || s.at !== system) return fail("it isn't here");
  const seen = s.foundBy[p.faction];
  if (!seen || now - seen > T.get().frontier.traceHours * hourMs()) return fail('find it first: scan the system');
  if (s.interception) return fail('it is already under attack');
  s.interception = { faction: p.faction, at: now };
  note(g, s.owner, `Your Terraformer is being intercepted by ${F.the(p.faction)}`, now);
  return { ok: true };
}

// The interception's result. A win for the attackers destroys the Terraformer and everything the
// Founder put into it; a loss sends them off and it has to be found again.
function interceptResult(g: any, shipId: number, attackersWon: boolean, now: number): Result {
  const fr = frontier(g);
  const s = shipOf(fr, shipId);
  if (!s?.interception) return fail('no interception');
  const by = s.interception.faction;
  s.interception = null;
  delete s.foundBy[by];
  if (attackersWon) {
    s.state = 'destroyed';
    note(g, s.owner, 'Your Terraformer was destroyed', now);
  } else note(g, s.owner, 'Your Terraformer fought off the interception', now);
  return { ok: true, destroyed: attackersWon };
}

// --- The three stages -------------------------------------------------------------------------

function stageOf(s: Ship): Stage | null {
  return s.state === 'orbit' ? STAGES[s.stage] : null;
}

// What a stage's bar still needs, scaled by the planet's survey grades: a good ice grade needs
// less ice, a good atmosphere less for the processor, a big world more biosphere.
function needs(g: any, s: Ship): Record<string, number> {
  const stage = stageOf(s);
  if (!stage) return {};
  const grades = frontier(g).clusters[s.cluster]?.surveys[s.target!]?.grades;
  const scale = !grades ? 1 : stage === 'atmosphere' ? 1.3 - grades.atmosphere * 0.1 : stage === 'water' ? 1.3 - grades.ice * 0.1 : 0.8 + grades.size * 0.1;
  const bar = T.get().frontier.bars[stage] as Record<string, number>;
  return Object.fromEntries(Object.entries(bar).map(([k, n]) => [k, Math.max(0, Math.ceil(n * scale) - (s.bars[k] || 0))]));
}

// The Founder buys a stage's engine at the faction shipyard; it goes into their cargo, and
// delivering it to the Terraformer fits it.
function buyEngine(g: any, name: string, shipId: number, stage: Stage): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const s = shipOf(fr, shipId);
  if (!p || !s || s.owner !== name) return fail('that is not your Terraformer');
  if (!ENGINES[stage]) return fail('no such engine');
  if (s.engines.includes(stage)) return fail('it already has that engine');
  const price = T.get().frontier.enginePrice;
  if (p.credits < price) return fail(`an engine costs ${price} credits`);
  p.credits -= price;
  p.cargo[`engine_${stage}`] = (p.cargo[`engine_${stage}`] || 0) + 1;
  return { ok: true };
}

// A pilot delivers to the Terraformer: an engine, or goods for the stage's bar. The Founder pays
// other pilots deliveryPay of each unit's value.
function deliver(g: any, name: string, shipId: number, item: string, qty: number, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const s = shipOf(fr, shipId);
  if (!p || !s || p.faction !== s.faction) return fail("deliver to your own faction's Terraformers");
  if (s.state !== 'orbit') return fail('it has to be established in orbit first');
  const engine = /^engine_(.+)$/.exec(item)?.[1] as Stage | undefined;
  if (engine) {
    if (!ENGINES[engine] || s.engines.includes(engine)) return fail('it has that engine');
    if (!take(p, item, 1)) return fail('you have no such engine aboard');
    s.engines.push(engine);
    return { ok: true, fitted: engine };
  }
  const stage = stageOf(s)!;
  if (!s.engines.includes(stage)) return fail(`fit the ${ENGINES[stage]} first`);
  if (!Number.isInteger(qty) || qty < 1) return fail('bad amount');
  const want = needs(g, s)[item] || 0;
  if (!want) return fail(`the ${stage} stage doesn't need that`);
  const n = Math.min(qty, want);
  const founder = pilotOf(g, s.owner);
  const pay = name === s.owner ? 0 : Math.round(n * value(item) * T.get().frontier.deliveryPay);
  if (pay && (!founder || founder.credits < pay)) return fail("the Founder can't pay for that delivery");
  if (!take(p, item, n)) return fail('not enough of it aboard');
  if (pay) {
    founder.credits -= pay;
    p.credits += pay;
  }
  s.bars[item] = (s.bars[item] || 0) + n;
  s.contributors[name] = (s.contributors[name] || 0) + n;
  advance(g, s, now);
  return { ok: true, delivered: n, paid: pay };
}

// An enemy attack on the engine that won (a Supremacy or Sector Defense match): the stage loses a
// quarter of what's been delivered.
function stageSetback(g: any, shipId: number): Result {
  const s = shipOf(frontier(g), shipId);
  if (!s || s.state !== 'orbit') return fail('no stage under way');
  for (const k of Object.keys(s.bars)) s.bars[k] = Math.floor(s.bars[k] * 0.75);
  return { ok: true };
}

// A stage ends when its bar is full and its minimum time has passed; the third makes the world.
function advance(g: any, s: Ship, now: number) {
  const stage = stageOf(s);
  if (!stage) return;
  if (Object.values(needs(g, s)).some((n) => n > 0)) return;
  if (now < s.stageStartedAt + T.get().frontier.stageHours[stage] * hourMs()) return;
  s.stage += 1;
  s.bars = {};
  s.stageStartedAt = now;
  if (s.stage < STAGES.length) {
    note(g, s.owner, `The ${stage} stage is done: the ${STAGES[s.stage]} stage begins`, now);
    return;
  }
  s.state = 'world';
  const c = frontier(g).clusters[s.cluster];
  const t = T.get().frontier.colony;
  c.colony = { planet: s.target!, pop: t.startPop, tier: 0, buildings: { habitat: 1, precinct: 1, clinic: 1, power: 1 }, stock: {}, carry: {}, boost: 0, collapseAt: null, updatedAt: now };
  note(g, s.owner, `${planetIn(c, s.target!)!.planet.name} is a living world`, now);
}

// --- The colony -------------------------------------------------------------------------------

// Buildings: civic ones cover a need for so many people; economic ones make products (an hour,
// at full power); habitats house people. `tier`: the population tier that unlocks it.
const BUILDINGS: Record<string, { name: string; tier: number; cost: number; covers?: string; per?: number; houses?: number; makes?: string; rate?: number }> = {
  habitat: { name: 'Habitat block', tier: 0, cost: 20_000, houses: 2500 },
  precinct: { name: 'Precinct', tier: 0, cost: 15_000, covers: 'crime', per: 2000 },
  clinic: { name: 'Clinic', tier: 0, cost: 15_000, covers: 'services', per: 2000 },
  power: { name: 'Power plant', tier: 0, cost: 25_000, covers: 'power', per: 3000 },
  mine: { name: 'Mine', tier: 0, cost: 20_000, makes: 'copper', rate: 12 },
  foundry: { name: 'Foundry', tier: 1, cost: 40_000, makes: 'alloy', rate: 3 },
  smelter: { name: 'Titanium smelter', tier: 2, cost: 80_000, makes: 'ti_alloy', rate: 1.5 },
  works: { name: 'Electronics works', tier: 2, cost: 90_000, makes: 'circuit', rate: 2 },
  reactor: { name: 'Isotope reactor', tier: 3, cost: 200_000, makes: 'isotope', rate: 1 },
};
const NEEDS = ['crime', 'services', 'power'];

function tierOf(pop: number): number {
  const ms = T.get().frontier.colony.milestones;
  const m = [ms.tier1, ms.tier2, ms.tier3];
  let t = 0;
  for (let i = 0; i < m.length; i++) if (pop >= m[i]) t = i + 1;
  return t;
}

// How well the colony's needs are met: the worst of crime, services and power, 1 = all covered.
function coverage(c: Colony): Record<string, number> {
  const out: Record<string, number> = {};
  for (const need of NEEDS) {
    const cover = Object.entries(BUILDINGS).filter(([, b]) => b.covers === need).reduce((a, [k, b]) => a + (c.buildings[k] || 0) * b.per!, 0);
    out[need] = c.pop > 0 ? Math.min(1, cover / c.pop) : 1;
  }
  return out;
}

function housing(c: Colony): number {
  return Object.entries(BUILDINGS).reduce((a, [k, b]) => a + (c.buildings[k] || 0) * (b.houses || 0), 0);
}

function buildIn(g: any, name: string, clusterId: string, type: string): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c || c.owner !== name || !c.colony) return fail('build in your own colony');
  const b = BUILDINGS[type];
  if (!b || !Object.hasOwn(BUILDINGS, type)) return fail('no such building');
  if (c.colony.collapseAt) return fail('resettle the colony first');
  if (c.colony.tier < b.tier) return fail(`the ${b.name} unlocks at population tier ${b.tier}`);
  if (p.credits < b.cost) return fail(`a ${b.name} costs ${b.cost} credits`);
  p.credits -= b.cost;
  c.colony.buildings[type] = (c.colony.buildings[type] || 0) + 1;
  return { ok: true };
}

// A collapsed colony, re-established inside its week.
function resettle(g: any, name: string, clusterId: string, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c || c.owner !== name || !c.colony?.collapseAt) return fail('nothing to resettle');
  const t = T.get().frontier.colony;
  if (p.credits < t.resettleCost) return fail(`resettling costs ${t.resettleCost} credits`);
  p.credits -= t.resettleCost;
  c.colony.pop = t.resettlePop;
  c.colony.collapseAt = null;
  c.colony.updatedAt = now;
  return { ok: true };
}

// Hours of colony life: growth when every need is covered (up to its housing), decline when one
// isn't, production by the power there is, and collapse at zero.
function colonyTick(g: any, c: Cluster, now: number) {
  const col = c.colony!;
  const t = T.get().frontier.colony;
  const h = Math.max(0, now - col.updatedAt) / hourMs();
  if (h <= 0) return;
  col.updatedAt = now;
  if (col.collapseAt !== null) {
    if (now >= col.collapseAt) toAuction(g, c, now);
    return;
  }
  const cov = coverage(col);
  const worst = Math.min(...NEEDS.map((n) => cov[n]));
  if (worst >= 1) col.pop = Math.min(Math.max(col.pop, housing(col)), col.pop * Math.pow(1 + t.growth, h));
  else col.pop -= Math.max(10, col.pop * t.decline) * (1 - worst) * h;
  col.pop = Math.max(0, Math.round(col.pop));
  const tier = tierOf(col.pop);
  if (tier > col.tier) note(g, c.owner!, `Your colony reached population tier ${tier}`, now);
  col.tier = Math.max(col.tier, tier);
  for (const [k, b] of Object.entries(BUILDINGS)) {
    if (!b.makes || !col.buildings[k]) continue;
    col.carry[b.makes] = (col.carry[b.makes] || 0) + col.buildings[k] * b.rate! * cov.power * h;
    const whole = Math.floor(col.carry[b.makes]);
    col.carry[b.makes] -= whole;
    col.stock[b.makes] = (col.stock[b.makes] || 0) + whole;
  }
  if (col.pop === 0) {
    col.collapseAt = now + t.collapseHours * hourMs();
    note(g, c.owner!, 'Your colony has collapsed: resettle it within a week or the cluster goes to auction', now);
  }
}

// The cluster goes to auction: the Founder's progress is gone, the buildings are ruins.
function toAuction(g: any, c: Cluster, now: number) {
  if (c.colony) c.ruins.push({ planet: c.colony.planet, buildings: c.colony.buildings, at: now });
  if (c.owner) note(g, c.owner, 'Your star cluster went to auction', now);
  c.owner = null;
  c.colony = null;
  c.surveys = {};
  c.scans = {};
  c.auction = { price: T.get().frontier.auctionPrice, since: now };
}

function buyAtAuction(g: any, name: string, clusterId: string, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c?.auction) return fail('that cluster is not for sale');
  if (p.faction !== c.faction) return fail("only the faction's own pilots lease its clusters");
  if (p.credits < c.auction.price) return fail(`it costs ${c.auction.price} credits`);
  p.credits -= c.auction.price;
  c.owner = name;
  c.leasedAt = now;
  c.auction = null;
  return { ok: true };
}

// --- Exports ----------------------------------------------------------------------------------

// A pilot at the colony buys its products at their value; the credits go to the Founder.
function buy(g: any, name: string, clusterId: string, item: string, qty: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c?.colony) return fail('no colony there');
  if (!Number.isInteger(qty) || qty < 1) return fail('bad amount');
  if ((c.colony.stock[item] || 0) < qty) return fail('not that many for sale');
  const cost = qty * value(item);
  if (name !== c.owner && p.credits < cost) return fail('not enough credits');
  c.colony.stock[item] -= qty;
  if (name !== c.owner) {
    p.credits -= cost;
    pilotOf(g, c.owner!).credits += cost;
  }
  p.cargo[item] = (p.cargo[item] || 0) + qty;
  return { ok: true, cost: name === c.owner ? 0 : cost };
}

// The Founder sells to the galactic market at its rate, boosted by finished Hauler missions.
function exportGoods(g: any, name: string, clusterId: string, item: string, qty: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c?.colony || c.owner !== name) return fail('export from your own colony');
  if (!Number.isInteger(qty) || qty < 1) return fail('bad amount');
  if ((c.colony.stock[item] || 0) < qty) return fail('not that many in stock');
  const ex = T.get().frontier.exports;
  const paid = Math.round(qty * value(item) * ex.marketRate * (1 + c.colony.boost));
  c.colony.stock[item] -= qty;
  p.credits += paid;
  return { ok: true, paid };
}

// A Hauler mission: goods from the colony to another system's station, to sell there.
function takeHaul(g: any, name: string, clusterId: string, item: string, qty: number, to: string, now: number): Result {
  const fr = frontier(g);
  const p = pilotOf(g, name);
  const c = clusterOf(fr, clusterId);
  if (!p || !c?.colony) return fail('no colony there');
  if (!Number.isInteger(qty) || qty < 1) return fail('bad amount');
  if ((c.colony.stock[item] || 0) < qty) return fail('not that many in stock');
  const wp = W.planet(g, to);
  if (!wp || wp.capital) return fail('haul it to a contested world\'s orbital station');
  if (fr.missions.filter((m) => m.pilot === name).length >= 3) return fail('finish a Hauler mission first');
  c.colony.stock[item] -= qty;
  const m = { id: fr.nextId++, pilot: name, cluster: c.id, item, qty, to, takenAt: now };
  fr.missions.push(m);
  return { ok: true, mission: m.id };
}

// Delivered at the station: the goods sell at their full value there; the pilot keeps haulShare
// and the Founder the rest, and the colony's export boost grows.
function deliverHaul(g: any, name: string, missionId: number, station: string | null): Result {
  const fr = frontier(g);
  const m = fr.missions.find((x) => x.id === missionId && x.pilot === name);
  if (!m) return fail('no such mission');
  if (station !== m.to) return fail(`deliver it at ${W.planet(g, m.to)?.name || m.to}'s orbital station`);
  const ex = T.get().frontier.exports;
  const sale = m.qty * value(m.item) * ex.haulRate;
  const share = Math.round(sale * ex.haulShare);
  pilotOf(g, name).credits += share;
  const c = fr.clusters[m.cluster];
  if (c?.owner) {
    pilotOf(g, c.owner).credits += Math.round(sale) - share;
    if (c.colony) c.colony.boost = Math.min(ex.boostMax, c.colony.boost + ex.boostPerMission);
  }
  fr.missions = fr.missions.filter((x) => x !== m);
  return { ok: true, paid: share };
}

// --- The clock --------------------------------------------------------------------------------

// Renewal fees for Terraformers not yet established, stages that can end, colonies, and traces
// that have faded. Returns whether anything changed.
function tick(g: any, now: number): boolean {
  const fr = frontier(g);
  const t = T.get().frontier;
  let changed = false;
  for (const s of Object.values(fr.ships)) {
    if (s.state === 'leased' || s.state === 'voyage') {
      while (now >= s.dueAt && (s.state === 'leased' || s.state === 'voyage')) {
        const p = pilotOf(g, s.owner);
        if (p && p.credits >= t.renewalFee) {
          p.credits -= t.renewalFee;
          s.renewals += 1;
          s.dueAt += t.startWindowHours * hourMs();
          note(g, s.owner, `Your Terraformer isn't established yet: ${t.renewalFee} credits renewal fee paid`, now);
        } else {
          s.state = 'lapsed';
          note(g, s.owner, "You couldn't pay the renewal fee: the Terraformer lease lapsed", now);
        }
        changed = true;
      }
    }
    if (s.state === 'orbit') {
      const before = s.stage;
      advance(g, s, now);
      changed ||= s.stage !== before;
    }
  }
  for (const c of Object.values(fr.clusters)) {
    if (!c.colony) continue;
    const pop = c.colony.pop;
    colonyTick(g, c, now);
    changed ||= !c.colony || c.colony.pop !== pop;
  }
  const fade = t.traceHours * hourMs();
  const kept = fr.traces.filter((x) => now - x.at < fade);
  if (kept.length !== fr.traces.length) fr.traces = kept;
  return changed;
}

// --- Views ------------------------------------------------------------------------------------

// What a faction may see: every cluster's owner, systems and colony (the surveys only of its own),
// its own Terraformers in full, and only the enemy ones it has found, while they're found. Traces
// and Hauler missions are secret (a scan or the mission list shows them).
function view(g: any, faction: Faction | null, now: number) {
  const fr = frontier(g);
  const fade = T.get().frontier.traceHours * hourMs();
  const clusters = Object.fromEntries(
    Object.values(fr.clusters).map((c) => [c.id, { ...c, anchor: anchorOf(c), scans: c.faction === faction ? c.scans : {}, surveys: c.faction === faction ? c.surveys : {} }]),
  );
  // Its own faction's Terraformers come with what their stage still needs and where they can jump.
  const ships = Object.fromEntries(
    Object.values(fr.ships)
      .filter((s) => s.faction === faction || (faction && s.foundBy[faction] && now - s.foundBy[faction] < fade && ['leased', 'voyage'].includes(s.state)))
      .map((s) => [s.id, s.faction === faction ? { ...s, needs: needs(g, s), next: neighbours(g, s.at) } : { id: s.id, faction: s.faction, owner: s.owner, at: s.at, state: s.state, escorts: s.escorts.length, interception: s.interception }]),
  );
  const pilots = new Set(Object.entries(g.pilots || {}).filter(([, p]: [string, any]) => p.faction === faction).map(([n]) => n));
  return { clusters, ships, missions: fr.missions.filter((m) => pilots.has(m.pilot)), regions: regionsView() };
}

function adminView(g: any) {
  const fr = frontier(g);
  return { ...fr, clusters: Object.fromEntries(Object.values(fr.clusters).map((c) => [c.id, { ...c, anchor: anchorOf(c) }])), regions: regionsView() };
}

function regionsView() {
  return Object.fromEntries(
    Object.keys(EXIT).map((f) => {
      const links = regionLinks(f);
      const names = Object.fromEntries(Object.keys(links).filter((id) => id.startsWith('fr-')).map((id) => [id, id === gateOf(f) ? `${nameFor(id)} Gate` : nameFor(id)]));
      return [f, { exit: EXIT[f], gate: gateOf(f), links, names }];
    }),
  );
}

// For the apps: what each building and engine is.
const CATALOG = { buildings: BUILDINGS, engines: ENGINES, stages: STAGES };

module.exports = {
  STAGES, ENGINES, BUILDINGS, CATALOG, POOL, EXIT,
  frontier, systemsOf, gradesOf, neighbours, lanes, isFrontierSystem, clusterOfSystem, shipyard, needs, coverage, tierOf,
  leaseCluster, sellBack, leaseShip, survey, setTarget, jump, establish, escort, decode, scan, intercept, interceptResult,
  buyEngine, deliver, stageSetback, buildIn, resettle, buyAtAuction, buy, exportGoods, takeHaul, deliverHaul, tick, view, adminView, hourMs,
};
