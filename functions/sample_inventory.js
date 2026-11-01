"use strict";
const { admin } = require("./transport_import");
const { FieldPath, Filter } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const allowed = [
  "transport_agencies",
  "transport_stops",
  "transport_routes",
  "transport_trips",
  "transport_services",
  "transport_fares",
];
async function sampleInventory(request, db) {
  admin(request);
  const { collection, after } = request.data || {};
  if (!allowed.includes(collection))
    throw new HttpsError("invalid-argument", "コレクション不正");
  let query = db
    .collection(collection)
    .where(
      Filter.or(
        Filter.where("sourceType", "==", "sample"),
        Filter.where("verificationStatus", "==", "sample"),
      ),
    )
    .orderBy(FieldPath.documentId())
    .limit(100);
  if (after) query = query.startAfter(after);
  const page = await query.get();
  return {
    records: page.docs.map((d) => ({
      id: d.id,
      name: d.data().name || d.data().headsign || d.id,
      sourceType: d.data().sourceType || null,
      verificationStatus: d.data().verificationStatus || null,
    })),
    next: page.docs.length === 100 ? page.docs.at(-1).id : null,
  };
}
module.exports = { sampleInventory };
