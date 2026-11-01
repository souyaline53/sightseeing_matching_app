// Development utility. Reads a ZIP or a directory of .txt files; never connects to Firebase.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { unzip, parseGtfs } = require("./gtfs");
const input = process.argv[2];
if (!input) {
  console.error(
    "Usage: node functions/validate_gtfs.js <ZIP or directory> [feedId] [--expect-yutetsu]",
  );
  process.exit(2);
}
try {
  const files = fs.statSync(input).isDirectory()
    ? Object.fromEntries(
        fs
          .readdirSync(input)
          .filter((name) => name.endsWith(".txt"))
          .map((name) => [
            name,
            new TextDecoder("utf-8", { fatal: true }).decode(
              fs.readFileSync(path.join(input, name)),
            ),
          ]),
      )
    : unzip(fs.readFileSync(input));
  const result = parseGtfs(
    files,
    process.argv[3] && !process.argv[3].startsWith("--")
      ? process.argv[3]
      : "validation",
  );
  if (process.argv.includes("--expect-yutetsu"))
    for (const [field, count] of Object.entries({
      routes: 3,
      stops: 290,
      trips: 53,
      stopTimes: 2542,
    }))
      if (result.summary[field] !== count)
        result.errors.push(
          `${field}: expected ${count}, actual ${result.summary[field]}`,
        );
  console.log(
    JSON.stringify(
      {
        summary: result.summary,
        errors: result.errors,
        warnings: result.warnings,
      },
      null,
      2,
    ),
  );
  if (result.errors.length) process.exitCode = 1;
} catch (e) {
  console.error(e.message);
  process.exitCode = 1;
}
