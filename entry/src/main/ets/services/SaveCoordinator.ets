import { SaveStateMachine, SaveState } from '../domain/recovery/SaveStateMachine';
import { SaveScheduler } from '../domain/recovery/SaveScheduler';
import { WriteDocumentResult, WriteFailResult } from '../domain/document/DocumentFileAdapter';

/**
 * SaveCoordinator（M4-01，FR-SAVE-001/002/003 编排）。
 * 组合领域层 SaveStateMachine + SaveScheduler，接入文件适配器与草稿存储。
 * 职责：
 *  - 编辑事件 → 状态机 DIRTY + 调度器防抖输入；
 *  - 到期（tick）→ 快照 → 持久化 → 成功/失败状态迁移；
 *  - 外部变更 → CONFLICT（自动保存停止）；
 *  - ERROR 后重试；草稿检查点由 deps 落盘。
 * 纯逻辑（di 注入），可本地单测。
 */
export interface SaveCoordinatorDeps {
  getSnapshot(): Promise<string>;
  persist(content: string): Promise<WriteDocumentResult>;
  saveCheckpoint(content: string): Promise<void>;
}

export class SaveCoordinator {
  private readonly sm: SaveStateMachine;
  private readonly sched: SaveScheduler;
  private readonly deps: SaveCoordinatorDeps;

  constructor(deps: SaveCoordinatorDeps) {
    this.sm = new SaveStateMachine();
    this.sched = new SaveScheduler();
    this.deps = deps;
  }

  get state(): SaveState {
    return this.sm.state;
  }

  get pending(): boolean {
    return this.sched.pending;
  }

  /** 编辑事件 */
  onEdit(now: number): void {
    if (this.sm.state === SaveState.CLEAN) {
      this.sm.edit();
    }
    this.sched.onInput(now);
  }

  /** 外部变更（FR-FILE-004）：进入 CONFLICT，自动保存停止 */
  onExternalChange(): void {
    this.sm.externalChange();
  }

  /** 用户决策 */
  decideKeepDisk(): void {
    this.sm.decideKeepDisk();
  }

  decideKeepLocal(): void {
    this.sm.decideKeepLocal();
  }

  /**
   * 定时检查：到点执行一次保存。返回是否执行了保存流程。
   */
  async tick(now: number): Promise<boolean> {
    const due = this.sched.dueTime();
    if (due === undefined || now < due) {
      return false;
    }
    return this.runSave(now);
  }

  /** 立即保存（手动 Ctrl+S / 分享前） */
  async saveNow(now: number): Promise<boolean> {
    return this.runSave(now);
  }

  private async runSave(now: number): Promise<boolean> {
    // 状态判定：DIRTY 进入 SAVING 后写；ERROR 直接重试（retry 已转移为 SAVING）；
    // 其余（CLEAN/CONFLICT/SAVING）不写
    if (this.sm.state === SaveState.ERROR) {
      this.sm.retry();
    } else {
      if (this.sm.state !== SaveState.DIRTY) {
        this.sched.onSaveStarted(now);
        return false;
      }
      this.sm.beginSave();
    }
    try {
      const content = await this.deps.getSnapshot();
      // 草稿检查点先落盘（FR-SAVE-003：写失败保留草稿）
      await this.deps.saveCheckpoint(content);
      const result = await this.deps.persist(content);
      if (result.ok) {
        this.sm.saveSuccess();
        this.sched.onSaveStarted(now);
        return true;
      }
      if ((result as WriteFailResult).reason === 'conflict') {
        // 外部已修改磁盘（FR-FILE-004）：进入 CONFLICT，自动保存停止（M4-03 用户决策）
        this.sm.externalChange();
        this.sched.onSaveStarted(now);
        return true;
      }
      // 保存失败：保留待保存（pending），后续 tick 自动重试（ERROR 可 retry）
      this.sm.saveFailure();
      return true;
    } catch (e) {
      this.sm.saveFailure();
      return true;
    }
  }
}