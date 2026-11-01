// Explicit opt-in: this script refuses production Firestore.
"use strict";
const assert = require("node:assert/strict");
if (
  !/^(127\.0\.0\.1|localhost):\d+$/.test(
    process.env.FIRESTORE_EMULATOR_HOST || "",
  )
)
  throw Error("Local Firestore emulator required");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { importTransport } = require("./transport_import");
const { saveManualTransport } = require("./manual_transport");
const { fixture, zip } = require("./test_support/gtfs_fixture");
const projectId = "demo-tabisaki-gtfs";
initializeApp({ projectId });
const db = getFirestore();

let buffer = zip(fixture());
const bucket = {
  file: () => ({
    getMetadata: async () => [{ size: buffer.length }],
    download: async () => [buffer],
  }),
};
const auth = {
  uid: "admin",
  token: { email: "nichi-ka@nichi-ka.com", email_verified: true },
};
async function call(data) {
  return importTransport({ auth, data }, db, bucket);
}
(async () => {
  const sourceFilePath = "transport_imports/admin/yutetsu/test.zip";
  await db
    .doc("transport_stops/manual")
    .set({ sourceType: "manual", name: "keep" });
  const p = await call({
    action: "preview",
    feedId: "yutetsu",
    sourceFilePath,
  });
  assert.deepEqual(p.errors, []);
  assert.equal((await db.doc("transport_feeds/yutetsu").get()).exists, false);
  await call({
    action: "commit",
    feedId: "yutetsu",
    versionId: p.versionId,
    expectedActiveVersionId: null,
  });
  const f = await db.doc("transport_feeds/yutetsu").get();
  assert.equal(f.data().activeVersionId, p.versionId);
  const repeat = await call({
    action: "preview",
    feedId: "yutetsu",
    sourceFilePath,
  });
  assert.equal(repeat.duplicate, true);
  await call({
    action: "commit",
    feedId: "yutetsu",
    versionId: p.versionId,
    expectedActiveVersionId: p.versionId,
  });
  const changed = fixture();
  changed["stop_times.txt"] += "missing,10:00:00,10:00:00,01,9,0,0\n";
  buffer = zip(changed);
  const bad = await call({
    action: "preview",
    feedId: "yutetsu",
    sourceFilePath,
  });
  assert.ok(bad.errors.length);
  await assert.rejects(
    call({
      action: "commit",
      feedId: "yutetsu",
      versionId: bad.versionId,
      expectedActiveVersionId: p.versionId,
    }),
  );
  assert.equal(
    (await db.doc("transport_feeds/yutetsu").get()).data().activeVersionId,
    p.versionId,
  );
  assert.equal(
    (await db.doc("transport_stops/manual").get()).data().name,
    "keep",
  );
  const revised = fixture();
  revised["stops.txt"] = revised["stops.txt"].replace("03,同名", "04,同名");
  revised["stop_times.txt"] = revised["stop_times.txt"].replace(
    ",03,2,",
    ",04,2,",
  );
  buffer = zip(revised);
  const update = await call({
    action: "preview",
    feedId: "yutetsu",
    sourceFilePath,
  });
  assert.deepEqual(update.errors, []);
  assert.ok(update.retired > 0);
  assert.ok(update.new > 0);
  assert.equal(
    (await db.doc("transport_feeds/yutetsu").get()).data().activeVersionId,
    p.versionId,
  );
  await call({
    action: "commit",
    feedId: "yutetsu",
    versionId: update.versionId,
    expectedActiveVersionId: p.versionId,
  });
  assert.equal(
    (await db.doc("transport_feeds/yutetsu").get()).data().activeVersionId,
    update.versionId,
  );
  assert.equal(
    (await db.collection("transport_feeds/yutetsu/versions").get()).docs.length,
    3,
  );
  const oldStops = await db
    .collection(
      `transport_feeds/yutetsu/versions/${p.versionId}/transport_stops`,
    )
    .get();
  assert.equal(oldStops.size, 3);
  console.log(
    "PASS: valid feed update, removed-ID preview, old-version master retention",
  );
  buffer = zip(fixture());
  const retry = await call({
    action: "preview",
    feedId: "other",
    sourceFilePath: "transport_imports/admin/other/test.zip",
  });
  buffer = Buffer.from("tamper");
  await assert.rejects(
    call({
      action: "commit",
      feedId: "other",
      versionId: retry.versionId,
      expectedActiveVersionId: null,
    }),
  );
  assert.equal((await db.doc("transport_feeds/other").get()).exists, false);
  const save = (collection, id, data, creating = true) =>
    saveManualTransport({ auth, data: { collection, id, data, creating } }, db);
  await save("transport_agencies", "agency", { name: "手動事業者" });
  await save("transport_routes", "route", {
    name: "手動路線",
    agencyId: "agency",
  });
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
      pickupAllowed: true,
      dropoffAllowed: true,
    })),
  };
  await save("transport_trips", "manual_trip", trip);
  assert.deepEqual(
    (await db.doc("transport_stops/middle").get()).data().routeIds,
    ["route"],
  );
  assert.equal(
    (await db.doc("transport_trips/manual_trip").get()).data().stopTimes.length,
    3,
  );
  await save(
    "transport_trips",
    "manual_trip",
    { ...trip, isActive: false },
    false,
  );
  assert.deepEqual(
    (await db.doc("transport_stops/middle").get()).data().routeIds,
    [],
  );
  await assert.rejects(
    save("transport_trips", "invalid", { ...trip, routeId: "missing" }),
  );
  await assert.rejects(
    save("transport_stops", "new_sample", {
      name: "sample",
      sourceType: "sample",
    }),
  );
  console.log(
    "PASS: manual agencies/routes/stops/services/trips, intermediate times, derived route-stop indexes, disabling, invalid references, new sample rejection",
  );
  console.log(
    "PASS: preview isolation, atomic activation, idempotency, invalid import preservation, manual data isolation, tampered original rejected",
  );
  await db.terminate();
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
