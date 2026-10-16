import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { SaveState, SaveStateMachine } from '../domain/recovery/SaveStateMachine';
import { MarkdownCommands, MarkdownCommandName, TextRange, TextTransformResult } from '../domain/editor/MarkdownCommands';
import { FindReplaceEngine, FindOptions, FindMatch } from '../domain/editor/FindReplaceEngine';
import { FindSession } from '../domain/editor/FindSession';
import { ViewModePolicy } from '../domain/editor/ViewModePolicy';
import { HeadingOutline } from '../domain/editor/HeadingOutline';
import { EditorBridge } from '../services/EditorBridge';
import { SaveCoordinator, SaveCoordinatorDeps, SnapshotData } from '../services/SaveCoordinator';
import { DocumentFileAdapter, DocumentSource, InternalSource, ExternalSource, FileRevisionContract, WriteDocumentResult, WriteFailResult, DocumentWriteFormat } from '../domain/document/DocumentFileAdapter';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { ExternalUriFileSource } from '../infrastructure/file/ExternalUriFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { RecentFileList } from '../domain/document/RecentFileList';
import { DocumentNamer } from '../domain/document/DocumentNamer';
import { HtmlExporter } from '../domain/document/HtmlExporter';
import { SettingsStore } from '../infrastructure/metadata/SettingsStore';
import { AppTheme } from '../common/AppTheme';
import { SegBtn } from '../common/SegBtn';
import { beginWindowMove } from '../common/WindowDrag';
import { DocumentSidebar } from '../components/DocumentSidebar';
import { WorkspaceUiStore } from '../infrastructure/metadata/WorkspaceUiStore';
import { RecentEntry } from '../domain/document/RecentFileList';
import { Breakpoint, watchBreakpoints, unwatchBreakpoints } from '../common/Breakpoints';
import { AppSettings, SettingsValidator, ThemeMode, DefaultView } from '../domain/settings/AppSettings';

const DOMAIN: number = 0x0000;
const TAG: string = 'HMWB-EDITOR';

/** 预览同步防抖（ms）：连续输入时预览不逐键重渲 */
const PREVIEW_SYNC_DEBOUNCE_MS: number = 300;

/** 桥消息队列（ArkWeb jsProxy 回调线程不能操作组件 this——M0-03 R-16 结论） */
let pendingBridge: Array<string> = [];
let bridgeSink: ((msg: string) => void) | undefined = undefined;

function editorBridgeSend(raw: string): void {
  pendingBridge.push(raw);
}

/** 路由参数形状（M5-01：name=内部相对路径 / uri=外部文档 URI） */
interface RouteParams {
  name?: string;
  uri?: string;
}

/** 大纲条目（渲染用）：层级 + 文档内选区（跳转定位） */
interface OutlineEntry {
  level: number;
  text: string;
  from: number;
  to: number;
}

/**
 * SaveCoordinator 依赖适配（ArkTS：接口方法成员不能由对象字面量属性函数满足，
 * 以显式 class 注入组件闭包）。
 */
class EditorPageDeps implements SaveCoordinatorDeps {
  private readonly snapshotImpl: () => Promise<SnapshotData>;
  private readonly checkpointImpl: (c: string) => Promise<void>;
  private readonly persistImpl: (c: string) => Promise<WriteDocumentResult>;

  constructor(
    snapshotImpl: () => Promise<SnapshotData>,
    checkpointImpl: (c: string) => Promise<void>,
    persistImpl: (c: string) => Promise<WriteDocumentResult>,
  ) {
    this.snapshotImpl = snapshotImpl;
    this.checkpointImpl = checkpointImpl;
    this.persistImpl = persistImpl;
  }

  getSnapshot(): Promise<SnapshotData> {
    return this.snapshotImpl();
  }

  saveCheckpoint(content: string): Promise<void> {
    return this.checkpointImpl(content);
  }

  persist(content: string): Promise<WriteDocumentResult> {
    return this.persistImpl(content);
  }
}

/**
 * 正式编辑器页：CM6 编辑运行时 + 预览运行时（三端视图）+ 快捷栏 + 查找替换 + SaveCoordinator。
 * 视图模式（SDD 4.2 三端）：
 *   phone：编辑 ⇄ 预览 单栏切换；
 *   tablet/pc：编辑 / 预览 / 左右分屏（编辑+预览同屏，预览随输入防抖同步）。
 * 入口视图消费设置 defaultView（M5-03；phone 上 split 自动降级为 edit）。
 */
@Entry
@Component
struct EditorPage {
  @State saveLabel: string = '已保存';
  @State docLength: number = 0;
  @State docTitle: string = '未命名';
  @State conflictVisible: boolean = false;
  @State viewMode: DefaultView = DefaultView.EDIT;
  @State findVisible: boolean = false;
  @State findQuery: string = '';
  @State replaceText: string = '';
  @State findCase: boolean = false;
  @State findWord: boolean = false;
  @State matchCount: number = 0;
  @State matchIndex: number = -1;
  @State outlineVisible: boolean = false;
  @State outlineEntries: OutlineEntry[] = [];
  @State cursorLine: number = 1;
  @State cursorCol: number = 1;
  /** 文档加载状态（A2）：新文档默认 ready；外部/内部文档打开前 loading，失败分流 */
  @State loadState: 'loading' | 'ready' | 'loadFailed' | 'accessExpired' = 'ready';
  // B1/B2：文档侧栏（编辑页内切换文档）
  @State sidebarVisible: boolean = false;
  @State sidebarRecent: RecentEntry[] = [];
  @State sidebarLibrary: string[] = [];
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private controller: webview.WebviewController = new webview.WebviewController();
  private previewController: webview.WebviewController = new webview.WebviewController();
  private bridge: EditorBridge = new EditorBridge();
  private internal: InternalFileSource = new InternalFileSource(getContext(this) as common.UIAbilityContext);
  private external: ExternalUriFileSource = new ExternalUriFileSource();
  private drafts: DraftStore = new DraftStore(getContext(this) as common.UIAbilityContext);
  private settings: SettingsStore = new SettingsStore(getContext(this) as common.UIAbilityContext);
  private meta: MetadataStore = new MetadataStore(getContext(this) as common.UIAbilityContext);
  private appSettings: AppSettings = SettingsValidator.defaults();
  @State pal: AppTheme = AppTheme.light();
  @State bp: Breakpoint = 'phone';
  /** B4：内容区实际宽度（vp），onAreaChange 更新 */
  @State contentWidthVp: number = 1000;
  private bpListeners: mediaquery.MediaQueryListener[] = [];
  private coordinator: SaveCoordinator | undefined = undefined;
  private docTarget: DocumentSource | undefined = undefined;
  private expectedRevision: FileRevisionContract = { size: 0, contentHash: '' };
  private pendingLoad: string = '';
  /** A3：新建文档的会话草稿 ID（首次保存前即拥有草稿身份，R05） */
  private sessionDraftId: string = `session:${Date.now()}-${Math.floor(Math.random() * 0xffff).toString(16)}`;
  /** A4：文档格式（编码/换行）——读取时捕获，落盘时还原；非法 UTF-8 阻断写回 */
  private docFormat: DocumentWriteFormat = { encoding: 'utf-8', lineEnding: 'lf' };
  private docValidUtf8: boolean = true;
  private pendingLoadAt: number = 0;
  private webReady: boolean = false;
  private previewReady: boolean = false;
  private lastPreviewedMd: string = '\u0000';
  private previewTimer: number = -1;
  private findMatches: FindMatch[] = [];
  private flushTimer: number = -1;
  private saveTimer: number = -1;

