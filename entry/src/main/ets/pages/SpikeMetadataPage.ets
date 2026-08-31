import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { RecentFileList } from '../domain/document/RecentFileList';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-SPIKE-META';

/**
 * M1-02 尖峰：元数据与最近文件基础设施验证页。
 * 验证：touch（打开文件）→ 持久化 preferences → 强杀重启 → 加载恢复；
 * 淘汰（35 条 → 30 条）与固定保护。
 */
@Entry
@Component
struct SpikeMetadataPage {
  @State log: string = '';
  @State summary: string = '未运行';
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private store: MetadataStore = new MetadataStore(getContext(this) as common.UIAbilityContext);
  private recent: RecentFileList = new RecentFileList();
  private openedId: string = '';

  private append(line: string): void {
    this.log = `${line}\n---\n${this.log}`;
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  private render(): void {
    const s = this.recent.snapshot();
    const pinned = s.filter((e) => e.pinned).length;
    this.summary = `总数=${s.length} 固定=${pinned}`;
    let preview = '';
    for (let i = 0; i < Math.min(5, s.length); i++) {
      preview += `${s[i].pinned ? '[钉] ' : ''}${s[i].documentId} @${s[i].lastOpenedAt}\n`;
    }
    this.append(`[列表] ${preview.trimEnd()}`);
  }

  /** ① 模拟打开文件（touch） */
  async touchDoc(): Promise<void> {
    const id = `doc-${Date.now() % 100000}`;
    this.openedId = id;
    this.recent.touch(id, Date.now());
    this.append(`[打开] ${id}`);
  }

  /** ② 固定当前文档 */
  async pinDoc(): Promise<void> {
    if (this.openedId.length === 0) {
      this.append('[固定] 请先打开文档');
      return;
    }
    this.recent.setPinned(this.openedId, true);
    this.append(`[固定] ${this.openedId}`);
  }

  /** ③ 填充 35 条（淘汰验证） */
  async fillMany(): Promise<void> {
    const now = Date.now();
    for (let i = 1; i <= 35; i++) {
      this.recent.touch(`batch-${i}`, now + i);
    }
    this.append('[填充] 35 条（固定项保护验证）');
  }

  /** ④ 保存到 preferences */
  async saveMeta(): Promise<void> {
    await this.store.saveRecent(this.recent.snapshot());
    this.append('[保存] 元数据已落盘');
  }

  /** ⑤ 从 preferences 重新加载 */
  async loadMeta(): Promise<void> {
    const entries = await this.store.loadRecent();
    this.recent = new RecentFileList(entries);
    this.append(`[加载] 恢复 ${entries.length} 条`);
    this.render();
  }

  /** ⑥ 清空 */
  async clearMeta(): Promise<void> {
    await this.store.saveRecent([]);
    this.recent = new RecentFileList();
    this.append('[清空] 完成');
  }

  async aboutToAppear(): Promise<void> {
    // 进入页面自动加载已有元数据（模拟启动恢复）
    const entries = await this.store.loadRecent();
    if (entries.length > 0) {
      this.recent = new RecentFileList(entries);
      this.append(`[启动恢复] 加载 ${entries.length} 条`);
      this.render();
    }
  }

  build() {
    Column({ space: 8 }) {
      Row() {
        Button('返回')
          .fontSize(14)
          .onClick(() => router.back())
        Blank()
        Button('跑流程①-⑤')
          .fontSize(13)
          .onClick(() => this.runAll())
      }
      .width('100%')

      Text('M1-02 元数据与最近文件')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)

      Row({ space: 8 }) {
        Button('① 打开文档')
          .fontSize(13)
          .onClick(() => this.touchDoc())
        Button('② 固定')
          .fontSize(13)
          .onClick(() => this.pinDoc())
        Button('③ 填35条')
          .fontSize(13)
          .onClick(() => this.fillMany())
        Button('④ 保存')
          .fontSize(13)
          .onClick(() => this.saveMeta())
      }
      Row({ space: 8 }) {
        Button('⑤ 加载')
          .fontSize(13)
          .onClick(() => this.loadMeta())
        Button('⑥ 清空')
          .fontSize(13)
          .onClick(() => this.clearMeta())
        Text(`汇总：${this.summary}`)
          .fontSize(12)
          .fontColor('#99000000')
      }
      .width('100%')

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

  /** 一次执行全流程（打开→固定→填充→保存） */
  async runAll(): Promise<void> {
    await this.touchDoc();
    await this.pinDoc();
    await this.fillMany();
    await this.saveMeta();
    this.render();
    this.append('[流程] 完成（重启后点⑤验证恢复与淘汰）');
  }
}