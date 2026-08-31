import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery } from '@kit.ArkUI';
import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-HOME';

/**
 * M5-01 正式首页（产品化）：最近文件 + 资料库 + 崩溃恢复入口。
 * 多端：MediaQuery 宽屏（≥840vp，平板横屏/PC 自由窗口）双栏，手机竖屏单栏。
 * 日志仅写入 hilog，不再占用界面（调试痕迹移出）。
 */
@Entry
@Component
struct HomePage {
  @State recent: RecentEntry[] = [];
  @State libraryFiles: string[] = [];
  @State draftCount: number = 0;
  @State pickingFile: boolean = false;
  @State isWide: boolean = false;
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private meta: MetadataStore = new MetadataStore(getContext(this) as common.UIAbilityContext);
  private fileSource: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private draftStore: DraftStore = new DraftStore(getContext(this) as common.UIAbilityContext);
  private media: mediaquery.MediaQueryListener | undefined = undefined;

  private note(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    this.media = mediaquery.matchMediaSync('(min-width: 840px)');
    this.media.on('change', (e: mediaquery.MediaQueryResult) => {
      this.isWide = e.matches;
    });
    this.isWide = this.media.matches;
    this.refresh();
    this.refreshRecovery();
  }

  aboutToDisappear(): void {
    if (this.media !== undefined) {
      this.media.off('change');
      this.media = undefined;
    }
  }

  /** 页面每次显示（含从编辑器返回）时刷新最近列表与恢复入口 */
  onPageShow(): void {
    if (this.media !== undefined) {
      this.isWide = this.media.matches;
    }
    this.refresh();
    this.refreshRecovery();
  }

  /** M4-04 恢复入口：存在未处理检查点时提示 */
  private async refreshRecovery(): Promise<void> {
    try {
      this.draftCount = this.draftStore.listAll().length;
    } catch (e) {
      this.draftCount = 0;
    }
    if (this.draftCount > 0) {
      this.note(`[恢复] ${this.draftCount} 个检查点`);
    }
  }

  private goRecovery(): void {
    router.pushUrl({ url: 'pages/RecoveryPage' });
  }

  private async refresh(): Promise<void> {
    const entries = await this.meta.loadRecent();
    this.recent = new RecentFileList(entries).snapshot();
    this.note(`[最近] ${this.recent.length} 条`);
  }

  private async refreshLibrary(): Promise<void> {
    try {
      const names = this.fileSource.listLibrary();
      this.libraryFiles = names;
      this.note(`[资料库] ${names.length} 个文档`);
    } catch (e) {
      this.note(`[资料库] 读取失败：${JSON.stringify(e)}`);
    }
  }

  private goEditor(): void {
    router.pushUrl({ url: 'pages/EditorPage' });
  }

  /** 打开最近/资料库文档（name 参数 → EditorPage 读取并加载） */
  private goEditorWith(name: string): void {
    const params: ESObject = { name: name } as ESObject;
    router.pushUrl({ url: 'pages/EditorPage', params: params });
  }

  /** 「打开文件」：枚举资料库选择（离线内部库） */
  private openLibraryFile(): void {
    this.refreshLibrary().then(() => {
      this.pickingFile = true;
    });
  }

  private fmtTime(ms: number): string {
    const d = new Date(ms);
    const hh = `${d.getHours()}`.padStart(2, '0');
    const mm = `${d.getMinutes()}`.padStart(2, '0');
    return `${d.getMonth() + 1}/${d.getDate()} ${hh}:${mm}`;
  }

  /** 最近列表（单栏/双栏共用） */
  @Builder
  recentPanel() {
    Column({ space: 6 }) {
      Text('最近文件')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)

      if (this.recent.length === 0) {
        Column({ space: 4 }) {
          Text('还没有打开过文档')
            .fontSize(13)
            .fontColor('#99000000')
          Text('新建文档或打开文件后，最近使用的文档会显示在这里。正文保存在应用私有目录，完全离线可用。')
            .fontSize(12)
            .fontColor('#B0B0B0')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }

      List({ space: 6 }) {
        ForEach(this.recent, (item: RecentEntry) => {
          ListItem() {
            Row({ space: 10 }) {
              Text(item.pinned ? '📌' : '📄')
                .fontSize(15)
              Column({ space: 2 }) {
                Text(item.documentId)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                Text(this.fmtTime(item.lastOpenedAt))
                  .fontSize(11)
                  .fontColor('#99000000')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .width('100%')
            .backgroundColor('#F7F7F7')
            .borderRadius(10)
            .onClick(() => this.goEditorWith(item.documentId))
          }
        }, (item: RecentEntry) => item.documentId)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  sidePanel() {
    Column({ space: 10 }) {
      Text(`资料库 · ${this.libraryFiles.length} 个文档`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)

      if (this.libraryFiles.length === 0) {
        Text('保存的文档会出现在资料库中')
          .fontSize(12)
          .fontColor('#B0B0B0')
      } else {
        List({ space: 4 }) {
          ForEach(this.libraryFiles, (name: string) => {
            ListItem() {
              Text(`📄 ${name}`)
                .fontSize(13)
                .padding(6)
                .width('100%')
                .onClick(() => this.goEditorWith(name))
            }
          }, (name: string) => name)
        }
        .height(180)
        .width('100%')
        .scrollBar(BarState.Off)
      }

      if (this.draftCount > 0) {
        Button(`找回未保存内容（${this.draftCount}）`)
          .fontSize(13)
          .backgroundColor('#B26A00')
          .onClick(() => this.goRecovery())
      }

      Text('完全离线 · 应用私有目录存储')
        .fontSize(11)
        .fontColor('#B0B0B0')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor('#FBFBFB')
    .borderRadius(12)
  }

  build() {
    Column({ space: 12 }) {
      // 顶栏
      Row() {
        Text('Markdown 工作台')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('设置')
          .fontSize(13)
          .borderRadius(8)
          .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
      }
      .width('100%')

      // 主操作
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
        Button('＋ 新建文档')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .borderRadius(8)
          .onClick(() => this.goEditor())
        Button('打开文件')
          .fontSize(14)
          .borderRadius(8)
          .onClick(() => this.openLibraryFile())
        Button('刷新')
          .fontSize(13)
          .borderRadius(8)
          .backgroundColor('#33000000')
          .onClick(() => {
            this.refresh();
            this.refreshLibrary();
          })
      }
      .width('100%')

      if (this.pickingFile) {
        Column({ space: 4 }) {
          Text(`选择资料库文档（${this.libraryFiles.length}）`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
          Scroll() {
            Column({ space: 2 }) {
              ForEach(this.libraryFiles, (name: string) => {
                Text(`📄 ${name}`)
                  .fontSize(13)
                  .width('100%')
                  .padding(6)
                  .onClick(() => {
                    this.pickingFile = false;
                    this.goEditorWith(name);
                  })
              }, (name: string) => name)
            }
            .width('100%')
          }
          .height(160)
          .width('100%')
          Button('取消')
            .fontSize(12)
            .borderRadius(8)
            .onClick(() => { this.pickingFile = false; })
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)
      }

      // 多端布局：宽屏（平板横屏/PC 自由窗口）双栏，手机竖屏单栏
      if (this.isWide) {
        Row({ space: 12 }) {
          Column() {
            this.recentPanel()
          }
          .layoutWeight(2)

          Column() {
            this.sidePanel()
          }
          .layoutWeight(1)
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        Column({ space: 10 }) {
          this.recentPanel()
          Divider()
          this.sidePanel()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}