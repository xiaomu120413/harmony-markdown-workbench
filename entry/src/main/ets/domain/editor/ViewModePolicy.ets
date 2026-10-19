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

  // ---- B4：空间预算（侧栏 + 大纲 + 分屏的最小宽度决策） ----

  static readonly SIDEBAR_W: number = 240;
  static readonly OUTLINE_W: number = 200;
  static readonly EDIT_MIN_W: number = 320;
  static readonly PREVIEW_MIN_W: number = 320;

  /**
   * 分屏在扣除侧栏/大纲后是否仍有最小宽度（B4-01）。
   * @param totalW 内容区总宽（vp）
   * @param sidebarOpen 文档侧栏是否可见
   * @param outlineOpen 大纲是否可见
   */
  static splitFits(totalW: number, sidebarOpen: boolean, outlineOpen: boolean): boolean {
    let available = totalW;
    if (sidebarOpen) {
      available -= ViewModePolicy.SIDEBAR_W + 1;
    }
    if (outlineOpen) {
      available -= ViewModePolicy.OUTLINE_W + 1;
    }
    return available >= ViewModePolicy.EDIT_MIN_W + ViewModePolicy.PREVIEW_MIN_W + 1;
  }

  /**
   * 大纲在扣除侧栏后是否仍有最小编辑宽度（B4-01）。
   */
  static outlineFits(totalW: number, sidebarOpen: boolean): boolean {
    let available = totalW;
    if (sidebarOpen) {
      available -= ViewModePolicy.SIDEBAR_W + 1;
    }
    return available - ViewModePolicy.OUTLINE_W - 1 >= ViewModePolicy.EDIT_MIN_W;
  }
}
