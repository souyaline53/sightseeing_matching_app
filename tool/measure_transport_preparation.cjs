'use strict';
// Read-only production measurement. Run --before and default in separate processes
// so each has a cold loader cache. Baseline is the committed pre-change API module.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const Module = require('node:module');
const { measureFirestore } = require('../functions/transport_read_metrics');
(async () => {
  const before = process.argv.includes('--before');
  const { db, bucket } = require('../functions/production_transport_context.cjs').context();
  try {
    let load;
    if (before) {
      const filename = path.resolve('functions/transport_optimizer_before_measurement.cjs');
      const source = execFileSync('git', ['show', 'HEAD:functions/transport_optimizer_api.js'], { encoding: 'utf8' });
      const mod = new Module(filename, module); mod.filename = filename; mod.paths = Module._nodeModulePaths(path.dirname(filename)); mod._compile(source, filename);
      load = mod.exports.loadOptimizerNetwork;
    } else load = require('../functions/transport_optimizer_api').loadOptimizerNetwork;
    const measurements = [];
    for (const label of ['cold', 'warm']) {
      const measured = measureFirestore(db), start = performance.now();
      const network = await load(measured.db, bucket);
      measurements.push({ label, ...measured.stats, elapsedMs: Math.round(performance.now() - start), stops: network.stops.size, trips: network.trips.length });
    }
    const report = { mode: before ? 'before' : 'after', measurements, difySendMs: null,
      note: 'Live SDK calls, not Cloud Billing totals; empty queries, retries and index-entry billing must be distinguished.' };
    fs.writeFileSync(`docs/transport_optimizer_reads_${report.mode}.json`, `${JSON.stringify(report, null, 2)}\n`);
    console.log(JSON.stringify(report));
  } finally { await db.terminate(); }
})().catch((e) => { console.error(e.message); process.exitCode = 1; });
