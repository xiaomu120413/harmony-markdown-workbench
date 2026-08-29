/**
 * 保存状态机（FR-SAVE-001）。
 *
 * 状态：
 *   CLEAN   已保存且与磁盘一致
 *   DIRTY   有未保存修改
 *   SAVING  正在写入
 *   ERROR   写入失败（保留 dirty 语义，可重试）
 *   CONFLICT 磁盘被外部修改（禁止默认覆盖，等待用户决策）
 *
 * 合法迁移：
 *   CLEAN  --edit-->             DIRTY
 *   DIRTY  --beginSave-->        SAVING
 *   DIRTY  --externalChange-->   CONFLICT
 *   SAVING --saveSuccess-->      CLEAN
 *   SAVING --saveFailure-->      ERROR
 *   SAVING --externalChange-->   CONFLICT
 *   ERROR  --retry-->            SAVING
 *   ERROR  --externalChange-->   CONFLICT
 *   CONFLICT --decideKeepDisk--> CLEAN   （使用磁盘版本重新加载）
 *   CONFLICT --decideKeepLocal--> DIRTY  （保留当前内容为副本/继续编辑）
 *
 * 其余迁移一律非法（抛 DomainError），校验行为有单测覆盖（M4-01 验收）。
 */
export enum SaveState {
  CLEAN = 'clean',
  DIRTY = 'dirty',
  SAVING = 'saving',
  ERROR = 'error',
  CONFLICT = 'conflict',
}

export class InvalidTransitionError extends Error {
  constructor(from: SaveState, action: string) {
    super(`invalid save-state transition: ${from} --${action}-->`);
    this.name = 'InvalidTransitionError';
  }
}

export class SaveStateMachine {
  private _state: SaveState;

  constructor(initial: SaveState = SaveState.CLEAN) {
    this._state = initial;
  }

  get state(): SaveState {
    return this._state;
  }

  edit(): void {
    this.transition(SaveState.DIRTY, 'edit');
  }

  beginSave(): void {
    this.transition(SaveState.SAVING, 'beginSave');
  }

  saveSuccess(): void {
    this.transition(SaveState.CLEAN, 'saveSuccess');
  }

  saveFailure(): void {
    this.transition(SaveState.ERROR, 'saveFailure');
  }

  retry(): void {
    this.transition(SaveState.SAVING, 'retry');
  }

  externalChange(): void {
    this.transition(SaveState.CONFLICT, 'externalChange');
  }

  /** 用户决策：使用磁盘版本重新加载 → 干净状态 */
  decideKeepDisk(): void {
    this.transition(SaveState.CLEAN, 'decideKeepDisk');
  }

  /** 用户决策：保留当前内容（导出副本或继续编辑）→ 回到脏状态 */
  decideKeepLocal(): void {
    this.transition(SaveState.DIRTY, 'decideKeepLocal');
  }

  private transition(next: SaveState, action: string): void {
    if (!SaveStateMachine.isLegal(this._state, action, next)) {
      throw new InvalidTransitionError(this._state, action);
    }
    this._state = next;
  }

  static isLegal(from: SaveState, action: string, to: SaveState): boolean {
    switch (from) {
      case SaveState.CLEAN:
        return action === 'edit' && to === SaveState.DIRTY;
      case SaveState.DIRTY:
        return (action === 'beginSave' && to === SaveState.SAVING) ||
          (action === 'externalChange' && to === SaveState.CONFLICT);
      case SaveState.SAVING:
        return (action === 'saveSuccess' && to === SaveState.CLEAN) ||
          (action === 'saveFailure' && to === SaveState.ERROR) ||
          (action === 'externalChange' && to === SaveState.CONFLICT);
      case SaveState.ERROR:
        return (action === 'retry' && to === SaveState.SAVING) ||
          (action === 'externalChange' && to === SaveState.CONFLICT);
      case SaveState.CONFLICT:
        return (action === 'decideKeepDisk' && to === SaveState.CLEAN) ||
          (action === 'decideKeepLocal' && to === SaveState.DIRTY);
      default:
        return false;
    }
  }

  /** 用可读格式输出状态（日志/UI 只靠文字，不依赖颜色，SDD 6.4） */
  static label(s: SaveState): string {
    switch (s) {
      case SaveState.CLEAN:
        return '已保存';
      case SaveState.DIRTY:
        return '未保存';
      case SaveState.SAVING:
        return '保存中';
      case SaveState.ERROR:
        return '保存失败';
      case SaveState.CONFLICT:
        return '外部冲突';
      default:
        return '';
    }
  }
}