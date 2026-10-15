import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { RecentFileList, RecentEntry } from '../domain/document/RecentFileList';
import { LibrarySearch, DocSearchResult, LibraryDoc } from '../domain/document/LibrarySearch';
import { FindOptions } from '../domain/editor/FindReplaceEngine';
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
  @State renamingFrom: string = '';
  @State renameText: string = '';
  @State trashFiles: string[] = [];
  @State trashOpen: boolean = false;
  @State searchQuery: string = '';
  @State searchResults: DocSearchResult[] = [];
  @State searchBusy: boolean = false;
  private searchTimer: number = -1;
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
      this.trashFiles = this.fileSource.listTrash();
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

  /** 资料库行操作菜单（V0.4.2 库管理） */
  private libraryRowMenu(name: string): void {
    const that = this;
    promptAction.showActionMenu({
      title: name,
      buttons: [
        { text: '重命名', color: that.pal.TEXT },
        { text: '删除（移入回收站）', color: that.pal.DANGER },
      ],
    }).then((r: promptAction.ActionMenuSuccessResponse) => {
      if (r.index === 0) {
        that.renamingFrom = name;
        that.renameText = name;
      } else if (r.index === 1) {
        that.confirmDelete(name);
      }
    });
  }

  /** 重命名确认：补 .md 后缀、查重、最近列表同步 */
  private async confirmRename(): Promise<void> {
    const oldName = this.renamingFrom;
    let newName = this.renameText.trim();
    this.renamingFrom = '';
    if (oldName.length === 0 || newName.length === 0 || newName === oldName) {
      return;
    }
    if (!newName.endsWith('.md')) {
      newName = `${newName}.md`;
    }
    if (newName.indexOf('/') >= 0 || this.fileSource.listLibrary().indexOf(newName) !== -1) {
      promptAction.showToast({ message: '名称不可用或已存在' });
      return;
    }
    if (this.fileSource.renameLibrary(oldName, newName)) {
      try {
        const entries = await this.meta.loadRecent();
        const list = new RecentFileList(entries);
        list.remove(`library/${oldName}`);
        list.touch(`library/${newName}`, Date.now());
        await this.meta.saveRecent(list.snapshot());
      } catch (e) {
        // 元数据失败不阻塞文件操作
      }
      this.refresh();
      this.refreshLibrary();
      if (this.searchQuery.length > 0) {
        this.runSearch();
      }
      promptAction.showToast({ message: `已重命名为 ${newName}` });
    } else {
      promptAction.showToast({ message: '重命名失败' });
    }
  }

  /** 资料库全文搜索（V0.4.3）：查询词防抖 300ms → 读全部文档 → 领域匹配 */
  private scheduleSearch(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.runSearch();
    }, 300);
  }

  private async runSearch(): Promise<void> {
    const q = this.searchQuery.trim();
    if (q.length === 0) {
      this.searchResults = [];
      return;
    }
    this.searchBusy = true;
    try {
      const docs: LibraryDoc[] = [];
      const names = this.fileSource.listLibrary();
      for (const name of names) {
        try {
          const src: ESObject = { kind: 'internal', relativePath: `library/${name}` } as ESObject;
          const r = await this.fileSource.read(src);
          docs.push({ name: name, content: r.content });
        } catch (e) {
          // 单篇读取失败跳过
        }
      }
      const opts: FindOptions = { caseSensitive: false, wholeWord: false };
      this.searchResults = LibrarySearch.search(docs, q, opts);
    } finally {
      this.searchBusy = false;
    }
  }

  /** 回收站恢复（V0.4.4：兑现"回收站"承诺——可见、可恢复） */
  private restoreFromTrash(name: string): void {
    if (this.fileSource.restoreTrash(name)) {
      this.refreshLibrary();
      this.refresh();
      promptAction.showToast({ message: `已恢复 ${name}` });
    } else {
      promptAction.showToast({ message: '恢复失败（同名文档已存在？）' });
    }
  }

  /** 搜索结果行点击 → 打开对应文档 */
  private goEditorWithResult(name: string): void {
    this.goEditorWith(`library/${name}`);
  }

  /** 删除确认（移入 library/.trash，listLibrary 不再枚举） */
  private confirmDelete(name: string): void {
    const that = this;
    AlertDialog.show({
      title: '删除文档',
      message: `「${name}」将移入回收站（应用私有目录），确定删除？`,
      primaryButton: {
        value: '删除',
        fontColor: that.pal.DANGER,
        action: () => {
          that.doDelete(name);
        },
      },
      secondaryButton: {
        value: '取消',
        action: () => {
        },
      },
    });
  }

  private async doDelete(name: string): Promise<void> {
    if (this.fileSource.trashLibrary(name)) {
      try {
        const entries = await this.meta.loadRecent();
        const list = new RecentFileList(entries);
        list.remove(`library/${name}`);
        await this.meta.saveRecent(list.snapshot());
      } catch (e) {
        // 元数据失败不阻塞文件操作
      }
      this.refresh();
      this.refreshLibrary();
      if (this.searchQuery.length > 0) {
        this.runSearch();
      }
      promptAction.showToast({ message: `已删除 ${name}` });
    } else {
      promptAction.showToast({ message: '删除失败' });
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
        Text('资料库是空的')
          .fontSize(13)
          .fontColor(this.pal.TEXT_FAINT)
          .padding(8)
      }
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.libraryFiles, (name: string) => {
            if (this.renamingFrom === name) {
              Row({ space: 8 }) {
                TextInput({ text: this.renameText })
                  .fontSize(14)
                  .height(36)
                  .padding({ left: 8, right: 8 })
                  .backgroundColor(this.pal.CONTENT)
                  .borderRadius(8)
                  .layoutWeight(1)
                  .onChange((v: string) => {
                    this.renameText = v;
                  })
                  .onSubmit(() => this.confirmRename())
                Text('✓')
                  .fontSize(15)
                  .fontColor(this.pal.PRIMARY)
                  .padding(6)
                  .onClick(() => this.confirmRename())
                Text('✕')
                  .fontSize(15)
                  .fontColor(this.pal.TEXT_SUB)
                  .padding(6)
                  .onClick(() => {
                    this.renamingFrom = '';
                  })
              }
              .width('100%')
              .padding({ top: 3, bottom: 3 })
            } else {
              Row({ space: 10 }) {
                Text(name)
                  .fontSize(14)
                  .fontColor(this.pal.TEXT)
                  .maxLines(1)
                  .layoutWeight(1)
                Text('⋯')
                  .fontSize(16)
                  .fontColor(this.pal.TEXT_FAINT)
                  .padding({ left: 6, right: 2 })
                  .onClick(() => this.libraryRowMenu(name))
              }
              .width('100%')
              .height(42)
              .padding({ left: 12, right: 12 })
              .onClick(() => {
                this.pickingFile = false;
                // listLibrary 返回裸文件名，路由需要完整相对路径（修复 loadFailed 误报）
                this.goEditorWith(`library/${name}`);
              })
            }
          }, (name: string) => name + (this.renamingFrom === name ? ':edit' : ''))
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 200 })
      .width('100%')

      // 回收站（可见、可恢复）
      if (this.trashFiles.length > 0 || this.trashOpen) {
        Divider().color(this.pal.DIVIDER).margin({ top: 4, bottom: 4 })
        Row() {
          Text(`回收站 · ${this.trashFiles.length}`)
            .fontSize(13)
            .fontColor(this.pal.TEXT_SUB)
            .layoutWeight(1)
          Text(this.trashOpen ? '收起' : '展开')
            .fontSize(12)
            .fontColor(this.pal.PRIMARY)
            .onClick(() => {
              this.trashOpen = !this.trashOpen;
            })
        }
        .width('100%')
        if (this.trashOpen) {
          ForEach(this.trashFiles, (name: string) => {
            Row({ space: 10 }) {
              Text(name)
                .fontSize(13)
                .fontColor(this.pal.TEXT_SUB)
                .maxLines(1)
                .layoutWeight(1)
              Text('恢复')
                .fontSize(12)
                .fontColor(this.pal.PRIMARY)
                .padding(4)
                .onClick(() => this.restoreFromTrash(name))
            }
            .width('100%')
            .height(36)
            .padding({ left: 12, right: 12 })
          }, (name: string) => name)
        }
      }
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

      this.primaryBtn('新建文档', () => this.goEditor())

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
        Text(this.searchQuery.length > 0 ? '搜索结果' : '最近')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.TEXT)
          .layoutWeight(1)
        if (this.searchQuery.length > 0) {
          Text(this.searchBusy ? '搜索中…' : `${this.searchResults.length} 篇`)
            .fontSize(12)
            .fontColor(this.pal.TEXT_FAINT)
        } else if (this.recent.length > 0) {
          Text(`${this.recent.length} 个文档`)
            .fontSize(12)
            .fontColor(this.pal.TEXT_FAINT)
        }
      }
      .width('100%')
      .height(52)
      .padding({ left: 20, right: 16 })

      // 资料库全文搜索框（V0.4.3）
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索文档内容', text: this.searchQuery })
          .fontSize(13)
          .height(34)
          .padding({ left: 0, right: 8 })
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.searchQuery = v;
            this.scheduleSearch();
          })
        if (this.searchQuery.length > 0) {
          Text('✕')
            .fontSize(13)
            .fontColor(this.pal.TEXT_SUB)
            .onClick(() => {
              this.searchQuery = '';
              this.searchResults = [];
            })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 16, bottom: 6 })

      if (this.searchQuery.length > 0) {
        // 搜索结果列表
        if (this.searchResults.length === 0 && !this.searchBusy) {
          Text('没有匹配的文档')
            .fontSize(13)
            .fontColor(this.pal.TEXT_FAINT)
            .padding({ top: 16, left: 20 })
        }
        List({ space: 0 }) {
          ForEach(this.searchResults, (r: DocSearchResult) => {
            ListItem() {
              Column({ space: 3 }) {
                Text(r.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal.TEXT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(r.snippet)
                  .fontSize(11)
                  .fontColor(this.pal.TEXT_FAINT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${r.count} 处命中`)
                  .fontSize(11)
                  .fontColor(this.pal.PRIMARY)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ top: 11, bottom: 11, left: 20, right: 16 })
              .border({ width: { bottom: 1 }, color: this.pal.DIVIDER })
              .onClick(() => this.goEditorWithResult(r.name))
            }
          }, (r: DocSearchResult) => `${r.name}-${r.count}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      } else {
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
    }
    .width(300)
    .height('100%')
    .backgroundColor(this.pal.BG)
    .alignItems(HorizontalAlign.Start)
  }

  /** 欢迎内容区（宽屏右栏）：安静的起点，不抢内容的戏 */
  @Builder
  welcomePanel() {
    Column({ space: 0 }) {
      Blank().height(120)

      Text('Markdown 工作台')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.TEXT)
      Text('打开的是原文件，保存后仍是原文件。')
        .fontSize(13)
        .fontColor(this.pal.TEXT_FAINT)
        .padding({ top: 6, bottom: 36 })

      Button('新建文档')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.pal.ON_PRIMARY)
        .backgroundColor(this.pal.PRIMARY)
        .borderRadius(22)
        .width(180)
        .height(44)
        .onClick(() => this.goEditor())

      Text('或从左侧打开最近的文档')
        .fontSize(12)
        .fontColor(this.pal.TEXT_FAINT)
        .padding({ top: 12 })

      if (this.recent.length > 0) {
        Text(`上次编辑 · ${RecentFileList.displayName(this.recent[0].documentId)} · ${this.fmtTime(this.recent[0].lastOpenedAt)}`)
          .fontSize(12)
          .fontColor(this.pal.TEXT_SUB)
          .padding({ top: 4 })
          .onClick(() => this.openRecent(this.recent[0]))
      }

      if (this.pickingFile) {
        Blank().height(24)
        this.libraryPanel()
      }

      Blank().layoutWeight(1)
    }
    .layoutWeight(1)
    .height('100%')
    .padding(28)
    .backgroundColor(this.pal.CONTENT)
    .alignItems(HorizontalAlign.Start)
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

      this.primaryBtn('新建文档', () => this.goEditor())

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

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索文档内容', text: this.searchQuery })
          .fontSize(13)
          .height(36)
          .padding({ left: 0, right: 8 })
          .backgroundColor(this.pal.CONTENT)
          .borderRadius(10)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.searchQuery = v;
            this.scheduleSearch();
          })
        if (this.searchQuery.length > 0) {
          Text('✕')
            .fontSize(13)
            .fontColor(this.pal.TEXT_SUB)
            .padding(4)
            .onClick(() => {
              this.searchQuery = '';
              this.searchResults = [];
            })
        }
      }
      .width('100%')

      if (this.searchQuery.length > 0) {
        if (this.searchResults.length === 0 && !this.searchBusy) {
          Text('没有匹配的文档')
            .fontSize(13)
            .fontColor(this.pal.TEXT_FAINT)
            .padding({ top: 12 })
        }
        List({ space: 0 }) {
          ForEach(this.searchResults, (r: DocSearchResult) => {
            ListItem() {
              Column({ space: 3 }) {
                Text(r.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.pal.TEXT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(r.snippet)
                  .fontSize(11)
                  .fontColor(this.pal.TEXT_FAINT)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${r.count} 处命中`)
                  .fontSize(11)
                  .fontColor(this.pal.PRIMARY)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ top: 11, bottom: 11, left: 4, right: 4 })
              .border({ width: { bottom: 1 }, color: this.pal.DIVIDER })
              .onClick(() => this.goEditorWithResult(r.name))
            }
          }, (r: DocSearchResult) => `${r.name}-${r.count}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      } else {
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
