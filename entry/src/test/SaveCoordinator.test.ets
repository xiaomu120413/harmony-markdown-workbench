import { describe, expect, it } from '@ohos/hypium';
import { SaveCoordinator, SaveCoordinatorDeps } from '../main/ets/services/SaveCoordinator';
import { SaveState } from '../main/ets/domain/recovery/SaveStateMachine';
import { WriteDocumentResult } from '../main/ets/domain/document/DocumentFileAdapter';

/** 虚拟依赖（内存实现，便于单测） */
class MemDeps implements SaveCoordinatorDeps {
  content: string = '';
  persisted: number = 0;
  checkpoints: number = 0;
  failNext: boolean = false;

  async getSnapshot(): Promise<string> {
    return this.content;
  }

  async saveCheckpoint(content: string): Promise<void> {
    void content;
    this.checkpoints++;
  }

  async persist(content: string): Promise<WriteDocumentResult> {
    this.content = content;
    if (this.failNext) {
      this.failNext = false;
      return { ok: false, reason: 'io', message: 'simulated io failure' };
    }
    this.persisted++;
    return { ok: true, revision: { size: content.length, contentHash: 'h' + content.length } };
  }
}

/**
 * M4-01 前置：SaveCoordinator 编排单测。
 */
export default function saveCoordinatorTest(): void {
  describe('SaveCoordinator', () => {
    it('edit_to_dirty_pending', 0, () => {
      const c = new SaveCoordinator(new MemDeps());
      c.onEdit(0);
      expect(c.state).assertEqual(SaveState.DIRTY);
      expect(c.pending).assertTrue();
    });

    it('tick_before_due_does_nothing', async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      const ran = await c.tick(500); // 防抖 1500ms 未到
      expect(ran).assertFalse();
      expect(deps.persisted).assertEqual(0);
    });

    it('tick_after_due_saves_and_clean', async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      deps.content = 'hello';
      const ran = await c.tick(1600);
      expect(ran).assertTrue();
      expect(deps.persisted).assertEqual(1);
      expect(deps.checkpoints).assertEqual(1);
      expect(c.state).assertEqual(SaveState.CLEAN);
    });

    it('save_failure_goes_error_retryable', async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      deps.failNext = true;
      await c.tick(1600);
      expect(c.state).assertEqual(SaveState.ERROR);
      // 重试成功后回到 CLEAN
      const again = await c.tick(2000);
      expect(again).assertTrue();
      expect(c.state).assertEqual(SaveState.CLEAN);
    });

    it('external_change_conflict_and_autosave_stops', async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      c.onExternalChange();
      expect(c.state).assertEqual(SaveState.CONFLICT);
      const ran = await c.tick(1600);
      expect(ran).assertFalse(); // 冲突时不执行自动保存
      expect(deps.persisted).assertEqual(0);
    });

    it('conflict_decisions', async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      c.onExternalChange();
      c.decideKeepDisk();
      expect(c.state).assertEqual(SaveState.CLEAN);
      // 再次编辑 → 冲突 → 保留本地 → DIRTY
      c.onEdit(500);
      c.onExternalChange();
      c.decideKeepLocal();
      expect(c.state).assertEqual(SaveState.DIRTY);
    });

    it('save_now_forces_save', async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(100);
      deps.content = 'x';
      await c.saveNow(200);
      expect(deps.persisted).assertEqual(1);
      expect(c.state).assertEqual(SaveState.CLEAN);
    });
  });
}