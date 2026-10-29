// Regression test: "the view jumps while using the joystick".
// The right thumb rests on the look area while the left thumb drives the
// joystick; the resting thumb then jitters by 1px. The camera must not
// move more than a degree, while a deliberate drag must still turn it.
// Reads window.rcState published by DebugBridge (page opened with ?debug=1).
//   node tools/web_touch_repro.cjs http://localhost:8766/index.html
const { chromium } = require('playwright');
const base = process.argv[2] || 'http://localhost:8766/index.html';
// The launch page (web/shell.html) covers the canvas until its "Wake up" button is tapped.
const tapBegin = async (page) => {
  await page.waitForSelector('#rc-wake:not([disabled])', { timeout: 120000 });
  await page.tap('#rc-wake');
  await page.waitForFunction(() => getComputedStyle(document.getElementById('status')).display === 'none', null, { timeout: 10000, polling: 250 });
};
// Title menu: "Wake Up" is the first text item at the left (src/ui/main_menu.tscn).
const WAKE_UP = { x: 60, y: 230 };
(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await page.goto(base + (base.includes('?') ? '&' : '?') + 'debug=1');
  await tapBegin(page);
  await page.waitForFunction(() => window.rcState, null, { timeout: 90000 });
  await page.waitForTimeout(5000); // let the menu settle before tapping
  const box = await page.locator('canvas').boundingBox();
  const s = box.height / 360, uiW = box.width / s;
  const P = (x, y) => ({ x: box.x + x * s, y: box.y + y * s });
  const send = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  const state = () => page.evaluate(() => window.rcState);
  // Poll with evaluate(): waitForFunction's rAF polling starves while Godot loads a scene.
  const until = async (pred, ms = 90000) => {
    for (const t0 = Date.now(); Date.now() - t0 < ms; await page.waitForTimeout(500)) {
      const st = await state();
      if (st && pred(st)) return st;
    }
    throw new Error('timed out waiting for game state');
  };
  const wake = P(WAKE_UP.x, WAKE_UP.y);
  await page.touchscreen.tap(wake.x, wake.y);          // Wake Up -> prologue
  await until((st) => st.scene === 'Prologue');
  await page.waitForTimeout(1500);
  const skip = P(uiW - 39, 16);
  await page.touchscreen.tap(skip.x, skip.y);          // SKIP >>
  await until((st) => !!st.player);
  await page.waitForTimeout(9000);                     // wake-up animation

  let thumb = { ...P(uiW * 0.8, 150), id: 7 };
  let stick = { ...P(80, 280), id: 3 };
  await send('touchStart', [thumb]);
  await send('touchStart', [thumb, stick]);
  for (let i = 1; i <= 6; i++) { stick = { ...stick, y: stick.y - 5 * s }; await send('touchMove', [thumb, stick]); }
  await page.waitForTimeout(500);
  const before = (await state()).player;
  for (let i = 0; i < 4; i++) { thumb = { ...thumb, x: thumb.x + (i % 2 ? -1 : 1) }; await send('touchMove', [thumb, stick]); await page.waitForTimeout(60); }
  await page.waitForTimeout(300);
  const after = (await state()).player;
  const jitterTurn = Math.abs(after.yaw - before.yaw) + Math.abs(after.pitch - before.pitch);
  const walked = Math.hypot(after.pos[0] - before.pos[0], after.pos[2] - before.pos[2]);

  // Deliberate 120px drag with the look thumb must still turn the camera.
  for (let i = 0; i < 12; i++) { thumb = { ...thumb, x: thumb.x - 10 * s }; await send('touchMove', [thumb, stick]); }
  await page.waitForTimeout(300);
  const turned = (await state()).player;
  const lookTurn = Math.abs(turned.yaw - after.yaw);
  await send('touchEnd', []);
  await browser.close();

  console.log(`jitter turn: ${jitterTurn.toFixed(2)} deg | walked while stick held: ${walked.toFixed(2)} m | deliberate look: ${lookTurn.toFixed(2)} deg`);
  const ok = jitterTurn < 1.0 && lookTurn > 5.0 && walked > 0.3;
  console.log(ok ? 'PASS' : 'FAIL');
  process.exit(ok ? 0 : 1);
})();
