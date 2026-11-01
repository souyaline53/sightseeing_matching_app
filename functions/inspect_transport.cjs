"use strict";
const { context } = require("./production_transport_context.cjs");
const { Filter } = require("firebase-admin/firestore");
(async () => {
  const { db, bucket, projectId, bucketName } = context();
  const result = { projectId, bucketName, feeds: [], samples: {} };
  result.feeds = (await db.collection("transport_feeds").get()).docs.map(
    (d) => ({ id: d.id, ...d.data() }),
  );
  for (const c of [
    "transport_agencies",
    "transport_routes",
    "transport_stops",
    "transport_trips",
    "transport_services",
    "transport_fares",
    "transit",
  ]) {
    const p = await db
      .collection(c)
      .where(
        Filter.or(
          Filter.where("sourceType", "==", "sample"),
          Filter.where("verificationStatus", "==", "sample"),
        ),
      )
      .get();
    result.samples[c] = p.docs.map((d) => ({
      id: d.id,
      name: d.data().name || d.data().title || d.data().headsign,
      sourceType: d.data().sourceType,
      verificationStatus: d.data().verificationStatus,
    }));
  }
  const [meta] = await bucket.getMetadata();
  result.bucketLocation = meta.location;
  console.log(JSON.stringify(result, null, 2));
  await db.terminate();
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
