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
  conflictNext: boolean = false;

  async getSnapshot(): Promise<string> {
    return this.content;
  }

  async saveCheckpoint(content: string): Promise<void> {
    void content;
    this.checkpoints++;
  }

  async persist(content: string): Promise<WriteDocumentResult> {
    if (this.conflictNext) {
      this.conflictNext = false;
      // 模拟 revision 冲突：不落盘（磁盘内容保持原值）
      return { ok: false, reason: 'conflict', message: 'simulated revision mismatch' };
    }
    if (this.failNext) {
      this.failNext = false;
      return { ok: false, reason: 'io', message: 'simulated io failure' };
    }
    this.content = content;
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

    it('tick_before_due_does_nothing', 0, async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      const ran = await c.tick(500); // 防抖 1500ms 未到
      expect(ran).assertFalse();
      expect(deps.persisted).assertEqual(0);
    });

    it('tick_after_due_saves_and_clean', 0, async () => {
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

    it('save_failure_goes_error_retryable', 0, async () => {
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

    it('external_change_conflict_and_autosave_stops', 0, async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      c.onExternalChange();
      expect(c.state).assertEqual(SaveState.CONFLICT);
      const ran = await c.tick(1600);
      expect(ran).assertFalse(); // 冲突时不执行自动保存
      expect(deps.persisted).assertEqual(0);
    });

    it('conflict_decisions', 0, async () => {
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

    it('save_now_forces_save', 0, async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(100);
      deps.content = 'x';
      await c.saveNow(200);
      expect(deps.persisted).assertEqual(1);
      expect(c.state).assertEqual(SaveState.CLEAN);
    });

    it('persist_conflict_enters_conflict_keeps_content', 0, async () => {
      const deps = new MemDeps();
      deps.content = 'mine';
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      deps.conflictNext = true;
      await c.tick(1600);
      expect(c.state).assertEqual(SaveState.CONFLICT);
      expect(deps.content).assertEqual('mine'); // 冲突时磁盘内容未被覆盖
      // 冲突状态下自动保存停止
      const ran = await c.tick(3000);
      expect(ran).assertFalse();
      expect(deps.persisted).assertEqual(0);
    });
  });
}