import { describe, expect, it } from '@ohos/hypium';
import { FindReplaceEngine, FindOptions } from '../main/ets/domain/editor/FindReplaceEngine';

/**
 * M3-04 领域层先行：查找替换（FR-EDIT-004）。
 */
export default function findReplaceEngineTest(): void {
  describe('FindReplaceEngine', () => {
    const ci: FindOptions = { caseSensitive: false, wholeWord: false };

    it('find_all_basic', 0, () => {
      const r = FindReplaceEngine.findAll('abc abc abc', 'abc', ci);
      expect(r.length).assertEqual(3);
      expect(r[0].from).assertEqual(0);
      expect(r[2].from).assertEqual(8);
    });

    it('case_insensitive_by_default', 0, () => {
      const r = FindReplaceEngine.findAll('AbC abc', 'abc', ci);
      expect(r.length).assertEqual(2);
    });

    it('case_sensitive_switch', 0, () => {
      const r = FindReplaceEngine.findAll('AbC abc', 'abc', { caseSensitive: true, wholeWord: false });
      expect(r.length).assertEqual(1);
    });

    it('whole_word_boundary', 0, () => {
      const r = FindReplaceEngine.findAll('the cat, these cats', 'cat', { caseSensitive: true, wholeWord: true });
      expect(r.length).assertEqual(1);
      expect(r[0].from).assertEqual(4);
    });

    it('empty_query_no_results', 0, () => {
      const r = FindReplaceEngine.findAll('abc', '', ci);
      expect(r.length).assertEqual(0);
    });

    it('replace_all_count_and_undos', 0, () => {
      const r = FindReplaceEngine.replaceAll('a-b-a', 'a', 'x', ci);
      expect(r.text).assertEqual('x-b-x');
      expect(r.count).assertEqual(2);
      expect(r.undos.length).assertEqual(2);
      expect(r.undos[0].oldText).assertEqual('a');
      expect(r.undos[0].from).assertEqual(0);
    });

    it('replace_current_next_match', 0, () => {
      // 从 from 起（含）的第一个匹配被替换；光标落在替换文本之后
      const r = FindReplaceEngine.replaceCurrent('a a a', 'a', 'x', 2, ci);
      expect(r.text).assertEqual('a x a');
      expect(r.newCursor).assertEqual(3);
      expect(r.replaced).assertTrue();
    });

    it('replace_current_wraps_around', 0, () => {
      // from 越过末尾（5 = 文本长度）→ 无"含起点"匹配 → 回绕替换第一个匹配
      const r = FindReplaceEngine.replaceCurrent('a a a', 'a', 'x', 5, ci);
      expect(r.text).assertEqual('x a a');
      expect(r.replaced).assertTrue();
    });

    it('replace_all_whole_word', 0, () => {
      const r = FindReplaceEngine.replaceAll('cat category cat', 'cat', 'dog', { caseSensitive: true, wholeWord: true });
      expect(r.text).assertEqual('dog category dog');
      expect(r.count).assertEqual(2);
    });
  });
}