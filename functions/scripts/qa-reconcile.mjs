import { readFileSync, writeFileSync } from "node:fs";
import assert from "node:assert/strict";
const config = JSON.parse(readFileSync("../config/firebase.qa.json", "utf8"));
const credentials = JSON.parse(
  readFileSync("../artifacts/qa-browser-credentials.local.json", "utf8"),
);
const user = credentials.users.find((u) => u.role === "admin");
const login = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.apiKey}`,
  {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: user.email,
      password: user.password,
      returnSecureToken: true,
    }),
  },
);
const signed = await login.json();
assert(signed.idToken, "QA test sign-in failed");
async function call(name, data) {
  const r = await fetch(
    `https://us-central1-estudio-tatuajes-newzenda.cloudfunctions.net/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${signed.idToken}`,
      },
      body: JSON.stringify({ data }),
    },
  );
  const b = await r.json();
  if (b.error) throw new Error(b.error.message);
  return b.result;
}
let cursor;
const reversed = [];
do {
  const page = await call("findinkQuery", {
    collection: "sales",
    ...(cursor ? { cursor } : {}),
  });
  for (const s of page.rows) {
    if (
      s.clientName === "Cliente ficticio de prueba de navegador" &&
      s.status === "confirmed" &&
      s.createdBy === user.uid
    ) {
      await call("findinkCommand", {
        action: "saleVoid",
        payload: {
          id: s.id,
          at: new Date().toISOString(),
          reason: "Cierre de pruebas automatizadas del formulario QA",
        },
        idempotencyKey: `cleanup_${s.id}`,
      });
      reversed.push(s.id);
    }
  }
  cursor = page.nextCursor;
} while (cursor);
const r = await call("findinkReport", { from: "2026-09-26", to: "2026-09-26" });
const expected = {
  gross: 375000,
  studio: 86000,
  artistGenerated: 289000,
  artistPaid: 50000,
  cogs: 12000,
  expenses: 30000,
  net: 44000,
  cash: 215000,
  receivable: 100000,
  payable: 55000,
};
for (const [k, v] of Object.entries(expected))
  assert.equal(r.totals[k], v, `Demo reconciliation: ${k}`);
writeFileSync(
  "../artifacts/qa-reconciliation.json",
  JSON.stringify(
    { at: new Date().toISOString(), reversed, expected, actual: r.totals },
    null,
    2,
  ),
);
console.log(
  "PASS QA demo reconciles: gross 375000, net 44000, cash 215000, CxC 100000, CxP 55000.",
);
