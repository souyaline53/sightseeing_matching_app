"use strict";
// Round-based earliest arrival: round k boards exactly k vehicles; at most 4 rounds (3 transfers).
// Seconds are relative to the requested civil day, not UTC instants or rounded minutes.
const { MAX_TRANSFERS, buildSameNameConnections } = require("./transport_nearby_stops");
const DAY = 86400, HORIZON = 2 * DAY;
function validDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}
function validateQuery(q) {
  if (!q || !validDate(q.date) || !Number.isInteger(q.departureSeconds) || q.departureSeconds < 0 || q.departureSeconds >= DAY ||
      !Number.isInteger(q.maxTransfers) || q.maxTransfers < 0 || q.maxTransfers > MAX_TRANSFERS ||
      !Number.isInteger(q.minimumTransferSeconds) || q.minimumTransferSeconds < 180 || q.minimumTransferSeconds > 3600)
    throw Error("旅行日・出発時刻・乗換上限（0〜3回）・乗換余裕（3〜60分）を確認してください");
  for (const field of ["from", "to"]) {
    if (!Array.isArray(q[field]) || !q[field].length || q[field].length > 30) throw Error("最寄り停留所は1〜30件指定してください");
    for (const s of q[field]) if (typeof s.stopId !== "string" || !/^[A-Za-z0-9_~-]{1,1400}$/.test(s.stopId) ||
      (s.walkingMinutes != null && (!Number.isInteger(s.walkingMinutes) || s.walkingMinutes < 0 || s.walkingMinutes > 1440))) throw Error("最寄り停留所・徒歩時間が不正です");
  }
  if (q.timetable != null && typeof q.timetable !== "boolean") throw Error("検索形式が不正です");
  return q;
}
function operates(service, day) {
  if (!service || service.isActive === false) return false;
  if (service.removedDates?.includes(day)) return false;
  if (service.addedDates?.includes(day)) return true;
  const weekday = new Date(day).getUTCDay() || 7;
  return service.validFrom <= day && day <= service.validTo && service.weekdays?.includes(weekday);
}
function prepareNetwork(parts) {
  const stops = new Map(), routes = new Map(), services = new Map(), trips = [], transfers = [];
  const source = new Map(), sameNameConnections = [];
  for (const [index, part] of parts.entries()) {
    for (const s of part.stops || []) if (s.isActive !== false) { stops.set(s.id, s); source.set(s.id, index); }
    sameNameConnections.push(...(part.sameNameConnections ?? buildSameNameConnections(part.stops || [])));
    for (const r of part.routes || []) if (r.isActive !== false) routes.set(r.id, r);
    for (const s of part.services || []) services.set(s.id, s);
    for (const t of part.trips || []) if (t.isActive !== false && !t.frequencyBased && routes.has(t.routeId)) {
      let firstTime = Infinity, lastTime = -Infinity;
      for (const time of t.times) for (const value of [time[2], time[3]]) if (Number.isInteger(value)) {
        firstTime = Math.min(firstTime, value); lastTime = Math.max(lastTime, value);
      }
      trips.push({ ...t, firstTime, lastTime });
    }
    transfers.push(...(part.transfers || []).filter((r) => r.isActive !== false && r.sourceType !== "sample" && r.verificationStatus !== "sample"));
  }
  // A rule on a parent station applies to its platforms, but parent/name alone adds no edge.
  const children = new Map();
  for (const s of stops.values()) if (s.parentStationId) {
    if (!children.has(s.parentStationId)) children.set(s.parentStationId, []);
    children.get(s.parentStationId).push(s.id);
  }
  const rules = new Map(), incoming = new Map(), contextual = new Set(), nearby = new Map();
  // Intra-feed pairs are built on import; cross-feed/manual pairs only on cache rebuild.
  sameNameConnections.push(...buildSameNameConnections([...stops.values()], (a, b) => source.get(a.id) !== source.get(b.id)));
  for (const [a, b, distance, seconds] of sameNameConnections) {
    if (!stops.has(a) || !stops.has(b)) continue;
    for (const [from, to] of [[a, b], [b, a]]) {
      if (!nearby.has(from)) nearby.set(from, new Map());
      nearby.get(from).set(to, { distanceMeters: distance, requiredSeconds: seconds, source: "nearby_same_name", estimated: true });
      if (!incoming.has(to)) incoming.set(to, new Set());
      incoming.get(to).add(from);
    }
  }
  for (const rule of transfers) {
    const from = children.get(rule.fromStopId) || [rule.fromStopId], to = children.get(rule.toStopId) || [rule.toStopId];
    for (const a of from) for (const b of to) {
      if (!stops.has(a) || !stops.has(b)) continue;
      const k = `${a}\n${b}`;
      if (!rules.has(k)) rules.set(k, []);
      rules.get(k).push(rule);
      if (!incoming.has(b)) incoming.set(b, new Set());
      incoming.get(b).add(a);
      if (rule.fromRouteId || rule.fromTripId || rule.toRouteId || rule.toTripId) contextual.add(a);
    }
  }
  const boardingSources = new Map([...stops.keys()].map((id) => [id, [id, ...[...(incoming.get(id) || [])].filter((from) => from !== id)]]));
  return { stops, routes, services, trips, rules, incoming, contextual, nearby, boardingSources };
}
function connection(net, label, target, next, buffer) {
  if (!label.trip) return label.stopId === target ? { requiredSeconds: 0, source: "access" } : null;
  if (label.instance === next.instance) return null;
  const nearby = net.nearby.get(label.stopId)?.get(target);
  const matches = (net.rules.get(`${label.stopId}\n${target}`) || []).filter((r) =>
    (!r.fromTripId || r.fromTripId === label.trip.id) && (!r.toTripId || r.toTripId === next.trip.id) &&
    (!r.fromRouteId || r.fromRouteId === label.trip.routeId) && (!r.toRouteId || r.toRouteId === next.trip.routeId));
  // GTFS specificity: both trips > one trip+other route > one trip > both routes > one route > stop-only.
  const specificity = (r) => r.fromTripId && r.toTripId ? 6 :
    (r.fromTripId && r.toRouteId) || (r.toTripId && r.fromRouteId) ? 5 :
      r.fromTripId || r.toTripId ? 4 : r.fromRouteId && r.toRouteId ? 3 : r.fromRouteId || r.toRouteId ? 2 : 1;
  if (matches.length) {
    const rank = Math.max(...matches.map(specificity)), best = matches.filter((r) => specificity(r) === rank);
    if (best.some((r) => [3, 4, 5].includes(r.transferType))) return null;
    const times = best.map((r) => r.minTransferSeconds);
    // Without a declared movement time, a different platform is not a verified walking link.
    if (label.stopId !== target && times.some((s) => !Number.isInteger(s)))
      return nearby ? { ...nearby, requiredSeconds: Math.max(buffer, nearby.requiredSeconds) } : null;
    return { requiredSeconds: Math.max(buffer, ...times.map((s) => s ?? 0)), source: best.some((r) => r.sourceType === "gtfs") ? "gtfs" : "manual", ruleIds: best.map((r) => r.id) };
  }
  return label.stopId === target ? { requiredSeconds: buffer, source: "same_stop" } :
    nearby ? { ...nearby, requiredSeconds: Math.max(buffer, nearby.requiredSeconds) } : null;
}
function expandAccessStops(net, accessStops, before) {
  const options = new Map();
  const add = (option) => {
    const old = options.get(option.stopId);
    if (!old || option.walkingSeconds < old.walkingSeconds ||
      (option.walkingSeconds === old.walkingSeconds && old.accessConnection?.estimated && !option.accessConnection?.estimated)) options.set(option.stopId, option);
  };
  for (const access of accessStops) {
    if (!net.stops.has(access.stopId)) continue;
    add({ ...access, walkingSeconds: (access.walkingMinutes ?? 0) * 60 });
    for (const [peer, edge] of net.nearby.get(access.stopId) || []) {
      const from = before ? access.stopId : peer, to = before ? peer : access.stopId;
      // A generic manual/GTFS prohibition also prevents automatic endpoint expansion.
      const rules = (net.rules.get(`${from}\n${to}`) || []).filter((r) => !r.fromTripId && !r.toTripId && !r.fromRouteId && !r.toRouteId);
      if (rules.some((r) => [3, 4, 5].includes(r.transferType))) continue;
      const confirmed = rules.length && rules.every((r) => Number.isInteger(r.minTransferSeconds));
      const seconds = confirmed ? Math.max(...rules.map((r) => r.minTransferSeconds)) : edge.requiredSeconds;
      const accessConnection = { fromStopId: from, toStopId: to, distanceMeters: edge.distanceMeters,
        requiredSeconds: seconds, source: confirmed ? "confirmed" : edge.source, estimated: !confirmed, ruleIds: confirmed ? rules.map((r) => r.id) : [] };
      add({ ...access, stopId: peer, registeredStopId: access.stopId, accessConnection,
        walkingSeconds: (access.walkingMinutes ?? 0) * 60 + seconds,
        walkingMinutes: access.walkingMinutes == null ? null : access.walkingMinutes + Math.ceil(seconds / 60) });
    }
  }
  return options;
}
function tripInstances(net, q) {
  const instances = [], start = q.departureSeconds, end = start + HORIZON;
  const base = Date.parse(q.date), dates = new Map(), serviceDays = new Map();
  for (const trip of net.trips) {
    const min = trip.firstTime, max = trip.lastTime;
    if (!Number.isFinite(min)) continue;
    // Include previous service days (25:xx etc.), and the next civil days in the window.
    for (let day = Math.ceil((start - max) / DAY); day <= Math.floor((end - min) / DAY); day++) {
      if (!dates.has(day)) dates.set(day, new Date(base + day * DAY * 1000).toISOString().slice(0, 10));
      const serviceDate = dates.get(day), key = `${trip.serviceId}@${serviceDate}`;
      if (!serviceDays.has(key)) serviceDays.set(key, operates(net.services.get(trip.serviceId), serviceDate));
      if (!serviceDays.get(key)) continue;
      instances.push({ trip, offset: day * DAY, serviceDate, instance: `${trip.id}@${serviceDate}` });
      if (instances.length > 100000) throw Error("検索対象の便が多すぎます。検索範囲を見直してください");
    }
  }
  return instances;
}
function sharesWalkingStop(net, q) {
  for (const from of q.from) for (const to of q.to) {
    if (from.stopId === to.stopId) return true;
    if (!net.nearby.get(from.stopId)?.has(to.stopId)) continue;
    const rules = (net.rules.get(`${from.stopId}\n${to.stopId}`) || []).filter((r) => !r.fromTripId && !r.toTripId && !r.fromRouteId && !r.toRouteId);
    if (!rules.some((r) => [3, 4, 5].includes(r.transferType))) return true;
  }
  return false;
}
function searchJourneys(net, input) {
  const result = searchJourneyOptions(net, input);
  // Preserve ordinary alternatives even when a faster paid train dominates the timetable.
  if (!input.timetable || result.walkingOnly) return result;
  const ordinaryTrips = net.trips.filter((t) => {
    const route = net.routes.get(t.routeId);
    return route?.trainType !== "limited_express" && !route?.requiresLimitedExpress;
  });
  if (ordinaryTrips.length === net.trips.length) return result;
  const ordinary = searchJourneyOptions({ ...net, trips: ordinaryTrips }, input);
  result.journeys = [...new Map([...result.journeys, ...ordinary.journeys].map((j) => [j.id, j])).values()]
    .sort((a, b) => a.arrivalSeconds - b.arrivalSeconds || a.transferCount - b.transferCount);
  result.stats.scannedStopTimes += ordinary.stats.scannedStopTimes;
  return result;
}
function searchJourneyOptions(net, input) {
  const q = validateQuery(input), end = q.departureSeconds + HORIZON;
  if (sharesWalkingStop(net, q)) return { walkingOnly: true, journeys: [], warnings: [], stats: { tripInstances: 0, scannedStopTimes: 0, maxTransfers: q.maxTransfers } };
  const instances = tripInstances(net, q);
  const destinations = expandAccessStops(net, q.to, false);
  let previous = new Map();
  function add(map, label) {
    if (!map.has(label.stopId)) map.set(label.stopId, new Map());
    const labels = map.get(label.stopId), context = net.contextual.has(label.stopId) ? label.instance : "*", key = q.timetable ? `${label.bucket ?? "start"}/${context}` : context;
    if (!labels.has(key) || label.time < labels.get(key).time) labels.set(key, label);
  }
  for (const origin of expandAccessStops(net, q.from, true).values()) add(previous, { stopId: origin.stopId, time: q.departureSeconds + origin.walkingSeconds, origin });
  const results = [];
  let bestArrival = Infinity, scannedStopTimes = 0;
  const bucketArrivals = new Map();
  for (let round = 1; round <= q.maxTransfers + 1 && previous.size; round++) {
    const current = new Map();
    for (const instance of instances) {
      let board = null;
      const boards = new Map();
      const { trip, offset } = instance;
      for (const time of trip.times) {
        scannedStopTimes++;
        const [stopId, sequence, arrival, departure, pickup, dropoff] = time;
        if (!net.stops.has(stopId)) continue;
        const riding = q.timetable ? boards.values() : board ? [board] : [];
        for (const ridingBoard of riding) {
          if (dropoff && arrival != null && sequence > ridingBoard.time[1] && arrival + offset >= ridingBoard.time[3] + offset && arrival + offset <= end) {
            add(current, { stopId, time: arrival + offset, trip, instance: instance.instance,
              parent: ridingBoard.label, board: ridingBoard.time, alight: time, serviceDate: instance.serviceDate, offset,
              bucket: ridingBoard.bucket, connection: ridingBoard.connection, origin: ridingBoard.label.origin });
          }
        }
        if ((!q.timetable && board) || !pickup || departure == null || departure + offset < q.departureSeconds || departure + offset > end) continue;
        let best = null;
        for (const from of net.boardingSources.get(stopId)) for (const label of previous.get(from)?.values() || []) {
          if (q.timetable && !label.trip && departure + offset >= q.departureSeconds + DAY) continue;
          const bucket = label.trip ? label.bucket : Math.floor((departure + offset) / 3600);
          if (q.timetable && boards.has(bucket)) continue;
          const edge = connection(net, label, stopId, instance, q.minimumTransferSeconds);
          if (!edge || label.time + edge.requiredSeconds > departure + offset) continue;
          const candidate = { label, connection: edge, time, bucket };
          if (q.timetable) boards.set(bucket, candidate);
          else if (!best || label.time + edge.requiredSeconds < best.label.time + best.connection.requiredSeconds) best = candidate;
        }
        if (best) board = best;
      }
    }
    // A Pareto frontier by arrival and number of boardings, including endpoint walks.
    let best = null;
    const bestBuckets = new Map();
    for (const [id, destination] of destinations) for (const label of current.get(id)?.values() || []) {
      const arrival = label.time + destination.walkingSeconds;
      if (arrival > end) continue;
      if (q.timetable) {
        if (!bestBuckets.has(label.bucket) || arrival < bestBuckets.get(label.bucket).arrival)
          bestBuckets.set(label.bucket, { label, destination, arrival });
      } else if (!best || arrival < best.arrival) best = { label, destination, arrival };
    }
    if (q.timetable) {
      for (const [bucket, candidate] of bestBuckets) {
        if (!bucketArrivals.has(bucket) || candidate.arrival < bucketArrivals.get(bucket).arrival) {
          bucketArrivals.set(bucket, { arrival: candidate.arrival, journey: serialize(net, q, candidate, round) });
        }
      }
    } else if (best && best.arrival < bestArrival) {
      bestArrival = best.arrival;
      results.push(serialize(net, q, best, round));
    }
    previous = current;
  }
  if (q.timetable) results.push(...[...bucketArrivals.values()].map((x) => x.journey));
  results.sort((a, b) => a.arrivalSeconds - b.arrivalSeconds || a.transferCount - b.transferCount);
  return { journeys: results, stats: { tripInstances: instances.length, scannedStopTimes, maxTransfers: q.maxTransfers },
    warnings: ["同名で500m以内の停留所を共通の候補に含めます。別乗り場への自動接続は直線距離による徒歩推定で、道路経路は未確認です。", "出発時刻は前の場所での滞在を終え、徒歩移動を開始できる時刻として指定してください。", "徒歩時間が未登録の経路は時刻表の参考候補です。到達できることは未確認です。"] };
}
function serialize(net, q, result, round) {
  const labels = [];
  for (let label = result.label; label.trip; label = label.parent) labels.push(label);
  labels.reverse();
  const legs = labels.map((l) => ({ tripId: l.trip.id, routeId: l.trip.routeId, routeName: net.routes.get(l.trip.routeId)?.name || l.trip.routeId,
    trainType: net.routes.get(l.trip.routeId)?.trainType || null,
    requiresLimitedExpress: net.routes.get(l.trip.routeId)?.requiresLimitedExpress === true,
    feedId: l.trip.feedId ?? null, versionId: l.trip.versionId ?? null, serviceDate: l.serviceDate, headsign: l.trip.headsign || "",
    boardingStopId: l.board[0], boardingStopName: net.stops.get(l.board[0])?.name || l.board[0], boardingPlatformCode: net.stops.get(l.board[0])?.platformCode || null,
    alightingStopId: l.alight[0], alightingStopName: net.stops.get(l.alight[0])?.name || l.alight[0], alightingPlatformCode: net.stops.get(l.alight[0])?.platformCode || null,
    boardingSequence: l.board[1], alightingSequence: l.alight[1], departureSeconds: l.board[3] + l.offset, arrivalSeconds: l.alight[2] + l.offset,
    fareYen: null,
  }));
  const transfers = labels.slice(1).map((l, i) => ({ fromStopId: legs[i].alightingStopId, toStopId: l.board[0],
    requiredSeconds: l.connection.requiredSeconds, availableSeconds: legs[i + 1].departureSeconds - legs[i].arrivalSeconds,
    source: l.connection.source, estimated: l.connection.estimated === true, ...(l.connection.distanceMeters == null ? {} : { distanceMeters: l.connection.distanceMeters }), ruleIds: l.connection.ruleIds || [] }));
  const origin = result.label.origin, destination = result.destination;
  const usesEstimatedWalking = origin.accessConnection?.estimated === true || destination.accessConnection?.estimated === true || labels.some((l) => l.connection.estimated === true);
  return { id: legs.map((l) => `${l.tripId}@${l.serviceDate}:${l.boardingSequence}-${l.alightingSequence}:${l.versionId}`).join("/"),
    legs, transfers, transferCount: round - 1, queryDate: q.date, departureSeconds: legs[0].departureSeconds, arrivalSeconds: result.arrival,
    walkingMinutesBefore: origin.walkingMinutes ?? null, walkingMinutesAfter: destination.walkingMinutes ?? null,
    verificationStatus: usesEstimatedWalking || origin.walkingMinutes == null || destination.walkingMinutes == null ? "needsReview" : labels.every((l) => l.trip.verificationStatus === "verified") ? "verified" : "unverified",
    usesEstimatedWalking,
    ...(origin.accessConnection ? { accessBefore: origin.accessConnection } : {}),
    ...(destination.accessConnection ? { accessAfter: destination.accessConnection } : {}),
    departureFromSpotSeconds: legs[0].departureSeconds - origin.walkingSeconds,
    timetableChecked: true,
    requestedDepartureSeconds: q.departureSeconds, minimumTransferSeconds: q.minimumTransferSeconds };
}
module.exports = { validateQuery, validDate, operates, prepareNetwork, searchJourneys };
