"use strict";
const fs = require("node:fs"),
  path = require("node:path");
const { fixture } = require("./gtfs_fixture");
const { parseFiles, compileBundle } = require("../transport_bundle");
const p = parseFiles(fixture(), "feed"),
  b = compileBundle(p, "feed", p.checksum),
  out = process.argv[2];
if (!out) throw Error("output directory required");
for (const o of b.objects) {
  const file = path.join(out, o.path);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, o.bytes);
}
fs.writeFileSync(
  path.join(out, "feed.json"),
  JSON.stringify({
    id: "feed",
    activeVersionId: p.checksum,
    distribution: {
      formatVersion: 2,
      manifestPath: b.manifestPath,
      manifestChecksum: b.manifestChecksum,
      platformLabels: b.platformLabels,
      manifestBytes: b.manifestBytes,
    },
  }),
);
