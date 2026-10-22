/** 木笺纸墨配色：纸色背景、墨色文字、低饱和强调，原生页面与 Web 内容共同使用。 */
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
      '#F6F5F2', '#EEEFEA', '#FCFCFA', '#EDEFEA',
      '#335E68', '#E0EBE9', '#FFFFFF',
      '#263532', '#596A63', '#5D6A63', '#DCDFD8',
      '#2E9E5B', '#C77A18', '#D93A3A', '#E7F6ED', '#FCF1E3', '#FDEBEB',
    );
  }

  static dark(): AppTheme {
    return new AppTheme(
      '#171D1D', '#1C2323', '#202827', '#293332',
      '#A9CCC4', '#2B403D', '#152829',
      '#E5ECE8', '#B0BDB5', '#A2B1AA', '#3A4742',
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
