import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { SaveStateMachine, SaveState } from '../domain/recovery/SaveStateMachine';
import { DraftDecisionEvaluator, RecoveryDecision, RecoveryDraft } from '../domain/recovery/DraftDecision';
import { FileRevision } from '../domain/document/FileRevision';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SPIKE-SAVE';
const DIR_NAME: string = 'spike-save';
const DOC_NAME: string = 'spike-note.md';
const DRAFT_NAME: string = 'recovery.json';

/**
 * M0-04 尖峰：保存与恢复验证页（无正式 UI，验证后由 M4 正式实现替换）。
 * 验证目标（SDD M0-04）：
 *  1. 内部文件原子写（临时文件 + fsync + rename 替换）与读回一致；
 *  2. 外部 URI 写失败路径（无效/未授权 URI → ERROR 状态，正文保留）；
 *  3. 草稿检查点（应用私有目录）与强杀恢复（决策器输出 + 草稿预览）。
 */
@Entry
@Component
struct SpikeSavePage {
  @State log: string = '';
  @State docId: string = '';
  @State draftState: string = '未检查';
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private sm: SaveStateMachine = new SaveStateMachine();
  private editContent: string = '';

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  private baseDir(): string {
    return `${this.ctx.filesDir}/${DIR_NAME}`;
  }

  private docPath(): string {
    return `${this.baseDir()}/${DOC_NAME}`;
  }

  private draftPath(): string {
    return `${this.baseDir()}/${DRAFT_NAME}`;
  }

  private ensureDir(): void {
    try {
      fs.mkdirSync(this.baseDir());
    } catch (e) {
      const err: string = String(e);
      // 目录已存在（EEXIST）可容忍；其他错误通过 openSync 探测暴露
      if (!err.includes('exist')) {
        throw new Error(err);
      }
    }
  }

  /** 确保状态机处于 SAVING（失败路径的合法前置状态） */
  private enterSaving(): void {
    if (this.sm.state === SaveState.CLEAN) {
      this.sm.edit();
    }
    if (this.sm.state === SaveState.DIRTY) {
      this.sm.beginSave();
    }
  }

