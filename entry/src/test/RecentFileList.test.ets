import { describe, expect, it } from '@ohos/hypium';
import { RecentFileList, RECENT_LIMIT } from '../main/ets/domain/document/RecentFileList';

/**
 * M1-02 领域层先行：最近文件排序/固定/淘汰（FR-RECENT）。
 */
export default function recentFileListTest(): void {
  describe('RecentFileList', () => {
    it('touch_inserts_and_sorts_desc', 0, () => {
      const list = new RecentFileList();
      list.touch('a', 100);
      list.touch('b', 200);
      list.touch('c', 300);
      const s = list.snapshot();
      expect(s.length).assertEqual(3);
      expect(s[0].documentId).assertEqual('c');
      expect(s[2].documentId).assertEqual('a');
    });

    it('touch_updates_time_of_existing', 0, () => {
      const list = new RecentFileList();
      list.touch('a', 100);
      list.touch('a', 999);
      const s = list.snapshot();
      expect(s.length).assertEqual(1);
      expect(s[0].lastOpenedAt).assertEqual(999);
    });

    it('evicts_oldest_unpinned_over_limit', 0, () => {
      const list = new RecentFileList();
      for (let i = 0; i < RECENT_LIMIT + 5; i++) {
        list.touch(`doc-${i}`, i);
      }
      expect(list.size).assertEqual(RECENT_LIMIT);
      // 最旧的 doc-0..doc-4 应被淘汰
      const ids = list.snapshot().map((e) => e.documentId);
      expect(ids.includes('doc-0')).assertFalse();
      expect(ids.includes('doc-4')).assertFalse();
      expect(ids.includes(`doc-${RECENT_LIMIT + 4}`)).assertTrue();
    });

    it('pinned_not_evicted', 0, () => {
      const list = new RecentFileList();
      list.touch('old-pinned', 0, true);
      for (let i = 1; i <= RECENT_LIMIT + 5; i++) {
        list.touch(`doc-${i}`, i);
      }
      const ids = list.snapshot().map((e) => e.documentId);
      expect(ids.includes('old-pinned')).assertTrue();
    });

    it('set_pinned_and_remove', 0, () => {
      const list = new RecentFileList();
      list.touch('a', 1);
      list.setPinned('a', true);
      const s = list.snapshot();
      expect(s[0].pinned).assertTrue();
      list.remove('a');
      expect(list.size).assertEqual(0);
    });

    it('constructor_normalizes_duplicates', 0, () => {
      const list = new RecentFileList([
        { documentId: 'x', lastOpenedAt: 5, pinned: false },
        { documentId: 'x', lastOpenedAt: 9, pinned: false },
        { documentId: 'y', lastOpenedAt: 3, pinned: false },
      ]);
      expect(list.size).assertEqual(2);
      expect(list.snapshot()[0].documentId).assertEqual('x');
    });
  });
}