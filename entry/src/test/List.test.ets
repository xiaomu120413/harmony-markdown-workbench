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
import saveCoordinatorTest from './SaveCoordinator.test';
import markdownCommandsTest from './MarkdownCommands.test';
import findReplaceEngineTest from './FindReplaceEngine.test';
import headingOutlineTest from './HeadingOutline.test';
import htmlSafetyTest from './HtmlSafety.test';
import appSettingsTest from './AppSettings.test';

/**
 * 测试入口（hvigor 单测索引固定引用本文件，业务套件在此聚合注册）。
 * - BaselineSmoke：框架冒烟
 * - SaveStateMachine / FileRevision / DraftDecision / SaveScheduler / SaveCoordinator：M0-04/M4-01 保存恢复领域层
 * - RecentFileList / FileNameValidator / TextEncoding / AdapterContract：M1 领域层
 * - MarkdownCommands / FindReplaceEngine / HeadingOutline / HtmlSafety：M2/M3 领域层
 * 注：每个套件都必须在此注册，否则 hvigor 单测不会运行（M4-01 复核修复）。
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
  saveCoordinatorTest();
  markdownCommandsTest();
  findReplaceEngineTest();
  headingOutlineTest();
  htmlSafetyTest();
  appSettingsTest();
}