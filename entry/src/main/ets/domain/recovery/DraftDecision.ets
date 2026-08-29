import { FileRevision } from '../document/FileRevision';

/**
 * 恢复草稿模型（FR-SAVE-004）。草稿只保存在应用私有目录，
 * 正文不在其中作为唯一副本（ADR-002）。
 */
export interface RecoveryDraft {
  documentId: string;
  sourceFingerprint: string;
  baseRevision: FileRevision;
  content: string;
  updatedAt: number;
  appVersion: string;
}

/**
 * 启动恢复决策（SDD 9.3）：
 * 1. 扫描未完成会话和草稿索引。
 * 2. 比较草稿时间、基线 revision 和磁盘 revision。
 * 3. 完全一致且磁盘内容已包含草稿时，清理冗余草稿。
 * 4. 草稿更新但磁盘未更新时，提示恢复。
 * 5. 草稿和磁盘都变化时，进入冲突恢复，不自动合并。
 */
export enum RecoveryDecision {
  NO_DRAFT = 'no_draft',
  DISCARD_REDUNDANT = 'discard_redundant',
  RESTORE_DRAFT = 'restore_draft',
  CONFLICT = 'conflict',
}

export class DraftDecisionEvaluator {
  /**
   * @param draft 磁盘上的草稿（可为空）
   * @param diskRevision 当前磁盘文件修订
   * @param draftContentHash 草稿内容的哈希（由基础设施层用真实哈希实现计算，
   *        保持领域层纯逻辑可单测，SDD 11.1）
   * @returns 决策
   */
  static decide(
    draft: RecoveryDraft | undefined,
    diskRevision: FileRevision | undefined,
    draftContentHash: string,
  ): RecoveryDecision {
    if (draft === undefined) {
      return RecoveryDecision.NO_DRAFT;
    }
    if (diskRevision === undefined) {
      // 磁盘文件不存在（外部删除后崩溃）：草稿是唯一可信内容
      return RecoveryDecision.RESTORE_DRAFT;
    }
    const diskUnchanged: boolean =
      draft.baseRevision.size === diskRevision.size &&
      draft.baseRevision.contentHash === diskRevision.contentHash;
    if (diskUnchanged) {
      // 磁盘 == 草稿基线：
      //  - 草稿内容已落盘（哈希一致）→ 冗余清理
      //  - 否则草稿还有未保存输入 → 恢复
      if (draftContentHash === diskRevision.contentHash) {
        return RecoveryDecision.DISCARD_REDUNDANT;
      }
      return RecoveryDecision.RESTORE_DRAFT;
    }
    // 磁盘被外部修改（!= 草稿基线）：
    //  - 草稿内容恰等于新磁盘（保存已生效）→ 冗余清理
    //  - 否则双份变更 → 冲突，不自动合并
    if (draftContentHash === diskRevision.contentHash) {
      return RecoveryDecision.DISCARD_REDUNDANT;
    }
    return RecoveryDecision.CONFLICT;
  }
}