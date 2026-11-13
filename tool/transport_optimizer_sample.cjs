// Offline fixture only. node tool/transport_optimizer_sample.cjs > /tmp/transport_optimizer_fixture.json
const { fixture } = require('../functions/test_support/gtfs_fixture');
const { parseFiles } = require('../functions/transport_bundle');
const { routingData } = require('../functions/transport_routing_bundle');
const { prepareNetwork } = require('../functions/transport_router');
const { buildPayload } = require('../functions/transport_optimizer');
const parsed = parseFiles(fixture(), 'sample');
const network = prepareNetwork([routingData(parsed.data, 'fixture-v1')]);
network.routes = new Map(parsed.data.routes.map((r) => [r.id, r]));
network.agencies = new Map(parsed.data.agencies.map((r) => [r.id, r]));
const ids = [...network.stops.keys()];
const place = (id, stopId) => ({ id, name: id, accessStops: [{ stopId, walkingMinutes: 5, verificationStatus: 'verified' }] });
console.log(JSON.stringify(buildPayload(network, { date: '2026-01-02', departureSeconds: 0, deadlineSeconds: 7200,
  origin: place('origin', ids[0]), destination: place('destination', ids[2]),
  visits: [{ ...place('visit', ids[1]), staySeconds: 600, opening: { status: 'unknown', windows: [] } }],
  modes: ['rail', 'bus', 'walk'], preference: 'travel_time', minimumTransferSeconds: 180 }).payload, null, 2));
