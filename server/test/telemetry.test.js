// Telemetry: tick windows summed up, alerts over budget, events kept and logged.

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const T = require('../tunables.ts');
const TM = require('../telemetry.ts');

test('ticks are summed up once a window, and a slow p99 raises an alert', () => {
  let clock = 0;
  TM.reset();
  TM.configure({ now: () => clock });
  try {
    for (let i = 1; i <= 100; i++) {
      clock += 100;
      TM.tick('sector', i === 100 ? 90 : 10 + (i % 5));
    }
    assert.strictEqual(TM.snapshot().ticks.sector.filling, true, 'the window is still filling');
    clock = 60_100;
    const s = TM.tick('sector', 12);
    assert.deepStrictEqual({ n: s.n, p50: s.p50, max: s.max, over: s.over }, { n: 101, p50: 12, max: 90, over: false });
    assert.strictEqual(TM.snapshot().alerts.length, 0, 'one slow tick in a hundred is under p99');
    for (let i = 0; i < 20; i++) {
      clock += 100;
      TM.tick('sector', 75);
    }
    clock += 60_000;
    const slow = TM.tick('sector', 75);
    assert.ok(slow.over && slow.p99 === 75);
    const [a] = TM.snapshot().alerts;
    assert.strictEqual(a.kind, 'tick');
    assert.match(a.text, /sector ticks ran over budget: p99 75 ms \(budget 60 ms/);
    assert.strictEqual(TM.snapshot().counters.tick, 2);
  } finally {
    TM.configure();
    TM.reset();
  }
});

test('timed() times every run, even one that throws', () => {
  TM.reset();
  const runs = [];
  const fn = TM.timed('galaxy', (n) => {
    runs.push(n);
    if (n === 2) throw new Error('boom');
  });
  fn(1);
  assert.throws(() => fn(2), /boom/);
  assert.deepStrictEqual(runs, [1, 2]);
  assert.strictEqual(TM.snapshot().ticks.galaxy.n, 2);
  assert.strictEqual(TM.quantile([1, 2, 3, 4], 0.5), 2);
  assert.strictEqual(TM.quantile([], 0.99), 0);
  TM.reset();
});

test('events are kept up to the tunable and every one goes to the log file', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'telemetry-'));
  const file = path.join(dir, 'log.jsonl');
  TM.reset();
  TM.configure({ file, now: () => 5 });
  T.override({ telemetry: { eventsKept: 3 } });
  try {
    for (let i = 0; i < 5; i++) TM.event('sign_in', { n: i });
    assert.deepStrictEqual(TM.recent('sign_in').map((e) => e.n), [2, 3, 4]);
    assert.strictEqual(TM.snapshot().counters.sign_in, 5, 'counted, all of them');
    const lines = fs.readFileSync(file, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
    assert.strictEqual(lines.length, 5);
    assert.deepStrictEqual(lines[4], { at: 5, kind: 'sign_in', n: 4 });
  } finally {
    T.reset();
    TM.configure();
    TM.reset();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
