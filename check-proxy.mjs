import { chromium } from "playwright";

const BASE = process.argv[2] ?? "http://localhost";
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

const errors = [];
const requests = [];
page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
page.on("requestfailed", (r) => requests.push(`FAILED ${r.url()} — ${r.failure()?.errorText}`));
page.on("response", (r) => {
  const u = r.url();
  if (u.includes("/extraction/") || u.includes("/runner/")) requests.push(`${r.status()} ${u}`);
});

for (const path of ["/", "/documents", "/live"]) {
  errors.length = 0; requests.length = 0;
  const res = await page.goto(BASE + path, { waitUntil: "networkidle", timeout: 45000 }).catch((e) => ({ status: () => "ERR " + e.message }));
  await page.waitForTimeout(2500);
  const title = await page.title().catch(() => "?");
  console.log(`\n=== ${path} -> ${typeof res.status === "function" ? res.status() : "?"}  "${title}"`);
  const backendCalls = requests.filter((r) => r.includes("/extraction/") || r.includes("/runner/"));
  if (backendCalls.length) { console.log("  service calls:"); backendCalls.slice(0, 8).forEach((r) => console.log("   ", r)); }
  else console.log("  service calls: none");
  if (errors.length) { console.log("  console errors:"); errors.slice(0, 6).forEach((e) => console.log("   ", e.slice(0, 160))); }
  else console.log("  console errors: none");
  await page.screenshot({ path: `proxy-${path.replace(/\//g, "_") || "root"}.png` });
}

await browser.close();
