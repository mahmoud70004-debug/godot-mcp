// Gameplay FPS of the web build in software-rendered Chromium, optionally with
// features switched off through Level's ?perf= flags, to find what costs most.
// Absolute numbers are far below a phone GPU; compare builds and flags only.
//   node tools/web_perf.cjs http://localhost:8766/index.html "" nograss "nosky,nopost"
// Flags: nosky, nograss, nohorizon, nopost, nofog (see src/world/level.gd).
const { chromium } = require('playwright');
(async () => {
  const [url, ...flagSets] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const flags of flagSets.length ? flagSets : ['']) {
    const ctx = await b.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true });
    const p = await ctx.newPage();
    await p.goto(`${url}?perf=${flags}`);
    await p.waitForTimeout(7000);
    const box = await p.locator('canvas').boundingBox();
    const sc = box.height / 360, uiW = box.width / sc;
    await p.touchscreen.tap(box.x + (uiW / 2) * sc, box.y + 222 * sc); // Wake Up
    await p.waitForTimeout(10000);
    await p.touchscreen.tap(box.x + (uiW - 39) * sc, box.y + 16 * sc); // SKIP
    await p.waitForTimeout(22000);
    const fps = await p.evaluate(() => new Promise((r) => {
      let n = 0; const t0 = performance.now();
      const f = () => { n++; if (performance.now() - t0 < 4000) requestAnimationFrame(f); else r(n / 4); };
      requestAnimationFrame(f);
    }));
    console.log(`${(flags || 'baseline').padEnd(30)} ${fps} fps`);
    await ctx.close();
  }
  await b.close();
})();
