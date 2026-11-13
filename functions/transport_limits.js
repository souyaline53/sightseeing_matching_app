'use strict';
const { HttpsError } = require('firebase-functions/v2/https');
// Input to Dify is separate from the 400,000-character Code node OUTPUT limit.
// The workflow must parse transport_data directly rather than echo the full input.
const DEFAULT_MAX_CHARACTERS = 4000000;
const DEFAULT_MAX_BYTES = 4000000;
function transportLimits() {
  const maxCharacters = Number(process.env.DIFY_TRANSPORT_MAX_CHARACTERS ?? DEFAULT_MAX_CHARACTERS);
  const maxBytes = Number(process.env.DIFY_TRANSPORT_MAX_BYTES ?? DEFAULT_MAX_BYTES);
  if (![maxCharacters, maxBytes].every((v) => Number.isSafeInteger(v) && v > 0)) {
    throw new HttpsError('failed-precondition', '交通データの容量設定を確認してください。');
  }
  return { maxCharacters, maxBytes };
}
module.exports = { DEFAULT_MAX_CHARACTERS, DEFAULT_MAX_BYTES, transportLimits };
