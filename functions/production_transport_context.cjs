"use strict";
const fs = require("node:fs"),
  { execFileSync } = require("node:child_process"),
  { createRequire } = require("node:module");
const projectId = "sightseeing-matching-prototype",
  bucketName = `${projectId}.firebasestorage.app`;
function context() {
  const configured = JSON.parse(fs.readFileSync(".firebaserc", "utf8")).projects
    .default;
  if (configured !== projectId) throw Error("Firebase接続先が想定と異なります");
  const cli = fs.realpathSync(
      execFileSync("which", ["firebase"], { encoding: "utf8" }).trim(),
    ),
    req = createRequire(cli),
    auth = req("../auth.js"),
    account = auth.getProjectDefaultAccount(process.cwd());
  if (!account) throw Error("Firebase CLIへのログインが必要です");
  const api = req("../api.js");
  const credentials = {
    type: "authorized_user",
    client_id: api.clientId(),
    client_secret: api.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  };
  const { Firestore } = require("@google-cloud/firestore"),
    { Storage } = require("@google-cloud/storage");
  const db = new Firestore({ projectId, credentials, preferRest: true }),
    bucket = new Storage({
      projectId,
      credentials,
      retryOptions: { maxRetries: 2, totalTimeout: 60 },
    }).bucket(bucketName);
  return { projectId, bucketName, db, bucket };
}
module.exports = { context };
