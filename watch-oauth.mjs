import { chromium } from "playwright";
import fs from "node:fs";

const cid = fs.readFileSync("_c.txt", "utf-8").trim();
const URI = "http://localhost/api/auth/callback/google";
const DEADLINE = Date.now() + 25 * 60 * 1000;

const b = await chromium.launch();

async function registered() {
  const ctx = await b.newContext();
  const p = await ctx.newPage();
  try {
    await p.goto("https://accounts.google.com/o/oauth2/v2/auth?" + new URLSearchParams({
      client_id: cid, redirect_uri: URI, response_type: "code", scope: "openid email profile",
    }), { waitUntil: "domcontentloaded", timeout: 40000 });
    await p.waitForTimeout(2200);
    const t = await p.evaluate(() => document.body.innerText);
    return !/redirect_uri_mismatch|Access blocked/i.test(t);
  } catch {
    return false;
  } finally {
    await ctx.close();
  }
}

while (Date.now() < DEADLINE) {
  if (await registered()) {
    console.log("REGISTERED — http://localhost/api/auth/callback/google is now accepted by Google.");
    await b.close();
    process.exit(0);
  }
  await new Promise((r) => setTimeout(r, 30000));
}

console.log("TIMED OUT after 25 min — the URI is still not registered.");
await b.close();
process.exit(1);
