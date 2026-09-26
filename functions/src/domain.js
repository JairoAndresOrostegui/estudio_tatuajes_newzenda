import { createHash } from "node:crypto";

export const STUDY = "findink-house-qa";
export class DomainError extends Error {
  constructor(message, code = "failed-precondition") {
    super(message);
    this.code = code;
  }
}
export function check(ok, message, code) {
  if (!ok) throw new DomainError(message, code);
}
export function integer(v, name, min = 0, max = 1_000_000_000_000) {
  check(
    Number.isSafeInteger(v) && v >= min && v <= max,
    `${name}: entero entre ${min} y ${max}.`,
    "invalid-argument",
  );
  return v;
}
export function str(v, name, max = 200, optional = false) {
  if (optional && (v == null || v === "")) return "";
  check(
    typeof v === "string" && v.trim().length > 0 && v.length <= max,
    `${name}: texto obligatorio (máximo ${max}).`,
    "invalid-argument",
  );
  return v.trim();
}
export function id(v) {
  v = str(v, "Identificador", 128);
  check(
    /^[a-zA-Z0-9_-]+$/.test(v),
    "Identificador inválido.",
    "invalid-argument",
  );
  return v;
}
export const hash = (v) =>
  createHash("sha256").update(JSON.stringify(v)).digest("hex");
export const percent = (amount, bps) =>
  Number((BigInt(amount) * BigInt(bps) + 5000n) / 10000n);
export function localDate(iso) {
  check(
    typeof iso === "string" &&
      /T.*(Z|[+-]\d\d:\d\d)$/.test(iso) &&
      Number.isFinite(Date.parse(iso)),
    "Fecha ISO con zona horaria requerida.",
    "invalid-argument",
  );
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(iso));
}
export function date(v) {
  check(
    typeof v === "string" &&
      /^\d{4}-\d{2}-\d{2}$/.test(v) &&
      new Date(`${v}T12:00:00Z`).toISOString().slice(0, 10) === v,
    "Fecha inválida.",
    "invalid-argument",
  );
  return v;
}
export function interval(day, mode, shifts) {
  date(day);
  const s = mode === "full" ? [shifts.am?.[0], shifts.pm?.[1]] : shifts[mode];
  check(
    s?.length === 2 && s.every((x) => /^([01]\d|2[0-3]):[0-5]\d$/.test(x)),
    "Configura los horarios de la modalidad.",
  );
  const start = new Date(`${day}T${s[0]}:00-05:00`);
  let end = new Date(`${day}T${s[1]}:00-05:00`);
  if (end <= start) {
    check(mode === "night", "Sólo nocturno puede cruzar medianoche.");
    end = new Date(+end + 86400000);
  }
  return { start: start.toISOString(), end: end.toISOString() };
}
export const overlaps = (a, b) => a.start < b.end && b.start < a.end;
const ops = new Set([
  "reserve",
  "appointmentStatus",
  "sale",
  "salePayment",
  "saleVoid",
  "purchase",
  "expense",
  "payablePayment",
  "payableVoid",
  "movement",
  "deposit",
  "depositRefund",
  "settlement",
]);
const adminOps = new Set([
  "saveCatalog",
  "saveArtist",
  "saveBed",
  "settings",
  "invite",
  "member",
  "importRow",
]);
export function authorize(member, action) {
  check(
    member?.active && member.studyId === STUDY,
    "Tu cuenta no tiene acceso activo al estudio.",
    "permission-denied",
  );
  check(
    member.role === "admin" || (member.role === "reception" && ops.has(action)),
    "Tu rol no permite esta operación.",
    "permission-denied",
  );
  check(
    ops.has(action) || adminOps.has(action),
    "Operación desconocida.",
    "invalid-argument",
  );
}

