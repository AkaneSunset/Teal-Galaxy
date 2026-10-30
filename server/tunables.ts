// Tunables: the war's rule numbers in one data file, tunables.json (or TUNABLES_FILE), checked
// against SCHEMA when the server starts and again whenever the file changes while it runs. A file
// that fails the check is refused and the numbers in use stay; the telemetry alerts say why.
//
// get() is the numbers in use, always the same object: a reload writes the new values into it, so
// a module may keep a section of it (get().ledger) and still see every change. Modules that mirror
// numbers into constants of their own (campaign.js MODES) do it in an onReload() listener.

const fs: typeof import('node:fs') = require('node:fs');
const path: typeof import('node:path') = require('node:path');

const FILE = path.join(__dirname, 'tunables.json');

interface NumberSpec {
  type: 'number';
  min: number;
  max: number;
  int?: boolean;
}
interface BooleanSpec {
  type: 'boolean';
}
type Spec = NumberSpec | BooleanSpec | { [key: string]: Spec };

const num = (min: number, max: number): NumberSpec => ({ type: 'number', min, max });
const int = (min: number, max: number): NumberSpec => ({ type: 'number', min, max, int: true });
const bool = (): BooleanSpec => ({ type: 'boolean' });
const points = () => ({ points: num(0, 1000) });

// Every number the file must have, and what it may be.
const SCHEMA: Spec = {
  campaign: {
    aiShare: num(0, 1), // a win against AI only scores this much
    finalMultiplier: num(1, 10), // wins in the final push score this many times over
    modes: { sector: points(), supremacy: points(), space: points(), facility: points(), defense: points() },
  },
  orders: {
    reward: { order: int(0, 100_000), member: int(0, 100_000), operation: int(0, 100_000) }, // credits
  },
  ledger: {
    shares: { arena: num(0, 1), frontier: num(0, 1) }, // the most of a front's war supply each source may be
    underdog: { min: num(0, 1), max: num(1, 3), slope: num(0, 5) }, // the war-supply multiplier's range, and how fast it moves
    perMerit: num(0, 10), // war supply for each War Merit of goods a Builder donates
    match: { win: num(0, 1000), loss: num(0, 1000), aiShare: num(0, 1) }, // war supply to each pilot in a match
    receiptsKept: int(1, 1000),
    historyKept: int(0, 100), // past campaigns' totals kept per front
  },
  accounts: {
    charactersMax: int(1, 100),
    nameMax: int(3, 64),
    passwordMin: int(1, 64),
    attemptsPerMinute: int(1, 100), // sign-in attempts per connection, wrong passwords included
  },
  sideLock: {
    on: bool(), // one side per front per account, until the campaign there ends
  },
  telemetry: {
    windowMs: int(1000, 3_600_000), // tick timings are summed up this often
    tickBudgetMs: num(1, 1000), // a loop whose p99 tick takes longer raises an alert
    alertsKept: int(1, 10_000),
    eventsKept: int(1, 100_000),
  },
  sector: {
    pilots: int(1, 256),
    aiUnits: int(0, 10_000),
    fallbackUnits: int(0, 10_000), // the unit budget if aiUnits can't keep to p99BudgetMs
    tickMs: int(10, 1000),
    p99BudgetMs: num(1, 1000),
  },
};

// What a file that passes the check holds.
interface Tunables {
  campaign: { aiShare: number; finalMultiplier: number; modes: Record<string, { points: number }> };
  orders: { reward: { order: number; member: number; operation: number } };
  ledger: {
    shares: { arena: number; frontier: number };
    underdog: { min: number; max: number; slope: number };
    perMerit: number;
    match: { win: number; loss: number; aiShare: number };
    receiptsKept: number;
    historyKept: number;
  };
  accounts: { charactersMax: number; nameMax: number; passwordMin: number; attemptsPerMinute: number };
  sideLock: { on: boolean };
  telemetry: { windowMs: number; tickBudgetMs: number; alertsKept: number; eventsKept: number };
  sector: { pilots: number; aiUnits: number; fallbackUnits: number; tickMs: number; p99BudgetMs: number };
}

type Listener = (t: Tunables) => void;

