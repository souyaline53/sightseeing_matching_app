"use strict";
const { HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const {
  parseFiles,
  compileBundle,
  publishBundle,
  decodeAsset,
  MAX_FILE,
  MAX_TOTAL,
} = require("./transport_bundle");
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
async function readSourceDirectory(bucket, directory) {
  const [objects, next] = await bucket.getFiles({
    prefix: `${directory}/`,
    autoPaginate: false,
    maxResults: 101,
  });
  if (!objects.length || objects.length > 100 || next)
    throw new HttpsError("invalid-argument", "txt一式は1〜100ファイル必要です");
  const files = {};
  let total = 0;
  for (let i = 0; i < objects.length; i += 8)
    await Promise.all(
      objects.slice(i, i + 8).map(async (object) => {
        const name = object.name.slice(directory.length + 1);
        if (!/^[a-z][a-z0-9_]*\.txt$/.test(name))
          throw new HttpsError(
            "invalid-argument",
            `標準ファイル名へ変更してください: ${name}`,
          );
        const [meta] = await object.getMetadata();
        const size = Number(meta.size);
        total += size;
        if (
          !size ||
          size > MAX_FILE ||
          total > MAX_TOTAL ||
          !String(meta.contentType).startsWith("text/plain")
        )
          throw new HttpsError(
            "invalid-argument",
            "UTF-8のtxt・1ファイル50MiB・合計100MiB以内でアップロードしてください",
          );
        const [bytes] = await object.download();
        files[name] = bytes;
      }),
    );
  return files;
}
async function previousIds(feedData, bucket) {
  if (feedData?.distribution?.formatVersion !== 2) return {};
  const [bytes] = await bucket
    .file(feedData.distribution.manifestPath)
    .download();
  const manifest = JSON.parse(bytes);
  const ids = {};
  for (const file of Object.keys(manifest.assets).filter((f) =>
    f.startsWith("ids/"),
  )) {
    const kind = file.slice(4, file.lastIndexOf("-"));
    const [b] = await bucket
      .file(`transport_data/${manifest.feedId}/${manifest.versionId}/${file}`)
      .download();
    (ids[kind] ??= []).push(...decodeAsset(b));
  }
  return ids;
}
async function importTransport(request, db, bucket) {
  admin(request);
  const {
    feedId,
    action,
    sourceDirectory,
    versionId,
    expectedActiveVersionId,
  } = request.data || {};
  if (!/^[A-Za-z0-9_-]{1,60}$/.test(feedId || ""))
    throw new HttpsError("invalid-argument", "feedId不正");
  const feed = db.collection("transport_feeds").doc(feedId);
  if (action === "preview") {
    const expectedPrefix = `transport_imports/${request.auth.uid}/${feedId}/`;
    if (
      typeof sourceDirectory !== "string" ||
      !sourceDirectory.startsWith(expectedPrefix) ||
      !/^[A-Za-z0-9_-]+$/.test(sourceDirectory.slice(expectedPrefix.length))
    )
      throw new HttpsError("invalid-argument", "アップロードフォルダ不正");
    let parsed;
    try {
      parsed = parseFiles(
        await readSourceDirectory(bucket, sourceDirectory),
        feedId,
      );
    } catch (e) {
      throw e instanceof HttpsError
        ? e
        : new HttpsError("invalid-argument", e.message);
    }
    const current = await feed.get(),
      active = current.data()?.activeVersionId || null,
      version = feed.collection("versions").doc(parsed.checksum),
      old = await version.get();
    if (
      old.data()?.status === "importing" &&
      Date.now() - (old.data().importStartedAt || 0) < 600000
    )
      throw new HttpsError("aborted", "インポート実行中です");
    if (
      old.data()?.status === "ready" &&
      active === parsed.checksum &&
      current.data()?.distribution?.formatVersion === 2
    )
      return {
        ...old.data().preview,
        versionId: parsed.checksum,
        duplicate: true,
        expectedActiveVersionId: active,
      };
    const diff = { new: 0, updated: 0, retired: 0 };
    if (!parsed.errors.length) {
      const oldIds = await previousIds(current.data(), bucket);
      for (const [kind, rows] of Object.entries(parsed.data)) {
        const before = new Set(oldIds[kind] || []),
          incoming = new Set(rows.map((r) => r.id));
        for (const id of incoming) before.has(id) ? diff.updated++ : diff.new++;
        for (const id of before) if (!incoming.has(id)) diff.retired++;
      }
    }
    const today = new Date().toISOString().slice(0, 10);
    if (parsed.summary.validTo && parsed.summary.validTo < today)
      parsed.warnings.push(
        `有効期間が終了しています（${parsed.summary.validTo}）。旅行日の運行候補にはなりません`,
      );
    const preview = {
      ...parsed.summary,
      ...diff,
      errors: parsed.errors,
      warnings: parsed.warnings,
      checksum: parsed.checksum,
      sourceDirectory,
      sourceFiles: parsed.sourceFiles,
      totalBytes: parsed.totalBytes,
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
        formatVersion: 2,
        createdBy: request.auth.uid,
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    return { ...preview, versionId: parsed.checksum };
  }
  if (action !== "commit" || !/^[a-f0-9]{64}$/.test(versionId || ""))
    throw new HttpsError("invalid-argument", "操作不正");
  const version = feed.collection("versions").doc(versionId),
    snapshot = await version.get();
  if (
    !snapshot.exists ||
    snapshot.data().formatVersion !== 2 ||
    snapshot.data().preview.errors.length
  )
    throw new HttpsError(
      "failed-precondition",
      "txt一式の検証済みプレビューが必要です",
    );
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
        "有効版が変わりました。再プレビューが必要です",
      );
    if (
      v.data().status === "importing" &&
      Date.now() - (v.data().importStartedAt || 0) < 600000
    )
      throw new HttpsError("aborted", "実行中です");
    tx.update(version, { status: "importing", importStartedAt: Date.now() });
  });
  try {
    const parsed = parseFiles(
      await readSourceDirectory(bucket, preview.sourceDirectory),
      feedId,
    );
    if (parsed.checksum !== versionId) throw Error("原本が変更されました");
    if (parsed.errors.length) throw Error(parsed.errors.join("\n"));
    const bundle = compileBundle(parsed, feedId, versionId);
    await publishBundle(bucket, bundle);
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
    await db.runTransaction(async (tx) => {
      const current = await tx.get(feed);
      if (
        (current.data()?.activeVersionId || null) !==
        (expectedActiveVersionId ?? null)
      )
        throw Error("並行更新を検出。再プレビューしてください");
      tx.set(
        feed,
        {
          feedId,
          ...parsed.summary,
          activeVersionId: versionId,
          checksum: versionId,
          sourceDirectory: preview.sourceDirectory,
          importStatus: "ready",
          importSummary: parsed.summary,
          distribution,
          importedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      tx.update(version, {
        status: "ready",
        distribution,
        importedAt: FieldValue.serverTimestamp(),
      });
    });
    return {
      status: "ready",
      versionId,
      summary: parsed.summary,
      distribution,
    };
  } catch (e) {
    await version.update({ status: "failed", error: e.message });
    throw new HttpsError("internal", e.message);
  }
}
module.exports = { importTransport, admin, readSourceDirectory };
