// Gameplay FPS of the web build in software-rendered Chromium, optionally with
// features switched off through Level's ?perf= flags, to find what costs most.
// Absolute numbers are far below a phone GPU; compare builds and flags only.
//   node tools/web_perf.cjs URL [flagset ...]
//   e.g. node tools/web_perf.cjs http://localhost:8766/index.html "" nograss "nosky,nopost"
// Then prints prologue_load_s, prologue_fps, spawn_fps and hollowmere_fps
// (Hollowmere via ?tp=20,1.5,300,180 - yaw 180 faces +Z; see Level._apply_dev_shot).
// Flags: nosky, nograss, nohorizon, nopost, nofog (see src/world/level.gd).
// RC_PERF_QUERY="&quality=1" pins a quality level (otherwise the auto-downgrade may switch to Low).
const { chromium } = require('playwright');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// The launch page (web/shell.html) covers the canvas until its "Wake up" button is tapped.
const tapBegin = async (page) => {
  await page.waitForSelector('#rc-wake:not([disabled])', { timeout: 120000 });
  await page.tap('#rc-wake');
  await page.waitForFunction(() => getComputedStyle(document.getElementById('status')).display === 'none', null, { timeout: 10000, polling: 250 });
};
// Title menu: "Wake Up" is the first text item at the left (src/ui/main_menu.tscn).
const WAKE_UP = { x: 60, y: 230 };
const countFps = (p) => p.evaluate(() => new Promise((r) => {
  let n = 0; const t0 = performance.now();
  const f = () => { n++; if (performance.now() - t0 < 4000) requestAnimationFrame(f); else r(n / 4); };
  requestAnimationFrame(f);
}));
const rcState = (p) => p.evaluate(() => window.rcState || null).catch(() => null);
// Poll rcState.scene (no waitForFunction: its rAF polling starves while loading).
async function waitScene(p, name, timeoutMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutMs) {
    const s = await rcState(p);
    if (s && s.scene === name) return true;
    await sleep(250);
  }
  throw new Error(`timeout waiting for scene ${name}`);
}
async function waitMenu(p) {
  const t0 = Date.now();
  while (Date.now() - t0 < 90000) {
    const s = await rcState(p);
    if (s && s.scene) return;
    await sleep(500);
  }
  throw new Error('menu never came up');
}
const geom = async (p) => {
  const box = await p.locator('canvas').boundingBox();
  const sc = box.height / 360;
  return { box, sc, uiW: box.width / sc };
};
async function measureAll(b, url) {
  const mk = async (q) => {
    const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true });
    const p = await ctx.newPage();
    await p.goto(`${url}?debug=1${process.env.RC_PERF_QUERY || ''}${q}`);
    await tapBegin(p);
    await waitMenu(p);
    await sleep(2000);
    return { ctx, p };
  };
  const wake = async (p) => {
    const { box, sc, uiW } = await geom(p);
    await p.touchscreen.tap(box.x + WAKE_UP.x * sc, box.y + WAKE_UP.y * sc);
  };
  const skip = async (p) => {
    const { box, sc, uiW } = await geom(p);
    await p.touchscreen.tap(box.x + (uiW - 39) * sc, box.y + 16 * sc);
  };
  {
    const { ctx, p } = await mk('');
    const t0 = Date.now();
    await wake(p);
    await waitScene(p, 'Prologue', 120000);
    await sleep(1000); // a few frames rendered
    console.log(`prologue_load_s ${((Date.now() - t0) / 1000).toFixed(1)}`);
    await sleep(2000);
    console.log(`prologue_fps ${await countFps(p)}`);
    await skip(p);
    await waitScene(p, 'ValdronOverworld', 120000);
    await sleep(3000);
    console.log(`spawn_fps ${await countFps(p)}`);
    await ctx.close();
  }
  {
    const { ctx, p } = await mk('&tp=20,1.5,300,180');
    await wake(p);
    await waitScene(p, 'Prologue', 120000);
    await sleep(1500);
    await skip(p);
    await waitScene(p, 'ValdronOverworld', 120000);
    await sleep(3000);
    console.log(`hollowmere_fps ${await countFps(p)}`);
    await ctx.close();
  }
}

(async () => {
  const [url, ...flagSets] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const flags of flagSets.length ? flagSets : ['']) {
    const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true });
    const p = await ctx.newPage();
    await p.goto(`${url}?perf=${flags}`);
    await tapBegin(p);
    await p.waitForTimeout(3000);
    const box = await p.locator('canvas').boundingBox();
    const sc = box.height / 360, uiW = box.width / sc;
    await p.touchscreen.tap(box.x + WAKE_UP.x * sc, box.y + WAKE_UP.y * sc); // Wake Up
    await p.waitForTimeout(10000);
    await p.touchscreen.tap(box.x + (uiW - 39) * sc, box.y + 16 * sc); // SKIP
    await p.waitForTimeout(22000);
    const fps = await countFps(p);
    console.log(`${(flags || 'baseline').padEnd(30)} ${fps} fps`);
    await ctx.close();
  }
  await measureAll(b, url);
  await b.close();
})().catch((e) => { console.error(e); process.exit(1); });