// Unit of work buffers all writes until every read has completed (Firestore contract).
export class Unit {
  constructor(store, now, uid) {
    this.store = store;
    this.now = now;
    this.uid = uid;
    this.cache = new Map();
    this.writes = new Map();
    this.seq = 0;
  }
  async get(path) {
    if (!this.cache.has(path)) this.cache.set(path, await this.store.get(path));
    return structuredClone(this.cache.get(path));
  }
  put(path, value) {
    const data = { ...value, studyId: STUDY, updatedAt: this.now };
    this.cache.set(path, data);
    this.writes.set(path, data);
    return data;
  }
  async need(path) {
    const v = await this.get(path);
    check(v, "Registro no encontrado.", "not-found");
    return v;
  }
  async flush() {
    for (const [p, v] of this.writes) this.store.set(p, v);
  }
  async journal(key, at, metrics, extra = {}) {
    const day = localDate(at);
    const entryId = `${key}_${this.seq++}`;
    this.put(`ledger/${entryId}`, {
      id: entryId,
      eventAt: at,
      day,
      metrics,
      ...extra,
      createdBy: this.uid,
      createdAt: this.now,
    });
    const dimensions = [
      "all",
      ...(extra.artistId ? [`artist_${extra.artistId}`] : []),
      ...(extra.categoryId ? [`category_${extra.categoryId}`] : []),
      ...(extra.methodId ? [`method_${extra.methodId}`] : []),
      ...(extra.accountId ? [`account_${extra.accountId}`] : []),
    ];
    for (const dimension of dimensions) {
      const path = `daily/${day}_${dimension}`;
      const d = (await this.get(path)) || {
        id: `${day}_${dimension}`,
        day,
        dimension,
        metrics: {},
      };
      for (const [k, v] of Object.entries(metrics))
        d.metrics[k] = integer(
          (d.metrics[k] || 0) + v,
          k,
          -1_000_000_000_000_000,
          1_000_000_000_000_000,
        );
      if (dimension === "all" && extra.artistId && metrics.gross) {
        d.production = d.production || {};
        d.production[extra.artistId] =
          (d.production[extra.artistId] || 0) + metrics.gross;
      }
      this.put(path, d);
    }
    const balance = (await this.get("balances/current")) || { metrics: {} };
    for (const [k, v] of Object.entries(metrics))
      balance.metrics[k] = integer(
        (balance.metrics[k] || 0) + v,
        k,
        -1_000_000_000_000_000,
        1_000_000_000_000_000,
      );
    this.put("balances/current", balance);
  }
  async stock(key, itemId, quantity, reason, reference, cost, valueOverride) {
    const p = await this.need(`catalog/${id(itemId)}`);
    check(p.kind !== "service", "Los servicios no tienen existencias.");
    integer(quantity, "Cantidad", -1_000_000, 1_000_000);
    check(quantity !== 0, "La cantidad no puede ser cero.");
    const oldStock = p.stock || 0,
      oldValue = p.inventoryValue ?? oldStock * p.cost;
    p.stock = integer(oldStock + quantity, "Existencias", 0, 1_000_000_000);
    const totalCost =
      valueOverride ??
      (quantity < 0 && reason !== "purchaseReversal"
        ? Math.min(
            oldValue,
            p.stock === 0 ? oldValue : Math.abs(quantity) * (cost ?? p.cost),
          )
        : Math.abs(quantity) * (cost ?? p.cost));
    p.inventoryValue = integer(
      oldValue + (quantity > 0 ? totalCost : -totalCost),
      "Valor de inventario",
      0,
      1_000_000_000_000,
    );
    if (p.stock > 0)
      p.cost = Number(
        (BigInt(p.inventoryValue) + BigInt(Math.floor(p.stock / 2))) /
          BigInt(p.stock),
      );
    this.put(`catalog/${itemId}`, p);
    const movementId = `${key}_${this.seq++}`;
    this.put(`movements/${movementId}`, {
      id: movementId,
      itemId,
      quantity,
      unitCost: cost ?? p.cost,
      totalCost,
      stockAfter: p.stock,
      valueAfter: p.inventoryValue,
      reason,
      reference,
      createdBy: this.uid,
      eventAt: this.now,
    });
    return totalCost;
  }
}

export async function execute(
  store,
  uid,
  action,
  payload,
  key,
  now = new Date().toISOString(),
) {
  id(key);
  check(
    payload && typeof payload === "object" && !Array.isArray(payload),
    "Datos inválidos.",
    "invalid-argument",
  );
  const u = new Unit(store, now, uid);
  const member = await u.need(`members/${uid}`);
  authorize(member, action);
  const fingerprint = hash([action, payload]);
  const existing = await u.get(`commands/${key}`);
  if (existing) {
    check(
      existing.uid === uid && existing.fingerprint === fingerprint,
      "La clave ya se usó con otros datos.",
      "already-exists",
    );
    return existing.result;
  }
  const result = await dispatch(u, action, payload, key);
  u.put(`commands/${key}`, { uid, fingerprint, result, createdAt: now });
  u.put(`audit/${key}`, {
    id: key,
    action,
    actorId: uid,
    entityId: result.id || "",
    createdAt: now,
    fingerprint,
  });
  await u.flush();
  return result;
}

