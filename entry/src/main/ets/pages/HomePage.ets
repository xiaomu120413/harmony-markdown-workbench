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
 * 首页（V0.4：对齐系统原生「色调分层」——参考系统备忘录真机提取）。
 * 宽屏三区：侧栏（导航，#EEEFF1）→ 最近列表（#F2F3F5，细分隔线行）→
 * 欢迎内容（#FFFFFF）。面板无边框无圆角，靠色调分层；phone 单栏。
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
  }

  private goRecovery(): void {
    router.pushUrl({ url: 'pages/RecoveryPage' });
  }

  private goSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
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

  /** 打开最近/资料库文档（name=内部相对路径） */
  private goEditorWith(name: string): void {
    const params: ESObject = { name: name } as ESObject;
    router.pushUrl({ url: 'pages/EditorPage', params: params });
  }

  /** 外部文档（URI）：EditorPage 经 ExternalUriFileSource 读写（M0-02 实测链路） */
  private goEditorWithUri(uri: string): void {
    const params: ESObject = { uri: uri } as ESObject;
    router.pushUrl({ url: 'pages/EditorPage', params: params });
  }

  private openRecent(item: RecentEntry): void {
    // 外部 URI 记录走 uri 通道（临时授权可能已失效，EditorPage 有失败路径）
    if (item.documentId.startsWith('library/')) {
      this.goEditorWith(item.documentId);
    } else {
      this.goEditorWithUri(item.documentId);
    }
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
   * 授权为单次临时（API 26 无持久授权，R-10/ADR-009）。
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

  // ---- 设计构件（备忘录式：平铺行、细分隔线、无描边） ----

  /** 侧栏导航行（备忘录式纯文字行） */
  @Builder
  navRow(label: string, action: () => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(15)
        .fontColor(this.pal.TEXT)
        .layoutWeight(1)
      Text('›')
        .fontSize(16)
        .fontColor(this.pal.TEXT_FAINT)
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 12 })
    .borderRadius(10)
    .onClick(() => action())
  }

  /** 最近文档行（列表区行 + 细分隔线） */
  @Builder
  recentRow(item: RecentEntry) {
    Column({ space: 3 }) {
      Text(RecentFileList.displayName(item.documentId))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.fmtTime(item.lastOpenedAt))
        .fontSize(11)
        .fontColor(this.pal.TEXT_FAINT)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 11, bottom: 11, left: 20, right: 16 })
    .border({ width: { bottom: 1 }, color: this.pal.DIVIDER })
    .onClick(() => this.openRecent(item))
  }

  /** 资料库选择面板 */
  @Builder
  libraryPanel() {
    Column({ space: 6 }) {
      Row() {
        Text(`资料库 · ${this.libraryFiles.length} 个文档`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.TEXT)
          .layoutWeight(1)
        Text('✕')
          .fontSize(14)
          .fontColor(this.pal.TEXT_SUB)
          .onClick(() => { this.pickingFile = false; })
      }
      .width('100%')

      if (this.libraryFiles.length === 0) {
        Text('资料库还没有文档，先新建一个吧。')
          .fontSize(13)
          .fontColor(this.pal.TEXT_FAINT)
          .padding(8)
      }
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.libraryFiles, (name: string) => {
            Row({ space: 10 }) {
              Text(name)
                .fontSize(14)
                .fontColor(this.pal.TEXT)
                .maxLines(1)
                .layoutWeight(1)
              Text('›').fontSize(16).fontColor(this.pal.TEXT_FAINT)
            }
            .width('100%')
            .height(42)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.pickingFile = false;
              this.goEditorWith(name);
            })
          }, (name: string) => name)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 260 })
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal.CONTENT)
    .borderRadius(12)
  }

  /** 主按钮（HarmonyOS 胶囊样式） */
  @Builder
  primaryBtn(label: string, action: () => void) {
    Button(label)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.pal.ON_PRIMARY)
      .backgroundColor(this.pal.PRIMARY)
      .borderRadius(22)
      .width('100%')
      .height(44)
      .onClick(() => action())
  }

  /** 侧栏（宽屏）：品牌 / 主操作 / 导航 / 最近 */
  @Builder
  sideBar() {
    Column({ space: 2 }) {
      Text('Markdown 工作台')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.TEXT)
        .maxLines(1)
        .padding({ top: 6, bottom: 2 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            beginWindowMove(this.ctx);
          }
        })
      Text('完全离线 · 只在你本机')
        .fontSize(11)
        .fontColor(this.pal.TEXT_FAINT)
        .padding({ bottom: 10 })

      this.primaryBtn('＋  新建文档', () => this.goEditor())

      Column({ space: 0 }) {
        this.navRow('打开文档', () => this.openExternalFile())
        this.navRow('资料库', () => this.openLibraryFile())
        if (this.draftCount > 0) {
          this.navRow(`找回未保存内容（${this.draftCount}）`, () => this.goRecovery())
        }
        this.navRow('设置', () => this.goSettings())
      }
      .width('100%')
      .margin({ top: 6 })

      Row() {
        Text('最近')
          .fontSize(12)
          .fontColor(this.pal.TEXT_SUB)
        Blank()
        if (this.recent.length > 0) {
          Text(`${this.recent.length}`)
            .fontSize(12)
            .fontColor(this.pal.TEXT_FAINT)
        }
      }
      .width('100%')
      .padding({ top: 14, bottom: 4, left: 14, right: 12 })
    }
    .width(250)
    .height('100%')
    .padding({ left: 8, right: 8, top: 10, bottom: 10 })
    .backgroundColor(this.pal.SIDEBAR)
    .alignItems(HorizontalAlign.Start)
  }

  /** 最近列表区（宽屏中栏） */
  @Builder
  recentColumn() {
    Column({ space: 0 }) {
      Row() {
        Text('最近')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.TEXT)
          .layoutWeight(1)
        if (this.recent.length > 0) {
          Text(`${this.recent.length} 个文档`)
            .fontSize(12)
            .fontColor(this.pal.TEXT_FAINT)
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 16 })

      if (this.recent.length === 0) {
        Text('打开过的文档会出现在这里')
          .fontSize(13)
          .fontColor(this.pal.TEXT_FAINT)
          .padding({ top: 16, left: 20 })
      }

      List({ space: 0 }) {
        ForEach(this.recent, (item: RecentEntry) => {
          ListItem() {
            this.recentRow(item)
          }
        }, (item: RecentEntry) => item.documentId)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width(300)
    .height('100%')
    .backgroundColor(this.pal.BG)
    .alignItems(HorizontalAlign.Start)
  }

  /** 欢迎内容区（宽屏右栏） */
  @Builder
  welcomePanel() {
    Column({ space: 14 }) {
      Blank().layoutWeight(1)

      Column({ space: 8 }) {
        Text('Markdown 工作台')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.pal.TEXT)
        Text('打开的是原文件，保存后仍是原文件。')
          .fontSize(14)
          .fontColor(this.pal.TEXT_SUB)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: 12 }) {
        this.entryTile('＋', '新建文档', '从空白文档开始', () => this.goEditor())
        this.entryTile('⇪', '打开文档', '系统文件 .md / .txt', () => this.openExternalFile())
        this.entryTile('▤', '资料库', `${this.libraryFiles.length} 个本地文档`, () => this.openLibraryFile())
      }
      .width('100%')
      .height(130)

      if (this.pickingFile) {
        this.libraryPanel()
      }

      Blank().layoutWeight(1)

      Row() {
        Text('修改自动保存 · 意外退出可找回')
          .fontSize(12)
          .fontColor(this.pal.TEXT_FAINT)
        Blank()
        Text('1.0')
          .fontSize(12)
          .fontColor(this.pal.TEXT_FAINT)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .height('100%')
    .padding(24)
    .backgroundColor(this.pal.CONTENT)
    .alignItems(HorizontalAlign.Start)
  }

  /** 入口瓷贴（浅色调块，无描边） */
  @Builder
  entryTile(badge: string, title: string, sub: string, action: () => void) {
    Column({ space: 6 }) {
      Text(badge)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.PRIMARY)
        .width(34)
        .height(34)
        .lineHeight(34)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.pal.PRIMARY_SOFT)
        .borderRadius(10)
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.TEXT)
      Text(sub)
        .fontSize(11)
        .fontColor(this.pal.TEXT_FAINT)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .height('100%')
    .padding(14)
    .backgroundColor(this.pal.CARD)
    .borderRadius(12)
    .onClick(() => action())
  }

  /** phone：单栏（列表色调背景 + 平铺行） */
  @Builder
  phoneHome() {
    Column({ space: 10 }) {
      Text('Markdown 工作台')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.TEXT)
        .padding({ top: 4, bottom: 2 })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            beginWindowMove(this.ctx);
          }
        })

      this.primaryBtn('＋  新建文档', () => this.goEditor())

      Row({ space: 10 }) {
        Button('打开文档')
          .fontSize(14)
          .fontColor(this.pal.TEXT)
          .backgroundColor(this.pal.CONTENT)
          .borderRadius(20)
          .height(38)
          .layoutWeight(1)
          .onClick(() => this.openExternalFile())
        Button('资料库')
          .fontSize(14)
          .fontColor(this.pal.TEXT)
          .backgroundColor(this.pal.CONTENT)
          .borderRadius(20)
          .height(38)
          .layoutWeight(1)
          .onClick(() => this.openLibraryFile())
      }
      .width('100%')

      if (this.draftCount > 0) {
        Text(`⚠ 找回未保存内容（${this.draftCount}）`)
          .fontSize(13)
          .fontColor(this.pal.AMBER)
          .width('100%')
          .padding({ top: 8, bottom: 8, left: 14, right: 14 })
          .backgroundColor(this.pal.AMBER_SOFT)
          .borderRadius(10)
          .onClick(() => this.goRecovery())
      }

      if (this.pickingFile) {
        this.libraryPanel()
      }

      Row() {
        Text('最近')
          .fontSize(13)
          .fontColor(this.pal.TEXT_SUB)
        Blank()
        if (this.recent.length > 0) {
          Text(`${this.recent.length} 个文档`)
            .fontSize(12)
            .fontColor(this.pal.TEXT_FAINT)
        }
      }
      .width('100%')
      .padding({ top: 2 })

      List({ space: 0 }) {
        ForEach(this.recent, (item: RecentEntry) => {
          ListItem() {
            this.recentRow(item)
          }
        }, (item: RecentEntry) => item.documentId)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 14, right: 14, top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  /** phone：底部 Tab */
  @Builder
  phoneTab(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(active ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(active ? this.pal.PRIMARY : this.pal.TEXT_FAINT)
      .textAlign(TextAlign.Center)
      .width('100%')
      .lineHeight(52)
      .onClick(() => action())
      .layoutWeight(1)
      .height(52)
  }

  build() {
    Column() {
      if (this.bp === 'phone') {
        this.phoneHome()
        Row() {
          this.phoneTab('首页', true, () => {})
          this.phoneTab('编辑', false, () => this.goEditor())
          this.phoneTab('设置', false, () => this.goSettings())
        }
        .width('100%')
        .height(52)
        .backgroundColor(this.pal.CONTENT)
        .border({ width: { top: 1 }, color: this.pal.DIVIDER })
      } else {
        Row({ space: 0 }) {
          this.sideBar()
          Divider().vertical(true).height('100%').color(this.pal.DIVIDER)
          this.recentColumn()
          Divider().vertical(true).height('100%').color(this.pal.DIVIDER)
          this.welcomePanel()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.BG)
  }
}
