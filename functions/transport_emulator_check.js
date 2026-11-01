"use strict";
const assert = require("node:assert/strict");
if (
  !/^(127\.0\.0\.1|localhost):\d+$/.test(
    process.env.FIRESTORE_EMULATOR_HOST || "",
  ) ||
  !process.env.FIREBASE_STORAGE_EMULATOR_HOST
)
  throw Error("Firestore and Storage emulators required");
const { initializeApp } = require("firebase-admin/app"),
  { getFirestore } = require("firebase-admin/firestore"),
  { getStorage } = require("firebase-admin/storage");
const { importTransport } = require("./transport_import"),
  { saveManualTransport } = require("./manual_transport"),
  { fixture } = require("./test_support/gtfs_fixture"),
  { immutableSave } = require("./transport_bundle");
initializeApp({
  projectId: "demo-tabisaki-gtfs",
  storageBucket: "demo-tabisaki-gtfs.appspot.com",
});
const db = getFirestore(),
  bucket = getStorage().bucket(),
  auth = {
    uid: "admin",
    token: { email: "nichi-ka@nichi-ka.com", email_verified: true },
  };
const call = (data) => importTransport({ auth, data }, db, bucket);
async function upload(files, dir) {
  for (const [name, value] of Object.entries(files))
    await immutableSave(
      bucket,
      `${dir}/${name}`,
      Buffer.from(value),
      "text/plain",
    );
}
(async () => {
  const dir = "transport_imports/admin/feed/one";
  await upload(fixture(), dir);
  await db
    .doc("transport_stops/manual")
    .set({ name: "keep", sourceType: "manual" });
  const p = await call({
    action: "preview",
    feedId: "feed",
    sourceDirectory: dir,
  });
  assert.deepEqual(p.errors, []);
  assert.equal((await db.doc("transport_feeds/feed").get()).exists, false);
  await call({
    action: "commit",
    feedId: "feed",
    versionId: p.versionId,
    expectedActiveVersionId: null,
  });
  let f = (await db.doc("transport_feeds/feed").get()).data();
  assert.equal(f.activeVersionId, p.versionId);
  assert.equal(f.distribution.formatVersion, 2);
  assert.ok(f.distribution.platformLabels);
  assert.equal((await bucket.file(f.distribution.platformLabels.path).exists())[0],true);
  const count = await db
    .collection(`transport_feeds/feed/versions/${p.versionId}/transport_trips`)
    .count()
    .get();
  assert.equal(count.data().count, 0, "No GTFS master documents in Firestore");
  const duplicate = await call({
    action: "preview",
    feedId: "feed",
    sourceDirectory: dir,
  });
  assert.equal(duplicate.duplicate, true);
  await call({
    action: "commit",
    feedId: "feed",
    versionId: p.versionId,
    expectedActiveVersionId: p.versionId,
  });
  const invalid = fixture();
  invalid["trips.txt"] += "missing,001,bad\n";
  await upload(invalid, "transport_imports/admin/feed/bad");
  const bad = await call({
    action: "preview",
    feedId: "feed",
    sourceDirectory: "transport_imports/admin/feed/bad",
  });
  assert.ok(bad.errors.length);
  await assert.rejects(
    call({
      action: "commit",
      feedId: "feed",
      versionId: bad.versionId,
      expectedActiveVersionId: p.versionId,
    }),
  );
  assert.equal(
    (await db.doc("transport_feeds/feed").get()).data().activeVersionId,
    p.versionId,
  );
  const updated = fixture();
  updated["stops.txt"] = updated["stops.txt"].replace("03,同名", "04,同名");
  updated["stop_times.txt"] = updated["stop_times.txt"].replace(
    ",03,2,",
    ",04,2,",
  );
  await upload(updated, "transport_imports/admin/feed/two");
  const change = await call({
    action: "preview",
    feedId: "feed",
    sourceDirectory: "transport_imports/admin/feed/two",
  });
  assert.ok(change.retired > 0);
  await call({
    action: "commit",
    feedId: "feed",
    versionId: change.versionId,
    expectedActiveVersionId: p.versionId,
  });
  assert.equal(
    (await db.doc("transport_feeds/feed").get()).data().activeVersionId,
    change.versionId,
  );
  assert.equal(
    (await bucket.file(f.distribution.manifestPath).exists())[0],
    true,
    "Old immutable bundle retained",
  );
  await upload(fixture(), "transport_imports/admin/tamper/one");
  const t = await call({
    action: "preview",
    feedId: "tamper",
    sourceDirectory: "transport_imports/admin/tamper/one",
  });
  await bucket
    .file("transport_imports/admin/tamper/one/agency.txt")
    .save("changed", { metadata: { contentType: "text/plain" } });
  await assert.rejects(
    call({
      action: "commit",
      feedId: "tamper",
      versionId: t.versionId,
      expectedActiveVersionId: null,
    }),
  );
  assert.equal((await db.doc("transport_feeds/tamper").get()).exists, false);
  await assert.rejects(
    call({
      action: "preview",
      feedId: "feed",
      sourceDirectory: "transport_imports/someone/feed/one",
    }),
  );
  const save = (collection, id, data, creating = true) =>
    saveManualTransport({ auth, data: { collection, id, data, creating } }, db, bucket);
  await save("transport_agencies", "agency", { name: "手動" });
  await save("transport_routes", "route", { name: "路線", agencyId: "agency" });
  await save("transport_services", "service", {
    validFrom: "2026-01-01",
    validTo: "2026-12-31",
    weekdays: [1],
    addedDates: [],
    removedDates: [],
  });
  for (const id of ["from", "middle", "to"])
    await save("transport_stops", id, { name: "停留所" });
  const trip = {
    routeId: "route",
    serviceId: "service",
    stopTimes: ["from", "middle", "to"].map((stopId, i) => ({
      stopId,
      sequence: i,
      arrivalMinutes: 600 + i * 10,
      departureMinutes: 601 + i * 10,
    })),
  };
  await save("transport_trips", "trip", trip);
  assert.deepEqual(
    (await db.doc("transport_stops/middle").get()).data().routeIds,
    ["route"],
  );
  await save("transport_trips", "trip", { ...trip, isActive: false }, false);
  assert.deepEqual(
    (await db.doc("transport_stops/middle").get()).data().routeIds,
    [],
  );
  assert.equal(
    (await db.doc("transport_stops/manual").get()).data().name,
    "keep",
  );
  const { searchTransportJourneys } = require("./transport_journey_api");
  const { key } = require("./gtfs");
  await save("transport_trips", "trip", { ...trip, isActive: true }, false);
  const query = { date: "2026-01-05", departureSeconds: 0, maxTransfers: 3, minimumTransferSeconds: 180,
    from: [{ stopId: "from", walkingMinutes: 0 }], to: [{ stopId: key("feed", "04"), walkingMinutes: 0 }] };
  const search = () => searchTransportJourneys({ data: query }, db, bucket);
  assert.equal((await search()).journeys.length, 0, "No implicit cross-feed/name connection");
  const transfer = { name: "確認済み乗換", fromStopId: "middle", toStopId: key("feed", "01"), transferType: "2", minTransferSeconds: 600, verificationStatus: "verified", sourceUrl: "https://example.test/transfer", sourceCheckedAt: "2026-01-01", isActive: true };
  await save("transport_transfers", "walk", transfer);
  const found = await search();
  assert.equal(found.journeys[0].legs.length, 2);
  assert.equal(found.journeys[0].transfers[0].requiredSeconds, 600);
  const timetableQuery={ ...query, timetable:true };
  const pool=await searchTransportJourneys({data:timetableQuery},db,bucket);
  assert.equal(pool.journeyPool.encoding,"gzip+base64");
  const decoded=JSON.parse(require("node:zlib").gunzipSync(Buffer.from(pool.journeyPool.data,"base64")));
  assert.ok(decoded.some(j=>j.legs.length===2));
  const cachedPool=await searchTransportJourneys({data:timetableQuery},db,bucket);
  assert.equal(cachedPool.stats.cacheHit,true);
  await save("transport_transfers", "walk", { ...transfer, isActive: false }, false);
  assert.equal((await search()).journeys.length, 0, "Manual revision invalidates warm network cache");
  await save("transport_stops", "middle", { name: "同名", latitude: 43, longitude: 141 }, false);
  const nearby = await search();
  assert.ok(nearby.journeys.length > 0, "500m same-name cross-feed/manual expansion");
  assert.equal(nearby.journeys[0].usesEstimatedWalking, true);
  assert.equal(nearby.journeys[0].verificationStatus, "needsReview");
  await save("transport_stops", "middle", { name: "同名", isActive: false }, false);
  assert.equal((await search()).journeys.length, 0, "Disabling a platform removes automatic connections after revision change");
  await assert.rejects(saveManualTransport({ data: { collection: "transport_transfers", id: "attack", data: transfer, creating: true } }, db, bucket), { code: "permission-denied" });
  await assert.rejects(searchTransportJourneys({ data: { ...query, maxTransfers: 4 } }, db, bucket), { code: "invalid-argument" });
  console.log(
    "PASS: journey routing, explicit cross-feed transfer, revision cache invalidation, server-only transfer writes; txt upload, preview isolation, Storage-only publication, zero GTFS Firestore records, duplicate imports, invalid/tampered source rejection, valid update, old bundle retention, admin path, manual indexes",
  );
  await db.terminate();
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
