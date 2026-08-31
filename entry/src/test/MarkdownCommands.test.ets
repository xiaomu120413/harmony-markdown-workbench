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
  });

}