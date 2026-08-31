/**
 * 应用统一视觉基调（产品化，V0.1）。
 * 单一颜色来源：页面组件直接引用，避免散落字面量。
 */
export class AppTheme {
  /** 页面背景 */
  static readonly BG: string = '#FAFAFC';
  /** 卡片背景 */
  static readonly CARD: string = '#FFFFFF';
  /** 主色（操作/强调） */
  static readonly PRIMARY: string = '#2F6FED';
  /** 主色浅底（选中/标签） */
  static readonly PRIMARY_SOFT: string = '#EEF4FF';
  /** 主按钮文字 */
  static readonly ON_PRIMARY: string = '#FFFFFF';
  /** 正文 */
  static readonly TEXT: string = '#1F2329';
  /** 次要文字 */
  static readonly TEXT_SUB: string = '#8A8F99';
  /** 弱文字 */
  static readonly TEXT_FAINT: string = '#B7BCC4';
  /** 分隔线 */
  static readonly DIVIDER: string = '#EDEFF3';
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