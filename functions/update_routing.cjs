"use strict";
// Attach routing assets without rewriting existing immutable timetables or IDs.
const fs = require("node:fs"),
  path = require("node:path");
const { context } = require("./production_transport_context.cjs");
const { parseFiles, immutableSave, hash } = require("./transport_bundle");
const { buildRoutingBundle } = require("./transport_routing_bundle");
(async () => {
  const { db, bucket } = context();
  for (const feedId of ["yutetsu_bus", "hokkaido_chuo"]) {
    const dir = path.join("docs/transport", feedId),
      files = Object.fromEntries(
        fs
          .readdirSync(dir)
          .filter((n) => n.endsWith(".txt"))
          .map((n) => [n, fs.readFileSync(path.join(dir, n))]),
      );
    const parsed = parseFiles(files, feedId);
    const ref = db.collection("transport_feeds").doc(feedId),
      feed = await ref.get();
    if (feed.data()?.activeVersionId !== parsed.checksum)
      throw Error(`${feedId}: ローカル原本と有効版が異なります`);
    const routing = buildRoutingBundle(parsed, feedId, parsed.checksum);
    if (process.argv.includes("--apply")) {
      await immutableSave(bucket, routing.object.path, routing.object.bytes);
      const [bytes] = await bucket.file(routing.object.path).download();
      if (hash(bytes) !== routing.descriptor.checksum)
        throw Error("乗換検索データの保存結果不一致");
      await db.runTransaction(async (tx) => {
        const current = await tx.get(ref);
        if (current.data().activeVersionId !== parsed.checksum)
          throw Error("有効版が変わりました");
        const distribution = current.data().distribution;
        const fields = {
          "distribution.routing": routing.descriptor,
          "distribution.totalBytes":
            distribution.totalBytes -
            (distribution.routing?.bytes || 0) +
            routing.descriptor.bytes,
          "distribution.objectCount":
            distribution.objectCount + (distribution.routing ? 0 : 1),
        };
        tx.update(ref, fields);
        tx.update(ref.collection("versions").doc(parsed.checksum), fields);
      });
    }
    console.log(
      JSON.stringify({
        feedId,
        tripCount: JSON.parse(require("node:zlib").gunzipSync(routing.object.bytes)).trips.length,
        bytes: routing.descriptor.bytes,
        applied: process.argv.includes("--apply"),
      }),
    );
  }
  await db.terminate();
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
