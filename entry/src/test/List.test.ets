import { describe, expect, it } from '@ohos/hypium';

/**
 * TASK-M0-01 示例测试套件。
 * 目的：验证 hvigor test 任务与 hypium 框架可用（工程基线门禁）。
 * 业务用例将在各功能任务中补充；本套件不是业务逻辑的替代测试。
 */
export default function listTest(): void {
  describe('BaselineSmoke', () => {
    it('hypium_basicTrue', 0, () => {
      expect(true).assertTrue();
    });

    it('hypium_arithmetic', 0, () => {
      expect(1 + 1).assertEqual(2);
    });

    it('hypium_stringConcat', 0, () => {
      expect('foo' + 'bar').assertEqual('foobar');
    });
  });
}