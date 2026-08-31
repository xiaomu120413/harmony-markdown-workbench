/**
 * 应用设置模型（M5-03，FR-SETTINGS）。
 * 纯逻辑：校验与非法值回退（验收：非法值回退默认值）。
 * 持久化：preferences（SettingsStore 基础设施层）。
 */
export enum ThemeMode {
  LIGHT = 'light',
  DARK = 'dark',
}

export enum DefaultView {
  EDIT = 'edit',
  PREVIEW = 'preview',
  SPLIT = 'split',
}

export interface AppSettings {
  theme: ThemeMode;
  fontSize: number;
  wrap: boolean;
  lineNumbers: boolean;
  autoSave: boolean;
  defaultView: DefaultView;
}

export class SettingsValidator {
  static readonly FONT_MIN: number = 12;
  static readonly FONT_MAX: number = 24;

  static defaults(): AppSettings {
    const d: AppSettings = {
      theme: ThemeMode.LIGHT,
      fontSize: 15,
      wrap: true,
      lineNumbers: true,
      autoSave: true,
      defaultView: DefaultView.EDIT,
    };
    return d;
  }

  /** 非法/越界值回退：逐一 clamp 后再按默认值兜底（损坏 JSON → 全默认） */
  static parse(raw: string): AppSettings {
    const d = SettingsValidator.defaults();
    if (raw.length === 0) {
      return d;
    }
    try {
      let o: ESObject = JSON.parse(raw);
      const themeRaw = o.theme as string | undefined;
      const fontRaw = o.fontSize as number | undefined;
      const wrapRaw = o.wrap as boolean | undefined;
      const linesRaw = o.lineNumbers as boolean | undefined;
      const autoRaw = o.autoSave as boolean | undefined;
      const viewRaw = o.defaultView as string | undefined;
      const out: AppSettings = {
        theme: themeRaw === 'dark' ? ThemeMode.DARK : ThemeMode.LIGHT,
        fontSize: SettingsValidator.clampFont(fontRaw),
        wrap: wrapRaw === undefined ? d.wrap : wrapRaw === true,
        lineNumbers: linesRaw === undefined ? d.lineNumbers : linesRaw === true,
        autoSave: autoRaw === undefined ? d.autoSave : autoRaw === true,
        defaultView: viewRaw === 'preview' ? DefaultView.PREVIEW : viewRaw === 'split' ? DefaultView.SPLIT : DefaultView.EDIT,
      };
      return out;
    } catch (e) {
      return d;
    }
  }

  /** 越界/NaN → 默认值 15 */
  static clampFont(font: number | undefined): number {
    if (font === undefined || font !== font || font < SettingsValidator.FONT_MIN || font > SettingsValidator.FONT_MAX) {
      return 15;
    }
    return Math.round(font);
  }
}