  private append(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    this.bpListeners = watchBreakpoints((bp: Breakpoint) => {
      this.bp = bp;
      // 断点变化归一化：phone 档无分屏（ViewModePolicy）
      this.viewMode = ViewModePolicy.normalize(this.viewMode, bp);
    });
    // 编排器延迟创建：deps 闭包依赖组件方法（字段初始化器内不能引用 this）
    this.coordinator = new SaveCoordinator(new EditorPageDeps(
      () => this.getSnapshotData(),
      (content: string) => this.doSaveCheckpoint(content),
      (content: string) => this.doPersist(content),
    ));
    bridgeSink = (raw: string): void => {
      const env = this.bridge.parseEvent(raw);
      if (env === undefined) {
        return;
      }
      if (env.type === 'edit') {
        // 用户输入（打字/粘贴/IME/撤销重做）：进入 DIRTY 并调度防抖保存与预览同步
        const len = env.payload.len as number | undefined;
        if (len !== undefined) {
          this.docLength = len;
        }
        const ln = env.payload.line as number | undefined;
        const col = env.payload.col as number | undefined;
        if (ln !== undefined) {
          this.cursorLine = ln;
        }
        if (col !== undefined) {
          this.cursorCol = col;
        }
        const c = this.coordinator;
        if (c !== undefined) {
          // A1：编辑事件携带版本 → 保存完成只确认快照版本
          const ver = env.payload.v as number | undefined;
          if (ver !== undefined) {
            c.onEdit(Date.now(), ver);
          } else {
            c.onEdit(Date.now());
          }
          this.saveLabel = SaveStateMachine.label(c.state);
        }
        this.scheduleDocSync();
        return;
      }
      if (env.type === 'command') {
        // C4：快捷键 → 统一命令（与按钮同一路径）
        const action = env.payload.action as string | undefined;
        if (action === 'save') {
          this.save();
        } else if (action === 'find') {
          if (this.findVisible) {
            this.findVisible = false;
          } else {
            this.openFind();
          }
        } else if (action === 'outline') {
          this.toggleOutline();
        } else if (action === 'bold') {
          this.applyCommand('bold');
        } else if (action === 'italic') {
          this.applyCommand('italic');
        }
        return;
      }
      if (env.type === 'cursor') {
        // 光标移动（点击/方向键）：状态栏行列更新
        const ln = env.payload.line as number | undefined;
        const col = env.payload.col as number | undefined;
        if (ln !== undefined) {
          this.cursorLine = ln;
        }
        if (col !== undefined) {
          this.cursorCol = col;
        }
        return;
      }
      if (!this.bridge.isFirstResponse(env.id)) {
        return;
      }
      this.append(`[event] ${env.type}`);
    };
    this.flushTimer = setInterval(() => {
      const drained = pendingBridge.slice();
      pendingBridge = [];
      for (let i = 0; i < drained.length; i++) {
        if (bridgeSink !== undefined) {
          bridgeSink(drained[i]);
        }
      }
    }, 500);
    // 自动保存检查（M4-01：防抖由 SaveScheduler 负责，轮询只触发到期保存；
    // autoSave 设置关闭时跳过自动保存，手动保存仍可用——M5-03）
    this.saveTimer = setInterval(() => {
      const c = this.coordinator;
      if (c === undefined || !this.appSettings.autoSave) {
        return;
      }
      c.tick(Date.now()).then((ran: boolean) => {
        if (ran) {
          this.saveLabel = SaveStateMachine.label(c.state);
          this.conflictVisible = c.state === SaveState.CONFLICT;
          if (c.state === SaveState.ERROR) {
            this.append('[自动保存] 失败，保留未保存内容');
          }
        }
      });
    }, 500);
    this.resolveRouteParams();
    this.applyAppSettings();
    this.initSidebar();
  }

  /** M5-03：读取持久化设置并应用（主题/字号/换行/行号即时生效；defaultView 决定入口视图） */
  private applyAppSettings(): void {
    this.settings.load().then((s: AppSettings) => {
      this.appSettings = s;
      this.viewMode = ViewModePolicy.resolveInitial(this.bp, s.defaultView);
      this.pal = AppTheme.of(s.theme === ThemeMode.DARK);
      this.applyEditorStyle();
      this.applyPreviewStyle();
    }).catch((e: ESObject) => {
      this.append(`[设置] 读取失败：${JSON.stringify(e)}`);
    });
  }

  /** 编辑器样式跟随设置（幂等；aboutToAppear 与 Web onPageEnd 各发一次，消除加载竞态） */
  private applyEditorStyle(): void {
    const s = this.appSettings;
    const dark = s.theme === ThemeMode.DARK;
    this.runJsValue(`window.__editorApi.setTheme(${dark});`);
    this.runJsValue(`window.__editorApi.setFontSize(${s.fontSize});`);
    this.runJsValue(`window.__editorApi.setWrap(${s.wrap});`);
    this.runJsValue(`window.__editorApi.setLineNumbers(${s.lineNumbers});`);
  }

  /** 预览样式跟随设置（就绪前跳过，onPageEnd 时补发） */
  private applyPreviewStyle(): void {
    if (!this.previewReady) {
      return;
    }
    const dark = this.appSettings.theme === ThemeMode.DARK;
    this.previewController.runJavaScript(`window.__previewApi.setDark(${dark});`);
    this.previewController.runJavaScript(`window.__previewApi.setFontSize(${this.appSettings.fontSize});`);
  }

  /** B1/B2：侧栏初始化——加载用户偏好与文档列表 */
  private initSidebar(): void {
    const ui = new WorkspaceUiStore(this.ctx);
    ui.loadSidebarPreferredOpen().then((open: boolean) => {
      this.sidebarVisible = open && this.bp !== 'phone';
    }).catch(() => {
      this.sidebarVisible = this.bp !== 'phone';
    });
    this.refreshSidebarData();
  }

  private refreshSidebarData(): void {
    this.sidebarLibrary = this.internal.listLibrary();
    this.meta.loadRecent().then((entries: RecentEntry[]) => {
      this.sidebarRecent = new RecentFileList(entries).snapshot();
    }).catch(() => {
      this.sidebarRecent = [];
    });
  }

  /** 侧栏开关（B2-01：手动调整持久化） */
  private toggleSidebar(): void {
    this.sidebarVisible = !this.sidebarVisible;
    const ui = new WorkspaceUiStore(this.ctx);
    ui.saveSidebarPreferredOpen(this.sidebarVisible);
    this.refreshSidebarData();
  }

  /**
   * B1-01：侧栏选文档 → 不必返回首页。
   * B1-02：dirty 时经 A3 离开流程（保存失败/冲突阻止切换）。
   */
  private async switchToDocument(docId: string): Promise<void> {
    if (docId.startsWith('library/')) {
      const cur = this.docTarget;
      if (cur !== undefined && cur.kind === 'internal' && (cur as InternalSource).relativePath === docId) {
        return;
      }
      const c = this.coordinator;
      if (c !== undefined && (c.state === SaveState.DIRTY || c.state === SaveState.ERROR || c.state === SaveState.CONFLICT)) {
        const outcome = await c.saveNow(Date.now());
        this.saveLabel = SaveStateMachine.label(c.state);
        if (!((outcome === 'saved' || outcome === 'unchanged') && !c.pending)) {
          promptAction.showToast({ message: '请先保存当前文档再切换' });
          return;
        }
      }
      const src: InternalSource = { kind: 'internal', relativePath: docId };
      this.docTarget = src;
      this.docTitle = docId.substring(docId.lastIndexOf('/') + 1);
      this.docFormat = { encoding: 'utf-8', lineEnding: 'lf' };
      this.docValidUtf8 = true;
      this.loadOpenedDoc(src);
      this.refreshSidebarData();
    }
  }

  aboutToDisappear(): void {
    unwatchBreakpoints(this.bpListeners);
    this.bpListeners = [];
    if (this.flushTimer >= 0) {
      clearInterval(this.flushTimer);
      this.flushTimer = -1;
    }
    if (this.saveTimer >= 0) {
      clearInterval(this.saveTimer);
      this.saveTimer = -1;
    }
    if (this.previewTimer >= 0) {
      clearTimeout(this.previewTimer);
      this.previewTimer = -1;
    }
    bridgeSink = undefined;
  }

  /** 路由参数：name=内部相对路径 / uri=外部文档（M5-01 入口传递） */
  private resolveRouteParams(): void {
    const params = router.getParams();
    if (params === undefined || params === null) {
      return;
    }
    const pObj: ESObject = params as ESObject;
    const name = pObj.name as string | undefined;
    const uri = pObj.uri as string | undefined;
    if (name !== undefined && name.length > 0) {
      const src: InternalSource = { kind: 'internal', relativePath: name };
      this.docTarget = src;
      this.docTitle = name.substring(name.lastIndexOf('/') + 1);
      this.loadOpenedDoc(src);
    } else if (uri !== undefined && uri.length > 0) {
      const src: ExternalSource = { kind: 'external', uri: uri, displayName: uri };
      this.docTarget = src;
      this.docTitle = RecentFileList.displayName(uri);
      this.loadOpenedDoc(src);
    }
  }