  /** ① 内部原子写：临时文件 → fsync → rename 替换目标 */
  atomicWrite(): void {
    try {
      this.ensureDir();
      const tmp = `${this.docPath()}.tmp`;
      const file = fs.openSync(tmp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      const content = this.editContent.length > 0 ? this.editContent : 'M0-04 原子写测试内容';
      this.editContent = content;
      fs.writeSync(file.fd, content);
      fs.fsyncSync(file.fd);
      fs.closeSync(file.fd);
      fs.renameSync(tmp, this.docPath());
      this.sm.edit();
      this.sm.beginSave();
      this.sm.saveSuccess();
      this.append(`[原子写] 完成（${content.length} 字节），状态=${SaveStateMachine.label(this.sm.state)}`);
    } catch (e) {
      this.enterSaving();
      this.sm.saveFailure();
      this.append(`[原子写] 失败：${JSON.stringify(e)}，状态=${SaveStateMachine.label(this.sm.state)}`);
    }
  }

  /** ② 读回验证 */
  readBack(): void {
    try {
      const text = fs.readTextSync(this.docPath());
      const stat = fs.statSync(this.docPath());
      this.docId = `size=${stat.size}`;
      const same: boolean = text === this.editContent;
      this.append(`[读回] 长度=${text.length}（${
        stat.size} 字节），与编辑内容一致=${same}${same ? '' : '（不一致！）'}`);
      this.append(`[读回] 前 100 字符：${text.substring(0, 100).replace(/\n/g, '⏎')}`);
    } catch (e) {
      this.append(`[读回] 失败：${JSON.stringify(e)}`);
    }
  }

  /** ③ 外部 URI 写失败路径：无效/未授权 URI → ERROR，正文（editContent）保留 */
  uriWriteFail(): void {
    // 走合法状态迁移：确保 SAVING；失败 → ERROR（正文保留，可重试）
    this.enterSaving();
    try {
      // 无效 URI 以只读方式探测（M0-02 实测：URI 授权失效时 openSync 抛 13900001；
      // 写模式打开无效 URI 存在 native 风险，用只读探测 + 状态机演示写失败路径）
      const file = fs.openSync('file://docs/not-authorized/x.md', fs.OpenMode.READ_ONLY);
      fs.closeSync(file.fd);
      this.append('[URI写] 意外成功（不应发生）');
      this.sm.saveSuccess();
    } catch (e) {
      const errorCode = JSON.stringify(e);
      this.sm.saveFailure();
      this.append(`[URI写] 失败（预期）：${errorCode}`);
      this.append(`[URI写] 状态=${SaveStateMachine.label(this.sm.state)}；编辑内容仍保留（${this.editContent.length} 字符）`);
    }
  }

  /** ④ 草稿检查点：编辑内容写入应用私有目录 */
  writeDraft(): void {
    try {
      this.ensureDir();
      const draftObj: RecoveryDraft = {
        documentId: 'spike-note',
        sourceFingerprint: 'internal:spike-note.md',
        baseRevision: { size: 0, contentHash: '' },
        content: this.editContent,
        updatedAt: Date.now(),
        appVersion: '0.1.0',
      };
      const draft = JSON.stringify(draftObj);
      const file = fs.openSync(this.draftPath(), fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, draft);
      fs.fsyncSync(file.fd);
      fs.closeSync(file.fd);
      this.draftState = '已写入';
      this.append(`[草稿] 检查点已写（${draft.length} 字节）`);
    } catch (e) {
      this.append(`[草稿] 写入失败：${JSON.stringify(e)}`);
    }
  }

  /** ⑤ 恢复检查：读草稿 + 磁盘 revision → 决策器 */
  recoveryCheck(): void {
    try {
      const raw = fs.readTextSync(this.draftPath());
      let draftObj: ESObject = JSON.parse(raw);
      const text = draftObj.content as string;
      const draft: RecoveryDraft = {
        documentId: draftObj.documentId as string,
        sourceFingerprint: draftObj.sourceFingerprint as string,
        baseRevision: { size: 0, contentHash: '' },
        content: text,
        updatedAt: draftObj.updatedAt as number,
        appVersion: draftObj.appVersion as string,
      };
      let diskRev: FileRevision | undefined;
      let diskText: string = '';
      try {
        const stat = fs.statSync(this.docPath());
        diskText = fs.readTextSync(this.docPath());
        diskRev = { size: stat.size, contentHash: `h${diskText.length}` };
      } catch (e) {
        const errMsg: string = String(e);
        diskRev = undefined;
        void errMsg;
      }
      const decision = DraftDecisionEvaluator.decide(draft, diskRev, `h${text.length}`);
      const dName = decision === RecoveryDecision.NO_DRAFT ? '无草稿' :
        decision === RecoveryDecision.DISCARD_REDUNDANT ? '冗余可清理' :
        decision === RecoveryDecision.RESTORE_DRAFT ? '恢复草稿' : '冲突（需用户决策）';
      this.draftState = dName;
      this.append(`[恢复] 决策=${dName}`);
      this.append(`[恢复] 草稿内容预览：${text.substring(0, 100).replace(/\n/g, '⏎')}`);
    } catch (e) {
      this.draftState = '无草稿';
      this.append(`[恢复] 无草稿或读取失败：${JSON.stringify(e)}`);
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .onClick(() => router.back())
        Blank()
      }
      .width('100%')

      Text('M0-04 保存恢复尖峰')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Row({ space: 8 }) {
        Button('① 原子写')
          .fontSize(13)
          .onClick(() => this.atomicWrite())
        Button('② 读回')
          .fontSize(13)
          .onClick(() => this.readBack())
        Button('③ URI写失败')
          .fontSize(13)
          .onClick(() => this.uriWriteFail())
      }
      Row({ space: 8 }) {
        Button('④ 写草稿')
          .fontSize(13)
          .onClick(() => this.writeDraft())
        Button('⑤ 恢复检查')
          .fontSize(13)
          .onClick(() => this.recoveryCheck())
        Text('强杀验证：hdc kill -9 后重启本页再点⑤')
          .fontSize(11)
          .fontColor('#99000000')
      }
      .width('100%')

      Text(`文件：${this.docId || '（未写）'}   草稿：${this.draftState}`)
        .fontSize(12)
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