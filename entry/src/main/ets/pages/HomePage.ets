import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { SettingsStore } from '../infrastructure/metadata/SettingsStore';
import { ThemeMode } from '../domain/settings/AppSettings';
import { AppTheme } from '../common/AppTheme';
import { beginWindowMove } from '../common/WindowDrag';
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
  @State pal: AppTheme = AppTheme.light();
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private meta: MetadataStore = new MetadataStore(getContext(this) as common.UIAbilityContext);
  private fileSource: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private draftStore: DraftStore = new DraftStore(getContext(this) as common.UIAbilityContext);
  private settings: SettingsStore = new SettingsStore(getContext(this) as common.UIAbilityContext);
  private bpListeners: mediaquery.MediaQueryListener[] = [];

  private note(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    this.bp = bpOf();
    this.bpListeners = watchBreakpoints((bp: Breakpoint) => {
      this.bp = bp;
    });
    this.applyTheme();
    this.refresh();
    this.refreshRecovery();
    this.refreshLibrary();
  }

  aboutToDisappear(): void {
    unwatchBreakpoints(this.bpListeners);
    this.bpListeners = [];
  }

  /** 页面每次显示（含从编辑器/设置返回、自由窗口 resize）时刷新 + 重读主题 */
  onPageShow(): void {
    this.bp = bpOf();
    this.applyTheme();
    this.refresh();
    this.refreshRecovery();
    this.refreshLibrary();
  }

  /** 主题跟随设置（设置页切换后返回本页生效） */
  private applyTheme(): void {
    this.settings.load().then((s) => {
      this.pal = AppTheme.of(s.theme === ThemeMode.DARK);
    }).catch(() => {
    });
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

  /** 打开最近/资料库文档（name=内部相对路径 / uri=外部文档 URI） */
  private goEditorWith(name: string): void {
    const params: ESObject = { name: name } as ESObject;
    router.pushUrl({ url: 'pages/EditorPage', params: params });
  }

  /** 外部文档（URI）：EditorPage 经 ExternalUriFileSource 读写（M0-02 实测链路） */
  private goEditorWithUri(uri: string): void {
    const params: ESObject = { uri: uri } as ESObject;
    router.pushUrl({ url: 'pages/EditorPage', params: params });
  }

  /** 「资料库」：枚举内部库选择 */
  private openLibraryFile(): void {
    this.refreshLibrary().then(() => {
      this.pickingFile = true;
    });
  }

  /**
   * 「打开文档」：系统文件选择器（.md/.txt）→ 外部 URI 打开。
   * 产品原则主链路："打开的是原文件，保存后仍是原文件"。
   * 授权为单次临时（API 26 无持久授权，R-10/ADR-009）：本次会话内可读写，
   * 重启后需重新定位。
   */
  private async openExternalFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.ctx);
      const result: Array<string> = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.md', '.markdown', '.txt'],
      });
      if (result.length === 0) {
        return; // 用户取消
      }
      this.goEditorWithUri(result[0]);
    } catch (e) {
      this.note(`[打开] 选择器失败：${JSON.stringify(e)}`);
    }
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
        .fontColor(this.pal.PRIMARY)
        .onClick(() => this.goEditor())
      Text('打开文档')
        .fontSize(16)
        .fontColor(this.pal.TEXT_SUB)
        .onClick(() => this.openExternalFile())
      Text('资料库')
        .fontSize(16)
        .fontColor(this.pal.TEXT_SUB)
        .onClick(() => this.openLibraryFile())
      Blank()
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
          .fontColor(this.pal.TEXT_SUB)
        Blank()
        if (this.recent.length > 0) {
          Text(`${this.recent.length} 个文档`)
            .fontSize(12)
            .fontColor(this.pal.TEXT_FAINT)
        }
      }
      .width('100%')
      .height(40)

      if (this.recent.length === 0) {
        Column({ space: 6 }) {
          Text('还没有打开过文档')
            .fontSize(15)
            .fontColor(this.pal.TEXT_SUB)
          Text('新建文档或打开文件后，最近使用的文档会显示在这里。')
            .fontSize(12)
            .fontColor(this.pal.TEXT_FAINT)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ top: 40, bottom: 40 })
      }

      List({ space: 0 }) {
        ForEach(this.recent, (item: RecentEntry) => {
          ListItem() {
            Column({ space: 4 }) {
              Text(RecentFileList.displayName(item.documentId))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.pal.TEXT)
                .maxLines(1)
              Text(this.fmtTime(item.lastOpenedAt))
                .fontSize(11)
                .fontColor(this.pal.TEXT_FAINT)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 16, bottom: 16, left: 0, right: 0 })
            .border({ width: { bottom: 1 }, color: this.pal.DIVIDER })
            .onClick(() => {
              // 外部 URI 记录走 uri 通道（临时授权可能已失效，EditorPage 有失败路径）
              if (item.documentId.startsWith('library/')) {
                this.goEditorWith(item.documentId);
              } else {
                this.goEditorWithUri(item.documentId);
              }
            })
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
        .fontColor(this.pal.TEXT_SUB)
      Text(`${this.libraryFiles.length} 个文档`)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.TEXT)

      if (this.draftCount > 0) {
        Text(`找回未保存内容（${this.draftCount}）`)
          .fontSize(13)
          .fontColor(this.pal.AMBER)
          .onClick(() => this.goRecovery())
      }

      Divider().color(this.pal.DIVIDER).margin({ top: 8, bottom: 8 })

      Text('完全离线 · 应用私有目录')
        .fontSize(12)
        .fontColor(this.pal.TEXT_FAINT)
      Text('不联网 · 不上传 · 不跟踪')
        .fontSize(12)
        .fontColor(this.pal.TEXT_FAINT)
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
        .fontColor(this.pal.TEXT_SUB)
      Text('Markdown 工作台')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
      Text('1.0')
        .fontSize(13)
        .fontColor(this.pal.TEXT_FAINT)
      Divider().color(this.pal.DIVIDER).margin({ top: 8, bottom: 8 })
      Text('打开的是原文件，保存后仍是原文件。')
        .fontSize(13)
        .fontColor(this.pal.TEXT_SUB)
        .lineHeight(20)
      Text('内容只保存在本机；修改自动保存，意外退出可找回。')
        .fontSize(12)
        .fontColor(this.pal.TEXT_FAINT)
        .lineHeight(18)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(20)
  }

  build() {
    Column({ space: 16 }) {
      // 顶栏（极简；标题区为窗口拖动热区——系统标题栏已隐藏）
      Row() {
        Text('Markdown 工作台')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.TEXT)
          .padding({ top: 8, bottom: 8 })
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              beginWindowMove(this.ctx);
            }
          })
        Blank()
        Text('设置')
          .fontSize(14)
          .fontColor(this.pal.TEXT_SUB)
          .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
      }
      .width('100%')

      this.actionCards()

      // 打开文档选择面板
      if (this.pickingFile) {
        Column({ space: 4 }) {
          Text(`选择文档（${this.libraryFiles.length}）`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.TEXT)
          if (this.libraryFiles.length === 0) {
            Text('资料库还没有文档，先新建一个吧。')
              .fontSize(12)
              .fontColor(this.pal.TEXT_FAINT)
              .padding(12)
          }
          Scroll() {
            Column({ space: 2 }) {
              ForEach(this.libraryFiles, (name: string) => {
                Text(`📄 ${name}`)
                  .fontSize(13)
                  .fontColor(this.pal.TEXT)
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
        .backgroundColor(this.pal.TOOLBAR_BG)
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

          // 底部 Tab Bar（自定义 Flex，3 个 tab：首页/编辑/设置）
          Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceAround, alignItems: ItemAlign.Center }) {
            Column({ space: 2 }) {
              Text('🏠').fontSize(20)
              Text('首页').fontSize(10).fontColor(this.pal.PRIMARY)
            }
            .justifyContent(FlexAlign.Center)
            .onClick(() => {})
            .layoutWeight(1)
            .height(56)

            Column({ space: 2 }) {
              Text('✏️').fontSize(20)
              Text('编辑').fontSize(10).fontColor(this.pal.TEXT_FAINT)
            }
            .justifyContent(FlexAlign.Center)
            .onClick(() => this.goEditor())
            .layoutWeight(1)
            .height(56)

            Column({ space: 2 }) {
              Text('⚙').fontSize(20)
              Text('设置').fontSize(10).fontColor(this.pal.TEXT_FAINT)
            }
            .justifyContent(FlexAlign.Center)
            .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
            .layoutWeight(1)
            .height(56)
          }
          .width('100%')
          .height(56)
          .backgroundColor(this.pal.CARD)
          .border({ width: { top: 1 }, color: this.pal.DIVIDER })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .padding(this.bp === 'phone' ? { left: 20, right: 20, top: 20, bottom: 0 } : 24)
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.BG)
    .alignItems(HorizontalAlign.Start)
  }
}