  /** 打开已有文档：读内容（Web 就绪后注入），基线 revision 用于冲突检测；
   * t0 记录请求时刻用于 M6-02 打开性能样本。 */
  private loadOpenedDoc(target: DocumentSource): void {
    const t0 = Date.now();
    this.loadState = 'loading';
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.internal : this.external;
    src.read(target).then((r) => {
      this.expectedRevision = r.revision;
      this.pendingLoad = r.content;
      this.pendingLoadAt = t0;
      this.docFormat = { encoding: r.encoding, lineEnding: r.lineEnding };
      this.docValidUtf8 = r.validUtf8;
      this.loadState = 'ready';
      this.trackRecent(target);
      if (this.webReady) {
        this.flushPendingLoad();
      }
    }).catch((e: ESObject) => {
      // A2-04：权限失效（重启后临时授权丢失/文件被移动删除）与普通读取失败分流通
      const msg = String(e);
      this.loadState = msg.includes('13900001') || msg.includes('13900002') || msg.includes('permission')
        ? 'accessExpired' : 'loadFailed';
      this.append(`[打开] 失败（${this.loadState}）：${msg.substring(0, 200)}`);
    });
  }

  /** A2-06：重新选择文件——重建来源、基线与显示名（不依赖旧 URI 的持久权限） */
  private async reselectExternalFile(): Promise<void> {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.ctx);
      const result: Array<string> = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.md', '.markdown', '.txt'],
      });
      if (result.length === 0) {
        return; // 用户取消：保持恢复面板
      }
      const src: ExternalSource = { kind: 'external', uri: result[0], displayName: result[0] };
      this.docTarget = src;
      this.docTitle = RecentFileList.displayName(result[0]);
      this.loadOpenedDoc(src);
    } catch (e) {
      this.append(`[重选] 选择器失败：${JSON.stringify(e)}`);
    }
  }

  /** A2-04：读取失败后的本地内容另存副本（正文仍在编辑器/草稿检查点中） */
  private async saveLocalCopyFromFailed(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    const content = await this.runJsValue('window.__editorApi.getSnapshot();');
    const name = DocumentNamer.derive(content, this.internal.listLibrary());
    const copy: InternalSource = { kind: 'internal', relativePath: `library/${name}` };
    this.docTarget = copy;
    this.docTitle = name;
    this.loadState = 'ready';
    const outcome = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.append(`[恢复] 副本保存${outcome === 'saved' ? '完成' : '失败'} → ${copy.relativePath}`);
  }

  /** M5-01：保存/打开后更新最近文件元数据（FR-RECENT；失败不阻塞保存） */
  private async trackRecent(target: DocumentSource): Promise<void> {
    try {
      const id = target.kind === 'internal'
        ? (target as InternalSource).relativePath
        : (target as ExternalSource).uri;
      const entries = await this.meta.loadRecent();
      const list = new RecentFileList(entries);
      list.touch(id, Date.now());
      await this.meta.saveRecent(list.snapshot());
    } catch (e) {
      // 元数据失败不影响正文保存
    }
  }

  private flushPendingLoad(): void {
    const md = this.pendingLoad;
    this.pendingLoad = '';
    const t0 = this.pendingLoadAt;
    const js = `window.__editorApi.loadDocument(${JSON.stringify(md)});`;
    this.runJsValue(js).then(() => {
      this.docLength = md.length;
      const dt = t0 > 0 ? Date.now() - t0 : -1;
      this.append(`[打开] 文档 ${md.length} 字符（打开至可编辑 ${dt}ms）`);
      const c0 = this.coordinator;
      if (c0 !== undefined) {
        c0.onDocumentLoaded();
      }
      this.syncDocNow();
    });
  }

  // ---- 文档联动同步（编辑 → 预览渲染 + 大纲重建，防抖 + 内容去重）----

  private scheduleDocSync(): void {
    if (this.viewMode === DefaultView.EDIT && !this.outlineVisible) {
      return;
    }
    if (this.previewTimer >= 0) {
      clearTimeout(this.previewTimer);
    }
    this.previewTimer = setTimeout(() => {
      this.previewTimer = -1;
      this.syncDocNow();
    }, PREVIEW_SYNC_DEBOUNCE_MS);
  }

  /** 一次快照取回，按需驱动预览渲染与大纲重建 */
  private syncDocNow(): void {
    if (!this.webReady) {
      return;
    }
    const needPreview = this.previewReady && this.viewMode !== DefaultView.EDIT;
    const needOutline = this.outlineVisible;
    if (!needPreview && !needOutline) {
      return;
    }
    this.runJsValue('window.__editorApi.getSnapshot();').then((md: string) => {
      if (needPreview && md !== this.lastPreviewedMd) {
        this.lastPreviewedMd = md;
        const js = `window.__previewApi.render(${JSON.stringify(md)});`;
        this.previewController.runJavaScript(js, (err) => {
          if (err) {
            this.append(`[预览] 渲染失败：${JSON.stringify(err)}`);
          }
        });
      }
      if (needOutline) {
        this.rebuildOutline(md);
      }
    });
  }

  /** 大纲重建：领域提取 + 行偏移映射（FR-PREVIEW-003 总装） */
  private rebuildOutline(md: string): void {
    const items = HeadingOutline.extract(md);
    const offsets = HeadingOutline.lineOffsets(md);
    const entries: OutlineEntry[] = [];
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      const from = it.line < offsets.length ? offsets[it.line] : 0;
      const to = it.line + 1 < offsets.length ? offsets[it.line + 1] - 1 : md.length;
      entries.push({
        level: it.level,
        text: it.text.length > 0 ? it.text : '（无标题）',
        from: from,
        to: to,
      });
    }
    this.outlineEntries = entries;
  }

  /** 大纲条目点击 → 编辑器定位（预览态先切回编辑） */
  private jumpToOutlineEntry(e: OutlineEntry): void {
    if (this.viewMode === DefaultView.PREVIEW) {
      this.setViewMode(DefaultView.EDIT);
    }
    this.runJsValue(`window.__editorApi.setSelectionRange(${e.from}, ${e.to});`);
  }

  private toggleOutline(): void {
    this.outlineVisible = !this.outlineVisible;
    if (this.outlineVisible) {
      this.syncDocNow();
    }
  }

  /** 视图切换：进入预览/分屏立即同步一次（不等防抖）；B4 空间预算 */
  private setViewMode(mode: DefaultView): void {
    if (mode === this.viewMode) {
      return;
    }
    if (mode === DefaultView.SPLIT && !ViewModePolicy.allowsSplit(this.bp)) {
      return;
    }
    // B4-01：分屏需满足空间预算（扣除侧栏+大纲后 ≥ 编辑+预览最小宽度）
    if (mode === DefaultView.SPLIT && !ViewModePolicy.splitFits(this.contentWidthVp, this.sidebarVisible, this.outlineVisible)) {
      promptAction.showToast({ message: '空间不足，无法分屏（请收起侧栏或大纲）' });
      return;
    }
    this.viewMode = mode;
    if (mode !== DefaultView.EDIT) {
      this.syncDocNow();
    }
  }

  // ---- 查找替换（FR-EDIT-04 面板；引擎与导航为领域层）----

  private findOpts(): FindOptions {
    const opts: FindOptions = { caseSensitive: this.findCase, wholeWord: this.findWord };
    return opts;
  }

  private openFind(): void {
    this.findVisible = true;
    // 预览态查找无选区可标：切回编辑视图
    if (this.viewMode === DefaultView.PREVIEW) {
      this.setViewMode(DefaultView.EDIT);
    }
    this.refreshFind().then(() => this.jumpNext());
  }

  /** 重算命中集合（正文或选项变化后调用） */
  private async refreshFind(): Promise<void> {
    if (this.findQuery.length === 0) {
      this.findMatches = [];
      this.matchCount = 0;
      this.matchIndex = -1;
      return;
    }
    const text = await this.runJsValue('window.__editorApi.getSnapshot();');
    this.findMatches = FindReplaceEngine.findAll(text, this.findQuery, this.findOpts());
    this.matchCount = this.findMatches.length;
    if (this.matchIndex >= this.matchCount) {
      this.matchIndex = this.matchCount - 1;
    }
  }

  private jumpNext(): void {
    this.matchIndex = FindSession.next(this.matchCount, this.matchIndex);
    this.selectCurrentMatch();
  }

  /** 查询词/选项变化后：尚未定位且有命中时自动选中第一处（主流编辑器行为） */
  private locateFirstMatch(): void {
    if (this.matchIndex < 0 && this.matchCount > 0) {
      this.matchIndex = 0;
      this.selectCurrentMatch();
    }
  }

  private jumpPrev(): void {
    this.matchIndex = FindSession.prev(this.matchCount, this.matchIndex);
    this.selectCurrentMatch();
  }

  private selectCurrentMatch(): void {
    if (this.matchIndex < 0 || this.matchIndex >= this.findMatches.length) {
      return;
    }
    const m = this.findMatches[this.matchIndex];
    this.runJsValue(`window.__editorApi.setSelectionRange(${m.from}, ${m.to});`);
  }

  private async replaceCurrent(): Promise<void> {
    if (this.findQuery.length === 0) {
      return;
    }
    const text = await this.runJsValue('window.__editorApi.getSnapshot();');
    const from = this.matchIndex >= 0 && this.matchIndex < this.findMatches.length
      ? this.findMatches[this.matchIndex].from
      : 0;
    const r = FindReplaceEngine.replaceCurrent(text, this.findQuery, this.replaceText, from, this.findOpts());
    if (!r.replaced) {
      return;
    }
    await this.runJsValue(`window.__editorApi.setDocument(${JSON.stringify(r.text)}, ${r.newCursor}, ${r.newCursor});`);
    this.docLength = r.text.length;
    this.markEdited();
    // 替换改变了正文：同步重算命中（替换处已消失，从锚点前进到下一处）
    const anchor = this.matchIndex;
    this.findMatches = FindReplaceEngine.findAll(r.text, this.findQuery, this.findOpts());
    this.matchCount = this.findMatches.length;
    this.matchIndex = FindSession.next(this.matchCount, Math.min(anchor, this.matchCount - 1));
    this.selectCurrentMatch();
  }

  private async replaceAllMatches(): Promise<void> {
    if (this.findQuery.length === 0) {
      return;
    }
    const text = await this.runJsValue('window.__editorApi.getSnapshot();');
    const r = FindReplaceEngine.replaceAll(text, this.findQuery, this.replaceText, this.findOpts());
    if (r.count === 0) {
      return;
    }
    const pos = r.undos.length > 0 ? r.undos[0].from : 0;
    await this.runJsValue(`window.__editorApi.setDocument(${JSON.stringify(r.text)}, ${pos}, ${pos});`);
    this.docLength = r.text.length;
    this.markEdited();
    // 全部替换后命中归零
    this.findMatches = [];
    this.matchCount = 0;
    this.matchIndex = -1;
    this.append(`[替换] 全部替换 ${r.count} 处`);
  }

  /** 程序化正文变更后的统一收口：置脏 + 预览同步 */
  private markEdited(): void {
    const c = this.coordinator;
    if (c !== undefined) {
      c.onEdit(Date.now());
      this.saveLabel = SaveStateMachine.label(c.state);
    }
    this.scheduleDocSync();
  }

  // ---- 保存 / 冲突 / 分享 ----

  /** 草稿检查点（FR-SAVE-003；A3：无目标的新文档也落会话草稿，R05） */
  private doSaveCheckpoint(content: string): Promise<void> {
    const target = this.docTarget;
    if (target === undefined) {
      this.drafts.save(
        this.sessionDraftId,
        'session:new',
        0,
        '',
        content,
      );
      return Promise.resolve();
    }
    this.drafts.save(
      this.draftIdOf(target),
      this.fingerprintOf(target),
      this.expectedRevision.size,
      this.expectedRevision.contentHash,
      content,
    );
    // 首次持久化成功后会清正式草稿；会话草稿一并在 doPersist 迁移清理
    return Promise.resolve();
  }

  /** 持久化：内部原子写 / 外部 URI 写；新建按首行智能命名，自动名随标题补全升级重命名 */
  private async doPersist(content: string): Promise<WriteDocumentResult> {
    let target = this.docTarget;
    if (target === undefined) {
      const name = DocumentNamer.derive(content, this.internal.listLibrary());
      const src: InternalSource = { kind: 'internal', relativePath: `library/${name}` };
      target = src;
      this.docTarget = src;
      this.docTitle = name;
      this.append(`[保存] 新建文档 → 资料库/${name}`);
    } else if (target.kind === 'internal') {
      // 自动名升级：首次自动保存常发生在标题输入完成前，标题可用时重命名
      const currentName = (target as InternalSource).relativePath.substring('library/'.length);
      const better = DocumentNamer.upgrade(currentName, content, this.internal.listLibrary());
      if (better !== undefined) {
        const renamed: InternalSource = { kind: 'internal', relativePath: `library/${better}` };
        const w = await this.internal.write(renamed, content, this.expectedRevision, this.docFormat);
        if (w.ok) {
          this.internal.remove(target);
          this.docTarget = renamed;
          this.docTitle = better;
          this.expectedRevision = w.revision;
          this.drafts.remove(this.draftIdOf(target));
          this.drafts.remove(this.draftIdOf(renamed));
          this.drafts.remove(this.sessionDraftId);
          this.trackRecent(renamed);
          this.append(`[保存] 自动名升级 → 资料库/${better}`);
          return w;
        }
        // 升级写入失败：按原名继续保存
      }
    }
    if (target.kind === 'external' && this.loadState !== 'ready') {
      // A2：外部文档未成功加载（accessExpired/loadFailed）时禁止原位写回
      const fail: WriteFailResult = { ok: false, reason: 'io', message: 'document not loaded; write-back blocked' };
      return fail;
    }
    if (!this.docValidUtf8) {
      // A4-04：非 UTF-8 文档不静默乱码覆盖——阻断原位写回（内容仍可另存副本）
      const fail: WriteFailResult = { ok: false, reason: 'io', message: 'non-UTF-8 document; write-back blocked' };
      return fail;
    }
    const result = target.kind === 'internal'
      ? await this.internal.write(target, content, this.expectedRevision, this.docFormat)
      : await this.external.write(target, content, this.expectedRevision, this.docFormat);
    if (result.ok) {
      this.expectedRevision = result.revision;
      this.drafts.remove(this.draftIdOf(target));
      // A3：正式目标确立后清理会话草稿（迁移完成）
      this.drafts.remove(this.sessionDraftId);
      this.trackRecent(target);
    }
    return result;
  }

  private draftIdOf(target: DocumentSource): string {
    if (target.kind === 'internal') {
      return `internal:${(target as InternalSource).relativePath}`;
    }
    return `external:${(target as ExternalSource).uri}`;
  }

  private fingerprintOf(target: DocumentSource): string {
    if (target.kind === 'internal') {
      return `internal:${(target as InternalSource).relativePath}`;
    }
    return `external:${(target as ExternalSource).uri}`;
  }

  /**
   * 统一离开流程（A3/R04）：保存成功且无新编辑才离开；失败留在页面可重试。
   * 提示以草稿检查点确实落盘为前提（doSaveCheckpoint 在保存流程中先行执行）。
   */
  private async requestLeave(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      router.back();
      return;
    }
    if (c.state === SaveState.CLEAN) {
      router.back();
      return;
    }
    const outcome = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.conflictVisible = c.state === SaveState.CONFLICT;
    // saved + 无待保存（保存期间无新编辑，A1 版本门控）→ 干净离开
    if ((outcome === 'saved' || outcome === 'unchanged') && !c.pending) {
      router.back();
      return;
    }
    // 失败/冲突/保存期间新编辑：留在页面，给出可执行下一步
    AlertDialog.show({
      title: '暂时无法离开',
      message: outcome === 'conflict' || c.state === SaveState.CONFLICT
        ? '磁盘版本已变化，请先在冲突条中选择处理方式。'
        : '保存未完成，正文与草稿检查点已保留。可重试保存，或放弃修改离开。',
      primaryButton: {
        value: '重试保存',
        action: () => {
          this.requestLeave();
        },
      },
      secondaryButton: {
        value: '放弃修改离开',
        action: () => {
          router.back();
        },
      },
      cancel: () => {
        // 留在页面继续编辑
      },
    });
  }

  /** 返回入口：DIRTY/ERROR 先经统一离开流程 */
  private goBack(): void {
    const c = this.coordinator;
    if (c !== undefined && (c.state === SaveState.DIRTY || c.state === SaveState.ERROR)) {
      AlertDialog.show({
        title: '未保存修改',
        message: '内容已由草稿检查点保留，是否在离开前保存？',
        primaryButton: {
          value: '保存并离开',
          action: () => {
            this.requestLeave();
          },
        },
        secondaryButton: {
          value: '放弃修改离开',
          action: () => {
            router.back();
          },
        },
        cancel: () => {
          // 取消：留在页面继续编辑
        },
      });
      return;
    }
    router.back();
  }

  /**
   * A1 快照契约：经 getSnapshotEx 信封读取（会话/版本/正文一次返回）。
   * 解析失败/Web 异常 → ok=false（空正文与失败可区分，原文件不被误写）。
   */
  private async getSnapshotData(): Promise<SnapshotData> {
    const raw = await this.runJsValue('window.__editorApi.getSnapshotEx();');
    try {
      const o: ESObject = JSON.parse(raw);
      const d: SnapshotData = {
        ok: o.ok === true,
        sessionId: `${o.s}`,
        version: o.v as number,
        content: `${o.c}`,
      };
      return d;
    } catch (e) {
      const fail: SnapshotData = { ok: false, sessionId: '', version: 0, content: '' };
      return fail;
    }
  }

  /** 同步执行 JS 并返回结果（返回值通道，M0-03 实测可用） */
  private runJsValue(script: string): Promise<string> {
    return this.runJsValueOn(this.controller, script);
  }

  /** 指定 Web 控制器的同步 JS 返回值通道（预览控制器复用） */
  private runJsValueOn(ctrl: webview.WebviewController, script: string): Promise<string> {
    return new Promise<string>((resolve) => {
      try {
        ctrl.runJavaScript(script, (err, result) => {
          resolve(err ? '' : (result === undefined ? '' : EditorPage.decodeReturn(result)));
        });
      } catch (e) {
        resolve('');
      }
    });
  }

  /**
   * ArkWeb runJavaScript 对字符串返回值按 JSON 编码返回（含引号与 \n 转义），
   * 需解码回原字符串。不为 '"' 开头（对象/数字/空）时原样返回。
   */
  private static decodeReturn(result: string): string {
    const trimmed = result.trim();
    if (trimmed.length === 0 || trimmed.charAt(0) !== '"') {
      return result;
    }
    try {
      const v: ESObject = JSON.parse(trimmed);
      return v as string;
    } catch (e) {
      return result;
    }
  }

  /** 快捷栏命令：读取选区/全文 → 领域变换 → 写回 */
  private async applyCommand(cmd: MarkdownCommandName): Promise<void> {
    try {
      const selRaw = await this.runJsValue('window.__editorApi.getSelectionRange();');
      const text = await this.runJsValue('window.__editorApi.getSnapshot();');
      const parsed: ESObject = JSON.parse(selRaw);
      const range: TextRange = { from: parsed.from as number, to: parsed.to as number };
      const result: TextTransformResult = MarkdownCommands.apply(text, range, cmd);
      const payload: ESObject = {
        text: result.text,
        cursorFrom: result.selection.from,
        cursorTo: result.selection.to,
      } as ESObject;
      const js = `window.__editorApi.setDocument(${JSON.stringify(payload.text)}, ${payload.cursorFrom}, ${payload.cursorTo});`;
      await this.runJsValue(js);
      this.docLength = result.text.length;
      this.markEdited();
    } catch (e) {
      this.append(`[命令] ${cmd} 失败：${JSON.stringify(e)}`);
    }
  }

  /** 撤销/重做：CM 内建历史；dispatch 触发 edit 事件 → 置脏与预览同步自动生效 */
  private async applyHistory(kind: 'undo' | 'redo'): Promise<void> {
    const len = await this.runJsValue(`window.__editorApi.${kind}();`);
    if (len.length > 0) {
      const n = Number(len);
      if (!Number.isNaN(n)) {
        this.docLength = n;
      }
    }
  }

  private async save(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    if (c.state === SaveState.CLEAN) {
      this.append('[保存] 无修改');
      return;
    }
    const outcome = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.conflictVisible = c.state === SaveState.CONFLICT;
    if (outcome === 'saved' || outcome === 'unchanged') {
      this.append(`[保存] ${outcome === 'saved' ? '完成' : '无修改'} → ${this.saveLabel}`);
    } else if (outcome === 'failed') {
      this.append('[保存] 失败，正文与草稿检查点已保留');
    } else if (outcome === 'busy') {
      this.append('[保存] 已有保存在进行中，稍后自动收敛');
    }
  }

  /** M4-03 冲突决策①：改用磁盘版本（编辑器内容放弃；草稿检查点保留本地，磁盘已读回） */
  private conflictKeepDisk(): void {
    const c = this.coordinator;
    const target = this.docTarget;
    if (c === undefined || target === undefined) {
      return;
    }
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.internal : this.external;
    src.read(target).then((r) => {
      this.expectedRevision = r.revision;
      this.pendingLoad = r.content;
      this.flushPendingLoad();
      c.decideKeepDisk();
      this.conflictVisible = false;
      this.saveLabel = SaveStateMachine.label(c.state);
      this.append('[冲突] 已加载磁盘版本');
    }).catch((e: ESObject) => {
      this.append(`[冲突] 读取磁盘版本失败：${JSON.stringify(e)}（保留本地编辑）`);
      c.decideKeepLocal();
      this.conflictVisible = false;
      this.saveLabel = SaveStateMachine.label(c.state);
    });
  }

  /** M4-03 冲突决策②：保留本地继续编辑（不再自动覆盖） */
  private conflictKeepLocal(): void {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    c.decideKeepLocal();
    this.conflictVisible = false;
    this.saveLabel = SaveStateMachine.label(c.state);
    this.append('[冲突] 保留本地内容继续编辑');
  }

  /** M4-03 冲突决策③：本地内容另存副本到资料库（智能命名自动避让重名） */
  private async conflictSaveCopy(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    const content = await this.runJsValue('window.__editorApi.getSnapshot();');
    const name = DocumentNamer.derive(content, this.internal.listLibrary());
    const copy: InternalSource = { kind: 'internal', relativePath: `library/${name}` };
    this.docTarget = copy;
    c.decideKeepLocal();
    this.conflictVisible = false;
    const outcome = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.docTitle = name;
    this.append(`[冲突] 副本保存${(outcome === 'saved') ? '完成' : '失败'} → ${copy.relativePath}`);
  }

  /** M5-02 分享：动作菜单（复制 Markdown 原文 / 复制渲染 HTML；API 26 无 ShareKit，R-18 剪贴板降级） */
  private async share(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    try {
      const that = this;
      promptAction.showActionMenu({
        title: '分享',
        buttons: [
          { text: '复制 Markdown 原文', color: that.pal.TEXT },
          { text: '复制渲染 HTML', color: that.pal.TEXT },
          { text: '导出 HTML 文件', color: that.pal.TEXT },
          { text: '另存为 Markdown…', color: that.pal.TEXT },
        ],
      }).then((r: promptAction.ActionMenuSuccessResponse) => {
        if (r.index === 0) {
          that.copyToClipboard('markdown');
        } else if (r.index === 1) {
          that.copyToClipboard('html');
        } else if (r.index === 2) {
          that.exportHtmlFile();
        } else if (r.index === 3) {
          that.saveAsMarkdown();
        }
      });
    } catch (e) {
      this.append(`[分享] 菜单失败：${JSON.stringify(e)}`);
    }
  }

  /** 剪贴板导出通道：markdown=原文；html=预览渲染结果 */
  private async copyToClipboard(kind: 'markdown' | 'html'): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    // dirty 文档导出前先落盘（SDD 9.2：确保最新内容）
    if (c.state === SaveState.DIRTY || c.state === SaveState.ERROR) {
      await c.saveNow(Date.now());
    }
    this.saveLabel = SaveStateMachine.label(c.state);
    if (c.state === SaveState.ERROR || c.state === SaveState.CONFLICT) {
      this.conflictVisible = c.state === SaveState.CONFLICT;
      this.append('[分享] 需要先解决保存状态（失败/冲突），避免分享过期内容');
      return;
    }
    let payload = '';
    if (kind === 'markdown') {
      payload = await this.runJsValue('window.__editorApi.getSnapshot();');
    } else {
      const md = await this.runJsValue('window.__editorApi.getSnapshot();');
      this.previewController.runJavaScript(`window.__previewApi.render(${JSON.stringify(md)});`);
      payload = await this.runJsValueOn(this.previewController, 'window.__previewApi.getHtml();');
    }
    try {
      const record = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, payload);
      await pasteboard.getSystemPasteboard().setData(record);
      promptAction.showToast({ message: kind === 'markdown' ? '已复制 Markdown 原文' : '已复制渲染 HTML' });
      this.append(`[分享] ${kind === 'markdown' ? 'Markdown 原文' : '渲染 HTML'}已复制（${payload.length} 字符）`);
    } catch (e) {
      const err: ESObject = e as ESObject;
      promptAction.showToast({ message: '复制失败' });
      this.append(`[分享] 复制失败：${JSON.stringify(err)}`);
    }
  }

  /**
   * 导出为独立 HTML 文件（V0.4.3）：渲染当前正文 → 自包含 HTML（内联样式）
   * → 系统保存选择器（用户选位置与文件名）→ fd 写入。
   */
  private async exportHtmlFile(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    try {
      const md = await this.runJsValue('window.__editorApi.getSnapshot();');
      this.previewController.runJavaScript(`window.__previewApi.render(${JSON.stringify(md)});`);
      const body = await this.runJsValueOn(this.previewController, 'window.__previewApi.getHtml();');
      if (body.length === 0) {
        promptAction.showToast({ message: '文档为空，无法导出' });
        return;
      }
      const html = HtmlExporter.buildStandalone(this.docTitle, body);
      const fileName = HtmlExporter.exportFileName(this.docTitle);
      const savePicker = new picker.DocumentViewPicker(this.ctx);
      const uris: Array<string> = await savePicker.save({ newFileNames: [fileName] });
      if (uris.length === 0) {
        return; // 用户取消
      }
      const file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, html);
      fs.closeSync(file.fd);
      promptAction.showToast({ message: `已导出 ${fileName}` });
      this.append(`[导出] ${fileName}（${html.length} 字符）`);
    } catch (e) {
      const err: ESObject = e as ESObject;
      promptAction.showToast({ message: '导出失败' });
      this.append(`[导出] 失败：${JSON.stringify(err)}`);
    }
  }

  /**
   * C2：插入本地图片——系统图片选择器 → 复制到应用附件目录 → 插入相对引用。
   * 取消不改变正文（C2-01）。
   */
  private async insertLocalImage(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1,
      });
      const uris: Array<string> = result.photoUris;
      if (uris.length === 0) {
        return; // 用户取消
      }
      const uri = uris[0];
      // 从 URI 提取文件名（兜底 attachment.png）
      const slash = uri.lastIndexOf('/');
      let name = slash >= 0 ? uri.substring(slash + 1) : 'attachment.png';
      if (name.length === 0 || !name.includes('.')) {
        name = 'attachment.png';
      }
      // 复制到附件目录（应用私有，不依赖外部授权持久性）
      const attPath = this.internal.copyToAttachments(uri, name);
      if (attPath.length === 0) {
        promptAction.showToast({ message: '图片复制失败' });
        return;
      }
      // 在光标处插入 Markdown 引用（相对路径，可迁移）
      const sel = await this.runJsValue('window.__editorApi.getSelectionRange();');
      let parsed: ESObject;
      try {
        parsed = JSON.parse(sel);
      } catch (e) {
        parsed = { from: 0, to: 0 };
      }
      const at = (parsed.from as number) ?? 0;
      const snippet = `![图片](${attPath})`;
      await this.runJsValue(`window.__editorApi.replaceRange(${at}, ${at}, ${JSON.stringify(snippet)});`);
      const c = this.coordinator;
      if (c !== undefined) {
        c.onEdit(Date.now());
        this.saveLabel = SaveStateMachine.label(c.state);
      }
      this.scheduleDocSync();
      promptAction.showToast({ message: `已插入 ${name}` });
    } catch (e) {
      const err: ESObject = e as ESObject;
      this.append(`[图片] 选择失败：${JSON.stringify(err)}`);
    }
  }

  /**
   * C1：另存为 Markdown——系统保存选择器选目标位置，写入当前正文快照。
   * 取消不改变标题/保存目标/最近列表/保存状态（C1-02）。
   */
  private async saveAsMarkdown(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    try {
      // 获取确定版本快照（A1 契约）
      const snap = await this.getSnapshotData();
      if (!snap.ok) {
        promptAction.showToast({ message: '获取内容失败' });
        return;
      }
      const fileName = HtmlExporter.exportFileName(this.docTitle).replace('.html', '.md');
      const savePicker = new picker.DocumentViewPicker(this.ctx);
      const uris: Array<string> = await savePicker.save({ newFileNames: [fileName] });
      if (uris.length === 0) {
        return; // 用户取消：一切不变
      }
      const file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY);
      if (snap.content.length > 0) {
        fs.writeSync(file.fd, snap.content);
      }
      fs.fsyncSync(file.fd);
      fs.closeSync(file.fd);
      promptAction.showToast({ message: `已另存 ${fileName}` });
      this.append(`[另存] ${fileName}（${snap.content.length} 字符）`);
    } catch (e) {
      const err: ESObject = e as ESObject;
      promptAction.showToast({ message: '另存失败' });
      this.append(`[另存] 失败：${JSON.stringify(err)}`);
    }
  }

  /** 快捷键与使用提示面板（V0.4.3） */
  private showHelp(): void {
    AlertDialog.show({
      title: '快捷键与提示',
      message: [
        '快捷键：',
        '· Ctrl+S 保存　Ctrl+F 查找　Ctrl+Shift+F 大纲',
        '· Ctrl+B 加粗　Ctrl+I 斜体',
        '· Ctrl+Z 撤销　Ctrl+Y 重做',
        '',
        '工具栏：',
        '· H1–H6 标题（同级再点取消，异级切换）',
        '· B/I/S/高亮/行内码 行内样式',
        '· 列表/序号/任务/引用/代码块/缩进 块级',
        '· 链接/图片/表格/分隔线 插入',
        '',
        '视图：',
        '· 编辑/预览/分屏 顶栏切换（平板与电脑支持分屏）',
        '· ☰ 侧栏　大纲面板 点击标题跳转',
        '',
        '保存：',
        '· 修改自动保存（1.5 秒防抖）',
        '· 分享菜单：复制 Markdown/HTML、导出 HTML、另存为',
        '· 意外退出可在首页「找回未保存内容」恢复',
      ].join('\\n'),
      confirm: {
        value: '知道了',
        action: () => {
        },
      },
    });
  }

  // ---- 视图构建 ----

  /** 快捷栏命令按钮（中文/短码标签，等高圆角，宽随文字） */
  @Builder
  toolBtn(label: string, cmd: MarkdownCommandName) {
    Button(label)
      .fontSize(13)
      .fontColor(this.pal.TEXT)
      .backgroundColor(this.pal.CARD)
      .borderRadius(8)
      .height(36)
      .padding({ left: 10, right: 10 })
      .onClick(() => this.applyCommand(cmd))
  }

  /** 快捷栏分组竖分隔线 */
  @Builder
  toolSep() {
    Divider()
      .vertical(true)
      .height(20)
      .color(this.pal.DIVIDER)
      .margin({ left: 5, right: 5 })
  }

  /** 历史按钮（撤销/重做） */
  @Builder
  histBtn(label: string, kind: 'undo' | 'redo') {
    Button(label)
      .fontSize(13)
      .fontColor(this.pal.TEXT)
      .backgroundColor(this.pal.CARD)
      .borderRadius(8)
      .height(36)
      .padding({ left: 10, right: 10 })
      .onClick(() => this.applyHistory(kind))
  }

  /** 顶栏小图标按钮 */
  @Builder
  topBtn(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor(active ? this.pal.ON_PRIMARY : this.pal.TEXT)
      .backgroundColor(active ? this.pal.PRIMARY : this.pal.CARD)
      .borderRadius(8)
      .width(36)
      .height(36)
      .lineHeight(36)
      .textAlign(TextAlign.Center)
      .onClick(() => action())
  }

  /** 面板小按钮 */
  @Builder
  panelBtn(label: string, action: () => void) {
    Button(label)
      .fontSize(12)
      .fontColor(this.pal.TEXT)
      .backgroundColor(this.pal.CARD)
      .borderRadius(6)
      .height(30)
      .onClick(() => action())
  }

  build() {
    Column({ space: 8 }) {
      // 顶栏：返回 | 文档名+保存状态 | （弹性） | 视图分段 | 查找/大纲/分享 | 保存（wrap 适配窄窗）
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
        Button('‹')
          .fontSize(20)
          .fontColor(this.pal.TEXT)
          .backgroundColor(Color.Transparent)
          .borderRadius(10)
          .width(38)
          .height(38)
          .onClick(() => this.goBack())
        this.topBtn('☰', this.sidebarVisible, () => this.toggleSidebar())

        Row({ space: 8 }) {
          Text(this.docTitle)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.pal.TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 220 })
            .padding({ top: 8, bottom: 8 })
            .onTouch((e: TouchEvent) => {
              // 系统标题栏已隐藏：文档标题区接管窗口拖动（startMoving 热区）
              if (e.type === TouchType.Down) {
                beginWindowMove(this.ctx);
              }
            })
          Text(this.saveLabel)
            .fontSize(11)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .fontColor(this.saveLabel === '已保存' ? this.pal.OK : (this.saveLabel === '外部冲突' || this.saveLabel === '保存失败' ? this.pal.DANGER : this.pal.AMBER))
            .backgroundColor(this.saveLabel === '已保存' ? this.pal.OK_SOFT : (this.saveLabel === '外部冲突' || this.saveLabel === '保存失败' ? this.pal.DANGER_SOFT : this.pal.AMBER_SOFT))
            .borderRadius(8)
        }
        .alignItems(VerticalAlign.Center)

        // 视图模式分段（三端核心交互；phone 无分屏档；SegBtn 保证 active/palette 动态刷新）
        Row({ space: 4 }) {
          SegBtn({ label: '编辑', active: this.viewMode === DefaultView.EDIT, pal: this.pal, action: () => this.setViewMode(DefaultView.EDIT) })
          SegBtn({ label: '预览', active: this.viewMode === DefaultView.PREVIEW, pal: this.pal, action: () => this.setViewMode(DefaultView.PREVIEW) })
          if (ViewModePolicy.allowsSplit(this.bp)) {
            SegBtn({ label: '分屏', active: this.viewMode === DefaultView.SPLIT, pal: this.pal, action: () => this.setViewMode(DefaultView.SPLIT) })
          }
        }

        Button('查找')
          .fontSize(13)
          .fontColor(this.findVisible ? this.pal.ON_PRIMARY : this.pal.TEXT)
          .backgroundColor(this.findVisible ? this.pal.PRIMARY : this.pal.CARD)
          .borderRadius(8)
          .height(36)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            if (this.findVisible) {
              this.findVisible = false;
            } else {
              this.openFind();
            }
          })
        Button('大纲')
          .fontSize(13)
          .fontColor(this.outlineVisible ? this.pal.ON_PRIMARY : this.pal.TEXT)
          .backgroundColor(this.outlineVisible ? this.pal.PRIMARY : this.pal.CARD)
          .borderRadius(8)
          .height(36)
          .padding({ left: 12, right: 12 })
          .onClick(() => this.toggleOutline())
        Button('分享')
          .fontSize(13)
          .backgroundColor(this.pal.CARD)
          .fontColor(this.pal.TEXT)
          .borderRadius(8)
          .height(36)
          .onClick(() => this.share())
        Button('帮助')
          .fontSize(13)
          .fontColor(this.pal.TEXT)
          .backgroundColor(this.pal.CARD)
          .borderRadius(8)
          .height(36)
          .padding({ left: 12, right: 12 })
          .onClick(() => this.showHelp())
        Button('保存')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.pal.ON_PRIMARY)
          .backgroundColor(this.pal.PRIMARY)
          .borderRadius(8)
          .height(36)
          .onClick(() => this.save())
      }
      .width('100%')

      // 查找替换面板（FR-EDIT-004；wrap 适配窄屏）
      if (this.findVisible) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
          TextInput({ placeholder: '查找', text: this.findQuery })
            .fontSize(13)
            .height(32)
            .padding({ left: 8, right: 8 })
            .backgroundColor(this.pal.CARD)
            .borderRadius(6)
            .constraintSize({ minWidth: 120, maxWidth: 220 })
            .onChange((v: string) => {
              this.findQuery = v;
              this.refreshFind().then(() => this.locateFirstMatch());
            })
            .onSubmit(() => this.jumpNext())
          TextInput({ placeholder: '替换为', text: this.replaceText })
            .fontSize(13)
            .height(32)
            .padding({ left: 8, right: 8 })
            .backgroundColor(this.pal.CARD)
            .borderRadius(6)
            .constraintSize({ minWidth: 120, maxWidth: 220 })
            .onChange((v: string) => {
              this.replaceText = v;
            })
          Text(this.matchCount > 0 ? `${this.matchIndex + 1}/${this.matchCount}` : '0 命中')
            .fontSize(12)
            .fontColor(this.matchCount > 0 ? this.pal.PRIMARY : this.pal.TEXT_FAINT)
            .padding({ left: 6, right: 6 })
          this.panelBtn('上一个', () => this.jumpPrev())
          this.panelBtn('下一个', () => this.jumpNext())
          this.panelBtn('替换', () => this.replaceCurrent())
          this.panelBtn('全部替换', () => this.replaceAllMatches())
          Row({ space: 4 }) {
            Text('Aa').fontSize(12)
              .fontColor(this.findCase ? this.pal.ON_PRIMARY : this.pal.TEXT)
              .backgroundColor(this.findCase ? this.pal.PRIMARY : this.pal.CARD)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.findCase = !this.findCase;
                this.refreshFind();
              })
            Text('全词').fontSize(12)
              .fontColor(this.findWord ? this.pal.ON_PRIMARY : this.pal.TEXT)
              .backgroundColor(this.findWord ? this.pal.PRIMARY : this.pal.CARD)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.findWord = !this.findWord;
                this.refreshFind();
              })
            Text('✕').fontSize(12)
              .fontColor(this.pal.TEXT_SUB)
              .backgroundColor(this.pal.CARD)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.findVisible = false;
              })
          }
        }
        .width('100%')
        .padding(6)
        .backgroundColor(this.pal.CARD)
        .borderRadius(8)
        .border({ width: 1, color: this.pal.DIVIDER })
      }

      // 冲突条（M4-03；wrap 防溢出）
      if (this.conflictVisible) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text('⚠ 磁盘版本已变化（自动保存已停止）')
            .fontSize(12)
            .fontColor(this.pal.DANGER)
          Button('用磁盘版').fontSize(12).fontColor(this.pal.TEXT).backgroundColor(this.pal.CARD).borderRadius(8).onClick(() => this.conflictKeepDisk())
          Button('保留本地').fontSize(12).fontColor(this.pal.TEXT).backgroundColor(this.pal.CARD).borderRadius(8).onClick(() => this.conflictKeepLocal())
          Button('另存副本').fontSize(12).fontColor(this.pal.TEXT).backgroundColor(this.pal.CARD).borderRadius(8).onClick(() => this.conflictSaveCopy())
        }
        .width('100%')
        .padding(6)
        .backgroundColor(this.pal.DANGER_SOFT)
        .borderRadius(8)
      }

      // 快捷栏（仅编辑/分屏可见；B3-02：单行水平滚动，不换行成按钮墙）
      if (this.viewMode !== DefaultView.PREVIEW) {
        Scroll() {
          Row({ space: 2 }) {
            // 标题等级（h1–h6 全量，Markdown 标准六级）
            this.toolBtn('H1', 'h1')
            this.toolBtn('H2', 'h2')
            this.toolBtn('H3', 'h3')
            this.toolBtn('H4', 'h4')
            this.toolBtn('H5', 'h5')
            this.toolBtn('H6', 'h6')
            this.toolSep()
            // 行内样式
            this.toolBtn('B', 'bold')
            this.toolBtn('I', 'italic')
            this.toolBtn('S', 'strike')
            this.toolBtn('</>', 'inlineCode')
            this.toolBtn('高亮', 'highlight')
            this.toolSep()
            // 块级
            this.toolBtn('列表', 'ul')
            this.toolBtn('序号', 'ol')
            this.toolBtn('任务', 'task')
            this.toolBtn('引用', 'quote')
            this.toolBtn('代码块', 'codeBlock')
            this.toolBtn('缩进', 'indent')
            this.toolBtn('减少缩进', 'outdent')
            this.toolSep()
            // 插入
            this.toolBtn('链接', 'link')
            Button('图片')
              .fontSize(13)
              .fontColor(this.pal.TEXT)
              .backgroundColor(this.pal.CARD)
              .borderRadius(8)
              .height(36)
              .padding({ left: 10, right: 10 })
              .onClick(() => this.insertLocalImage())
            this.toolBtn('表格', 'table')
            this.toolBtn('分隔线', 'hr')
            this.toolSep()
            this.histBtn('撤销', 'undo')
            this.histBtn('重做', 'redo')
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .width('100%')
        .height(44)
      }

      // A2 恢复面板：外部文档读取失败/授权失效（不呈现可正常保存的空白文档）
      if (this.loadState === 'loadFailed' || this.loadState === 'accessExpired') {
        Column({ space: 12 }) {
          Text(this.loadState === 'accessExpired' ? '无法访问文件' : '文件读取失败')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.pal.TEXT)
          Text(this.loadState === 'accessExpired'
            ? '外部文件的访问授权已失效（重启或授权过期）。可重新选择文件，或将内容另存到资料库。'
            : '文件可能已被移动、删除或暂时不可读。可将编辑器中的内容另存到资料库，或返回后再试。')
            .fontSize(13)
            .fontColor(this.pal.TEXT_SUB)
            .lineHeight(20)
          Row({ space: 12 }) {
            if (this.docTarget !== undefined && this.docTarget.kind === 'external') {
              Button('重新选择文件')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.pal.ON_PRIMARY)
                .backgroundColor(this.pal.PRIMARY)
                .borderRadius(20)
                .height(40)
                .padding({ left: 16, right: 16 })
                .onClick(() => this.reselectExternalFile())
            }
            Button('另存到资料库')
              .fontSize(14)
              .fontColor(this.pal.TEXT)
              .backgroundColor(this.pal.CARD)
              .borderRadius(20)
              .height(40)
              .padding({ left: 16, right: 16 })
              .onClick(() => this.saveLocalCopyFromFailed())
            Button('返回')
              .fontSize(14)
              .fontColor(this.pal.TEXT_SUB)
              .backgroundColor(Color.Transparent)
              .borderRadius(20)
              .height(40)
              .padding({ left: 16, right: 16 })
              .onClick(() => router.back())
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(28)
      } else {
      // 工作区：大纲（可选）+ 编辑器 + 预览（三端同一布局路径——
      // phone：单栏互斥切换；tablet/pc 分屏：双 Web 并排；隐藏侧 Visibility.None 不占位）
      Row({ space: 0 }) {
        // B1/B2：文档侧栏（编辑页内切换文档，phone 档可折叠）
        if (this.sidebarVisible) {
          DocumentSidebar({
            recent: $sidebarRecent,
            libraryFiles: $sidebarLibrary,
            pal: this.pal,
            onDocSelected: (docId: string): void => {
              this.switchToDocument(docId);
            },
          })
          Divider().vertical(true).height('100%').color(this.pal.DIVIDER)
        }

        // 大纲侧栏（FR-PREVIEW-003 总装：点击跳转标题行）
        if (this.outlineVisible) {
          Column() {
            Text('大纲')
              .fontSize(12)
              .fontColor(this.pal.TEXT_SUB)
              .padding({ left: 8, top: 8, bottom: 4 })
              .width('100%')
            if (this.outlineEntries.length === 0) {
              Text('暂无标题（用 H1–H3 或输入 # 添加）')
                .fontSize(12)
                .fontColor(this.pal.TEXT_FAINT)
                .padding(8)
            }
            List() {
              ForEach(this.outlineEntries, (e: OutlineEntry) => {
                ListItem() {
                  Text(e.text)
                    .fontSize(13)
                    .fontColor(e.level === 1 ? this.pal.TEXT : this.pal.TEXT_SUB)
                    .fontWeight(e.level === 1 ? FontWeight.Medium : FontWeight.Normal)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 8 + (e.level - 1) * 12, top: 6, bottom: 6, right: 8 })
                    .width('100%')
                    .onClick(() => this.jumpToOutlineEntry(e))
                }
              }, (e: OutlineEntry) => `${e.from}-${e.text}`)
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Auto)
          }
          .width(200)
          .height('100%')
          .backgroundColor(this.pal.SIDEBAR)
          .clip(true)
        }

        if (this.outlineVisible) {
          Divider().vertical(true).height('100%').color(this.pal.DIVIDER)
        }

        Column() {
          Web({ src: $rawfile('web/editor.html'), controller: this.controller })
            .javaScriptAccess(true)
            .javaScriptProxy({
              object: { send: editorBridgeSend },
              name: '__nativeBridge',
              methodList: ['send'],
              controller: this.controller,
            })
            .onPageEnd(() => {
              this.webReady = true;
              // 补发样式：aboutToAppear 时 Web 可能未就绪，样式命令会被吞掉
              this.applyEditorStyle();
              if (this.pendingLoad.length > 0 || this.docTarget !== undefined) {
                this.flushPendingLoad();
              }
              this.append('编辑器就绪');
            })
            .onErrorReceive((event) => {
              this.append(`页面错误：${JSON.stringify(event.request)}`);
            })
            .layoutWeight(1)
            .width('100%')
        }
        .visibility(this.viewMode === DefaultView.PREVIEW ? Visibility.None : Visibility.Visible)
        .layoutWeight(1)
        .width('100%')
        .clip(true)

        if (this.viewMode === DefaultView.SPLIT) {
          Divider()
            .vertical(true)
            .height('92%')
            .color(this.pal.DIVIDER)
        }

        Column() {
          Web({ src: $rawfile('web/preview.html'), controller: this.previewController })
            .javaScriptAccess(true)
            .onPageEnd(() => {
              this.previewReady = true;
              this.applyPreviewStyle();
              this.syncDocNow();
              this.append('预览就绪');
            })
            .onErrorReceive((event) => {
              this.append(`预览页面错误：${JSON.stringify(event.request)}`);
            })
            .layoutWeight(1)
            .width('100%')
        }
        .visibility(this.viewMode === DefaultView.EDIT ? Visibility.None : Visibility.Visible)
        .layoutWeight(1)
        .width('100%')
        .clip(true)
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Center)
      }

      // 状态栏（V0.4.2：字数 + 光标行列，备忘录式底部信息条）
      Row() {
        Text(`${this.docLength} 字`)
          .fontSize(11)
          .fontColor(this.pal.TEXT_FAINT)
        Text(`行 ${this.cursorLine}，列 ${this.cursorCol}`)
          .fontSize(11)
          .fontColor(this.pal.TEXT_FAINT)
          .padding({ left: 12 })
        Blank()
        if (this.outlineEntries.length > 0) {
          Text(`${this.outlineEntries.length} 个标题`)
            .fontSize(11)
            .fontColor(this.pal.TEXT_FAINT)
        }
      }
      .width('100%')
      .height(26)
      .padding({ left: 4, right: 4 })
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(this.pal.CONTENT)
    .onAreaChange((_old: Area, newArea: Area) => {
      // B2-05/B4：实际 vp 尺寸驱动空间决策（不以设备类型或整块屏幕分辨率决定）
      this.contentWidthVp = newArea.width as number;
      // B4-01：空间不足时自动降级分屏 → 编辑（偏好不覆盖，空间恢复后可重新切换）
      if (this.viewMode === DefaultView.SPLIT &&
        !ViewModePolicy.splitFits(this.contentWidthVp, this.sidebarVisible, this.outlineVisible)) {
        this.viewMode = DefaultView.EDIT;
      }
    })
  }
}
