/**
 * 自动保存调度（FR-SAVE-002）。
 * 规则：
 *  - 编辑停止 1.5 秒后触发保存（防抖）；
 *  - 连续输入时，最长 10 秒到达一次"保存/检查点"时刻（不强制频繁写外部文件）；
 *  - 同一文件的保存请求串行执行（调用方在 onSaveStarted/onSaveFinished 之间不重叠）；
 *  - 新保存请求到达时，过期未开始请求可合并（仅一次调度）。
 * 纯逻辑，时间由调用方注入（now），便于单测。
 */
export const SAVE_DEBOUNCE_MS: number = 1500;
export const SAVE_MAX_DELAY_MS: number = 10000;

export class SaveScheduler {
  private _pending: boolean = false;
  private lastInputAt: number = 0;
  private cycleStart: number = 0;
  private readonly debounceMs: number;
  private readonly maxDelayMs: number;

  constructor(debounceMs: number = SAVE_DEBOUNCE_MS, maxDelayMs: number = SAVE_MAX_DELAY_MS) {
    this.debounceMs = debounceMs;
    this.maxDelayMs = maxDelayMs;
  }

  get pending(): boolean {
    return this._pending;
  }

  /** 输入事件：记录输入时刻；若尚未调度则挂起待保存（合并重复请求） */
  onInput(now: number): void {
    this.lastInputAt = now;
    if (!this._pending) {
      this._pending = true;
    }
  }

  /**
   * 下一次保存应发生的时刻；无待保存时返回 undefined。
   * dueTime = min(最后一次输入 + 防抖, 本周期开始 + 最长延迟)
   */
  dueTime(): number | undefined {
    if (!this._pending) {
      return undefined;
    }
    const byDebounce = this.lastInputAt + this.debounceMs;
    const byMax = this.cycleStart + this.maxDelayMs;
    return byDebounce < byMax ? byDebounce : byMax;
  }

  /** 保存开始：开始新的周期（发出请求即视为本周期结束） */
  onSaveStarted(now: number): void {
    this._pending = false;
    this.cycleStart = now;
  }

  /** 保存完成（无论成败），后续输入重新调度 */
  onSaveFinished(): void {
    // 周期起点保持为最近一次保存开始；若期间有新输入（pending），
    // 以最后一次输入为基础重新按防抖计算。
    if (this._pending) {
      // 保留：dueTime 将按 lastInputAt + debounce 计算
    }
  }
}