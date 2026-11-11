"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { prepareNetwork, searchJourneys, validateQuery } = require("./transport_router");
const { routingData, buildRoutingBundle } = require("./transport_routing_bundle");
const { parseGtfs } = require("./gtfs");
const { fixture } = require("./test_support/gtfs_fixture");
const service = { id: "s", validFrom: "2026-06-01", validTo: "2026-06-01", weekdays: [1,2,3,4,5,6,7], removedDates: [], addedDates: [] };
const stop = (id, name = id) => ({ id, name });
const time = (id, seq, sec, pickup = true, dropoff = true) => [id, seq, sec, sec, pickup, dropoff];
const trip = (id, a, b, departure, arrival) => ({ id, routeId: "r", serviceId: "s", times: [time(a,1,departure),time(b,2,arrival)] });
const query = (from = "p0", to = "p6") => ({ date: "2026-06-01", departureSeconds: 8*3600, maxTransfers: 3, minimumTransferSeconds: 180, from: [{ stopId: from, walkingMinutes: 0 }], to: [{ stopId: to, walkingMinutes: 0 }] });
const network = (trips, stops, transfers = [], services = [service]) => prepareNetwork([{ stops, routes: [{id:"r", name:"路線"}], trips, services, transfers }]);
const edge = (a,b,min=180,extra={}) => ({id:`${a}-${b}`,sourceType:"gtfs",fromStopId:a,toStopId:b,transferType:2,minTransferSeconds:min,...extra});
test("four vehicles / three transfers succeeds; five vehicles cannot be reached", () => {
  const stops = Array.from({length:8}, (_,i)=>stop(`p${i}`));
  const trips = Array.from({length:7}, (_,i)=>trip(`t${i}`,`p${i}`,`p${i+1}`,28800+i*900,29400+i*900));
  const net = network(trips, stops), found = searchJourneys(net, query("p0","p4"));
  assert.equal(found.journeys.length,1); assert.equal(found.journeys[0].transferCount,3); assert.equal(found.journeys[0].legs.length,4);
  assert.equal(searchJourneys(net, query("p0","p5")).journeys.length,0);
  assert.equal(searchJourneys(net,{...query("p0","p4"),maxTransfers:2}).journeys.length,0);
});
test("without coordinates, name / zone / parent alone do not connect platforms", () => {
  const stops = [stop("p0"), {...stop("a","夕張高校"),zoneId:"z",parentStationId:"station"}, {...stop("b","夕張高校"),zoneId:"z",parentStationId:"station"},stop("station"),stop("p6")];
  const trips = [trip("t0","p0","a",28800,29400),trip("t1","b","p6",30000,30600)];
  assert.equal(searchJourneys(network(trips,stops),query()).journeys.length,0);
  assert.equal(searchJourneys(network(trips,stops,[edge("a","b")]),query()).journeys.length,1);
  assert.equal(searchJourneys(network(trips,stops,[edge("b","a")]),query()).journeys.length,0);
  assert.equal(searchJourneys(network(trips,stops,[edge("a","b",null)]),query()).journeys.length,0);
  assert.equal(searchJourneys(network(trips,stops,[edge("a","b",180,{sourceType:"manual",verificationStatus:"unverified"})]),query()).journeys.length,1);
});
test("transfer minimum and pickup/dropoff apply in exact seconds", () => {
  const stops=[stop("p0"),stop("a"),stop("p6")];
  const a=trip("t0","p0","a",28800,29401), b=trip("t1","a","p6",29580,30000);
  assert.equal(searchJourneys(network([a,b],stops),query()).journeys.length,0);
  b.times[0][2]=b.times[0][3]=29581;
  assert.equal(searchJourneys(network([a,b],stops),query()).journeys.length,1);
  b.times[0][4]=false;
  assert.equal(searchJourneys(network([a,b],stops),query()).journeys.length,0);
  b.times[0][4]=true; a.times[1][5]=false;
  assert.equal(searchJourneys(network([a,b],stops),query()).journeys.length,0);
});
test("forbidden scoped rule retains alternative incoming trip context", () => {
  const stops=[stop("p0"),stop("a"),stop("p6")];
  const trips=[trip("bad","p0","a",28800,29400),trip("good","p0","a",28800,29460),trip("next","a","p6",30000,30600)];
  const rules=[edge("a","a",0,{fromTripId:"bad",toTripId:"next",transferType:3})];
  const found=searchJourneys(network(trips,stops,rules),query()).journeys;
  assert.equal(found.length,1);assert.equal(found[0].legs[0].tripId,"good");
});
test("GTFS trip specific rule overrides generic forbidden rule",()=>{
  const stops=[stop("p0"),stop("a"),stop("p6")], trips=[trip("t0","p0","a",28800,29400),trip("next","a","p6",30000,30600)];
  const rules=[edge("a","a",0,{transferType:3}),edge("a","a",180,{fromTripId:"t0",toTripId:"next"})];
  assert.equal(searchJourneys(network(trips,stops,rules),query()).journeys.length,1);
});
test("service exceptions and previous service day's 25:xx are honored",()=>{
  const s={...service,weekdays:[],addedDates:["2026-05-31"]};
  const net=network([trip("night","p0","p6",25*3600,26*3600)],[stop("p0"),stop("p6")],[],[s]);
  const q={...query(),departureSeconds:1800};
  const found=searchJourneys(net,q).journeys[0];assert.equal(found.legs[0].serviceDate,"2026-05-31");assert.equal(found.departureSeconds,3600);
  s.removedDates=["2026-05-31"];assert.equal(searchJourneys(net,q).journeys.length,0);
});
test("loop visits retain sequence; walking prevents impossible boarding",()=>{
  const t={...trip("loop","p0","p6",28800,31000), times:[time("p0",1,28800),time("a",2,29000),time("p0",3,30000),time("p6",4,31000)]};
  const found=searchJourneys(network([t],[stop("p0"),stop("a"),stop("p6")]),{...query(),departureSeconds:29500}).journeys[0];
  assert.equal(found.legs[0].boardingSequence,3);
  assert.equal(searchJourneys(network([t],[stop("p0"),stop("p6")]),{...query(),from:[{stopId:"p0",walkingMinutes:1440}]}).journeys.length,0);
});
test("Pareto frontier preserves slower route with fewer transfers",()=>{
  const stops=[stop("p0"),stop("a"),stop("p6")], trips=[trip("direct","p0","p6",28800,32000),trip("t0","p0","a",28800,29000),trip("t1","a","p6",29200,30000)];
  const found=searchJourneys(network(trips,stops),query()).journeys;
  assert.deepEqual(found.map(j=>j.transferCount),[1,0]);
});
test("unknown walks stay unconfirmed; invalid queries and >3 transfers rejected",()=>{
  const q=query();q.from[0].walkingMinutes=null;
  const found=searchJourneys(network([trip("t","p0","p6",28800,30000)],[stop("p0"),stop("p6")]),q).journeys[0];
  assert.equal(found.verificationStatus,"needsReview");assert.equal(found.walkingMinutesBefore,null);
  for (const patch of [{maxTransfers:4},{date:"2026-02-30"},{minimumTransferSeconds:0},{departureSeconds:86400}]) assert.throws(()=>validateQuery({...query(),...patch}));
});

