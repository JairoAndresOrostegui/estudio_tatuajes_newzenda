// Execute an approved, normalized mapping through the same protected API as the UI.
// Input stays local/ignored. Do not put real migration files into git.
// FIREBASE_ID_TOKEN must be a current administrator ID token; it is never printed.
import { readFileSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
const file = process.argv[2];
const approved = process.argv.includes("--approved");
if (!file)
  throw new Error(
    "Usage: node scripts/import-approved.mjs artifacts/mapping.local.json [--approved]",
  );
const rows = JSON.parse(readFileSync(file, "utf8"));
if (!Array.isArray(rows))
  throw new Error(
    "Mapping must be an array of {fileHash,sheet,row,operation,data}.",
  );
const errors = [];
for (const [i, r] of rows.entries()) {
  if (
    !/^[a-f0-9]{64}$/.test(r.fileHash) ||
    !r.sheet ||
    !Number.isInteger(r.row) ||
    r.row < 1 ||
    ![
      "saveCatalog",
      "saveArtist",
      "sale",
      "expense",
      "purchase",
      "deposit",
    ].includes(r.operation) ||
    !r.data
  )
    errors.push({
      entry: i + 1,
      sheet: r.sheet,
      row: r.row,
      field: "mapping",
      message: "Invalid source/operation/data",
    });
}
if (errors.length) {
  writeFileSync(`${file}.errors.json`, JSON.stringify(errors, null, 2));
  throw new Error("Mapping errors written beside source. No rows imported.");
}
console.log(`Validated ${rows.length} normalized rows. Approval: ${approved}.`);
if (!approved) process.exit(0);
const token = process.env.FIREBASE_ID_TOKEN;
if (!token) throw new Error("FIREBASE_ID_TOKEN required for approved import.");
for (const r of rows) {
  const idempotencyKey = randomUUID();
  const res = await fetch(
    "https://us-central1-estudio-tatuajes-newzenda.cloudfunctions.net/findinkCommand",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        data: {
          action: "importRow",
          payload: { ...r, approved: true },
          idempotencyKey,
        },
      }),
    },
  );
  const body = await res.json();
  if (body.error) {
    errors.push({
      sheet: r.sheet,
      row: r.row,
      field: "server",
      message: body.error.message,
    });
    break;
  }
  console.log(`Confirmed source row ${r.row} in ${r.sheet}`);
}
writeFileSync(`${file}.errors.json`, JSON.stringify(errors, null, 2));
if (errors.length) process.exitCode = 1;
