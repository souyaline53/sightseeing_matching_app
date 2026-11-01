"use strict";
const { admin } = require("./transport_import");
const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, GeoPoint } = require("firebase-admin/firestore");
const allowed = [
  "transport_agencies",
  "transport_routes",
  "transport_stops",
  "transport_services",
  "transport_trips",
  "transport_fares",
];
async function saveManualTransport(request, db) {
  admin(request);
  const { collection, id, data, creating } = request.data || {};
  const fail = (message) => {
    throw new HttpsError("invalid-argument", message);
  };
  if (
    !allowed.includes(collection) ||
    !/^[A-Za-z0-9_-]{1,80}$/.test(id || "") ||
    !data ||
    Array.isArray(data) ||
    typeof data !== "object"
  )
    fail("入力形式不正");
  if (Buffer.byteLength(JSON.stringify(data)) > 700000)
    fail("ドキュメント容量超過");
  if (
    !["manual", "official", "sample", undefined, null].includes(data.sourceType)
  )
    fail("GTFSの直接編集はできません");
  if (collection === "transport_trips") {
    if (
      !Array.isArray(data.stopTimes) ||
      data.stopTimes.length < 2 ||
      data.stopTimes.length > 100
    )
      fail("停留所は2〜100件");
    data.stopTimes.sort((a, b) => a.sequence - b.sequence);
    let last = -1;
    const sequences = new Set();
    for (const s of data.stopTimes) {
      if (
        !Number.isInteger(s.sequence) ||
        s.sequence < 0 ||
        sequences.has(s.sequence)
      )
        fail("停車順不正");
      sequences.add(s.sequence);
      for (const field of ["arrivalMinutes", "departureMinutes"])
        if (s[field] != null) {
          if (
            !Number.isInteger(s[field]) ||
            s[field] < last ||
            s[field] > 59999
          )
            fail("時刻順序不正");
          last = s[field];
        }
      s.arrivalSeconds =
        s.arrivalMinutes == null ? null : s.arrivalMinutes * 60;
      s.departureSeconds =
        s.departureMinutes == null ? null : s.departureMinutes * 60;
      s.pickupType = s.pickupAllowed === false ? 1 : 0;
      s.dropOffType = s.dropoffAllowed === false ? 1 : 0;
    }
    data.stopIds = [...new Set(data.stopTimes.map((s) => s.stopId))];
    data.firstStopId = data.stopTimes[0].stopId;
    data.lastStopId = data.stopTimes.at(-1).stopId;
    data.firstDepartureMinutes = data.stopTimes[0].departureMinutes ?? null;
    data.lastArrivalMinutes = data.stopTimes.at(-1).arrivalMinutes ?? null;
  }
  if (
    ["transport_agencies", "transport_routes", "transport_stops"].includes(
      collection,
    ) &&
    (!data.name || typeof data.name !== "string")
  )
    fail("名称は必須です");
  if (collection === "transport_services") {
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(data.validFrom || "") ||
      !/^\d{4}-\d{2}-\d{2}$/.test(data.validTo || "") ||
      data.validFrom > data.validTo
    )
      fail("運行期間不正");
    for (const field of ["weekdays", "addedDates", "removedDates"])
      if (!Array.isArray(data[field])) fail("運行日形式不正");
  }
  if (
    collection === "transport_fares" &&
    (!Number.isInteger(data.amountYen) || data.amountYen < 0)
  )
    fail("運賃不正");
  const ref = db.collection(collection).doc(id);
  return db.runTransaction(async (tx) => {
    const old = await tx.get(ref);
    if (creating === old.exists)
      throw new HttpsError(
        "already-exists",
        creating ? "同じIDが存在します" : "データが削除されています",
      );
    if (old.data()?.sourceType === "gtfs") fail("GTFS直接編集禁止");
    if (
      (data.sourceType === "sample" || data.verificationStatus === "sample") &&
      old.data()?.sourceType !== "sample" &&
      old.data()?.verificationStatus !== "sample"
    )
      fail("新しいサンプルは登録できません");
    const references = [];
    if (collection === "transport_routes")
      references.push(["transport_agencies", data.agencyId]);
    if (collection === "transport_trips")
      references.push(
        ["transport_routes", data.routeId],
        ["transport_services", data.serviceId],
        ...data.stopIds.map((id) => ["transport_stops", id]),
      );
    if (collection === "transport_fares")
      references.push(
        ["transport_routes", data.routeId],
        ["transport_stops", data.fromStopId],
        ["transport_stops", data.toStopId],
      );
    for (const [c, key] of references) {
      if (typeof key !== "string" || !/^[A-Za-z0-9_-]{1,80}$/.test(key))
        fail("手動交通マスターの参照IDを選んでください");
      if (!(await tx.get(db.collection(c).doc(key))).exists)
        fail(`参照先がありません: ${c}/${key}`);
    }
    const indexes = [];
    if (collection === "transport_trips") {
      const routes = new Set(
        [data.routeId, old.data()?.routeId].filter(Boolean),
      );
      for (const routeId of routes) {
        const trips = await tx.get(
          db.collection("transport_trips").where("routeId", "==", routeId),
        );
        const stopIds = new Set(),
          previousStops = new Set();
        for (const t of trips.docs) {
          for (const s of t.data().stopTimes || []) previousStops.add(s.stopId);
          if (t.id !== id && t.data().isActive !== false)
            for (const s of t.data().stopTimes || []) stopIds.add(s.stopId);
        }
        if (routeId === data.routeId && data.isActive !== false)
          for (const s of data.stopIds) stopIds.add(s);
        for (const stopId of new Set([...previousStops, ...stopIds])) {
          const stop = db.collection("transport_stops").doc(stopId);
          if ((await tx.get(stop)).exists)
            indexes.push({ stop, routeId, include: stopIds.has(stopId) });
        }
      }
    }
    // Preserve GeoPoint and unknown existing metadata; the callable payload carries only editable fields.
    if (
      collection === "transport_stops" &&
      data.latitude != null &&
      data.longitude != null
    ) {
      if (
        !Number.isFinite(data.latitude) ||
        Math.abs(data.latitude) > 90 ||
        !Number.isFinite(data.longitude) ||
        Math.abs(data.longitude) > 180
      )
        fail("緯度経度不正");
      data.location = new GeoPoint(data.latitude, data.longitude);
    }
    tx.set(ref, {
      ...old.data(),
      ...data,
      id,
      sourceType: data.sourceType || "manual",
      createdAt: old.data()?.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    for (const index of indexes)
      tx.update(index.stop, {
        routeIds: index.include
          ? FieldValue.arrayUnion(index.routeId)
          : FieldValue.arrayRemove(index.routeId),
      });
    return { id };
  });
}
module.exports = { saveManualTransport };
