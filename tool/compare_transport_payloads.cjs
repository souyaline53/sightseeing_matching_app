'use strict';
const fs = require('node:fs'), assert = require('node:assert/strict');
const { pruneUnreachable, metrics } = require('../functions/transport_payload_optimizer');
const { evaluate } = require('../functions/test_support/transport_payload_reference');
const copy = (v) => JSON.parse(JSON.stringify(v));
const one = require('../docs/transport_optimizer_sample.json'), two = require('../docs/transport_optimizer_meroad_coal_network.json');
const cases = [
  ['sapporo_meroad_sapporo', copy(one), ['melon']],
  ['meroad_then_coal', copy(two), ['melon', 'coal']],
  ['coal_then_meroad', copy(two), ['coal', 'melon']],
  ['rail_bus_transfer', copy(two), ['melon', 'coal']],
  ['overnight', copy(one), ['melon']],
  ['closed_hours', copy(two), ['melon', 'coal']],
  ['no_services', copy(one), ['melon']],
];
for (const [name, p] of cases) {
  if (name === 'overnight') {
    // Shift the registered timetable across midnight; synthetic regression, not a real operating date claim.
    const shift = 10 * 3600;
    p.departureSeconds += shift; p.deadlineSeconds += shift;
    for (const s of p.segments) { s.departureSeconds += shift; s.arrivalSeconds += shift; }
    for (const place of p.places.filter((v) => v.role === 'visit')) place.opening.windows = place.opening.windows.map(([a, b]) => [a + shift, b + shift]);
  }
  if (name === 'closed_hours') p.places.find((v) => v.id === 'coal').opening = { status: 'known', windows: [[0, 1]] };
  if (name === 'no_services') { p.segments = []; p.instances = []; }
}
const report = cases.map(([name, before, order]) => {
  const start = performance.now(), after = pruneUnreachable(before), elapsedMs = performance.now() - start;
  const places = (p) => order.map((id) => p.places.find((v) => v.role === 'visit' && v.id === id));
  // Local router validates exact visit orders, times, transfers, walks, review and warnings.
  const originalResults = evaluate(before, places(before)), optimizedResults = evaluate(after, places(after));
  assert.deepEqual(optimizedResults, originalResults, name);
  const size = (p) => ({ ...metrics(JSON.stringify(p)), instances: p.instances.length, stops: p.stops.length, segments: p.segments.length, transfers: p.transfers.length });
  return { case: name, source: name === 'overnight' ? 'synthetic_shift_of_registered_sample' : 'registered_sample_with_case_constraints', before: size(before), after: size(after), byteReductionPercent: (1 - size(after).bytes / size(before).bytes) * 100,
    localRouterEqual: true, localResultCount: originalResults.journeys.length, localResults: originalResults, difyResultsEqual: null, optimizationMs: Math.round(elapsedMs * 100) / 100, difySendMs: null };
});
fs.writeFileSync('docs/transport_optimizer_payload_comparison.json', `${JSON.stringify(report, null, 2)}\n`);
for (const r of report) {
  const name = r.case === 'sapporo_meroad_sapporo' ? 'meroad' : r.case === 'meroad_then_coal' ? 'meroad_coal' : null;
  if (name) fs.writeFileSync(`docs/transport_optimizer_${name}_optimized.json`, `${JSON.stringify(pruneUnreachable(cases.find((c) => c[0] === r.case)[1]))}\n`);
}
console.log(JSON.stringify(report.map(({ case: name, before, after, byteReductionPercent, localRouterEqual, localResultCount }) => ({ name, before, after, byteReductionPercent, localRouterEqual, localResultCount }))));
