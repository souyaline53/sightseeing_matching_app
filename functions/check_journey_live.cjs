"use strict";
// Read-only production check; no authentication tokens or writes.
const fs = require("node:fs"), path = require("node:path"), assert = require("node:assert/strict");
const { parseFiles } = require("./transport_bundle"), { operates } = require("./transport_router");
(async () => {
  const folder = path.join(__dirname, "../docs/transport/hokkaido_chuo");
  const files = Object.fromEntries(fs.readdirSync(folder).filter((n) => n.endsWith(".txt")).map((n) => [n, fs.readFileSync(path.join(folder, n))]));
  const parsed = parseFiles(files, "hokkaido_chuo"); assert.deepEqual(parsed.errors, []);
  const date = "2026-11-01", services = new Map(parsed.data.services.map((s) => [s.id, s]));
  const origins = parsed.data.stops.filter((s) => ["札幌駅前", "札幌駅北口"].includes(s.name));
  const ids = new Set(origins.map((s) => s.id));
  const t = parsed.data.trips.find((t) => operates(services.get(t.serviceId), date) && t.stopTimes.some((s, i) => ids.has(s.stopId) && s.pickupAllowed && s.departureSeconds >= 28800 && i < t.stopTimes.length - 3) && t.stopTimes.at(-1).dropoffAllowed);
  assert.ok(t, "Real Sapporo departure on test day");
  const query = { date, departureSeconds: 28800, maxTransfers: 3, minimumTransferSeconds: 180,
    from: origins.map((s) => ({stopId:s.id,walkingMinutes:null})), to: [{stopId:t.stopTimes.at(-1).stopId,walkingMinutes:null}] };
  if (process.argv.includes("--timetable")) query.timetable=true;
  const unpack=(result)=>result.journeyPool?{...result,journeys:JSON.parse(require("node:zlib").gunzipSync(Buffer.from(result.journeyPool.data,"base64")))}:result;
  const queryFile = process.argv.find((a) => a.startsWith("--query-file="))?.slice("--query-file=".length);
  if (queryFile) fs.writeFileSync(queryFile, JSON.stringify(query));
  const endpoint = "https://asia-northeast1-sightseeing-matching-prototype.cloudfunctions.net/searchTransportJourneys";
  for (let i=0;i<2;i++) {
    const r=await fetch(endpoint,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({data:query}),signal:AbortSignal.timeout(60000)});
    const responseText=await r.text(), body=JSON.parse(responseText);assert.equal(r.status,200,JSON.stringify(body));
    const result=unpack(body.result);assert.ok(result.journeys.length>0);assert.equal(result.versions.hokkaido_chuo,parsed.checksum);
    for(const journey of result.journeys) {assert.ok(journey.legs.length<=4);assert.equal(journey.verificationStatus,"needsReview");for(const x of journey.transfers) assert.ok(x.availableSeconds>=x.requiredSeconds);}
    console.log(JSON.stringify({phase:i===0?"first":"warm",requestJsonBytes:Buffer.byteLength(JSON.stringify({data:query})),responseJsonBytes:Buffer.byteLength(responseText),contentEncoding:r.headers.get("content-encoding")||"none",journeys:result.journeys.length,...result.stats}));
  }
  const { key }=require("./gtfs");
  const grouped={...query,from:[{stopId:key("yutetsu_bus","S018100000300100"),walkingMinutes:8}],to:[{stopId:key("yutetsu_bus","S018100001500200"),walkingMinutes:5}]};
  const groupedResponse=await fetch(endpoint,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({data:grouped}),signal:AbortSignal.timeout(60000)});
  const groupedText=await groupedResponse.text(), groupedResult=unpack(JSON.parse(groupedText).result);
  assert.equal(groupedResponse.status,200);assert.ok(groupedResult.journeys.some((j)=>j.usesEstimatedWalking && j.transferCount===0));
  console.log(JSON.stringify({phase:"nearby_yutetsu",requestJsonBytes:Buffer.byteLength(JSON.stringify({data:grouped})),responseJsonBytes:Buffer.byteLength(groupedText),...groupedResult.stats}));
  const bad=await fetch(endpoint,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({data:{...query,maxTransfers:4}})});
  assert.equal(bad.status,400);assert.equal((await bad.json()).error.status,"INVALID_ARGUMENT");
  console.log("PASS: production Callable, real Sapporo platform IDs, 500m Yutetsu platform expansion, active versions, transfer buffers, 4 transfers rejected");
})().catch((e) => { console.error(e.message); process.exitCode = 1; });
