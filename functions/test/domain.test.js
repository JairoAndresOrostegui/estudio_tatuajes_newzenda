import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  execute,
  STUDY,
  interval,
  overlaps,
  summarize,
  percent,
} from "../src/domain.js";
const fixtures = JSON.parse(
  readFileSync(new URL("./fixtures/seed.json", import.meta.url)),
);
class Memory {
  data = new Map();
  seq = 0;
  queue = Promise.resolve();
  async command(action, p, key = `cmd_${this.seq++}`, uid = "admin") {
    const run = this.queue.then(async () => {
      const next = new Map(
        [...this.data].map(([k, v]) => [k, structuredClone(v)]),
      );
      const result = await execute(
        { get: async (p) => next.get(p), set: (p, v) => next.set(p, v) },
        uid,
        action,
        p,
        key,
        "2026-09-26T15:00:00Z",
      );
      this.data = next;
      return result;
    });
    this.queue = run.catch(() => {});
    return run;
  }
  get(path) {
    return this.data.get(path);
  }
}
async function setup() {
  const m = new Memory();
  for (const role of ["admin", "reception", "artist", "auditor"])
    m.data.set(`members/${role}`, {
      role,
      active: true,
      studyId: STUDY,
      artistId: "artist_ada",
    });
  for (const x of fixtures) await m.command(x.action, x.payload);
  return m;
}
const at = "2026-09-26T15:00:00Z";
const pay = (amount, when = at) => ({
  amount,
  at: when,
  methodId: "cash",
  accountId: "cashbox",
});
const service = (price = 1_000_000, artistId = "artist_ada") => ({
  itemId: "tattoo",
  quantity: 1,
  price,
  artistId,
});
const sale = (lines, payment) => ({ at, lines, payment });
test("real interval overlap, full blocks AM/PM, independent night crossing midnight", async () => {
  const m = await setup();
  const settings = m.get("settings/general");
  assert.equal(
    interval("2026-09-26", "night", settings.shifts).end,
    "2026-09-27T07:00:00.000Z",
  );
  assert.equal(
    overlaps(
      interval("2026-09-26", "full", settings.shifts),
      interval("2026-09-26", "night", settings.shifts),
    ),
    false,
  );
  const p = {
    day: "2026-09-26",
    mode: "full",
    kind: "appointment",
    bedId: "bed_a",
    artistId: "artist_ada",
  };
  const results = await Promise.allSettled([
    m.command("reserve", p, "r1", "reception"),
    m.command("reserve", p, "r2", "reception"),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  await assert.rejects(
    m.command("reserve", { ...p, mode: "am", artistId: "artist_leo" }),
    /reserva/,
  );
  await assert.rejects(
    m.command("reserve", { ...p, mode: "pm", bedId: "bed_b" }),
    /reserva/,
  );
  await m.command("reserve", { ...p, mode: "night" });
  await m.command("appointmentStatus", {
    id: "r1",
    status: "cancelled",
    reason: "Prueba",
  });
  await m.command("reserve", { ...p, mode: "am" });
});
test("mixed sale, split payments, idempotency, cash vs accrual and traceable reversal", async () => {
  const m = await setup();
  const p = sale(
    [service(200000), { itemId: "cream", quantity: 2, price: 25000 }],
    pay(100000),
  );
  await m.command("sale", p, "mixed");
  await m.command("sale", p, "mixed");
  assert.equal(m.get("catalog/cream").stock, 28);
  assert.equal(m.get("sales/mixed").balance, 150000);
  await m.command(
    "salePayment",
    { id: "mixed", ...pay(150000, "2026-09-27T15:00:00Z") },
    "pay2",
  );
  await m.command(
    "salePayment",
    { id: "mixed", ...pay(150000, "2026-09-27T15:00:00Z") },
    "pay2",
  );
  assert.equal(m.get("balances/current").metrics.cash, 250000);
  assert.equal(m.get("balances/current").metrics.gross, 250000);
  assert.equal(m.get("artistMonths/artist_ada_2026-09").collected, 200000);
  await m.command("settlement", { artistId: "artist_ada", ...pay(100000) });
  const report = summarize([m.get("balances/current")]);
  assert.equal(report.net, 42000);
  assert.equal(report.cash, 150000);
  await m.command("saleVoid", {
    id: "mixed",
    at: "2026-09-28T15:00:00Z",
    reason: "Devolución total",
  });
  assert.equal(m.get("catalog/cream").stock, 30);
  assert.equal(m.get("balances/current").metrics.receivable, 0);
  assert.equal(m.get("balances/current").metrics.gross, 0);
  assert.equal(m.get("artistMonths/artist_ada_2026-09").collected, 0);
  assert.equal(m.get("artistBalances/artist_ada").pending, -100000);
  await assert.rejects(
    m.command("saleVoid", { id: "mixed", at, reason: "Dos veces" }),
    /anulada/,
  );
});
test("purchase received unpaid increases stock once and payment closes payable", async () => {
  const m = await setup();
  await m.command(
    "purchase",
    {
      at,
      categoryId: "supplies",
      lines: [{ itemId: "needle", quantity: 10, cost: 3500 }],
    },
    "purchase",
  );
  assert.equal(m.get("catalog/needle").stock, 50);
  assert.equal(m.get("payables/purchase").balance, 35000);
  await m.command(
    "payablePayment",
    { id: "purchase", ...pay(35000) },
    "purchase_payment",
  );
  await m.command(
    "payablePayment",
    { id: "purchase", ...pay(35000) },
    "purchase_payment",
  );
  assert.equal(m.get("catalog/needle").stock, 50);
  assert.equal(m.get("payables/purchase").balance, 0);
  assert.equal(m.get("balances/current").metrics.expenses, 0);
  await m.command("payableVoid", {
    id: "purchase",
    at,
    reason: "Proveedor devuelve pago",
  });
  assert.equal(m.get("catalog/needle").stock, 40);
  assert.equal(m.get("balances/current").metrics.payable, 0);
});
test("study 8/6 threshold crossing, partial payments, next month and immutable snapshots", async () => {
  const m = await setup();
  await m.command("sale", sale([service()], pay(500000)), "a");
  assert.equal(m.get("artistMonths/artist_ada_2026-09"), undefined);
  await m.command("salePayment", { id: "a", ...pay(500000) }, "a_pay");
  await m.command("sale", sale([service()], pay(1000000)), "b");
  assert.equal(m.get("sales/b").lines[0].studioBps, 800);
  await m.command("sale", sale([service()], pay(1000000)), "c");
  assert.equal(m.get("sales/c").lines[0].studioBps, 600);
  await m.command(
    "sale",
    {
      ...sale([service()], pay(1000000, "2026-10-01T05:00:00Z")),
      at: "2026-10-01T05:00:00Z",
    },
    "d",
  );
  assert.equal(m.get("sales/d").lines[0].studioBps, 800);
  await m.command("saveArtist", {
    ...fixtures[3].payload,
    rule: {
      baseBps: 3000,
      reducedBps: 2500,
      threshold: 2000000,
      effectiveFrom: "2026-10-01",
    },
  });
  assert.equal(m.get("sales/a").lines[0].studioBps, 800);
  await m.command("saleVoid", {
    id: "b",
    at: "2026-10-01T06:00:00Z",
    reason: "Reverso",
  });
  assert.equal(m.get("artistMonths/artist_ada_2026-09").collected, 2000000);
  assert.equal(m.get("sales/c").lines[0].studioBps, 600);
  assert.equal(percent(999999, 800), 80000);
});
test("roles cannot perform privileged mutations and unaffiliated member is rejected", async () => {
  const m = await setup();
  for (const role of ["reception", "artist", "auditor"])
    await assert.rejects(
      m.command("settings", fixtures[0].payload, `denied_${role}`, role),
      /rol/,
    );
  for (const role of ["artist", "auditor"])
    await assert.rejects(
      m.command("sale", sale([service()]), `denied_sale_${role}`, role),
      /rol/,
    );
  m.data.set("members/foreign", {
    role: "admin",
    active: true,
    studyId: "another",
  });
  await assert.rejects(
    m.command("settings", fixtures[0].payload, "foreign", "foreign"),
    /acceso/,
  );
});
test("import duplicate rows remain idempotent even with a new command key", async () => {
  const m = await setup();
  const payload = {
    approved: true,
    fileHash: "a".repeat(64),
    sheet: "Ingresos",
    row: 9,
    operation: "sale",
    data: sale([service(200000)], pay(200000)),
  };
  const a = await m.command("importRow", payload);
  const b = await m.command("importRow", payload);
  assert.equal(a.id, b.id);
  assert.equal(b.duplicate, true);
  assert.equal(m.get("balances/current").metrics.gross, 200000);
  await assert.rejects(
    m.command("importRow", { ...payload, data: sale([service(300000)]) }),
    /otro mapeo/,
  );
});
test("deposit applied once does not create a second cash receipt and refund removes liability", async () => {
  const m = await setup();
  await m.command(
    "deposit",
    { ...pay(50000), clientName: "Cliente ficticio" },
    "dep",
  );
  await m.command(
    "sale",
    { ...sale([service(200000)], pay(150000)), depositId: "dep" },
    "with_deposit",
  );
  assert.equal(m.get("balances/current").metrics.cash, 200000);
  assert.equal(m.get("balances/current").metrics.depositLiability, 0);
  assert.equal(m.get("sales/with_deposit").balance, 0);
  await assert.rejects(
    m.command("sale", { ...sale([service(200000)]), depositId: "dep" }),
    /Anticipo/,
  );
  await m.command("saleVoid", { id: "with_deposit", at, reason: "Devolución" });
  assert.equal(m.get("balances/current").metrics.cash, 0);
});
test("failure is atomic, oversell and overpay rejected, idempotency collisions rejected", async () => {
  const m = await setup();
  await assert.rejects(
    m.command("sale", sale([{ itemId: "cream", quantity: 31, price: 25000 }])),
  );
  assert.equal(m.get("catalog/cream").stock, 30);
  await m.command("sale", sale([service(100)]), "x");
  await assert.rejects(
    m.command("salePayment", { id: "x", ...pay(101) }),
    /supera/,
  );
  await assert.rejects(
    m.command("sale", sale([service(200)]), "x"),
    /otros datos/,
  );
  assert.equal(m.get("sales/x").paid, 0);
});
