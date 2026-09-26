import test, { before, after } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  getDocs,
  collection,
  query,
  where,
} from "firebase/firestore";
import { initializeApp, deleteApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { execute, STUDY } from "../../src/domain.js";
const projectId = "demo-findink";
let env, app, db;
before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync("../firestore.rules", "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
  app = initializeApp({ projectId }, "test");
  db = getFirestore(app);
  const records = {
    "members/admin": { role: "admin", active: true },
    "members/reception": { role: "reception", active: true },
    "members/ada": { role: "artist", artistId: "artist_ada", active: true },
    "members/auditor": { role: "auditor", active: true },
    "appointments/own": { artistId: "artist_ada" },
    "appointments/other": { artistId: "artist_leo" },
    "daily/example": { dimension: "all" },
    "settings/general": {
      shifts: {
        am: ["08:00", "13:00"],
        pm: ["13:00", "18:00"],
        night: ["20:00", "02:00"],
      },
    },
    "beds/b": { id: "b", active: true },
    "artists/a": { id: "a", active: true, bedIds: ["b"] },
  };
  for (const [p, v] of Object.entries(records))
    await db.doc(`studies/${STUDY}/${p}`).set({ ...v, studyId: STUDY });
});
after(async () => {
  await env.cleanup();
  await deleteApp(app);
});
test("Firestore enforces own artist data, auditor read-only, no client writes, no cross-study", async () => {
  const artist = env.authenticatedContext("ada").firestore();
  const path = `studies/${STUDY}`;
  await assertSucceeds(getDoc(doc(artist, `${path}/appointments/own`)));
  await assertFails(getDoc(doc(artist, `${path}/appointments/other`)));
  await assertFails(getDocs(collection(artist, `${path}/appointments`)));
  await assertSucceeds(
    getDocs(
      query(
        collection(artist, `${path}/appointments`),
        where("artistId", "==", "artist_ada"),
      ),
    ),
  );
  await assertFails(getDoc(doc(artist, `${path}/sales/secret`)));
  const auditor = env.authenticatedContext("auditor").firestore();
  await assertSucceeds(getDoc(doc(auditor, `${path}/daily/example`)));
  await assertFails(
    setDoc(doc(auditor, `${path}/daily/example`), { gross: 1 }),
  );
  for (const uid of ["admin", "reception", "ada"])
    await assertFails(
      setDoc(
        doc(env.authenticatedContext(uid).firestore(), `${path}/sales/hack`),
        { total: 0 },
      ),
    );
  await assertFails(
    getDoc(
      doc(env.unauthenticatedContext().firestore(), `${path}/appointments/own`),
    ),
  );
  await assertFails(getDoc(doc(artist, "studies/foreign/appointments/x")));
});
test("real Firestore concurrent transactions serialize the same bed reservation", async () => {
  const payload = {
    day: "2026-09-26",
    mode: "full",
    kind: "appointment",
    bedId: "b",
    artistId: "a",
  };
  const command = (key) =>
    db.runTransaction((tx) =>
      execute(
        {
          get: async (p) =>
            (await tx.get(db.doc(`studies/${STUDY}/${p}`))).data(),
          set: (p, v) => tx.set(db.doc(`studies/${STUDY}/${p}`), v),
        },
        "reception",
        "reserve",
        payload,
        key,
      ),
    );
  const results = await Promise.allSettled([
    command("concurrent_a"),
    command("concurrent_b"),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.match(
    results.find((r) => r.status === "rejected").reason.message,
    /reserva/,
  );
});
