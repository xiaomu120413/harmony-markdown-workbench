/**
 * 查找会话导航（FR-EDIT-004 面板交互，纯逻辑）。
 * 输入：命中总数与当前索引（0 起，-1 表示尚未定位）；
 * 输出：推进/回退后的索引，越界回绕；空命中集恒 -1。
 */
export class FindSession {
  /** 下一处命中：-1 → 0；末尾回绕到 0；空集 → -1 */
  static next(count: number, current: number): number {
    if (count <= 0) {
      return -1;
    }
    if (current < 0) {
      return 0;
    }
    return (current + 1) % count;
  }

  /** 上一处命中：-1 → 末尾；0 回绕到末尾；空集 → -1 */
  static prev(count: number, current: number): number {
    if (count <= 0) {
      return -1;
    }
    if (current < 0) {
      return count - 1;
    }
    return (current - 1 + count) % count;
  }
}
