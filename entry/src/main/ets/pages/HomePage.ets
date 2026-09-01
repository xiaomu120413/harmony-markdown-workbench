import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery } from '@kit.ArkUI';
import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { AppTheme } from '../common/AppTheme';
import { Breakpoint, watchBreakpoints, unwatchBreakpoints, bpOf } from '../common/Breakpoints';

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
    this.bp = bpOf();
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

  /** 页面每次显示（含从编辑器返回、自由窗口 resize）时刷新 */
  onPageShow(): void {
    this.bp = bpOf();
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

  /** 主操作行（极简文字按钮，非大卡片） */
  @Builder
  actionCards() {
    Row({ space: 20 }) {
      Text('＋ 新建文档')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.PRIMARY)
        .onClick(() => this.goEditor())
      Text('打开文件')
        .fontSize(16)
        .fontColor(AppTheme.TEXT_SUB)
        .onClick(() => this.openLibraryFile())
      Blank()
      Button('刷新')
        .fontSize(12)
        .backgroundColor(AppTheme.TOOLBAR_BG)
        .fontColor(AppTheme.TEXT_SUB)
        .borderRadius(6)
        .height(32)
        .onClick(() => {
          this.refresh();
          this.refreshLibrary();
        })
    }
    .width('100%')
    .height(48)
  }

  /** 最近文件列表（极简线条行，无卡片/阴影） */
  @Builder
  recentPanel() {
    Column({ space: 0 }) {
      Row() {
        Text('最近')
          .fontSize(14)
          .fontColor(AppTheme.TEXT_SUB)
        Blank()
        if (this.recent.length > 0) {
          Text(`${this.recent.length} 个文档`)
            .fontSize(12)
            .fontColor(AppTheme.TEXT_FAINT)
        }
      }
      .width('100%')
      .height(40)

      if (this.recent.length === 0) {
        Column({ space: 6 }) {
          Text('还没有打开过文档')
            .fontSize(15)
            .fontColor(AppTheme.TEXT_SUB)
          Text('新建文档或打开文件后，最近使用的文档会显示在这里。')
            .fontSize(12)
            .fontColor(AppTheme.TEXT_FAINT)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ top: 40, bottom: 40 })
      }

      List({ space: 0 }) {
        ForEach(this.recent, (item: RecentEntry) => {
          ListItem() {
            Column({ space: 4 }) {
              Text(item.documentId)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.TEXT)
                .maxLines(1)
              Text(this.fmtTime(item.lastOpenedAt))
                .fontSize(11)
                .fontColor(AppTheme.TEXT_FAINT)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 16, bottom: 16, left: 0, right: 0 })
            .border({ width: { bottom: 1 }, color: AppTheme.DIVIDER })
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

  /** 资料库/恢复侧栏（极简） */
  @Builder
  sidePanel() {
    Column({ space: 12 }) {
      Text(`资料库`)
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
      Text(`${this.libraryFiles.length} 个文档`)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT)

      if (this.draftCount > 0) {
        Text(`找回未保存内容（${this.draftCount}）`)
          .fontSize(13)
          .fontColor(AppTheme.AMBER)
          .onClick(() => this.goRecovery())
      }

      Divider().color(AppTheme.DIVIDER).margin({ top: 8, bottom: 8 })

      Text('完全离线 · 应用私有目录')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_FAINT)
      Text('不联网 · 不上传 · 不跟踪')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_FAINT)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(20)
  }

  /** 信息卡（pc 档第三列） */
  @Builder
  infoPanel() {
    Column({ space: 10 }) {
      Text('关于')
        .fontSize(14)
        .fontColor(AppTheme.TEXT_SUB)
      Text('Markdown 工作台')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      Text('V0.1')
        .fontSize(13)
        .fontColor(AppTheme.TEXT_FAINT)
      Divider().color(AppTheme.DIVIDER).margin({ top: 8, bottom: 8 })
      Text('打开的是原文件，保存后仍是原文件。')
        .fontSize(13)
        .fontColor(AppTheme.TEXT_SUB)
        .lineHeight(20)
      Text('自动保存 1.5 秒防抖落盘；外部修改进入冲突保护；崩溃后草稿可恢复。')
        .fontSize(12)
        .fontColor(AppTheme.TEXT_FAINT)
        .lineHeight(18)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(20)
  }

  build() {
    Column({ space: 16 }) {
      // 顶栏（极简）
      Row() {
        Text('Markdown 工作台')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.TEXT)
        Blank()
        Text('设置')
          .fontSize(14)
          .fontColor(AppTheme.TEXT_SUB)
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

      // 断点布局：phone 单栏 + 底部 Tab Bar；tablet 双栏；pc 三栏 + 限宽居中
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
        // Phone：内容区 + 底部 Tab Bar（产品级导航）
        Column({ space: 0 }) {
          Column() {
            this.recentPanel()
          }
          .layoutWeight(1)
          .width('100%')

          // 底部 Tab Bar（自定义 Flex，3 个 tab：首页/编辑/我的）
          Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceAround, alignItems: ItemAlign.Center }) {
            Column({ space: 2 }) {
              Text('🏠').fontSize(20)
              Text('首页').fontSize(10).fontColor(AppTheme.PRIMARY)
            }
            .justifyContent(FlexAlign.Center)
            .onClick(() => {})
            .layoutWeight(1)
            .height(56)

            Column({ space: 2 }) {
              Text('✏️').fontSize(20)
              Text('编辑').fontSize(10).fontColor(AppTheme.TEXT_FAINT)
            }
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.goEditor())
            .layoutWeight(1)
            .height(56)

            Column({ space: 2 }) {
              Text('⚙').fontSize(20)
              Text('我的').fontSize(10).fontColor(AppTheme.TEXT_FAINT)
            }
            .justifyContent(FlexAlign.Center)
            .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
            .layoutWeight(1)
            .height(56)
          }
          .width('100%')
          .height(56)
          .backgroundColor('#FFFFFF')
          .border({ width: { top: 1 }, color: AppTheme.DIVIDER })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .padding(this.bp === 'phone' ? { left: 20, right: 20, top: 20, bottom: 0 } : 24)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
    .alignItems(HorizontalAlign.Start)
  }
}