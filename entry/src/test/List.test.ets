import { describe, expect, it } from '@ohos/hypium';
import saveStateMachineTest from './SaveStateMachine.test';
import fileRevisionTest from './FileRevision.test';
import draftDecisionTest from './DraftDecision.test';

/**
 * 测试入口（hvigor 单测索引固定引用本文件，业务套件在此聚合注册）。
 * - BaselineSmoke：框架冒烟
 * - SaveStateMachine / FileRevision / DraftDecision：M0-04 领域层
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

  saveStateMachineTest();
  fileRevisionTest();
  draftDecisionTest();
}