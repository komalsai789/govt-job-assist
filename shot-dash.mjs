import { chromium } from "playwright";
const b = await chromium.launch();
const p = await (await b.newContext()).newPage({ viewport: { width: 1512, height: 950 } });
const errs = [];
p.on("pageerror", e => errs.push(e.message));
p.on("console", m => { if (m.type() === "error") errs.push(m.text()); });
await p.goto("http://localhost/login", { waitUntil: "networkidle", timeout: 60000 });
await p.locator("form button").first().click();
await p.waitForURL(/\/dashboard/, { timeout: 30000 }).catch(() => {});
await p.goto("http://localhost/dashboard", { waitUntil: "networkidle", timeout: 60000 });
await p.waitForTimeout(3000);
await p.screenshot({ path: "dash.png", fullPage: true });
const m = await p.evaluate(() => {
  const cols = [...document.querySelectorAll('[class*="xl:grid-cols"] > div')];
  return {
    height: document.body.scrollHeight,
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    clipped: [...document.querySelectorAll("h1,h2,h3,p,span,a")].filter(e => e.scrollWidth > e.clientWidth + 1 && e.clientWidth > 0).length,
    columnHeights: cols.slice(0, 2).map(c => Math.round(c.getBoundingClientRect().height)),
  };
});
console.log("page height :", m.height);
console.log("overflow    :", m.overflow);
console.log("clipped text:", m.clipped);
console.log("column heights:", m.columnHeights, m.columnHeights.length === 2 ? `(gap ${Math.abs(m.columnHeights[0]-m.columnHeights[1])}px)` : "");
console.log("errors      :", errs.length);
await b.close();
