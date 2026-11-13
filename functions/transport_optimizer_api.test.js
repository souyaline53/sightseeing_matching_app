'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {prepareTransportOptimization} = require('./transport_optimizer_api');
const {buildPayload} = require('./transport_optimizer');
const {validateTransportData} = require('./transport_dify');
const {evaluate} = require('./test_support/transport_payload_reference');
function fixture() {
  const stopIds = ['a','via','visit','d','isolated-a','isolated-b'];
  const time = (id,seq,t) => [id,seq,t,t,true,true];
  const network = {
    optimizerVersionKey:'api-default-pruning-fixture-v1',
    stops:new Map(stopIds.map(id=>[id,{id,name:id}])),
    routes:new Map([['rail',{id:'rail',name:'rail',routeType:2,agencyId:'operator'}]]),
    agencies:new Map([['operator',{id:'operator',name:'operator'}]]),
    services:new Map([['day',{id:'day',validFrom:'2026-11-01',validTo:'2026-11-01',weekdays:[7]}]]),
    trips:[{id:'out',routeId:'rail',serviceId:'day',times:[time('a',1,1000),time('via',2,1100),time('visit',3,1200)]},
      {id:'back',routeId:'rail',serviceId:'day',times:[time('visit',1,2500),time('d',2,3000)]},
      // Same component but unusable because it departs the origin before it is reachable.
      {id:'too-early',routeId:'rail',serviceId:'day',times:[time('via',1,500),time('visit',2,600)]},
      ...Array.from({length:1000},(_,i)=>({id:'isolated-'+i,routeId:'rail',serviceId:'day',times:[time('isolated-a',1,1500),time('isolated-b',2,1600)]}))],
    rules:new Map(),
  };
  const place=(id,stopId)=>({id,name:id,accessStops:[{stopId,walkingMinutes:0,verificationStatus:'verified'}]});
  const query={date:'2026-11-01',departureSeconds:0,deadlineSeconds:4000,modes:['rail','walk'],preference:'transfers',minimumTransferSeconds:180,
    origin:place('start','a'),destination:place('end','d'),visits:[{...place('spot','visit'),staySeconds:600,opening:{status:'known',windows:[[0,4000]]}}]};
  return {network,query};
}
test('production preparation defaults to conservative pruning and keeps complete feasible detour',async()=>{
  const {network,query}=fixture();
  const before=buildPayload(network,query,{maxBytes:4000000}).payload;
  const old=process.env.TRANSPORT_OPTIMIZER_PRUNE; delete process.env.TRANSPORT_OPTIMIZER_PRUNE;
  try {
    const result=await prepareTransportOptimization({auth:{uid:'test'},data:query},{},null,{loadNetwork:async()=>network});
    assert.equal(result.stats.pruning,true);
    const after=JSON.parse(result.inputs.transport_json);
    validateTransportData({transport_data:result.inputs.transport_json});
    assert.deepEqual(after.instances.map(i=>i.tripId),['out','back']);
    assert(after.stops.some(s=>s.id==='via'));
    assert.deepEqual(after.segments,before.segments.filter(s=>s.instanceId.startsWith('out@')||s.instanceId.startsWith('back@')));
    assert.deepEqual(evaluate(after,[after.places[1]]),evaluate(before,[before.places[1]]));
    assert(result.bytes < Buffer.byteLength(JSON.stringify(before))/10);
  } finally {if(old===undefined)delete process.env.TRANSPORT_OPTIMIZER_PRUNE;else process.env.TRANSPORT_OPTIMIZER_PRUNE=old;}
});
test('explicit rollback disables pruning and does not reuse the optimized cache',async()=>{
  const {network,query}=fixture();const old=process.env.TRANSPORT_OPTIMIZER_PRUNE;
  process.env.TRANSPORT_OPTIMIZER_PRUNE='false';
  try {
    const result=await prepareTransportOptimization({auth:{uid:'test'},data:query},{},null,{loadNetwork:async()=>network});
    assert.equal(result.stats.pruning,false);
    assert.equal(JSON.parse(result.inputs.transport_json).instances.length,network.trips.length);
  } finally {if(old===undefined)delete process.env.TRANSPORT_OPTIMIZER_PRUNE;else process.env.TRANSPORT_OPTIMIZER_PRUNE=old;}
});

test('two-night input retains third-day services and registered assumptions without a user confirmation',async()=>{
  const {network,query}=fixture();
  network.optimizerVersionKey+='-two-night';
  network.services.set('day',{id:'day',validFrom:'2026-11-01',validTo:'2026-11-03',weekdays:[1,2,7]});
  query.deadlineSeconds=2*86400+4000;
  query.visits[0].opening={status:'known',windows:[[0,86400],[86400,172800],[172800,259200]],assumedOpen:true};
  query.visits[0].accessStops=[{stopId:'visit',walkingMinutes:0,verificationStatus:'unverified',useRegisteredWalking:true}];
  const result=await prepareTransportOptimization({auth:{uid:'test'},data:query},{},null,{loadNetwork:async()=>network});
  const p=JSON.parse(result.inputs.transport_json);
  validateTransportData({transport_data:result.inputs.transport_json});
  assert(p.instances.some(i=>i.serviceDate==='2026-11-03'));
  assert.equal(p.places[1].opening.assumedOpen,true);
  assert.equal(p.places[1].accessStops[0].usableForRouting,true);
  assert.equal(p.places[1].accessStops[0].requiresReview,true);
  assert.equal(p.places[1].accessStops[0].verificationStatus,'unverified');
});
