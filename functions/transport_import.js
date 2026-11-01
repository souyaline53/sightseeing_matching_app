"use strict";
const { createHash } = require("node:crypto");
const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue, GeoPoint } = require("firebase-admin/firestore");
const { unzip, parseGtfs, MAX_ZIP } = require("./gtfs");
const collections = {
  agencies: "transport_agencies",
  routes: "transport_routes",
  stops: "transport_stops",
  trips: "transport_trips",
  services: "transport_services",
  fares: "transport_fares",
  patterns: "transport_patterns",
  passes: "transport_passes",
};
function admin(request) {
  const t = request.auth?.token;
  if (
    !t ||
    t.email?.toLowerCase() !== "nichi-ka@nichi-ka.com" ||
    t.email_verified !== true ||
    t.firebase?.sign_in_provider === "anonymous"
  )
    throw new HttpsError("permission-denied", "管理者権限が必要です");
}
async function importTransport(request, db, bucket) {
  admin(request);
  const { feedId, action, sourceFilePath, versionId, expectedActiveVersionId } =
    request.data || {};
  if (!/^[A-Za-z0-9_-]{1,60}$/.test(feedId || ""))
    throw new HttpsError("invalid-argument", "feedId不正");
  const feed = db.collection("transport_feeds").doc(feedId);
  if (action === "preview") {
    if (
      !new RegExp(
        `^transport_imports/${request.auth.uid}/${feedId}/[A-Za-z0-9_-]+\\.zip$`,
      ).test(sourceFilePath || "")
    )
      throw new HttpsError("invalid-argument", "アップロードパス不正");
    const file = bucket.file(sourceFilePath);
    const [meta] = await file.getMetadata();
    if (Number(meta.size) > MAX_ZIP)
      throw new HttpsError("invalid-argument", "ZIP容量超過");
    const [buffer] = await file.download();
    const checksum = createHash("sha256").update(buffer).digest("hex");
    let parsed;
    try {
      parsed = parseGtfs(unzip(buffer), feedId);
    } catch (e) {
      throw new HttpsError("invalid-argument", e.message);
    }
    const current = await feed.get();
    const active = current.data()?.activeVersionId || null;
    const version = feed.collection("versions").doc(checksum);
    const old = await version.get();
    if (
      old.exists &&
      old.data().status === "importing" &&
      Date.now() - (old.data().importStartedAt || 0) < 600000
    )
      throw new HttpsError("aborted", "インポート実行中です");
    if (old.exists && old.data().status === "ready" && active === checksum)
      return {
        ...old.data().preview,
        versionId: checksum,
        duplicate: true,
        expectedActiveVersionId: active,
      };
    const diff = { new: 0, updated: 0, retired: 0 };
    if (!parsed.errors.length)
      for (const [kind, collection] of Object.entries(collections)) {
        const previous = active
          ? await feed
              .collection("versions")
              .doc(active)
              .collection(collection)
              .select()
              .get()
          : null;
        const ids = new Set(previous?.docs.map((d) => d.id) || []);
        const incoming = new Set(parsed.data[kind].map((d) => d.id));
        for (const id of incoming) ids.has(id) ? diff.updated++ : diff.new++;
        for (const id of ids) if (!incoming.has(id)) diff.retired++;
      }
    const preview = {
      ...parsed.summary,
      ...diff,
      errors: parsed.errors,
      warnings: parsed.warnings,
      checksum,
      sourceFilePath,
      expectedActiveVersionId: active,
    };
    await db.runTransaction(async (tx) => {
      const v = await tx.get(version);
      if (
        v.data()?.status === "importing" &&
        Date.now() - (v.data().importStartedAt || 0) < 600000
      )
        throw new HttpsError("aborted", "インポート実行中");
      tx.set(version, {
        status: parsed.errors.length ? "invalid" : "preview",
        preview,
        createdBy: request.auth.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    return { ...preview, versionId: checksum };
  }
  if (action !== "commit" || !/^[a-f0-9]{64}$/.test(versionId || ""))
    throw new HttpsError("invalid-argument", "操作不正");
  const version = feed.collection("versions").doc(versionId);
  const snapshot = await version.get();
  if (!snapshot.exists || snapshot.data().preview.errors.length)
    throw new HttpsError("failed-precondition", "検証済みプレビューが必要です");
  const preview = snapshot.data().preview;
  if (
    snapshot.data().status === "ready" &&
    (await feed.get()).data()?.activeVersionId === versionId
  )
    return { status: "ready", versionId, duplicate: true };
  if (preview.expectedActiveVersionId !== (expectedActiveVersionId ?? null))
    throw new HttpsError(
      "failed-precondition",
      "プレビューを再取得してください",
    );
  await db.runTransaction(async (tx) => {
    const f = await tx.get(feed),
      v = await tx.get(version);
    if (
      (f.data()?.activeVersionId || null) !== (expectedActiveVersionId ?? null)
    )
      throw new HttpsError(
        "aborted",
        "有効版が変わりました。プレビューを再取得してください",
      );
    if (
      v.data().status === "importing" &&
      Date.now() - (v.data().importStartedAt || 0) < 600000
    )
      throw new HttpsError("aborted", "インポート実行中");
    tx.update(version, { status: "importing", importStartedAt: Date.now() });
  });
  try {
    const [buffer] = await bucket.file(preview.sourceFilePath).download();
    if (createHash("sha256").update(buffer).digest("hex") !== versionId)
      throw Error("原本が変更されました");
    const parsed = parseGtfs(unzip(buffer), feedId);
    if (parsed.errors.length) throw Error(parsed.errors.join("\n"));
    const writer = db.bulkWriter();
    writer.onWriteError((e) => e.failedAttempts < 3);
    const writes = [];
    for (const [kind, collection] of Object.entries(collections))
      for (const record of parsed.data[kind]) {
        if (
          kind === "stops" &&
          record.latitude !== null &&
          record.longitude !== null
        )
          record.location = new GeoPoint(record.latitude, record.longitude);
        writes.push(
          writer.set(version.collection(collection).doc(record.id), {
            ...record,
            versionId,
          }),
        );
      }
    const outcomes = Promise.allSettled(writes);
    await writer.close();
    const results = await outcomes;
    if (results.some((r) => r.status === "rejected"))
      throw Error("一部書き込み失敗。旧版を維持します");
    for (const [kind, collection] of Object.entries(collections)) {
      const count = await version.collection(collection).count().get();
      if (count.data().count !== parsed.data[kind].length)
        throw Error(`${collection}: 保存件数不一致`);
    }
    await db.runTransaction(async (tx) => {
      const current = await tx.get(feed);
      if (
        (current.data()?.activeVersionId || null) !==
        (expectedActiveVersionId ?? null)
      )
        throw Error("並行更新を検出。再プレビューが必要");
      tx.set(
        feed,
        {
          feedId,
          activeVersionId: versionId,
          ...parsed.summary,
          checksum: versionId,
          sourceFilePath: preview.sourceFilePath,
          importStatus: "ready",
          importSummary: parsed.summary,
          importedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      tx.update(version, {
        status: "ready",
        importedAt: FieldValue.serverTimestamp(),
      });
    });
    return { status: "ready", versionId, summary: parsed.summary };
  } catch (e) {
    await version.update({ status: "failed", error: e.message });
    throw new HttpsError("internal", e.message);
  }
}
module.exports = { importTransport, admin };
