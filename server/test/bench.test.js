// The sector tick budget, briefly: 32 pilots and 400 units for 30 seconds of battle. (The full run
// is `npm run bench`.)

const test = require('node:test');
const assert = require('node:assert');
const { run, verdict } = require('../bench/sector.ts');

test('a full sector battle fits its tick: p99 within the budget', () => {
  const r = run({ pilots: 32, units: 400, ticks: 300, seed: 2 });
  assert.strictEqual(r.meanUnits, 400, 'the field stays full');
  assert.ok(r.ok, verdict(r));
  assert.match(verdict({ ...r, ok: false, p99: 99 }), /worker threads.*250/);
});
