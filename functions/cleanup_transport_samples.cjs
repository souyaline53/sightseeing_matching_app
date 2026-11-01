"use strict";
// Read-only unless --apply. Only explicit sample provenance is eligible.
const fs = require("node:fs");
const { context } = require("./production_transport_context.cjs");
const { immutableSave } = require("./transport_bundle");
const { FieldPath } = require("firebase-admin/firestore");
const collections = [
  "transport_agencies",
  "transport_routes",
  "transport_stops",
  "transport_trips",
  "transport_services",
  "transport_fares",
  "transit",
];
const sample = (d) =>
  d.sourceType === "sample" || d.verificationStatus === "sample";
function references(d) {
  return new Set(
    [
      d.agencyId,
      d.routeId,
      d.serviceId,
      d.parentStationId,
      d.fromStopId,
      d.toStopId,
      ...(d.routeIds || []),
      ...(d.stopIds || []),
      ...(d.stopTimes || []).map((s) => s.stopId),
    ].filter((v) => typeof v === "string"),
  );
}
(async () => {
  const { db, bucket, projectId } = context(),
    snapshots = [];
  for (const name of collections) {
    const result = await db.collection(name).get();
    if (result.size > 5000)
      throw Error("安全のためコレクションが5000件を超える処理は停止します");
    snapshots.push(...result.docs);
  }
  let candidates = snapshots.filter((d) => sample(d.data()));
  const blocked = new Set();
  // Retain sample masters referenced by actual records, including transitive dependencies.
  let changed = true;
  while (changed) {
    changed = false;
    const retained = snapshots.filter(
      (d) => !sample(d.data()) || blocked.has(d.ref.path),
    );
    for (const doc of candidates) {
      if (blocked.has(doc.ref.path)) continue;
      if (retained.some((r) => references(r.data()).has(doc.id))) {
        blocked.add(doc.ref.path);
        changed = true;
      }
    }
  }
  candidates = candidates.filter((d) => !blocked.has(d.ref.path));
  const stopIds = new Set(
    candidates
      .filter((d) => d.ref.parent.id === "transport_stops")
      .map((d) => d.id),
  );
  const spotChanges = [];
  for (const name of ["sightseeing_spot", "transit"]) {
    const page = await db.collection(name).get();
    if (page.size > 5000) throw Error("観光地が5000件を超えるため中止");
    for (const doc of page.docs) {
      if (!Array.isArray(doc.data().accessStops)) continue;
      const before = doc.data().accessStops,
        after = before.filter((s) => !stopIds.has(s.stopId));
      if (after.length !== before.length)
        spotChanges.push({ doc, before, after });
    }
  }
  const plan = {
    projectId,
    candidates: candidates.map((d) => d.ref.path),
    retainedReferences: [...blocked],
    accessUpdates: spotChanges.map((s) => ({
      path: s.doc.ref.path,
      removed: s.before
        .filter((x) => stopIds.has(x.stopId))
        .map((x) => x.stopId),
    })),
  };
  console.log(JSON.stringify(plan, null, 2));
  if (!process.argv.includes("--apply") || !candidates.length) {
    await db.terminate();
    return;
  }
  if (candidates.length + spotChanges.length > 400)
    throw Error("400件を超える一括変更は拒否");
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-"),
    backup = {
      ...plan,
      createdAt: new Date().toISOString(),
      documents: [...candidates, ...spotChanges.map((s) => s.doc)].map((d) => ({
        path: d.ref.path,
        updateTime: {
          seconds: d.updateTime.seconds,
          nanoseconds: d.updateTime.nanoseconds,
        },
        data: d.data(),
      })),
    };
  const bytes = Buffer.from(JSON.stringify(backup, null, 2));
  fs.mkdirSync(".local-backups", { recursive: true });
  fs.writeFileSync(`.local-backups/transport-samples-${timestamp}.json`, bytes);
  await immutableSave(
    bucket,
    `transport_backups/${timestamp}/samples.json`,
    bytes,
    "application/json",
  );
  const batch = db.batch();
  for (const d of candidates)
    batch.delete(d.ref, { lastUpdateTime: d.updateTime });
  for (const s of spotChanges)
    batch.update(
      s.doc.ref,
      { accessStops: s.after },
      { lastUpdateTime: s.doc.updateTime },
    );
  await batch.commit();
  console.log(
    JSON.stringify({
      deleted: candidates.length,
      accessUpdated: spotChanges.length,
      backup: `transport_backups/${timestamp}/samples.json`,
    }),
  );
  await db.terminate();
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
