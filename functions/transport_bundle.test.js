"use strict";
const { test } = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
const { fixture } = require("./test_support/gtfs_fixture");
const {
  parseFiles,
  compileBundle,
  decodeAsset,
  shard,
  inspectFiles,
} = require("./transport_bundle");
const { key } = require("./gtfs");
test("txt inventory is canonical regardless of file selection order; unsafe names, ZIP, encoding and size reject", () => {
  const a = fixture(),
    b = Object.fromEntries(Object.entries(a).reverse());
  assert.equal(inspectFiles(a).checksum, inspectFiles(b).checksum);
  assert.throws(() => parseFiles({ "agency.zip": "x" }, "x"), /標準/);
  assert.throws(() => parseFiles({ "../agency.txt": "x" }, "x"), /標準/);
  assert.throws(
    () => parseFiles({ "agency.txt": Buffer.from([0xff]) }, "x"),
    /encoded/,
  );
  assert.throws(
    () => inspectFiles({ "agency.txt": Buffer.alloc(50 * 1024 * 1024 + 1) }),
    /50MiB/,
  );
});
test("bundle browse needs no trips; stop membership, intermediate times, patterns and fare zones are retained", () => {
  const parsed = parseFiles(fixture(), "feed"),
    bundle = compileBundle(parsed, "feed", parsed.checksum),
    objects = new Map(bundle.objects.map((o) => [o.path, o.bytes]));
  const get = (f) =>
    decodeAsset(objects.get(`transport_data/feed/${parsed.checksum}/${f}`));
  const catalog = get("catalog.json.gz");
  assert.equal(catalog.agencies.length, 1);
  assert.equal(catalog.routes.length, 1);
  assert.ok(!JSON.stringify(catalog).includes("stopTimes"));
  const summary = get(catalog.routes[0].routeFile);
  assert.equal(summary.stops.length, 3);
  assert.equal(summary.patterns.length, 1);
  assert.ok(!JSON.stringify(summary).includes("arrivalSeconds"));
  const page = get(summary.tripPages[0].file);
  assert.equal(page.trips[0].stopTimes[0].departureSeconds, 87031);
  assert.ok(summary.tripPages[0].stopIds.includes(key("feed", "02")));
  const fareFiles = Object.keys(bundle.manifest.assets).filter((f) =>
    f.startsWith(`fares/${shard("A")}-`),
  );
  assert.equal(get(fareFiles[0]).fares[0].rules[0].destinationId, "C");
  assert.equal(
    bundle.manifestChecksum,
    require("./transport_bundle").hash(objects.get(bundle.manifestPath)),
  );
  assert.throws(() =>
    compileBundle({ ...parsed, errors: ["invalid"] }, "feed", parsed.checksum),
  );
});
test("real Yutetsu and Hokkaido Chuo feeds compile without Firestore per-record size constraints", () => {
  for (const [folder, counts] of [
    ["yutetsu_bus", [3, 290, 53, 2542]],
    ["hokkaido_chuo", [185, 3863, 8639, 200801]],
  ]) {
    const dir = path.join(__dirname, "../docs/transport", folder),
      files = Object.fromEntries(
        fs
          .readdirSync(dir)
          .filter((n) => n.endsWith(".txt"))
          .map((n) => [n, fs.readFileSync(path.join(dir, n))]),
      );
    const p = parseFiles(files, folder);
    assert.deepEqual(p.errors, []);
    assert.deepEqual(
      [p.summary.routes, p.summary.stops, p.summary.trips, p.summary.stopTimes],
      counts,
    );
    const b = compileBundle(p, folder, p.checksum);
    assert.ok(b.totalBytes < p.totalBytes);
    assert.ok(b.objects.every((o) => o.bytes.length <= 4 * 1024 * 1024));
  }
});

test("platform labels use real trip headsigns and pickup/dropoff, with immutable timetables unchanged", () => {
  const fs = require("node:fs"),
    path = require("node:path"),
    { buildStopLabels } = require("./transport_stop_labels");
  const dir = path.join(__dirname, "../docs/transport/yutetsu_bus"),
    files = Object.fromEntries(
      fs
        .readdirSync(dir)
        .filter((n) => n.endsWith(".txt"))
        .map((n) => [n, fs.readFileSync(path.join(dir, n))]),
    );
  const p = parseFiles(files, "yutetsu_bus"),
    b = compileBundle(p, "yutetsu_bus", p.checksum),
    label = buildStopLabels(p, "yutetsu_bus", p.checksum),
    data = decodeAsset(label.object.bytes);
  const heads = (id) =>
    Object.values(data.stops[key("yutetsu_bus", id)]).flatMap(
      (r) => r.departures,
    );
  assert.ok(heads("S018100000300100").includes("新夕張駅前"));
  assert.ok(heads("S018100000300200").includes("夕張市石炭博物館"));
  assert.ok(heads("S018100000400100").includes("夕張市石炭博物館"));
  assert.ok(heads("S018100000400200").includes("新夕張駅前"));
  assert.equal(b.platformLabels.checksum, label.descriptor.checksum);
  assert.equal(
    b.manifestChecksum,
    "f9886f6e87f7b79f053af986cdf8c9d76d135edfc1c169733300f3dcab4ab28f",
    "Existing timetable manifest remains unchanged",
  );
  assert.equal(
    b.manifest.assets[label.object.path.split("/").at(-1)],
    undefined,
    "Additional display metadata must not rewrite existing manifest assets",
  );
});
