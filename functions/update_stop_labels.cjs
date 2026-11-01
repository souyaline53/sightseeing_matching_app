"use strict";
// Attach display metadata without rewriting immutable timetable assets or changing IDs.
const fs = require("node:fs"),
  path = require("node:path");
const { context } = require("./production_transport_context.cjs");
const { parseFiles, immutableSave, hash } = require("./transport_bundle");
const { buildStopLabels } = require("./transport_stop_labels");
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
    const labels = buildStopLabels(parsed, feedId, parsed.checksum);
    if (process.argv.includes("--apply")) {
      await immutableSave(bucket, labels.object.path, labels.object.bytes);
      const [bytes] = await bucket.file(labels.object.path).download();
      if (hash(bytes) !== labels.descriptor.checksum)
        throw Error("乗り場案内の保存結果不一致");
      await db.runTransaction(async (tx) => {
        const current = await tx.get(ref);
        if (current.data().activeVersionId !== parsed.checksum)
          throw Error("有効版が変わりました");
        const distribution = current.data().distribution;
        const fields = {
          "distribution.platformLabels": labels.descriptor,
          "distribution.totalBytes":
            distribution.totalBytes -
            (distribution.platformLabels?.bytes || 0) +
            labels.descriptor.bytes,
          "distribution.objectCount":
            distribution.objectCount + (distribution.platformLabels ? 0 : 1),
        };
        tx.update(ref, fields);
        tx.update(ref.collection("versions").doc(parsed.checksum), fields);
      });
    }
    console.log(
      JSON.stringify({
        feedId,
        stopCount: Object.keys(
          JSON.parse(require("node:zlib").gunzipSync(labels.object.bytes))
            .stops,
        ).length,
        bytes: labels.descriptor.bytes,
        applied: process.argv.includes("--apply"),
      }),
    );
  }
  await db.terminate();
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
