// Browser smoke test for the Web export, emulating a landscape phone with touch.
//   node tools/web_smoke_test.cjs http://localhost:8765/index.html out_dir
// Taps "Wake Up", walks through the gate with the virtual joystick, looks
// around with the right-half drag, opens the bag, and saves screenshots.
// Exits non-zero if the page throws or Godot prints an ERROR / SCRIPT ERROR.
const { chromium } = require('playwright');
const fs = require('fs');

const url = process.argv[2] || 'http://localhost:8765/index.html';
const out = process.argv[3] || 'build/smoke';
const UI_H = 360; // project viewport height

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const remote = !/^https?:\/\/(localhost|127\.0\.0\.1)/.test(url);
  const proxyUrl = process.env.HTTPS_PROXY || process.env.https_proxy;
  const browser = await chromium.launch({
    ...(remote && proxyUrl ? { proxy: { server: proxyUrl } } : {}),
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
  });
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  const cdp = await ctx.newCDPSession(page);

  await page.goto(url);
  await page.waitForFunction(() => document.querySelector('#status') && getComputedStyle(document.querySelector('#status')).display === 'none' || performance.now() > 60000, null, { timeout: 90000 }).catch(() => {});
  await page.waitForTimeout(4000);
  const box = await page.locator('canvas').boundingBox();
  const scale = box.height / UI_H;
  const uiW = box.width / scale;
  const P = (ux, uy) => ({ x: box.x + ux * scale, y: box.y + uy * scale });
  const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points.map((p, i) => ({ x: p.x, y: p.y, id: p.id ?? i })) });
  const shot = (name) => page.screenshot({ path: `${out}/${name}.png` });

  await shot('01_menu');
  await page.touchscreen.tap(P(uiW / 2, UI_H - 138).x, P(uiW / 2, UI_H - 138).y); // "Wake Up"
  await page.waitForTimeout(9000);
  await shot('02a_prologue');
  const skip = P(uiW - 39, 16);
  await page.touchscreen.tap(skip.x, skip.y); // "SKIP >>"
  await page.waitForTimeout(12000);
  await shot('02_wake');      // eyes opening in the meadow
  await page.waitForTimeout(8000); // wake-up animation keeps input locked
  await shot('02b_awake');

  // Walk forward: hold the joystick (centre 80, 280) pushed up.
  const stick = P(80, 280);
  await touch('touchStart', [{ ...stick, id: 1 }]);
  for (let i = 0; i <= 10; i++) await touch('touchMove', [{ x: stick.x, y: stick.y - i * 4 * scale, id: 1 }]);
  await page.waitForTimeout(8500);
  await shot('03_gate');
  await page.waitForTimeout(3000);
  await touch('touchEnd', []);
  await shot('04_courtyard');

  // Look around: drag on the right half while standing still.
  const look = P(uiW * 0.75, 180);
  await touch('touchStart', [{ ...look, id: 2 }]);
  for (let i = 1; i <= 20; i++) await touch('touchMove', [{ x: look.x - i * 6 * scale, y: look.y, id: 2 }]);
  await touch('touchEnd', []);
  await page.waitForTimeout(800);
  await shot('05_look');

  // Attack once, then open the bag (top-right "BAG" button).
  const atk = P(uiW - 59, UI_H - 69);
  await page.touchscreen.tap(atk.x, atk.y);
  await page.waitForTimeout(400);
  await shot('06_attack');
  await page.waitForTimeout(800);
  const bag = P(uiW - 74, 18);
  await page.touchscreen.tap(bag.x, bag.y);
  await page.waitForTimeout(1200);
  await shot('07_bag');

  fs.writeFileSync(`${out}/console.txt`, logs.join('\n'));
  await browser.close();
  const bad = logs.filter((l) => /pageerror|SCRIPT ERROR|ERROR:/.test(l));
  console.log(logs.join('\n'));
  if (bad.length) {
    console.error(`\nFAILED: ${bad.length} error line(s)`);
    process.exit(1);
  }
  console.log(`\nOK - screenshots in ${out}`);
})();
