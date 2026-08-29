import { describe, expect, it } from '@ohos/hypium';
import { SaveState, SaveStateMachine, InvalidTransitionError } from '../main/ets/domain/recovery/SaveStateMachine';

/**
 * TASK-M4-01 验收前置（M0-04 领域层）：保存状态机全路径单测。
 * 覆盖 FR-SAVE-001 的合法迁移与非法迁移。
 */
export default function saveStateMachineTest(): void {
  describe('SaveStateMachine', () => {
    it('edit_from_clean_to_dirty', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      expect(m.state).assertEqual(SaveState.DIRTY);
    });

    it('normal_save_cycle', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.beginSave();
      expect(m.state).assertEqual(SaveState.SAVING);
      m.saveSuccess();
      expect(m.state).assertEqual(SaveState.CLEAN);
    });

    it('save_failure_goes_error_and_retry', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.beginSave();
      m.saveFailure();
      expect(m.state).assertEqual(SaveState.ERROR);
      m.retry();
      expect(m.state).assertEqual(SaveState.SAVING);
      m.saveSuccess();
      expect(m.state).assertEqual(SaveState.CLEAN);
    });

    it('external_change_from_dirty', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.externalChange();
      expect(m.state).assertEqual(SaveState.CONFLICT);
    });

    it('external_change_during_saving', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.beginSave();
      m.externalChange();
      expect(m.state).assertEqual(SaveState.CONFLICT);
    });

    it('external_change_from_error', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.beginSave();
      m.saveFailure();
      m.externalChange();
      expect(m.state).assertEqual(SaveState.CONFLICT);
    });

    it('conflict_decide_keep_disk', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.externalChange();
      m.decideKeepDisk();
      expect(m.state).assertEqual(SaveState.CLEAN);
    });

    it('conflict_decide_keep_local', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.externalChange();
      m.decideKeepLocal();
      expect(m.state).assertEqual(SaveState.DIRTY);
    });

    it('invalid_begin_save_from_clean_throws', 0, () => {
      const m = new SaveStateMachine();
      let caught: boolean = false;
      try {
        m.beginSave();
      } catch (e) {
        caught = e instanceof InvalidTransitionError;
      }
      expect(caught).assertTrue();
    });

    it('invalid_edit_from_saving_throws', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      m.beginSave();
      let caught: boolean = false;
      try {
        m.edit();
      } catch (e) {
        caught = e instanceof InvalidTransitionError;
      }
      expect(caught).assertTrue();
    });

    it('invalid_save_success_from_clean_throws', 0, () => {
      const m = new SaveStateMachine();
      let caught: boolean = false;
      try {
        m.saveSuccess();
      } catch (e) {
        caught = e instanceof InvalidTransitionError;
      }
      expect(caught).assertTrue();
    });

    it('invalid_user_decision_from_dirty_throws', 0, () => {
      const m = new SaveStateMachine();
      m.edit();
      let caught: boolean = false;
      try {
        m.decideKeepDisk();
      } catch (e) {
        caught = e instanceof InvalidTransitionError;
      }
      expect(caught).assertTrue();
    });

    it('labels_readable_for_ui', 0, () => {
      expect(SaveStateMachine.label(SaveState.CLEAN)).assertEqual('已保存');
      expect(SaveStateMachine.label(SaveState.DIRTY)).assertEqual('未保存');
      expect(SaveStateMachine.label(SaveState.SAVING)).assertEqual('保存中');
      expect(SaveStateMachine.label(SaveState.ERROR)).assertEqual('保存失败');
      expect(SaveStateMachine.label(SaveState.CONFLICT)).assertEqual('外部冲突');
    });
  });
}