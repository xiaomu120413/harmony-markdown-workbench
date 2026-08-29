import { describe, expect, it } from '@ohos/hypium';
import { DraftDecisionEvaluator, RecoveryDecision, RecoveryDraft } from '../main/ets/domain/recovery/DraftDecision';
import { FileRevision } from '../main/ets/domain/document/FileRevision';

function makeDraft(content: string, base: FileRevision): RecoveryDraft {
  return {
    documentId: 'doc-1',
    sourceFingerprint: 'file://x',
    baseRevision: base,
    content: content,
    updatedAt: 1000,
    appVersion: '0.1.0',
  };
}

/**
 * TASK-M0-04 领域层：启动恢复决策（SDD 9.3）单测。
 */
export default function draftDecisionTest(): void {
  describe('DraftDecisionEvaluator', () => {
    const baseRev: FileRevision = { size: 10, contentHash: 'base-hash' };
    const diskSame: FileRevision = { size: 10, contentHash: 'base-hash' };

    it('no_draft_no_action', 0, () => {
      expect(DraftDecisionEvaluator.decide(undefined, diskSame, '')).assertEqual(RecoveryDecision.NO_DRAFT);
    });

    it('disk_missing_draft_restores', 0, () => {
      // 磁盘文件不存在（外部删除后崩溃）→ 草稿是唯一内容 → 恢复
      expect(DraftDecisionEvaluator.decide(makeDraft('content', baseRev), undefined, 'draft-hash')).assertEqual(
        RecoveryDecision.RESTORE_DRAFT);
    });

    it('disk_unchanged_draft_new_restores', 0, () => {
      // 磁盘未变（== 草稿基线）、草稿有未保存输入 → 恢复草稿
      expect(DraftDecisionEvaluator.decide(makeDraft('new content', baseRev), diskSame, 'draft-hash-2')).assertEqual(
        RecoveryDecision.RESTORE_DRAFT);
    });

    it('save_completed_draft_discarded', 0, () => {
      // 磁盘 == 草稿基线且草稿内容已落盘（哈希一致）→ 草稿冗余清理
      expect(DraftDecisionEvaluator.decide(makeDraft('base', baseRev), diskSame, 'base-hash')).assertEqual(
        RecoveryDecision.DISCARD_REDUNDANT);
    });

    it('disk_changed_and_draft_changed_conflicts', 0, () => {
      // 磁盘被外部修改且草稿也有新内容 → 冲突，不自动合并
      const draft: RecoveryDraft = makeDraft('draft with new edits', baseRev);
      const diskChanged: FileRevision = { size: 20, contentHash: 'disk-hash-2' };
      expect(DraftDecisionEvaluator.decide(draft, diskChanged, 'draft-hash-3')).assertEqual(
        RecoveryDecision.CONFLICT);
    });

    it('disk_matches_draft_after_save_discarded', 0, () => {
      // 外部修改后磁盘内容恰为草稿内容（崩溃前保存已生效）→ 冗余
      const draft: RecoveryDraft = makeDraft('saved', { size: 20, contentHash: 'disk-hash-2' });
      const diskChanged: FileRevision = { size: 20, contentHash: 'disk-hash-2' };
      expect(DraftDecisionEvaluator.decide(draft, diskChanged, 'disk-hash-2')).assertEqual(
        RecoveryDecision.DISCARD_REDUNDANT);
    });
  });
}