test("GTFS transfer references/types/minimums validate and survive compact snapshots",()=>{
  const files=fixture();
  files["transfers.txt"]="from_stop_id,to_stop_id,transfer_type,min_transfer_time,from_trip_id,to_route_id\n01,02,2,240,0001,01\n";
  const parsed=parseGtfs(files,"feed"); assert.deepEqual(parsed.errors,[]);
  const data=routingData(parsed.data,"v1");
  assert.equal(data.transfers[0].minTransferSeconds,240);assert.equal(data.transfers[0].fromStopId,"feed~MDE");
  assert.equal(data.trips[0].times[0][3],87031);
  assert.ok(buildRoutingBundle(parsed,"feed","v1").descriptor.bytes>0);
  for(const bad of ["01,02,2,,0001,01", "missing,02,2,240,0001,01", "01,02,9,240,0001,01"]) {
    files["transfers.txt"]="from_stop_id,to_stop_id,transfer_type,min_transfer_time,from_trip_id,to_route_id\n"+bad+"\n";
    assert.match(parseGtfs(files,"feed").errors.join(),/transfers.txt:2:/);
  }
});
test("real Hokkaido Chuo data routes actual platform IDs with bounded scanning",()=>{
  const fs=require("node:fs"),path=require("node:path"),{parseFiles}=require("./transport_bundle");
  const dir=path.join(__dirname,"../docs/transport/hokkaido_chuo");
  const files=Object.fromEntries(fs.readdirSync(dir).filter(n=>n.endsWith(".txt")).map(n=>[n,fs.readFileSync(path.join(dir,n))]));
  const parsed=parseFiles(files,"hokkaido_chuo");assert.deepEqual(parsed.errors,[]);
  const data=routingData(parsed.data,"test-version"), net=prepareNetwork([data]);
  const t=data.trips.find(t=>t.times.length>5 && t.times[0][4] && t.times.at(-1)[5]);
  const s=data.services.find(s=>s.id===t.serviceId), date=s.addedDates[0] || s.validFrom;
  const q={...query(t.times[0][0],t.times.at(-1)[0]),date,departureSeconds:0};
  // Choose a real operating day without assuming holidays/weekends.
  for(let i=0;i<8 && !require("./transport_router").operates(s,q.date);i++) q.date=new Date(Date.parse(q.date)+86400000).toISOString().slice(0,10);
  const start=performance.now(), found=searchJourneys(net,q);
  assert.ok(found.journeys.length>0);assert.ok(found.journeys.every(j=>j.legs.length<=4));
  assert.ok(found.stats.scannedStopTimes<=found.stats.tripInstances*1000*4);
  console.log(JSON.stringify({realRoutingMs:Math.round(performance.now()-start),...found.stats,resultCount:found.journeys.length}));
});

