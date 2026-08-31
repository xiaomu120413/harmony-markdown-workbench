import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import {
  DocumentSource,
  FileRevisionContract,
  WriteOkResult,
  WriteFailResult,
} from '../domain/document/DocumentFileAdapter';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { ExternalUriFileSource } from '../infrastructure/file/ExternalUriFileSource';
import { HashUtil } from '../domain/document/HashUtil';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SPIKE-CONTRACT';
const DIR_NAME: string = 'spike-contract';

/**
 * M1-01 尖峰：真实适配器契约测试页（SDD 15.2——同一套契约用例，
 * 在内存实现（单测）与真实适配器（本页）上分别执行）。
 */
@Entry
@Component
struct SpikeContractPage {
  @State log: string = '';
  @State summary: string = '未运行';
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private internal: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private external: ExternalUriFileSource = new ExternalUriFileSource();
  private pass: number = 0;
  private fail: number = 0;

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  private report(name: string, ok: boolean, detail: string): void {
    if (ok) {
      this.pass++;
      this.append(`[PASS] ${name} ${detail}`);
    } else {
      this.fail++;
      this.append(`[FAIL] ${name} ${detail}`);
    }
  }

  private async runContract(): Promise<void> {
    this.pass = 0;
    this.fail = 0;
    const relPath = 'contract.md';
    const source: DocumentSource = { kind: 'internal', relativePath: `${DIR_NAME}/${relPath}` };
    const emptyRev: FileRevisionContract = { size: 0, contentHash: '' };

    // 先清理旧文件，保证从干净状态开始
    try {
      fs.unlinkSync(`${this.ctx.filesDir}/${DIR_NAME}/${relPath}`);
    } catch (e) {
      // 不存在则忽略
    }
    try {
      // 用例 1：读写一致
      const w1 = await this.internal.write(source, '契约测试内容', emptyRev);
      if ((w1 as WriteOkResult).ok) {
        const r = await this.internal.read(source);
        this.report('roundtrip_write_read', r.content === '契约测试内容', `read=${r.content}`);
      } else {
        this.report('roundtrip_write_read', false, `write failed ${(w1 as WriteFailResult).message}`);
      }

      // 用例 2：空文件
      const wEmpty = await this.internal.write(source, '', (w1 as WriteOkResult).ok ? (w1 as WriteOkResult).revision : emptyRev);
      const wEmptyOk = (wEmpty as WriteOkResult).ok;
      this.append(`[调试] empty write ok=${wEmptyOk} ${wEmptyOk ? '' : JSON.stringify((wEmpty as WriteFailResult).reason + ':' + (wEmpty as WriteFailResult).message)}`);
      const rEmpty = await this.internal.read(source);
      this.report('empty_file', rEmpty.content === '' && rEmpty.revision.size === 0, `size=${rEmpty.revision.size}`);

      // 用例 3：基线冲突（用过期基线写 → conflict + 原内容保留）
      // 先以当前磁盘基线写入 v1（空文件 revision 来自 rEmpty）
      const wV1 = await this.internal.write(source, 'v1', rEmpty.revision);
      this.append(`[调试] v1 write ok=${(wV1 as WriteOkResult).ok}`);
      const wConflict = await this.internal.write(source, 'v2', emptyRev);
      const conflictOk = (wConflict as WriteOkResult).ok;
      this.report('revision_conflict', !conflictOk && (wConflict as WriteFailResult).reason === 'conflict',
        conflictOk ? 'unexpected ok' : `reason=${(wConflict as WriteFailResult).reason}`);
      const rAfterConflict = await this.internal.read(source);
      this.report('conflict_preserves_disk', rAfterConflict.content === 'v1', `disk=${rAfterConflict.content}`);

      // 用例 4：正确基线覆盖写
      const wV2 = await this.internal.write(source, 'v2', (wV1 as WriteOkResult).ok ? (wV1 as WriteOkResult).revision : emptyRev);
      const v2Ok = (wV2 as WriteOkResult).ok;
      this.report('overwrite_with_new_revision', v2Ok, v2Ok ? 'ok' : (wV2 as WriteFailResult).message);
      const rV2 = await this.internal.read(source);
      this.report('overwrite_content', rV2.content === 'v2', `disk=${rV2.content}`);
      this.report('hash_stable', HashUtil.of('v2') === rV2.revision.contentHash, `hash=${rV2.revision.contentHash}`);

      // 用例 5：内部可持久化
      this.report('internal_persistable', await this.internal.canPersistAccess(source), '');

      // 用例 6：外部不可持久化（M0-02 结论）
      const ext: DocumentSource = { kind: 'external', uri: 'file://docs/x.md', displayName: 'x.md' };
      this.report('external_not_persistable', !(await this.external.canPersistAccess(ext)), '');

      // 用例 7：外部无效 URI 读取失败路径（安全错误）
      let threw = false;
      try {
        await this.external.read(ext);
      } catch (e) {
        threw = true;
      }
      this.report('external_missing_uri_throws', threw, '');

      // 清理
      try {
        fs.unlinkSync(`${this.ctx.filesDir}/${DIR_NAME}/${relPath}`);
      } catch (e) {
        // 清理失败不影响结论
      }
      this.summary = `PASS=${this.pass} FAIL=${this.fail}`;
      this.append(`[契约] 汇总：${this.summary}`);
    } catch (e) {
      this.append(`[契约] 运行异常：${JSON.stringify(e)}`);
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .onClick(() => router.back())
        Blank()
        Button('跑契约测试')
          .fontSize(14)
          .onClick(() => this.runContract())
      }
      .width('100%')

      Text('M1-01 适配器契约测试')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Text(`汇总：${this.summary}`)
        .fontSize(13)
        .fontColor('#99000000')

      Scroll() {
        Text(this.log)
          .fontSize(12)
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .padding(12)
    .width('100%')
    .height('100%')
  }
}