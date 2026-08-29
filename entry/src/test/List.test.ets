import { describe, expect, it } from '@ohos/hypium';
import saveStateMachineTest from './SaveStateMachine.test';
import fileRevisionTest from './FileRevision.test';
import draftDecisionTest from './DraftDecision.test';
import recentFileListTest from './RecentFileList.test';
import fileNameValidatorTest from './FileNameValidator.test';
import textEncodingTest from './TextEncoding.test';
import documentAdapterContractTest from './DocumentAdapterContract.test';
import saveSchedulerTest from './SaveScheduler.test';
import bridgeProtocolTest from './BridgeProtocol.test';

/**
 * 测试入口（hvigor 单测索引固定引用本文件，业务套件在此聚合注册）。
 * - BaselineSmoke：框架冒烟
 * - SaveStateMachine / FileRevision / DraftDecision：M0-04 领域层
 * - RecentFileList / FileNameValidator / TextEncoding / AdapterContract：M1 领域层先行
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
  recentFileListTest();
  fileNameValidatorTest();
  textEncodingTest();
  documentAdapterContractTest();
  saveSchedulerTest();
  bridgeProtocolTest();
}