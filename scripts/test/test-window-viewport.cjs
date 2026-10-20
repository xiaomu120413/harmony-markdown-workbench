const assert = require('node:assert/strict');
const path = require('node:path');
const createLoader = require('./lib/ets-loader.cjs');
const storage = new Map(), errors = [];
const load = createLoader({
  '@kit.ArkUI': { KeyboardAvoidMode: { RESIZE: 1 }, window: { AvoidAreaType: {
    TYPE_SYSTEM: 0, TYPE_CUTOUT: 1, TYPE_NAVIGATION_INDICATOR: 3,
  } } },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error: (...v) => errors.push(v) } },
}, { AppStorage: { get: k => storage.get(k), setOrCreate: (k, v) => storage.set(k, v) } });
const root = path.join(__dirname, '../../entry/src/main/ets');
const { SafeAreaPolicy } = load(`${root}/domain/editor/SafeAreaPolicy`);
const { WindowViewportAdapter } = load(`${root}/infrastructure/window/WindowViewportAdapter`);
const rect = (left = 0, top = 0, width = 0, height = 0) => ({ left, top, width, height });
const area = overrides => ({ leftRect: rect(), topRect: rect(), rightRect: rect(), bottomRect: rect(), ...overrides });
function fakeWindow() {
  return {
    events: new Map(), layouts: [], mode: undefined, broken: false,
    dimensions: { width: 720, height: 1280 },
    areas: [area({ topRect: rect(0, 0, 720, 48), bottomRect: rect(0, 1240, 720, 40) }),
      area({ topRect: rect(300, 0, 120, 60) }), area({ bottomRect: rect(0, 1240, 720, 40) })],
    async setWindowLayoutFullScreen(value) { this.layouts.push(value); },
    setWindowDecorVisible() {},
    getWindowProperties() { return { windowRect: this.dimensions }; },
    getWindowAvoidArea(type) { if (this.broken) throw new Error('injected native failure'); return this.areas[type === 3 ? 2 : type]; },
    getTitleButtonRect: () => ({ right: 0, top: 0, width: 0, height: 0 }),
    getUIContext() { return { px2vp: v => v / 2, setKeyboardAvoidMode: mode => { this.mode = mode; } }; },
    on(type, cb) { this.events.set(type, cb); },
    off(type, cb) { assert.equal(this.events.get(type), cb); this.events.delete(type); },
  };
}
(async () => {
  const w = fakeWindow();
  assert.deepEqual(SafeAreaPolicy.resolve(w.areas, 720, 1280, 2), { left: 0, top: 30, right: 0, bottom: 20 });
  assert.deepEqual(SafeAreaPolicy.resolve([area({ leftRect: rect(0, 0, 36, 720), rightRect: rect(1248, 0, 32, 720) })],
    1280, 720, 2), { left: 18, top: 0, right: 16, bottom: 0 });
  assert.deepEqual(SafeAreaPolicy.resolve([area()], 720, 1280, 2), { left: 0, top: 0, right: 0, bottom: 0 });
  const adapter = new WindowViewportAdapter(); await adapter.attach(w);
  assert.equal(w.mode, 1); assert.deepEqual(w.layouts, [true]); assert.equal(w.events.size, 4);
  assert.equal(storage.get('safeTop'), 30); assert.equal(storage.get('safeBottom'), 20);
  w.events.get('keyboardHeightChange')(500);
  assert.equal(storage.get('keyboardVisible'), true);
  assert.equal(storage.get('safeBottom'), 20); // Never add the 500px keyboard to safe insets.
  w.events.get('keyboardHeightChange')(0); assert.equal(storage.get('keyboardVisible'), false);
  w.dimensions = { width: 1280, height: 720 };
  w.areas = [area({ leftRect: rect(0, 0, 40, 720) }), area(), area()];
  w.events.get('windowSizeChange')();
  assert.equal(storage.get('safeTop'), 0); assert.equal(storage.get('safeLeft'), 20);
  w.broken = true; w.events.get('avoidAreaChange')(); await Promise.resolve();
  assert.equal(w.layouts.at(-1), false); assert.equal(storage.get('safeLeft'), 0);
  adapter.detach(); assert.equal(w.events.size, 0); assert.equal(storage.get('keyboardVisible'), false);
  assert.ok(errors.length > 0);
  const broken = fakeWindow(); broken.broken = true;
  await adapter.attach(broken); assert.equal(broken.layouts.at(-1), false); adapter.detach();
  console.log('8 viewport scenarios passed (overlap, rotation, empty, keyboard resize, dynamic failure, fallback, cleanup, units)');
})().catch(error => { console.error(error); process.exitCode = 1; });
