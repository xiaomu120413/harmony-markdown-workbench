/**
 * 文档修订（磁盘基线）模型（FR-FILE-004）。
 * 领域层纯逻辑：不依赖 @ohos 平台模块，便于单元测试（SDD 11.1）。
 * 内容哈希由基础层注入（实现方可用 @ohos.security.cryptoFramework / util）。
 */
export interface FileRevision {
  size: number;
  modifiedTime?: number;
  contentHash: string;
}

/**
 * 修订比较：外部变化检测。
 * 规则（SDD FR-FILE-004）：
 *  - size 变化必然冲突；
 *  - 内容哈希不同视为冲突（修改时间不可用或不可靠时以哈希兜底）；
 *  - 修改时间变化但 size/hash 相同时不算冲突（时间戳抖动容忍）。
 */
export class FileRevisionCompare {
  static isSame(base: FileRevision, disk: FileRevision): boolean {
    if (base.size !== disk.size) {
      return false;
    }
    return base.contentHash === disk.contentHash;
  }

  static hasChanged(base: FileRevision, disk: FileRevision): boolean {
    return !FileRevisionCompare.isSame(base, disk);
  }
}