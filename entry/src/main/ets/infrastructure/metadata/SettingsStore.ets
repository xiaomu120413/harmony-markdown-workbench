import { MuLogger } from '../../common/MuLogger';
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppSettings, SettingsValidator, ThemeMode } from '../../domain/settings/AppSettings';

/**
 * 设置持久化（M5-03：重启后保持；损坏/非法 → 校验器回退默认值）。
 * preferences 键：settings（AppSettings JSON 序列化）。
 */
export class SettingsStore {
  private readonly ctx: common.UIAbilityContext;
  private readonly prefName: string = 'hmwb_metadata';
  private readonly key: string = 'settings';

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  async load(): Promise<AppSettings> {
    let settings: AppSettings;
    try {
      const prefs = await preferences.getPreferences(this.ctx, this.prefName);
      const raw = (await prefs.get(this.key, '')) as string;
      settings = SettingsValidator.parse(raw);
    } catch (e) {
      settings = SettingsValidator.defaults();
    }
    this.applyNativeTheme(settings);
    return settings;
  }

  /** 自绘配色与系统菜单、三键使用相同模式，避免深色页面上的黑色控件。 */
  private applyNativeTheme(settings: AppSettings): void {
    try {
      this.ctx.getApplicationContext().setColorMode(settings.theme === ThemeMode.SYSTEM
        ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET : settings.theme === ThemeMode.DARK
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (e) {
      MuLogger.warn(`native theme unavailable: ${String(e)}`);
    }
  }

  async save(settings: AppSettings): Promise<void> {
    const prefs = await preferences.getPreferences(this.ctx, this.prefName);
    const data = JSON.stringify(settings);
    await prefs.put(this.key, data);
    await prefs.flush();
    this.applyNativeTheme(settings);
  }
}
