import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, mediaquery } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { SaveState, SaveStateMachine } from '../domain/recovery/SaveStateMachine';
import { MarkdownCommands, MarkdownCommandName, TextRange, TextTransformResult } from '../domain/editor/MarkdownCommands';
import { FindReplaceEngine, FindOptions, FindMatch } from '../domain/editor/FindReplaceEngine';
import { FindSession } from '../domain/editor/FindSession';
import { ViewModePolicy } from '../domain/editor/ViewModePolicy';
import { EditorBridge } from '../services/EditorBridge';
import { SaveCoordinator, SaveCoordinatorDeps } from '../services/SaveCoordinator';
import { DocumentFileAdapter, DocumentSource, InternalSource, ExternalSource, FileRevisionContract, WriteDocumentResult } from '../domain/document/DocumentFileAdapter';
import { InternalFileSource } from '../infrastructure/file/InternalFileSource';
import { ExternalUriFileSource } from '../infrastructure/file/ExternalUriFileSource';
import { DraftStore } from '../infrastructure/metadata/DraftStore';
import { MetadataStore } from '../infrastructure/metadata/MetadataStore';
import { RecentFileList } from '../domain/document/RecentFileList';
import { SettingsStore } from '../infrastructure/metadata/SettingsStore';
import { AppTheme } from '../common/AppTheme';
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

/**
 * SaveCoordinator 依赖适配（ArkTS：接口方法成员不能由对象字面量属性函数满足，
 * 以显式 class 注入组件闭包）。
 */
class EditorPageDeps implements SaveCoordinatorDeps {
  private readonly snapshotImpl: () => Promise<string>;
  private readonly checkpointImpl: (c: string) => Promise<void>;
  private readonly persistImpl: (c: string) => Promise<WriteDocumentResult>;

  constructor(
    snapshotImpl: () => Promise<string>,
    checkpointImpl: (c: string) => Promise<void>,
    persistImpl: (c: string) => Promise<WriteDocumentResult>,
  ) {
    this.snapshotImpl = snapshotImpl;
    this.checkpointImpl = checkpointImpl;
    this.persistImpl = persistImpl;
  }

  getSnapshot(): Promise<string> {
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
  @State bp: Breakpoint = 'phone';
  private bpListeners: mediaquery.MediaQueryListener[] = [];
  private coordinator: SaveCoordinator | undefined = undefined;
  private docTarget: DocumentSource | undefined = undefined;
  private expectedRevision: FileRevisionContract = { size: 0, contentHash: '' };
  private pendingLoad: string = '';
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
      () => this.runJsValue('window.__editorApi.getSnapshot();'),
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
        const c = this.coordinator;
        if (c !== undefined) {
          c.onEdit(Date.now());
          this.saveLabel = SaveStateMachine.label(c.state);
        }
        this.schedulePreviewSync();
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
  }

