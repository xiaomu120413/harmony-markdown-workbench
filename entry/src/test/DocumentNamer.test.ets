import { describe, expect, it } from '@ohos/hypium';
import { DocumentNamer } from '../main/ets/domain/document/DocumentNamer';

/**
 * V0.2.2 产品化：新文档智能命名。
 */
export default function documentNamerTest(): void {
  describe('DocumentNamer', () => {
    it('uses_first_nonempty_line', 0, () => {
      expect(DocumentNamer.derive('\n\n会议纪要\n正文', [])).assertEqual('会议纪要.md');
    });

    it('strips_heading_marker_and_md_syntax', 0, () => {
      expect(DocumentNamer.derive('# 项目 **周报**', [])).assertEqual('项目 周报.md');
    });

    it('removes_illegal_filename_chars', 0, () => {
      expect(DocumentNamer.derive('a/b:c*d?e', [])).assertEqual('abcde.md');
    });

    it('empty_content_falls_back', 0, () => {
      expect(DocumentNamer.derive('', [])).assertEqual('未命名文档.md');
      expect(DocumentNamer.derive('   \n\n', [])).assertEqual('未命名文档.md');
    });

    it('long_title_truncated', 0, () => {
      const name = DocumentNamer.derive('一'.repeat(50), []);
      expect(name.length).assertEqual(DocumentNamer.MAX_BASE + 3); // 30 字 + '.md'
    });

    it('dedup_appends_sequence', 0, () => {
      const existing: string[] = ['周报.md', '周报(2).md'];
      expect(DocumentNamer.derive('周报', existing)).assertEqual('周报(3).md');
    });

    it('no_collision_keeps_plain_name', 0, () => {
      expect(DocumentNamer.derive('周报', ['其他.md'])).assertEqual('周报.md');
    });

    // ---- 自动名升级（首次保存早于标题输入完成的场景） ----

    it('is_auto_name_matches_fallback_names', 0, () => {
      expect(DocumentNamer.isAutoName('未命名文档.md')).assertTrue();
      expect(DocumentNamer.isAutoName('未命名文档(3).md')).assertTrue();
      expect(DocumentNamer.isAutoName('周报.md')).assertFalse();
      expect(DocumentNamer.isAutoName('未命名-1791602218415.md')).assertFalse();
    });

    it('upgrade_auto_name_once_title_available', 0, () => {
      const r = DocumentNamer.upgrade('未命名文档.md', '# 会议纪要\n正文', []);
      expect(r).assertEqual('会议纪要.md');
    });

    it('upgrade_skipped_when_still_no_title', 0, () => {
      expect(DocumentNamer.upgrade('未命名文档.md', '\n\n', [])).assertUndefined();
    });

    it('upgrade_only_for_auto_names', 0, () => {
      // 已有真实名字的文档不重命名
      expect(DocumentNamer.upgrade('周报.md', '# 完全新的内容', [])).assertUndefined();
    });

    it('upgrade_dedups_against_library', 0, () => {
      const r = DocumentNamer.upgrade('未命名文档.md', '# 周报', ['周报.md']);
      expect(r).assertEqual('周报(2).md');
    });
  });
}
