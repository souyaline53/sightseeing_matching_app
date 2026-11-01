"use strict";
const assert = require("node:assert/strict");
if (
  !/^(127\.0\.0\.1|localhost):\d+$/.test(
    process.env.FIRESTORE_EMULATOR_HOST || "",
  )
)
  throw Error("Local emulator required");
const project = "demo-tabisaki-gtfs";
const db = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${project}/databases/(default)/documents`;
const auth = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const storage = `http://127.0.0.1:9199/v0/b/${project}.appspot.com/o`;
async function request(url, { token, ...options } = {}) {
  const r = await fetch(url, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });
  return { status: r.status, body: await r.json().catch(() => ({})) };
}
async function signup(email) {
  const r = await request(`${auth}/accounts:signUp?key=emulator`, {
    method: "POST",
    body: JSON.stringify({
      email,
      password: "abcdef",
      returnSecureToken: true,
    }),
  });
  assert.equal(r.status, 200);
  return r.body;
}
const fields = {
  name: { stringValue: "test" },
  sourceType: { stringValue: "manual" },
};
async function write(path, token, values = fields) {
  return request(`${db}/${path}`, {
    method: "PATCH",
    token,
    body: JSON.stringify({ fields: values }),
  });
}
(async () => {
  const other = await signup("reader@test.example");
  let admin = await signup("nichi-ka@nichi-ka.com");
  assert.equal(
    (await write("transport_agencies/denied", other.idToken)).status,
    403,
  );
  assert.equal(
    (await write("transport_agencies/unverified", admin.idToken)).status,
    403,
  );
  await request(`${auth}/accounts:update?key=emulator`, {
    token: "owner",
    method: "POST",
    body: JSON.stringify({ localId: admin.localId, emailVerified: true }),
  });
  admin = (
    await request(`${auth}/accounts:signInWithPassword?key=emulator`, {
      method: "POST",
      body: JSON.stringify({
        email: admin.email,
        password: "abcdef",
        returnSecureToken: true,
      }),
    })
  ).body;
  assert.equal(
    (await write("transport_agencies/manual", admin.idToken)).status,
    403,
    "手動登録もサーバー専用",
  );
  assert.equal(
    (
      await write("transport_agencies/gtfs", admin.idToken, {
        ...fields,
        sourceType: { stringValue: "gtfs" },
      })
    ).status,
    403,
  );
  await write("transport_feeds/rules", "owner", {
    activeVersionId: { stringValue: "v1" },
  });
  for (const version of ["v1", "v2"])
    await write(
      `transport_feeds/rules/versions/${version}/transport_stops/a`,
      "owner",
    );
  assert.equal(
    (await request(`${db}/transport_feeds/rules/versions/v1/transport_stops/a`))
      .status,
    200,
  );
  assert.equal(
    (await request(`${db}/transport_feeds/rules/versions/v2/transport_stops/a`))
      .status,
    403,
  );
  assert.equal(
    (await write("transport_feeds/rules", admin.idToken)).status,
    403,
  );
  assert.equal(
    (
      await write(
        "transport_feeds/rules/versions/v1/transport_stops/a",
        admin.idToken,
      )
    ).status,
    403,
  );
  const path = `transport_imports/${admin.localId}/rules/test.zip`;
  async function upload(token, name = path, type = "application/zip") {
    return request(
      `${storage}?uploadType=media&name=${encodeURIComponent(name)}`,
      {
        token,
        method: "POST",
        headers: { "Content-Type": type, "X-Goog-Upload-Protocol": "raw" },
        body: Buffer.from("PK fake test bytes"),
      },
    );
  }
  assert.equal((await upload(other.idToken)).status, 403);
  assert.equal((await upload(admin.idToken, path, "text/plain")).status, 403);
  assert.equal((await upload(admin.idToken)).status, 200);
  assert.equal((await upload(admin.idToken)).status, 403, "原本の上書きは禁止");
  assert.equal(
    (await request(`${storage}/${encodeURIComponent(path)}?alt=media`)).status,
    403,
  );
  console.log(
    "PASS: non-admin/unverified denial, manual writes, GTFS server-only writes, active-version reads, private immutable ZIP uploads",
  );
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
