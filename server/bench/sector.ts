// The sector tick budget (guide ARCH-01, ARCH-07): can one Node process run a full Sector Battle,
// 32 pilots and 400 units, in its 100 ms tick with room to spare? This runs one, flat out, and
// times every tick the way the server runs it: the simulation step, and every other tick a snapshot
// to each of the 32 pilots, written out as JSON. The units fight all the way through: whatever dies
// is dropped again, so there are always about 400 on the field, and every pilot gives their units
// an order every 2 seconds.
//
//   npm run bench                        (tunables sector: 32 pilots, 400 units, 3000 ticks)
//   node bench/sector.ts --units=250 --ticks=600 --json
//
// Passes when the p99 tick is within sector.p99BudgetMs (60 ms). If it isn't, the guide's fallback
// steps apply, in order: the battles move to worker threads, then the unit budget drops to
// sector.fallbackUnits (250); this says which.

const B = require('../battle');
const T = require('../tunables.ts');
const TM = require('../telemetry.ts');

interface Options {
  pilots: number;
  units: number;
  ticks: number;
  seed: number;
}
interface Report {
  pilots: number;
  units: number;
  ticks: number;
  meanUnits: number;
  lost: number; // units destroyed (and dropped again) over the run
  p50: number;
  p99: number;
  max: number;
  budget: number;
  tickMs: number;
  ok: boolean;
  snapshotBytes: number;
}

const MIX = ['striker', 'tank', 'striker', 'aa', 'artillery', 'striker', 'tank', 'fighter', 'gunship', 'bomber'];
const ORDER_S = 2; // each pilot orders their units this often

const round2 = (x: number) => Math.round(x * 100) / 100;

// A planet and sector to fight over (the battle only reads their ids and names).
function arena(seed: number) {
  const sector = { id: `bench-${seed}`, name: `Bench ${seed}`, lat: 0, lon: 0, owner: 'ashen', capital: false, links: [] };
  return { wp: { id: 'bench', name: 'Bench', system: 'bench', sectors: [sector] }, sector };
}

function run({ pilots, units, ticks, seed }: Options): Report {
  const { wp, sector } = arena(seed);
  const b = B.newBattle({ id: 'bench', wp, sector, attacker: 'compact', defender: 'ashen', now: 0 });
  const names: string[] = [];
  for (let i = 0; i < pilots; i++) {
    const name = `Pilot ${i + 1}`;
    B.addPilot(b, name, i % 2 ? 'd' : 'a', i % 2 ? 'ashen' : 'compact');
    names.push(name);
  }
  const mobile = () => [...b.units.values()].filter((u: any) => u.hp > 0 && B.CATALOG[u.type].kind !== 'structure' && !B.CATALOG[u.type].acu);
  let next = 0;
  let lost = -units;
  // Tops the field back up to `units`, round the pilots, as the server's drops do.
  const topUp = () => {
    const short = units - mobile().length;
    lost += Math.max(0, short);
    for (let i = 0; i < short; i++) {
      const name = names[next++ % names.length];
      const p = b.pilots.get(name);
      B.dropUnits(b, p.side, name, MIX[next % MIX.length], 1);
    }
  };
  topUp();
  const times: number[] = [];
  let unitSum = 0;
  let bytes = 0;
  const every = Math.round(ORDER_S * 10);
  for (let t = 0; t < ticks; t++) {
    b.ai.mass = 0; // the field stays at `units`: the defender AI buys nothing of its own
    if (t % every === 0) {
      // Every pilot sends their units at the enemy's end of the map, attack-moving.
      for (const name of names) {
        const p = b.pilots.get(name);
        const mine = mobile().filter((u: any) => u.owner === name).map((u: any) => u.id);
        const z = p.side === 'a' ? B.SIZE * 0.75 : B.SIZE * 0.25;
        B.order(b, name, { order: 'amove', units: mine, x: B.SIZE * (0.2 + 0.6 * ((t / every + names.indexOf(name)) % 5) / 4), z });
      }
    }
    const start = performance.now();
    B.step(b, 0.1);
    if (t % 2 === 0) {
      const f = B.frame(b);
      bytes = 0;
      for (const name of names) bytes += JSON.stringify(B.stateFor(b, f, name)).length;
    }
    times.push(performance.now() - start);
    if (b.result) b.result = null; // nothing ends the run early
    topUp();
    unitSum += mobile().length;
  }
  const sorted = times.slice().sort((x, y) => x - y);
  const { p99BudgetMs, tickMs } = T.get().sector;
  const p99 = round2(TM.quantile(sorted, 0.99));
  return {
    pilots,
    units,
    ticks,
    meanUnits: Math.round(unitSum / ticks),
    lost,
    p50: round2(TM.quantile(sorted, 0.5)),
    p99,
    max: round2(sorted[sorted.length - 1]),
    budget: p99BudgetMs,
    tickMs,
    ok: p99 <= p99BudgetMs,
    snapshotBytes: bytes,
  };
}

// What to do about a report, in the guide's order.
function verdict(r: Report): string {
  if (r.ok) return `PASS: ${r.pilots} pilots and ${r.units} units fit the ${r.tickMs} ms tick (p99 ${r.p99} ms, budget ${r.budget} ms)`;
  const fallback = T.get().sector.fallbackUnits;
  return `FAIL: p99 ${r.p99} ms is over the ${r.budget} ms budget. Fallback: run sector battles in worker threads; if that isn't enough, drop the unit budget to ${fallback}`;
}

function args(argv: string[]): Options & { json: boolean } {
  const s = T.get().sector;
  const opt = { pilots: s.pilots, units: s.aiUnits, ticks: 3000, seed: 1, json: false };
  for (const a of argv) {
    const [k, v] = a.replace(/^--/, '').split('=');
    if (k === 'json') opt.json = true;
    else if (k in opt && Number.isFinite(Number(v))) (opt as Record<string, number | boolean>)[k] = Number(v);
  }
  return opt;
}

if (require.main === module) {
  const opt = args(process.argv.slice(2));
  const r = run(opt);
  if (opt.json) console.log(JSON.stringify({ ...r, verdict: verdict(r) }));
  else {
    console.log(`Sector tick benchmark: ${r.pilots} pilots, ${r.units} units (mean ${r.meanUnits} on the field, ${r.lost} destroyed and dropped again), ${r.ticks} ticks`);
    console.log(`  tick p50 ${r.p50} ms, p99 ${r.p99} ms, max ${r.max} ms; ${Math.round(r.snapshotBytes / 1024)} KiB of snapshots a frame`);
    console.log(verdict(r));
  }
  process.exitCode = r.ok ? 0 : 1;
}

module.exports = { run, verdict };
