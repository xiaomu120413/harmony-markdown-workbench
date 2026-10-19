import { ControlStyle, ControlMetrics } from '../common/ControlStyle';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery, promptAction } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { DocumentImportService } from '../services/DocumentImportService';
import { DocumentIntake } from '../domain/document/DocumentIntake';
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
  @State dropBusy: boolean = false;

  private async receiveDrop(event: DragEvent): Promise<void> {
    if (this.dropBusy) { promptAction.showToast({ message: '正在读取文件，请稍候再拖入' }); return; }
    this.dropBusy = true;
    try {
      const id = await new DocumentImportService(this.ctx,
        (key: string) => this.getUIContext().getDragController().cancelDataLoading(key)).receive(event);
      promptAction.showToast({ message: '已导入“我的文档”，编辑的是副本' });
      AppStorage.setOrCreate('pendingOpenUri', id);
    } catch (e) {
      this.note('[拖入] 文件获取失败');
      promptAction.showToast({ message: String(e).replace(/^Error: /, '') });
    } finally { this.dropBusy = false; }
  }
  @StorageLink('pendingOpenUri') @Watch('consumeExternalOpen') pendingOpenUri: string = '';

  private consumeExternalOpen(): void {
    if (this.pendingOpenUri.length === 0 || router.getState().name !== 'HomePage') { return; }
    const uri = this.pendingOpenUri;
    this.pendingOpenUri = '';
    router.pushUrl({ url: 'pages/EditorPage', params: DocumentIntake.route(uri) }).catch(() => {
      this.note('[打开] 无法进入编辑页，请重新打开文件');
      promptAction.showToast({ message: '打开失败，请重新选择文件' });
    });
  }
  @State recent: RecentEntry[] = [];
  @State libraryFiles: string[] = [];
  @State draftCount: number = 0;
  @State pickingFile: boolean = false;
  @State renamingFrom: string = '';
  @State renameText: string = '';
  @State trashFiles: string[] = [];
  @State trashOpen: boolean = false;
  @State searchQuery: string = '';
  /** 最近列表收起（宽屏）：收起后欢迎区占满 */
  @State recentCollapsed: boolean = false;
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
    this.consumeExternalOpen();
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
    // C3-4：固定项排最前，其余按时间倒序
    this.recent = new RecentFileList(entries).snapshot().sort((a: RecentEntry, b: RecentEntry): number => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.lastOpenedAt - a.lastOpenedAt;
    });
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

  /** 回收站恢复（C3：唯一回收 ID + 重名避让） */
  private restoreFromTrash(trashName: string): void {
    const restored = this.fileSource.restoreTrash(trashName);
    if (restored.length > 0) {
      this.refreshLibrary();
      this.refresh();
      promptAction.showToast({ message: `已恢复为 ${restored}` });
    } else {
      promptAction.showToast({ message: '恢复失败' });
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
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        Text(label)
          .fontSize(ControlMetrics.FONT)
          .fontColor(this.pal.TEXT)
          .layoutWeight(1)
      }.width('100%')
    }
      .attributeModifier(new ControlStyle(this.pal)).width('100%')
      .onClick(() => action())
  }

  /** 回收名（原名.<时间戳>）→ 显示原名 */
  private trashDisplayName(trashName: string): string {
    const dot = trashName.lastIndexOf('.');
    return dot > 0 ? trashName.substring(0, dot) : trashName;
  }

  /** C3-4：最近行长按 → 固定/取消固定 */
  private recentRowMenu(item: RecentEntry): void {
    const that = this;
    promptAction.showActionMenu({
      title: RecentFileList.displayName(item.documentId),
      buttons: [
        { text: item.pinned ? '取消固定' : '固定到顶部', color: that.pal.TEXT },
      ],
    }).then((r: promptAction.ActionMenuSuccessResponse) => {
      if (r.index === 0) {
        that.togglePin(item.documentId);
      }
    });
  }

  private async togglePin(docId: string): Promise<void> {
    try {
      const entries = await this.meta.loadRecent();
      const list = new RecentFileList(entries);
      const cur = entries.find((e: RecentEntry): boolean => e.documentId === docId);
      list.setPinned(docId, !(cur?.pinned === true));
      await this.meta.saveRecent(list.snapshot());
      this.refresh();
    } catch (e) {
      promptAction.showToast({ message: '操作失败' });
    }
  }

  /** 最近文档行（列表区行 + 细分隔线） */
  @Builder
  recentRow(item: RecentEntry) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        if (item.pinned) {
          Text('📌').fontSize(11)
        }
        Text(RecentFileList.displayName(item.documentId))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      Text(`${RecentFileList.location(item.documentId)} · ${this.fmtTime(item.lastOpenedAt)}`)
        .fontSize(11)
        .fontColor(this.pal.TEXT_FAINT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 11, bottom: 11, left: 20, right: 16 })
    .border({ width: { bottom: 1 }, color: this.pal.DIVIDER })
    .onClick(() => this.openRecent(item))
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onActionEnd(() => this.recentRowMenu(item))
    )
  }

  /** 资料库选择面板 */
  @Builder
  libraryPanel() {
    Column({ space: 6 }) {
      Row() {
        Text(`我的文档 · ${this.libraryFiles.length} 个`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.TEXT)
          .layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.pal.TEXT])
        }
          .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('关闭')
          .onClick(() => { this.pickingFile = false; })
      }
      .width('100%')

      if (this.libraryFiles.length === 0) {
        Text('还没有保存过文档')
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
                  .height(ControlMetrics.HEIGHT)
                  .padding({ left: 8, right: 8 })
                  .backgroundColor(this.pal.CONTENT)
                  .borderRadius(8)
                  .layoutWeight(1)
                  .onChange((v: string) => {
                    this.renameText = v;
                  })
                  .onSubmit(() => this.confirmRename())
                Button({ type: ButtonType.Normal }) {
                  SymbolGlyph($r('sys.symbol.checkmark')).fontSize(20).fontColor([this.pal.TEXT])
                }
                  .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('确认')
                  .onClick(() => this.confirmRename())
                Button({ type: ButtonType.Normal }) {
                  SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.pal.TEXT])
                }
                  .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('关闭')
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
                Button({ type: ButtonType.Normal }) {
                  SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(20).fontColor([this.pal.TEXT])
                }
                  .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('更多操作')
                  .onClick(() => this.libraryRowMenu(name))
              }
              .width('100%')
              .height(ControlMetrics.HEIGHT)
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
          Button(this.trashOpen ? '收起' : '展开', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.pal, 'quiet'))
            .onClick(() => {
              this.trashOpen = !this.trashOpen;
            })
        }
        .width('100%')
        if (this.trashOpen) {
          ForEach(this.trashFiles, (trashName: string) => {
            Row({ space: 10 }) {
              Text(this.trashDisplayName(trashName))
                .fontSize(13)
                .fontColor(this.pal.TEXT_SUB)
                .maxLines(1)
                .layoutWeight(1)
              Button('恢复', { type: ButtonType.Normal })
                .attributeModifier(new ControlStyle(this.pal, 'quiet'))
                .onClick(() => this.restoreFromTrash(trashName))
            }
            .width('100%')
            .height(ControlMetrics.HEIGHT)
            .padding({ left: 12, right: 12 })
          }, (trashName: string) => trashName)
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.pal.CONTENT)
    .borderRadius(12)
  }

  /** 全局主操作，与编辑页保存共用尺寸和配色。 */
  @Builder
  primaryBtn(label: string, action: () => void) {
    Button(label, { type: ButtonType.Normal })
      .width('100%')
      .attributeModifier(new ControlStyle(this.pal, 'primary'))
      .onClick(() => action())
  }

  /** 侧栏（宽屏）：品牌 / 主操作 / 导航 / 最近 */
  @Builder
  sideBar() {
    Column({ space: 2 }) {
      Text('木笺')
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
      Text('本机 Markdown 文档')
        .fontSize(11)
        .fontColor(this.pal.TEXT_FAINT)
        .padding({ bottom: 10 })

      this.primaryBtn('新建文档', () => this.goEditor())

      Column({ space: 0 }) {
        this.navRow('打开文档', () => this.openExternalFile())
        this.navRow('我的文档', () => this.openLibraryFile())
        if (this.draftCount > 0) {
          this.navRow(`找回未保存内容（${this.draftCount}）`, () => this.goRecovery())
        }
        this.navRow('设置', () => this.goSettings())
      }
      .width('100%')
      .margin({ top: 6 })

      // 最近列表收起/展开（收起后欢迎区占满）
      Row() {
        Text('最近列表')
          .fontSize(12)
          .fontColor(this.pal.TEXT_SUB)
        Blank()
        Button(this.recentCollapsed ? '展开' : '收起', { type: ButtonType.Normal })
          .attributeModifier(new ControlStyle(this.pal, 'quiet'))
          .onClick(() => {
            this.recentCollapsed = !this.recentCollapsed;
          })
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
          .height(ControlMetrics.HEIGHT)
          .padding({ left: 0, right: 8 })
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.searchQuery = v;
            this.scheduleSearch();
          })
        if (this.searchQuery.length > 0) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.pal.TEXT])
          }
            .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('关闭')
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

      Text('开始写作')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.pal.TEXT)
      Text('打开已有文档，或新建一份 Markdown。')
        .fontSize(13)
        .fontColor(this.pal.TEXT_FAINT)
        .padding({ top: 6, bottom: 36 })

      Button('新建文档', { type: ButtonType.Normal })
        .width(180)
        .attributeModifier(new ControlStyle(this.pal, 'secondary'))
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
      Text('木笺')
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
        Button('打开文档', { type: ButtonType.Normal })
          .layoutWeight(1)
          .attributeModifier(new ControlStyle(this.pal, 'quiet'))
          .onClick(() => this.openExternalFile())
        Button('我的文档', { type: ButtonType.Normal })
          .layoutWeight(1)
          .attributeModifier(new ControlStyle(this.pal, 'quiet'))
          .onClick(() => this.openLibraryFile())
      }
      .width('100%')

      if (this.draftCount > 0) {
        this.navRow(`找回未保存内容（${this.draftCount}）`, () => this.goRecovery())
      }

      if (this.pickingFile) {
        this.libraryPanel()
      }

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索文档内容', text: this.searchQuery })
          .fontSize(13)
          .height(ControlMetrics.HEIGHT)
          .padding({ left: 0, right: 8 })
          .backgroundColor(this.pal.CONTENT)
          .borderRadius(ControlMetrics.RADIUS)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.searchQuery = v;
            this.scheduleSearch();
          })
        if (this.searchQuery.length > 0) {
          Button({ type: ButtonType.Normal }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.pal.TEXT])
          }
            .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('关闭')
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
          if (!this.recentCollapsed) {
            this.recentColumn()
            Divider().vertical(true).height('100%').color(this.pal.DIVIDER)
          }
          this.welcomePanel()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.BG)
    .onDrop((event: DragEvent) => { this.receiveDrop(event); }, { disableDataPrefetch: true })
  }
}
