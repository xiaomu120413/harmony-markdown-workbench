/**
 * 应用统一视觉基调（产品化，V0.1）。
 * 色板来源：HarmonyOS 官方设计规范（dososo/HarmonyOS-Design 参考）。
 */
export class AppTheme {
  /** 页面背景 */
  static readonly BG: string = '#F4F4F5';
  /** 卡片背景 */
  static readonly CARD: string = '#FFFFFF';
  /** 主色（HarmonyOS 官方蓝 #007DFF） */
  static readonly PRIMARY: string = '#007DFF';
  /** 主色浅底（选中/标签） */
  static readonly PRIMARY_SOFT: string = '#E6F0FF';
  /** 主按钮文字 */
  static readonly ON_PRIMARY: string = '#FFFFFF';
  /** 正文（墨色 #182431） */
  static readonly TEXT: string = '#182431';
  /** 次要文字 */
  static readonly TEXT_SUB: string = '#8A8F99';
  /** 弱文字 */
  static readonly TEXT_FAINT: string = '#B7BCC4';
  /** 分隔线 */
  static readonly DIVIDER: string = '#EDEDED';
  /** 工具条底色 */
  static readonly TOOLBAR_BG: string = '#F4F5F7';
  /** 成功（已保存） */
  static readonly OK: string = '#2E9E5B';
  /** 琥珀（进行中/未保存） */
  static readonly AMBER: string = '#C77A18';
  /** 危险（冲突/失败） */
  static readonly DANGER: string = '#D93A3A';
  /** 标签浅底 */
  static readonly OK_SOFT: string = '#E7F6ED';
  static readonly AMBER_SOFT: string = '#FCF1E3';
  static readonly DANGER_SOFT: string = '#FDEBEB';

  /** 卡片阴影（首页列表/主操作） */
  static readonly SHADOW: ShadowOptions = { radius: 10, color: '#0D1F2329', offsetY: 2 };
}