test("inactive/missing stops cannot be transfer or destination platforms",()=>{
  const trips=[trip("t0","p0","a",28800,29400),trip("t1","a","p6",30000,30600)];
  assert.equal(searchJourneys(network(trips,[stop("p0"),{...stop("a"),isActive:false},stop("p6")]),query()).journeys.length,0);
  assert.equal(searchJourneys(network([trip("t0","p0","p6",28800,29400)],[stop("p0")]),query()).journeys.length,0);
});

test("timetable mode keeps later departure buckets for local filtering in one response",()=>{
  const ts=[trip("early","p0","p6",28800,30000),trip("later","p0","p6",32400,33600),trip("late","p0","p6",36000,37200)];
  const net=network(ts,[stop("p0"),stop("p6")]);
  const found=searchJourneys(net,{...query(),timetable:true}).journeys;
  assert.equal(found.length,3);assert.deepEqual(found.filter(j=>j.departureFromSpotSeconds>=32400).map(j=>j.legs[0].tripId),["later","late"]);
  assert.equal(searchJourneys(net,query()).journeys.length,1);
  assert.throws(()=>validateQuery({...query(),timetable:"true"}));
});
test("timetable pool includes direct and transferred options and honors first-departure 24h window",()=>{
  const ts=[trip("direct","p0","p6",28800,33000),trip("a","p0","middle",32400,32700),trip("b","middle","p6",33000,33600),trip("nextday","p0","p6",120000,121000)];
  const net=network(ts,[stop("p0"),stop("middle"),stop("p6")]);
  const found=searchJourneys(net,{...query(),timetable:true}).journeys;
  assert.deepEqual(found.map(j=>j.transferCount),[0,1]);assert.ok(found.every(j=>j.departureSeconds<115200));
});

test("shared exact stop returns walking only before scanning a looping trip, without invented timing",()=>{
  const t={...trip("loop","a","a",28800,30600),times:[time("a",1,28800),time("remote",2,29400),time("a",3,30600)]};
  const net=network([t],[stop("a"),stop("remote")]);
  for (const timetable of [false,true]) {
    const result=searchJourneys(net,{...query("a","a"),timetable});
    assert.equal(result.walkingOnly,true);assert.deepEqual(result.journeys,[]);
    assert.equal(result.stats.scannedStopTimes,0);assert.equal(result.stats.tripInstances,0);
    assert.equal(result.arrivalSeconds,undefined);assert.equal(result.walkingMinutes,undefined);
  }
});

test("paid express metadata reaches journeys while slower ordinary alternatives remain available", () => {
  const net = prepareNetwork([{
    stops: [stop('p0'), stop('p6')], services: [service],
    routes: [{id:'r',name:'普通'}, {id:'paid',name:'特急',trainType:'limited_express',requiresLimitedExpress:true}],
    trips: [trip('local','p0','p6',28800,32000), {...trip('express','p0','p6',28900,30000),routeId:'paid'}],
  }]);
  const journeys = searchJourneys(net, {...query(), timetable:true}).journeys;
  assert.ok(journeys.some(j => j.legs[0].tripId === 'local' && !j.legs[0].requiresLimitedExpress));
  assert.ok(journeys.some(j => j.legs[0].tripId === 'express' && j.legs[0].requiresLimitedExpress));
});

 test("manual connections need no verification status but inactive and sample connections stay excluded", () => {
  const stops = [stop("p0"), stop("a"), stop("b"), stop("p6")];
  const trips = [trip("first", "p0", "a", 28800, 29400), trip("next", "b", "p6", 30000, 30600)];
  const rule = edge("a", "b", 300, {sourceType:"manual"});
  assert.equal(searchJourneys(network(trips, stops, [rule]), query()).journeys.length, 1);
  for (const extra of [{isActive:false}, {sourceType:"sample"}, {verificationStatus:"sample"}]) {
    assert.equal(searchJourneys(network(trips, stops, [{...rule, ...extra}]), query()).journeys.length, 0);
  }
});
