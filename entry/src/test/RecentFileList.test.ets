import { describe, expect, it } from '@ohos/hypium';
import { RecentFileList, RECENT_LIMIT } from '../main/ets/domain/document/RecentFileList';

/**
 * M1-02 领域层先行：最近文件排序/固定/淘汰（FR-RECENT）。
 */
export default function recentFileListTest(): void {
  describe('RecentFileList', () => {
    it('transient_cache_uris_are_not_recent_documents', 0, () => {
      const list = new RecentFileList([
        { documentId: 'file://app/data/storage/el2/base/haps/entry/cache/a.md', lastOpenedAt: 3, pinned: false },
        { documentId: 'file://app/data/storage/el2/base/cache/b.md', lastOpenedAt: 2, pinned: false },
        { documentId: 'library/a.md', lastOpenedAt: 1, pinned: false },
      ]);
      expect(list.size).assertEqual(1);
    });
    it('uri_aliases_merge_latest_address_and_keep_pinned', 0, () => {
      const list = new RecentFileList([
        { documentId: 'file://docs/a/%E6%9C%A8%E7%AC%BA.md?old=1', lastOpenedAt: 1, pinned: true },
        { documentId: 'file://docs/a/木笺.md?new=1', lastOpenedAt: 2, pinned: false },
      ]);
      expect(list.size).assertEqual(1);
      expect(list.snapshot()[0].pinned).assertTrue();
      list.touch('file://docs/a/木笺.md?grant=3', 3);
      expect(list.size).assertEqual(1);
      expect(list.snapshot()[0].documentId).assertEqual('file://docs/a/木笺.md?grant=3');
      expect(RecentFileList.displayName(list.snapshot()[0].documentId)).assertEqual('木笺.md');
    });

    it('same_name_different_sources_are_kept_with_locations', 0, () => {
      const list = new RecentFileList();
      list.touch('library/a.md', 1);
      list.touch('file://docs/a/a.md', 2);
      list.touch('file://docs/b/a.md', 3);
      expect(list.size).assertEqual(3);
      expect(RecentFileList.location('library/a.md')).assertEqual('我的文档 · 应用内');
      expect(RecentFileList.location('file://docs/a/a.md')).assertEqual('外部 · docs/a');
    });

    it('display_name_internal_strips_library_prefix', 0, () => {
      expect(RecentFileList.displayName('library/周报.md')).assertEqual('周报.md');
      expect(RecentFileList.displayName('library/未命名文档(2).md')).assertEqual('未命名文档(2).md');
    });

    it('display_name_external_uri_takes_last_segment', 0, () => {
      expect(RecentFileList.displayName('file:///docs/notes/会议纪要.md')).assertEqual('会议纪要.md');
      expect(RecentFileList.displayName('filestorage://media/README.md')).assertEqual('README.md');
    });

    it('display_name_fallback', 0, () => {
      expect(RecentFileList.displayName('裸名.md')).assertEqual('裸名.md');
      expect(RecentFileList.displayName('a/')).assertEqual('a/');
    });

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
