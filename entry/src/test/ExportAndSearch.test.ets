import { describe, expect, it } from '@ohos/hypium';
import { HtmlExporter } from '../main/ets/domain/document/HtmlExporter';
import { LibrarySearch, LibraryDoc } from '../main/ets/domain/document/LibrarySearch';
import { FindOptions } from '../main/ets/domain/editor/FindReplaceEngine';

/**
 * V0.4.3：HTML 导出组装 + 资料库全文搜索。
 */
export default function exportAndSearchTest(): void {
  describe('HtmlExporter', () => {
    it('export_name_strips_md_suffix', 0, () => {
      expect(HtmlExporter.exportFileName('周报.md')).assertEqual('周报.html');
      expect(HtmlExporter.exportFileName('README.MD')).assertEqual('README.html');
    });

    it('export_name_fallback_when_empty', 0, () => {
      expect(HtmlExporter.exportFileName('.md')).assertEqual('未命名文档.html');
    });

    it('standalone_contains_body_and_styles', 0, () => {
      const html = HtmlExporter.buildStandalone('标题A', '<h1>标题A</h1>');
      expect(html.startsWith('<!DOCTYPE html>')).assertTrue();
      expect(html.includes('<h1>标题A</h1>')).assertTrue();
      expect(html.includes('font-family')).assertTrue();
      expect(html.endsWith('</html>')).assertTrue();
    });

    it('title_escaped', 0, () => {
      const html = HtmlExporter.buildStandalone('<script>', 'x');
      expect(html.includes('<title>&lt;script&gt;</title>')).assertTrue();
      expect(html.includes('<title><script>')).assertFalse();
    });
  });

  describe('LibrarySearch', () => {
    const ci: FindOptions = { caseSensitive: false, wholeWord: false };
    const docs: LibraryDoc[] = [
      { name: 'a.md', content: '这是一段足够长的开场白用来撑开上下文窗口的宽度，会议纪要提到预算的内容出现在中部位置，随后还有一段收尾文字继续拉长整体篇幅以便产生省略号。' },
      { name: 'b.md', content: '完全无关的内容' },
      { name: 'c.md', content: 'BUDGET 大写形式' },
    ];

    it('search_finds_matching_docs_only', 0, () => {
      const r = LibrarySearch.search(docs, '预算', ci);
      expect(r.length).assertEqual(1);
      expect(r[0].name).assertEqual('a.md');
      expect(r[0].count).assertEqual(1);
    });

    it('search_case_insensitive_matches_case_variants', 0, () => {
      const r = LibrarySearch.search(docs, 'budget', ci);
      expect(r.length).assertEqual(1);
      expect(r[0].name).assertEqual('c.md');
    });

    it('search_case_sensitive_filter', 0, () => {
      const r = LibrarySearch.search(docs, 'BUDGET', { caseSensitive: true, wholeWord: false });
      expect(r.length).assertEqual(1);
      expect(r[0].name).assertEqual('c.md');
      const r2 = LibrarySearch.search(docs, 'budget', { caseSensitive: true, wholeWord: false });
      expect(r2.length).assertEqual(0);
    });

    it('snippet_has_context_and_ellipsis', 0, () => {
      const r = LibrarySearch.search(docs, '预算', ci);
      // 命中位于长文中部：前后均有上下文并带省略号
      expect(r[0].snippet.startsWith('…')).assertTrue();
      expect(r[0].snippet.endsWith('…')).assertTrue();
      expect(r[0].snippet.includes('预算')).assertTrue();
    });

    it('empty_query_returns_nothing', 0, () => {
      expect(LibrarySearch.search(docs, '', ci).length).assertEqual(0);
    });
  });
}
