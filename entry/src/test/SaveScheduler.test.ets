import { describe, expect, it } from '@ohos/hypium';
import { SaveScheduler } from '../main/ets/domain/recovery/SaveScheduler';

/**
 * M0-04 领域层：自动保存调度（FR-SAVE-002）单测。
 * - 防抖 1.5s；连续输入 10s 检查点；请求合并；串行周期。
 */
export default function saveSchedulerTest(): void {
  describe('SaveScheduler', () => {
    it('no_input_no_due', 0, () => {
      const s = new SaveScheduler();
      expect(s.dueTime()).assertUndefined();
    });

    it('debounce_after_input', 0, () => {
      const s = new SaveScheduler();
      s.onInput(0);
      expect(s.dueTime()).assertEqual(1500);
    });

    it('debounce_extends_with_later_input', 0, () => {
      const s = new SaveScheduler();
      s.onInput(0);
      s.onInput(1000);
      expect(s.dueTime()).assertEqual(2500);
    });

    it('continuous_input_forced_checkpoint_at_max', 0, () => {
      const s = new SaveScheduler();
      // 每 500ms 输入一次，持续到 9500ms：due 被 maxDelay（10000）钳制
      for (let t = 0; t <= 9500; t += 500) {
        s.onInput(t);
      }
      expect(s.dueTime()).assertEqual(10000);
    });

    it('save_started_clears_pending_and_new_cycle', 0, () => {
      const s = new SaveScheduler();
      s.onInput(0);
      expect(s.pending).assertTrue();
      s.onSaveStarted(1500);
      expect(s.pending).assertFalse();
      expect(s.dueTime()).assertUndefined();
      // 新周期：输入 1600 → 防抖到 3100
      s.onInput(1600);
      expect(s.dueTime()).assertEqual(3100);
    });

    it('merged_requests_single_schedule', 0, () => {
      const s = new SaveScheduler();
      s.onInput(100);
      s.onInput(200);
      s.onInput(300);
      // 多次输入只产生一次调度（pending 保持，不重复排队）
      expect(s.pending).assertTrue();
      expect(s.dueTime()).assertEqual(1800);
    });

    it('after_finish_with_new_input_reschedules', 0, () => {
      const s = new SaveScheduler();
      s.onInput(0);
      s.onSaveStarted(1500);
      s.onSaveFinished();
      s.onInput(2000);
      expect(s.dueTime()).assertEqual(3500);
    });
  });
}