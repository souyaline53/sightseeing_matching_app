"use strict";
const fs = require("node:fs"),
  path = require("node:path");
const { FieldValue } = require("firebase-admin/firestore");
const { context } = require("./production_transport_context.cjs");
const {
  parseFiles,
  compileBundle,
  immutableSave,
  publishBundle,
} = require("./transport_bundle");
const jr = process.argv.includes("--jr-hokkaido");
const folders = jr ? ["jr_hokkaido"] : ["yutetsu_bus", "hokkaido_chuo"];
(async () => {
  const inputs = folders.map((feedId) => {
    const dir = jr ? "assets/jr_all_combined_with_train_types" : path.join("docs/transport", feedId),
      files = Object.fromEntries(
        fs
          .readdirSync(dir)
          .filter((n) => n.endsWith(".txt") || n === "train_types.csv")
          .map((n) => [n, fs.readFileSync(path.join(dir, n))]),
      );
    const parsed = parseFiles(files, feedId);
    if (parsed.errors.length)
      throw Error(`${feedId}: ${parsed.errors.join("\n")}`);
    const bundle = compileBundle(parsed, feedId, parsed.checksum);
    return { feedId, files, parsed, bundle };
  });
  const { db, bucket, projectId } = context();
  const reports = [];
  for (const { feedId, files, parsed, bundle } of inputs) {
    const distribution = {
      formatVersion: 2,
      manifestPath: bundle.manifestPath,
      manifestChecksum: bundle.manifestChecksum,
      platformLabels: bundle.platformLabels,
      routing: bundle.routing,
      manifestBytes: bundle.manifestBytes,
      totalBytes: bundle.totalBytes,
      objectCount: bundle.objects.length,
    };
    const feed = db.collection("transport_feeds").doc(feedId),
      sourceDirectory = `transport_imports/maintenance/${feedId}/${parsed.checksum}`,
      existing = await feed.get();
    if (process.argv.includes("--apply")) {
      for (const [name, bytes] of Object.entries(files))
        await immutableSave(
          bucket,
          `${sourceDirectory}/${name}`,
          bytes,
          "text/plain",
        );
      await publishBundle(bucket, bundle);
      const preview = {
        ...parsed.summary,
        new: Object.values(parsed.data).reduce((n, r) => n + r.length, 0),
        updated: 0,
        retired: 0,
        errors: [],
        warnings: parsed.warnings,
        checksum: parsed.checksum,
        sourceDirectory,
        sourceFiles: parsed.sourceFiles,
        totalBytes: parsed.totalBytes,
        expectedActiveVersionId: existing.data()?.activeVersionId || null,
      };
      await feed.collection("versions").doc(parsed.checksum).set(
        {
          status: "prepared",
          formatVersion: 2,
          preview,
          distribution,
          preparedAt: FieldValue.serverTimestamp(),
          preparedBy: "authorized-maintenance-cli",
        },
        { merge: true },
      );
      await feed.set(
        {
          feedId,
          ...parsed.summary,
          pendingVersionId: parsed.checksum,
          pendingDistribution: distribution,
          importStatus: existing.data()?.activeVersionId ? "ready" : "prepared",
        },
        { merge: true },
      );
    }
    if (process.argv.includes("--activate")) {
      // Activate after a verified production release; never implied by --apply.
      await db.runTransaction(async (tx) => {
        const f = await tx.get(feed),
          v = await tx.get(feed.collection("versions").doc(parsed.checksum));
        if (
          !v.exists ||
          !["prepared", "ready"].includes(v.data().status) ||
          v.data().distribution.manifestChecksum !== bundle.manifestChecksum
        )
          throw Error("検証済みのStorageデータがありません");
        if (
          f.data()?.pendingVersionId !== parsed.checksum &&
          f.data()?.activeVersionId !== parsed.checksum
        )
          throw Error("公開待ちバージョンが変わっています");
        tx.set(
          feed,
          {
            ...parsed.summary,
            feedId,
            activeVersionId: parsed.checksum,
            checksum: parsed.checksum,
            sourceDirectory,
            distribution,
            importStatus: "ready",
            importSummary: parsed.summary,
            importedAt: FieldValue.serverTimestamp(),
            pendingVersionId: FieldValue.delete(),
            pendingDistribution: FieldValue.delete(),
          },
          { merge: true },
        );
        tx.update(v.ref, {
          status: "ready",
          importedAt: FieldValue.serverTimestamp(),
        });
      });
    }
    reports.push({
      feedId,
      versionId: parsed.checksum,
      summary: parsed.summary,
      rawFiles: parsed.sourceFiles.length,
      rawBytes: parsed.totalBytes,
      distribution,
      uploaded: process.argv.includes("--apply"),
      activated: process.argv.includes("--activate"),
    });
    console.log(JSON.stringify(reports.at(-1)));
  }
  fs.mkdirSync(".local-backups", { recursive: true });
  fs.writeFileSync(
    `.local-backups/${jr ? "jr-hokkaido" : "transport"}-storage-upload-report.json`,
    JSON.stringify(
      { projectId, createdAt: new Date().toISOString(), feeds: reports },
      null,
      2,
    ),
  );
  await db.terminate();
})().catch((e) => {
  console.error(e.message);
  process.exitCode = 1;
});
