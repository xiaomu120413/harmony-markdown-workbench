import { describe, expect, it } from '@ohos/hypium';
import { MarkdownCommands } from '../main/ets/domain/editor/MarkdownCommands';

/**
 * M2-04 领域层先行：快捷栏命令文本变换（FR-EDIT-002 验收：
 * 每个命令覆盖空选区和非空选区；包裹后光标/选区合理）。
 */
export default function markdownCommandsTest(): void {
  describe('MarkdownCommands', () => {
    it('wrap_bold_nonempty_selection', 0, () => {
      const r = MarkdownCommands.apply('hello world', { from: 0, to: 5 }, 'bold');
      expect(r.text).assertEqual('**hello** world');
      expect(r.selection.from).assertEqual(2);
      expect(r.selection.to).assertEqual(7);
    });

    it('wrap_bold_empty_selection_places_cursor', 0, () => {
      const r = MarkdownCommands.apply('abc', { from: 1, to: 1 }, 'bold');
      expect(r.text).assertEqual('a**加粗文本**bc');
      expect(r.selection.from).assertEqual(1 + 2 + 4); // 光标停在内容尾
    });

    it('wrap_strike', 0, () => {
      const r = MarkdownCommands.apply('x', { from: 0, to: 1 }, 'strike');
      expect(r.text).assertEqual('~~x~~');
    });

    it('wrap_toggle_removes_bold', 0, () => {
      const r = MarkdownCommands.apply('**bold**', { from: 0, to: 8 }, 'bold');
      expect(r.text).assertEqual('bold');
    });

    it('link_inserts_template', 0, () => {
      const r = MarkdownCommands.apply('', { from: 0, to: 0 }, 'link');
      expect(r.text).assertEqual('[链接文字](https://)');
    });

    it('ul_single_line', 0, () => {
      const r = MarkdownCommands.apply('item', { from: 0, to: 4 }, 'ul');
      expect(r.text).assertEqual('- item');
    });

    it('ol_multi_line_numbered', 0, () => {
      // 选区仅覆盖前两行（0..3），第三行保留 → 只前两行编号
      const r = MarkdownCommands.apply('a\nb\nc', { from: 0, to: 3 }, 'ol');
      expect(r.text).assertEqual('1. a\n2. b\nc');
    });

    it('task_list_line', 0, () => {
      const r = MarkdownCommands.apply('todo', { from: 0, to: 4 }, 'task');
      expect(r.text).assertEqual('- [ ] todo');
    });

    it('quote_multi_line', 0, () => {
      const r = MarkdownCommands.apply('one\ntwo', { from: 0, to: 7 }, 'quote');
      expect(r.text).assertEqual('> one\n> two');
    });

    it('inline_code_wrap', 0, () => {
      const r = MarkdownCommands.apply('abc', { from: 1, to: 2 }, 'inlineCode');
      expect(r.text).assertEqual('a`b`c');
    });

    it('selection_kept_within_wrap', 0, () => {
      const r = MarkdownCommands.apply('hello', { from: 1, to: 4 }, 'italic');
      expect(r.text).assertEqual('h*ell*o');
      expect(r.selection.from).assertEqual(2);
      expect(r.selection.to).assertEqual(5);
    });

    // ---- V0.2.1：标题等级 / 分隔线 / 表格 ----

    it('heading_adds_prefix_on_plain_line', 0, () => {
      const r = MarkdownCommands.apply('标题文字', { from: 0, to: 4 }, 'h2');
      expect(r.text).assertEqual('## 标题文字');
      // 光标随前缀平移，不低于行首
      expect(r.selection.from).assertEqual(3);
    });

    it('heading_midline_uses_its_line', 0, () => {
      const r = MarkdownCommands.apply('a\n标题\nb', { from: 2, to: 4 }, 'h1');
      expect(r.text).assertEqual('a\n# 标题\nb');
    });

    it('heading_same_level_toggles_off', 0, () => {
      const r = MarkdownCommands.apply('### 三级', { from: 0, to: 6 }, 'h3');
      expect(r.text).assertEqual('三级');
    });

    it('heading_switches_between_levels', 0, () => {
      const r = MarkdownCommands.apply('### 三级', { from: 0, to: 6 }, 'h1');
      expect(r.text).assertEqual('# 三级');
    });

    it('heading_h6_deepest', 0, () => {
      const r = MarkdownCommands.apply('深', { from: 0, to: 1 }, 'h6');
      expect(r.text).assertEqual('###### 深');
    });

    it('hr_inserts_at_cursor', 0, () => {
      const r = MarkdownCommands.apply('ab', { from: 1, to: 1 }, 'hr');
      expect(r.text).assertEqual('a---\nb');
      expect(r.selection.from).assertEqual(5);
    });

    it('table_inserts_snippet', 0, () => {
      const r = MarkdownCommands.apply('', { from: 0, to: 0 }, 'table');
      expect(r.text).assertEqual('| 列1 | 列2 |\n| --- | --- |\n| 内容 | 内容 |\n');
    });

    // ---- V0.4.1：缩进/减少缩进（嵌套列表） ----

    it('indent_adds_two_spaces_per_line', 0, () => {
      const r = MarkdownCommands.apply('- a\n- b', { from: 0, to: 9 }, 'indent');
      expect(r.text).assertEqual('  - a\n  - b');
    });

    it('outdent_removes_up_to_two_spaces', 0, () => {
      const r = MarkdownCommands.apply('  - a\n    - b', { from: 0, to: 15 }, 'outdent');
      expect(r.text).assertEqual('- a\n  - b');
    });

    it('outdent_no_leading_space_unchanged', 0, () => {
      const r = MarkdownCommands.apply('- a', { from: 0, to: 3 }, 'outdent');
      expect(r.text).assertEqual('- a');
    });

    it('outdent_single_space_removed', 0, () => {
      const r = MarkdownCommands.apply(' - a', { from: 0, to: 4 }, 'outdent');
      expect(r.text).assertEqual('- a');
    });

    it('highlight_wraps_with_double_equals', 0, () => {
      const r = MarkdownCommands.apply('重点内容', { from: 0, to: 4 }, 'highlight');
      expect(r.text).assertEqual('==重点内容==');
    });

    it('highlight_toggle_removes', 0, () => {
      const r = MarkdownCommands.apply('==重点内容==', { from: 0, to: 8 }, 'highlight');
      expect(r.text).assertEqual('重点内容');
    });
  });

}