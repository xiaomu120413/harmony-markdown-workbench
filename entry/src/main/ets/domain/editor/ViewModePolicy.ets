import { DefaultView } from '../settings/AppSettings';

/**
 * 视图模式 × 断点适配策略（纯逻辑，可本地单测）。
 * 三端布局规则（SDD 4.2 / M6-01）：
 *   phone（<600vp）：单栏，编辑 ⇄ 预览 切换，不提供分屏；
 *   tablet（600–959vp）与 pc（≥960vp）：编辑 / 预览 / 分屏三态。
 * LayoutTier 与 common/Breakpoints 的 Breakpoint 结构同型（string 字面量联合），
 * 此处独立声明以保持领域层不依赖 ArkUI。
 */
export type LayoutTier = 'phone' | 'tablet' | 'pc';

export class ViewModePolicy {
  /** 分屏仅双栏及以上断点提供 */
  static allowsSplit(tier: LayoutTier): boolean {
    return tier !== 'phone';
  }

  /** 入口视图：设置默认视图 × 断点（phone 上 split 降级为 edit） */
  static resolveInitial(tier: LayoutTier, defaultView: DefaultView): DefaultView {
    if (defaultView === DefaultView.SPLIT && !ViewModePolicy.allowsSplit(tier)) {
      return DefaultView.EDIT;
    }
    return defaultView;
  }

  /** 断点变化时归一化：phone 上 split 降级为 edit，其余保持 */
  static normalize(mode: DefaultView, tier: LayoutTier): DefaultView {
    if (mode === DefaultView.SPLIT && !ViewModePolicy.allowsSplit(tier)) {
      return DefaultView.EDIT;
    }
    return mode;
  }
}
