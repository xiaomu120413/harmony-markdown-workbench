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
  getSnapshot: () => Promise<SnapshotData>;
  persist: (content: string) => Promise<WriteDocumentResult>;
  saveCheckpoint: (content: string) => Promise<void>;
  clearCheckpoint?: () => Promise<void>;
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
  private sessionId: string = '';
  private checkpointVersion: number = -1;
  private checkpointChain: Promise<void> = Promise.resolve();
  private checkpointInFlight: Promise<boolean> | undefined = undefined;
  private checkpointAgain: boolean = false;
  private _checkpointFailed: boolean = false;

  get checkpointFailed(): boolean {
    return this._checkpointFailed;
  }

  /** 恢复保护不改变原文件保存状态，不受自动保存开关影响。每批通知合并一次。 */
  checkpointNow(): Promise<boolean> {
    if (this.checkpointInFlight !== undefined) {
      this.checkpointAgain = true;
      return this.checkpointInFlight;
    }
    const work = this.drainCheckpoints();
    this.checkpointInFlight = work;
    work.then(() => { this.checkpointInFlight = undefined; }, () => { this.checkpointInFlight = undefined; });
    return work;
  }

  private async drainCheckpoints(): Promise<boolean> {
    let ok = false;
    do {
      this.checkpointAgain = false;
      ok = await this.captureCheckpoint();
    } while (ok && this.checkpointAgain);
    return ok;
  }

  private async captureCheckpoint(): Promise<boolean> {
    try {
      const snap = await this.deps.getSnapshot();
      if (!this.acceptSnapshot(snap)) {
        throw new Error('checkpoint snapshot unavailable');
      }
      if (snap.version > this.latestVersion) { this.onEdit(Date.now(), snap.version); }
      if (this.sm.state === SaveState.CLEAN) { return true; }
      await this.writeCheckpoint(snap);
      this._checkpointFailed = false;
      return true;
    } catch (e) {
      this._checkpointFailed = true;
      return false;
    }
  }

  private acceptSnapshot(snap: SnapshotData): boolean {
    if (!snap.ok || snap.sessionId.length === 0 || !Number.isFinite(snap.version) || snap.version < 0) {
      return false;
    }
    if (this.sessionId.length === 0) {
      this.sessionId = snap.sessionId;
    }
    return snap.sessionId === this.sessionId;
  }

  private writeCheckpoint(snap: SnapshotData): Promise<void> {
    const work = this.checkpointChain.then(async () => {
      if (!this.acceptSnapshot(snap)) {
        throw new Error('stale checkpoint session');
      }
      if (snap.version <= this.checkpointVersion) {
        return;
      }
      await this.deps.saveCheckpoint(snap.content);
      this.checkpointVersion = snap.version;
    });
    this.checkpointChain = work.then(() => {}, () => {});
    return work;
  }

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

  get documentVersion(): number { return this.latestVersion; }

  /**
   * 编辑事件。version 为编辑器单调递增版本（可选：旧协议缺省时退化为
   * dirtyAfterSave 布尔门控，不会丢内容，只会多一次收敛保存）。
   */
  onEdit(now: number, version?: number): void {
    if (version !== undefined && version <= this.latestVersion && this.sm.state === SaveState.CLEAN) { return; }
    this.lastEditAt = now;
    if (version !== undefined) {
      this.latestVersion = Math.max(this.latestVersion, version);
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
  onDocumentLoaded(sessionId: string = '', version: number = 0): void {
    this.latestVersion = version;
    this.dirtyAfterSave = false;
    this.lastEditAt = 0;
    this.sessionId = sessionId;
    this.checkpointVersion = -1;
    this._checkpointFailed = false;
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
    if (!this.acceptSnapshot(snap)) {
      // R02：Web 失败 ≠ 空正文。不写检查点不写文件，原文件字节不变。
      this.sm.saveFailure();
      return 'failed';
    }
    try {
      await this.writeCheckpoint(snap);
      const result = await this.deps.persist(snap.content);
      if (result.ok) {
        // 编辑通知可能比 IO 完成晚到，重新读取同会话版本后才能确认已保存。
        const current = await this.deps.getSnapshot();
        const caughtUp = this.acceptSnapshot(current) && current.version === snap.version && current.content === snap.content;
        this.sm.saveSuccess();
        this.latestVersion = Math.max(this.latestVersion, snap.version);
        this.sched.onSaveStarted(now);
        // R01/A1-03：写入完成只确认快照版本；保存期间有更新版本 → 恢复 DIRTY
        if (!caughtUp || this.dirtyAfterSave || this.latestVersion > snap.version) {
          this.dirtyAfterSave = false;
          this.sm.edit();
          // 从最后一次编辑时刻重新起防抖（可能已到期 → 下一轮 tick 立即收敛）
          this.sched.onInput(this.lastEditAt);
          if (this.acceptSnapshot(current)) {
            try { await this.writeCheckpoint(current); }
            catch (e) { this._checkpointFailed = true; }
          }
        } else if (this.deps.clearCheckpoint !== undefined) {
          try { await this.deps.clearCheckpoint(); }
          catch (e) { this._checkpointFailed = true; }
          this.checkpointVersion = -1;
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
