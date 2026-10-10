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
      // 平板分屏 → 窗口缩窄到手机档：降级为编辑（保留用户内容上下文）
      expect(ViewModePolicy.normalize(DefaultView.SPLIT, 'phone')).assertEqual(DefaultView.EDIT);
    });
  });
}
