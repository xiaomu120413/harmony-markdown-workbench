import { MuLogger } from '../../common/MuLogger';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AppSettings, SettingsValidator, ThemeMode, DefaultView } from '../../domain/settings/AppSettings';
import { SettingsStore } from '../../infrastructure/metadata/SettingsStore';
import { DraftStore } from '../../infrastructure/metadata/DraftStore';
import { AppTheme } from '../../common/AppTheme';
import { SettingsState } from './SettingsState';
export class SettingsViewModel {
  private active: boolean = true;
  private writeChain: Promise<void> = Promise.resolve();
  private ctx: common.UIAbilityContext;
  private store: SettingsStore;
  state: SettingsState;
  constructor(state: SettingsState, ctx: common.UIAbilityContext) { this.state = state; this.ctx = ctx; this.store = new SettingsStore(ctx); }
  dispose(): void { this.active = false; }
  setTheme(value: ThemeMode): void { this.state.themeMode = value; this.state.pal = AppTheme.of(value === ThemeMode.DARK); this.persist(); }
  adjustFont(delta: number): void { this.state.fontSize = SettingsValidator.clampFont(this.state.fontSize + delta); this.persist(); }
  setWrap(value: boolean): void { this.state.wrap = value; this.persist(); }
  setLineNumbers(value: boolean): void { this.state.lineNumbers = value; this.persist(); }
  setAutoSave(value: boolean): void { this.state.autoSave = value; this.persist(); }
  setDefaultView(value: DefaultView): void { this.state.defaultView = value; this.persist(); }

  async load(): Promise<void> {
    const s = await this.store.load();
    if (!this.active) { return; }
    this.state.themeMode = s.theme;
    this.state.fontSize = s.fontSize;
    this.state.wrap = s.wrap;
    this.state.lineNumbers = s.lineNumbers;
    this.state.autoSave = s.autoSave;
    this.state.defaultView = s.defaultView;
    this.state.pal = AppTheme.of(s.theme === ThemeMode.DARK);
    try {
      const drafts = new DraftStore(this.ctx);
      this.state.draftCount = drafts.listAll().length;
    } catch (e) {
      this.state.draftCount = 0;
    }
  }

  /** Serialize snapshots so rapid changes cannot persist in reverse order. */
  persist(): Promise<void> {
    const s: AppSettings = {
      theme: this.state.themeMode,
      fontSize: SettingsValidator.clampFont(this.state.fontSize),
      wrap: this.state.wrap,
      lineNumbers: this.state.lineNumbers,
      autoSave: this.state.autoSave,
      defaultView: this.state.defaultView,
    };
    this.writeChain = this.writeChain.then(() => this.store.save(s)).catch((error: Object) => {
      MuLogger.error(`settings save failed: ${String(error)}`);
      if (this.active) { promptAction.showToast({ message: '设置保存失败，请重试' }); }
    });
    MuLogger.info(`[设置] theme=${s.theme} font=${s.fontSize} wrap=${s.wrap} lines=${s.lineNumbers} auto=${s.autoSave} view=${s.defaultView}`);
    return this.writeChain;
  }

}
