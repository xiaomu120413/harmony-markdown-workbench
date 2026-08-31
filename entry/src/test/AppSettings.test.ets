import { describe, expect, it } from '@ohos/hypium';
import { AppSettings, SettingsValidator, ThemeMode, DefaultView } from '../main/ets/domain/settings/AppSettings';

/**
 * M5-03 设置领域：解析/校验/非法值回退（验收：非法值回退默认值）。
 */
export default function appSettingsTest(): void {
  describe('AppSettingsValidator', () => {
    it('empty_raw_returns_defaults', 0, () => {
      const s = SettingsValidator.parse('');
      expect(s.fontSize).assertEqual(15);
      expect(s.theme).assertEqual(ThemeMode.LIGHT);
      expect(s.autoSave).assertTrue();
    });

    it('corrupt_json_returns_defaults', 0, () => {
      const s = SettingsValidator.parse('{not json');
      expect(s.fontSize).assertEqual(15);
      expect(s.wrap).assertTrue();
    });

    it('valid_values_roundtrip', 0, () => {
      const raw = JSON.stringify({ theme: 'dark', fontSize: 18, wrap: false, lineNumbers: false, autoSave: false, defaultView: 'split' });
      const s = SettingsValidator.parse(raw);
      expect(s.theme).assertEqual(ThemeMode.DARK);
      expect(s.fontSize).assertEqual(18);
      expect(s.wrap).assertFalse();
      expect(s.lineNumbers).assertFalse();
      expect(s.autoSave).assertFalse();
      expect(s.defaultView).assertEqual(DefaultView.SPLIT);
    });

    it('font_out_of_range_falls_back', 0, () => {
      expect(SettingsValidator.clampFont(8)).assertEqual(15);
      expect(SettingsValidator.clampFont(99)).assertEqual(15);
      expect(SettingsValidator.clampFont(undefined)).assertEqual(15);
      expect(SettingsValidator.clampFont(14.6)).assertEqual(15);
    });

    it('unknown_enum_falls_back', 0, () => {
      const s = SettingsValidator.parse(JSON.stringify({ theme: 'neon', defaultView: 'tab' }));
      expect(s.theme).assertEqual(ThemeMode.LIGHT);
      expect(s.defaultView).assertEqual(DefaultView.EDIT);
    });

    it('dirty_field_missing_falls_back_individually', 0, () => {
      const s = SettingsValidator.parse(JSON.stringify({ fontSize: 20 }));
      expect(s.fontSize).assertEqual(20);
      expect(s.wrap).assertTrue(); // 未提供 → 默认值
      expect(s.autoSave).assertTrue();
    });
  });
}