"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const { distanceMeters, estimatedWalkingSeconds, buildSameNameConnections } = require("./transport_nearby_stops");
const { prepareNetwork, searchJourneys } = require("./transport_router");
const meterLatitude = 180 / Math.PI / 6371000;
const stop = (id, meters, name = "同名") => ({id, name, latitude: meters * meterLatitude, longitude: 0});
const trip = (id, from, to, departure, arrival) => ({id,routeId:"r",serviceId:"s",verificationStatus:"verified",times:[[from,1,departure,departure,true,true],[to,2,arrival,arrival,true,true]]});
const q = (from = "start", to = "end") => ({date:"2026-06-01",departureSeconds:28800,maxTransfers:3,minimumTransferSeconds:180,from:[{stopId:from,walkingMinutes:0}],to:[{stopId:to,walkingMinutes:0}]});
const data = (stops, trips = [], transfers = []) => ({stops,trips,transfers,routes:[{id:"r",name:"路線"}],services:[{id:"s",validFrom:"2026-06-01",validTo:"2026-06-01",weekdays:[1]}]});
const stops = () => [stop("start", -10000,"出発"), stop("a",0),stop("b",300),stop("end",10000,"終点")];
const trips = () => [trip("t0","start","a",28800,29400),trip("t1","b","end",30000,30600)];
test("500m inclusive, 501m excluded, different/blank names and missing coordinates excluded",()=>{
  const rows=[stop("a",0),stop("b",500),stop("c",1001),stop("different",0,"別名"),{id:"missing",name:"同名"},stop("blank",0,""),stop("inactive",0,"同名")];rows.at(-1).isActive=false;
  const pairs=buildSameNameConnections(rows);
  assert.deepEqual(pairs.map(p=>p.slice(0,2)),[["a","b"]]);
  assert.ok(Math.abs(distanceMeters(rows[0],rows[1])-500)<0.0001);
  assert.ok(estimatedWalkingSeconds(500)>=600);
  assert.equal(distanceMeters({latitude:NaN,longitude:0},rows[0]),null);
  assert.equal(buildSameNameConnections([stop("x",0," ABC "),stop("y",10,"ABC")]).length,1);
});
test("nearby opposite platforms connect with walking time, unchanged IDs and unconfirmed status",()=>{
  const net=prepareNetwork([data(stops(),trips())]);
  const found=searchJourneys(net,q()).journeys[0];
  assert.equal(found.transferCount,1);assert.equal(found.legs[0].alightingStopId,"a");assert.equal(found.legs[1].boardingStopId,"b");
  assert.equal(found.transfers[0].source,"nearby_same_name");assert.equal(found.transfers[0].distanceMeters,300);
  assert.equal(found.verificationStatus,"needsReview");assert.equal(found.usesEstimatedWalking,true);
  assert.ok(found.transfers[0].requiredSeconds>180);
  const early=trips();early[1].times[0][2]=early[1].times[0][3]=29580;
  assert.equal(searchJourneys(prepareNetwork([data(stops(),early)]),q()).journeys.length,0);
});
test("separate feeds connect; far same names and disabled platforms do not",()=>{
  const all=stops(), ts=trips();
  const a=data([all[0],all[1]], [ts[0]]), b=data([all[2],all[3]],[ts[1]]);
  a.sameNameConnections=[];b.sameNameConnections=[];
  assert.equal(searchJourneys(prepareNetwork([a,b]),q()).journeys.length,1);
  b.stops[0]={...b.stops[0],latitude:501*meterLatitude};
  assert.equal(searchJourneys(prepareNetwork([a,b]),q()).journeys.length,0);
  b.stops[0]={...all[2],isActive:false};
  assert.equal(searchJourneys(prepareNetwork([a,b]),q()).journeys.length,0);
});
test("generic prohibition and specific trip prohibition override automatic edges; confirmed minimum wins",()=>{
  const rule={id:"no",sourceType:"gtfs",fromStopId:"a",toStopId:"b",transferType:3};
  for(const r of [rule,{...rule,fromTripId:"t0",toTripId:"t1"}])
    assert.equal(searchJourneys(prepareNetwork([data(stops(),trips(),[r])]),q()).journeys.length,0);
  const allowed={...rule,sourceType:"manual",verificationStatus:"verified",transferType:2,minTransferSeconds:300};
  const found=searchJourneys(prepareNetwork([data(stops(),trips(),[allowed])]),q()).journeys[0];
  assert.equal(found.transfers[0].requiredSeconds,300);assert.equal(found.usesEstimatedWalking,false);
});
test("endpoint expansion uses one nearby hop, includes walking and retains exact vehicle platforms",()=>{
  const rows=stops(), t=trip("one","b","end",30000,30600);
  const found=searchJourneys(prepareNetwork([data(rows,[t])]),q("a","end")).journeys[0];
  assert.equal(found.legs[0].boardingStopId,"b");assert.equal(found.accessBefore.fromStopId,"a");assert.equal(found.walkingMinutesBefore,9);
  assert.equal(found.verificationStatus,"needsReview");
  const reverse=searchJourneys(prepareNetwork([data(rows,[trip("one","start","a",28800,29400)])]),q("start","b")).journeys[0];
  assert.equal(reverse.accessAfter.fromStopId,"a");assert.equal(reverse.accessAfter.toStopId,"b");assert.equal(reverse.arrivalSeconds,29400+540);
});
test("500m chains do not silently merge distant stops or allow repeated walking hops",()=>{
  const rows=[stop("a",0),stop("b",400),stop("c",800),stop("end",10000,"終点")];
  const net=prepareNetwork([data(rows,[trip("t","c","end",32000,33000)])]);
  assert.ok(net.nearby.get("a").has("b"));assert.equal(net.nearby.get("a").has("c"),false);
  assert.equal(searchJourneys(net,q("a","end")).journeys.length,0);
  assert.equal(searchJourneys(net,q("b","end")).journeys.length,1);
});
test("endpoint prohibited movement cannot be bypassed by automatic expansion",()=>{
  const rule={id:"no",sourceType:"manual",verificationStatus:"verified",fromStopId:"a",toStopId:"b",transferType:3};
  const net=prepareNetwork([data(stops(),[trip("t","b","end",32000,33000)],[rule])]);
  assert.equal(searchJourneys(net,q("a","end")).journeys.length,0);
});
