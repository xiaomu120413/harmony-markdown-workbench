/**
 * 应用统一视觉基调（产品化，V0.2.2）。
 * 色板来源：HarmonyOS 官方设计规范；明/暗双实例，随设置（M5-03 主题）切换。
 * 页面持有 `@State pal: AppTheme` 并在读取设置后赋值；
 * 属性绑定统一走 `this.pal.XXX`（深色切换时随状态驱动刷新）。
 */
export class AppTheme {
  /** 页面背景 */
  readonly BG: string;
  /** 卡片背景 */
  readonly CARD: string;
  /** 主色（HarmonyOS 官方蓝 #007DFF） */
  readonly PRIMARY: string;
  /** 主色浅底（选中/标签） */
  readonly PRIMARY_SOFT: string;
  /** 主按钮文字 */
  readonly ON_PRIMARY: string;
  /** 正文（墨色 #182431） */
  readonly TEXT: string;
  /** 次要文字 */
  readonly TEXT_SUB: string;
  /** 弱文字 */
  readonly TEXT_FAINT: string;
  /** 分隔线 */
  readonly DIVIDER: string;
  /** 工具条底色 */
  readonly TOOLBAR_BG: string;
  /** 成功（已保存） */
  readonly OK: string;
  /** 琥珀（进行中/未保存） */
  readonly AMBER: string;
  /** 危险（冲突/失败） */
  readonly DANGER: string;
  /** 标签浅底 */
  readonly OK_SOFT: string;
  readonly AMBER_SOFT: string;
  readonly DANGER_SOFT: string;

  private constructor(
    bg: string, card: string, primary: string, primarySoft: string, onPrimary: string,
    text: string, textSub: string, textFaint: string, divider: string, toolbarBg: string,
    ok: string, amber: string, danger: string, okSoft: string, amberSoft: string, dangerSoft: string,
  ) {
    this.BG = bg;
    this.CARD = card;
    this.PRIMARY = primary;
    this.PRIMARY_SOFT = primarySoft;
    this.ON_PRIMARY = onPrimary;
    this.TEXT = text;
    this.TEXT_SUB = textSub;
    this.TEXT_FAINT = textFaint;
    this.DIVIDER = divider;
    this.TOOLBAR_BG = toolbarBg;
    this.OK = ok;
    this.AMBER = amber;
    this.DANGER = danger;
    this.OK_SOFT = okSoft;
    this.AMBER_SOFT = amberSoft;
    this.DANGER_SOFT = dangerSoft;
  }

  static light(): AppTheme {
    return new AppTheme(
      '#F4F4F5', '#FFFFFF', '#007DFF', '#E6F0FF', '#FFFFFF',
      '#182431', '#8A8F99', '#B7BCC4', '#EDEDED', '#F4F5F7',
      '#2E9E5B', '#C77A18', '#D93A3A', '#E7F6ED', '#FCF1E3', '#FDEBEB',
    );
  }

  static dark(): AppTheme {
    return new AppTheme(
      '#131316', '#1E1E22', '#0A84FF', '#1B2A3D', '#FFFFFF',
      '#E8E9EB', '#9CA1AA', '#6B7078', '#323236', '#2A2A2F',
      '#4BC98A', '#E0A64E', '#F06A6A', '#1C3227', '#39301E', '#3D2424',
    );
  }

  static of(dark: boolean): AppTheme {
    return dark ? AppTheme.dark() : AppTheme.light();
  }
}
