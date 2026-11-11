// Settings menu: swapped touch controls. Opens Settings from the pause menu, swaps the layout,
// checks the HUD rects (joystick right, Strike left), walks with the stick on the right, looks by
// dragging the left half, then reloads the page and checks the swap persisted.
//   NODE_PATH=/opt/node-tools/node_modules node tools/web_controls_swap_test.cjs http://localhost:8861/index.html [shotsDir]
const { chromium } = require('playwright');
const fs = require('fs');
const base = process.argv[2] || 'http://localhost:8861/index.html';
const shots = process.argv[3] || 'build/swap_shots';
fs.mkdirSync(shots, { recursive: true });
const WAKE_UP = { x: 60, y: 230 };
const dYaw = (a, b) => Math.abs(((a - b + 540) % 360) - 180);
const mid = (r) => [(r[0] + r[2]) / 2, (r[1] + r[3]) / 2];

(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  const send = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  const state = () => page.evaluate(() => window.rcState);
  const until = async (pred, ms = 90000) => {
    for (const t0 = Date.now(); Date.now() - t0 < ms; await page.waitForTimeout(500)) {
      const st = await state();
      if (st && pred(st)) return st;
    }
    throw new Error('timed out waiting for game state');
  };
  let box, s, uiW;
  // Quality changes (the automatic probe included) resize the UI space: refresh the scale from the HUD.
  const sync = async () => { const st = await state(); if (st && st.hud) { s = box.height / st.hud.viewport[3]; uiW = box.width / s; } return st; };
  const P = (x, y) => ({ x: box.x + x * s, y: box.y + y * s });
  const tapUi = async (x, y) => { await sync(); const p = P(x, y); await page.touchscreen.tap(p.x, p.y); };
  const tapRect = async (name) => { const h = (await state()).hud; await tapUi(...mid(h[name])); };
  const tapRight = async (dx, y) => { await sync(); await tapUi(uiW - dx, y); };
  const checks = [];
  // Software GL runs at a few fps: wait for the HUD flag instead of a fixed delay.
  const hudWhen = async (pred) => { let st; try { st = await until((s2) => s2.hud && pred(s2.hud), 20000); } catch (e) { st = await state(); } await sync(); return st.hud; };
  const check = (name, ok, extra = '') => { checks.push(ok); console.log(`${ok ? 'ok  ' : 'FAIL'} ${name} ${extra}`); };

  const startGame = async () => {
    await page.goto(base + (base.includes('?') ? '&' : '?') + 'debug=1');
    await page.waitForSelector('#rc-wake:not([disabled])', { timeout: 120000 });
    await page.tap('#rc-wake');
    await page.waitForFunction(() => getComputedStyle(document.getElementById('status')).display === 'none', null, { timeout: 10000, polling: 250 });
    await page.waitForFunction(() => window.rcState, null, { timeout: 90000 });
    await page.waitForTimeout(5000);
    box = await page.locator('canvas').boundingBox();
    s = box.height / 360; uiW = box.width / s;
    const w = P(WAKE_UP.x, WAKE_UP.y);
    await page.touchscreen.tap(w.x, w.y);
    await until((st) => st.scene === 'Prologue');
    await page.waitForTimeout(1500);
    await tapUi(uiW - 39, 16);
    await until((st) => !!st.player);
    await page.waitForTimeout(9000);
  };

  await startGame();
  let hud = (await state()).hud;
  check('default: joystick left', mid(hud.Joystick)[0] < hud.viewport[2] / 2);
  check('default: Strike right', mid(hud.AttackButton)[0] > hud.viewport[2] / 2);

  // Pause -> Settings -> Controls.
  await tapRight(26, 24);
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${shots}/pause_menu.png` });
  hud = (await state()).hud;
  check('pause open', hud.pause_open === true);
  await tapRect('SettingsButton');
  hud = await hudWhen((h) => h.settings_open);
  check('settings open', hud.settings_open === true && hud.pause_open === false);
  await tapRect('ControlsButton');
  await page.waitForTimeout(600);
  await page.screenshot({ path: `${shots}/settings_panel.png` });
  await tapRect('BackButton');
  hud = await hudWhen((h) => h.pause_open);
  check('back returns to pause', hud.pause_open === true && hud.settings_open === false);
  await tapRect('ResumeButton');
  hud = await hudWhen((h) => !h.pause_open);
  check('menu closed', hud.pause_open === false);
  check('swapped: joystick right half', mid(hud.Joystick)[0] > hud.viewport[2] / 2, JSON.stringify(hud.Joystick));
  check('swapped: Strike/Guard left half', mid(hud.AttackButton)[0] < hud.viewport[2] / 2 && mid(hud.BlockButton)[0] < hud.viewport[2] / 2);
  check('swapped flag', hud.controls_swapped === true);
  await page.screenshot({ path: `${shots}/swapped_hud.png` });

  // Walk with the stick on the right.
  await sync();
  const c = mid(hud.Joystick);
  let stick = { ...P(c[0], c[1]), id: 3 };
  const before = (await state()).player;
  await send('touchStart', [stick]);
  for (let i = 1; i <= 6; i++) { stick = { ...stick, y: stick.y - 5 * s }; await send('touchMove', [stick]); }
  await page.waitForTimeout(800);
  const mid1 = (await state()).player;
  await send('touchEnd', []);
  const walked = Math.hypot(mid1.pos[0] - before.pos[0], mid1.pos[2] - before.pos[2]);
  check('stick on the right walks', walked > 0.3, `${walked.toFixed(2)} m`);
  await page.waitForTimeout(500);

  // Look on the left half (above the buttons).
  const a = (await state()).player;
  await sync();
  let thumb = { ...P(uiW * 0.4, 130), id: 5 };
  await send('touchStart', [thumb]);
  for (let i = 0; i < 12; i++) { thumb = { ...thumb, x: thumb.x - 8 * s }; await send('touchMove', [thumb]); }
  await page.waitForTimeout(400);
  await send('touchEnd', []);
  const b = (await state()).player;
  check('drag on left half looks', dYaw(b.yaw, a.yaw) > 5, `${dYaw(b.yaw, a.yaw).toFixed(1)} deg`);
  // The right half must no longer look (it holds the stick).
  const a2 = (await state()).player;
  await sync();
  thumb = { ...P(uiW * 0.7, 130), id: 6 };
  await send('touchStart', [thumb]);
  for (let i = 0; i < 12; i++) { thumb = { ...thumb, x: thumb.x - 8 * s }; await send('touchMove', [thumb]); }
  await page.waitForTimeout(400);
  await send('touchEnd', []);
  const b2 = (await state()).player;
  check('drag on right half does not look', dYaw(b2.yaw, a2.yaw) < 1, `${dYaw(b2.yaw, a2.yaw).toFixed(1)} deg`);

  // Persistence across a reload.
  await page.waitForTimeout(1500);
  await page.reload();
  await startGame();
  hud = (await state()).hud;
  check('reload: swap persisted (joystick right)', mid(hud.Joystick)[0] > hud.viewport[2] / 2 && hud.controls_swapped === true);
  await page.screenshot({ path: `${shots}/swapped_after_reload.png` });
  await browser.close();
  const ok = checks.every(Boolean);
  console.log(ok ? 'PASS' : 'FAIL');
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.error(e); console.log('FAIL'); process.exit(1); });
