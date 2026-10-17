import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";

const SRC = process.argv[2];
const OUT = process.argv[3];

fs.mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 1920, height: 1080 },
  deviceScaleFactor: 2,
});

await page.goto("file:///" + SRC.replace(/\\/g, "/"), { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(1500);

const count = await page.locator(".slide").count();
console.log("slides found:", count);

// Report anything that overflows its slide box.
const overflow = await page.evaluate(() => {
  const bad = [];
  document.querySelectorAll(".slide").forEach((s, i) => {
    const sb = s.getBoundingClientRect();
    s.querySelectorAll("*").forEach((el) => {
      const b = el.getBoundingClientRect();
      if (b.width === 0 || b.height === 0) return;
      if (b.right > sb.right + 1 || b.bottom > sb.bottom + 1 || b.left < sb.left - 1 || b.top < sb.top - 1) {
        bad.push({
          slide: i + 1,
          tag: el.tagName.toLowerCase() + (el.className && typeof el.className === "string" ? "." + el.className.split(" ")[0] : ""),
          text: (el.textContent || "").trim().slice(0, 44),
          over: {
            r: Math.round(b.right - sb.right),
            b: Math.round(b.bottom - sb.bottom),
            l: Math.round(sb.left - b.left),
            t: Math.round(sb.top - b.top),
          },
        });
      }
    });
  });
  return bad;
});
if (overflow.length) {
  console.log("OVERFLOW (" + overflow.length + "):");
  for (const o of overflow.slice(0, 40)) console.log("  ", JSON.stringify(o));
} else {
  console.log("no overflow");
}

for (let i = 0; i < count; i++) {
  const el = page.locator(".slide").nth(i);
  const file = path.join(OUT, String(i + 1).padStart(2, "0") + ".png");
  await el.screenshot({ path: file });
  process.stdout.write(".");
}
console.log("\nwrote " + count + " png to " + OUT);

await browser.close();
