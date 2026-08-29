import { describe, expect, it } from '@ohos/hypium';
import { HeadingOutline, OutlineItem } from '../main/ets/domain/editor/HeadingOutline';

/**
 * M3-03 领域层先行：大纲提取（FR-PREVIEW-003）。
 */
export default function headingOutlineTest(): void {
  describe('HeadingOutline', () => {
    it('extracts_levels_1_to_6', 0, () => {
      const items = HeadingOutline.extract('# H1\n## H2\n###### H6');
      expect(items.length).assertEqual(3);
      expect(items[0].level).assertEqual(1);
      expect(items[1].level).assertEqual(2);
      expect(items[2].level).assertEqual(6);
    });

    it('ignores_non_headings', 0, () => {
      const items = HeadingOutline.extract('plain text\n- list\n# real heading\n#not-heading');
      expect(items.length).assertEqual(1);
      expect(items[0].text).assertEqual('real heading');
    });

    it('duplicate_titles_get_unique_ids', 0, () => {
      const items = HeadingOutline.extract('# Intro\n## Detail\n# Intro');
      expect(items.length).assertEqual(3);
      expect(items[0].id).assertEqual('Intro');
      expect(items[2].id).assertEqual('Intro-1');
      expect(items[2].id === items[0].id).assertFalse();
    });

    it('line_numbers_tracked', 0, () => {
      const items = HeadingOutline.extract('a\n# T\nb\n# U');
      expect(items[0].line).assertEqual(1);
      expect(items[1].line).assertEqual(3);
    });

    it('empty_or_whitespace_only_markdown', 0, () => {
      expect(HeadingOutline.extract('').length).assertEqual(0);
      expect(HeadingOutline.extract('   \n\n').length).assertEqual(0);
    });

    it('large_document_parses', 0, () => {
      // 模拟 1000 个标题的长文（S2 样本特征）
      let doc = '';
      for (let i = 0; i < 1000; i++) {
        doc += `# heading ${i}\n`;
      }
      const items = HeadingOutline.extract(doc);
      expect(items.length).assertEqual(1000);
      expect(items[500].text).assertEqual('heading 500');
    });

    it('heading_text_trimmed', 0, () => {
      const items = HeadingOutline.extract('#   padded   ');
      expect(items[0].text).assertEqual('padded');
    });
  });

  // 类型引用（避免未使用导入告警）
  function ref(): void {
    const o: OutlineItem = { level: 1, text: '', id: '', line: 0 };
    void o;
  }
}