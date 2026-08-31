import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { FileNameValidator } from '../domain/document/FileNameValidator';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SPIKE-LIB';
const DIR_NAME: string = 'library';
const TRASH_NAME: string = '.trash';

/**
 * M1-03 尖峰：内部资料库（FR-FILE-001）验证页。
 * 验证：新建/重命名/软删除/恢复，FileNameValidator 集成（非法名/目录穿越拒绝），重名冲突。
 */
@Entry
@Component
struct SpikeLibraryPage {
  @State log: string = '';
  @State summary: string = '';
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  private dir(): string {
    return `${this.ctx.filesDir}/${DIR_NAME}`;
  }

  private trashDir(): string {
    return `${this.dir()}/${TRASH_NAME}`;
  }

  private docPath(name: string): string {
    return `${this.dir()}/${name}`;
  }

  private ensureDirs(): void {
    try {
      fs.mkdirSync(this.dir());
    } catch (e) {
      // exists tolerated
    }
    try {
      fs.mkdirSync(this.trashDir());
    } catch (e) {
      // exists tolerated
    }
  }

  private listDocs(): string[] {
    const names: string[] = [];
    try {
      const all = fs.listFileSync(this.dir());
      for (let i = 0; i < all.length; i++) {
        const n = all[i];
        if (n !== TRASH_NAME && !n.startsWith('.')) {
          names.push(n);
        }
      }
    } catch (e) {
      // dir missing → empty
    }
    return names;
  }

  private listTrash(): string[] {
    const names: string[] = [];
    try {
      names.push(...fs.listFileSync(this.trashDir()));
    } catch (e) {
      // empty
    }
    return names;
  }

  private refresh(): void {
    const docs = this.listDocs();
    const trash = this.listTrash();
    this.summary = `文档=${docs.length} 回收站=${trash.length}`;
  }

  private validateOrLog(name: string): boolean {
    const err = FileNameValidator.validate(name);
    if (err !== undefined) {
      this.append(`[校验拒绝] "${name}" → ${err}`);
      return false;
    }
    return true;
  }

  /** ① 新建文档 */
  createDoc(name: string): void {
    if (!this.validateOrLog(name)) {
      return;
    }
    this.ensureDirs();
    try {
      const fd = fs.openSync(this.docPath(name), fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      fs.closeSync(fd.fd);
      this.append(`[新建] ${name}`);
    } catch (e) {
      this.append(`[新建] 失败：${JSON.stringify(e)}`);
    }
    this.refresh();
  }

  /** ② 非法文件名校验测试 */
  testInvalidNames(): void {
    this.validateOrLog('../evil.md');
    this.validateOrLog('a/b.md');
    this.validateOrLog('.hidden.md');
    this.validateOrLog('bad\u0000name');
    this.validateOrLog('');
  }

  /** ③ 重命名（含重名冲突拒绝） */
  renameDoc(oldName: string, newName: string): void {
    if (!this.validateOrLog(newName)) {
      return;
    }
    this.ensureDirs();
    try {
      fs.renameSync(this.docPath(oldName), this.docPath(newName));
      this.append(`[重命名] ${oldName} → ${newName}`);
    } catch (e) {
      this.append(`[重命名] 失败（可能重名/不存在）：${JSON.stringify(e)}`);
    }
    this.refresh();
  }

  /** ④ 软删除（移入回收站） */
  softDelete(name: string): void {
    this.ensureDirs();
    try {
      fs.renameSync(this.docPath(name), `${this.trashDir()}/${name}`);
      this.append(`[软删除] ${name} → 回收站`);
    } catch (e) {
      this.append(`[软删除] 失败：${JSON.stringify(e)}`);
    }
    this.refresh();
  }

  /** ⑤ 恢复（回收站移回；重名时自动改名避免覆盖） */
  restore(name: string, newName?: string): void {
    this.ensureDirs();
    try {
      const target = newName !== undefined ? newName : name;
      const path = this.docPath(target);
      // 目标已存在 → 自动改名（不覆盖，FR-FILE-001 验收）
      let finalName = target;
      let idx = 1;
      while (fs.accessSync(path) === true) {
        finalName = `${target}-restored-${idx}`;
        idx++;
        try { fs.accessSync(this.docPath(finalName)); } catch (e) { break; }
      }
      fs.renameSync(`${this.trashDir()}/${name}`, this.docPath(finalName));
      this.append(`[恢复] ${name} → ${finalName}`);
    } catch (e) {
      this.append(`[恢复] 失败：${JSON.stringify(e)}`);
    }
    this.refresh();
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

      Text('M1-03 内部资料库')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Row({ space: 8 }) {
        Button('新建A')
          .fontSize(13)
          .onClick(() => this.createDoc('doc-a.md'))
        Button('新建B')
          .fontSize(13)
          .onClick(() => this.createDoc('doc-b.md'))
        Button('新建C')
          .fontSize(13)
          .onClick(() => this.createDoc('doc-c.md'))
        Button('非法名测试')
          .fontSize(13)
          .onClick(() => this.testInvalidNames())
      }
      Row({ space: 8 }) {
        Button('A→A2')
          .fontSize(13)
          .onClick(() => this.renameDoc('doc-a.md', 'doc-a2.md'))
        Button('C→A2(重名)')
          .fontSize(13)
          .onClick(() => this.renameDoc('doc-c.md', 'doc-a2.md'))
        Button('软删A2')
          .fontSize(13)
          .onClick(() => this.softDelete('doc-a2.md'))
        Button('恢复A2')
          .fontSize(13)
          .onClick(() => this.restore('doc-a2.md'))
      }
      .width('100%')

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