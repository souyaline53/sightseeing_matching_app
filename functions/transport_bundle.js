"use strict";
const { createHash } = require("node:crypto");
const { gzipSync, gunzipSync } = require("node:zlib");
const { parseGtfs } = require("./gtfs");
const { buildRoutingBundle } = require("./transport_routing_bundle");
const { buildStopLabels } = require("./transport_stop_labels");
const FORMAT = 2,
  MAX_FILE = 50 * 1024 * 1024,
  MAX_TOTAL = 100 * 1024 * 1024;
const hash = (b) => createHash("sha256").update(b).digest("hex");
const shard = (id) => hash(id).slice(0, 2);
const standardFiles = {
  "agency.txt": "必須：交通事業者",
  "stops.txt": "必須：駅・停留所",
  "routes.txt": "必須：路線",
  "trips.txt": "必須：便",
  "stop_times.txt": "必須：途中停留所の発着時刻",
  "calendar.txt": "calendar_dates.txtと少なくとも一方：曜日・期間",
  "calendar_dates.txt": "calendar.txtと少なくとも一方：運行日・例外日",
  "fare_attributes.txt": "任意：片道運賃",
  "fare_rules.txt": "任意：運賃の適用区間",
  "agency_jp.txt": "任意：日本向け事業者拡張",
  "routes_jp.txt": "任意：日本向け路線拡張（原本保管）",
  "office_jp.txt": "任意：営業所（原本保管）",
  "feed_info.txt": "任意／translations.txt使用時必須：配信情報",
  "translations.txt": "任意：翻訳（原本保管）",
  "pass_attributes.txt": "任意：定期券・パス",
  "pass_rules.txt": "任意：パスの適用区間",
  "shapes.txt": "任意：経路形状（原本保管）",
  "transfers.txt": "任意：明示的な乗換接続・最小乗換時間",
  "frequencies.txt": "任意：頻度運行（対象便は時刻表候補から除外）",
};
function inspectFiles(files) {
  const names = Object.keys(files).sort();
  if (!names.length || names.length > 100)
    throw Error("txtファイルは1〜100個選択してください");
  let total = 0;
  const canonical = createHash("sha256"),
    sourceFiles = [];
  for (const name of names) {
    if (!/^[a-z][a-z0-9_]*\.txt$/.test(name))
      throw Error(`ファイル名を標準名へ変更してください: ${name}`);
    const raw = Buffer.isBuffer(files[name])
      ? files[name]
      : Buffer.from(files[name]);
    total += raw.length;
    if (!raw.length || raw.length > MAX_FILE || total > MAX_TOTAL)
      throw Error(
        "1ファイル50MiB・合計100MiB以内の空でないtxtを選択してください",
      );
    const checksum = hash(raw);
    canonical.update(`${name}\0${checksum}\n`);
    sourceFiles.push({ name, bytes: raw.length, checksum });
  }
  return { checksum: canonical.digest("hex"), sourceFiles, totalBytes: total };
}
function parseFiles(files, feedId) {
  const inspection = inspectFiles(files);
  const text = Object.fromEntries(
    Object.entries(files).map(([n, b]) => [
      n,
      new TextDecoder("utf-8", { fatal: true }).decode(
        Buffer.isBuffer(b) ? b : Buffer.from(b),
      ),
    ]),
  );
  return { ...inspection, ...parseGtfs(text, feedId) };
}
function pages(rows, maxBytes = 512 * 1024) {
  const out = [];
  let batch = [],
    size = 2;
  for (const row of rows) {
    const bytes = Buffer.byteLength(JSON.stringify(row)) + 1;
    if (bytes > 2 * 1024 * 1024)
      throw Error("検索用レコードが2MiBを超えています");
    if (batch.length && (size + bytes > maxBytes || batch.length >= 128)) {
      out.push(batch);
      batch = [];
      size = 2;
    }
    batch.push(row);
    size += bytes;
  }
  if (batch.length) out.push(batch);
  return out;
}
function compileBundle(parsed, feedId, versionId) {
  if (parsed.errors.length)
    throw Error("検証エラーがあるフィードは公開できません");
  const prefix = `transport_data/${feedId}/${versionId}`,
    assets = {},
    objects = [];
  const add = (file, value) => {
    const raw = Buffer.from(JSON.stringify(value));
    if (raw.length > 4 * 1024 * 1024)
      throw Error(`検索用ファイルが4MiBを超えています: ${file}`);
    const bytes = gzipSync(raw, { level: 6 });
    assets[file] = {
      checksum: hash(bytes),
      bytes: bytes.length,
      rawBytes: raw.length,
    };
    objects.push({ path: `${prefix}/${file}`, bytes });
    return file;
  };
  const data = Object.fromEntries(
    Object.entries(parsed.data).map(([k, rows]) => [
      k,
      rows.map((r) => ({ ...r, versionId })),
    ]),
  );
  const services = new Map(data.services.map((r) => [r.id, r])),
    stops = new Map(data.stops.map((s) => [s.id, s]));
  const routeTrips = new Map(),
    routePatterns = new Map(),
    routeStops = new Map();
  for (const t of data.trips) {
    if (!routeTrips.has(t.routeId)) routeTrips.set(t.routeId, []);
    routeTrips.get(t.routeId).push(t);
  }
  for (const p of data.patterns) {
    if (!routePatterns.has(p.routeId)) routePatterns.set(p.routeId, []);
    routePatterns.get(p.routeId).push(p);
  }
  for (const s of data.stops)
    for (const rid of s.routeIds) {
      if (!routeStops.has(rid)) routeStops.set(rid, []);
      routeStops.get(rid).push(s);
    }
  const routes = [];
  for (const route of data.routes) {
    const dir = `routes/${hash(route.id)}`,
      tripPages = [];
    for (const [i, rows] of pages(routeTrips.get(route.id) || []).entries()) {
      const file = add(`${dir}/trips-${i}.json.gz`, {
        trips: rows,
        services: [...new Set(rows.map((t) => t.serviceId))].map((id) =>
          services.get(id),
        ),
      });
      tripPages.push({
        file,
        stopIds: [...new Set(rows.flatMap((t) => t.stopIds))],
      });
    }
    const routeFile = add(`${dir}/stops.json.gz`, {
      route,
      stops: routeStops.get(route.id) || [],
      patterns: routePatterns.get(route.id) || [],
      tripPages,
    });
    routes.push({ ...route, routeFile });
  }
  add("catalog.json.gz", { agencies: data.agencies, routes });
  add("stop-names.json.gz", {
    stops: data.stops.map((s) => ({
      id: s.id,
      name: s.name,
      platformCode: s.platformCode,
    })),
  });
  const stopShards = new Map();
  for (const s of stops.values()) {
    const k = shard(s.id);
    if (!stopShards.has(k)) stopShards.set(k, []);
    stopShards.get(k).push(s);
  }
  for (const [k, rows] of stopShards)
    add(`stops/${k}.json.gz`, { stops: rows });
  const fareShards = new Map();
  for (const f of data.fares) {
    for (const r of f.rules) {
      const k = shard(r.originId || "*");
      if (!fareShards.has(k)) fareShards.set(k, new Map());
      const bucket = fareShards.get(k);
      if (!bucket.has(f.id))
        bucket.set(f.id, {
          ...f,
          containsUnresolved: f.rules.some((rule) => rule.containsId != null),
          rules: [],
        });
      bucket.get(f.id).rules.push(r);
    }
  }
  for (const [k, byId] of fareShards) {
    const rows = [...byId.values()].flatMap((f) =>
      pages(f.rules, 128 * 1024).map((rules) => ({ ...f, rules })),
    );
    for (const [i, chunk] of pages(rows).entries())
      add(`fares/${k}-${i}.json.gz`, { fares: chunk });
  }
  for (const [i, rows] of pages(data.passes).entries())
    add(`passes/${i}.json.gz`, { passes: rows });
  for (const [kind, rows] of Object.entries(data))
    for (const [i, ids] of pages(rows.map((r) => r.id)).entries())
      add(`ids/${kind}-${i}.json.gz`, ids);
  const manifest = {
    formatVersion: FORMAT,
    feedId,
    versionId,
    summary: parsed.summary,
    assets,
  };
  const manifestBytes = Buffer.from(JSON.stringify(manifest));
  if (manifestBytes.length > 2 * 1024 * 1024)
    throw Error("配信マニフェスト容量超過");
  const labels = buildStopLabels(parsed, feedId, versionId);
  const routing = buildRoutingBundle(parsed, feedId, versionId);
  return {
    routing: routing.descriptor,
    platformLabels: labels.descriptor,
    manifest,
    manifestPath: `${prefix}/manifest.json`,
    manifestChecksum: hash(manifestBytes),
    manifestBytes: manifestBytes.length,
    objects: [
      ...objects,
      labels.object,
      routing.object,
      { path: `${prefix}/manifest.json`, bytes: manifestBytes },
    ],
    totalBytes:
      objects.reduce((n, o) => n + o.bytes.length, 0) +
      manifestBytes.length +
      labels.object.bytes.length + routing.object.bytes.length,
  };
}
async function immutableSave(
  bucket,
  path,
  bytes,
  contentType = "application/octet-stream",
) {
  const file = bucket.file(path);
  try {
    await file.save(bytes, {
      resumable: false,
      preconditionOpts: { ifGenerationMatch: 0 },
      metadata: {
        contentType,
        cacheControl: path.startsWith("transport_data/")
          ? "public,max-age=31536000,immutable"
          : "private,no-store",
        metadata: { sha256: hash(bytes) },
      },
    });
  } catch (e) {
    if (e.code !== 412) throw e;
    const [old] = await file.download();
    if (hash(old) !== hash(bytes))
      throw Error(`既存オブジェクト内容が不一致: ${path}`);
  }
}
async function publishBundle(bucket, bundle) {
  for (let i = 0; i < bundle.objects.length; i += 8)
    await Promise.all(
      bundle.objects
        .slice(i, i + 8)
        .map((o) =>
          immutableSave(
            bucket,
            o.path,
            o.bytes,
            o.path.endsWith(".json")
              ? "application/json"
              : "application/octet-stream",
          ),
        ),
    );
  // Verify persisted object sizes and hashes before making the manifest pointer active.
  for (let i = 0; i < bundle.objects.length; i += 8)
    await Promise.all(
      bundle.objects.slice(i, i + 8).map(async (o) => {
        const [bytes] = await bucket.file(o.path).download();
        if (hash(bytes) !== hash(o.bytes))
          throw Error(`Storage保存結果不一致: ${o.path}`);
      }),
    );
}
function decodeAsset(bytes) {
  return JSON.parse(gunzipSync(bytes).toString("utf8"));
}
module.exports = {
  FORMAT,
  MAX_FILE,
  MAX_TOTAL,
  hash,
  shard,
  standardFiles,
  inspectFiles,
  parseFiles,
  pages,
  compileBundle,
  immutableSave,
  publishBundle,
  decodeAsset,
};
