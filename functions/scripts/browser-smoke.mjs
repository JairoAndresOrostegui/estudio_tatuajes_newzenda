import { chromium } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
const credentials = JSON.parse(
  readFileSync("../artifacts/qa-browser-credentials.local.json", "utf8"),
);
const browser = await chromium.launch({ channel: "chrome", headless: true });
const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
const failures = [];
page.on("pageerror", (e) => failures.push(e.message));
await page.goto("https://estudio-tatuajes-newzenda-qa.web.app", {
  waitUntil: "networkidle",
  timeout: 60000,
});
await page
  .locator("flutter-view")
  .waitFor({ timeout: 45000, state: "attached" });
await page.locator("flt-semantics-placeholder").evaluate((el) => el.click());
await page.getByRole("textbox").first().waitFor({ timeout: 30000 });
await page.screenshot({
  path: "../artifacts/login-desktop.png",
  fullPage: true,
});
const user = credentials.users.find((u) => u.role === "admin");
await page.getByRole("textbox").nth(0).fill(user.email);
await page.getByRole("textbox").nth(1).fill(user.password);
await page
  .getByRole("button", { name: "Entrar al estudio", exact: true })
  .click();
await page
  .getByText("El pulso de tu estudio", { exact: true })
  .waitFor({ timeout: 60000 });
await page
  .getByText("En la agenda de hoy", { exact: true })
  .waitFor({ timeout: 60000 });
await page.screenshot({
  path: "../artifacts/dashboard-desktop.png",
  fullPage: true,
});
const visited = [];
for (const name of [
  "Agenda",
  "Ventas y CxC",
  "Gastos y compras",
  "Catálogo e inventario",
  "Artistas",
  "Camillas",
  "Caja y reportes",
  "Usuarios",
  "Configuración",
]) {
  await page.getByText(name, { exact: true }).first().click();
  await page.waitForTimeout(1500);
  visited.push(name);
  if (
    await page
      .getByText("No fue posible completar la operación.", { exact: false })
      .count()
  )
    failures.push(`Error loading ${name}`);
}
await page.getByText("Vista general", { exact: true }).click();
await page.setViewportSize({ width: 390, height: 844 });
await page.waitForTimeout(1200);
await page.screenshot({
  path: "../artifacts/dashboard-mobile.png",
  fullPage: true,
});
writeFileSync(
  "../artifacts/browser-smoke-results.json",
  JSON.stringify({ at: new Date().toISOString(), visited, failures }, null, 2),
);
console.log(JSON.stringify({ visited, failures }));
await browser.close();
if (failures.length) process.exitCode = 1;