async function paymentFields(u, p) {
  integer(p.amount, "Monto", 1);
  localDate(p.at);
  const settings = await u.need("settings/general");
  check(
    settings.methods.some((x) => x.id === p.methodId && x.active !== false),
    "Medio de pago no habilitado.",
  );
  check(
    settings.accounts.some((x) => x.id === p.accountId && x.active !== false),
    "Cuenta no habilitada.",
  );
  return {
    amount: p.amount,
    at: p.at,
    methodId: p.methodId,
    accountId: p.accountId,
    reference: str(p.reference, "Referencia", 200, true),
    status: "confirmed",
  };
}
async function category(u, value) {
  id(value);
  const settings = await u.need("settings/general");
  check(
    settings.categories.some((c) => c.id === value && c.active !== false),
    "Categoría no habilitada.",
  );
  return value;
}
async function artistBalance(u, artistId, generated = 0, paid = 0) {
  const path = `artistBalances/${artistId}`;
  const b = (await u.get(path)) || {
    id: artistId,
    artistId,
    generated: 0,
    paid: 0,
  };
  b.generated += generated;
  b.paid += paid;
  b.pending = b.generated - b.paid;
  u.put(path, b);
  return b;
}
async function countPaid(u, sale, at, reverse = false) {
  // Allocation order is persisted; fully paid services count exactly once.
  let budget = sale.paid;
  for (const line of sale.lines) {
    const covered = budget >= line.total;
    budget -= line.total;
    if (line.kind !== "service") continue;
    if (reverse && line.countedMonth) {
      const path = `artistMonths/${line.artistId}_${line.countedMonth}`;
      const m = await u.need(path);
      m.collected -= line.total;
      u.put(path, m);
      line.countedReversed = true;
    } else if (!reverse && covered && !line.countedMonth) {
      const month = localDate(at).slice(0, 7);
      const path = `artistMonths/${line.artistId}_${month}`;
      const m = (await u.get(path)) || {
        artistId: line.artistId,
        month,
        collected: 0,
      };
      m.collected += line.total;
      u.put(path, m);
      line.countedMonth = month;
    }
  }
}

