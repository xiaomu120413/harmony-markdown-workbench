import { describe, expect, it } from '@ohos/hypium';
import { SaveCoordinator, SaveCoordinatorDeps, SnapshotData, SaveOutcome } from '../main/ets/services/SaveCoordinator';
import { SaveState } from '../main/ets/domain/recovery/SaveStateMachine';
import { WriteDocumentResult } from '../main/ets/domain/document/DocumentFileAdapter';

/** 虚拟依赖（内存实现；快照走 A1 信封契约，可注入延迟与失败） */
class MemDeps implements SaveCoordinatorDeps {
  content: string = '';
  version: number = 0;
  snapshotOk: boolean = true;
  snapshotDelayMs: number = 0;
  persisted: number = 0;
  checkpoints: number = 0;
  failNext: boolean = false;
  conflictNext: boolean = false;
  persistInFlight: boolean = false;
  overlapDetected: boolean = false;

  async getSnapshot(): Promise<SnapshotData> {
    if (this.snapshotDelayMs > 0) {
      await new Promise<void>((resolve) => setTimeout(resolve, this.snapshotDelayMs));
    }
    const d: SnapshotData = {
      ok: this.snapshotOk,
      sessionId: 's1',
      version: this.version,
      content: this.content,
    };
    return d;
  }

  async saveCheckpoint(content: string): Promise<void> {
    void content;
    this.checkpoints++;
  }

  async persist(content: string): Promise<WriteDocumentResult> {
    if (this.persistInFlight) {
      this.overlapDetected = true;
    }
    this.persistInFlight = true;
    try {
      if (this.conflictNext) {
        this.conflictNext = false;
        return { ok: false, reason: 'conflict', message: 'simulated revision mismatch' };
      }
      if (this.failNext) {
        this.failNext = false;
        return { ok: false, reason: 'io', message: 'simulated io failure' };
      }
      this.content = content;
      this.persisted++;
      return { ok: true, revision: { size: content.length, contentHash: 'h' + content.length } };
    } finally {
      this.persistInFlight = false;
    }
  }
}

/**
 * M4-01 编排单测（A1 重构后：版本门控 + 串行保存 + 快照契约）。
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
      expect(ran).assertFalse();
      expect(deps.persisted).assertEqual(0);
    });

    it('conflict_decisions', 0, async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      c.onExternalChange();
      c.decideKeepDisk();
      expect(c.state).assertEqual(SaveState.CLEAN);
      c.onEdit(500);
      c.onExternalChange();
      c.decideKeepLocal();
      expect(c.state).assertEqual(SaveState.DIRTY);
    });

    it('save_now_returns_outcome_saved', 0, async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      c.onEdit(100);
      deps.content = 'x';
      const outcome = await c.saveNow(200);
      expect(outcome).assertEqual('saved');
      expect(deps.persisted).assertEqual(1);
      expect(c.state).assertEqual(SaveState.CLEAN);
    });

    it('save_now_on_clean_returns_unchanged', 0, async () => {
      const deps = new MemDeps();
      const c = new SaveCoordinator(deps);
      const outcome = await c.saveNow(100);
      expect(outcome).assertEqual('unchanged');
      expect(deps.persisted).assertEqual(0);
    });

    it('persist_conflict_enters_conflict_keeps_content', 0, async () => {
      const deps = new MemDeps();
      deps.content = 'mine';
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      deps.conflictNext = true;
      const outcome = await c.tick(1600);
      expect(outcome).assertTrue();
      expect(c.state).assertEqual(SaveState.CONFLICT);
      expect(deps.content).assertEqual('mine');
      const ran = await c.tick(3000);
      expect(ran).assertFalse();
      expect(deps.persisted).assertEqual(0);
    });

    // ---- A1 新增：快照契约 / 保存期间编辑 / 串行 ----

    it('A1_snapshot_failure_no_write_no_checkpoint', 0, async () => {
      // R02/A1-05：Web 失败（ok=false）≠ 空正文——不落盘不写检查点，原文件字节不变
      const deps = new MemDeps();
      deps.content = '磁盘原内容';
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      deps.snapshotOk = false;
      const outcome = await c.saveNow(100);
      expect(outcome).assertEqual('failed');
      expect(deps.persisted).assertEqual(0);
      expect(deps.checkpoints).assertEqual(0);
      expect(deps.content).assertEqual('磁盘原内容');
      expect(c.state).assertEqual(SaveState.ERROR);
    });

    it('A1_empty_snapshot_ok_saves_empty', 0, async () => {
      // 合法空正文允许保存为空
      const deps = new MemDeps();
      deps.content = '';
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      const outcome = await c.saveNow(100);
      expect(outcome).assertEqual('saved');
      expect(deps.persisted).assertEqual(1);
    });

    it('A1_edit_during_save_stays_dirty', 0, async () => {
      // R01/A1-03：保存进行中继续输入，完成后不得清除待保存状态
      const deps = new MemDeps();
      deps.content = 'v1';
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      deps.snapshotDelayMs = 30;
      const p = c.saveNow(100);
      // 保存挂起期间：用户输入（版本 2）
      await new Promise<void>((resolve) => setTimeout(resolve, 10));
      c.onEdit(120, 2);
      const outcome = await p;
      expect(outcome).assertEqual('saved');
      expect(c.state).assertEqual(SaveState.DIRTY); // 不显示已保存
      expect(c.pending).assertTrue(); // 待保存未被吞
      // 收敛：下一次保存落最新内容（编辑器版本此时为 2）
      deps.content = 'v2';
      deps.version = 2;
      deps.snapshotDelayMs = 0;
      const out2 = await c.saveNow(200);
      expect(out2).assertEqual('saved');
      expect(c.state).assertEqual(SaveState.CLEAN);
      expect(deps.content).assertEqual('v2');
    });

    it('A1_stale_version_event_triggers_catchup', 0, async () => {
      // 快照读了 v5 内容，随后到达 v7 编辑事件 → 保存完成后仍 DIRTY
      const deps = new MemDeps();
      deps.content = 'c5';
      deps.version = 5;
      const c = new SaveCoordinator(deps);
      c.onEdit(0, 5);
      // 快照与事件版本一致，保存本应 CLEAN；迟到 v7 事件改变结论
      const p = c.saveNow(100);
      await new Promise<void>((resolve) => setTimeout(resolve, 5));
      c.onEdit(110, 7); // 迟到的版本事件
      const outcome = await p;
      expect(outcome).assertEqual('saved');
      expect(c.state).assertEqual(SaveState.DIRTY);
    });

    it('A1_concurrent_save_now_serialized', 0, async () => {
      // A1-04：并发手动保存串行执行，无重叠写入
      const deps = new MemDeps();
      deps.content = 'x';
      deps.snapshotDelayMs = 20;
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      const p1 = c.saveNow(100);
      const p2 = c.saveNow(101);
      const o1 = await p1;
      const o2 = await p2;
      expect(o1).assertEqual('saved');
      expect(deps.overlapDetected).assertFalse();
      expect(o2 === 'unchanged' || o2 === 'saved').assertTrue();
    });

    it('A1_tick_skips_while_save_in_flight', 0, async () => {
      const deps = new MemDeps();
      deps.content = 'x';
      deps.snapshotDelayMs = 40;
      const c = new SaveCoordinator(deps);
      c.onEdit(0);
      const p = c.tick(1600); // 第一次 tick 发起保存（快照挂起中）
      const ran = await c.tick(2000); // 到期但保存进行中 → 跳过
      expect(ran).assertFalse();
      expect(deps.overlapDetected).assertFalse();
      await p;
    });
  });
}
