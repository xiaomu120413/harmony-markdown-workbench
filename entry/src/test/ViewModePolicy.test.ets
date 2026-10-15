import { describe, expect, it } from '@ohos/hypium';
import { ViewModePolicy, LayoutTier } from '../main/ets/domain/editor/ViewModePolicy';
import { DefaultView } from '../main/ets/domain/settings/AppSettings';

/**
 * 视图模式 × 断点适配（三端布局规则）。
 */
export default function viewModePolicyTest(): void {
  describe('ViewModePolicy', () => {
    it('split_only_above_phone', 0, () => {
      expect(ViewModePolicy.allowsSplit('phone')).assertFalse();
      expect(ViewModePolicy.allowsSplit('tablet')).assertTrue();
      expect(ViewModePolicy.allowsSplit('pc')).assertTrue();
    });

    it('initial_respects_default_on_wide_tier', 0, () => {
      expect(ViewModePolicy.resolveInitial('pc', DefaultView.SPLIT)).assertEqual(DefaultView.SPLIT);
      expect(ViewModePolicy.resolveInitial('tablet', DefaultView.PREVIEW)).assertEqual(DefaultView.PREVIEW);
      expect(ViewModePolicy.resolveInitial('tablet', DefaultView.EDIT)).assertEqual(DefaultView.EDIT);
    });

    it('initial_split_degrades_to_edit_on_phone', 0, () => {
      expect(ViewModePolicy.resolveInitial('phone', DefaultView.SPLIT)).assertEqual(DefaultView.EDIT);
    });

    it('normalize_keeps_mode_when_allowed', 0, () => {
      expect(ViewModePolicy.normalize(DefaultView.SPLIT, 'pc')).assertEqual(DefaultView.SPLIT);
      expect(ViewModePolicy.normalize(DefaultView.PREVIEW, 'phone')).assertEqual(DefaultView.PREVIEW);
    });

    it('normalize_degrades_split_on_phone', 0, () => {
      expect(ViewModePolicy.normalize(DefaultView.SPLIT, 'phone')).assertEqual(DefaultView.EDIT);
    });

    // ---- B4：空间预算 ----

    it('B4_split_fits_wide_with_all_panels', 0, () => {
      // 1200vp，侧栏+大纲全开：1200-240-200=760 ≥ 320+320=640 ✓
      expect(ViewModePolicy.splitFits(1200, true, true)).assertTrue();
    });

    it('B4_split_fits_tablet_no_panels', 0, () => {
      // 700vp 无面板：700 ≥ 640 ✓
      expect(ViewModePolicy.splitFits(700, false, false)).assertTrue();
    });

    it('B4_split_does_not_fit_tablet_with_sidebar', 0, () => {
      // 700vp 侧栏开：700-240=460 < 640 ✗
      expect(ViewModePolicy.splitFits(700, true, false)).assertFalse();
    });

    it('B4_split_does_not_fit_with_all_panels_narrow', 0, () => {
      // 1000vp 全开：1000-240-200=560 < 640 ✗
      expect(ViewModePolicy.splitFits(1000, true, true)).assertFalse();
    });

    it('B4_outline_fits_normal', 0, () => {
      expect(ViewModePolicy.outlineFits(800, false)).assertTrue();
    });

    it('B4_outline_does_not_fit_with_sidebar_narrow', 0, () => {
      // 500vp 侧栏开：500-240-200=60 < 320 ✗
      expect(ViewModePolicy.outlineFits(500, true)).assertFalse();
    });
  });
}
