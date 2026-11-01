"use strict";
const { createHash } = require("node:crypto");
const key = (feed, id) => `${feed}~${Buffer.from(id).toString("base64url")}`;
function csv(text, file) {
  const rows = [];
  let row = [],
    cell = "",
    quoted = false,
    closed = false,
    line = 1,
    rowLine = 1;
  text = text.replace(/^\uFEFF/, "");
  const finishCell = () => {
    row.push(cell);
    cell = "";
    closed = false;
  };
  const finishRow = () => {
    finishCell();
    if (row.some(Boolean)) rows.push({ cells: row, line: rowLine });
    row = [];
  };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell += c;
        if (c === "\n") line++;
      }
      continue;
    }
    if (c === ",") {
      finishCell();
      continue;
    }
    if (c === "\n" || c === "\r") {
      finishRow();
      if (c === "\r" && text[i + 1] === "\n") i++;
      line++;
      rowLine = line;
      continue;
    }
    if (closed)
      throw Error(`${file}:${line}: 閉じた引用符の後に文字があります`);
    if (c === '"') {
      if (cell) throw Error(`${file}:${line}: 引用符不正`);
      quoted = true;
    } else cell += c;
  }
  if (quoted) throw Error(`${file}:${line}: 引用符が閉じていません`);
  if (cell || row.length || closed) finishRow();
  const header = rows.shift()?.cells || [];
  if (new Set(header).size !== header.length)
    throw Error(`${file}: 重複ヘッダー`);
  return rows.map((r) => {
    if (r.cells.length !== header.length)
      throw Error(`${file}:${r.line}: 列数不一致`);
    return {
      ...Object.fromEntries(header.map((h, i) => [h, r.cells[i]])),
      _line: r.line,
    };
  });
}
function seconds(value) {
  if (!value) return null;
  if (!/^\d{2,}:([0-5]\d):([0-5]\d)$/.test(value))
    throw Error(`時刻不正: ${value}`);
  const [h, m, s] = value.split(":").map(Number);
  const total = h * 3600 + m * 60 + s;
  if (!Number.isSafeInteger(total)) throw Error("時刻の範囲超過");
  return total;
}
function date(value) {
  if (!/^\d{8}$/.test(value || "")) throw Error(`日付不正: ${value}`);
  const iso = `${value.slice(0, 4)}-${value.slice(4, 6)}-${value.slice(6)}`;
  if (new Date(iso).toISOString().slice(0, 10) !== iso)
    throw Error(`日付不正: ${value}`);
  return iso;
}
function parseGtfs(files, feedId) {
  if (!/^[a-zA-Z0-9_-]{1,60}$/.test(feedId))
    throw Error("feedIdは英数字・_・-の1〜60文字");
  const tables = {},
    warnings = [],
    errors = [];
  const known = [
    "agency",
    "agency_jp",
    "stops",
    "routes",
    "trips",
    "stop_times",
    "calendar",
    "calendar_dates",
    "fare_attributes",
    "fare_rules",
    "feed_info",
    "translations",
    "pass_attributes",
    "pass_rules",
    "frequencies",
    "transfers",
  ];
  for (const [file, content] of Object.entries(files)) {
    if (!known.includes(file.replace(/\.txt$/, ""))) {
      warnings.push(`${file}: 未対応。原本のみ保持します`);
      continue;
    }
    try {
      tables[file.replace(".txt", "")] = csv(content, file);
    } catch (e) {
      errors.push(e.message);
    }
  }
  for (const f of ["agency", "stops", "routes", "trips", "stop_times"])
    if (!tables[f]?.length) errors.push(`${f}.txt: 必須ファイルがないか空です`);
  if (!tables.calendar?.length && !tables.calendar_dates?.length)
    errors.push("calendar.txt または calendar_dates.txt が必要です");
  const requiredHeaders = {
    agency: ["agency_name", "agency_url", "agency_timezone"],
    stops: ["stop_id"],
    routes: ["route_id", "route_type"],
    trips: ["route_id", "service_id", "trip_id"],
    stop_times: ["trip_id", "stop_id", "stop_sequence"],
    calendar: [
      "service_id",
      "monday",
      "tuesday",
      "wednesday",
      "thursday",
      "friday",
      "saturday",
      "sunday",
      "start_date",
      "end_date",
    ],
    calendar_dates: ["service_id", "date", "exception_type"],
    fare_attributes: [
      "fare_id",
      "price",
      "currency_type",
      "payment_method",
      "transfers",
    ],
    fare_rules: ["fare_id"],
    feed_info: ["feed_publisher_name", "feed_publisher_url", "feed_lang"],
  };
  for (const [table, headers] of Object.entries(requiredHeaders))
    if (tables[table]?.length)
      for (const header of headers)
        if (!(header in tables[table][0]))
          errors.push(`${table}.txt:1: ${header} 列は必須です`);
  if (tables.translations?.length && !tables.feed_info?.length)
    errors.push("feed_info.txt: translations.txt がある場合は必須です");
  const data = {
    agencies: [],
    stops: [],
    routes: [],
    services: [],
    trips: [],
    fares: [],
    patterns: [],
    passes: [],
  };
  const ns = (id) => key(feedId, id);
  const base = { feedId, sourceType: "gtfs", verificationStatus: "unverified" };
  const maps = {};
  function each(file, fn) {
    for (const r of tables[file] || [])
      try {
        fn(r);
      } catch (e) {
        errors.push(`${file}.txt:${r._line}: ${e.message}`);
      }
  }
  function required(r, fields) {
    for (const f of fields) if (!r[f]) throw Error(`${f} は必須です`);
  }
  function unique(kind, raw, record) {
    if (!raw) throw Error(`${kind} ID未設定`);
    if (Buffer.byteLength(ns(raw)) > 1400) throw Error("IDが長すぎます");
    maps[kind] ||= new Map();
    if (maps[kind].has(raw)) throw Error(`ID重複: ${raw}`);
    maps[kind].set(raw, record);
    data[kind].push(record);
  }
  function ref(kind, raw) {
    if (!maps[kind]?.has(raw)) throw Error(`${kind} 参照先なし: ${raw}`);
    return ns(raw);
  }
  each("agency", (r) => {
    required(r, ["agency_name", "agency_url", "agency_timezone"]);
    new Intl.DateTimeFormat("en", { timeZone: r.agency_timezone });
    const url = new URL(r.agency_url);
    if (!["http:", "https:"].includes(url.protocol))
      throw Error("agency_url不正");
    const raw =
      r.agency_id || ((tables.agency || []).length === 1 ? "_default" : "");
    unique("agencies", raw, {
      ...base,
      id: ns(raw),
      agencyId: raw,
      name: r.agency_name,
      website: r.agency_url,
      timezone: r.agency_timezone,
      phone: r.agency_phone || null,
      email: r.agency_email || null,
    });
  });
  each("agency_jp", (r) => {
    const a = maps.agencies?.get(r.agency_id);
    if (!a) throw Error("agency_id参照先なし");
    a.jp = r;
    a.officialName = r.agency_official_name || a.name;
  });
  each("stops", (r) => {
    required(r, ["stop_id"]);
    const type = Number(r.location_type || 0);
    if (![0, 1, 2, 3, 4].includes(type)) throw Error("location_type不正");
    if ([2, 3, 4].includes(type) && !r.parent_station)
      throw Error("parent_station必須");
    if ([0, 1, 2].includes(type))
      required(r, ["stop_name", "stop_lat", "stop_lon"]);
    const lat = r.stop_lat ? Number(r.stop_lat) : null,
      lon = r.stop_lon ? Number(r.stop_lon) : null;
    if (
      (lat !== null && (!Number.isFinite(lat) || Math.abs(lat) > 90)) ||
      (lon !== null && (!Number.isFinite(lon) || Math.abs(lon) > 180))
    )
      throw Error("緯度経度不正");
    unique("stops", r.stop_id, {
      ...base,
      id: ns(r.stop_id),
      stopId: r.stop_id,
      name: r.stop_name,
      latitude: lat,
      longitude: lon,
      locationType: type,
      parentStationId: r.parent_station ? ns(r.parent_station) : null,
      platformCode: r.platform_code || null,
      zoneId: r.zone_id || null,
      routeIds: [],
    });
  });
  each("stops", (r) => {
    if (r.parent_station) ref("stops", r.parent_station);
  });
  each("routes", (r) => {
    required(r, ["route_id", "route_type"]);
    if (!r.route_short_name && !r.route_long_name) throw Error("路線名が必要");
    if (!/^\d+$/.test(r.route_type)) throw Error("route_type不正");
    const agency =
      r.agency_id ||
      (maps.agencies?.size === 1 ? [...maps.agencies.keys()][0] : "");
    unique("routes", r.route_id, {
      ...base,
      id: ns(r.route_id),
      routeId: r.route_id,
      agencyId: ref("agencies", agency),
      name: r.route_long_name || r.route_short_name,
      displayName: r.route_long_name || r.route_short_name,
      routeShortName: r.route_short_name,
      routeLongName: r.route_long_name,
      routeType: Number(r.route_type),
    });
  });
  each("calendar", (r) => {
    required(r, ["service_id", "start_date", "end_date"]);
    const days = [
      "monday",
      "tuesday",
      "wednesday",
      "thursday",
      "friday",
      "saturday",
      "sunday",
    ];
    for (const d of days)
      if (!["0", "1"].includes(r[d])) throw Error(`${d}不正`);
    const start = date(r.start_date),
      end = date(r.end_date);
    if (start > end) throw Error("運行期間不正");
    unique("services", r.service_id, {
      ...base,
      id: ns(r.service_id),
      serviceId: r.service_id,
      validFrom: start,
      validTo: end,
      startDate: start,
      endDate: end,
      weekdays: days.flatMap((d, i) => (r[d] === "1" ? [i + 1] : [])),
      addedDates: [],
      removedDates: [],
    });
  });
  const exceptions = new Set();
  each("calendar_dates", (r) => {
    required(r, ["service_id", "date", "exception_type"]);
    const d = date(r.date),
      k = `${r.service_id}/${d}`;
    if (exceptions.has(k)) throw Error("例外日重複");
    exceptions.add(k);
    if (!["1", "2"].includes(r.exception_type))
      throw Error("exception_type不正");
    if (!maps.services?.has(r.service_id))
      unique("services", r.service_id, {
        ...base,
        id: ns(r.service_id),
        serviceId: r.service_id,
        weekdays: [],
        addedDates: [],
        removedDates: [],
      });
    maps.services
      .get(r.service_id)
      [r.exception_type === "1" ? "addedDates" : "removedDates"].push(d);
  });
  each("trips", (r) => {
    required(r, ["trip_id", "route_id", "service_id"]);
    unique("trips", r.trip_id, {
      ...base,
      id: ns(r.trip_id),
      tripId: r.trip_id,
      routeId: ref("routes", r.route_id),
      serviceId: ref("services", r.service_id),
      headsign: r.trip_headsign || "",
      directionId: r.direction_id || null,
      stopTimes: [],
    });
  });
  each("stop_times", (r) => {
    required(r, ["trip_id", "stop_id", "stop_sequence"]);
    ref("trips", r.trip_id);
    ref("stops", r.stop_id);
    const a = seconds(r.arrival_time),
      d = seconds(r.departure_time),
      seq = Number(r.stop_sequence);
    if (!Number.isInteger(seq) || seq < 0) throw Error("stop_sequence不正");
    if ((r.timepoint || "1") === "1" && (a === null || d === null))
      throw Error("timepoint=1は到着・出発時刻が必須");
    const pickup = Number(r.pickup_type || 0),
      drop = Number(r.drop_off_type || 0);
    if (![0, 1, 2, 3].includes(pickup) || ![0, 1, 2, 3].includes(drop))
      throw Error("乗降区分不正");
    maps.trips.get(r.trip_id).stopTimes.push({
      stopId: ns(r.stop_id),
      sequence: seq,
      arrivalSeconds: a,
      departureSeconds: d,
      arrivalMinutes: a === null ? null : Math.floor(a / 60),
      departureMinutes: d === null ? null : Math.floor(d / 60),
      pickupType: pickup,
      dropOffType: drop,
      pickupAllowed: pickup === 0,
      dropoffAllowed: drop === 0,
      timepoint: Number(r.timepoint || 1),
    });
  });
  each("frequencies", (r) => {
    ref("trips", r.trip_id);
    maps.trips.get(r.trip_id).frequencyBased = true;
  });
  if (tables.frequencies?.length)
    warnings.push(
      "frequencies.txt: 頻度運行の展開は未対応。対象便は通常の発車時刻候補から除外",
    );
  // Explicit transfer edges only. A shared name/zone never creates a connection.
  if (tables.transfers?.length) data.transfers = [];
  const transferKeys = new Set();
  each("transfers", (r) => {
    required(r, ["transfer_type"]);
    if (!/^[0-5]$/.test(r.transfer_type)) throw Error("transfer_type不正");
    const type = Number(r.transfer_type);
    if ([4, 5].includes(type)) {
      if (r.from_trip_id) ref("trips", r.from_trip_id);
      if (r.to_trip_id) ref("trips", r.to_trip_id);
      warnings.push(`transfers.txt:${r._line}: 車内継続乗車は未対応。乗換接続には使用しません`);
      return;
    }
    required(r, ["from_stop_id", "to_stop_id"]);
    const record = { ...base, id: ns(`transfer-${r._line}`),
      fromStopId: ref("stops", r.from_stop_id), toStopId: ref("stops", r.to_stop_id),
      transferType: type, minTransferSeconds: null };
    for (const [column, field, kind] of [["from_route_id", "fromRouteId", "routes"], ["to_route_id", "toRouteId", "routes"], ["from_trip_id", "fromTripId", "trips"], ["to_trip_id", "toTripId", "trips"]])
      if (r[column]) record[field] = ref(kind, r[column]);
    if (r.min_transfer_time) {
      if (!/^\d+$/.test(r.min_transfer_time) || Number(r.min_transfer_time) > 86400) throw Error("min_transfer_time不正（0〜86400秒）");
      record.minTransferSeconds = Number(r.min_transfer_time);
    }
    if (type === 2 && record.minTransferSeconds == null) throw Error("transfer_type=2はmin_transfer_time必須");
    const k = JSON.stringify([record.fromStopId, record.toStopId, record.fromRouteId, record.toRouteId, record.fromTripId, record.toTripId]);
    if (transferKeys.has(k)) throw Error("乗換ルール重複");
    transferKeys.add(k);
    if ([0, 1].includes(type) && record.fromStopId !== record.toStopId && record.minTransferSeconds == null)
      warnings.push(`transfers.txt:${r._line}: 別乗り場への必要時間が不明のため乗換接続には使用しません`);
    data.transfers.push(record);
  });
  const patternMap = new Map();
  const stopsById = new Map(data.stops.map((s) => [s.id, s]));
  for (const t of data.trips) {
    t.stopTimes.sort((a, b) => a.sequence - b.sequence);
    let previous = -1;
    const seq = new Set();
    for (const s of t.stopTimes) {
      if (seq.has(s.sequence))
        errors.push(`stop_times.txt: ${t.tripId}: stop_sequence重複`);
      seq.add(s.sequence);
      const a = s.arrivalSeconds,
        d = s.departureSeconds;
      if ((a !== null && a < previous) || (a !== null && d !== null && d < a))
        errors.push(`stop_times.txt: ${t.tripId}: 時刻順序不正`);
      previous = d ?? a ?? previous;
    }
    if (t.stopTimes.length < 2)
      errors.push(`trips.txt: ${t.tripId}: 停留所が2件未満`);
    t.firstDepartureMinutes = t.stopTimes[0]?.departureMinutes ?? null;
    t.lastArrivalMinutes = t.stopTimes.at(-1)?.arrivalMinutes ?? null;
    t.firstStopId = t.stopTimes[0]?.stopId ?? null;
    t.lastStopId = t.stopTimes.at(-1)?.stopId ?? null;
    t.stopIds = [...new Set(t.stopTimes.map((s) => s.stopId))];
    for (const s of t.stopTimes) {
      const stop = stopsById.get(s.stopId);
      if (stop && !stop.routeIds.includes(t.routeId))
        stop.routeIds.push(t.routeId);
    }
    const hash = createHash("sha256")
      .update(
        JSON.stringify([
          t.routeId,
          t.directionId,
          t.stopTimes.map((s) => [s.stopId, s.pickupType, s.dropOffType]),
        ]),
      )
      .digest("hex");
    patternMap.set(hash, {
      ...base,
      id: hash,
      routeId: t.routeId,
      directionId: t.directionId,
      stopIds: t.stopTimes.map((s) => s.stopId),
    });
  }
  data.patterns = [...patternMap.values()];
  each("fare_attributes", (r) => {
    required(r, ["fare_id", "price", "currency_type", "payment_method"]);
    if (
      !["0", "1"].includes(r.payment_method) ||
      !["", "0", "1", "2"].includes(r.transfers ?? "")
    )
      throw Error("運賃支払い・乗換区分不正");
    const price = Number(r.price);
    if (!Number.isFinite(price) || price < 0) throw Error("運賃不正");
    unique("fares", r.fare_id, {
      ...base,
      id: ns(r.fare_id),
      fareId: r.fare_id,
      price,
      currency: r.currency_type,
      paymentMethod: r.payment_method,
      transfers: r.transfers,
      transferDuration: r.transfer_duration || null,
      rules: [],
    });
  });
  const zones = new Set(data.stops.map((s) => s.zoneId).filter(Boolean));
  each("fare_rules", (r) => {
    ref("fares", r.fare_id);
    if (r.route_id) ref("routes", r.route_id);
    for (const f of ["origin_id", "destination_id", "contains_id"])
      if (r[f] && !zones.has(r[f])) throw Error(`${f}ゾーン参照先なし`);
    maps.fares.get(r.fare_id).rules.push({
      routeId: r.route_id ? ns(r.route_id) : null,
      originId: r.origin_id || null,
      destinationId: r.destination_id || null,
      containsId: r.contains_id || null,
    });
  });
  for (const f of data.fares)
    f.originZones = [...new Set(f.rules.map((r) => r.originId || "*"))];
  each("pass_attributes", (r) =>
    data.passes.push({
      ...base,
      id: createHash("sha256").update(JSON.stringify(r)).digest("hex"),
      kind: "pass",
      attributes: r,
      rules: (tables.pass_rules || []).filter(
        (x) => Boolean(r.pass_id) && x.pass_id === r.pass_id,
      ),
    }),
  );
  if (
    (tables.pass_attributes || []).some((r) => !r.pass_id) ||
    (tables.pass_rules || []).some((r) => !r.pass_id)
  )
    warnings.push(
      "パス拡張のpass_idを解決できません。関連付けを推測せず原本に保持します",
    );
  if (tables.pass_rules?.length && !tables.pass_attributes?.length)
    warnings.push("pass_rules.txt: pass_attributes.txt がないため原本のみ保持");
  if (tables.translations?.length)
    warnings.push("translations.txt: 原本に保持。表示言語への反映は未対応");
  if (data.passes.length)
    warnings.push("定期券・パスは保存のみ。片道運賃検索から除外");
  const info = tables.feed_info?.[0] || {};
  const summary = {
    agencyNames: data.agencies.map((a) => a.name),
    routes: data.routes.length,
    stops: data.stops.length,
    trips: data.trips.length,
    stopTimes: (tables.stop_times || []).length,
    fares: data.fares.length,
    publisherName: info.feed_publisher_name || data.agencies[0]?.name || "",
    publisherUrl: info.feed_publisher_url || "",
    version: info.feed_version || "",
    timezone: data.agencies[0]?.timezone || "Asia/Tokyo",
    validFrom: info.feed_start_date
      ? date(info.feed_start_date)
      : data.services
          .map((s) => s.validFrom)
          .filter(Boolean)
          .sort()[0] || null,
    validTo: info.feed_end_date
      ? date(info.feed_end_date)
      : data.services
          .map((s) => s.validTo)
          .filter(Boolean)
          .sort()
          .at(-1) || null,
  };
  return { data, summary, errors: errors.slice(0, 200), warnings };
}
module.exports = { csv, seconds, date, parseGtfs, key };
