const assert = require('node:assert/strict');
const path = require('node:path');
const createLoader = require('./lib/ets-loader.cjs');
const colors = { COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1, COLOR_MODE_NOT_SET: -1 };
const writes = [], nativeModes = [];
let raw = '';
const ctx = { config: { colorMode: 1 }, getApplicationContext: () => ({ setColorMode: mode => nativeModes.push(mode) }) };
const load = createLoader({
  '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: colors } },
  '@kit.ArkData': { preferences: { getPreferences: async () => ({
    get: async () => raw, put: async (_, value) => { raw = value; writes.push(value); }, flush: async () => {},
  }) } },
  '@kit.CoreFileKit': {}, '@kit.ArkTS': {},
  '@kit.ArkUI': { promptAction: { showToast() {} } },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {}, error() {} } },
}, { Observed: cls => cls });
const root = path.join(__dirname, '../../entry/src/main/ets');
const { AppTheme } = load(`${root}/common/AppTheme`);
const { SettingsValidator, ThemeMode } = load(`${root}/domain/settings/AppSettings`);
const { SettingsStore } = load(`${root}/infrastructure/metadata/SettingsStore`);
const { SettingsState } = load(`${root}/features/settings/SettingsState`);
const { SettingsViewModel } = load(`${root}/features/settings/SettingsViewModel`);
const { EditorLifecycle } = load(`${root}/features/editor/EditorLifecycle`);
(async () => {
  assert.equal(SettingsValidator.defaults().theme, ThemeMode.SYSTEM);
  for (const theme of ['light', 'dark', 'system']) {
    assert.equal(SettingsValidator.parse(JSON.stringify({ theme })).theme, theme);
  }
  assert.equal(SettingsValidator.parse('{"theme":"bad"}').theme, ThemeMode.SYSTEM);
  for (const mode of [0, 1, undefined]) {
    assert.equal(AppTheme.isDark(ThemeMode.DARK, mode), true);
    assert.equal(AppTheme.isDark(ThemeMode.LIGHT, mode), false);
    assert.equal(AppTheme.isDark(ThemeMode.SYSTEM, mode), mode === 0);
  }
  const store = new SettingsStore(ctx);
  await store.load(); assert.equal(nativeModes.at(-1), -1);
  for (const [theme, expected] of [['dark', 0], ['light', 1], ['system', -1]]) {
    await store.save({ ...SettingsValidator.defaults(), theme });
    assert.equal(nativeModes.at(-1), expected); assert.equal((await store.load()).theme, theme);
  }
  const state = new SettingsState(), vm = new SettingsViewModel(state, ctx);
  state.fontSize = 21; state.autoSave = false;
  ctx.config.colorMode = 0; vm.refreshTheme(); assert.equal(state.pal.CONTENT, AppTheme.dark().CONTENT);
  ctx.config.colorMode = 1; vm.refreshTheme(); assert.equal(state.pal.CONTENT, AppTheme.light().CONTENT);
  state.themeMode = ThemeMode.DARK; vm.refreshTheme(); assert.equal(state.pal.CONTENT, AppTheme.dark().CONTENT);
  state.themeMode = ThemeMode.LIGHT; ctx.config.colorMode = 0; vm.refreshTheme();
  assert.equal(state.pal.CONTENT, AppTheme.light().CONTENT);
  assert.equal(state.fontSize, 21); assert.equal(state.autoSave, false);
  assert.equal(writes.length, 3, 'system configuration refresh must not overwrite preferences');
  const editorCalls = [], previewCalls = [], session = {};
  const editorState = { viewMode: 'split', docLength: 92, cursorLine: 5, cursorCol: 3, saveState: 'dirty' };
  const host = { state: editorState, isActive: () => true, enforceWorkspaceBudget() {},
    env: { ctx, webReady: true, previewReady: true, activeSession: session, coordinator: session,
      appSettings: SettingsValidator.defaults(), settings: { load: async () => SettingsValidator.defaults() },
      previewController: { runJavaScript: code => previewCalls.push(code) } },
    runJsValue: code => editorCalls.push(code),
  };
  const lifecycle = new EditorLifecycle(host);
  host.applyEditorStyle = () => lifecycle.applyEditorStyle();
  host.applyPreviewStyle = () => lifecycle.applyPreviewStyle();
  host.syncDocNow = () => editorCalls.push('sync');
  const before = { ...editorState };
  for (const [mode, dark] of [[0, true], [1, false]]) {
    ctx.config.colorMode = mode; lifecycle.applyAppSettings(true); await Promise.resolve();
    assert.ok(editorCalls.includes(`window.__editorApi.setTheme(${dark});`));
    assert.ok(previewCalls.includes(`window.__previewApi.setDark(${dark});`));
    assert.deepEqual({ ...editorState, pal: undefined }, { ...before, pal: undefined });
    assert.equal(host.env.activeSession, session); assert.equal(host.env.coordinator, session);
  }
  assert.equal(editorCalls.length, 8, 'theme refresh only changes four style compartments each time');
  assert.equal(previewCalls.length, 4);
  host.env.settings.load = async () => ({ ...SettingsValidator.defaults(), defaultView: 'preview' });
  lifecycle.applyAppSettings(true); await Promise.resolve();
  assert.equal(editorState.viewMode, 'preview'); assert.equal(editorCalls.at(-1), 'sync');
  editorState.viewMode = 'edit'; lifecycle.applyAppSettings(true); await Promise.resolve();
  assert.equal(editorState.viewMode, 'edit', 'unchanged preference preserves temporary view');
  editorState.bp = 'phone';
  host.env.settings.load = async () => ({ ...SettingsValidator.defaults(), defaultView: 'split' });
  lifecycle.applyAppSettings(true); await Promise.resolve();
  assert.equal(editorState.viewMode, 'edit', 'phone split preference falls back to editor');
  editorState.bp = 'pc'; lifecycle.applyAppSettings(); await Promise.resolve();
  assert.equal(editorState.viewMode, 'split', 'wide editor applies initial split preference');
  console.log('System theme checks passed: defaults, legacy choices, native modes, live palette and unchanged preferences');
})().catch(error => { console.error(error); process.exitCode = 1; });
