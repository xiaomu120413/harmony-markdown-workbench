import { describe, expect, it } from '@ohos/hypium';
import { FileRevision, FileRevisionCompare } from '../main/ets/domain/document/FileRevision';

/**
 * TASK-M0-04 领域层：外部变更检测（FR-FILE-004）单测。
 */
export default function fileRevisionTest(): void {
  describe('FileRevisionCompare', () => {
    const base: FileRevision = { size: 100, contentHash: 'hash-a' };

    it('same_revision_is_same', 0, () => {
      const disk: FileRevision = { size: 100, contentHash: 'hash-a' };
      expect(FileRevisionCompare.isSame(base, disk)).assertTrue();
      expect(FileRevisionCompare.hasChanged(base, disk)).assertFalse();
    });

    it('size_change_detected', 0, () => {
      const disk: FileRevision = { size: 101, contentHash: 'hash-a' };
      expect(FileRevisionCompare.hasChanged(base, disk)).assertTrue();
    });

    it('hash_change_detected_even_with_same_size', 0, () => {
      // 外部修改了相同长度内容：size 相同但 hash 不同 → 冲突
      const disk: FileRevision = { size: 100, contentHash: 'hash-b' };
      expect(FileRevisionCompare.hasChanged(base, disk)).assertTrue();
    });

    it('modified_time_change_with_same_hash_not_conflict', 0, () => {
      // 时间戳抖动容忍：仅 mtime 变化不视为冲突
      const disk: FileRevision = {
        size: 100, contentHash: 'hash-a', modifiedTime: (base.modifiedTime as number) + 1
      };
      expect(FileRevisionCompare.hasChanged(base, disk)).assertFalse();
    });

    it('empty_revisions_compared', 0, () => {
      const a: FileRevision = { size: 0, contentHash: '' };
      const b: FileRevision = { size: 0, contentHash: '' };
      expect(FileRevisionCompare.isSame(a, b)).assertTrue();
    });
  });
}