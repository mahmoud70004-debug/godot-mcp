// Browser smoke test for the Web export, emulating a landscape phone with touch.
//   node tools/web_smoke_test.cjs http://localhost:8765/index.html out_dir
// Taps "Wake Up", walks from the wake-up spot through the kingdom gate with the
// virtual joystick (the knight wakes facing it), looks around with the right-half
// drag, opens the bag, then reloads with ?tp= into the Outer Ward courtyard at the
// citadel (it lies ~200 m up the King's Road) and checks the player stands there.
// Saves screenshots.
// Exits non-zero if the page throws or Godot prints an ERROR / SCRIPT ERROR.
const { chromium } = require('playwright');
const fs = require('fs');

const url = process.argv[2] || 'http://localhost:8765/index.html';
const out = process.argv[3] || 'build/smoke';
const UI_H = 360; // project viewport height
// The launch page (web/shell.html) covers the canvas until its "Wake up" button is tapped.
const tapBegin = async (page) => {
  await page.waitForSelector('#rc-wake:not([disabled])', { timeout: 120000 });
  await page.tap('#rc-wake');
  await page.waitForFunction(() => getComputedStyle(document.getElementById('status')).display === 'none', null, { timeout: 10000, polling: 250 });
};
// Title menu: "Wake Up" is the first text item at the left (src/ui/main_menu.tscn).
const WAKE_UP = { x: 60, y: 230 };

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

  const query = (extra) => url + (url.includes('?') ? '&' : '?') + 'debug=1' + extra;
  await page.goto(query(''));
  await page.waitForTimeout(1500);
  await page.screenshot({ path: `${out}/00_launch.png` });
  await tapBegin(page);
  await page.waitForTimeout(4000);
  const box = await page.locator('canvas').boundingBox();
  const scale = box.height / UI_H;
  const uiW = box.width / scale;
  const P = (ux, uy) => ({ x: box.x + ux * scale, y: box.y + uy * scale });
  const touch = (type, points) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: points.map((p, i) => ({ x: p.x, y: p.y, id: p.id ?? i })) });
  const shot = (name) => page.screenshot({ path: `${out}/${name}.png` });
  // Title menu -> "Wake Up" -> skip the prologue -> wait for the overworld.
  const enterOverworld = async (prefix) => {
    await page.touchscreen.tap(P(WAKE_UP.x, WAKE_UP.y).x, P(WAKE_UP.x, WAKE_UP.y).y); // "Wake Up"
    await page.waitForTimeout(9000);
    if (prefix) await shot(prefix);
    const skip = P(uiW - 39, 16);
    await page.touchscreen.tap(skip.x, skip.y); // "SKIP >>"
    let scene = '';
    for (let i = 0; i < 240 && scene !== 'ValdronOverworld'; i++) { // up to 60 s
      scene = await page.evaluate(() => (window.rcState && window.rcState.scene) || '').catch(() => '');
      if (scene !== 'ValdronOverworld') await page.waitForTimeout(250);
    }
    if (scene !== 'ValdronOverworld') logs.push(`[pageerror] expected scene ValdronOverworld after SKIP, got "${scene}"`);
    await page.waitForTimeout(4000);
  };

  await shot('01_menu');
  await enterOverworld('02a_prologue');
  await shot('02_wake');      // eyes opening on the plains, facing the kingdom gate
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
  await shot('04_inside_gate'); // the fork: King's Road (right) and the pumpkin road
  const walked = await page.evaluate(() => window.rcState && window.rcState.player && window.rcState.player.pos).catch(() => null);
  if (!walked || walked[2] < 36) logs.push(`[pageerror] expected the joystick walk to head for the kingdom gate (z >= 36), player at ${JSON.stringify(walked)}`);

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
  const bag = P(uiW - 70, 24);
  await page.touchscreen.tap(bag.x, bag.y);
  await page.waitForTimeout(1200);
  await shot('07_bag');

  // The Outer Ward at the citadel: reload straight into its courtyard (?tp=x,y,z,yaw).
  await page.goto(query('&tp=125,1,214,180'));
  await page.waitForTimeout(1500);
  await tapBegin(page);
  await page.waitForTimeout(4000);
  await enterOverworld('');
  await page.waitForTimeout(8000); // wake-up animation
  await shot('08_ward_court');
  const ward = await page.evaluate(() => window.rcState && window.rcState.player && window.rcState.player.pos).catch(() => null);
  if (!ward || Math.hypot(ward[0] - 125, ward[2] - 214) > 3) logs.push(`[pageerror] expected the player in the ward courtyard (125, 214), got ${JSON.stringify(ward)}`);

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
