'use strict';
const { transportLimits } = require('./transport_limits');
const { PreparationError } = require('./transport_optimizer');
const { createHash } = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');
const digest = (v) => createHash('sha256').update(JSON.stringify(v)).digest('hex');
function metrics(json) {
  let characters = 0;
  for (const _ of json) characters++;
  return { characters, utf16Units: json.length, bytes: Buffer.byteLength(json) };
}
function serialize(payload, { maxCharacters, maxBytes } = transportLimits()) {
  const defaults = transportLimits();
  maxCharacters ??= defaults.maxCharacters; maxBytes ??= defaults.maxBytes;
  if (![maxCharacters, maxBytes].every((v) => Number.isSafeInteger(v) && v > 0)) throw new PreparationError('failed-precondition', '交通JSONの容量設定が不正です');
  const json = JSON.stringify(payload), size = metrics(json);
  // UTF-16 is also checked conservatively for runtimes which count surrogate pairs twice.
  if (size.characters > maxCharacters || size.utf16Units > maxCharacters || size.bytes > maxBytes) {
    const error = new PreparationError('resource-exhausted', `交通JSON容量超過: ${size.characters}文字 / ${size.utf16Units} UTF-16 / ${size.bytes} bytes。上限${maxCharacters}文字・${maxBytes} bytes。データは切り捨てていません`);
    error.details = { reason: 'transport-payload-too-large', difyRequestStarted: false, ...size, maxCharacters, maxBytes };
    throw error;
  }
  return { payload, json, ...size };
}
function unique(rows, key) {
  const seen = new Map();
  return rows.filter((r) => {
    const k = key(r), old = seen.get(k);
    if (old != null && !isDeepStrictEqual(old, r)) throw new PreparationError('data-loss', '同一IDの交通レコードが競合しています');
    if (old != null) return false;
    seen.set(k, r); return true;
  });
}
function deduplicate(payload) {
  // Preserve field values, optional nulls, warnings and array order. Without the Python
  // consumer, a null field cannot safely be assumed equivalent to an absent field.
  const p = { ...payload };
  for (const field of ['stops', 'routes', 'agencies', 'instances']) p[field] = unique(p[field], (r) => r.id);
  p.segments = unique(p.segments, (s) => JSON.stringify([s.instanceId, s.fromSequence, s.toSequence]));
  p.transfers = unique(p.transfers, (s) => JSON.stringify(s));
  return p;
}
function connectedNetwork(network, q) {
  // Static undirected over-approximation, with no geographic bounding box. A legal
  // path cannot leave the union of components containing the input access stops.
  const links = new Map();
  const connect = (a, b) => { if (!links.has(a)) links.set(a, new Set()); if (!links.has(b)) links.set(b, new Set()); links.get(a).add(b); links.get(b).add(a); };
  for (const trip of network.trips) {
    for (let i = 1; i < trip.times.length; i++) connect(trip.times[i - 1][0], trip.times[i][0]);
  }
  for (const pair of network.rules.keys()) { const [a, b] = pair.split('\n'); connect(a, b); }
  const reached = new Set(), queue = [q.origin, ...q.visits, q.destination].flatMap((p) => p.accessStops.map((a) => a.stopId));
  for (let i = 0; i < queue.length; i++) {
    const id = queue[i]; if (reached.has(id)) continue; reached.add(id);
    for (const to of links.get(id) || []) if (!reached.has(to)) queue.push(to);
  }
  return { ...network, trips: network.trips.filter((t) => t.times.some((s) => reached.has(s[0]))) };
}
function pruneUnreachable(payload, { includeVisits = false } = {}) {
  const p = deduplicate(payload), adjacency = new Map(), reverse = new Map();
  const add = (map, a, b) => { if (!map.has(a)) map.set(a, new Set()); map.get(a).add(b); };
  // Relax all explicit transfers to zero-cost edges, even prohibited/unusable/scoped rules.
  // Also relax access walks, pickup/dropoff, transfer buffers and opening hours.
  // Optional visit layers enforce only the explicitly requested stay durations.
  // This over-approximates legal paths and may retain extra edges.
  for (const t of p.transfers) { add(adjacency, t.fromStopId, t.toStopId); add(reverse, t.toStopId, t.fromStopId); }
  for (const place of p.places) for (const a of place.accessStops) for (const b of place.accessStops) {
    add(adjacency, a.stopId, b.stopId); add(reverse, b.stopId, a.stopId);
  }
  const propagate = (times, start, value, graph, earlier) => {
    const queue = [[start, value]];
    for (let i = 0; i < queue.length; i++) {
      const [id, time] = queue[i], previous = times.get(id);
      if (previous != null && (earlier ? previous <= time : previous >= time)) continue;
      times.set(id, time);
      for (const target of graph.get(id) || []) queue.push([target, time]);
    }
  };
  // Optional visit-mask layers retain only paths which can also complete every
  // mandatory stay. All visit orders remain possible. Walks, buffers, restrictions
  // and opening windows are still relaxed, so every legal path is represented.
  const visits = includeVisits ? p.places.filter(v => v.role === 'visit') : [];
  if (visits.length > 3) throw new PreparationError('invalid-argument', '訪問先は最大3件です');
  const layerCount = 1 << visits.length;
  const earliest = Array.from({length: layerCount}, () => new Map());
  const latest = Array.from({length: layerCount}, () => new Map());
  for (const a of p.places.find(v => v.role === 'origin').accessStops) propagate(earliest[0], a.stopId, p.departureSeconds, adjacency, true);
  for (const a of p.places.find(v => v.role === 'destination').accessStops) propagate(latest[layerCount - 1], a.stopId, p.deadlineSeconds, reverse, false);
  // Fixed point also handles equal-time zero-duration chains in either input order.
  const forward = p.segments.slice().sort((a, b) => a.departureSeconds - b.departureSeconds);
  const backward = p.segments.slice().sort((a, b) => b.arrivalSeconds - a.arrivalSeconds);
  for (let mask = 0; mask < layerCount; mask++) {
    let changed;
    do {
      changed = false;
      for (const s of forward) if ((earliest[mask].get(s.fromStopId) ?? Infinity) <= s.departureSeconds && (earliest[mask].get(s.toStopId) ?? Infinity) > s.arrivalSeconds) {
        propagate(earliest[mask], s.toStopId, s.arrivalSeconds, adjacency, true); changed = true;
      }
    } while (changed);
    visits.forEach((place, bit) => {
      if (mask & (1 << bit)) return;
      const time = Math.min(...place.accessStops.map(a => earliest[mask].get(a.stopId) ?? Infinity)) + place.staySeconds;
      if (!Number.isFinite(time)) return;
      for (const access of place.accessStops) propagate(earliest[mask | (1 << bit)], access.stopId, time, adjacency, true);
    });
  }
  for (let mask = layerCount - 1; mask >= 0; mask--) {
    let changed;
    do {
      changed = false;
      for (const s of backward) if ((latest[mask].get(s.toStopId) ?? -Infinity) >= s.arrivalSeconds && (latest[mask].get(s.fromStopId) ?? -Infinity) < s.departureSeconds) {
        propagate(latest[mask], s.fromStopId, s.departureSeconds, reverse, false); changed = true;
      }
    } while (changed);
    visits.forEach((place, bit) => {
      if (!(mask & (1 << bit))) return;
      const time = Math.max(...place.accessStops.map(a => latest[mask].get(a.stopId) ?? -Infinity)) - place.staySeconds;
      if (!Number.isFinite(time)) return;
      for (const access of place.accessStops) propagate(latest[mask & ~(1 << bit)], access.stopId, time, reverse, false);
    });
  }
  p.segments = p.segments.filter(s => earliest.some((times, mask) =>
    (times.get(s.fromStopId) ?? Infinity) <= s.departureSeconds &&
    (latest[mask].get(s.toStopId) ?? -Infinity) >= s.arrivalSeconds));
  const ids = new Set(p.segments.map((s) => s.instanceId));
  p.instances = p.instances.filter((i) => ids.has(i.id));
  // Keep all metadata and transfer constraints, including references to trips no longer
  // boardable. Consumers may use them for diagnostics or rule specificity.
  return p;
}
class TransportPayloadCache {
  constructor({ maxBytes = 16 * 1024 * 1024, ttlMs = 300000, now = Date.now } = {}) {
    Object.assign(this, { maxBytes, ttlMs, now }); this.entries = new Map(); this.bytes = 0;
  }
  get(key) {
    const value = this.entries.get(key);
    if (!value) return null;
    if (value.expires <= this.now()) { this.entries.delete(key); this.bytes -= value.bytes; return null; }
    this.entries.delete(key); this.entries.set(key, value);
    return JSON.parse(value.json);
  }
  set(key, value) {
    const json = JSON.stringify(value), bytes = Buffer.byteLength(json);
    if (this.entries.has(key)) { this.bytes -= this.entries.get(key).bytes; this.entries.delete(key); }
    if (bytes > this.maxBytes) return;
    while (this.bytes + bytes > this.maxBytes && this.entries.size) { const first = this.entries.keys().next().value; this.bytes -= this.entries.get(first).bytes; this.entries.delete(first); }
    this.entries.set(key, { json, bytes, expires: this.now() + this.ttlMs }); this.bytes += bytes;
  }
}
function cacheKey(versionKey, q, pruning) {
  // No traveler names, coordinates, opening hours or preferences are cached. Stays
  // affect mandatory-visit pruning and must be included. Access IDs
  // affect relaxed connectivity; role and order are preserved to avoid aliasing endpoints.
  return digest([2, versionKey, q.date, q.departureSeconds, q.deadlineSeconds, q.modes, q.minimumTransferSeconds,
    [q.origin, ...q.visits, q.destination].map((p) => p.accessStops.map((a) => a.stopId)), q.visits.map(v => v.staySeconds), pruning]);
}
module.exports = { metrics, serialize, deduplicate, connectedNetwork, pruneUnreachable, TransportPayloadCache, cacheKey };
