import { createRequire } from "node:module";
import { join } from "node:path";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { randomBytes, randomUUID } from "node:crypto";
import assert from "node:assert/strict";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Firestore } from "@google-cloud/firestore";
import { GoogleAuth } from "google-auth-library";
import { STUDY } from "../src/domain.js";
const require = createRequire(import.meta.url),
  cli =
    process.env.FIREBASE_TOOLS_PATH ||
    join(process.env.APPDATA, "npm/node_modules/firebase-tools");
const auth = require(join(cli, "lib/auth.js")),
  cliApi = require(join(cli, "lib/api.js")),
  account = auth.getGlobalDefaultAccount();
const project = "estudio-tatuajes-newzenda";
const config = JSON.parse(readFileSync("../config/firebase.qa.json", "utf8"));
const credential = new GoogleAuth({
  credentials: {
    type: "authorized_user",
    client_id: cliApi.clientId(),
    client_secret: cliApi.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  },
});
const db = new Firestore({ projectId: project, auth: credential });
initializeApp({
  projectId: project,
  credential: {
    getAccessToken: async () => ({
      access_token: (
        await auth.getAccessToken(account.tokens.refresh_token, [
          "https://www.googleapis.com/auth/cloud-platform",
          "https://www.googleapis.com/auth/firebase",
        ])
      ).access_token,
      expires_in: 3500,
    }),
  },
});
mkdirSync("../artifacts", { recursive: true });
const credentialsFile = "../artifacts/qa-browser-credentials.local.json";
if (process.argv.includes("--cleanup")) {
  let nextPageToken;
  do {
    const page = await getAuth().listUsers(1000, nextPageToken);
    for (const u of page.users) {
      if (
        /^smoke_\d+_(admin|reception|artist|auditor)@example\.test$/.test(
          u.email || "",
        ) &&
        u.displayName?.startsWith("QA ficticio ")
      ) {
        await getAuth().updateUser(u.uid, { disabled: true });
        const ref = db.doc(`studies/${STUDY}/members/${u.uid}`);
        if ((await ref.get()).exists) await ref.update({ active: false });
      }
    }
    nextPageToken = page.pageToken;
  } while (nextPageToken);
  console.log("Temporary QA test users disabled.");
  process.exit(0);
}
const users = [];
const run = `smoke_${Date.now()}`;
for (const role of ["admin", "reception", "artist", "auditor"]) {
  const email = `${run}_${role}@example.test`,
    password = randomBytes(24).toString("base64url");
  const user = await getAuth().createUser({
    email,
    password,
    emailVerified: true,
    displayName: `QA ficticio ${role}`,
  });
  await db.doc(`studies/${STUDY}/members/${user.uid}`).set({
    id: user.uid,
    email,
    role,
    active: true,
    artistId: role === "artist" ? "artist_ada" : "",
    studyId: STUDY,
  });
  const login = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await login.json();
  assert(body.idToken, JSON.stringify(body.error));
  users.push({ uid: user.uid, role, email, password, token: body.idToken });
}
writeFileSync(
  credentialsFile,
  JSON.stringify({ users: users.map(({ token, ...u }) => u) }, null, 2),
);
async function call(role, name, data = {}) {
  const token = users.find((u) => u.role === role)?.token;
  const res = await fetch(
    `https://us-central1-${project}.cloudfunctions.net/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ data }),
    },
  );
  const b = await res.json();
  if (b.error) {
    const e = new Error(b.error.message);
    e.code = b.error.status;
    throw e;
  }
  return b.result;
}
const command = (
  action,
  payload,
  idempotencyKey = `${run}_${randomUUID()}`,
  role = "admin",
) => call(role, "findinkCommand", { action, payload, idempotencyKey });
const at = new Date().toISOString(),
  payment = (amount) => ({
    amount,
    at,
    methodId: "cash",
    accountId: "cashbox",
  });
const reportDay = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/Bogota",
}).format(new Date());
const baseline = (
  await call("auditor", "findinkReport", { from: reportDay, to: reportDay })
).totals;
const checks = [];
async function verify(name, fn) {
  await fn();
  checks.push(name);
  console.log(`PASS ${name}`);
}
await verify("Unauthenticated requests denied", async () => {
  await assert.rejects(
    call(null, "findinkSession"),
    (e) => e.code === "UNAUTHENTICATED",
  );
});
await verify("Email/password and memberships for all four roles", async () => {
  for (const user of users)
    assert.equal((await call(user.role, "findinkSession")).role, user.role);
});
await verify(
  "Reception cannot change configuration; auditor cannot sell; artist cannot read sales",
  async () => {
    await assert.rejects(
      command("saveBed", { name: "not allowed" }, `${run}_denied`, "reception"),
      (e) => e.code === "PERMISSION_DENIED",
    );
    await assert.rejects(
      command("sale", {}, `${run}_denied_auditor`, "auditor"),
      (e) => e.code === "PERMISSION_DENIED",
    );
    await assert.rejects(
      call("artist", "findinkQuery", { collection: "sales" }),
      (e) => e.code === "PERMISSION_DENIED",
    );
  },
);
const salesId = `${run}_sale`;
await verify(
  "Mixed sale, two payments and exact retry in deployed Functions",
  async () => {
    const payload = {
      at,
      clientName: "Cliente QA ficticio",
      lines: [
        {
          itemId: "tattoo",
          artistId: "artist_ada",
          quantity: 1,
          price: 200000,
        },
        { itemId: "cream", quantity: 1, price: 25000 },
      ],
      payment: payment(100000),
    };
    await command("sale", payload, salesId, "reception");
    await command("sale", payload, salesId, "reception");
    await command(
      "salePayment",
      { id: salesId, ...payment(125000) },
      `${run}_payment`,
      "reception",
    );
    const sale = (
      await call("admin", "findinkQuery", {
        collection: "sales",
        entityId: salesId,
      })
    ).rows[0];
    assert.equal(sale.balance, 0);
    assert.equal(sale.payments.length, 2);
  },
);
await verify("Artist cannot request another artist participation", async () => {
  const own = await call("artist", "findinkQuery", {
    collection: "accruals",
    artistId: "artist_leo",
  });
  assert(own.rows.every((r) => r.artistId === "artist_ada"));
});
await verify("Void reverses stock, cash and balances with trace", async () => {
  await command(
    "saleVoid",
    { id: salesId, at, reason: "Reverso de prueba QA" },
    `${run}_void`,
  );
  const sale = (
    await call("admin", "findinkQuery", {
      collection: "sales",
      entityId: salesId,
    })
  ).rows[0];
  assert.equal(sale.status, "void");
  assert.equal(sale.reversal.refunded, 225000);
});
const purchaseId = `${run}_purchase`;
await verify("Purchase received unpaid and paid exactly once", async () => {
  await command(
    "purchase",
    {
      at,
      categoryId: "supplies",
      supplier: "Proveedor QA",
      lines: [{ itemId: "needle", quantity: 2, cost: 3500 }],
    },
    purchaseId,
  );
  await command(
    "payablePayment",
    { id: purchaseId, ...payment(7000) },
    `${run}_purchase_pay`,
  );
  await command(
    "payablePayment",
    { id: purchaseId, ...payment(7000) },
    `${run}_purchase_pay`,
  );
  const row = (
    await call("admin", "findinkQuery", {
      collection: "payables",
      entityId: purchaseId,
    })
  ).rows[0];
  assert.equal(row.balance, 0);
  assert.equal(row.payments.length, 1);
  await command(
    "payableVoid",
    { id: purchaseId, at, reason: "Reverso QA" },
    `${run}_purchase_void`,
  );
});
await verify(
  "Indexed reports return reconciled daily totals for auditor",
  async () => {
    const report = await call("auditor", "findinkReport", {
      from: reportDay,
      to: reportDay,
    });
    for (const key of ["gross", "cash", "net"])
      assert.equal(report.totals[key] || 0, baseline[key] || 0);
  },
);
writeFileSync(
  "../artifacts/qa-smoke-results.json",
  JSON.stringify({ at: new Date().toISOString(), project, checks }, null, 2),
);
console.log(
  "QA remote smoke completed; temporary browser users retained until --cleanup.",
);
