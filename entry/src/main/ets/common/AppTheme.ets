/**
 * 应用统一视觉基调（V0.4：对齐系统原生「色调分层」设计）。
 * 参考提取自系统备忘录（真机像素采样）：
 *   侧栏 #EEEFF1 → 列表区 #F2F3F5 → 内容区 #FFFFFF，面板间无边框无圆角，
 *   列表项以细分隔线区隔——平台风格是色调分层而非描边卡片。
 * 明/暗双实例，随设置（M5-03 主题）切换；页面持有 @State pal。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeMode } from '../domain/settings/AppSettings';

export class AppTheme {
  /** 页面背景（最底层/列表区） */
  readonly BG: string;
  /** 侧栏底色（导航区） */
  readonly SIDEBAR: string;
  /** 内容区底色（编辑器/主内容/设置分组） */
  readonly CONTENT: string;
  /** 控件浅底（工具条/输入框/非激活分段） */
  readonly CARD: string;
  /** 主操作色；普通控件不铺主色底。 */
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
    bg: string, sidebar: string, content: string, card: string,
    primary: string, primarySoft: string, onPrimary: string,
    text: string, textSub: string, textFaint: string, divider: string,
    ok: string, amber: string, danger: string, okSoft: string, amberSoft: string, dangerSoft: string,
  ) {
    this.BG = bg;
    this.SIDEBAR = sidebar;
    this.CONTENT = content;
    this.CARD = card;
    this.PRIMARY = primary;
    this.PRIMARY_SOFT = primarySoft;
    this.ON_PRIMARY = onPrimary;
    this.TEXT = text;
    this.TEXT_SUB = textSub;
    this.TEXT_FAINT = textFaint;
    this.DIVIDER = divider;
    this.OK = ok;
    this.AMBER = amber;
    this.DANGER = danger;
    this.OK_SOFT = okSoft;
    this.AMBER_SOFT = amberSoft;
    this.DANGER_SOFT = dangerSoft;
  }

  static light(): AppTheme {
    return new AppTheme(
      '#F2F3F5', '#EEEFF1', '#FFFFFF', '#F4F5F7',
      '#0069D9', '#E8EEF6', '#FFFFFF',
      '#20252B', '#626A73', '#626A73', '#E5E6E8',
      '#2E9E5B', '#C77A18', '#D93A3A', '#E7F6ED', '#FCF1E3', '#FDEBEB',
    );
  }

  static dark(): AppTheme {
    return new AppTheme(
      '#131316', '#17171B', '#1E1E22', '#2A2A2F',
      '#0069D9', '#27313D', '#FFFFFF',
      '#E8E9EB', '#A4ABB4', '#A4ABB4', '#323236',
      '#4BC98A', '#E0A64E', '#F06A6A', '#1C3227', '#39301E', '#3D2424',
    );
  }

  static of(dark: boolean): AppTheme {
    return dark ? AppTheme.dark() : AppTheme.light();
  }

  static isDark(mode: ThemeMode, colorMode?: number): boolean {
    return mode === ThemeMode.DARK || (mode === ThemeMode.SYSTEM &&
      colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }
}
