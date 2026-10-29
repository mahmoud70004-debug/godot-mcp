// Camera-turn stutter measurement. For each location, on a FRESH page load (cold shaders), performs a 4 s
// standing-still baseline and two full 360-degree yaw sweeps (look drag on the right half of the screen),
// recording every requestAnimationFrame interval. Sweep 1 (cold) vs sweep 2 (warm) shows compile hitches.
//   node tools/web_turn_test.cjs URL [--cpu N] [--quality 0|1|2] [--out file.json] [--sweep-s 7]
// Needs a build with the DebugBridge render stats (?debug=1). Software Chromium: use relative numbers.
const { chromium } = require('playwright');
const fs = require('fs');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const url = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const cpu = Number(opt('--cpu', 1)), quality = opt('--quality', '1'), out = opt('--out', ''), sweepS = Number(opt('--sweep-s', 7));
if (!url) { console.error('usage: node tools/web_turn_test.cjs URL [--cpu N] [--quality 0|1|2] [--out f.json]'); process.exit(2); }
const LOCS = [
  { name: 'spawn', q: '' },
  { name: 'hollowmere', q: '&tp=20,1.5,300,180' },
  { name: 'wood', q: '&tp=126,0,151,40' },
];
const WAKE_UP = { x: 60, y: 230 };
const tapBegin = async (page) => {
  await page.waitForSelector('#rc-wake:not([disabled])', { timeout: 120000 });
  await page.tap('#rc-wake');
  await page.waitForFunction(() => getComputedStyle(document.getElementById('status')).display === 'none', null, { timeout: 10000, polling: 250 });
};
const rcState = (p) => p.evaluate(() => window.rcState || null).catch(() => null);
async function waitScene(p, name, ms) {
  for (const t0 = Date.now(); Date.now() - t0 < ms; await sleep(250)) {
    const s = await rcState(p);
    if (s && s.scene === name) return;
  }
  throw new Error('timeout waiting for scene ' + name);
}
async function waitMenu(p) {
  for (const t0 = Date.now(); Date.now() - t0 < 90000; await sleep(500)) { const s = await rcState(p); if (s && s.scene) return; }
  throw new Error('menu never came up');
}
const pct = (a, q) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(q * s.length))] : 0; };
function summarize(intervals, renders) {
  const n = intervals.length, total = intervals.reduce((a, b) => a + b, 0);
  const dc = renders.map((r) => r.draw_calls), pr = renders.map((r) => r.primitives), pm = renders.map((r) => r.process_ms);
  const avg = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
  return {
    frames: n, secs: +(total / 1000).toFixed(1), fps: +(n / (total / 1000)).toFixed(2),
    p50: +pct(intervals, 0.5).toFixed(1), p95: +pct(intervals, 0.95).toFixed(1), max: +Math.max(0, ...intervals).toFixed(1),
    h50: intervals.filter((x) => x > 50).length, h100: intervals.filter((x) => x > 100).length,
    dc_avg: Math.round(avg(dc)), dc_max: Math.max(0, ...dc), prim_avg: Math.round(avg(pr)), prim_max: Math.max(0, ...pr),
    proc_ms_avg: +avg(pm).toFixed(1), samples: renders.length,
  };
}
async function runLocation(browser, loc) {
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, isMobile: true, hasTouch: true });
  const p = await ctx.newPage();
  const cdp = await ctx.newCDPSession(p);
  if (cpu > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: cpu });
  await p.goto(`${url}${url.includes('?') ? '&' : '?'}debug=1&quality=${quality}${loc.q}`);
  await tapBegin(p);
  await waitMenu(p);
  await sleep(2000);
  const box = await p.locator('canvas').boundingBox();
  const sc = box.height / 360, uiW = box.width / sc;
  await p.touchscreen.tap(box.x + WAKE_UP.x * sc, box.y + WAKE_UP.y * sc);
  await waitScene(p, 'Prologue', 120000);
  await sleep(1500);
  await p.touchscreen.tap(box.x + (uiW - 39) * sc, box.y + 16 * sc);
  await waitScene(p, 'ValdronOverworld', 120000);
  await sleep(3000);
  const send = (type, pts) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  const yaw = async () => { const s = await rcState(p); return s && s.player ? s.player.yaw : null; };
  // Recorder: rAF intervals + rcState.render samples, reset per phase.
  await p.evaluate(() => {
    window.__rec = { on: false, iv: [], rn: [], last: 0, lastRn: null };
    const f = (t) => {
      const r = window.__rec;
      if (r.on) {
        if (r.last) r.iv.push(t - r.last);
        r.last = t;
        const s = window.rcState;
        if (s && s.render && s.render !== r.lastRn) { r.lastRn = s.render; r.rn.push(s.render); }
      }
      requestAnimationFrame(f);
    };
    requestAnimationFrame(f);
  });
  const rec = (on) => p.evaluate((o) => { const r = window.__rec; if (o) { r.iv = []; r.rn = []; r.last = 0; r.lastRn = null; } r.on = o; return { iv: r.iv, rn: r.rn }; }, on);
  const res = { location: loc.name };
  await rec(true); await sleep(4000);
  const still = await rec(false);
  res.still = summarize(still.iv, still.rn);
  // Look drag: right half, horizontal strokes, re-anchored near the edge; unwrapped yaw tracks progress.
  const y0 = box.y + box.height * 0.5, xa = box.x + box.width * 0.55, xb = box.x + box.width * 0.95;
  const id = 11, STEP_PX = 36; // css px per drag event (about 10 deg; MAX_LOOK_STEP caps one event at 48 viewport px)
  const delta = (a, b) => ((b - a + 540) % 360) - 180;
  // Drags to the right in STEP_PX steps every stepMs; re-anchors at xa when reaching xb. Tracks unwrapped yaw.
  async function drag(targetDeg, stepMs, steps, record) {
    let prev = await yaw(), total = 0, x = xa, down = false, n = 0;
    if (record) await rec(true);
    const t0 = Date.now();
    while ((steps ? n < steps : Math.abs(total) < targetDeg) && Date.now() - t0 < 60000) {
      if (!down) { x = xa; await send('touchStart', [{ x, y: y0, id }]); down = true; }
      x += STEP_PX; n++;
      await send('touchMove', [{ x, y: y0, id }]);
      await sleep(stepMs);
      if (n % 3 === 0 || x + STEP_PX > xb) { // yaw readback costs a frame on slow machines: only every 3rd step
        const cur = await yaw();
        if (cur !== null && prev !== null) { total += delta(prev, cur); prev = cur; }
      }
      if (x + STEP_PX > xb) { await send('touchEnd', []); down = false; }
    }
    if (down) await send('touchEnd', []);
    const r = record ? await rec(false) : null;
    return { total, secs: (Date.now() - t0) / 1000, n, r };
  }
  // Wait until look responds (the wake-up animation may lock input), measuring degrees per step.
  let degPerStep = 0;
  for (let k = 0; k < 30 && !degPerStep; k++) {
    const c = await drag(0, 20, 6, false);
    if (Math.abs(c.total) > 1) degPerStep = Math.abs(c.total) / c.n; else await sleep(1000);
  }
  if (!degPerStep) throw new Error('look input never responded at ' + loc.name);
  // Steady rate: one step every stepMs (CDP dispatch latency adds on slow machines; sweep_s is reported).
  const stepMs = Math.max(0, Math.round((degPerStep * 1000 * sweepS) / 360));
  res.calib = { degPerStep: +degPerStep.toFixed(2), stepMs };
  for (const key of ['sweep1', 'sweep2']) {
    const d = await drag(360, stepMs, 0, true);
    res[key] = { ...summarize(d.r.iv, d.r.rn), yaw_covered: +Math.abs(d.total).toFixed(0), sweep_s: +d.secs.toFixed(1) };
  }
  await ctx.close();
  return res;
}
(async () => {
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const results = [];
  for (const loc of LOCS) {
    try { results.push(await runLocation(browser, loc)); } catch (e) { console.error(loc.name, 'FAILED:', e.message); results.push({ location: loc.name, error: e.message }); }
  }
  await browser.close();
  const cols = ['fps', 'p50', 'p95', 'max', 'h50', 'h100', 'dc_avg', 'dc_max', 'prim_avg', 'prim_max', 'proc_ms_avg'];
  console.log(`url=${url} cpu=${cpu} quality=${quality}`);
  console.log(['location/phase'.padEnd(20), 'yaw', 'secs', ...cols.map((c) => c.padStart(9))].join(' '));
  for (const r of results) {
    if (r.error) { console.log(r.location.padEnd(20), 'ERROR', r.error); continue; }
    for (const ph of ['still', 'sweep1', 'sweep2']) {
      const s = r[ph];
      console.log([`${r.location}/${ph}`.padEnd(20), String(s.yaw_covered ?? '-').padStart(3), String(s.sweep_s ?? s.secs).padStart(5), ...cols.map((c) => String(s[c]).padStart(9))].join(' '));
    }
  }
  if (out) fs.writeFileSync(out, JSON.stringify({ url, cpu, quality, results }, null, 1));
})().catch((e) => { console.error(e); process.exit(1); });
