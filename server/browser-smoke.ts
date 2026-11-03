// Isolated Chromium smoke. Run from server/ with BP26_URL set if not on 8787.
import { chromium } from "@playwright/test";
import { mkdir } from "node:fs/promises";
const executablePath =
  process.env.CHROMIUM_PATH ??
  "/Users/syedc/Library/Caches/ms-playwright/chromium-1247/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";
const browser = await chromium.launch({
  executablePath,
  headless: true,
  args: ["--no-sandbox"],
});
const artifacts = process.env.BP26_ARTIFACTS ?? "/private/tmp/bp26-browser";
await mkdir(artifacts, { recursive: true });
try {
  const page = await browser.newPage({
    viewport: { width: 1360, height: 1100 },
    recordVideo: { dir: artifacts, size: { width: 1360, height: 1100 } },
  });
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => {
    if (m.type() === "error") console.log("browser console:", m.text());
  });
  await page.goto(process.env.BP26_URL ?? "http://localhost:8787");
  await page.waitForFunction(() => !!(window as any).bp26, { timeout: 30000 });
  await page.waitForFunction(
    () =>
      document
        .querySelector("#badge")
        ?.textContent?.includes("Demo - no rewards"),
    { timeout: 10000 },
  );
  await page.screenshot({ path: artifacts + "/desktop.png", fullPage: true });
  await page.getByRole("button", { name: "SELECT", exact: true }).click();
  await page.waitForFunction(
    () =>
      document.querySelector("#badge")?.textContent?.includes("Investigator"),
    { timeout: 15000 },
  );
  await page.waitForFunction(
    () => document.querySelector("#badge")?.textContent?.includes("CLEAN"),
    { timeout: 45000 },
  );
  console.log("browser active:", await page.locator("#badge").innerText());
  // Source is deterministic only in the demo namespace. Wait through its latent window.
  await page.waitForTimeout(12400);
  await page.getByRole("button", { name: "SELECT", exact: true }).click();
  await page.waitForFunction(
    () => document.querySelector("#badge")?.textContent?.includes("CAUGHT"),
    { timeout: 10000 },
  );
  console.log("PASS browser CAUGHT");
  await page.screenshot({ path: artifacts + "/caught.png", fullPage: true });
  await page.getByRole("button", { name: "Right", exact: true }).click();
  await page.waitForFunction(() => document.querySelector("#badge .qr img"), {
    timeout: 10000,
  });
  await page.getByRole("button", { name: "BACK", exact: true }).click();
  await page.getByRole("button", { name: "New room", exact: true }).click();
  await page.waitForFunction(() => !!(window as any).bp26, { timeout: 30000 });
  await page.waitForFunction(
    () =>
      document
        .querySelector("#badge")
        ?.textContent?.includes("Demo - no rewards"),
    { timeout: 10000 },
  );
  await page.getByRole("button", { name: "SELECT", exact: true }).click();
  await page.waitForFunction(
    () => document.querySelector("#badge")?.textContent?.includes("ESCAPED"),
    { timeout: 75000 },
  );
  console.log("PASS browser ESCAPED");
  await page.screenshot({ path: artifacts + "/escaped.png", fullPage: true });
  await page.setViewportSize({ width: 390, height: 1100 });
  await page.screenshot({ path: artifacts + "/phone.png", fullPage: true });
  if (
    await page.evaluate(
      () => document.documentElement.scrollWidth > window.innerWidth,
    )
  )
    throw Error("mobile horizontal overflow");
  if (errors.length) throw Error(errors.join("\n"));
  await page.close();
  console.log("PASS browser widgets, QR, mobile, no console errors");
} finally {
  await browser.close();
}
