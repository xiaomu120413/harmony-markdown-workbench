import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, SettingsValidator } from '../../domain/settings/AppSettings';

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
    try {
      const prefs = await preferences.getPreferences(this.ctx, this.prefName);
      const raw = (await prefs.get(this.key, '')) as string;
      return SettingsValidator.parse(raw);
    } catch (e) {
      return SettingsValidator.defaults();
    }
  }

  async save(settings: AppSettings): Promise<void> {
    const prefs = await preferences.getPreferences(this.ctx, this.prefName);
    const data = JSON.stringify(settings);
    await prefs.put(this.key, data);
    await prefs.flush();
  }
}