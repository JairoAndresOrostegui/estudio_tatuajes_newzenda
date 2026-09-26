import { initializeApp } from "firebase-admin/app";
import {
  getFirestore,
  FieldValue,
  AggregateField,
} from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import {
  STUDY,
  Unit,
  execute,
  check,
  hash,
  id,
  date,
  summarize,
  DomainError,
} from "./domain.js";

initializeApp();
setGlobalOptions({
  region: "us-central1",
  maxInstances: 5,
  minInstances: 0,
  memory: "256MiB",
  timeoutSeconds: 60,
});
const db = getFirestore();
const root = db.collection("studies").doc(STUDY);
function adapter(tx) {
  return {
    get: async (path) => {
      const s = await tx.get(db.doc(`${root.path}/${path}`));
      return s.exists ? s.data() : undefined;
    },
    set: (path, value) =>
      tx.set(db.doc(`${root.path}/${path}`), {
        ...value,
        serverUpdatedAt: FieldValue.serverTimestamp(),
      }),
  };
}
function wrap(fn) {
  return onCall(async (req) => {
    try {
      check(req.auth, "Inicia sesión para continuar.", "unauthenticated");
      return await fn(req);
    } catch (e) {
      if (e instanceof DomainError) throw new HttpsError(e.code, e.message);
      console.error("Findink request failed", e.code || e.name);
      throw new HttpsError(
        "internal",
        "No fue posible completar la operación. Reintenta con la misma solicitud.",
      );
    }
  });
}
async function membership(uid) {
  const snap = await root.collection("members").doc(uid).get();
  const m = snap.data();
  check(
    m?.active && m.studyId === STUDY,
    "Tu cuenta no tiene acceso activo. Solicita el alta al administrador.",
    "permission-denied",
  );
  return m;
}

export const findinkCommand = wrap(async (req) => {
  const { action, payload, idempotencyKey } = req.data || {};
  return db.runTransaction((tx) =>
    execute(adapter(tx), req.auth.uid, action, payload, idempotencyKey),
  );
});

export const findinkSession = wrap(async (req) =>
  db.runTransaction(async (tx) => {
    const u = new Unit(adapter(tx), new Date().toISOString(), req.auth.uid);
    let m = await u.get(`members/${req.auth.uid}`);
    if (!m) {
      const email = req.auth.token.email?.toLowerCase();
      check(
        email && req.auth.token.email_verified,
        "Verifica tu correo para activar el acceso.",
        "permission-denied",
      );
      const invitation = await u.get(`invitations/${hash(email)}`);
      check(
        invitation?.active,
        "Tu correo no tiene una invitación activa.",
        "permission-denied",
      );
      m = {
        id: req.auth.uid,
        email,
        role: invitation.role,
        artistId: invitation.artistId || "",
        active: true,
        studyId: STUDY,
      };
      u.put(`members/${m.id}`, m);
      u.put(`invitations/${hash(email)}`, {
        ...invitation,
        active: false,
        acceptedBy: m.id,
      });
      u.put(`audit/join_${m.id}`, {
        id: `join_${m.id}`,
        action: "acceptInvitation",
        actorId: m.id,
        createdAt: u.now,
      });
      await u.flush();
    }
    check(m.active, "Tu acceso está deshabilitado.", "permission-denied");
    return m;
  }),
);

