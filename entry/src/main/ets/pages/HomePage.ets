import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery } from '@kit.ArkUI';
import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { AppTheme } from '../common/AppTheme';
import { Breakpoint, watchBreakpoints, unwatchBreakpoints } from '../common/Breakpoints';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-HOME';

/**
 * 正式首页（产品化）：品牌顶栏 + 主操作卡片 + 最近列表（卡片行）。
 * 断点（common/Breakpoints）：phone 单栏；tablet 双栏；pc 三栏 + 内容限宽居中。
 * 日志仅 hilog；无调试痕迹。
 */
@Entry
@Component
struct HomePage {
  @State recent: RecentEntry[] = [];
  @State libraryFiles: string[] = [];
  @State draftCount: number = 0;
  @State pickingFile: boolean = false;
  @State bp: Breakpoint = 'phone';
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private meta: MetadataStore = new MetadataStore(getContext(this) as common.UIAbilityContext);
  private fileSource: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private draftStore: DraftStore = new DraftStore(getContext(this) as common.UIAbilityContext);
  private bpListeners: mediaquery.MediaQueryListener[] = [];

  private note(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    this.bpListeners = watchBreakpoints((bp: Breakpoint) => {
      this.bp = bp;
    });
    this.refresh();
    this.refreshRecovery();
    this.refreshLibrary();
  }

  aboutToDisappear(): void {
    unwatchBreakpoints(this.bpListeners);
    this.bpListeners = [];
  }

  /** 页面每次显示（含从编辑器返回）时刷新 */
  onPageShow(): void {
    this.refresh();
    this.refreshRecovery();
    this.refreshLibrary();
  }

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

  /** 主操作卡片（新建/打开） */
  @Builder
  actionCards() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      Column({ space: 6 }) {
        Text('＋')
          .fontSize(26)
          .fontColor(AppTheme.ON_PRIMARY)
        Text('新建文档')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.ON_PRIMARY)
        Text('空白 Markdown，自动保存')
          .fontSize(11)
          .fontColor('#D9E6FF')
      }
      .width(150)
      .height(110)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppTheme.PRIMARY)
      .borderRadius(14)
      .onClick(() => this.goEditor())

      Column({ space: 6 }) {
        Text('📂')
          .fontSize(24)
        Text('打开文件')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
        Text('从资料库选择文档')
          .fontSize(11)
          .fontColor(AppTheme.TEXT_SUB)
      }
      .width(150)
      .height(110)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(AppTheme.CARD)
      .borderRadius(14)
      .border({ width: 1, color: AppTheme.DIVIDER })
      .onClick(() => this.openLibraryFile())
    }
    .width('100%')
  }

  /** 最近文件列表（卡片行） */
  @Builder
  recentPanel() {
    Column({ space: 8 }) {
      Row() {
        Text('最近')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
        Blank()
        if (this.recent.length > 0) {
          Text(`查看全部 · ${this.recent.length}`)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_SUB)
        }
      }
      .width('100%')

      if (this.recent.length === 0) {
        Column({ space: 6 }) {
          Text('还没有打开过文档')
            .fontSize(14)
            .fontColor(AppTheme.TEXT_SUB)
          Text('点击「新建文档」开始写作，正文保存在应用私有目录，完全离线可用。')
            .fontSize(12)
            .fontColor(AppTheme.TEXT_FAINT)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(16)
        .backgroundColor(AppTheme.CARD)
        .borderRadius(12)
      }

      List({ space: 8 }) {
        ForEach(this.recent, (item: RecentEntry) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(item.pinned ? '📌' : '📄')
                .fontSize(16)
              Column({ space: 3 }) {
                Text(item.documentId)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(AppTheme.TEXT)
                Text(this.fmtTime(item.lastOpenedAt))
                  .fontSize(11)
                  .fontColor(AppTheme.TEXT_SUB)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .width('100%')
            .backgroundColor(AppTheme.CARD)
            .borderRadius(12)
            .shadow(AppTheme.SHADOW)
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

  /** 资料库/恢复侧栏（宽屏右列；窄屏置于列表下方） */
  @Builder
  sidePanel() {
    Column({ space: 10 }) {
      Text(`资料库 · ${this.libraryFiles.length} 个文档`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)

      if (this.libraryFiles.length === 0) {
        Text('保存的文档会出现在这里')
          .fontSize(12)
          .fontColor(AppTheme.TEXT_FAINT)
      }

      if (this.draftCount > 0) {
        Button(`找回未保存内容（${this.draftCount}）`)
          .fontSize(13)
          .backgroundColor(AppTheme.AMBER)
          .borderRadius(8)
          .onClick(() => this.goRecovery())
      }

      Divider().color(AppTheme.DIVIDER)

      Text('完全离线\n正文仅存于应用私有目录，不联网、不上传。')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_SUB)
        .lineHeight(17)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(AppTheme.CARD)
    .borderRadius(12)
    .border({ width: 1, color: AppTheme.DIVIDER })
  }

  /** 信息卡（pc 档第三列） */
  @Builder
  infoPanel() {
    Column({ space: 10 }) {
      Text('关于')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
      Text('Markdown 工作台 V0.1')
        .fontSize(13)
      Text('正面打开的是原文件，保存后仍是原文件。')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_SUB)
        .lineHeight(18)
      Divider().color(AppTheme.DIVIDER)
      Text('离线优先：正文仅存于应用私有目录与草稿检查点，不联网、不上传。自动保存每秒检查，1.5 秒防抖落盘；外部修改会进入冲突保护。')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_FAINT)
        .lineHeight(17)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor(AppTheme.CARD)
    .borderRadius(12)
    .border({ width: 1, color: AppTheme.DIVIDER })
  }

  build() {
    Column({ space: 12 }) {
      // 顶栏
      Row() {
        Text('Markdown 工作台')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
        Blank()
        Button('⚙ 设置')
          .fontSize(13)
          .backgroundColor(AppTheme.TOOLBAR_BG)
          .fontColor(AppTheme.TEXT)
          .borderRadius(8)
          .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
      }
      .width('100%')

      this.actionCards()

      // 打开文件选择面板
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
                  .padding(8)
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
        .backgroundColor(AppTheme.TOOLBAR_BG)
        .borderRadius(10)
      }

      // 断点布局：phone 单栏；tablet 双栏（最近 | 资料库）；pc 三栏 + 限宽居中
      if (this.bp === 'pc') {
        Row({ space: 12 }) {
          Column() {
            this.recentPanel()
          }
          .layoutWeight(3)

          Column() {
            this.sidePanel()
            Blank().height(12)
            this.infoPanel()
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignSelf(ItemAlign.Center)
        .constraintSize({ maxWidth: 1280 })
        .layoutWeight(1)
      } else if (this.bp === 'tablet') {
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
          Column() {
            this.recentPanel()
          }
          .layoutWeight(1)
          .width('100%')

          this.sidePanel()
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .padding(20)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
    .alignItems(HorizontalAlign.Start)
  }
}