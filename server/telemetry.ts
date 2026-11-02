// Telemetry: what the server's loops and rules are doing, for its admins. Three kinds of record:
//
//   - tick timings: every simulation loop (each battle mode at 10 Hz, the galaxy tick) is wrapped
//     in timed(), and every tunables telemetry.windowMs its ticks are summed up (count, p50, p99,
//     max). A loop whose p99 runs over telemetry.tickBudgetMs raises an alert.
//   - events: sign-ins and refusals, war supply credited and capped, tunables reloaded. The last
//     telemetry.eventsKept are kept in memory, and every one goes to the log file (TELEMETRY_FILE,
//     one JSON object a line) when the server has one.
//   - alerts: events an admin should look at, the last telemetry.alertsKept kept.
//
// One recorder for the whole process (several test servers share it); reset() clears it.

const fs: typeof import('node:fs') = require('node:fs');
const T = require('./tunables.ts');

interface TelemetryEvent {
  at: number;
  kind: string;
  [key: string]: unknown;
}
interface Alert {
  at: number;
  kind: string;
  text: string;
}
interface Window {
  since: number;
  times: number[];
}
interface TickSummary {
  loop: string;
  at: number;
  n: number;
  p50: number;
  p99: number;
  max: number;
  over: boolean;
}

let file: string | null = null;
let clock: () => number = Date.now;
let events: TelemetryEvent[] = [];
let alerts: Alert[] = [];
let windows = new Map<string, Window>();
let ticks = new Map<string, TickSummary>(); // the last summary of each loop
let counters: Record<string, number> = {};

const round2 = (x: number) => Math.round(x * 100) / 100;

// The value at fraction `q` of the sorted list (nearest rank).
function quantile(sorted: number[], q: number): number {
  if (!sorted.length) return 0;
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(q * sorted.length) - 1))];
}

function summarize(times: number[]) {
  const s = times.slice().sort((a, b) => a - b);
  return { n: s.length, p50: round2(quantile(s, 0.5)), p99: round2(quantile(s, 0.99)), max: round2(s[s.length - 1] ?? 0) };
}

// Logs to TELEMETRY_FILE (null: memory only), with `now` as the clock.
function configure({ file: to = null, now = Date.now }: { file?: string | null; now?: () => number } = {}): void {
  file = to;
  clock = now;
}

function event(kind: string, data: Record<string, unknown> = {}): TelemetryEvent {
  const e: TelemetryEvent = { at: clock(), kind, ...data };
  events.push(e);
  const kept = T.get().telemetry.eventsKept;
  if (events.length > kept) events.splice(0, events.length - kept);
  counters[kind] = (counters[kind] || 0) + 1;
  if (file) {
    try {
      fs.appendFileSync(file, `${JSON.stringify(e)}\n`);
    } catch (err) {
      file = null; // a log that can't be written mustn't stop the galaxy: memory only from now on
      console.error('telemetry: stopped writing the log file:', (err as Error).message);
    }
  }
  return e;
}

function alert(kind: string, text: string, data: Record<string, unknown> = {}): Alert {
  const a: Alert = { at: clock(), kind, text };
  alerts.push(a);
  const kept = T.get().telemetry.alertsKept;
  if (alerts.length > kept) alerts.splice(0, alerts.length - kept);
  event('alert', { alert: kind, text, ...data });
  return a;
}

// One tick of `loop` took `ms`. Once the loop's window is telemetry.windowMs old, it's summed up.
function tick(loop: string, ms: number): TickSummary | null {
  const t = clock();
  let w = windows.get(loop);
  if (!w) windows.set(loop, (w = { since: t, times: [] }));
  w.times.push(ms);
  const { windowMs, tickBudgetMs } = T.get().telemetry;
  if (t - w.since < windowMs) return null;
  return close(loop, w, tickBudgetMs);
}

function close(loop: string, w: Window, budget: number): TickSummary {
  const s: TickSummary = { loop, at: clock(), ...summarize(w.times), over: false };
  s.over = s.p99 > budget;
  ticks.set(loop, s);
  windows.set(loop, { since: clock(), times: [] });
  event('tick', { ...s });
  if (s.over) alert('tick', `${loop} ticks ran over budget: p99 ${s.p99} ms (budget ${budget} ms, ${s.n} ticks)`, { loop });
  return s;
}

// `fn`, timed as one tick of `loop` each time it runs.
function timed<A extends unknown[]>(loop: string, fn: (...args: A) => void): (...args: A) => void {
  return (...args: A) => {
    const start = performance.now();
    try {
      fn(...args);
    } finally {
      tick(loop, performance.now() - start);
    }
  };
}

// Everything for the admins' dashboard: the last tick summary of each loop (and the window still
// filling), the alerts, the counts of each kind of event, and the latest events.
function snapshot(recent = 50) {
  const live: Record<string, TickSummary & { filling: boolean }> = {};
  for (const [loop, s] of ticks) live[loop] = { ...s, filling: false };
  for (const [loop, w] of windows) if (!live[loop] && w.times.length) live[loop] = { loop, at: clock(), ...summarize(w.times), over: false, filling: true };
  return { ticks: live, alerts: alerts.slice(), counters: { ...counters }, events: events.slice(-recent) };
}

function recent(kind: string | null = null, n = 50): TelemetryEvent[] {
  return (kind ? events.filter((e) => e.kind === kind) : events).slice(-n);
}

function reset(): void {
  events = [];
  alerts = [];
  windows = new Map();
  ticks = new Map();
  counters = {};
}

module.exports = { configure, event, alert, tick, timed, snapshot, recent, reset, quantile };
