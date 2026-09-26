import { chromium } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
const user = JSON.parse(
  readFileSync("../artifacts/qa-browser-credentials.local.json", "utf8"),
).users.find((u) => u.role === "admin");
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
await page.goto("https://estudio-tatuajes-newzenda-qa.web.app", {
  waitUntil: "networkidle",
});
await page.locator("flt-semantics-placeholder").evaluate((el) => el.click());
await page
  .getByRole("textbox", { name: "Correo electrónico", exact: true })
  .click();
await page
  .getByRole("textbox", { name: "Correo electrónico", exact: true })
  .pressSequentially(user.email, { delay: 10 });
await page.getByRole("textbox", { name: "Contraseña", exact: true }).click();
await page
  .getByRole("textbox", { name: "Contraseña", exact: true })
  .pressSequentially(user.password, { delay: 15 });
await page
  .getByRole("button", { name: "Entrar al estudio", exact: true })
  .click();
try {
  await page
    .getByText("El pulso de tu estudio", { exact: true })
    .waitFor({ timeout: 60000 });
} catch (e) {
  await page.screenshot({ path: "../artifacts/form-error.png" });
  writeFileSync(
    "../artifacts/form-error.txt",
    await page.locator("body").ariaSnapshot(),
  );
  await browser.close();
  throw e;
}
await page.getByText("Ventas y CxC", { exact: true }).first().click();
await page.getByRole("button", { name: "Nueva venta", exact: true }).click();
writeFileSync(
  "../artifacts/form-semantics.txt",
  await page.locator("body").ariaSnapshot(),
);
await page.screenshot({ path: "../artifacts/sale-form.png", fullPage: true });
async function fill(name, value) {
  const input = page.getByRole("textbox", { name, exact: true });
  await input.click();
  await input.press("Control+A");
  await input.pressSequentially(value, { delay: 12 });
}
async function select(name, value, last = false) {
  const b = page.getByRole("button", { name, exact: true });
  await (last ? b.last() : b.first()).click();
  await page.waitForTimeout(500);
  writeFileSync(
    "../artifacts/dropdown-semantics.txt",
    await page.locator("body").ariaSnapshot(),
  );
  await page.screenshot({ path: "../artifacts/dropdown.png" });
  await page.getByRole("menuitem", { name: value, exact: true }).click();
}
await fill("Cliente (opcional)", "Cliente ficticio de prueba de navegador");
await fill("Pago inicial (0 = pendiente)", "100000");
await select("Medio de pago", "Efectivo");
await select("Cuenta destino / origen", "Caja QA");
await select("Servicio / producto", "Tatuaje · precio de prueba");
await select("Artista del servicio", "Ada · artista ficticia");
await page.getByRole("button", { name: "Agregar línea", exact: true }).click();
await select("Servicio / producto", "Crema de cuidado · QA", true);
const response = page.waitForResponse(
  (r) =>
    r.url().includes("findinkCommand") &&
    r.request().postDataJSON()?.data?.action === "sale",
  { timeout: 60000 },
);
await page
  .getByRole("button", { name: "Confirmar operación", exact: true })
  .click();
const created = await (await response).json();
if (created.error) throw new Error(created.error.message);
writeFileSync(
  "../artifacts/browser-created-sale.json",
  JSON.stringify(created.result),
);
await page.waitForTimeout(2000);
writeFileSync(
  "../artifacts/after-sale-semantics.txt",
  await page.locator("body").ariaSnapshot(),
);
await page
  .getByRole("button", { name: /Cliente ficticio de prueba de navegador/ })
  .first()
  .click();
await page
  .getByRole("button", { name: "Anular y devolver", exact: true })
  .click();
await fill(
  "Motivo de la anulación / devolución",
  "Reverso de prueba completa desde navegador",
);
const reversal = page.waitForResponse(
  (r) =>
    r.url().includes("findinkCommand") &&
    r.request().postDataJSON()?.data?.action === "saleVoid",
  { timeout: 60000 },
);
await page
  .getByRole("button", { name: "Confirmar operación", exact: true })
  .click();
const reversed = await (await reversal).json();
if (reversed.error) throw new Error(reversed.error.message);
writeFileSync(
  "../artifacts/browser-form-results.json",
  JSON.stringify(
    {
      at: new Date().toISOString(),
      saleId: created.result.id,
      checks: [
        "Mixed sale with two lines, artist and partial payment submitted from UI",
        "Full reversal submitted from UI",
      ],
    },
    null,
    2,
  ),
);
console.log("PASS browser mixed-sale form and traceable full reversal.");
await browser.close();