const readCollections = new Set([
  "settings",
  "beds",
  "artists",
  "catalog",
  "appointments",
  "sales",
  "payables",
  "movements",
  "ledger",
  "accruals",
  "settlements",
  "artistBalances",
  "deposits",
  "members",
  "invitations",
  "audit",
  "imports",
  "ruleVersions",
]);
export const findinkCreateUser = wrap(async (req) => {
  const m = await membership(req.auth.uid);
  check(
    m.role === "admin",
    "Sólo el administrador puede crear usuarios.",
    "permission-denied",
  );
  const { email, password, role, artistId = "" } = req.data || {};
  check(
    typeof email === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email),
    "Correo inválido.",
    "invalid-argument",
  );
  check(
    typeof password === "string" &&
      password.length >= 12 &&
      password.length <= 128,
    "La contraseña temporal debe tener entre 12 y 128 caracteres.",
    "invalid-argument",
  );
  check(
    ["admin", "reception", "artist", "auditor"].includes(role),
    "Rol inválido.",
  );
  if (role === "artist")
    check(
      (await root.collection("artists").doc(id(artistId)).get()).exists,
      "Artista no encontrado.",
    );
  const uid = `managed_${hash(email.trim().toLowerCase()).slice(0, 32)}`;
  try {
    await getAuth().createUser({
      uid,
      email: email.trim().toLowerCase(),
      password,
    });
  } catch (e) {
    if (e.code !== "auth/uid-already-exists")
      throw new DomainError(
        e.code === "auth/email-already-exists"
          ? "La cuenta ya existe. Usa Autorizar correo para asignar el acceso."
          : "No se pudo crear la cuenta.",
        "already-exists",
      );
  }
  await db.runTransaction(async (tx) => {
    const current = await tx.get(root.collection("members").doc(req.auth.uid));
    check(
      current.data()?.active && current.data()?.role === "admin",
      "Acceso administrativo revocado.",
      "permission-denied",
    );
    const existing = await tx.get(root.collection("members").doc(uid));
    if (existing.exists) return;
    tx.set(root.collection("members").doc(uid), {
      id: uid,
      email: email.trim().toLowerCase(),
      role,
      artistId: role === "artist" ? artistId : "",
      active: true,
      studyId: STUDY,
      createdAt: new Date().toISOString(),
      serverUpdatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(root.collection("audit").doc(`create_${uid}`), {
      id: `create_${uid}`,
      action: "createUser",
      actorId: req.auth.uid,
      entityId: uid,
      studyId: STUDY,
      createdAt: new Date().toISOString(),
    });
  });
  return { id: uid };
});
const artistCollections = new Set([
  "appointments",
  "accruals",
  "settlements",
  "artistBalances",
]);
const adminCollections = new Set([
  "members",
  "invitations",
  "audit",
  "imports",
  "ruleVersions",
]);
export const findinkQuery = wrap(async (req) => {
  const m = await membership(req.auth.uid);
  const p = req.data || {};
  const collection = p.collection;
  check(
    readCollections.has(collection),
    "Consulta inválida.",
    "invalid-argument",
  );
  check(
    !adminCollections.has(collection) || m.role === "admin",
    "Consulta restringida.",
    "permission-denied",
  );
  if (m.role === "auditor")
    check(
      ["artists", "beds", "catalog", "settings", "ledger"].includes(collection),
      "El auditor sólo consulta reportes.",
      "permission-denied",
    );
  if (m.role === "artist") {
    check(
      artistCollections.has(collection) ||
        ["artists", "beds"].includes(collection),
      "Consulta restringida.",
      "permission-denied",
    );
    if (collection === "artists") {
      const a = await root.collection("artists").doc(m.artistId).get();
      return {
        rows: a.exists
          ? [
              {
                id: a.id,
                name: a.data().name,
                styles: a.data().styles,
                bedIds: a.data().bedIds,
              },
            ]
          : [],
        nextCursor: null,
      };
    }
    if (collection === "beds") {
      const a = (await root.collection("artists").doc(m.artistId).get()).data();
      const ids = a?.bedIds || [];
      const docs = await Promise.all(
        ids.map((x) => root.collection("beds").doc(x).get()),
      );
      return {
        rows: docs.filter((s) => s.exists).map((s) => s.data()),
        nextCursor: null,
      };
    }
  }
  let q = root.collection(collection);
  if (m.role === "artist") q = q.where("artistId", "==", m.artistId);
  else if (p.artistId) {
    check(
      ["appointments", "accruals", "settlements", "artistBalances"].includes(
        collection,
      ),
      "Filtro de artista no disponible.",
    );
    q = q.where("artistId", "==", id(p.artistId));
  }
  if (p.itemId) {
    check(collection === "movements", "Filtro de artículo no disponible.");
    q = q.where("itemId", "==", id(p.itemId));
  }
  if (p.day) {
    check(collection === "appointments", "Filtro de día no disponible.");
    q = q.where("day", "==", date(p.day));
  }
  if (p.bedId) {
    check(collection === "appointments", "Filtro de camilla no disponible.");
    q = q.where("bedId", "==", id(p.bedId));
  }
  if (p.entityId) q = q.where("__name__", "==", id(p.entityId));
  q = q.orderBy("__name__");
  if (p.cursor) q = q.startAfter(id(p.cursor));
  const limit = 50;
  const snap = await q.limit(limit + 1).get();
  const rows = snap.docs
    .slice(0, limit)
    .map((s) => ({ id: s.id, ...s.data(), serverUpdatedAt: undefined }));
  // Strip undefined fields to keep callable serialization and Flutter JSON predictable.
  return JSON.parse(
    JSON.stringify({
      rows,
      nextCursor: snap.size > limit ? snap.docs[limit - 1].id : null,
    }),
  );
});

export const findinkReport = wrap(async (req) => {
  const m = await membership(req.auth.uid);
  const { from, to, dimension = "all" } = req.data || {};
  date(from);
  date(to);
  check(
    from <= to && Date.parse(to) - Date.parse(from) <= 366 * 86400000,
    "El rango máximo es de 367 días.",
  );
  check(
    dimension === "all" ||
      /^(artist|category|method|account)_[a-zA-Z0-9_-]+$/.test(dimension),
    "Filtro inválido.",
  );
  if (m.role === "artist")
    check(
      dimension === `artist_${m.artistId}`,
      "Sólo puedes consultar tu producción.",
      "permission-denied",
    );
  const snap = await root
    .collection("daily")
    .where("dimension", "==", dimension)
    .where("day", ">=", from)
    .where("day", "<=", to)
    .orderBy("day")
    .limit(367)
    .get();
  const rows = snap.docs.map((s) => ({
    day: s.data().day,
    metrics: s.data().metrics,
    production: s.data().production || {},
  }));
  let balances = {};
  if (m.role !== "artist")
    balances =
      (await root.collection("balances").doc("current").get()).data()
        ?.metrics || {};
  const production = {};
  for (const r of rows)
    for (const [artist, value] of Object.entries(r.production))
      production[artist] = (production[artist] || 0) + value;
  const top = Object.entries(production).sort((a, b) => b[1] - a[1])[0];
  let inventoryValue = 0;
  const artistBalance = dimension.startsWith("artist_")
    ? (
        await root.collection("artistBalances").doc(dimension.slice(7)).get()
      ).data() || { generated: 0, paid: 0, pending: 0 }
    : null;
  if (m.role !== "artist")
    inventoryValue = (
      await root
        .collection("catalog")
        .aggregate({ value: AggregateField.sum("inventoryValue") })
        .get()
    ).data().value;
  return {
    from,
    to,
    dimension,
    rows,
    totals: summarize(rows),
    balances,
    inventoryValue,
    artistBalance,
    topArtist: top ? { id: top[0], gross: top[1] } : null,
    definitions: {
      net: "Ingresos devengados − parte artista generada − costo vendido − gastos devengados. Los pagos de artistas sólo afectan caja.",
      cash: "Cobros menos desembolsos, incluidos anticipos; no equivale a ingreso devengado.",
      balances:
        "Saldos actuales de todas las fechas, independientes del rango seleccionado.",
    },
  };
});
