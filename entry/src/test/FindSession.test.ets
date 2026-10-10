import { describe, expect, it } from '@ohos/hypium';
import { FindSession } from '../main/ets/domain/editor/FindSession';

/**
 * 查找会话导航（回绕语义）。
 */
export default function findSessionTest(): void {
  describe('FindSession', () => {
    it('next_starts_at_zero_from_unpositioned', 0, () => {
      expect(FindSession.next(3, -1)).assertEqual(0);
    });

    it('next_advances', 0, () => {
      expect(FindSession.next(3, 0)).assertEqual(1);
      expect(FindSession.next(3, 1)).assertEqual(2);
    });

    it('next_wraps_at_end', 0, () => {
      expect(FindSession.next(3, 2)).assertEqual(0);
    });

    it('prev_from_unpositioned_goes_last', 0, () => {
      expect(FindSession.prev(3, -1)).assertEqual(2);
    });

    it('prev_retreats', 0, () => {
      expect(FindSession.prev(3, 2)).assertEqual(1);
      expect(FindSession.prev(3, 1)).assertEqual(0);
    });

    it('prev_wraps_at_start', 0, () => {
      expect(FindSession.prev(3, 0)).assertEqual(2);
    });

    it('empty_matches_always_negative', 0, () => {
      expect(FindSession.next(0, -1)).assertEqual(-1);
      expect(FindSession.next(0, 0)).assertEqual(-1);
      expect(FindSession.prev(0, -1)).assertEqual(-1);
      expect(FindSession.prev(0, 2)).assertEqual(-1);
    });

    it('single_match_stays_put', 0, () => {
      expect(FindSession.next(1, 0)).assertEqual(0);
      expect(FindSession.prev(1, 0)).assertEqual(0);
    });
  });
}