async function dispatch(u, action, p, key) {
  if (action === "settings") {
    for (const mode of ["am", "pm", "night", "full"])
      interval("2026-01-01", mode, p.shifts);
    const am = interval("2026-01-01", "am", p.shifts),
      pm = interval("2026-01-01", "pm", p.shifts);
    check(am.end <= pm.start, "AM debe terminar antes o al inicio de PM.");
    for (const field of ["methods", "accounts", "categories"]) {
      check(
        Array.isArray(p[field]) && p[field].length > 0 && p[field].length <= 80,
        `${field}: lista requerida.`,
      );
      const seen = new Set();
      for (const v of p[field]) {
        id(v.id);
        str(v.name, "Nombre");
        check(!seen.has(v.id), "Identificador duplicado.");
        seen.add(v.id);
      }
    }
    u.put("settings/general", {
      id: "general",
      name: "Findink House",
      currency: "COP",
      timezone: "America/Bogota",
      shifts: p.shifts,
      methods: p.methods,
      accounts: p.accounts,
      categories: p.categories,
      qa: true,
    });
    return { id: "general" };
  }
  if (action === "saveBed") {
    const bedId = id(p.id || key);
    u.put(`beds/${bedId}`, {
      id: bedId,
      name: str(p.name, "Nombre"),
      active: p.active !== false,
      notes: str(p.notes, "Notas", 1000, true),
    });
    return { id: bedId };
  }
  if (action === "saveArtist") {
    const artistId = id(p.id || key);
    const old = await u.get(`artists/${artistId}`);
    check(
      Array.isArray(p.bedIds) && p.bedIds.length <= 50,
      "Camillas inválidas.",
    );
    for (const bedId of p.bedIds) await u.need(`beds/${id(bedId)}`);
    const r = p.rule;
    check(r, "Regla requerida.");
    integer(r.baseBps, "Tasa base", 0, 10000);
    integer(r.reducedBps, "Tasa reducida", 0, 10000);
    integer(r.threshold, "Umbral", 1);
    date(r.effectiveFrom);
    const rule = {
      baseBps: r.baseBps,
      reducedBps: r.reducedBps,
      threshold: r.threshold,
      effectiveFrom: r.effectiveFrom,
      version: key,
    };
    check(
      rule.reducedBps <= rule.baseBps,
      "La tasa reducida no puede superar la base.",
    );
    const changed =
      !old ||
      ["baseBps", "reducedBps", "threshold", "effectiveFrom"].some(
        (f) => old.rule[f] !== rule[f],
      );
    u.put(`artists/${artistId}`, {
      id: artistId,
      name: str(p.name, "Nombre"),
      styles: str(p.styles, "Estilos", 500, true),
      bedIds: p.bedIds,
      active: p.active !== false,
      rule: changed ? rule : old.rule,
      previousRules:
        changed && old
          ? [...(old.previousRules || []), old.rule].slice(-100)
          : old?.previousRules || [],
    });
    if (changed)
      u.put(`ruleVersions/${artistId}_${key}`, {
        artistId,
        rule,
        createdBy: u.uid,
        createdAt: u.now,
      });
    return { id: artistId };
  }
  if (action === "saveCatalog") {
    const itemId = id(p.id || key);
    const old = await u.get(`catalog/${itemId}`);
    check(
      ["service", "product", "material"].includes(p.kind),
      "Tipo inválido.",
    );
    check(
      !old || old.kind === p.kind,
      "No se puede cambiar el tipo del artículo.",
    );
    const sku = str(p.sku, "SKU", 64).toUpperCase();
    const skuPath = `skus/${hash(sku)}`;
    const taken = await u.get(skuPath);
    check(!taken || taken.itemId === itemId, "El SKU ya está registrado.");
    integer(p.cost, "Costo");
    integer(p.price, "Precio");
    integer(p.minimum, "Mínimo", 0, 1_000_000);
    await category(u, p.categoryId);
    if (old)
      check(
        p.cost === old.cost,
        "El costo de existencias cambia mediante compras o ajustes de valoración, no al editar el catálogo.",
      );
    const record = {
      id: itemId,
      name: str(p.name, "Nombre"),
      sku,
      kind: p.kind,
      description: str(p.description, "Descripción", 1000, true),
      unit: str(p.unit, "Unidad", 40),
      supplier: str(p.supplier, "Proveedor", 200, true),
      categoryId: id(p.categoryId),
      cost: p.cost,
      price: p.price,
      minimum: p.minimum,
      active: p.active !== false,
      stock: old?.stock || 0,
      inventoryValue: old?.inventoryValue ?? (old?.stock || 0) * p.cost,
    };
    u.put(`catalog/${itemId}`, record);
    u.put(skuPath, { itemId });
    if (!old && p.initialStock) {
      check(p.kind !== "service", "Un servicio no tiene stock.");
      integer(p.initialStock, "Stock inicial", 1, 1_000_000);
      await u.stock(key, itemId, p.initialStock, "opening", key, p.cost);
    }
    return { id: itemId };
  }
  if (action === "invite") {
    const email = str(p.email, "Correo", 254).toLowerCase();
    check(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email), "Correo inválido.");
    check(
      ["admin", "reception", "artist", "auditor"].includes(p.role),
      "Rol inválido.",
    );
    if (p.role === "artist") await u.need(`artists/${id(p.artistId)}`);
    u.put(`invitations/${hash(email)}`, {
      email,
      role: p.role,
      artistId: p.role === "artist" ? p.artistId : "",
      active: true,
      createdBy: u.uid,
    });
    return { id: hash(email) };
  }
  if (action === "member") {
    id(p.id);
    check(p.id !== u.uid, "No puedes modificar tu propio acceso.");
    const m = await u.need(`members/${p.id}`);
    check(
      ["admin", "reception", "artist", "auditor"].includes(p.role),
      "Rol inválido.",
    );
    if (p.role === "artist") await u.need(`artists/${id(p.artistId)}`);
    u.put(`members/${p.id}`, {
      ...m,
      role: p.role,
      active: p.active !== false,
      artistId: p.role === "artist" ? p.artistId : "",
    });
    return { id: p.id };
  }
  if (action === "reserve") {
    const settings = await u.need("settings/general");
    const bed = await u.need(`beds/${id(p.bedId)}`);
    check(bed.active, "Camilla inactiva.");
    const blocked = p.kind === "block";
    check(
      ["appointment", "reservation", "block"].includes(p.kind),
      "Tipo inválido.",
    );
    let artistId = "";
    if (!blocked) {
      artistId = id(p.artistId);
      const artist = await u.need(`artists/${artistId}`);
      check(
        artist.active && artist.bedIds.includes(p.bedId),
        "Artista no habilitado en esta camilla.",
      );
    }
    const times = interval(p.day, p.mode, settings.shifts);
    const days = [
      localDate(times.start),
      localDate(new Date(Date.parse(times.end) - 1).toISOString()),
    ];
    const lockIds = [];
    for (const day of new Set(days))
      for (const resource of [
        `bed_${p.bedId}`,
        ...(artistId ? [`artist_${artistId}`] : []),
      ]) {
        const lockId = `${resource}_${day}`;
        const lock = (await u.get(`scheduleLocks/${lockId}`)) || { slots: [] };
        check(
          !lock.slots.some((s) => overlaps(s, times)),
          "La camilla o el artista ya tiene una reserva en ese intervalo.",
          "already-exists",
        );
        check(lock.slots.length < 100, "Límite de reservas por día alcanzado.");
        lock.slots.push({ id: key, ...times });
        u.put(`scheduleLocks/${lockId}`, lock);
        lockIds.push(lockId);
      }
    u.put(`appointments/${key}`, {
      id: key,
      ...times,
      day: p.day,
      mode: p.mode,
      kind: p.kind,
      bedId: p.bedId,
      artistId,
      status: "reserved",
      clientName: str(p.clientName, "Cliente", 200, true),
      contact: str(p.contact, "Contacto", 200, true),
      design: str(p.design, "Diseño", 1000, true),
      lockIds,
      history: [{ status: "reserved", at: u.now, by: u.uid }],
      createdAt: u.now,
    });
    return { id: key };
  }
  if (action === "appointmentStatus") {
    const a = await u.need(`appointments/${id(p.id)}`);
    check(["reserved", "arrived"].includes(a.status), "Cita ya finalizada.");
    check(
      ["arrived", "completed", "cancelled", "noShow"].includes(p.status),
      "Estado inválido.",
    );
    if (p.status === "cancelled" || p.status === "noShow")
      for (const lockId of a.lockIds) {
        const lock = await u.need(`scheduleLocks/${lockId}`);
        lock.slots = lock.slots.filter((s) => s.id !== a.id);
        u.put(`scheduleLocks/${lockId}`, lock);
      }
    a.status = p.status;
    a.history.push({
      status: p.status,
      at: u.now,
      by: u.uid,
      reason: str(p.reason, "Motivo", 500, true),
    });
    u.put(`appointments/${a.id}`, a);
    return { id: a.id };
  }
  if (action === "movement") {
    check(
      ["consumption", "adjustment"].includes(p.kind),
      "Tipo de movimiento inválido.",
    );
    const item = await u.need(`catalog/${id(p.itemId)}`);
    integer(p.quantity, "Cantidad", -1_000_000, 1_000_000);
    if (p.kind === "consumption")
      check(
        item.kind === "material" && p.quantity < 0,
        "El consumo es una salida de material.",
      );
    const reason = str(p.reason, "Motivo", 500);
    const value = await u.stock(key, p.itemId, p.quantity, p.kind, reason);
    await u.journal(
      key,
      u.now,
      { expenses: p.quantity < 0 ? value : -value },
      { kind: p.kind, reference: key, categoryId: item.categoryId },
    );
    return { id: key };
  }
  if (action === "sale") {
    localDate(p.at);
    check(
      Array.isArray(p.lines) && p.lines.length > 0 && p.lines.length <= 20,
      "Incluye entre 1 y 20 líneas.",
    );
    const sale = {
      id: key,
      eventAt: p.at,
      serviceDate: date(p.serviceDate || localDate(p.at)),
      clientName: str(p.clientName, "Cliente", 200, true),
      bedId: p.bedId ? id(p.bedId) : "",
      status: "confirmed",
      lines: [],
      total: 0,
      paid: 0,
      payments: [],
      createdAt: u.now,
      createdBy: u.uid,
      currency: "COP",
    };
    if (sale.bedId) await u.need(`beds/${sale.bedId}`);
    for (const input of p.lines) {
      const item = await u.need(`catalog/${id(input.itemId)}`);
      check(
        item.active && item.kind !== "material",
        "Artículo no disponible para venta.",
      );
      integer(input.quantity, "Cantidad", 1, 10000);
      integer(input.price, "Precio");
      integer(input.discount || 0, "Descuento");
      const total = integer(
        input.quantity * input.price - (input.discount || 0),
        "Total de línea",
        1,
      );
      const line = {
        id: `${key}_${sale.lines.length}`,
        itemId: item.id,
        name: item.name,
        sku: item.sku,
        kind: item.kind,
        quantity: input.quantity,
        unitPrice: input.price,
        unitCost: item.cost,
        categoryId: item.categoryId,
        discount: input.discount || 0,
        discountReason: input.discount
          ? str(input.discountReason, "Motivo del descuento", 500)
          : "",
        tax: integer(input.tax || 0, "Impuesto informativo", 0, total),
        total,
        artistId: "",
        studioShare: total,
        artistShare: 0,
        cogs: 0,
      };
      if (item.kind === "service") {
        const artist = await u.need(`artists/${id(input.artistId)}`);
        check(artist.active, "Artista inactivo.");
        const rules = [...(artist.previousRules || []), artist.rule]
          .filter((r) => r.effectiveFrom <= sale.serviceDate)
          .sort((a, b) => a.effectiveFrom.localeCompare(b.effectiveFrom));
        const rule = rules.at(-1);
        check(rule, "No hay regla vigente para la fecha del servicio.");
        const month = localDate(p.at).slice(0, 7);
        const m = await u.get(`artistMonths/${artist.id}_${month}`);
        const bps =
          (m?.collected || 0) >= rule.threshold
            ? rule.reducedBps
            : rule.baseBps;
        Object.assign(line, {
          artistId: artist.id,
          artistName: artist.name,
          ruleSnapshot: rule,
          studioBps: bps,
          studioShare: percent(total, bps),
        });
        line.artistShare = total - line.studioShare;
        await artistBalance(u, artist.id, line.artistShare);
        u.put(`accruals/${line.id}`, {
          id: line.id,
          saleId: key,
          artistId: artist.id,
          amount: line.artistShare,
          studioBps: bps,
          eventAt: p.at,
          status: "generated",
        });
      } else {
        line.cogs = await u.stock(
          key,
          item.id,
          -input.quantity,
          "sale",
          key,
          item.cost,
        );
      }
      sale.total = integer(sale.total + total, "Total de venta");
      sale.lines.push(line);
      await u.journal(
        key,
        p.at,
        {
          gross: total,
          studio: line.studioShare,
          artistGenerated: line.artistShare,
          cogs: line.cogs,
          receivable: total,
          taxCollected: line.tax,
        },
        {
          kind: "sale",
          reference: key,
          artistId: line.artistId,
          categoryId: line.categoryId,
        },
      );
    }
    u.put(`sales/${key}`, sale);
    if (p.depositId) {
      const d = await u.need(`deposits/${id(p.depositId)}`);
      check(
        d.status === "available" && d.amount <= sale.total,
        "Anticipo aplicado, devuelto o mayor que la venta.",
      );
      d.status = "applied";
      d.saleId = key;
      u.put(`deposits/${d.id}`, d);
      sale.paid += d.amount;
      sale.payments.push({ ...d.payment, id: d.id, depositId: d.id });
      await u.journal(
        key,
        p.at,
        { receivable: -d.amount, depositLiability: -d.amount },
        { kind: "depositApplication", reference: key },
      );
    }
    if (p.payment) {
      const pay = await paymentFields(u, p.payment);
      check(pay.amount <= sale.total - sale.paid, "El pago supera el saldo.");
      sale.paid += pay.amount;
      sale.payments.push({ ...pay, id: key });
      await u.journal(
        key,
        pay.at,
        { cash: pay.amount, receivable: -pay.amount },
        {
          kind: "salePayment",
          reference: key,
          methodId: pay.methodId,
          accountId: pay.accountId,
        },
      );
    }
    await countPaid(u, sale, p.payment?.at || p.at);
    sale.balance = sale.total - sale.paid;
    u.put(`sales/${key}`, sale);
    return { id: key };
  }
  if (action === "salePayment") {
    const s = await u.need(`sales/${id(p.id)}`);
    check(s.status === "confirmed", "Venta anulada.");
    check(s.payments.length < 100, "Límite de pagos alcanzado.");
    const pay = await paymentFields(u, p);
    check(pay.amount <= s.total - s.paid, "El pago supera el saldo.");
    s.paid += pay.amount;
    s.balance = s.total - s.paid;
    s.payments.push({ ...pay, id: key });
    await countPaid(u, s, p.at);
    await u.journal(
      key,
      p.at,
      { cash: pay.amount, receivable: -pay.amount },
      {
        kind: action,
        reference: s.id,
        methodId: pay.methodId,
        accountId: pay.accountId,
      },
    );
    u.put(`sales/${s.id}`, s);
    return { id: s.id };
  }
  if (action === "saleVoid") {
    const s = await u.need(`sales/${id(p.id)}`);
    check(s.status === "confirmed", "Venta ya anulada.");
    str(p.reason, "Motivo", 500);
    localDate(p.at);
    await countPaid(u, s, p.at, true);
    for (const line of s.lines) {
      if (line.kind === "product")
        await u.stock(
          key,
          line.itemId,
          line.quantity,
          "saleReversal",
          s.id,
          line.unitCost,
          line.cogs,
        );
      else {
        await artistBalance(u, line.artistId, -line.artistShare);
        const a = await u.need(`accruals/${line.id}`);
        a.status = "reversed";
        a.reversalId = key;
        u.put(`accruals/${line.id}`, a);
      }
      await u.journal(
        key,
        p.at,
        {
          gross: -line.total,
          studio: -line.studioShare,
          artistGenerated: -line.artistShare,
          cogs: -line.cogs,
          receivable: -line.total,
          taxCollected: -line.tax,
        },
        {
          kind: action,
          reference: s.id,
          artistId: line.artistId,
          categoryId: line.categoryId,
        },
      );
    }
    for (const pay of s.payments) {
      await u.journal(
        key,
        p.at,
        { cash: -pay.amount, receivable: pay.amount },
        {
          kind: "refund",
          reference: s.id,
          methodId: pay.methodId,
          accountId: pay.accountId,
        },
      );
      if (pay.depositId) {
        const d = await u.need(`deposits/${pay.depositId}`);
        d.status = "refunded";
        u.put(`deposits/${d.id}`, d);
      }
    }
    s.status = "void";
    s.balance = 0;
    s.reversal = {
      id: key,
      reason: p.reason,
      at: p.at,
      by: u.uid,
      refunded: s.paid,
    };
    u.put(`sales/${s.id}`, s);
    return { id: s.id };
  }
  if (action === "purchase" || action === "expense") {
    await category(u, p.categoryId);
    localDate(p.at);
    const e = {
      id: key,
      kind: action,
      eventAt: p.at,
      supplier: str(p.supplier, "Proveedor", 200, true),
      categoryId: id(p.categoryId),
      folio: str(p.folio, "Folio", 100, true),
      costCenter: str(p.costCenter, "Centro de costos", 100, true),
      notes: str(p.notes, "Notas", 1000, true),
      dueDate: p.dueDate ? date(p.dueDate) : "",
      status: "confirmed",
      paid: 0,
      payments: [],
      lines: [],
      createdBy: u.uid,
    };
    if (action === "purchase") {
      check(
        Array.isArray(p.lines) && p.lines.length > 0 && p.lines.length <= 20,
        "Incluye entre 1 y 20 líneas.",
      );
      e.total = 0;
      for (const input of p.lines) {
        const item = await u.need(`catalog/${id(input.itemId)}`);
        check(
          item.active && item.kind !== "service",
          "Artículo inválido para compra.",
        );
        integer(input.quantity, "Cantidad", 1, 10000);
        integer(input.cost, "Costo");
        e.total = integer(e.total + input.quantity * input.cost, "Total");
        e.lines.push({
          itemId: item.id,
          name: item.name,
          quantity: input.quantity,
          cost: input.cost,
        });
        await u.stock(
          key,
          item.id,
          input.quantity,
          "purchase",
          key,
          input.cost,
        );
      }
      check(e.total > 0, "La compra debe tener valor.");
    } else {
      e.total = integer(p.amount, "Valor", 1);
      e.description = str(p.description, "Descripción", 500);
    }
    e.tax = integer(p.tax || 0, "Impuesto informativo", 0, e.total);
    await u.journal(
      key,
      p.at,
      {
        payable: e.total,
        expenses: action === "expense" ? e.total : 0,
        purchases: action === "purchase" ? e.total : 0,
        taxPaid: e.tax,
      },
      { kind: action, reference: key, categoryId: e.categoryId },
    );
    if (p.payment) {
      const pay = await paymentFields(u, p.payment);
      check(pay.amount <= e.total, "El pago supera el saldo.");
      e.paid = pay.amount;
      e.payments.push({ ...pay, id: key });
      await u.journal(
        key,
        pay.at,
        { cash: -pay.amount, payable: -pay.amount },
        {
          kind: "payablePayment",
          reference: key,
          methodId: pay.methodId,
          accountId: pay.accountId,
        },
      );
    }
    e.balance = e.total - e.paid;
    u.put(`payables/${key}`, e);
    return { id: key };
  }
  if (action === "payablePayment") {
    const e = await u.need(`payables/${id(p.id)}`);
    check(e.status === "confirmed", "Obligación anulada.");
    const pay = await paymentFields(u, p);
    check(pay.amount <= e.total - e.paid, "El pago supera el saldo.");
    check(e.payments.length < 100, "Límite de pagos alcanzado.");
    e.paid += pay.amount;
    e.balance = e.total - e.paid;
    e.payments.push({ ...pay, id: key });
    u.put(`payables/${e.id}`, e);
    await u.journal(
      key,
      p.at,
      { cash: -pay.amount, payable: -pay.amount },
      {
        kind: action,
        reference: e.id,
        methodId: pay.methodId,
        accountId: pay.accountId,
      },
    );
    return { id: e.id };
  }
  if (action === "payableVoid") {
    const e = await u.need(`payables/${id(p.id)}`);
    check(e.status === "confirmed", "Obligación ya anulada.");
    str(p.reason, "Motivo", 500);
    localDate(p.at);
    for (const line of e.lines)
      await u.stock(
        key,
        line.itemId,
        -line.quantity,
        "purchaseReversal",
        e.id,
        line.cost,
      );
    await u.journal(
      key,
      p.at,
      {
        payable: -e.total,
        expenses: e.kind === "expense" ? -e.total : 0,
        purchases: e.kind === "purchase" ? -e.total : 0,
        taxPaid: -e.tax,
      },
      { kind: action, reference: e.id, categoryId: e.categoryId },
    );
    for (const pay of e.payments)
      await u.journal(
        key,
        p.at,
        { cash: pay.amount, payable: pay.amount },
        {
          kind: "supplierRefund",
          reference: e.id,
          methodId: pay.methodId,
          accountId: pay.accountId,
        },
      );
    e.status = "void";
    e.balance = 0;
    e.reversal = { id: key, reason: p.reason, at: p.at, refunded: e.paid };
    u.put(`payables/${e.id}`, e);
    return { id: e.id };
  }
  if (action === "deposit") {
    const pay = await paymentFields(u, p);
    if (p.appointmentId) await u.need(`appointments/${id(p.appointmentId)}`);
    u.put(`deposits/${key}`, {
      id: key,
      amount: pay.amount,
      payment: pay,
      status: "available",
      clientName: str(p.clientName, "Cliente", 200),
      appointmentId: p.appointmentId || "",
      eventAt: p.at,
    });
    await u.journal(
      key,
      p.at,
      { cash: pay.amount, depositLiability: pay.amount },
      {
        kind: action,
        reference: key,
        methodId: pay.methodId,
        accountId: pay.accountId,
      },
    );
    return { id: key };
  }
  if (action === "depositRefund") {
    const d = await u.need(`deposits/${id(p.id)}`);
    check(d.status === "available", "Anticipo no disponible.");
    str(p.reason, "Motivo", 500);
    localDate(p.at);
    d.status = "refunded";
    d.reversal = { id: key, reason: p.reason, at: p.at };
    u.put(`deposits/${d.id}`, d);
    await u.journal(
      key,
      p.at,
      { cash: -d.amount, depositLiability: -d.amount },
      {
        kind: action,
        reference: d.id,
        methodId: d.payment.methodId,
        accountId: d.payment.accountId,
      },
    );
    return { id: d.id };
  }
  if (action === "settlement") {
    const artistId = id(p.artistId);
    await u.need(`artists/${artistId}`);
    const pay = await paymentFields(u, p);
    const b = await artistBalance(u, artistId);
    check(
      pay.amount <= b.pending,
      "El pago supera la participación pendiente.",
    );
    await artistBalance(u, artistId, 0, pay.amount);
    u.put(`settlements/${key}`, {
      id: key,
      artistId,
      ...pay,
      eventAt: p.at,
      createdBy: u.uid,
    });
    await u.journal(
      key,
      p.at,
      { cash: -pay.amount, artistPaid: pay.amount },
      {
        kind: action,
        reference: key,
        artistId,
        methodId: pay.methodId,
        accountId: pay.accountId,
      },
    );
    return { id: key };
  }
  if (action === "importRow") {
    check(p.approved === true, "Debes aprobar la equivalencia y conciliación.");
    str(p.fileHash, "Huella del archivo", 64);
    check(/^[a-f0-9]{64}$/.test(p.fileHash), "Huella inválida.");
    str(p.sheet, "Hoja", 100);
    integer(p.row, "Fila", 1, 100000);
    check(
      [
        "saveCatalog",
        "saveArtist",
        "sale",
        "expense",
        "purchase",
        "deposit",
      ].includes(p.operation),
      "Operación de importación inválida.",
    );
    const sourceId = hash([p.fileHash, p.sheet, p.row]);
    const old = await u.get(`imports/${sourceId}`);
    if (old) {
      check(
        old.mappingHash === hash([p.operation, p.data]),
        "Esta fila ya se importó con otro mapeo.",
      );
      return { id: old.entityId, duplicate: true };
    }
    const result = await dispatch(u, p.operation, p.data, `import_${sourceId}`);
    u.put(`imports/${sourceId}`, {
      id: sourceId,
      fileHash: p.fileHash,
      sheet: p.sheet,
      row: p.row,
      operation: p.operation,
      entityId: result.id,
      mappingHash: hash([p.operation, p.data]),
      approvedBy: u.uid,
      createdAt: u.now,
    });
    return result;
  }
  throw new DomainError("Operación no implementada.", "invalid-argument");
}

export function summarize(rows) {
  const totals = {};
  for (const row of rows)
    for (const [key, value] of Object.entries(row.metrics || {}))
      totals[key] = (totals[key] || 0) + value;
  totals.net =
    (totals.gross || 0) -
    (totals.artistGenerated || 0) -
    (totals.cogs || 0) -
    (totals.expenses || 0);
  totals.artistPending =
    (totals.artistGenerated || 0) - (totals.artistPaid || 0);
  return totals;
}