  /** M5-03：读取持久化设置并应用（主题/字号/换行/行号即时生效；defaultView 决定入口视图） */
  private applyAppSettings(): void {
    this.settings.load().then((s: AppSettings) => {
      this.appSettings = s;
      this.viewMode = ViewModePolicy.resolveInitial(this.bp, s.defaultView);
      const dark = s.theme === ThemeMode.DARK;
      this.runJsValue(`window.__editorApi.setTheme(${dark});`);
      this.runJsValue(`window.__editorApi.setFontSize(${s.fontSize});`);
      this.runJsValue(`window.__editorApi.setWrap(${s.wrap});`);
      this.runJsValue(`window.__editorApi.setLineNumbers(${s.lineNumbers});`);
      this.applyPreviewStyle();
      this.append(`[设置] 主题=${s.theme} 字号=${s.fontSize} 换行=${s.wrap} 行号=${s.lineNumbers} 自动保存=${s.autoSave} 入口视图=${this.viewMode}`);
    }).catch((e: ESObject) => {
      this.append(`[设置] 读取失败：${JSON.stringify(e)}`);
    });
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
      this.docTitle = uri;
      this.loadOpenedDoc(src);
    }
  }

  /** 打开已有文档：读内容（Web 就绪后注入），基线 revision 用于冲突检测；
   * t0 记录请求时刻用于 M6-02 打开性能样本。 */
  private loadOpenedDoc(target: DocumentSource): void {
    const t0 = Date.now();
    const src: DocumentFileAdapter = target.kind === 'internal' ? this.internal : this.external;
    src.read(target).then((r) => {
      this.expectedRevision = r.revision;
      this.pendingLoad = r.content;
      this.pendingLoadAt = t0;
      this.trackRecent(target);
      if (this.webReady) {
        this.flushPendingLoad();
      }
    }).catch((e: ESObject) => {
      this.append(`[打开] 失败：${JSON.stringify(e)}`);
    });
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
      this.syncPreviewNow();
    });
  }

  // ---- 预览同步（编辑 → 预览，防抖 + 内容去重）----

  private schedulePreviewSync(): void {
    if (this.viewMode === DefaultView.EDIT) {
      return;
    }
    if (this.previewTimer >= 0) {
      clearTimeout(this.previewTimer);
    }
    this.previewTimer = setTimeout(() => {
      this.previewTimer = -1;
      this.syncPreviewNow();
    }, PREVIEW_SYNC_DEBOUNCE_MS);
  }

  private syncPreviewNow(): void {
    if (!this.previewReady || this.viewMode === DefaultView.EDIT) {
      return;
    }
    this.runJsValue('window.__editorApi.getSnapshot();').then((md: string) => {
      if (md === this.lastPreviewedMd) {
        return;
      }
      this.lastPreviewedMd = md;
      const js = `window.__previewApi.render(${JSON.stringify(md)});`;
      this.previewController.runJavaScript(js, (err) => {
        if (err) {
          this.append(`[预览] 渲染失败：${JSON.stringify(err)}`);
        }
      });
    });
  }

  /** 视图切换：进入预览/分屏立即同步一次（不等防抖） */
  private setViewMode(mode: DefaultView): void {
    if (mode === this.viewMode) {
      return;
    }
    if (mode === DefaultView.SPLIT && !ViewModePolicy.allowsSplit(this.bp)) {
      return;
    }
    this.viewMode = mode;
    if (mode !== DefaultView.EDIT) {
      this.syncPreviewNow();
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
    this.schedulePreviewSync();
  }

  // ---- 保存 / 冲突 / 分享 ----

  /** 草稿检查点（FR-SAVE-003） */
  private doSaveCheckpoint(content: string): Promise<void> {
    const target = this.docTarget;
    if (target === undefined) {
      return Promise.resolve();
    }
    this.drafts.save(
      this.draftIdOf(target),
      this.fingerprintOf(target),
      this.expectedRevision.size,
      this.expectedRevision.contentHash,
      content,
    );
    return Promise.resolve();
  }

  /** 持久化：内部原子写 / 外部 URI 写；新建文档首次保存自动命名到资料库 */
  private async doPersist(content: string): Promise<WriteDocumentResult> {
    let target = this.docTarget;
    if (target === undefined) {
      const stamp = `${Date.now()}`;
      const src: InternalSource = { kind: 'internal', relativePath: `library/未命名-${stamp}.md` };
      target = src;
      this.docTarget = src;
      this.docTitle = `未命名-${stamp}.md`;
      this.append(`[保存] 新建文档 → 资料库/未命名-${stamp}.md`);
    }
    const result = target.kind === 'internal'
      ? await this.internal.write(target, content, this.expectedRevision)
      : await this.external.write(target, content, this.expectedRevision);
    if (result.ok) {
      this.expectedRevision = result.revision;
      this.drafts.remove(this.draftIdOf(target));
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

  /** 返回前未保存保护（M2-03）：草稿检查点已保留内容 */
  private goBack(): void {
    const c = this.coordinator;
    if (c !== undefined && (c.state === SaveState.DIRTY || c.state === SaveState.ERROR)) {
      AlertDialog.show({
        title: '未保存修改',
        message: '内容已由草稿检查点保留，是否在离开前保存？',
        primaryButton: {
          value: '保存并离开',
          action: () => {
            this.save().then(() => {
              router.back();
            });
          },
        },
        secondaryButton: {
          value: '放弃',
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

  /** 同步执行 JS 并返回结果（返回值通道，M0-03 实测可用） */
  private runJsValue(script: string): Promise<string> {
    return new Promise<string>((resolve) => {
      try {
        this.controller.runJavaScript(script, (err, result) => {
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
    const ran = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.conflictVisible = c.state === SaveState.CONFLICT;
    this.append(`[保存] ${ran ? '完成' : '未执行'} → ${this.saveLabel}`);
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

  /** M4-03 冲突决策③：本地内容另存副本到资料库 */
  private async conflictSaveCopy(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    const stamp = `${Date.now()}`;
    const copy: InternalSource = { kind: 'internal', relativePath: `library/未命名-${stamp}.md` };
    this.docTarget = copy;
    c.decideKeepLocal();
    this.conflictVisible = false;
    const ran = await c.saveNow(Date.now());
    this.saveLabel = SaveStateMachine.label(c.state);
    this.append(`[冲突] 副本保存${ran && c.state !== SaveState.ERROR ? '完成' : '失败'} → ${copy.relativePath}`);
  }

  /** M5-02 分享：原始 Markdown → 剪贴板（API 26 Beta SDK 无 ShareKit，R-18 降级通道） */
  private async share(): Promise<void> {
    const c = this.coordinator;
    if (c === undefined) {
      return;
    }
    // dirty 文档分享前先落盘（SDD 9.2：确保最新内容已保存）
    let saveOk: boolean = true;
    if (c.state === SaveState.DIRTY || c.state === SaveState.ERROR) {
      saveOk = await c.saveNow(Date.now());
    }
    this.saveLabel = SaveStateMachine.label(c.state);
    if (c.state === SaveState.CONFLICT) {
      this.conflictVisible = true;
    }
    if (!saveOk || c.state === SaveState.ERROR || c.state === SaveState.CONFLICT) {
      this.append('[分享] 需要先解决保存状态（失败/冲突），避免分享过期内容');
      return;
    }
    const text = await this.runJsValue('window.__editorApi.getSnapshot();');
    try {
      const record = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(record);
      this.append(`[分享] Markdown 原文已复制（${text.length} 字符），请粘贴到目标应用`);
    } catch (e) {
      const err: ESObject = e as ESObject;
      this.append(`[分享] 复制失败：${JSON.stringify(err)}`);
    }
  }

  // ---- 视图构建 ----

  /** 快捷栏统一按钮样式（图标化，浅底圆角） */
  @Builder
  toolBtn(label: string, cmd: MarkdownCommandName) {
    Button(label)
      .fontSize(15)
      .fontColor(AppTheme.TEXT)
      .backgroundColor(AppTheme.TOOLBAR_BG)
      .borderRadius(8)
      .width(46)
      .height(38)
      .onClick(() => this.applyCommand(cmd))
  }

  /** 视图模式分段按钮 */
  @Builder
  viewTab(label: string, mode: DefaultView) {
    Text(label)
      .fontSize(13)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .fontColor(this.viewMode === mode ? AppTheme.ON_PRIMARY : AppTheme.TEXT)
      .backgroundColor(this.viewMode === mode ? AppTheme.PRIMARY : AppTheme.TOOLBAR_BG)
      .borderRadius(8)
      .onClick(() => this.setViewMode(mode))
  }

  /** 面板小按钮 */
  @Builder
  panelBtn(label: string, action: () => void) {
    Button(label)
      .fontSize(12)
      .fontColor(AppTheme.TEXT)
      .backgroundColor(AppTheme.TOOLBAR_BG)
      .borderRadius(6)
      .height(30)
      .onClick(() => action())
  }

  build() {
    Column({ space: 8 }) {
      // 标题栏（wrap 保证窄窗/自由窗口下按钮不被挤出）
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center }) {
        Button('‹')
          .fontSize(22)
          .fontColor(AppTheme.TEXT)
          .backgroundColor(AppTheme.TOOLBAR_BG)
          .borderRadius(10)
          .width(40)
          .height(40)
          .onClick(() => this.goBack())
        Text(this.docTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT)
          .constraintSize({ maxWidth: 200 })
        Text(this.saveLabel)
          .fontSize(12)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .fontColor(this.saveLabel === '已保存' ? AppTheme.OK : (this.saveLabel === '外部冲突' || this.saveLabel === '保存失败' ? AppTheme.DANGER : AppTheme.AMBER))
          .backgroundColor(this.saveLabel === '已保存' ? AppTheme.OK_SOFT : (this.saveLabel === '外部冲突' || this.saveLabel === '保存失败' ? AppTheme.DANGER_SOFT : AppTheme.AMBER_SOFT))
          .borderRadius(8)

        // 视图模式分段（三端核心交互；phone 无分屏档）
        Row({ space: 4 }) {
          this.viewTab('编辑', DefaultView.EDIT)
          this.viewTab('预览', DefaultView.PREVIEW)
          if (ViewModePolicy.allowsSplit(this.bp)) {
            this.viewTab('分屏', DefaultView.SPLIT)
          }
        }

        Button('🔍')
          .fontSize(15)
          .fontColor(AppTheme.TEXT)
          .backgroundColor(AppTheme.TOOLBAR_BG)
          .borderRadius(8)
          .width(40)
          .height(40)
          .onClick(() => {
            if (this.findVisible) {
              this.findVisible = false;
            } else {
              this.openFind();
            }
          })
        Button('分享')
          .fontSize(13)
          .backgroundColor(AppTheme.TOOLBAR_BG)
          .fontColor(AppTheme.TEXT)
          .borderRadius(8)
          .onClick(() => this.share())
        Button('保存')
          .fontSize(13)
          .fontColor(AppTheme.ON_PRIMARY)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(8)
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
            .backgroundColor(AppTheme.CARD)
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
            .backgroundColor(AppTheme.CARD)
            .borderRadius(6)
            .constraintSize({ minWidth: 120, maxWidth: 220 })
            .onChange((v: string) => {
              this.replaceText = v;
            })
          Text(this.matchCount > 0 ? `${this.matchIndex + 1}/${this.matchCount}` : '0 命中')
            .fontSize(12)
            .fontColor(this.matchCount > 0 ? AppTheme.PRIMARY : AppTheme.TEXT_FAINT)
            .padding({ left: 6, right: 6 })
          this.panelBtn('上一个', () => this.jumpPrev())
          this.panelBtn('下一个', () => this.jumpNext())
          this.panelBtn('替换', () => this.replaceCurrent())
          this.panelBtn('全部替换', () => this.replaceAllMatches())
          Row({ space: 4 }) {
            Text('Aa').fontSize(12)
              .fontColor(this.findCase ? AppTheme.ON_PRIMARY : AppTheme.TEXT)
              .backgroundColor(this.findCase ? AppTheme.PRIMARY : AppTheme.TOOLBAR_BG)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.findCase = !this.findCase;
                this.refreshFind();
              })
            Text('全词').fontSize(12)
              .fontColor(this.findWord ? AppTheme.ON_PRIMARY : AppTheme.TEXT)
              .backgroundColor(this.findWord ? AppTheme.PRIMARY : AppTheme.TOOLBAR_BG)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.findWord = !this.findWord;
                this.refreshFind();
              })
            Text('✕').fontSize(12)
              .fontColor(AppTheme.TEXT_SUB)
              .backgroundColor(AppTheme.TOOLBAR_BG)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => {
                this.findVisible = false;
              })
          }
        }
        .width('100%')
        .padding(6)
        .backgroundColor(AppTheme.CARD)
        .borderRadius(8)
        .border({ width: 1, color: AppTheme.DIVIDER })
      }

      // 冲突条（M4-03；wrap 防溢出）
      if (this.conflictVisible) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text('⚠ 磁盘版本已变化（自动保存已停止）')
            .fontSize(12)
            .fontColor(AppTheme.DANGER)
          Button('用磁盘版').fontSize(12).fontColor(AppTheme.TEXT).backgroundColor(AppTheme.TOOLBAR_BG).borderRadius(8).onClick(() => this.conflictKeepDisk())
          Button('保留本地').fontSize(12).fontColor(AppTheme.TEXT).backgroundColor(AppTheme.TOOLBAR_BG).borderRadius(8).onClick(() => this.conflictKeepLocal())
          Button('另存副本').fontSize(12).fontColor(AppTheme.TEXT).backgroundColor(AppTheme.TOOLBAR_BG).borderRadius(8).onClick(() => this.conflictSaveCopy())
        }
        .width('100%')
        .padding(6)
        .backgroundColor(AppTheme.DANGER_SOFT)
        .borderRadius(8)
      }

      // 快捷栏（仅编辑/分屏可见；FR-EDIT-002 命令子集；wrap 防溢出）
      if (this.viewMode !== DefaultView.PREVIEW) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          this.toolBtn('B', 'bold')
          this.toolBtn('I', 'italic')
          this.toolBtn('S̶', 'strike')
          this.toolBtn('`', 'inlineCode')
          this.toolBtn('🔗', 'link')
          this.toolBtn('•', 'ul')
          this.toolBtn('1.', 'ol')
          this.toolBtn('☑', 'task')
          this.toolBtn('❝', 'quote')
          this.toolBtn('{}', 'codeBlock')
          Button('⤺')
            .fontSize(15)
            .fontColor(AppTheme.TEXT)
            .backgroundColor(AppTheme.TOOLBAR_BG)
            .borderRadius(8)
            .width(46)
            .height(38)
            .onClick(() => this.applyHistory('undo'))
          Button('⤿')
            .fontSize(15)
            .fontColor(AppTheme.TEXT)
            .backgroundColor(AppTheme.TOOLBAR_BG)
            .borderRadius(8)
            .width(46)
            .height(38)
            .onClick(() => this.applyHistory('redo'))
          Button('✎ 示例')
            .fontSize(13)
            .fontColor(AppTheme.TEXT)
            .backgroundColor(AppTheme.TOOLBAR_BG)
            .borderRadius(8)
            .height(38)
            .onClick(() => {
              const md = '# 正式编辑器\n\n**M2** 快捷栏命令测试：\n\n- 列表 A\n\n> 引用\n';
              const js = `window.__editorApi.setDocument(${JSON.stringify(md)}, 0, 0);`;
              this.runJsValue(js).then(() => {
                this.docLength = md.length;
                this.markEdited();
              });
            })
        }
        .width('100%')
      }

      // 工作区：编辑器 + 预览（三端同一布局路径——
      // phone：单栏互斥切换；tablet/pc 分屏：双 Web 并排；隐藏侧 Visibility.None 不占位）
      Row({ space: 8 }) {
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
        .backgroundColor(AppTheme.CARD)
        .borderRadius(12)
        .border({ width: 1, color: AppTheme.DIVIDER })
        .clip(true)

        if (this.viewMode === DefaultView.SPLIT) {
          Divider()
            .vertical(true)
            .height('92%')
            .color(AppTheme.DIVIDER)
        }

        Column() {
          Web({ src: $rawfile('web/preview.html'), controller: this.previewController })
            .javaScriptAccess(true)
            .onPageEnd(() => {
              this.previewReady = true;
              this.applyPreviewStyle();
              this.syncPreviewNow();
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
        .backgroundColor(AppTheme.CARD)
        .borderRadius(12)
        .border({ width: 1, color: AppTheme.DIVIDER })
        .clip(true)
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .padding(12)
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG)
    .alignSelf(ItemAlign.Center)
    .constraintSize({ maxWidth: this.bp === 'pc' ? 1440 : 10000 })
  }
}
