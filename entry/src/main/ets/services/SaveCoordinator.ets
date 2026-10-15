import { SaveStateMachine, SaveState } from '../domain/recovery/SaveStateMachine';
import { SaveScheduler } from '../domain/recovery/SaveScheduler';
import { WriteDocumentResult, WriteFailResult } from '../domain/document/DocumentFileAdapter';

/**
 * 编辑器快照（A1 快照契约，R02）。
 * ok=false 表示 Web 调用失败/超时/协议错误——此时空正文与读取失败可区分，
 * 保存流程不得把空字符串当正文写盘。
 * sessionId/version 与 content 来自同一次编辑器状态读取（Web 侧一次性返回）。
 */
export interface SnapshotData {
  ok: boolean;
  sessionId: string;
  version: number;
  content: string;
}

/** 保存结果（A1：saveNow 明确成功/未执行/冲突/失败/忙碌） */
export type SaveOutcome = 'saved' | 'unchanged' | 'conflict' | 'failed' | 'busy';

/**
 * SaveCoordinator（M4-01 编排；A1 重构：版本门控 + 串行保存）。
 * 组合领域层 SaveStateMachine + SaveScheduler，接入文件适配器与草稿存储。
 * 职责：
 *  - 编辑事件（可携带编辑器版本）→ 状态机 DIRTY + 调度器防抖；
 *  - 到期/手动 → 快照 → 检查点 → 持久化；
 *  - 写入完成只确认快照版本：保存期间发生新编辑（版本更高）→ 恢复 DIRTY 继续调度，
 *    不无条件清除待保存状态（R01）；
 *  - 快照失败（ok=false）不落盘不写检查点，原文件字节不变（R02）；
 *  - 手动保存串行（同一文档不重叠写入），自动 tick 在保存进行中跳过（A1-04）；
 *  - 外部变更 → CONFLICT（自动保存停止）；ERROR 后重试。
 * 纯逻辑（di 注入），可本地单测。
 */
export interface SaveCoordinatorDeps {
  getSnapshot(): Promise<SnapshotData>;
  persist(content: string): Promise<WriteDocumentResult>;
  saveCheckpoint(content: string): Promise<void>;
}

export class SaveCoordinator {
  private readonly sm: SaveStateMachine;
  private readonly sched: SaveScheduler;
  private readonly deps: SaveCoordinatorDeps;
  private inFlight: boolean = false;
  private chain: Promise<void> = Promise.resolve();
  private latestVersion: number = 0;
  private lastEditAt: number = 0;
  private dirtyAfterSave: boolean = false;

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

  /**
   * 编辑事件。version 为编辑器单调递增版本（可选：旧协议缺省时退化为
   * dirtyAfterSave 布尔门控，不会丢内容，只会多一次收敛保存）。
   */
  onEdit(now: number, version?: number): void {
    this.lastEditAt = now;
    if (version !== undefined) {
      this.latestVersion = version;
    }
    if (this.sm.state === SaveState.CLEAN) {
      this.sm.edit();
    } else if (this.sm.state === SaveState.SAVING) {
      // R01：保存期间的编辑不得被完成回调吞掉
      this.dirtyAfterSave = true;
    }
    this.sched.onInput(now);
  }

  /** 文档加载完成：重置版本跟踪（编辑器侧版本已归零） */
  onDocumentLoaded(): void {
    this.latestVersion = 0;
    this.dirtyAfterSave = false;
    this.lastEditAt = 0;
  }

  /** 外部变更（FR-FILE-004）：进入 CONFLICT，自动保存停止 */
  onExternalChange(): void {
    this.sm.externalChange();
  }

  decideKeepDisk(): void {
    this.sm.decideKeepDisk();
  }

  decideKeepLocal(): void {
    this.sm.decideKeepLocal();
  }

  /** 定时检查：到点执行一次保存；保存进行中跳过（下一轮 tick 兜底）。返回是否执行。 */
  async tick(now: number): Promise<boolean> {
    if (this.inFlight) {
      return false;
    }
    const due = this.sched.dueTime();
    if (due === undefined || now < due) {
      return false;
    }
    const outcome = await this.runSave(now);
    return outcome !== 'unchanged' && outcome !== 'busy';
  }

  /** 立即保存（手动/分享前）：经串行队列，同一文档不重叠写入 */
  saveNow(now: number): Promise<SaveOutcome> {
    const p = this.chain.then((): Promise<SaveOutcome> => this.runSave(now));
    this.chain = p.then(() => {
    }, () => {
    });
    return p;
  }

  private async runSave(now: number): Promise<SaveOutcome> {
    if (this.inFlight) {
      return 'busy';
    }
    this.inFlight = true;
    try {
      return await this.performSave(now);
    } finally {
      this.inFlight = false;
    }
  }

  private async performSave(now: number): Promise<SaveOutcome> {
    if (this.sm.state === SaveState.ERROR) {
      this.sm.retry();
    } else {
      if (this.sm.state !== SaveState.DIRTY) {
        // CLEAN/SAVING/CONFLICT：清掉过期调度请求，不写
        this.sched.onSaveStarted(now);
        return 'unchanged';
      }
      this.sm.beginSave();
    }
    let snap: SnapshotData;
    try {
      snap = await this.deps.getSnapshot();
    } catch (e) {
      this.sm.saveFailure();
      return 'failed';
    }
    if (!snap.ok) {
      // R02：Web 失败 ≠ 空正文。不写检查点不写文件，原文件字节不变。
      this.sm.saveFailure();
      return 'failed';
    }
    try {
      await this.deps.saveCheckpoint(snap.content);
      const result = await this.deps.persist(snap.content);
      if (result.ok) {
        this.sm.saveSuccess();
        this.sched.onSaveStarted(now);
        // R01/A1-03：写入完成只确认快照版本；保存期间有更新版本 → 恢复 DIRTY
        if (this.dirtyAfterSave || this.latestVersion > snap.version) {
          this.dirtyAfterSave = false;
          this.sm.edit();
          // 从最后一次编辑时刻重新起防抖（可能已到期 → 下一轮 tick 立即收敛）
          this.sched.onInput(this.lastEditAt);
        }
        return 'saved';
      }
      if ((result as WriteFailResult).reason === 'conflict') {
        this.sm.externalChange();
        this.sched.onSaveStarted(now);
        return 'conflict';
      }
      this.sm.saveFailure();
      return 'failed';
    } catch (e) {
      this.sm.saveFailure();
      return 'failed';
    }
  }
}
