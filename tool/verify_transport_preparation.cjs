'use strict';
// Offline regression over an existing routing snapshot. No Firebase or Dify calls.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {buildPayload} = require('../functions/transport_optimizer');
const {prepareTransportOptimization} = require('../functions/transport_optimizer_api');
const {metrics} = require('../functions/transport_payload_optimizer');
const {validateTransportData} = require('../functions/transport_dify');
const {evaluate} = require('../functions/test_support/transport_payload_reference');
async function main() {
  const file = process.argv[2];
  if (!file) throw Error('Usage: node tool/verify_transport_preparation.cjs routing-snapshot.json');
  const d = JSON.parse(fs.readFileSync(file));
  const network = {...d, ...Object.fromEntries(['stops','routes','services','agencies'].map(k=>[k,new Map(d[k].map(r=>[r.id,r]))])),rules:new Map(d.rules)};
  const one = require('../docs/transport_optimizer_meroad_request.json'), two = require('../docs/transport_optimizer_meroad_coal_request.json');
  const copy = v=>JSON.parse(JSON.stringify(v));
  const cases = [
    ['sapporo_meroad_sapporo',one],['meroad_then_coal',two],
    ['coal_then_meroad',{...two,visits:[...two.visits].reverse()}],
    ['rail_bus_transfer',two],['overnight_synthetic',two],
    ['closed_hours',two],['no_services',one],
  ];
  const report=[];
  const previous=process.env.TRANSPORT_OPTIMIZER_PRUNE;delete process.env.TRANSPORT_OPTIMIZER_PRUNE;
  try {
    for (const [name,original] of cases) {
      const query=copy(original);
      let net={...network,optimizerVersionKey:`offline-default-pruning-${name}`};
      if(name==='closed_hours')query.visits.find(v=>v.id==='coal').opening={status:'closed',windows:[]};
      if(name==='no_services')net={...net,trips:[]};
      if(name==='overnight_synthetic') {
        const shift=36000;
        query.departureSeconds+=shift;query.deadlineSeconds+=shift;
        for(const v of query.visits)v.opening.windows=v.opening.windows.map(([a,b])=>[a+shift,b+shift]);
        net={...net,trips:net.trips.map(t=>({...t,times:t.times.map(s=>s.map((v,i)=>(i===2||i===3)&&v!==null?v+shift:v))}))};
      }
      const baseline=buildPayload(net,query,{maxBytes:32*1024*1024}).payload;
      const prepared=await prepareTransportOptimization({auth:{uid:'offline-regression'},data:query},{},null,{loadNetwork:async()=>net});
      const optimized=validateTransportData({transport_data:prepared.inputs.transport_json}).payload;
      const beforeResults=evaluate(baseline,baseline.places.filter(p=>p.role==='visit'));
      const afterResults=evaluate(optimized,optimized.places.filter(p=>p.role==='visit'));
      assert.deepEqual(afterResults,beforeResults,name);
      assert.deepEqual(optimized.places,baseline.places,name+' places');
      assert.deepEqual(optimized.policy,baseline.policy,name+' policy');
      assert.deepEqual(optimized.transfers,baseline.transfers,name+' transfers');
      assert.deepEqual(optimized.warnings,baseline.warnings,name+' warnings');
      const size=p=>({...metrics(JSON.stringify(p)),instances:p.instances.length,segments:p.segments.length,stops:p.stops.length,transfers:p.transfers.length});
      const before=size(baseline),after=size(optimized);
      report.push({case:name,date:query.date,departureSeconds:query.departureSeconds,deadlineSeconds:query.deadlineSeconds,pruning:prepared.stats.pruning,before,after,byteReductionPercent:before.bytes?(1-after.bytes/before.bytes)*100:0,localRouterEqual:true,localResultCount:beforeResults.journeys.length,difyExecuted:false});
    }
  } finally {if(previous===undefined)delete process.env.TRANSPORT_OPTIMIZER_PRUNE;else process.env.TRANSPORT_OPTIMIZER_PRUNE=previous;}
  fs.writeFileSync('docs/transport_preparation_default_pruning_verification.json',JSON.stringify({source:'existing_local_routing_snapshot',snapshotStops:network.stops.size,snapshotTrips:network.trips.length,cases:report,note:'Offline local-router comparison only; not the actual failing request and not a Dify workflow execution.'},null,2)+'\n');
  console.log(JSON.stringify(report));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