const isObject = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);
const isLeaf = (s: Spec): s is NumberSpec | BooleanSpec => typeof (s as NumberSpec).type === 'string';

// What's wrong with `raw` as tunables (an empty list: nothing). Every key must be there, with
// nothing extra, so a typo can't quietly leave a number at its old value.
function check(raw: unknown, spec: Spec = SCHEMA, at = ''): string[] {
  if (isLeaf(spec)) {
    if (spec.type === 'boolean') return typeof raw === 'boolean' ? [] : [`${at}: must be true or false`];
    const ok = typeof raw === 'number' && Number.isFinite(raw) && raw >= spec.min && raw <= spec.max && (!spec.int || Number.isInteger(raw));
    return ok ? [] : [`${at}: must be ${spec.int ? 'a whole number' : 'a number'} from ${spec.min} to ${spec.max}`];
  }
  if (!isObject(raw)) return [`${at || 'the file'}: must be an object`];
  const errors: string[] = [];
  for (const k of Object.keys(spec)) {
    const where = at ? `${at}.${k}` : k;
    if (!Object.hasOwn(raw, k)) errors.push(`${where}: missing`);
    else errors.push(...check(raw[k], spec[k], where));
  }
  for (const k of Object.keys(raw)) if (!Object.hasOwn(spec, k)) errors.push(`${at ? `${at}.${k}` : k}: not a tunable`);
  return errors;
}

// Writes `from` into `into`, object by object, so the objects in use stay the same ones.
function assign(into: Record<string, unknown>, from: Record<string, unknown>): void {
  for (const [k, v] of Object.entries(from)) {
    if (isObject(v) && isObject(into[k])) assign(into[k] as Record<string, unknown>, v);
    else into[k] = isObject(v) ? structuredClone(v) : v;
  }
}

function read(file: string): { ok: true; values: Tunables } | { ok: false; errors: string[] } {
  let raw: unknown;
  try {
    raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    return { ok: false, errors: [`${path.basename(file)}: ${(err as Error).message}`] };
  }
  const errors = check(raw);
  return errors.length ? { ok: false, errors } : { ok: true, values: raw as Tunables };
}

const listeners: Listener[] = [];
let file = FILE;
const first = read(FILE);
if (!first.ok) throw new Error(`tunables.json is not valid:\n  ${first.errors.join('\n  ')}`);
const values: Tunables = first.values;

function get(): Tunables {
  return values;
}

function onReload(fn: Listener): void {
  listeners.push(fn);
  fn(values);
}

function changed(): void {
  for (const fn of listeners) fn(values);
}

// Loads a tunables file in place of the numbers in use, if it passes the check.
function load(from: string = file): { ok: boolean; errors: string[] } {
  const r = read(from);
  if (!r.ok) return { ok: false, errors: r.errors };
  file = from;
  assign(values as unknown as Record<string, unknown>, r.values as unknown as Record<string, unknown>);
  changed();
  return { ok: true, errors: [] };
}

// For tests: some numbers changed by hand (checked like a file). reset() puts the file's back.
function override(patch: Record<string, unknown>): { ok: boolean; errors: string[] } {
  const next = structuredClone(values) as unknown as Record<string, unknown>;
  assign(next, patch);
  const errors = check(next);
  if (errors.length) return { ok: false, errors };
  assign(values as unknown as Record<string, unknown>, next);
  changed();
  return { ok: true, errors: [] };
}

function reset(): { ok: boolean; errors: string[] } {
  return load(file);
}

// Reloads the file whenever it changes, calling `then` with how it went. Returns the stop.
function watch(from: string, then: (r: { ok: boolean; errors: string[] }) => void, intervalMs = 1000): () => void {
  const target = path.resolve(from);
  const r = load(target);
  if (!r.ok) throw new Error(`${target} is not valid:\n  ${r.errors.join('\n  ')}`);
  const on = (cur: { mtimeMs: number }, prev: { mtimeMs: number }) => {
    if (cur.mtimeMs !== prev.mtimeMs) then(load(target));
  };
  fs.watchFile(target, { interval: intervalMs }, on);
  return () => fs.unwatchFile(target, on);
}

module.exports = { FILE, SCHEMA, check, get, load, onReload, override, reset, watch };
