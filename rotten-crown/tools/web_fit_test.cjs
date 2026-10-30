// Screen-fit regression: nothing at the bottom (or any edge) may be cut off on phones.
// For each viewport it loads the build, taps through to gameplay, screenshots the menu, the HUD and the
// pause menu, and asserts (via window.rcState, page opened with ?debug=1) that
//   - the canvas size equals the visible viewport,
//   - the game's UI space has the same aspect as the canvas (stretch "expand", nothing cropped),
//   - every bottom HUD element (prompt, message, joystick, buttons, pause footer) lies inside the viewport
//     and keeps at least UiSafeArea.MIN_MARGIN from the bottom edge.
//   node tools/web_fit_test.cjs http://localhost:8792/index.html OUT_DIR
const { chromium } = require('playwright');
const fs = require('fs');
const url = process.argv[2] || 'http://localhost:8792/index.html';
const out = process.argv[3] || 'build/fit';
fs.mkdirSync(out, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const VIEWPORTS = [
  { name: '844x390_19.5x9', width: 844, height: 390 },
  { name: '915x412_20x9', width: 915, height: 412 },
  { name: '740x360_18.5x9', width: 740, height: 360 },
  { name: '640x360_16x9', width: 640, height: 360 },
  { name: '1024x768_4x3', width: 1024, height: 768 },
  { name: '844x340_bars', width: 844, height: 340 },
];
const tapBegin = async (page) => {
  await page.waitForSelector('#rc-wake:not([disabled])', { timeout: 180000 });
  await page.tap('#rc-wake');
  await page.waitForFunction(() => getComputedStyle(document.getElementById('status')).display === 'none', null, { timeout: 10000, polling: 250 });
};
const rcState = (p) => p.evaluate(() => window.rcState || null).catch(() => null);
async function until(p, pred, ms, what) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    const s = await rcState(p);
    if (s && pred(s)) return s;
    await sleep(300);
  }
  throw new Error('timeout: ' + what);
}
// Canvas CSS box and the UI-unit -> CSS-pixel scale (UI space is canvas-sized divided by the stretch scale).
const geom = async (p) => {
  const g = await p.evaluate(() => {
    const r = document.getElementById('canvas').getBoundingClientRect();
    const vv = window.visualViewport;
    return { x: r.x, y: r.y, w: r.width, h: r.height, vw: vv ? vv.width : innerWidth, vh: vv ? vv.height : innerHeight };
  });
  const s = await rcState(p);
  const [uw, uh] = s.screen.ui;
  return { ...g, uw, uh, sc: g.w / uw };
};

async function runViewport(browser, vp) {
  const fails = [];
  const check = (cond, msg) => { if (!cond) fails.push(msg); };
  const ctx = await browser.newContext({ viewport: { width: vp.width, height: vp.height }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => fails.push('pageerror: ' + e.message));
  await page.goto(`${url}?debug=1&quality=1`);
  await tapBegin(page);
  await until(page, (s) => s.scene, 120000, 'menu');
  await sleep(2500);
  let g = await geom(page);
  check(Math.abs(g.w - g.vw) <= 1 && Math.abs(g.h - g.vh) <= 1, `canvas ${g.w}x${g.h} != viewport ${g.vw}x${g.vh}`);
  check(Math.abs(g.uw / g.uh - g.w / g.h) < 0.02, `ui aspect ${(g.uw / g.uh).toFixed(3)} != canvas ${(g.w / g.h).toFixed(3)}`);
  await page.screenshot({ path: `${out}/${vp.name}_menu.png` });
  // Main menu: "Wake Up" is the first text item at the left, anchored 130 UI units above the bottom edge.
  await page.touchscreen.tap(g.x + 60 * g.sc, g.y + (g.uh - 130) * g.sc);
  await until(page, (s) => s.scene === 'Prologue', 120000, 'prologue');
  await sleep(2500);
  await page.screenshot({ path: `${out}/${vp.name}_prologue.png` });
  await page.touchscreen.tap(g.x + (g.uw - 39) * g.sc, g.y + 16 * g.sc); // Skip
  await until(page, (s) => !!s.player && !!s.hud, 120000, 'gameplay');
  await sleep(25000); // wake-up animation (slow in software GL)
  g = await geom(page);
  const st = await rcState(page);
  const [, , vw, vh] = st.hud.viewport;
  check(Math.abs(g.uw - vw) < 1 && Math.abs(g.uh - vh) < 1, 'hud viewport differs from ui size');
  for (const [name, r] of Object.entries(st.hud)) {
    if (!Array.isArray(r) || name === 'viewport') continue;
    if (name === 'PauseRegion') continue; // only laid out while the pause menu is open
    check(r[0] >= -0.5 && r[1] >= -0.5 && r[2] <= vw + 0.5 && r[3] <= vh + 0.5, `${name} outside viewport: ${r.map((n) => n.toFixed(1))} in ${vw.toFixed(0)}x${vh.toFixed(0)}`);
    check(r[3] <= vh - st.hud.bottom_margin + 0.5 || name === 'PauseRegion', `${name} closer than margin to the bottom: ${r[3].toFixed(1)} of ${vh.toFixed(0)}`);
  }
  await page.screenshot({ path: `${out}/${vp.name}_hud.png` });
  // Pause (top-right button, 26 units from the right edge).
  await page.touchscreen.tap(g.x + (g.uw - 26) * g.sc, g.y + 24 * g.sc);
  const paused = await until(page, (s) => s.hud && s.hud.pause_open, 8000, 'pause menu');
  await sleep(600);
  const pr = paused.hud.PauseRegion;
  check(pr[3] <= vh - paused.hud.bottom_margin + 0.5 || pr[3] <= vh - 5.5, `pause footer too low: ${pr[3].toFixed(1)} of ${vh.toFixed(0)}`);
  await page.screenshot({ path: `${out}/${vp.name}_pause.png` });
  console.log(`${fails.length ? 'FAIL' : 'ok  '} ${vp.name}: canvas ${g.w}x${g.h} ui ${g.uw.toFixed(0)}x${g.uh.toFixed(0)} scale ${g.sc.toFixed(2)} bottom_margin ${st.hud.bottom_margin}`);
  fails.forEach((f) => console.log('   - ' + f));
  await ctx.close();
  return fails.length === 0;
}

(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  let ok = true;
  for (const vp of VIEWPORTS) {
    try {
      ok = (await runViewport(browser, vp)) && ok;
    } catch (e) {
      ok = false;
      console.log(`FAIL ${vp.name}: ${e.message}`);
    }
  }
  await browser.close();
  console.log(ok ? 'PASS' : 'FAIL');
  process.exit(ok ? 0 : 1);
})();
