// Uses the existing Firebase CLI session in memory. Never prints or persists tokens.
import { createRequire } from "node:module";
import { join } from "node:path";
import { writeFileSync, mkdirSync } from "node:fs";
import { initializeApp } from "firebase-admin/app";
import { Firestore } from "@google-cloud/firestore";
import { GoogleAuth } from "google-auth-library";
import { getAuth } from "firebase-admin/auth";
import { STUDY, hash, execute } from "../src/domain.js";
const require = createRequire(import.meta.url);
const cli =
  process.env.FIREBASE_TOOLS_PATH ||
  join(process.env.APPDATA || "", "npm/node_modules/firebase-tools");
const auth = require(join(cli, "lib/auth.js"));
const account = auth.getGlobalDefaultAccount();
if (!account) throw new Error("Inicia sesión con firebase login.");
const cliApi = require(join(cli, "lib/api.js"));
const googleAuth = new GoogleAuth({
  credentials: {
    type: "authorized_user",
    client_id: cliApi.clientId(),
    client_secret: cliApi.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  },
});
async function token() {
  return (
    await auth.getAccessToken(account.tokens.refresh_token, [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/firebase",
    ])
  ).access_token;
}
const project = "estudio-tatuajes-newzenda";
async function api(url, method = "GET", body) {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${await token()}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  if (!res.ok)
    throw new Error(
      `${res.status}: ${data.error?.message || "Cloud request failed"}`,
    );
  return data;
}
const task = process.argv[2];
if (task === "enable") {
  for (const service of [
    "firestore.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
  ]) {
    await api(
      `https://serviceusage.googleapis.com/v1/projects/${project}/services/${service}:enable`,
      "POST",
      {},
    );
    console.log(`Enabled ${service}`);
  }
} else if (task === "config") {
  const apps = await api(
    `https://firebase.googleapis.com/v1beta1/projects/${project}/webApps`,
  );
  const web = apps.apps.find((a) => a.displayName === "Findink House QA Web");
  const c = await api(
    `https://firebase.googleapis.com/v1beta1/${web.name}/config`,
  );
  const android = (
    await api(
      `https://firebase.googleapis.com/v1beta1/projects/${project}/androidApps`,
    )
  ).apps[0];
  const ios = (
    await api(
      `https://firebase.googleapis.com/v1beta1/projects/${project}/iosApps`,
    )
  ).apps[0];
  const config = {
    projectId: project,
    apiKey: c.apiKey,
    appId: c.appId,
    messagingSenderId: c.messagingSenderId,
    authDomain: c.authDomain,
    storageBucket: c.storageBucket,
    androidAppId: android.appId,
    iosAppId: ios.appId,
    iosBundleId: ios.bundleId,
  };
  mkdirSync("../config", { recursive: true });
  writeFileSync("../config/firebase.qa.json", JSON.stringify(config, null, 2));
  const aconfig = await api(
    `https://firebase.googleapis.com/v1beta1/${android.name}/config`,
  );
  writeFileSync(
    "../android/app/google-services.json",
    Buffer.from(aconfig.configFileContents, "base64"),
  );
  const androidConfig = JSON.parse(
    Buffer.from(aconfig.configFileContents, "base64").toString(),
  );
  config.googleWebClientId = androidConfig.client[0].oauth_client.find(
    (c) => c.client_type === 3,
  )?.client_id;
  config.androidApiKey = androidConfig.client[0].api_key[0].current_key;
  writeFileSync("../config/firebase.qa.json", JSON.stringify(config, null, 2));
  const iconfig = await api(
    `https://firebase.googleapis.com/v1beta1/${ios.name}/config`,
  );
  writeFileSync(
    "../ios/Runner/GoogleService-Info.plist",
    Buffer.from(iconfig.configFileContents, "base64"),
  );
  const plist = Buffer.from(iconfig.configFileContents, "base64").toString();
  const plistValue = (key) =>
    plist.match(
      new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`),
    )?.[1];
  config.iosApiKey = plistValue("API_KEY");
  config.iosClientId = plistValue("CLIENT_ID");
  writeFileSync("../config/firebase.qa.json", JSON.stringify(config, null, 2));
  console.log("Firebase public client configurations written.");
} else if (task === "domains") {
  const url = `https://identitytoolkit.googleapis.com/admin/v2/projects/${project}/config`;
  const c = await api(url);
  const domains = [
    ...new Set([
      ...(c.authorizedDomains || []),
      "estudio-tatuajes-newzenda-qa.web.app",
      "estudio-tatuajes-newzenda-qa.firebaseapp.com",
      "localhost",
    ]),
  ];
  await api(`${url}?updateMask=authorizedDomains`, "PATCH", {
    authorizedDomains: domains,
  });
  console.log("QA authentication domains configured.");
} else if (task === "bootstrap") {
  const email = process.argv[3]?.toLowerCase();
  if (!email?.includes("@")) throw new Error("Supply administrator email.");
  initializeApp({
    projectId: project,
    credential: {
      getAccessToken: async () => ({
        access_token: await token(),
        expires_in: 3500,
      }),
    },
  });
  const db = new Firestore({ projectId: project, auth: googleAuth });
  const root = `studies/${STUDY}`;
  await db
    .doc(`${root}/invitations/${hash(email)}`)
    .set({ email, role: "admin", artistId: "", active: true, studyId: STUDY });
  // Do not create a password or send any email; the owner can use their Google account.
  try {
    const user = await getAuth().getUserByEmail(email);
    await db
      .doc(`${root}/members/${user.uid}`)
      .set({
        id: user.uid,
        email,
        role: "admin",
        artistId: "",
        active: true,
        studyId: STUDY,
      });
    console.log("Existing administrator membership configured.");
  } catch (e) {
    if (e.code !== "auth/user-not-found") throw e;
    console.log("Administrator invitation ready for Google sign-in.");
  }
} else if (task === "seed" || task === "demo") {
  initializeApp({
    projectId: project,
    credential: {
      getAccessToken: async () => ({
        access_token: await token(),
        expires_in: 3500,
      }),
    },
  });
  const db = new Firestore({ projectId: project, auth: googleAuth });
  const root = `studies/${STUDY}`;
  const uid = "qa_seed_operator";
  const at = "2026-09-26T15:00:00Z",
    pay = (amount) => ({
      amount,
      at,
      methodId: "cash",
      accountId: "cashbox",
      reference: "Demostración ficticia",
    });
  const fixture =
    task === "seed"
      ? JSON.parse(
          (await import("node:fs")).readFileSync(
            "test/fixtures/seed.json",
            "utf8",
          ),
        )
      : [
          {
            action: "reserve",
            payload: {
              day: "2026-09-28",
              mode: "am",
              kind: "appointment",
              bedId: "bed_a",
              artistId: "artist_ada",
              clientName: "Cliente demo A",
              design: "Botánico · ejemplo ficticio",
            },
          },
          {
            action: "reserve",
            payload: {
              day: "2026-09-28",
              mode: "pm",
              kind: "reservation",
              bedId: "bed_b",
              artistId: "artist_leo",
              clientName: "Cliente demo B",
            },
          },
          {
            action: "deposit",
            payload: { ...pay(30000), clientName: "Cliente demo A" },
          },
          {
            action: "sale",
            payload: {
              at,
              clientName: "Cliente demo A",
              depositId: "qa_demo_2",
              lines: [
                {
                  itemId: "tattoo",
                  artistId: "artist_ada",
                  quantity: 1,
                  price: 200000,
                },
                { itemId: "cream", quantity: 1, price: 25000 },
              ],
              payment: {
                ...pay(95000),
                methodId: "transfer",
                accountId: "bank",
              },
            },
          },
          {
            action: "sale",
            payload: {
              at,
              clientName: "Cliente demo B",
              lines: [
                {
                  itemId: "tattoo",
                  artistId: "artist_leo",
                  quantity: 1,
                  price: 150000,
                },
              ],
              payment: pay(150000),
            },
          },
          {
            action: "purchase",
            payload: {
              at,
              categoryId: "supplies",
              supplier: "Proveedor ficticio",
              folio: "DEMO-COMPRA",
              lines: [{ itemId: "needle", quantity: 10, cost: 3500 }],
            },
          },
          {
            action: "expense",
            payload: {
              at,
              categoryId: "other",
              description: "Gasto operativo ficticio",
              amount: 30000,
              payment: pay(10000),
            },
          },
          {
            action: "settlement",
            payload: { ...pay(50000), artistId: "artist_ada" },
          },
        ];
  await db
    .doc(`${root}/members/${uid}`)
    .set({ id: uid, role: "admin", active: true, studyId: STUDY });
  try {
    for (const [i, command] of fixture.entries())
      await db.runTransaction((tx) =>
        execute(
          {
            get: async (path) =>
              (await tx.get(db.doc(`${root}/${path}`))).data(),
            set: (path, v) => tx.set(db.doc(`${root}/${path}`), v),
          },
          uid,
          command.action,
          command.payload,
          `qa_${task}_${i}`,
        ),
      );
    console.log("Fictitious QA data applied idempotently.");
  } finally {
    await db
      .doc(`${root}/members/${uid}`)
      .set({ id: uid, role: "admin", active: false, studyId: STUDY });
  }
} else
  throw new Error("Task: enable, config, domains, bootstrap <email>, seed");
