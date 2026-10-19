import { ControlStyle, ControlMetrics } from '../common/ControlStyle';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { picker } from '@kit.CoreFileKit';
import { SaveState, SaveStateMachine } from '../domain/recovery/SaveStateMachine';
import { MarkdownCommands, MarkdownCommandName, TextRange, TextTransformResult } from '../domain/editor/MarkdownCommands';
import { FindReplaceEngine, FindOptions, FindMatch } from '../domain/editor/FindReplaceEngine';
import { FindSession } from '../domain/editor/FindSession';
import { ViewModePolicy } from '../domain/editor/ViewModePolicy';
import { HeadingOutline } from '../domain/editor/HeadingOutline';
import { EditorBridge } from '../services/EditorBridge';
import { DocumentDeliveryService } from '../services/DocumentDeliveryService';
import { DocumentImportService } from '../services/DocumentImportService';
import { DocumentIntake } from '../domain/document/DocumentIntake';
import { SaveCoordinator, SaveCoordinatorDeps, SnapshotData } from '../services/SaveCoordinator';
import { DocumentFileAdapter, DocumentSource, InternalSource, ExternalSource, FileRevisionContract, WriteDocumentResult, WriteFailResult, DocumentWriteFormat } from '../domain/document/DocumentFileAdapter';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { ExternalUriFileSource } from '../infrastructure/file/ExternalUriFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { RecentFileList } from '../domain/document/RecentFileList';
import { DocumentNamer } from '../domain/document/DocumentNamer';
import { HashUtil } from '../domain/document/HashUtil';
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
  private readonly cleanupImpl: () => Promise<void>;
  private readonly persistImpl: (c: string) => Promise<WriteDocumentResult>;

  constructor(
    snapshotImpl: () => Promise<SnapshotData>,
    checkpointImpl: (c: string) => Promise<void>,
    persistImpl: (c: string) => Promise<WriteDocumentResult>,
    cleanupImpl: () => Promise<void>,
  ) {
    this.snapshotImpl = snapshotImpl;
    this.checkpointImpl = checkpointImpl;
    this.persistImpl = persistImpl;
    this.cleanupImpl = cleanupImpl;
  }

  clearCheckpoint(): Promise<void> { return this.cleanupImpl(); }

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
  @State recoveryLabel: string = '';
  @State deliveryBusy: boolean = false;
  @State dropBusy: boolean = false;
  @State fileHover: boolean = false;
  @State fileMenuVisible: boolean = false;
  @State fileSheetVisible: boolean = false;
  @StorageLink('titleControlsBottom') titleControlsBottom: number = 0;
  @StorageLink('titleControlsWidth') titleControlsWidth: number = 0;
  @State fileSheetSection: string = 'root';
  private afterFileSheet: (() => void) | undefined = undefined;
  @State activeToolMenu: string = '';
  private openPromptVisible: boolean = false;
  @StorageLink('checkpointRequest') @Watch('onCheckpointRequest') checkpointRequest: number = 0;
  @StorageLink('pendingOpenUri') @Watch('onExternalOpen') pendingOpenUri: string = '';
  private activeSession: string = '';
  private pageActive: boolean = true;
  private loadGeneration: number = 0;
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
  @State loadFailure: string = '';
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
  private retiredDraftId: string = '';
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

  private onCheckpointRequest(): void {
    if (this.pageActive) { this.protectDraft(); }
  }

  private async protectDraft(): Promise<boolean> {
    const c = this.coordinator;
    if (!this.pageActive || !this.webReady || this.loadState !== 'ready' || c === undefined) { return false; }
    const ok = await c.checkpointNow();
    if (!this.pageActive || c !== this.coordinator) { return false; }
    this.recoveryLabel = ok ? (c.state === SaveState.CLEAN ? '' : '恢复草稿已保留') : '恢复草稿写入失败，请立即保存或导出';
    if (!ok) { this.append('[草稿] 检查点失败，保留编辑器正文'); }
    return ok;
  }

  private async onExternalOpen(): Promise<void> {
    if (this.deliveryBusy) { return; }
    if (!this.pageActive || this.openPromptVisible || this.pendingOpenUri.length === 0) { return; }
    const uri = this.pendingOpenUri;
    if (this.loadState !== 'ready' && this.docLength === 0) {
      this.pendingOpenUri = '';
      this.openReceivedDocument(uri);
      return;
    }
    this.openPromptVisible = true;
    if (!await this.protectDraft() || !this.pageActive) { this.openPromptVisible = false; return; }
    if (this.coordinator?.state === SaveState.CLEAN) {
      this.openPromptVisible = false;
      if (this.pendingOpenUri !== uri) { this.onExternalOpen(); return; }
      this.pendingOpenUri = '';
      this.openReceivedDocument(uri);
      return;
    }
    AlertDialog.show({
      title: '打开收到的文档',
      message: '先保留当前文档的恢复草稿，再打开收到的文件。',
      primaryButton: { value: '保留草稿并打开', action: () => {
        this.protectDraft().then((ok: boolean) => {
          this.openPromptVisible = false;
          if (!ok || this.pendingOpenUri !== uri) { this.onExternalOpen(); return; }
          this.pendingOpenUri = '';
          this.openReceivedDocument(uri);
        });
      } },
      secondaryButton: { value: '取消', action: () => { this.openPromptVisible = false; this.pendingOpenUri = ''; } },
      cancel: () => { this.openPromptVisible = false; this.pendingOpenUri = ''; },
    });
  }

  private openReceivedDocument(id: string): void {
    router.replaceUrl({ url: 'pages/EditorPage', params: DocumentIntake.route(id) });
  }

  private async receiveDrop(event: DragEvent): Promise<void> {
    this.fileHover = false;
    if (this.dropBusy || this.deliveryBusy) { promptAction.showToast({ message: '文件操作进行中，请稍后再拖入' }); return; }
    this.dropBusy = true;
    this.append('[拖入] 开始异步取数');
    try {
      const uri = await new DocumentImportService(this.ctx,
        (key: string) => this.getUIContext().getDragController().cancelDataLoading(key)).receive(event);
      if (!this.pageActive) { return; }
      this.append('[拖入] 已取得单文档授权');
      promptAction.showToast({ message: '已导入“我的文档”，编辑的是副本' });
      this.pendingOpenUri = uri;
    } catch (e) {
      this.append('[拖入] 未完成，当前正文保留');
      if (this.pageActive) { promptAction.showToast({ message: String(e).replace(/^Error: /, '') }); }
    } finally { this.dropBusy = false; }
  }

  onBackPress(): boolean {
    if (this.fileSheetVisible) {
      if (this.fileSheetSection !== 'root') { this.fileSheetSection = 'root'; }
      else { this.fileSheetVisible = false; }
      return true;
    }
    this.goBack();
    return true;
  }

  private append(line: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', line);
  }

  aboutToAppear(): void {
    this.bpListeners = watchBreakpoints((bp: Breakpoint) => {
      this.bp = bp;
      // 断点变化归一化：phone 档无分屏（ViewModePolicy）
      this.viewMode = ViewModePolicy.normalize(this.viewMode, bp);
      if (bp === 'phone') { this.fileMenuVisible = false; this.outlineVisible = false; }
      else { this.fileSheetVisible = false; }
    });
    // 编排器延迟创建：deps 闭包依赖组件方法（字段初始化器内不能引用 this）
    this.coordinator = new SaveCoordinator(new EditorPageDeps(
      () => this.getSnapshotData(),
      (content: string) => this.doSaveCheckpoint(content),
      (content: string) => this.doPersist(content),
      () => this.clearSavedDrafts(),
    ));
    bridgeSink = (raw: string): void => {
      const env = this.bridge.parseEvent(raw);
      if (env === undefined) {
        return;
      }
      if (env.type === 'edit') {
        if (env.payload.s !== this.activeSession) { return; }
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
      if (env.type === 'editorScroll') {
        // D1：编辑器滚动 → 预览同步（分屏时；防回环：仅编辑器侧触发）
        if (this.viewMode === DefaultView.SPLIT && this.previewReady) {
          const line = env.payload.line as number | undefined;
          if (line !== undefined) {
            this.runJsValue('window.__editorApi.getSnapshot();').then((md: string) => {
              const js = `window.__previewApi.scrollToLine(${line}, ${JSON.stringify(md)});`;
              this.previewController.runJavaScript(js);
            });
          }
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
      if (drained.some((raw: string): boolean => raw.includes('"edit"'))) {
        this.protectDraft();
      }
    }, 500);
    // 自动保存检查（M4-01：防抖由 SaveScheduler 负责，轮询只触发到期保存；
    // autoSave 设置关闭时跳过自动保存，手动保存仍可用——M5-03）
    this.saveTimer = setInterval(() => {
      const c = this.coordinator;
      if (c === undefined || this.deliveryBusy || !this.appSettings.autoSave) {
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
    if (this.deliveryBusy || !await this.protectDraft()) { return; }
    const current = this.docTarget;
    if (current !== undefined && (current.kind === 'internal' ? current.relativePath : current.uri) === docId) { return; }
    const c = this.coordinator;
    if (c !== undefined && c.state !== SaveState.CLEAN) {
      const outcome = await c.saveNow(Date.now());
      this.saveLabel = SaveStateMachine.label(c.state);
      if (!((outcome === 'saved' || outcome === 'unchanged') && SaveStateMachine.label(c.state) === '已保存' && !c.pending)) {
        promptAction.showToast({ message: '请先保存当前文档，或保留草稿返回首页再打开' }); return;
      }
    }
    const source: DocumentSource = docId.startsWith('library/')
      ? { kind: 'internal', relativePath: docId }
      : { kind: 'external', uri: docId, displayName: RecentFileList.displayName(docId) };
    this.docTarget = source;
    this.docTitle = RecentFileList.displayName(docId);
    this.docFormat = { encoding: 'utf-8', lineEnding: 'lf' };
    this.docValidUtf8 = true;
    this.loadOpenedDoc(source);
    this.refreshSidebarData();
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.loadGeneration++;
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
    const generation = ++this.loadGeneration;
    this.loadState = 'loading';
    this.saveLabel = '正在打开';
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.internal : this.external;
    src.read(target).then((r) => {
      if (!this.pageActive || generation !== this.loadGeneration) { return; }
      this.expectedRevision = r.revision;
      this.pendingLoad = r.content;
      this.pendingLoadAt = t0;
      this.docFormat = { encoding: r.encoding, lineEnding: r.lineEnding };
      this.docValidUtf8 = r.validUtf8;
      this.loadState = 'ready';
      this.trackRecent(target).then(() => this.refreshSidebarData());
      if (this.webReady) {
        this.flushPendingLoad();
      }
    }).catch((e: ESObject) => {
      if (!this.pageActive || generation !== this.loadGeneration) { return; }
      // A2-04：权限失效（重启后临时授权丢失/文件被移动删除）与普通读取失败分流通
      const msg = String(e);
      this.loadFailure = e.message === undefined ? msg : String(e.message);
      this.loadState = e.code === 13900001 || e.code === 13900002 || /13900001|13900002|permission|not permitted/i.test(msg)
        ? 'accessExpired' : 'loadFailed';
      this.saveLabel = '未打开';
      this.append(`[打开] 失败（${this.loadState}）`);
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
    this.activeSession = `s-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const session = this.activeSession;
    const js = `window.__editorApi.loadDocument(${JSON.stringify(md)}, ${JSON.stringify(session)});`;
    this.runJsValue(js).then(() => {
      if (session !== this.activeSession || !this.pageActive) { return; }
      this.coordinator = new SaveCoordinator(new EditorPageDeps(
        () => this.getSnapshotData(), (content: string) => this.doSaveCheckpoint(content),
        (content: string) => this.doPersist(content), () => this.clearSavedDrafts()));
      this.saveLabel = '已保存';
      this.recoveryLabel = '';
      this.lastPreviewedMd = '\u0000';
      this.docLength = md.length;
      const dt = t0 > 0 ? Date.now() - t0 : -1;
      this.append(`[打开] 文档 ${md.length} 字符（打开至可编辑 ${dt}ms）`);
      const c0 = this.coordinator;
      if (c0 !== undefined) {
        c0.onDocumentLoaded(session);
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
        this.renderPreview(md, this.activeSession);
      }
      if (needOutline) {
        this.rebuildOutline(md);
      }
    });
  }

  /** 与交付共用解析器及路径门控，支持空格、引用式图片，拒绝私有目录穿越。 */
  private async renderPreview(md: string, session: string): Promise<void> {
    try {
      const images = await this.inspectImages(md);
      const service = new DocumentDeliveryService(this.ctx);
      const resources: Record<string, string> = {};
      let total = 0;
      let incomplete = false;
      for (const source of images) {
        try {
          const item = service.resources([source]);
          for (const key of Object.keys(item)) {
            total += item[key].length;
            if (total > 28 * 1024 * 1024) { throw new Error('preview image limit'); }
            resources[key] = item[key];
          }
        } catch (e) { incomplete = true; }
      }
      if (!this.pageActive || session !== this.activeSession || md !== this.lastPreviewedMd) { return; }
      if (incomplete) { this.append('[预览] 部分图片无法读取或超过限额，正文及附件未修改'); }
      await this.runJsChecked(this.previewController,
        `window.__previewApi.render(${JSON.stringify(md)}, ${JSON.stringify(resources)});`);
    } catch (e) { this.append('[预览] 渲染失败，请重新切换预览视图'); }
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
    if (this.bp === 'phone') {
      this.outlineVisible = false;
      if (this.fileSheetVisible && this.fileSheetSection === 'outline') { this.fileSheetVisible = false; }
      else { this.openPhoneOutline(); }
      return;
    }
    this.outlineVisible = !this.outlineVisible;
    if (this.outlineVisible) {
      this.syncDocNow();
    }
  }

  private async openPhoneOutline(): Promise<void> {
    const session = this.activeSession;
    const md = await this.runJsValue('window.__editorApi.getSnapshot();');
    if (!this.pageActive || session !== this.activeSession || this.bp !== 'phone') { return; }
    this.rebuildOutline(md);
    this.fileSheetSection = 'outline';
    this.fileSheetVisible = true;
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
    if (this.deliveryBusy) { return; }
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
    if (this.deliveryBusy) { return; }
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
        const w = await this.internal.write(renamed, content, { size: 0, contentHash: '' }, this.docFormat);
        if (w.ok) {
          this.retiredDraftId = this.draftIdOf(target);
          this.internal.remove(target);
          this.docTarget = renamed;
          this.docTitle = better;
          this.expectedRevision = w.revision;
          // 原名草稿保留供恢复页按内容核对。


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
      // 恢复页按实际磁盘内容清理冗余，不能在旧版本提交时删除新草稿。
      // A3：正式目标确立后清理会话草稿（迁移完成）

      this.trackRecent(target);
    }
    return result;
  }

  private clearSavedDrafts(): Promise<void> {
    if (this.retiredDraftId.length > 0) { this.drafts.remove(this.retiredDraftId); this.retiredDraftId = ''; }
    this.recoveryLabel = '';
    if (this.docTarget !== undefined) { this.drafts.remove(this.draftIdOf(this.docTarget)); }
    this.drafts.remove(this.sessionDraftId);
    return Promise.resolve();
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
    if ((outcome === 'saved' || outcome === 'unchanged') && SaveStateMachine.label(c.state) === '已保存' && !c.pending) {
      router.back();
      return;
    }
    // 失败/冲突/保存期间新编辑：留在页面，给出可执行下一步
    AlertDialog.show({
      title: '暂时无法离开',
      message: outcome === 'conflict' || c.state === SaveState.CONFLICT
        ? '磁盘版本已变化，请先在冲突条中选择处理方式。'
        : '保存未完成，请重试或导出副本；退出前请确认恢复草稿状态。',
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
  private async goBack(): Promise<void> {
    if (this.deliveryBusy) { promptAction.showToast({ message: '请先完成或取消文件操作' }); return; }
    if (this.loadState === 'ready' && this.webReady && !await this.protectDraft()) {
      promptAction.showToast({ message: '恢复草稿未确认写入，请保存或导出后离开' }); return;
    }
    const c = this.coordinator;
    if (c !== undefined && c.state !== SaveState.CLEAN) {
      AlertDialog.show({
        title: '未保存修改',
        message: '仍有未保存内容。保存成功后离开，或保留恢复草稿后离开。',
        primaryButton: {
          value: '保存并离开',
          action: () => {
            this.requestLeave();
          },
        },
        secondaryButton: {
          value: '保留草稿离开',
          action: () => { this.protectDraft().then((ok: boolean) => { if (ok) { router.back(); } }); },
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
    try {
      const raw = await this.runJsChecked(this.controller, 'window.__editorApi.getSnapshotEx();');
      const o: ESObject = JSON.parse(raw);
      const d: SnapshotData = {
        ok: o.ok === true && typeof o.c === 'string' && typeof o.v === 'number' && o.s === this.activeSession,
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

  private runJsChecked(ctrl: webview.WebviewController, script: string): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('编辑器响应超时')), 5000);
      try {
        ctrl.runJavaScript(script, (err, result) => {
          clearTimeout(timer);
          if (err || result === undefined) { reject(new Error('编辑器读取失败')); }
          else { resolve(EditorPage.decodeReturn(result)); }
        });
      } catch (e) { clearTimeout(timer); reject(new Error('编辑器暂不可用')); }
    });
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
    if (this.deliveryBusy) { return; }
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
    if (this.deliveryBusy) { return; }
    const len = await this.runJsValue(`window.__editorApi.${kind}();`);
    if (len.length > 0) {
      const n = Number(len);
      if (!Number.isNaN(n)) {
        this.docLength = n;
      }
    }
  }

  private async save(): Promise<void> {
    if (this.deliveryBusy) { return; }
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    if (!await this.protectDraft()) {
      promptAction.showToast({ message: '无法确认正文快照，请重试或导出' }); return;
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
    if (this.deliveryBusy) { return; }
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
    if (this.deliveryBusy) { return; }
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    c.decideKeepLocal();
    this.conflictVisible = false;
    this.saveLabel = SaveStateMachine.label(c.state);
    this.append('[冲突] 保留本地内容继续编辑');
  }

  /** 冲突副本复用可靠另存链，不能提前清冲突或改目标。 */
  private conflictSaveCopy(): void {
    this.deliverDocument(0);
  }

  private async openDocument(): Promise<void> {
    if (this.deliveryBusy || this.dropBusy) { return; }
    try {
      const uris = await new picker.DocumentViewPicker(this.ctx).select({
        maxSelectNumber: 1, fileSuffixFilters: ['.md', '.markdown', '.txt'],
      });
      if (this.pageActive && uris.length > 0) { this.pendingOpenUri = uris[0]; }
    } catch (e) { this.append('[打开] 选择器未完成'); promptAction.showToast({ message: '打开失败，请重试' }); }
  }

  private async newDocument(): Promise<void> {
    if (this.deliveryBusy || !await this.protectDraft()) { return; }
    if (this.coordinator?.state === SaveState.CLEAN) {
      router.replaceUrl({ url: 'pages/EditorPage' }); return;
    }
    AlertDialog.show({ title: '新建文档', message: '当前修改已保留为恢复草稿。新建后可从首页“找回未保存内容”继续。',
      primaryButton: { value: '保留草稿并新建', action: () => {
        this.protectDraft().then((ok: boolean) => { if (ok) { router.replaceUrl({ url: 'pages/EditorPage' }); } });
      } }, secondaryButton: { value: '取消', action: () => {} } });
  }

  @Builder
  fileMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: '新建文档' }).onClick(() => this.newDocument())
        MenuItem({ content: '打开文档…' }).onClick(() => this.openDocument())
        MenuItem({ content: '另存为…' }).onClick(() => this.deliverDocument(0))
      }
      MenuItemGroup() {
        MenuItem({ content: '导出副本', builder: this.exportMenu })
        MenuItem({ content: '复制内容', builder: this.copyMenu })
        MenuItem({ content: '查看保存位置' }).onClick(() => this.showLocation())
      }
    }.width(264)
  }

  @Builder
  exportMenu() {
    Menu() {
      MenuItem({ content: '图文包 ZIP', labelInfo: '正文和图片' }).onClick(() => this.deliverDocument(2))
      MenuItem({ content: '网页 HTML', labelInfo: '内嵌图片' }).onClick(() => this.deliverDocument(3))
      MenuItem({ content: 'Markdown', labelInfo: '仅正文' }).onClick(() => this.deliverDocument(1))
    }
  }

  private documentLocation(): string {
    const target = this.docTarget;
    return target === undefined ? '尚未保存到文件' : target.kind === 'internal'
      ? '我的文档 · 应用内' : RecentFileList.location(target.uri);
  }

  private dismissFileSheet(action: () => void): void {
    this.afterFileSheet = action;
    this.fileSheetVisible = false;
  }

  private fileSheetClosed(): void {
    this.fileSheetVisible = false;
    const action = this.afterFileSheet;
    this.afterFileSheet = undefined;
    if (this.pageActive && action !== undefined) { action(); }
  }

  @Builder
  fileActionRow(label: string, detail: string, next: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(label).fontSize(ControlMetrics.FONT).fontColor(this.pal.TEXT).maxLines(1)
          if (detail.length > 0) {
            Text(detail).fontSize(12).fontColor(this.pal.TEXT_SUB).maxLines(2)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (next) { SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([this.pal.TEXT_SUB]) }
      }.width('100%')
    }
    .width('100%').constraintSize({ minHeight: 56 }).padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(Color.Transparent).borderRadius(ControlMetrics.RADIUS).hoverEffect(HoverEffect.Highlight)
    .accessibilityText(`${label}，${detail}`).onClick(action)
  }

  @Builder
  fileSheet() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.fileSheetSection !== 'root') {
          Button('返回', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.pal, 'quiet')).onClick(() => { this.fileSheetSection = 'root'; })
        }
        Text(this.fileSheetSection === 'root' ? '文档操作' : this.fileSheetSection === 'export' ? '导出副本' : this.fileSheetSection === 'outline' ? '文档大纲' : '复制内容')
          .fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.pal.TEXT).layoutWeight(1)
        Button('关闭', { type: ButtonType.Normal })
          .attributeModifier(new ControlStyle(this.pal, 'quiet')).onClick(() => { this.fileSheetVisible = false; })
      }.width('100%')
      Column({ space: 4 }) {
        Text(this.docTitle).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.pal.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.documentLocation()} · ${this.saveLabel}`).fontSize(12).fontColor(this.pal.TEXT_SUB).maxLines(2)
      }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 12, right: 12, bottom: 8 })
      Divider().color(this.pal.DIVIDER)
      Scroll() {
        Column({ space: 2 }) {
          if (this.fileSheetSection === 'root') {
            this.fileActionRow('新建文档', '', false, () => this.dismissFileSheet(() => this.newDocument()))
            this.fileActionRow('打开文档', '选择要继续编辑的原文件', false, () => this.dismissFileSheet(() => this.openDocument()))
            this.fileActionRow('另存为', '保存后继续编辑新文件', false, () => this.dismissFileSheet(() => this.deliverDocument(0)))
            Divider().color(this.pal.DIVIDER).margin({ top: 4, bottom: 4 })
            this.fileActionRow('导出副本', '选择格式，保留当前保存位置', true, () => { this.fileSheetSection = 'export'; })
            this.fileActionRow('复制内容', '', true, () => { this.fileSheetSection = 'copy'; })
            this.fileActionRow('保存位置', this.documentLocation(), false, () => this.dismissFileSheet(() => this.showLocation()))
            this.fileActionRow('快捷键与帮助', '', false, () => this.dismissFileSheet(() => this.showHelp()))
          } else if (this.fileSheetSection === 'export') {
            this.fileActionRow('图文包 ZIP', 'Markdown 正文和引用的本地图片', false, () => this.dismissFileSheet(() => this.deliverDocument(2)))
            this.fileActionRow('网页 HTML', '在浏览器查看，本地图片嵌入文件', false, () => this.dismissFileSheet(() => this.deliverDocument(3)))
            this.fileActionRow('Markdown', '仅保存正文，不包含图片附件', false, () => this.dismissFileSheet(() => this.deliverDocument(1)))
          } else if (this.fileSheetSection === 'outline') {
            if (this.outlineEntries.length === 0) {
              Text('添加 Markdown 标题后，可在这里快速跳转。').fontSize(14).fontColor(this.pal.TEXT_SUB).padding(12)
            }
            ForEach(this.outlineEntries, (entry: OutlineEntry) => {
              this.fileActionRow(`${'#'.repeat(entry.level)} ${entry.text}`, '', false,
                () => this.dismissFileSheet(() => this.jumpToOutlineEntry(entry)))
            })
          } else {
            this.fileActionRow('Markdown 原文', '', false, () => this.dismissFileSheet(() => this.deliverDocument(4)))
            this.fileActionRow('渲染 HTML', '', false, () => this.dismissFileSheet(() => this.deliverDocument(7)))
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding({ left: 16, right: 16, bottom: 24 })
      .backgroundColor(this.pal.CONTENT)
  }

  @Builder
  fileEntry() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 7 }) {
        SymbolGlyph(this.bp === 'phone' ? $r('sys.symbol.ellipsis_circle') : $r('sys.symbol.folder'))
          .fontSize(this.bp === 'phone' ? 22 : 18).fontColor([this.pal.TEXT])
        if (this.bp !== 'phone') {
          Text('文档').fontSize(14).fontColor(this.pal.TEXT)
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(11).fontColor([this.pal.TEXT_SUB])
        }
      }
    }
      .attributeModifier(new ControlStyle(this.pal,
      this.fileMenuVisible || this.fileSheetVisible ? 'selected' : 'quiet', this.bp === 'phone'))
    .accessibilityText('文档操作').id('document-actions')
    .enabled(!this.deliveryBusy && !this.dropBusy)
    .onClick(() => {
      if (this.bp === 'phone') { this.fileSheetSection = 'root'; this.fileSheetVisible = true; }
      else { this.fileMenuVisible = true; }
    })
    .bindMenu(this.bp !== 'phone' && this.fileMenuVisible, this.fileMenu, {
      showInSubWindow: false, onDisappear: () => { this.fileMenuVisible = false; },
    })
    .bindSheet(this.bp === 'phone' && this.fileSheetVisible, this.fileSheet, {
      height: '75%', preferType: SheetType.BOTTOM, showClose: false, dragBar: true,
      backgroundColor: this.pal.CONTENT, onDisappear: () => this.fileSheetClosed(),
    })
  }

  @Builder
  phoneHeader() {
    if (this.titleControlsBottom > 0) {
      Blank().height(this.titleControlsBottom).width('100%')
        .onTouch((e: TouchEvent) => { if (e.type === TouchType.Down) { beginWindowMove(this.ctx); } })
    }
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.pal.TEXT])
      }.attributeModifier(new ControlStyle(this.pal, 'quiet', true))
        .accessibilityText('返回首页').onClick(() => this.goBack())
      Column({ space: 2 }) {
        Text(this.docTitle).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.pal.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.saveLabel).fontSize(12).fontColor(this.saveStatusColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button('保存', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.pal, 'primary')).onClick(() => this.save())
      this.fileEntry()
    }.width('100%')
    Row({ space: 6 }) {
      SegBtn({ label: '编辑', active: this.viewMode === DefaultView.EDIT, pal: this.pal, action: () => this.setViewMode(DefaultView.EDIT) })
      SegBtn({ label: '预览', active: this.viewMode === DefaultView.PREVIEW, pal: this.pal, action: () => this.setViewMode(DefaultView.PREVIEW) })
      Blank()
      Button('大纲', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.pal, 'quiet'))
        .onClick(() => { this.toggleOutline(); })
      Button('查找', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.pal, 'quiet'))
        .onClick(() => { this.openFind(); })
    }.width('100%')
  }

  @Builder
  copyMenu() {
    Menu() {
      MenuItem({ content: 'Markdown 原文' }).onClick(() => this.deliverDocument(4))
      MenuItem({ content: '渲染 HTML' }).onClick(() => this.deliverDocument(7))
    }
  }

  private saveStatusColor(): string {
    return this.saveLabel === '已保存' ? this.pal.TEXT_SUB
      : this.saveLabel === '外部冲突' || this.saveLabel === '保存失败' ? this.pal.DANGER : this.pal.AMBER;
  }

  @Builder
  wideHeader() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(20).fontColor([this.pal.TEXT])
      }.attributeModifier(new ControlStyle(this.pal, 'quiet', true))
        .accessibilityText('返回首页').onClick(() => this.goBack())
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal')).fontSize(20).fontColor([this.pal.TEXT])
      }.attributeModifier(new ControlStyle(this.pal, this.sidebarVisible ? 'selected' : 'quiet', true))
        .accessibilityText('文档侧栏').onClick(() => this.toggleSidebar())
      Column({ space: 2 }) {
        Text(this.docTitle).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.pal.TEXT)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        Text(this.saveLabel).fontSize(12).fontColor(this.saveStatusColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ left: 8 })
        .onTouch((e: TouchEvent) => { if (e.type === TouchType.Down) { beginWindowMove(this.ctx); } })
      this.fileEntry()
      Button('保存', { type: ButtonType.Normal })
        .attributeModifier(new ControlStyle(this.pal, 'primary')).onClick(() => this.save())
    }.width('100%').height(ControlMetrics.HEIGHT)
      .padding({ right: this.titleControlsWidth > 0 ? this.titleControlsWidth + 8 : 0 })
  }

  @Builder
  viewControls() {
    SegBtn({ label: '编辑', active: this.viewMode === DefaultView.EDIT, pal: this.pal, action: () => this.setViewMode(DefaultView.EDIT) })
    SegBtn({ label: '预览', active: this.viewMode === DefaultView.PREVIEW, pal: this.pal, action: () => this.setViewMode(DefaultView.PREVIEW) })
    SegBtn({ label: '分屏', active: this.viewMode === DefaultView.SPLIT, pal: this.pal, action: () => this.setViewMode(DefaultView.SPLIT) })
  }

  @Builder
  navigationTools() {
    Button('查找', { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.pal, this.findVisible ? 'selected' : 'quiet'))
      .onClick(() => { if (this.findVisible) { this.findVisible = false; } else { this.openFind(); } })
    Button('大纲', { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.pal, this.outlineVisible ? 'selected' : 'quiet'))
      .onClick(() => this.toggleOutline())
    Button('帮助', { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.pal)).onClick(() => this.showHelp())
  }

  @Builder
  commandItem(label: string, cmd: MarkdownCommandName) {
    MenuItem({ content: label }).onClick(() => this.applyCommand(cmd))
  }

  @Builder
  commandMenu(kind: string) {
    Menu() {
      if (kind === '标题') {
        this.commandItem('一级标题 H1', 'h1')
        this.commandItem('二级标题 H2', 'h2')
        this.commandItem('三级标题 H3', 'h3')
        this.commandItem('四级标题 H4', 'h4')
        this.commandItem('五级标题 H5', 'h5')
        this.commandItem('六级标题 H6', 'h6')
      } else if (kind === '格式') {
        this.commandItem('加粗  Ctrl+B', 'bold')
        this.commandItem('斜体  Ctrl+I', 'italic')
        this.commandItem('删除线', 'strike')
        this.commandItem('行内代码', 'inlineCode')
        this.commandItem('高亮', 'highlight')
      } else if (kind === '段落') {
        MenuItemGroup({ header: '列表' }) {
          this.commandItem('无序列表', 'ul')
          this.commandItem('有序列表', 'ol')
          this.commandItem('任务列表', 'task')
        }
        MenuItemGroup({ header: '块与缩进' }) {
          this.commandItem('引用', 'quote')
          this.commandItem('代码块', 'codeBlock')
          this.commandItem('增加缩进', 'indent')
          this.commandItem('减少缩进', 'outdent')
        }
      } else {
        this.commandItem('链接', 'link')
        MenuItem({ content: '本地图片…' }).onClick(() => this.insertLocalImage())
        this.commandItem('表格', 'table')
        this.commandItem('分隔线', 'hr')
      }
    }.width(220)
  }

  @Builder
  toolGroup(label: string) {
    Button(label, { type: ButtonType.Normal })
      .enabled(!this.deliveryBusy)
      .attributeModifier(new ControlStyle(this.pal, this.activeToolMenu === label ? 'selected' : 'quiet'))
      .onClick(() => { this.activeToolMenu = label; })
      .bindMenu(this.activeToolMenu === label, this.activeCommandMenu, {
        showInSubWindow: false, onDisappear: () => { this.activeToolMenu = ''; },
      })
  }

  @Builder
  activeCommandMenu() { this.commandMenu(this.activeToolMenu) }

  private showLocation(): void {
    const source = this.docTarget;
    AlertDialog.show({ title: '当前保存位置', message: source === undefined
      ? '尚未保存到文件；恢复草稿仅在本机应用内保留。'
      : source.kind === 'internal'
        ? `我的文档 / ${source.relativePath.substring('library/'.length)}\n应用私有目录，卸载前请导出文档和附件。`
        : `外部原文件（临时访问授权）\n${source.uri}\n重启后可能需要重新选择文件。`,
      confirm: { value: '知道了', action: () => {} } });
  }

  private async inspectImages(content: string): Promise<string[]> {
    const raw = await this.runJsChecked(this.controller,
      `window.__editorApi.inspectMarkdown(${JSON.stringify(content)});`);
    const parsed: ESObject = JSON.parse(raw);
    return parsed.images as string[];
  }

  private async renderForDelivery(content: string, resources: Record<string, string>): Promise<string> {
    return this.runJsChecked(this.controller,
      `window.__editorApi.renderMarkdown(${JSON.stringify(content)}, ${JSON.stringify(resources)});`);
  }

  private async deliverDocument(action: number): Promise<void> {
    const c = this.coordinator;
    if (this.deliveryBusy || c === undefined || this.loadState !== 'ready') { return; }
    if (c.state === SaveState.SAVING) {
      promptAction.showToast({ message: '正在保存，请完成后再导出或另存' }); return;
    }
    this.deliveryBusy = true;
    const session = this.activeSession;
    try {
      // 阻止选择器期间改写正文；取消后恢复编辑和原保存目标。
      await this.runJsChecked(this.controller, 'window.__editorApi.setEditable(false);');
      const snap = await this.getSnapshotData();
      if (!snap.ok || session !== snap.sessionId) { throw new Error('获取正文失败，请重试'); }
      if (!await c.checkpointNow()) { throw new Error('恢复草稿写入失败，请先检查可用空间'); }
      const service = new DocumentDeliveryService(this.ctx);
      const images = await this.inspectImages(snap.content);
      if ((action === 0 || action === 1) && images.length > 0) {
        // 单文件 Markdown 不能携带附件；用户显式选定后才输出正文副本。
        const accepted = await new Promise<boolean>((resolve) => {
          AlertDialog.show({ title: 'Markdown 文件不包含图片附件',
            message: '此操作仅保存 Markdown 正文。要把图片一起带走，请取消并选择“导出图文 ZIP”。',
            primaryButton: { value: '仅保存正文', action: () => resolve(true) },
            secondaryButton: { value: '取消', action: () => resolve(false) }, cancel: () => resolve(false) });
        });
        if (!accepted) { return; }
      }
      if (action === 4 || action === 7) {
        const payload = action === 4 ? snap.content : await this.renderForDelivery(snap.content, service.resources(images));
        await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, payload));
        promptAction.showToast({ message: action === 4 ? '已复制 Markdown 原文' : '已复制渲染 HTML' });
        return;
      }
      const result = action === 0 || action === 1
        ? await service.markdown(this.docTitle, snap.content)
        : action === 2 ? await service.zip(this.docTitle, snap.content, images)
          : await service.html(this.docTitle, snap.content, images,
            (text: string, resources: Record<string, string>) => this.renderForDelivery(text, resources));
      if (result === undefined) { return; }
      if (!this.pageActive || session !== this.activeSession) { return; }
      if (action === 0) {
        // 成功后才切换目标；后续 Ctrl+S 和自动保存都写入此文件。
        const previousDraftId = this.docTarget === undefined ? this.sessionDraftId : this.draftIdOf(this.docTarget);
        const source: ExternalSource = { kind: 'external', uri: result.uri, displayName: result.fileName };
        this.docTarget = source;
        this.docTitle = result.fileName;
        this.expectedRevision = { size: util.TextEncoder.create('utf-8').encodeInto(snap.content).byteLength,
          contentHash: HashUtil.of(snap.content) };
        this.docFormat = { encoding: 'utf-8', lineEnding: 'lf' };
        this.docValidUtf8 = true;
        this.coordinator = new SaveCoordinator(new EditorPageDeps(() => this.getSnapshotData(),
          (text: string) => this.doSaveCheckpoint(text), (text: string) => this.doPersist(text), () => this.clearSavedDrafts()));
        this.coordinator.onDocumentLoaded(session, snap.version);
        this.drafts.remove(previousDraftId);
        this.drafts.remove(this.sessionDraftId);
        this.recoveryLabel = '';
        this.saveLabel = '已保存';
        this.conflictVisible = false;
        await this.trackRecent(source);
        this.refreshSidebarData();
      }
      this.append(`[交付] ${action === 0 ? '保存目标已切换' : '副本导出完成'}`);
      promptAction.showToast({ message: `${action === 0 ? '已另存，后续保存使用新文件' : '已导出'}${result.remoteImages ? '；网络图片仍需联网查看' : ''}` });
    } catch (e) {
      this.append('[交付] 操作失败，原会话及草稿保留');
      AlertDialog.show({ title: '文件操作未完成', message: String(e), confirm: { value: '返回编辑', action: () => {} } });
    } finally {
      this.deliveryBusy = false;
      if (this.pendingOpenUri.length > 0) { this.onExternalOpen(); }
      if (this.pageActive && session === this.activeSession) {
        this.runJsChecked(this.controller, 'window.__editorApi.setEditable(true);').catch(() => {
          this.append('[交付] 恢复编辑失败，请保留草稿后重新打开');
        });
      }
    }
  }

  /**
   * C2：插入本地图片——系统图片选择器 → 复制到应用附件目录 → 插入相对引用。
   * 取消不改变正文（C2-01）。
   */
  private async insertLocalImage(): Promise<void> {
    if (this.deliveryBusy) { return; }
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
      const snippet = `![图片](<${attPath}>)`;
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

  /** 快捷键与使用提示面板（V0.4.3） */
  private showHelp(): void {
    AlertDialog.show({
      title: '木笺 MuMark · 快捷键与提示',
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
        '· 文档侧栏　大纲面板点击标题跳转',
        '',
        '保存：',
        '· 修改自动保存（1.5 秒防抖）',
        '· 文档菜单：另存为、导出副本、图文 ZIP、HTML、复制',
        '· 意外退出可在首页「找回未保存内容」恢复',
      ].join('\n'),
      confirm: {
        value: '知道了',
        action: () => {
        },
      },
    });
  }

  // ---- 视图构建 ----

  /** 命令组之间的轻量分隔。 */
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
    Button(label, { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.pal, 'quiet'))
      .onClick(() => this.applyHistory(kind))
  }

  /** 查找面板的同宽操作。 */
  @Builder
  panelBtn(label: string, action: () => void) {
    Button(label, { type: ButtonType.Normal })
      .attributeModifier(new ControlStyle(this.pal, 'quiet'))
      .width(96)
      .onClick(() => action())
  }

  build() {
    Column({ space: 8 }) {
      if (this.bp === 'phone') {
        this.phoneHeader()
      } else {
        this.wideHeader()
      }

      if (this.findVisible) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
          TextInput({ placeholder: '查找', text: this.findQuery })
            .fontSize(13)
            .height(ControlMetrics.HEIGHT)
            .padding({ left: 8, right: 8 })
            .backgroundColor(this.pal.CARD)
            .borderRadius(ControlMetrics.RADIUS)
            .constraintSize({ minWidth: 120, maxWidth: 220 })
            .onChange((v: string) => {
              this.findQuery = v;
              this.refreshFind().then(() => this.locateFirstMatch());
            })
            .onSubmit(() => this.jumpNext())
          TextInput({ placeholder: '替换为', text: this.replaceText })
            .fontSize(13)
            .height(ControlMetrics.HEIGHT)
            .padding({ left: 8, right: 8 })
            .backgroundColor(this.pal.CARD)
            .borderRadius(ControlMetrics.RADIUS)
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
            Button('Aa', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.pal, this.findCase ? 'selected' : 'quiet'))
              .onClick(() => {
                this.findCase = !this.findCase;
                this.refreshFind();
              })
            Button('全词', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.pal, this.findWord ? 'selected' : 'quiet'))
              .onClick(() => {
                this.findWord = !this.findWord;
                this.refreshFind();
              })
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([this.pal.TEXT])
            }
              .attributeModifier(new ControlStyle(this.pal, 'quiet', true)).accessibilityText('关闭')
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
          Button('用磁盘版', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.pal, 'quiet')).onClick(() => this.conflictKeepDisk())
          Button('保留本地', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.pal, 'quiet')).onClick(() => this.conflictKeepLocal())
          Button('另存副本', { type: ButtonType.Normal })
            .attributeModifier(new ControlStyle(this.pal, 'quiet')).onClick(() => this.conflictSaveCopy())
        }
        .width('100%')
        .padding(6)
        .backgroundColor(this.pal.DANGER_SOFT)
        .borderRadius(8)
      }

      // 预览只保留视图与导航；窄窗命令单行滚动。
      if (this.viewMode !== DefaultView.PREVIEW || this.bp !== 'phone') {
        Scroll() {
          Row({ space: 4 }) {
            if (this.bp !== 'phone') {
              this.viewControls()
              this.toolSep()
            }
            if (this.viewMode !== DefaultView.PREVIEW) {
            this.toolGroup('标题')
            this.toolGroup('格式')
            this.toolGroup('段落')
            this.toolGroup('插入')
            this.toolSep()
            this.histBtn('撤销', 'undo')
            this.histBtn('重做', 'redo')
            }
            if (this.bp !== 'phone') {
              this.toolSep()
              this.navigationTools()
            }
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .align(Alignment.Start)
        .scrollBar(BarState.Auto)
        .width('100%')
        .height(ControlMetrics.HEIGHT)
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
          Text(this.loadFailure).fontSize(12).fontColor(this.pal.DANGER).maxLines(3)
          Row({ space: 12 }) {
            if (this.docTarget !== undefined && this.docTarget.kind === 'external') {
              Button('重新选择文件', { type: ButtonType.Normal })
                .attributeModifier(new ControlStyle(this.pal, 'primary'))
                .onClick(() => this.reselectExternalFile())
            }
            Button('查看恢复草稿', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.pal, 'quiet'))
              .onClick(() => router.pushUrl({ url: 'pages/RecoveryPage' }))
            Button('返回', { type: ButtonType.Normal })
              .attributeModifier(new ControlStyle(this.pal, 'quiet'))
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
      Stack() {
      Row({ space: 0 }) {
        // B1/B2：文档侧栏（编辑页内切换文档，phone 档可折叠）
        if (this.sidebarVisible && this.bp !== 'phone') {
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
        if (this.outlineVisible && this.bp !== 'phone') {
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
            .enableDrag(false)
            .onDragEnter(() => { this.fileHover = true; })
            .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
              return !request.getRequestUrl().endsWith('/web/editor.html');
            })
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
              if (this.loadState === 'ready') {
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
            .enableDrag(false)
            .onDragEnter(() => { this.fileHover = true; })
            .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
              return !request.getRequestUrl().endsWith('/web/preview.html');
            })
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
      if (this.fileHover) {
        Column({ space: 10 }) {
          Text('松开以导入文档').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.pal.PRIMARY)
          Text('Markdown / txt · 副本保存在“我的文档”').fontSize(14).fontColor(this.pal.TEXT_SUB)
        }
        .justifyContent(FlexAlign.Center)
        .width('100%').height('100%').backgroundColor(this.pal.PRIMARY_SOFT)
        .onDrop((event: DragEvent) => { this.receiveDrop(event); }, { disableDataPrefetch: true })
        .onDragLeave(() => { this.fileHover = false; })
      }
      }
      .layoutWeight(1).width('100%')
      }

      // 状态栏（V0.4.2：字数 + 光标行列，备忘录式底部信息条）
      Row() {
        if (this.dropBusy) { Text('正在读取拖入文件…').fontSize(11).fontColor(this.pal.PRIMARY) }
        Text(this.recoveryLabel).fontSize(11).fontColor(this.pal.TEXT_SUB).maxLines(1)
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
    .onDragEnter(() => { this.fileHover = true; })
    .onDragLeave(() => { this.fileHover = false; })
    .onDrop((event: DragEvent) => { this.receiveDrop(event); }, { disableDataPrefetch: true })
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
