const { test } = require("node:test");
const assert = require("node:assert/strict");
const { parseGtfs, seconds, csv, key } = require("./gtfs");
const { admin } = require("./transport_import");
const { fixture } = require("./test_support/gtfs_fixture");

test("preserves string IDs, intermediate times, seconds, zones, exceptions and patterns", () => {
  const p = parseGtfs(fixture(), "yutetsu");
  assert.deepEqual(p.errors, []);
  assert.equal(p.data.trips[0].tripId, "0001");
  assert.equal(p.data.stops.length, 3);
  assert.notEqual(p.data.stops[0].id, p.data.stops[2].id);
  assert.equal(p.data.trips[0].stopTimes[0].departureSeconds, 87031);
  assert.equal(p.data.trips[0].stopTimes.length, 3);
  assert.equal(p.data.stops[1].routeIds[0], key("yutetsu", "01"));
  assert.equal(p.data.fares[0].rules[0].originId, "A");
  assert.deepEqual(p.data.services[0].removedDates, ["2026-01-02"]);
  assert.deepEqual(p.data.services[0].addedDates, ["2026-01-03"]);
  assert.equal(p.data.patterns.length, 1);
});
test("calendar_dates alone is supported; unknown optional files warn", () => {
  const f = fixture();
  delete f["calendar.txt"];
  f["shapes.txt"] = "unknown";
  const p = parseGtfs(f, "test");
  assert.deepEqual(p.errors, []);
  assert.ok(p.warnings.some((w) => w.includes("shapes")));
});
test("errors contain file and physical row; invalid references and duplicate IDs block import", () => {
  const f = fixture();
  f["stops.txt"] += "01,重複,43,141,A\n";
  f["stop_times.txt"] += "missing,12:00:00,12:00:00,01,10,0,0\n";
  const p = parseGtfs(f, "test");
  assert.ok(p.errors.some((e) => e.includes("stops.txt:5")));
  assert.ok(p.errors.some((e) => e.includes("参照先なし")));
});
test("CSV BOM, quotes, embedded newlines and CRLF", () => {
  assert.equal(csv('\uFEFFid,name\r\n01,"a,\nb"\r\n', "test")[0].name, "a,\nb");
  assert.throws(() => csv('id,name\n01,"bad', "test"));
  assert.throws(() => seconds("25:60:01"));
  assert.equal(seconds("25:01:59"), 90119);
  assert.notEqual(key("a", "001"), key("b", "001"));
});
test("untrusted, unverified and anonymous administrators rejected on server", () => {
  for (const auth of [
    null,
    { token: { email: "user@test", email_verified: true } },
    { token: { email: "nichi-ka@nichi-ka.com", email_verified: false } },
    {
      token: {
        email: "nichi-ka@nichi-ka.com",
        email_verified: true,
        firebase: { sign_in_provider: "anonymous" },
      },
    },
  ])
    assert.throws(() => admin({ auth }));
  assert.doesNotThrow(() =>
    admin({
      auth: { token: { email: "nichi-ka@nichi-ka.com", email_verified: true } },
    }),
  );
});

test("frequency templates are marked rather than misrepresented as scheduled trips", () => {
  const files = fixture();
  files["frequencies.txt"] =
    "trip_id,start_time,end_time,headway_secs\n0001,08:00:00,10:00:00,600\n";
  const result = parseGtfs(files, "test");
  assert.deepEqual(result.errors, []);
  assert.equal(result.data.trips[0].frequencyBased, true);
  assert.ok(result.warnings.some((w) => w.includes("frequencies")));
});

test("passes remain isolated from single fares and missing extension IDs are never joined", () => {
  const f = fixture();
  f["pass_attributes.txt"] = "pass_id,price\n01,10000\n02,20000\n";
  f["pass_rules.txt"] = "pass_id,route_id\n02,01\n";
  const p = parseGtfs(f, "test");
  assert.equal(p.data.fares.length, 1);
  assert.equal(p.data.passes.length, 2);
  assert.equal(p.data.passes[0].rules.length, 0);
  assert.equal(p.data.passes[1].rules.length, 1);
  f["pass_attributes.txt"] = "custom_id,price\nx,10000\n";
  f["pass_rules.txt"] = "custom_id,route_id\nx,01\n";
  assert.equal(parseGtfs(f, "test").data.passes[0].rules.length, 0);
});
