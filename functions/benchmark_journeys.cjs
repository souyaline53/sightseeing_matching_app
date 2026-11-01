"use strict";
// Local real-data benchmark. Never connects to Firebase or writes data.
const fs = require("node:fs"), path = require("node:path");
const { parseFiles } = require("./transport_bundle");
const { routingData, buildRoutingBundle } = require("./transport_routing_bundle");
const router = require("./transport_router");
const { key } = require("./gtfs");
const baselineFile = process.argv.find((a) => a.startsWith("--baseline="))?.slice("--baseline=".length);
const parts = [], bundles = [];
for (const feed of ["yutetsu_bus", "hokkaido_chuo"]) {
  const dir = path.join(__dirname, "../docs/transport", feed);
  const parsed = parseFiles(Object.fromEntries(fs.readdirSync(dir).filter((n) => n.endsWith(".txt")).map((n) => [n, fs.readFileSync(path.join(dir, n))])), feed);
  if (parsed.errors.length) throw Error(parsed.errors.join("\n"));
  parts.push(routingData(parsed.data, parsed.checksum));
  const bundle = buildRoutingBundle(parsed, feed, parsed.checksum);
  bundles.push({ feed, bytes: bundle.descriptor.bytes, rawBytes: bundle.descriptor.rawBytes, withinFeedPairs: parts.at(-1).sameNameConnections.length });
}
const origins = parts.flatMap((p) => p.stops).filter((s) => ["札幌駅前", "札幌駅北口"].includes(s.name));
const ids = new Set(origins.map((s) => s.id));
const central = parts[1], services = new Map(central.services.map((s) => [s.id,s]));
const t = central.trips.find((t) => router.operates(services.get(t.serviceId),"2026-11-01") && t.times.some((s,i) => ids.has(s[0]) && s[4] && s[3]>=28800 && i<t.times.length-3) && t.times.at(-1)[5]);
const queries = [
  { name:"sapporo", from:origins.map((s)=>({stopId:s.id,walkingMinutes:null})), to:[{stopId:t.times.at(-1)[0],walkingMinutes:null}] },
  { name:"yutetsu_platform", from:[{stopId:key("yutetsu_bus","S018100000300100"),walkingMinutes:8}], to:[{stopId:key("yutetsu_bus","S018100001500200"),walkingMinutes:5}] },
];
function run(name, engine, data, maxTransfers) {
  const started=performance.now(), net=engine.prepareNetwork(data), buildMs=performance.now()-started;
  const results=[];
  for (const input of queries) {
    const q={date:"2026-11-01",departureSeconds:28800,maxTransfers,minimumTransferSeconds:180,from:input.from,to:input.to};
    engine.searchJourneys(net,q); // Warm JIT before timing.
    const timings=[];let found;
    for(let i=0;i<5;i++){const begin=performance.now();found=engine.searchJourneys(net,q);timings.push(performance.now()-begin);}
    timings.sort((a,b)=>a-b);
    results.push({name:input.name,medianMs:Math.round(timings[2]),responseJsonBytes:Buffer.byteLength(JSON.stringify({result:found})),requestJsonBytes:Buffer.byteLength(JSON.stringify({data:q})),journeys:found.journeys.length,transfers:found.journeys.map((j)=>j.transferCount),scannedStopTimes:found.stats.scannedStopTimes});
  }
  console.log(JSON.stringify({policy:name,buildMs:Math.round(buildMs),nearbyDirectedPairs:net.nearby?[...net.nearby.values()].reduce((n,m)=>n+m.size,0):0,results}));
}
if (baselineFile) run("previous_5",require(path.resolve(baselineFile)),parts,5);
run("3_without_groups",router,parts.map((p)=>({...p,sameNameConnections:[],stops:p.stops.map(({latitude,longitude,...s})=>s)})),3);
run("3_with_500m_groups",router,parts,3);
console.log(JSON.stringify({routingBundles:bundles}));
